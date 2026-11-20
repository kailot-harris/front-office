#!/usr/bin/env node
/**
 * Static veracity guard for R pipeline builders and exporters (front-office#108).
 *
 * Scans recursive `build_*.R` and `export_*.R` scripts under this repo's four
 * read-only sport subtree mirrors (`mlb/`, `nba/`, `nfl/`, `wnba/`, skipping
 * `node_modules`, `.git`, `renv`, and `archive`) for four classes of synthetic
 * data fabrication idioms:
 *   1. `unreviewed_rng`: RNG calls (`runif(`, `rnorm(`, `sample(`, etc.) outside
 *      reviewed allow-list entries (which must also carry `set.seed(` in-file).
 *   2. `player_name_override`: Player-name literal conditional overrides
 *      (`grepl("<Player Name>"`, `str_detect(..., "<Player Name>")`, or
 *      `player_name == "<Player Name>"`).
 *   3. `affine_clamp_formula`: `clamp(` calls or nested `pmin`/`pmax` clamps
 *      combining arithmetic/weights (excluding pure epsilon log-loss clips and
 *      nonparametric `percent_rank(` scalers).
 *   4. `hardcoded_metric_vector`: Hard-coded `tribble(` tables or numeric
 *      vector literals `c(num, num, num, ...)` (outside `%in% c(...)` filters).
 *
 * R `#` comments are stripped in-place (preserving line numbers and `#` inside
 * quoted strings) so explanatory comments never false-trigger.
 *
 * Never writes inside `mlb/`, `nba/`, `nfl/`, or `wnba/` — those are managed
 * exclusively via subtree syncs.
 *
 * Usage:
 *   node tools/check_fabrication_idioms.mjs [--root <dir>] [--allowlist <path>]
 *
 * Environment overrides (used by tests):
 *   FABRICATION_GUARD_ROOT       Root directory containing sport subtrees
 *   FABRICATION_GUARD_ALLOWLIST  Path to JSON allow-list file
 *
 * Exit codes:
 *   0 = clean (all hits covered by reviewed allow-list entries)
 *   1 = unreviewed fabrication idiom(s) or malformed configuration/allow-list
 */

import { readFileSync, readdirSync, existsSync, realpathSync } from 'node:fs';
import { join, dirname, relative, resolve } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const __dirname = dirname(fileURLToPath(import.meta.url));
const DEFAULT_ROOT = join(__dirname, '..');
const DEFAULT_ALLOWLIST = join(__dirname, 'fabrication_guard_allowlist.json');

export const SPORTS = ['mlb', 'nba', 'nfl', 'wnba'];
export const SKIP_DIRS = new Set(['node_modules', '.git', 'renv', 'archive']);
export const TARGET_FILE_RE = /^(build_|export_).*\.R$/;

export const RULES = {
  UNREVIEWED_RNG: 'unreviewed_rng',
  PLAYER_NAME_OVERRIDE: 'player_name_override',
  AFFINE_CLAMP_FORMULA: 'affine_clamp_formula',
  HARDCODED_METRIC_VECTOR: 'hardcoded_metric_vector',
};

const VALID_RULES = new Set(Object.values(RULES));

const PBP_EVENT_LITERAL_RE = /^(?:Free Throw|Shooting Foul|Turnover|Overturned|Coach's Challenge|Jump Ball|Technical Foul|Flagrant Foul|Timeout|Rebound|Three Point|Two Point|Semifinals|Finals|Quarterfinals|Confirmed|Tentative|Guaranteed)$/i;
const PLAYER_VAR_HINT_RE = /(?:player|athlete|full_name|display_name|passer|rusher|receiver|batter|pitcher)/i;
const PLAYER_FIELD_RE = /\b(?:player_name|athlete_name|athlete_display_name|passer_player_name|rusher_player_name|receiver_player_name|batter_name|pitcher_name|player|full_name)\b/;
const CAP_NAME_LITERAL_RE = /^[A-Z][A-Za-z'.-]*(?:\s+(?:[A-Z][A-Za-z'.-]*|de|da|del|van|von|la|Jr\.|Sr\.|II|III|IV)){0,3}$/;
const REGEX_META_RE = /[\\^$|[\](){}*+?,=<>]/;
const NUM_ARG_RE = /^(?:(?:[A-Za-z_][A-Za-z0-9_.]*|["'][^"']+["'])\s*=\s*)?-?(?:\d+\.?\d*|\.\d+)(?:[eE][+-]?\d+)?L?$/;
const EPS_LOW_RE = /^(?:1e-\d+|eps)$/i;
const EPS_HIGH_RE = /^1\s*-\s*(?:1e-\d+|eps)$/i;

