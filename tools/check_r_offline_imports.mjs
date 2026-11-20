#!/usr/bin/env node
/**
 * Static offline-CI R library import guard.
 *
 * Scans every `.R` file under this repo's four sport subtree mirrors (`mlb/`,
 * `nba/`, `nfl/`, `wnba/`, skipping `node_modules`, `.git`, `renv`, `archive`,
 * and `tests`) for unconditional `library(pkg)` / `require(pkg)` calls that
 * attach heavy network-fetch packages (hoopR, nflfastR, nflreadr, wehoop,
 * baseballr). Such calls make a script fail to even load on an offline CI host
 * that lacks those packages. Lazy `requireNamespace("pkg", quietly = TRUE)`
 * guards are the preferred pattern and are never flagged.
 *
 * R `#` comments are stripped (respecting quotes) and string literal contents
 * are masked, so `library(...)` text inside comments or strings never matches.
 *
 * Existing hits must be listed in the reviewed allow-list
 * (`tools/r_offline_imports_allowlist.json`, entries `{file, line, package,
 * reason}`). The guard fails on any un-allowlisted hit AND on any stale entry
 * that no longer matches a hit on disk, so entries are removed as files migrate
 * to `requireNamespace`.
 *
 * Never writes inside `mlb/`, `nba/`, `nfl/`, or `wnba/`.
 *
 * Usage:
 *   node tools/check_r_offline_imports.mjs [--root <dir>] [--allowlist <path>]
 *
 * Environment overrides (used by tests):
 *   OFFLINE_R_GUARD_ROOT       Root directory containing sport subtrees
 *   OFFLINE_R_GUARD_ALLOWLIST  Path to JSON allow-list file
 *
 * Exit codes:
 *   0 = clean
 *   1 = un-allowlisted hit(s), stale allow-list entries, or bad configuration
 */

