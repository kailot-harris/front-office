#!/usr/bin/env node
/**
 * One-command test pipeline for the MLB Analytics web app.
 *
 * Runs every layer in cheapest-first order, then reconciles the failures
 * against tests/known-issues.json so the suite works as a merge gate while
 * documented defects are still open:
 *
 *   typecheck -> lint -> vitest (node) -> build
 *
 *   a failure listed in known-issues.json  -> KNOWN     (does not fail the run)
 *   a failure that is not listed           -> REGRESSION (fails the run)
 *   a listed test that now passes          -> FIXED     (prompts you to delete it)
 *
 * Usage:
 *   node scripts/run-test-suite.mjs                 # everything
 *   node scripts/run-test-suite.mjs --fast          # skip build
 *   node scripts/run-test-suite.mjs --only=contracts # one stage
 *   node scripts/run-test-suite.mjs --strict        # ignore the baseline; any failure fails
 *   node scripts/run-test-suite.mjs --update-baseline
 *
 * Writes a markdown summary to test-results/SUMMARY.md.
 */
import { spawnSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import process from 'node:process';

const ROOT = path.resolve(import.meta.dirname, '..');
const RESULTS_DIR = path.join(ROOT, 'test-results');
const KNOWN_ISSUES_PATH = path.join(ROOT, 'tests', 'known-issues.json');

const args = process.argv.slice(2);
const flag = (name) => args.includes(`--${name}`);
const option = (name) => args.find((a) => a.startsWith(`--${name}=`))?.split('=')[1];

const FAST = flag('fast');
const STRICT = flag('strict');
const UPDATE_BASELINE = flag('update-baseline');
const ONLY = option('only');

const C = {
  reset: '\x1b[0m',
  bold: '\x1b[1m',
  dim: '\x1b[2m',
  red: '\x1b[31m',
  green: '\x1b[32m',
  yellow: '\x1b[33m',
  blue: '\x1b[36m',
};
const paint = (color, s) => (process.stdout.isTTY ? `${C[color]}${s}${C.reset}` : s);

fs.mkdirSync(RESULTS_DIR, { recursive: true });

// --------------------------------------------------------------- stages ------

const STAGES = [
  {
    id: 'typecheck',
    label: 'TypeScript',
    kind: 'gate',
    fastOk: true,
    cmd: ['npx', 'tsc', '--noEmit'],
  },
  {
    id: 'lint',
    label: 'ESLint',
    kind: 'gate',
    fastOk: true,
    cmd: ['npx', 'next', 'lint', '--max-warnings=0'],
  },
  {
    id: 'contracts',
    label: 'Dataset contracts, invariants & drift (vitest/node)',
    kind: 'tests',
    fastOk: true,
    cmd: [
      'npx',
      'vitest',
      'run',
      '--project',
      'node',
      '--reporter=default',
      '--reporter=json',
      '--outputFile=test-results/vitest-node.json',
    ],
    resultFile: 'vitest-node.json',
    parse: parseVitest,
    minTests: 40,
  },
  {
    id: 'build',
    label: 'Production build',
    kind: 'gate',
    fastOk: false,
    cmd: ['npx', 'next', 'build'],
  },
];

// ---------------------------------------------------------------- parsing ----

function readJson(file) {
  const p = path.join(RESULTS_DIR, file);
  if (!fs.existsSync(p)) return null;
  try {
    return JSON.parse(fs.readFileSync(p, 'utf-8'));
  } catch {
    return null;
  }
}

/** vitest --reporter=json -> [{ name, status }] */
function parseVitest(file) {
  const data = readJson(file);
  if (!data?.testResults) return null;
  const out = [];
  for (const suite of data.testResults) {
    for (const t of suite.assertionResults ?? []) {
      const name = [...(t.ancestorTitles ?? []), t.title].join(' > ');
      out.push({
        name,
        status:
          t.status === 'passed'
            ? 'passed'
            : t.status === 'pending' || t.status === 'skipped'
              ? 'skipped'
              : 'failed',
        message: (t.failureMessages ?? []).join('\n').split('\n')[0] ?? '',
      });
    }
  }
  return out;
}

// --------------------------------------------------------------- baseline ----

function loadKnownIssues() {
  if (!fs.existsSync(KNOWN_ISSUES_PATH)) return [];
  const raw = JSON.parse(fs.readFileSync(KNOWN_ISSUES_PATH, 'utf-8'));
  return raw.issues ?? [];
}

function matchIssue(issues, testName) {
  for (const issue of issues) {
    for (const pattern of issue.tests ?? []) {
      if (testName.includes(pattern)) return issue;
    }
  }
  return null;
}

// ------------------------------------------------------------------- run -----

function runStage(stage) {
  const [cmd, ...rest] = stage.cmd;
  const started = Date.now();
  process.stdout.write(`\n${paint('blue', '▶')} ${paint('bold', stage.label)}\n`);
  const res = spawnSync(cmd, rest, {
    cwd: ROOT,
    stdio: 'inherit',
    shell: process.platform === 'win32',
    env: { ...process.env, FORCE_COLOR: '1' },
  });
  return { exitCode: res.status ?? 1, durationMs: Date.now() - started };
}

const issues = loadKnownIssues();
const stagesToRun = STAGES.filter((s) => {
  if (ONLY) return s.id === ONLY;
  if (FAST) return s.fastOk;
  return true;
});

if (!stagesToRun.length) {
  console.error(`No stage matched --only=${ONLY}. Known stages: ${STAGES.map((s) => s.id).join(', ')}`);
  process.exit(2);
}

const report = [];
let hardFailure = false;
const allKnown = [];
const allRegressions = [];
const allFixed = [];

for (const stage of stagesToRun) {
  const { exitCode, durationMs } = runStage(stage);
  const entry = { id: stage.id, label: stage.label, exitCode, durationMs, kind: stage.kind };

  if (stage.kind === 'gate') {
    entry.ok = exitCode === 0;
    if (!entry.ok) hardFailure = true;
    report.push(entry);
    continue;
  }

  const tests = stage.parse(stage.resultFile);
  if (!tests) {
    entry.ok = false;
    entry.note = `could not read ${stage.resultFile}; treating the stage as failed`;
    hardFailure = true;
    report.push(entry);
    continue;
  }

  const minTests = stage.minTests ?? 1;
  if (tests.length < minTests) {
    entry.ok = false;
    entry.total = tests.length;
    entry.passed = tests.filter((t) => t.status === 'passed').length;
    entry.failed = tests.filter((t) => t.status === 'failed').length;
    entry.note =
      `ran ${tests.length} test(s), below this stage's floor of ${minTests} - ` +
      `the harness did not execute, so a green result here means nothing`;
    hardFailure = true;
    report.push(entry);
    continue;
  }

  const failed = tests.filter((t) => t.status === 'failed');
  const passed = tests.filter((t) => t.status === 'passed');

  const known = [];
  const regressions = [];
  for (const t of failed) {
    const issue = STRICT ? null : matchIssue(issues, t.name);
    if (issue) known.push({ ...t, issueId: issue.id, issueTitle: issue.title });
    else regressions.push(t);
  }

  const fixed = [];
  for (const issue of issues) {
    const related = tests.filter((t) => (issue.tests ?? []).some((p) => t.name.includes(p)));
    if (related.length && related.every((t) => t.status === 'passed')) {
      fixed.push({ issueId: issue.id, issueTitle: issue.title, count: related.length });
    }
  }

  entry.total = tests.length;
  entry.passed = passed.length;
  entry.failed = failed.length;
  entry.known = known;
  entry.regressions = regressions;
  entry.fixed = fixed;
  entry.ok = regressions.length === 0;
  if (!entry.ok) hardFailure = true;

  allKnown.push(...known);
  allRegressions.push(...regressions);
  allFixed.push(...fixed);
  report.push(entry);
}

// ---------------------------------------------------------------- summary ----

const dur = (ms) => `${(ms / 1000).toFixed(1)}s`;
const line = '─'.repeat(74);

console.log(`\n${line}\n${paint('bold', 'TEST SUITE SUMMARY')}\n${line}`);

for (const s of report) {
  if (s.kind === 'gate') {
    const tag = s.ok ? paint('green', 'PASS') : paint('red', 'FAIL');
    console.log(`${tag}  ${s.label.padEnd(50)} ${paint('dim', dur(s.durationMs))}`);
    continue;
  }
  const tag = s.ok ? paint('green', 'PASS') : paint('red', 'FAIL');
  const bits = [`${s.passed}/${s.total} passed`];
  if (s.known?.length) bits.push(paint('yellow', `${s.known.length} known`));
  if (s.regressions?.length) bits.push(paint('red', `${s.regressions.length} NEW`));
  console.log(`${tag}  ${s.label.padEnd(50)} ${paint('dim', dur(s.durationMs))}`);
  console.log(`      ${bits.join(', ')}${s.note ? ` — ${s.note}` : ''}`);
}

if (allRegressions.length) {
  console.log(`\n${paint('red', paint('bold', `NEW FAILURES (${allRegressions.length}) — not in tests/known-issues.json`))}`);
  for (const t of allRegressions.slice(0, 40)) {
    console.log(`  ${paint('red', '✗')} ${t.name}${t.project ? paint('dim', ` [${t.project}]`) : ''}`);
    if (t.message) console.log(`      ${paint('dim', t.message.slice(0, 160))}`);
  }
  if (allRegressions.length > 40) console.log(`  ${paint('dim', `...and ${allRegressions.length - 40} more`)}`);
}

if (allKnown.length) {
  const byIssue = new Map();
  for (const t of allKnown) {
    if (!byIssue.has(t.issueId)) byIssue.set(t.issueId, { title: t.issueTitle, count: 0 });
    byIssue.get(t.issueId).count++;
  }
  console.log(`\n${paint('yellow', paint('bold', `KNOWN DEFECTS (${byIssue.size} issues, ${allKnown.length} failing tests)`))}`);
  for (const [id, info] of byIssue) {
    console.log(`  ${paint('yellow', '!')} ${paint('bold', id)} (${info.count}) ${info.title.slice(0, 110)}`);
  }
  console.log(paint('dim', '  Each has a documented fix in tests/known-issues.json.'));
}

if (allFixed.length) {
  const unique = [...new Map(allFixed.map((f) => [f.issueId, f])).values()];
  console.log(`\n${paint('green', paint('bold', `FIXED (${unique.length}) — remove these from tests/known-issues.json`))}`);
  for (const f of unique) console.log(`  ${paint('green', '✓')} ${paint('bold', f.issueId)} ${f.issueTitle.slice(0, 110)}`);
}

// ------------------------------------------------------------- markdown ------

const md = [];
md.push('# Test suite summary', '');
md.push(`Run at ${new Date().toISOString()}`);
md.push(`Mode: ${STRICT ? 'strict (baseline ignored)' : 'baseline-aware'}${FAST ? ', fast (no build)' : ''}${ONLY ? `, only=${ONLY}` : ''}`, '');
md.push('| Stage | Result | Passed | Known | New | Time |');
md.push('| --- | --- | --- | --- | --- | --- |');
for (const s of report) {
  md.push(
    `| ${s.label} | ${s.ok ? 'pass' : 'fail'} | ${s.kind === 'gate' ? '—' : `${s.passed}/${s.total}`} | ` +
      `${s.known?.length ?? '—'} | ${s.regressions?.length ?? '—'} | ${dur(s.durationMs)} |`,
  );
}
if (allRegressions.length) {
  md.push('', '## New failures', '');
  for (const t of allRegressions) md.push(`- \`${t.name}\`${t.project ? ` [${t.project}]` : ''} — ${t.message}`);
}
if (allKnown.length) {
  md.push('', '## Known defects still failing', '');
  const byIssue = new Map();
  for (const t of allKnown) {
    if (!byIssue.has(t.issueId)) byIssue.set(t.issueId, { title: t.issueTitle, tests: [] });
    byIssue.get(t.issueId).tests.push(t.name);
  }
  for (const [id, info] of byIssue) {
    md.push(`### ${id}`, '', info.title, '');
    for (const name of info.tests) md.push(`- \`${name}\``);
    md.push('');
  }
}
fs.writeFileSync(path.join(RESULTS_DIR, 'SUMMARY.md'), `${md.join('\n')}\n`);
console.log(`\n${paint('dim', `Markdown summary: test-results/SUMMARY.md`)}`);

if (UPDATE_BASELINE) {
  console.log(
    `\n${paint('yellow', '--update-baseline is intentionally not automatic.')}\n` +
      `Adding an entry requires a human-written title and fix, so the baseline cannot\n` +
      `silently absorb a regression. Copy the NEW FAILURES above into\n` +
      `tests/known-issues.json with an id, severity, title and fix.`,
  );
}

console.log(line);
if (hardFailure) {
  console.log(paint('red', paint('bold', 'RESULT: FAILED')));
  process.exit(1);
}
console.log(
  paint('green', paint('bold', 'RESULT: PASSED')) +
    (allKnown.length ? paint('yellow', ` (with ${allKnown.length} known defect(s) still open)`) : ''),
);
process.exit(0);