/**
 * Replaces R `#` comments with spaces while preserving line structure and
 * keeping `#` characters inside single-quoted, double-quoted, or backticked
 * literals intact.
 */
export function stripRCommentsPreserveLines(source) {
  const out = [];
  let inQuote = null;
  let inComment = false;

  for (let i = 0; i < source.length; i += 1) {
    const ch = source[i];

    if (inComment) {
      if (ch === '\n') {
        inComment = false;
        out.push('\n');
      } else if (ch === '\r') {
        out.push('\r');
      } else {
        out.push(' ');
      }
      continue;
    }

    if (inQuote !== null) {
      out.push(ch);
      if (ch === '\\' && i + 1 < source.length) {
        out.push(source[i + 1]);
        i += 1;
        continue;
      }
      if (ch === inQuote) {
        inQuote = null;
      }
      continue;
    }

    if (ch === '"' || ch === "'" || ch === '`') {
      inQuote = ch;
      out.push(ch);
      continue;
    }

    if (ch === '#') {
      inComment = true;
      out.push(' ');
      continue;
    }

    out.push(ch);
  }

  return out.join('');
}

function lineNumberAt(text, index) {
  let line = 1;
  for (let i = 0; i < index; i += 1) {
    if (text.charCodeAt(i) === 10) line += 1;
  }
  return line;
}

/**
 * Extracts a balanced `(...)` slice starting at the opening `(` index.
 * Returns `{ text, endIndex }` or null if unbalanced.
 */
function extractBalancedParens(text, openParenIdx) {
  if (text[openParenIdx] !== '(') return null;
  let depth = 0;
  let inQuote = null;

  for (let i = openParenIdx; i < text.length; i += 1) {
    const ch = text[i];
    if (inQuote !== null) {
      if (ch === '\\' && i + 1 < text.length) {
        i += 1;
        continue;
      }
      if (ch === inQuote) inQuote = null;
      continue;
    }
    if (ch === '"' || ch === "'" || ch === '`') {
      inQuote = ch;
      continue;
    }
    if (ch === '(') depth += 1;
    else if (ch === ')') {
      depth -= 1;
      if (depth === 0) {
        return { text: text.slice(openParenIdx, i + 1), endIndex: i + 1 };
      }
    }
  }
  return null;
}

/** Splits top-level comma-separated arguments inside `(...)` (without outer parens). */
function splitTopLevelArgs(innerText) {
  const args = [];
  let depth = 0;
  let inQuote = null;
  let start = 0;

  for (let i = 0; i < innerText.length; i += 1) {
    const ch = innerText[i];
    if (inQuote !== null) {
      if (ch === '\\' && i + 1 < innerText.length) {
        i += 1;
        continue;
      }
      if (ch === inQuote) inQuote = null;
      continue;
    }
    if (ch === '"' || ch === "'" || ch === '`') {
      inQuote = ch;
      continue;
    }
    if (ch === '(' || ch === '[' || ch === '{') depth += 1;
    else if (ch === ')' || ch === ']' || ch === '}') depth -= 1;
    else if (ch === ',' && depth === 0) {
      args.push(innerText.slice(start, i).trim());
      start = i + 1;
    }
  }
  const tail = innerText.slice(start).trim();
  if (tail.length > 0 || args.length > 0) args.push(tail);
  return args;
}

function unquoteLiteral(expr) {
  const trimmed = expr.trim();
  if (trimmed.length < 2) return null;
  const quote = trimmed[0];
  if ((quote !== '"' && quote !== "'") || trimmed[trimmed.length - 1] !== quote) {
    return null;
  }
  return trimmed.slice(1, -1);
}

function collapseSnippet(text, maxLen = 160) {
  const collapsed = text.replace(/\s+/g, ' ').trim();
  return collapsed.length > maxLen ? `${collapsed.slice(0, maxLen - 3)}...` : collapsed;
}

