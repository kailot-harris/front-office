#!/usr/bin/env node
/**
 * Unit and negative regression tests for tools/check_fabrication_idioms.mjs
 * (front-office#108).
 *
 * Uses plain Node (`node:assert/strict`) and isolated temporary directories so
 * none of the read-only sport subtrees (mlb/, nba/, nfl/, wnba/) are ever
 * modified.
 *
 * Usage:
 *   node tools/test_check_fabrication_idioms.mjs
 */

import assert from 'node:assert/strict';
import { execFileSync, spawnSync } from 'node:child_process';
import { mkdtempSync, mkdirSync, writeFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = dirname(fileURLToPath(import.meta.url));
const REPO_ROOT = join(__dirname, '..');
const GUARD_SCRIPT = join(__dirname, 'check_fabrication_idioms.mjs');
const REAL_ALLOWLIST = join(__dirname, 'fabrication_guard_allowlist.json');

const EMPTY_ALLOWLIST = JSON.stringify({ schema_version: '1.0', entries: [] }, null, 2);

function withTempWorkspace(files, fn, allowlistJson = EMPTY_ALLOWLIST) {
  const root = mkdtempSync(join(tmpdir(), 'fo-fab-guard-'));
  try {
    for (const [relPath, contents] of Object.entries(files)) {
      const abs = join(root, relPath);
      mkdirSync(dirname(abs), { recursive: true });
      writeFileSync(abs, contents, 'utf8');
    }
    const allowPath = join(root, 'allowlist.json');
    writeFileSync(allowPath, allowlistJson, 'utf8');
    fn(root, allowPath);
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
}

function runGuard({ rootDir, allowlistPath }) {
  const res = spawnSync(
    process.execPath,
    [GUARD_SCRIPT, '--root', rootDir, '--allowlist', allowlistPath],
    { encoding: 'utf8' }
  );
  return {
    status: res.status,
    stdout: res.stdout || '',
    stderr: res.stderr || '',
    output: `${res.stdout || ''}\n${res.stderr || ''}`,
  };
}

const tests = [];
function test(name, fn) {
  tests.push({ name, fn });
}

test('passes (exit 0) on current repository tree', () => {
  const out = execFileSync(process.execPath, [GUARD_SCRIPT], {
    cwd: REPO_ROOT,
    encoding: 'utf8',
  });
  assert.match(out, /check_fabrication_idioms: OK/);
  assert.match(out, /0 violations/);
});

test('fails (exit 1) on un-allowlisted runif(', () => {
  withTempWorkspace(
    {
      'nba/build_fake.R': [
        '# legitimate header comment',
        'rating <- runif(10, 0, 1)',
        '',
      ].join('\n'),
    },
    (root, allowPath) => {
      const res = runGuard({ rootDir: root, allowlistPath: allowPath });
      assert.equal(res.status, 1);
      assert.match(res.output, /nba\/build_fake\.R:2/);
      assert.match(res.output, /\[unreviewed_rng\]/);
      assert.match(res.output, /runif\(/);
    }
  );
});

test('fails (exit 1) on un-allowlisted rnorm( even with set.seed(', () => {
  withTempWorkspace(
    {
      'nfl/build_fake.R': [
        'set.seed(123)',
        'epa_adj <- rnorm(16, mean = 0, sd = 0.05)',
        '',
      ].join('\n'),
    },
    (root, allowPath) => {
      const res = runGuard({ rootDir: root, allowlistPath: allowPath });
      assert.equal(res.status, 1);
      assert.match(res.output, /nfl\/build_fake\.R:2/);
      assert.match(res.output, /\[unreviewed_rng\]/);
      assert.match(res.output, /rnorm\(/);
    }
  );
});

test('fails (exit 1) on un-allowlisted sample(', () => {
  withTempWorkspace(
    {
      'mlb/tools/export_fake.R': [
        'winner <- sample(c("NYY", "LAD"), size = 1)',
        '',
      ].join('\n'),
    },
    (root, allowPath) => {
      const res = runGuard({ rootDir: root, allowlistPath: allowPath });
      assert.equal(res.status, 1);
      assert.match(res.output, /mlb\/tools\/export_fake\.R:1/);
      assert.match(res.output, /\[unreviewed_rng\]/);
      assert.match(res.output, /sample\(/);
    }
  );
});

test('fails (exit 1) on player-name literal conditional grepl("LeBron"', () => {
  withTempWorkspace(
    {
      'nba/build_fake.R': [
        'players$score <- ifelse(grepl("LeBron", players$player_name), 99.0, players$raw_score)',
        '',
      ].join('\n'),
    },
    (root, allowPath) => {
      const res = runGuard({ rootDir: root, allowlistPath: allowPath });
      assert.equal(res.status, 1);
      assert.match(res.output, /nba\/build_fake\.R:1/);
      assert.match(res.output, /\[player_name_override\]/);
      assert.match(res.output, /LeBron/);
    }
  );
});

test('fails (exit 1) on player_name == literal override', () => {
  withTempWorkspace(
    {
      'wnba/build_fake.R': [
        'df$rating <- ifelse(df$player_name == "A\'ja Wilson", 98.5, df$rating)',
        '',
      ].join('\n'),
    },
    (root, allowPath) => {
      const res = runGuard({ rootDir: root, allowlistPath: allowPath });
      assert.equal(res.status, 1);
      assert.match(res.output, /wnba\/build_fake\.R:1/);
      assert.match(res.output, /\[player_name_override\]/);
    }
  );
});

test('fails (exit 1) on affine pmin(pmax( box-score clamp formula', () => {
  withTempWorkspace(
    {
      'nba/build_fake.R': [
        'skill <- pmin(pmax(0.45 * pts_per36 + 0.30 * ast_per36 + 12.0, 40), 99)',
        '',
      ].join('\n'),
    },
    (root, allowPath) => {
      const res = runGuard({ rootDir: root, allowlistPath: allowPath });
      assert.equal(res.status, 1);
      assert.match(res.output, /nba\/build_fake\.R:1/);
      assert.match(res.output, /\[affine_clamp_formula\]/);
      assert.match(res.output, /pmin\(pmax\(/);
    }
  );
});

test('fails (exit 1) on clamp( box-score helper call', () => {
  withTempWorkspace(
    {
      'nfl/export_fake.R': [
        'score <- clamp(0.6 * epa + 50, 15, 99)',
        '',
      ].join('\n'),
    },
    (root, allowPath) => {
      const res = runGuard({ rootDir: root, allowlistPath: allowPath });
      assert.equal(res.status, 1);
      assert.match(res.output, /nfl\/export_fake\.R:1/);
      assert.match(res.output, /\[affine_clamp_formula\]/);
      assert.match(res.output, /clamp\(/);
    }
  );
});

test('fails (exit 1) on un-allowlisted tribble( and numeric c(...) vectors', () => {
  withTempWorkspace(
    {
      'nba/build_fake.R': [
        'weights <- c(0.41, 0.32, 0.27)',
        'overrides <- tribble(~team, ~boost, "BOS", 4.5)',
        '',
      ].join('\n'),
    },
    (root, allowPath) => {
      const res = runGuard({ rootDir: root, allowlistPath: allowPath });
      assert.equal(res.status, 1);
      assert.match(res.output, /nba\/build_fake\.R:1 \[hardcoded_metric_vector\]/);
      assert.match(res.output, /nba\/build_fake\.R:2 \[hardcoded_metric_vector\]/);
    }
  );
});

test('respects R # comments and safe log-loss / PBP / %in% code', () => {
  withTempWorkspace(
    {
      'nba/build_clean.R': [
        '# Purged old fabrication: runif(1); rnorm(5); sample(1:3)',
        '# Never do grepl("LeBron", player_name) or pmin(pmax(pts * 0.5 + 10, 0), 100)',
        '# Nor tribble(~a, 1) or c(1.1, 2.2, 3.3)',
        'hex_palette <- c("#1b9e77", "#d95f02", "#7570b3")',
        'p <- pmin(pmax(raw_prob, 1e-6), 1 - 1e-6)',
        'is_ft <- grepl("Free Throw", type_text, ignore.case = TRUE)',
        'shots <- shots[shots$score_value %in% c(0, 2, 3), ]',
        '',
      ].join('\n'),
    },
    (root, allowPath) => {
      const res = runGuard({ rootDir: root, allowlistPath: allowPath });
      assert.equal(res.status, 0, `Expected pass, got:\n${res.output}`);
      assert.match(res.output, /0 violations/);
    }
  );
});

test('fails (exit 1) when an allow-listed RNG file drops set.seed(', () => {
  withTempWorkspace(
    {
      'wnba/export_web_json.R': [
        'sim <- function(p) if (runif(1) < p) 1L else 0L',
        '',
      ].join('\n'),
    },
    (root) => {
      const res = runGuard({ rootDir: root, allowlistPath: REAL_ALLOWLIST });
      assert.equal(res.status, 1);
      assert.match(res.output, /wnba\/export_web_json\.R:1 \[unreviewed_rng\]/);
      assert.match(res.output, /requires set\.seed\(\)/);
    }
  );
});

test('skips archive/ and renv/ directories and non-builder R files', () => {
  withTempWorkspace(
    {
      'nba/build_ok.R': 'x <- 1 + 1\n',
      'nba/archive/build_old.R': 'x <- runif(1)\n',
      'nba/renv/build_pkg.R': 'x <- rnorm(1)\n',
      'nba/helper_utils.R': 'x <- sample(1:5, 1)\n',
    },
    (root, allowPath) => {
      const res = runGuard({ rootDir: root, allowlistPath: allowPath });
      assert.equal(res.status, 0, `Expected pass, got:\n${res.output}`);
      assert.match(res.output, /scanned 1 R file\(s\)/);
    }
  );
});

test('flags (exit 1) non-build_ writer to web/public/data with runif(', () => {
  withTempWorkspace(
    {
      'nba/publish_custom_metrics.R': [
        'payload <- list(score = runif(5))',
        'jsonlite::write_json(payload, "web/public/data/custom.json")',
        '',
      ].join('\n'),
    },
    (root, allowPath) => {
      const res = runGuard({ rootDir: root, allowlistPath: allowPath });
      assert.equal(res.status, 1);
      assert.match(res.output, /\[SCAN\] nba\/publish_custom_metrics\.R \(reasons: published_writer\)/);
      assert.match(res.output, /nba\/publish_custom_metrics\.R:1 \[unreviewed_rng\]/);
    }
  );
});

test('scans (exit 1) pipeline stage referenced by run_full_pipeline.R', () => {
  withTempWorkspace(
    {
      'nba/run_full_pipeline.R': [
        'run_stage("custom_engine.R", "Run custom engine")',
        '',
      ].join('\n'),
      'nba/custom_engine.R': [
        'val <- rnorm(10)',
        '',
      ].join('\n'),
    },
    (root, allowPath) => {
      const res = runGuard({ rootDir: root, allowlistPath: allowPath });
      assert.equal(res.status, 1);
      assert.match(res.output, /\[SCAN\] nba\/custom_engine\.R \(reasons: pipeline_stage\)/);
      assert.match(res.output, /nba\/custom_engine\.R:1 \[unreviewed_rng\]/);
    }
  );
});

test('does not scan research script outside published path or pipeline', () => {
  withTempWorkspace(
    {
      'nba/build_ok.R': 'x <- 1 + 1\n',
      'nba/research/backtest_experiment.R': [
        'sim <- runif(100)',
        'jsonlite::write_json(list(sim = sim), "cache/research_backtest.json")',
        '',
      ].join('\n'),
    },
    (root, allowPath) => {
      const res = runGuard({ rootDir: root, allowlistPath: allowPath });
      assert.equal(res.status, 0, `Expected pass, got:\n${res.output}`);
      assert.match(res.output, /\[SCAN\] nba\/build_ok\.R \(reasons: build_or_export_floor\)/);
      assert.doesNotMatch(res.output, /backtest_experiment\.R/);
      assert.match(res.output, /scanned 1 R file\(s\)/);
    }
  );
});

test('excluded file requires concrete allowlist justification and passes when justified', () => {
  const files = {
    'nba/build_ok.R': 'x <- 1 + 1\n',
    'nba/tests/test_mock_writer.R': [
      'sim <- runif(3)',
      'jsonlite::write_json(list(sim = sim), file.path(WEB_DATA_DIR, "mock.json"))',
      '',
    ].join('\n'),
  };

  const missingJustAllowlist = JSON.stringify(
    {
      schema_version: '1.0',
      entries: [],
      exclusions: [{ file: 'nba/tests/test_mock_writer.R', justification: 'TODO' }],
    },
    null,
    2
  );
  withTempWorkspace(files, (root, allowPath) => {
    const res = runGuard({ rootDir: root, allowlistPath: allowPath });
    assert.equal(res.status, 1);
    assert.match(res.output, /Allow-list exclusion #0 .* must include a concrete one-line 'justification'/);
  }, missingJustAllowlist);

  const validJustAllowlist = JSON.stringify(
    {
      schema_version: '1.0',
      entries: [],
      exclusions: [
        {
          file: 'nba/tests/test_mock_writer.R',
          justification: 'Unit test fixture writing mock JSON to an isolated temp WEB_DATA_DIR.',
        },
      ],
    },
    null,
    2
  );
  withTempWorkspace(files, (root, allowPath) => {
    const res = runGuard({ rootDir: root, allowlistPath: allowPath });
    assert.equal(res.status, 0, `Expected pass, got:\n${res.output}`);
    assert.match(res.output, /\[EXCLUDED\] nba\/tests\/test_mock_writer\.R/);
    assert.match(res.output, /1 excluded/);
  }, validJustAllowlist);
});

let passed = 0;
for (const { name, fn } of tests) {
  try {
    fn();
    passed += 1;
    console.log(`PASS: ${name}`);
  } catch (err) {
    console.error(`FAIL: ${name}`);
    console.error(err);
    process.exitCode = 1;
  }
}

if (process.exitCode) {
  console.error(`\ntest_check_fabrication_idioms: FAILED (${passed}/${tests.length} passed)`);
} else {
  console.log(`\ntest_check_fabrication_idioms: OK (${passed}/${tests.length} tests passed)`);
}