import { readFileSync, readdirSync, existsSync, realpathSync } from 'node:fs';
import { join, dirname, relative, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = dirname(fileURLToPath(import.meta.url));
const DEFAULT_ROOT = join(__dirname, '..');
const DEFAULT_ALLOWLIST = join(__dirname, 'r_offline_imports_allowlist.json');

export const SPORTS = ['mlb', 'nba', 'nfl', 'wnba'];
export const SKIP_DIRS = new Set(['node_modules', '.git', 'renv', 'archive', 'tests']);
export const HEAVY_PACKAGES = ['hoopR', 'nflfastR', 'nflreadr', 'wehoop', 'baseballr'];
const HEAVY_SET = new Set(HEAVY_PACKAGES);

/**
 * Returns a copy of `source` with `#` comments blanked and the contents of
 * quoted literals replaced by spaces (quote characters kept). Line structure
 * and character offsets are preserved.
 */
export function maskCommentsAndStrings(source) {
  const out = [];
  let inQuote = null;
  let inComment = false;

  for (let i = 0; i < source.length; i += 1) {
    const ch = source[i];

    if (inComment) {
      if (ch === '\n' || ch === '\r') {
        if (ch === '\n') inComment = false;
        out.push(ch);
      } else {
        out.push(' ');
      }
      continue;
    }

    if (inQuote !== null) {
      if (ch === '\\' && i + 1 < source.length) {
        out.push(' ', source[i + 1] === '\n' ? '\n' : ' ');
        i += 1;
        continue;
      }
      if (ch === inQuote) {
        inQuote = null;
        out.push(ch);
      } else {
        out.push(ch === '\n' || ch === '\r' ? ch : ' ');
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

const CALL_RE = /(?<![A-Za-z0-9_.])(library|require)\s*\(\s*/g;
const ARG_RE = /^(?:package\s*=\s*)?(["'`]?)([A-Za-z][A-Za-z0-9.]*)\1\s*[,)]/;

/** Returns hits `{file, line, package, call}` for one file's source text. */
export function scanSource(relPath, source) {
  const masked = maskCommentsAndStrings(source);
  const hits = [];
  for (const m of masked.matchAll(CALL_RE)) {
    const argStart = m.index + m[0].length;
    // Read the argument from the raw source (masked text blanks quoted names),
    // but only after confirming the call itself is live code.
    const argMatch = ARG_RE.exec(source.slice(argStart, argStart + 80));
    if (!argMatch) continue;
    const pkg = argMatch[2];
    if (!HEAVY_SET.has(pkg)) continue;
    hits.push({ file: relPath, line: lineNumberAt(masked, m.index), package: pkg, call: m[1] });
  }
  return hits;
}

export function loadAllowlist(allowlistPath) {
  const parsed = JSON.parse(readFileSync(allowlistPath, 'utf8'));
  const rawEntries = Array.isArray(parsed) ? parsed : parsed?.entries;
  if (!Array.isArray(rawEntries)) {
    throw new Error(`Allow-list at ${allowlistPath} must contain an 'entries' array.`);
  }
  return rawEntries.map((entry, idx) => {
    if (!entry || typeof entry !== 'object') throw new Error(`Allow-list entry #${idx} must be an object.`);
    const file = typeof entry.file === 'string' ? entry.file.replace(/\\/g, '/').trim() : '';
    const pkg = typeof entry.package === 'string' ? entry.package.trim() : '';
    const reason = typeof entry.reason === 'string' ? entry.reason.trim() : '';
    if (!file || file.includes('*')) throw new Error(`Allow-list entry #${idx} must specify an exact 'file' path.`);
    if (!Number.isInteger(entry.line) || entry.line < 1) throw new Error(`Allow-list entry #${idx} (${file}) needs a positive integer 'line'.`);
    if (!HEAVY_SET.has(pkg)) throw new Error(`Allow-list entry #${idx} (${file}) has unknown package '${pkg}'.`);
    if (reason.length < 10 || /[\r\n]/.test(reason)) throw new Error(`Allow-list entry #${idx} (${file}) needs a concrete one-line 'reason'.`);
    return { file, line: entry.line, package: pkg, reason };
  });
}

function collectRFiles(rootDir) {
  const collected = [];
  function walk(dir) {
    let entries;
    try {
      entries = readdirSync(dir, { withFileTypes: true });
    } catch {
      return;
    }
    for (const entry of entries) {
      if (SKIP_DIRS.has(entry.name) || entry.isSymbolicLink()) continue;
      const full = join(dir, entry.name);
      if (entry.isDirectory()) walk(full);
      else if (entry.isFile() && /\.R$/.test(entry.name)) {
        collected.push({ absPath: full, relPath: relative(rootDir, full).replace(/\\/g, '/') });
      }
    }
  }
  for (const sport of SPORTS) {
    const d = join(rootDir, sport);
    if (existsSync(d)) walk(d);
  }
  collected.sort((a, b) => a.relPath.localeCompare(b.relPath));
  return collected;
}

const keyOf = (x) => `${x.file}:${x.line}:${x.package}`;

export function scanRepository({ rootDir = DEFAULT_ROOT, allowlistPath = DEFAULT_ALLOWLIST } = {}) {
  const allowlist = loadAllowlist(allowlistPath);
  const files = collectRFiles(rootDir);
  const hits = files.flatMap(({ absPath, relPath }) => scanSource(relPath, readFileSync(absPath, 'utf8')));

  const allowKeys = new Set(allowlist.map(keyOf));
  const hitKeys = new Set(hits.map(keyOf));
  const violations = hits.filter((h) => !allowKeys.has(keyOf(h)));
  const stale = allowlist.filter((e) => !hitKeys.has(keyOf(e)));

  return { filesScanned: files.length, allowlistEntries: allowlist.length, hits, violations, stale };
}

function parseCliArgs(argv) {
  let rootDir = process.env.OFFLINE_R_GUARD_ROOT || DEFAULT_ROOT;
  let allowlistPath = process.env.OFFLINE_R_GUARD_ALLOWLIST || DEFAULT_ALLOWLIST;
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
  let report;
  try {
    report = scanRepository(parseCliArgs(process.argv.slice(2)));
  } catch (err) {
    console.error(`check_r_offline_imports: ERROR -- ${err.message}`);
    process.exit(1);
  }

  if (report.violations.length > 0 || report.stale.length > 0) {
    console.error(
      `check_r_offline_imports: FAILED -- ${report.violations.length} un-allowlisted heavy import(s), ${report.stale.length} stale allow-list entr(ies) across ${report.filesScanned} R file(s):`
    );
    for (const v of report.violations) console.error(`  - ${v.file}:${v.line} ${v.call}(${v.package})`);
    for (const s of report.stale) console.error(`  - STALE allow-list entry ${s.file}:${s.line} (${s.package}) no longer matches on disk`);
    console.error('');
    console.error('Fix: replace library()/require() with a lazy requireNamespace("pkg", quietly = TRUE) guard');
    console.error('(preferred), or update tools/r_offline_imports_allowlist.json (remove stale entries).');
    process.exit(1);
  }

  console.log(
    `check_r_offline_imports: OK -- scanned ${report.filesScanned} R file(s) across ${SPORTS.length} sports (${report.hits.length} allow-listed hit(s), 0 violations, 0 stale)`
  );
}

const isMain =
  Boolean(process.argv[1]) &&
  existsSync(resolve(process.argv[1])) &&
  realpathSync(resolve(process.argv[1])) === realpathSync(fileURLToPath(import.meta.url));

if (isMain) main();