function detectUnreviewedRng(relPath, stripped, rawLines) {
  const findings = [];
  const re = /(?<![A-Za-z0-9_.])(runif|rnorm|rbinom|rpois|rexp|rgamma|sample\.int|sample)\s*\(/g;

  for (const m of stripped.matchAll(re)) {
    const line = lineNumberAt(stripped, m.index);
    const openIdx = stripped.indexOf('(', m.index);
    const call = extractBalancedParens(stripped, openIdx);
    const matchText = call
      ? collapseSnippet(`${m[1]}${call.text}`, 300)
      : collapseSnippet(stripped.slice(m.index, m.index + 80), 300);
    const rawLine = (rawLines[line - 1] ?? '').trim();
    findings.push({
      file: relPath,
      line,
      rule: RULES.UNREVIEWED_RNG,
      match: matchText,
      context: rawLine,
    });
  }
  return findings;
}

function detectPlayerNameOverrides(relPath, stripped, rawLines) {
  const findings = [];
  const seenLines = new Set();

  const callRe = /(?<![A-Za-z0-9_.])(grepl|grep|str_detect)\s*\(/g;
  for (const m of stripped.matchAll(callRe)) {
    const fnName = m[1];
    const openIdx = stripped.indexOf('(', m.index);
    const call = extractBalancedParens(stripped, openIdx);
    if (!call) continue;

    const args = splitTopLevelArgs(call.text.slice(1, -1));
    if (args.length < 2) continue;

    const rawPatternArg = fnName === 'str_detect' ? args[1] : args[0];
    const rawTargetArg = fnName === 'str_detect' ? args[0] : args[1];
    const patternArg = rawPatternArg.replace(/^(?:pattern|x|string)\s*=\s*/, '');
    const targetArg = rawTargetArg.replace(/^(?:pattern|x|string)\s*=\s*/, '');
    const lit = unquoteLiteral(patternArg);
    if (!lit) continue;
    if (REGEX_META_RE.test(lit) || !CAP_NAME_LITERAL_RE.test(lit)) continue;

    if (!PLAYER_VAR_HINT_RE.test(targetArg) && PBP_EVENT_LITERAL_RE.test(lit)) {
      continue;
    }

    const line = lineNumberAt(stripped, m.index);
    seenLines.add(`${line}:${m.index}`);
    findings.push({
      file: relPath,
      line,
      rule: RULES.PLAYER_NAME_OVERRIDE,
      match: collapseSnippet(`${fnName}${call.text}`, 300),
      context: (rawLines[line - 1] ?? '').trim(),
    });
  }

  const eqPatterns = [
    new RegExp(`${PLAYER_FIELD_RE.source}\\s*(?:==|!=)\\s*(["'])([A-Z][A-Za-z'.-]*(?:\\s+[A-Za-z'.-]+){0,3})\\1`, 'g'),
    new RegExp(`(["'])([A-Z][A-Za-z'.-]*(?:\\s+[A-Za-z'.-]+){0,3})\\1\\s*(?:==|!=)\\s*${PLAYER_FIELD_RE.source}`, 'g'),
    new RegExp(`${PLAYER_FIELD_RE.source}\\s*%in%\\s*c\\([^)]*(["'])([A-Z][A-Za-z'.-]*(?:\\s+[A-Za-z'.-]+){0,3})\\1`, 'g'),
  ];

  for (const re of eqPatterns) {
    for (const m of stripped.matchAll(re)) {
      const line = lineNumberAt(stripped, m.index);
      const key = `${line}:${m.index}`;
      if (seenLines.has(key)) continue;
      seenLines.add(key);
      findings.push({
        file: relPath,
        line,
        rule: RULES.PLAYER_NAME_OVERRIDE,
        match: collapseSnippet(m[0], 300),
        context: (rawLines[line - 1] ?? '').trim(),
      });
    }
  }

  return findings;
}

function isPureProbabilityEpsilonClip(outerArgs, innerArgs) {
  const allArgs = [...outerArgs, ...innerArgs];
  const hasLowEps = allArgs.some((a) => EPS_LOW_RE.test(a.trim()));
  const hasHighEps = allArgs.some((a) => EPS_HIGH_RE.test(a.trim()));
  if (!hasLowEps || !hasHighEps) return false;

  const valueArgs = innerArgs.filter((a) => {
    const t = a.trim();
    return !EPS_LOW_RE.test(t) && !EPS_HIGH_RE.test(t);
  });
  return valueArgs.every((a) => !/[+\-*/]/.test(a) || /^pnorm\s*\(/.test(a.trim()));
}

function detectAffineClamps(relPath, stripped, rawLines) {
  const findings = [];

  const clampRe = /(?<![A-Za-z0-9_.])clamp\s*\(/g;
  for (const m of stripped.matchAll(clampRe)) {
    const line = lineNumberAt(stripped, m.index);
    const openIdx = stripped.indexOf('(', m.index);
    const call = extractBalancedParens(stripped, openIdx);
    findings.push({
      file: relPath,
      line,
      rule: RULES.AFFINE_CLAMP_FORMULA,
      match: collapseSnippet(call ? `clamp${call.text}` : m[0], 300),
      context: (rawLines[line - 1] ?? '').trim(),
    });
  }

  const pmRe = /(?<![A-Za-z0-9_.])(pmin|pmax)\s*\(/g;
  let lastAcceptedEnd = -1;
  for (const m of stripped.matchAll(pmRe)) {
    if (m.index < lastAcceptedEnd) continue;

    const outerFn = m[1];
    const innerFn = outerFn === 'pmin' ? 'pmax' : 'pmin';
    const openIdx = stripped.indexOf('(', m.index);
    const call = extractBalancedParens(stripped, openIdx);
    if (!call) continue;

    const innerMatch = new RegExp(`(?<![A-Za-z0-9_.])${innerFn}\\s*\\(`).exec(call.text.slice(1, -1));
    if (!innerMatch) continue;

    const outerArgs = splitTopLevelArgs(call.text.slice(1, -1));
    const innerOpenRelative = call.text.slice(1, -1).indexOf('(', innerMatch.index);
    const innerCall = extractBalancedParens(call.text.slice(1, -1), innerOpenRelative);
    const innerArgs = innerCall ? splitTopLevelArgs(innerCall.text.slice(1, -1)) : [];

    if (/\bpercent_rank\s*\(/.test(call.text)) continue;
    if (isPureProbabilityEpsilonClip(outerArgs, innerArgs)) continue;

    // Strip epsilon upper-bound pattern `1 - 1e-6` and unary minus on numeric
    // literals (e.g. `pmax(-4, pmin(4, x))`) before testing for arithmetic.
    const bodyForArith = call.text
      .slice(1, -1)
      .replace(/1\s*-\s*(?:1e-\d+|eps)\b/gi, '')
      .replace(/(^|[(\[,=+\-*/])\s*-(?=\s*(?:\d|\.\d))/g, '$1');
    if (!/[+\-*/]/.test(bodyForArith)) continue;

    const line = lineNumberAt(stripped, m.index);
    lastAcceptedEnd = call.endIndex;
    findings.push({
      file: relPath,
      line,
      rule: RULES.AFFINE_CLAMP_FORMULA,
      match: collapseSnippet(`${outerFn}${call.text}`, 300),
      context: (rawLines[line - 1] ?? '').trim(),
    });
  }

  return findings;
}

function detectHardcodedMetricVectors(relPath, stripped, rawLines) {
  const findings = [];

  const tribbleRe = /(?<![A-Za-z0-9_.])(?:tibble::)?tribble\s*\(/g;
  for (const m of stripped.matchAll(tribbleRe)) {
    const line = lineNumberAt(stripped, m.index);
    const openIdx = stripped.indexOf('(', m.index);
    const call = extractBalancedParens(stripped, openIdx);
    const snippet = call ? `${m[0].replace(/\s*\($/, '')}${call.text}` : m[0];
    findings.push({
      file: relPath,
      line,
      rule: RULES.HARDCODED_METRIC_VECTOR,
      match: collapseSnippet(snippet, 300),
      context: (rawLines[line - 1] ?? '').trim(),
    });
  }

  const vecRe = /(?<![A-Za-z0-9_.])c\s*\(/g;
  for (const m of stripped.matchAll(vecRe)) {
    // Skip `%in% c(...)` membership filter predicates.
    const prefix = stripped.slice(Math.max(0, m.index - 20), m.index);
    if (/%in%\s*$/.test(prefix)) continue;

    const openIdx = stripped.indexOf('(', m.index);
    const call = extractBalancedParens(stripped, openIdx);
    if (!call) continue;

    const args = splitTopLevelArgs(call.text.slice(1, -1));
    const numCount = args.filter((a) => NUM_ARG_RE.test(a.trim())).length;
    if (numCount < 3) continue;

    const line = lineNumberAt(stripped, m.index);
    findings.push({
      file: relPath,
      line,
      rule: RULES.HARDCODED_METRIC_VECTOR,
      match: collapseSnippet(`c${call.text}`, 300),
      context: (rawLines[line - 1] ?? '').trim(),
    });
  }

  return findings;
}

/**
 * Loads and validates `tools/fabrication_guard_allowlist.json`.
 * Rejects missing justification, invalid rule names, or wildcard catch-alls.
 */
export function loadAllowlist(allowlistPath) {
  const raw = readFileSync(allowlistPath, 'utf8');
  const parsed = JSON.parse(raw);
  const rawEntries = Array.isArray(parsed) ? parsed : parsed?.entries;
  if (!Array.isArray(rawEntries)) {
    throw new Error(`Allow-list at ${allowlistPath} must contain an 'entries' array.`);
  }

  return rawEntries.map((entry, idx) => {
    if (!entry || typeof entry !== 'object') {
      throw new Error(`Allow-list entry #${idx} must be an object.`);
    }
    const file = typeof entry.file === 'string' ? entry.file.replace(/\\/g, '/').trim() : '';
    const rule = typeof entry.rule === 'string' ? entry.rule.trim() : '';
    const pattern = typeof entry.pattern === 'string' ? entry.pattern : '';
    const justification = typeof entry.justification === 'string' ? entry.justification.trim() : '';

    if (!file || file.includes('*')) {
      throw new Error(`Allow-list entry #${idx} must specify an exact relative 'file' path (no wildcards).`);
    }
    if (!VALID_RULES.has(rule)) {
      throw new Error(`Allow-list entry #${idx} (${file}) has invalid rule '${rule}'.`);
    }
    if (pattern.trim().length < 5 || /^(\.\*|\.\+|\\s\*)$/.test(pattern.trim())) {
      throw new Error(`Allow-list entry #${idx} (${file}) must provide a concrete, non-wildcard 'pattern'.`);
    }
    if (justification.length < 15 || /[\r\n]/.test(justification) || /^(todo|tbd|fixme)$/i.test(justification)) {
      throw new Error(`Allow-list entry #${idx} (${file}) must include a concrete one-line 'justification'.`);
    }

    let regex;
    try {
      regex = new RegExp(pattern);
    } catch (err) {
      throw new Error(`Allow-list entry #${idx} (${file}) has invalid regex '${pattern}': ${err.message}`);
    }

    return { file, rule, pattern, justification, regex };
  });
}

/** Scans a single R file and returns raw (pre-allowlist) findings plus seed status. */
export function scanFile(absPath, relPath) {
  const raw = readFileSync(absPath, 'utf8');
  const rawLines = raw.split(/\r?\n/);
  const stripped = stripRCommentsPreserveLines(raw);
  const hasSetSeed = /(?<![A-Za-z0-9_.])set\.seed\s*\(/.test(stripped);

  const findings = [
    ...detectUnreviewedRng(relPath, stripped, rawLines),
    ...detectPlayerNameOverrides(relPath, stripped, rawLines),
    ...detectAffineClamps(relPath, stripped, rawLines),
    ...detectHardcodedMetricVectors(relPath, stripped, rawLines),
  ];

  return { findings, hasSetSeed };
}

function collectTargetFiles(rootDir) {
  const collected = [];

  function walk(dir) {
    let entries;
    try {
      entries = readdirSync(dir, { withFileTypes: true });
    } catch {
      return;
    }
    for (const entry of entries) {
      if (SKIP_DIRS.has(entry.name)) continue;
      if (entry.isSymbolicLink()) continue;
      const fullPath = join(dir, entry.name);
      if (entry.isDirectory()) {
        walk(fullPath);
      } else if (entry.isFile() && TARGET_FILE_RE.test(entry.name)) {
        collected.push({
          absPath: fullPath,
          relPath: relative(rootDir, fullPath).replace(/\\/g, '/'),
        });
      }
    }
  }

  for (const sport of SPORTS) {
    const sportDir = join(rootDir, sport);
    if (existsSync(sportDir)) walk(sportDir);
  }

  collected.sort((a, b) => a.relPath.localeCompare(b.relPath));
  return collected;
}

/** Scans the target tree and applies the reviewed allow-list. */
export function scanRepository({ rootDir = DEFAULT_ROOT, allowlistPath = DEFAULT_ALLOWLIST } = {}) {
  const allowlist = loadAllowlist(allowlistPath);
  const files = collectTargetFiles(rootDir);

  if (files.length === 0) {
    throw new Error(`No build_*.R or export_*.R files found under ${SPORTS.join('/, ')}/ in ${rootDir}`);
  }

  const violations = [];
  let allowlistedHits = 0;

  for (const { absPath, relPath } of files) {
    const { findings, hasSetSeed } = scanFile(absPath, relPath);
    for (const finding of findings) {
      const matchedAllow = allowlist.find(
        (entry) =>
          entry.file === finding.file &&
          entry.rule === finding.rule &&
          (entry.regex.test(finding.match) || entry.regex.test(finding.context))
      );

      if (matchedAllow) {
        if (finding.rule === RULES.UNREVIEWED_RNG && !hasSetSeed) {
          violations.push({
            ...finding,
            note: 'Allow-listed RNG requires set.seed() in the same file, but none was found.',
          });
        } else {
          allowlistedHits += 1;
        }
      } else {
        violations.push(finding);
      }
    }
  }

  return {
    filesScanned: files.length,
    allowlistEntries: allowlist.length,
    allowlistedHits,
    violations,
  };
}

function parseCliArgs(argv) {
  let rootDir = process.env.FABRICATION_GUARD_ROOT || DEFAULT_ROOT;
  let allowlistPath = process.env.FABRICATION_GUARD_ALLOWLIST || DEFAULT_ALLOWLIST;

  for (let i = 0; i < argv.length; i += 1) {
    if (argv[i] === '--root' && argv[i + 1]) {
      rootDir = resolve(argv[i + 1]);
      i += 1;
    } else if (argv[i] === '--allowlist' && argv[i + 1]) {
      allowlistPath = resolve(argv[i + 1]);
      i += 1;
    } else {
      throw new Error(`Unknown or incomplete argument: ${argv[i]}`);
    }
  }

  return { rootDir, allowlistPath };
}

function main() {
  let opts;
  try {
    opts = parseCliArgs(process.argv.slice(2));
  } catch (err) {
    console.error(`check_fabrication_idioms: ${err.message}`);
    process.exit(1);
  }

  let report;
  try {
    report = scanRepository(opts);
  } catch (err) {
    console.error(`check_fabrication_idioms: ERROR -- ${err.message}`);
    process.exit(1);
  }

  if (report.violations.length > 0) {
    console.error(
      `check_fabrication_idioms: FAILED -- ${report.violations.length} unreviewed fabrication idiom(s) detected across ${report.filesScanned} file(s):`
    );
    for (const v of report.violations) {
      const note = v.note ? ` [${v.note}]` : '';
      console.error(`  - ${v.file}:${v.line} [${v.rule}] ${collapseSnippet(v.match, 120)}${note}`);
    }
    console.error('');
    console.error('Fix: remove the fabrication idiom from the R script (preferred), or if it is a');
    console.error('verified structural constant / seeded simulator, add an audited entry to');
    console.error('tools/fabrication_guard_allowlist.json with file, rule, pattern, and a one-line justification.');
    process.exit(1);
  }

  console.log(
    `check_fabrication_idioms: OK -- scanned ${report.filesScanned} R file(s) across ${SPORTS.length} sports (${report.allowlistedHits} allow-listed hit(s), 0 violations)`
  );
}

const isMain =
  Boolean(process.argv[1]) &&
  existsSync(resolve(process.argv[1])) &&
  realpathSync(resolve(process.argv[1])) === realpathSync(fileURLToPath(import.meta.url));

if (isMain) {
  main();
}
