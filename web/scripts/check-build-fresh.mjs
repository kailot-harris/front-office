#!/usr/bin/env node
/**
 * check-build-fresh.mjs
 *
 * Guards against serving a stale static export.
 *
 * `next.config.mjs` sets `output: 'export'`, so `npm run build` writes the whole
 * site into `web/out/`. That directory is gitignored, so `git status` stays
 * silent when it is stale and a local preview can happily serve month-old data
 * while the JSON in `web/public/data/` and the components are already correct
 * (GitHub issue #21).
 *
 * This check compares the newest mtime under the output directory against the
 * newest mtime under the data directory and fails when the output is older or
 * missing.
 *
 * Usage:
 *   node scripts/check-build-fresh.mjs [--out <dir>] [--data <dir>]
 *
 * Defaults (relative to the `web/` directory that contains this script's
 * parent): --out out  --data public/data
 */

import { readdir, stat } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const SCRIPT_DIR = path.dirname(fileURLToPath(import.meta.url));
const WEB_DIR = path.resolve(SCRIPT_DIR, '..');

const USAGE = 'Usage: node scripts/check-build-fresh.mjs [--out <dir>] [--data <dir>]';

function parseArgs(argv) {
  const opts = { out: null, data: null };
  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];
    if (arg === '--out' || arg === '--data') {
      const value = argv[i + 1];
      if (!value || value.startsWith('--')) {
        throw new Error(`Missing value for ${arg}. ${USAGE}`);
      }
      opts[arg.slice(2)] = value;
      i += 1;
    } else if (arg.startsWith('--out=')) {
      opts.out = arg.slice('--out='.length);
    } else if (arg.startsWith('--data=')) {
      opts.data = arg.slice('--data='.length);
    } else if (arg === '--help' || arg === '-h') {
      process.stdout.write(`${USAGE}\n`);
      process.exit(0);
    } else {
      throw new Error(`Unrecognized argument: ${arg}. ${USAGE}`);
    }
  }
  return opts;
}

/**
 * Walk a directory tree and return the newest file mtime (ms) plus the file
 * that carried it. Returns null when the tree contains no files at all.
 */
async function newestFile(dir) {
  let newest = null;
  const stack = [dir];
  while (stack.length > 0) {
    const current = stack.pop();
    const entries = await readdir(current, { withFileTypes: true });
    for (const entry of entries) {
      const full = path.join(current, entry.name);
      if (entry.isDirectory()) {
        stack.push(full);
      } else if (entry.isFile()) {
        const info = await stat(full);
        if (newest === null || info.mtimeMs > newest.mtimeMs) {
          newest = { file: full, mtimeMs: info.mtimeMs };
        }
      }
    }
  }
  return newest;
}

async function directoryExists(dir) {
  try {
    const info = await stat(dir);
    return info.isDirectory();
  } catch (err) {
    if (err.code === 'ENOENT' || err.code === 'ENOTDIR') return false;
    throw err;
  }
}

function fail(lines) {
  for (const line of lines) {
    process.stderr.write(`${line}\n`);
  }
  process.exit(1);
}

async function main() {
  let opts;
  try {
    opts = parseArgs(process.argv.slice(2));
  } catch (err) {
    process.stderr.write(`${err.message}\n`);
    process.exit(2);
    return;
  }

  const outDir = path.resolve(opts.out ?? path.join(WEB_DIR, 'out'));
  const dataDir = path.resolve(opts.data ?? path.join(WEB_DIR, 'public', 'data'));

  if (!(await directoryExists(outDir))) {
    fail([
      `check-build-fresh: no static export found at ${outDir}`,
      'The site has never been built here (or the export was removed).',
      'Run `npm run build` in web/ before serving or deploying.',
    ]);
    return;
  }

  if (!(await directoryExists(dataDir))) {
    fail([
      `check-build-fresh: data directory not found at ${dataDir}`,
      'Pass --data <dir> or regenerate the JSON data the site is built from.',
    ]);
    return;
  }

  const newestOut = await newestFile(outDir);
  const newestData = await newestFile(dataDir);

  if (newestData === null) {
    process.stdout.write(
      `check-build-fresh: OK - data directory ${dataDir} contains no files, nothing can be stale.\n`,
    );
    return;
  }

  if (newestOut === null) {
    fail([
      `check-build-fresh: static export directory ${outDir} is empty`,
      `Data directory ${dataDir} has files (newest: ${newestData.file}).`,
      'Run `npm run build` in web/ before serving or deploying.',
    ]);
    return;
  }

  if (newestOut.mtimeMs <= newestData.mtimeMs) {
    const lagMs = newestData.mtimeMs - newestOut.mtimeMs;
    const lagMin = (lagMs / 60000).toFixed(1);
    fail([
      'check-build-fresh: FAIL - the static export is stale.',
      `  stale output directory: ${outDir}`,
      `    newest file: ${newestOut.file} (${new Date(newestOut.mtimeMs).toISOString()})`,
      `  newer data directory:   ${dataDir}`,
      `    newest file: ${newestData.file} (${new Date(newestData.mtimeMs).toISOString()})`,
      `  the data is ${lagMin} minute(s) newer than the build output.`,
      `${outDir} is gitignored, so git status will not warn you about this.`,
      'Run `npm run build` in web/ before serving or deploying.',
    ]);
    return;
  }

  const aheadMin = ((newestOut.mtimeMs - newestData.mtimeMs) / 60000).toFixed(1);
  process.stdout.write(
    `check-build-fresh: OK - static export is newer than the data it was built from.\n`,
  );
  process.stdout.write(`  output: ${newestOut.file} (${new Date(newestOut.mtimeMs).toISOString()})\n`);
  process.stdout.write(`  data:   ${newestData.file} (${new Date(newestData.mtimeMs).toISOString()})\n`);
  process.stdout.write(`  output is ${aheadMin} minute(s) newer than the newest data file.\n`);
}

main().catch((err) => {
  process.stderr.write(`check-build-fresh: unexpected error: ${err?.stack ?? err}\n`);
  process.exit(2);
});
