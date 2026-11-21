/**
 * Static guard: /player-dna publishes no hand-typed comparables.
 *
 * mlb_player_dna_engine.R once matched current players against two hand-typed `tribble()`
 * tables of 16 batter and 16 pitcher "historical twins", each with an invented 16-number
 * skill vector. This test reads the engine as text and fails if a `tribble(` block holding a
 * quoted name next to a numeric `c(` vector is (re)introduced, if inputs are selected by glob
 * or by a literal season, or if the engine calls stop() (a failing stage must log a
 * `>>> [FAIL]` line instead, so the pipeline exit code is untouched). It also checks that the
 * published payload and the page code no longer carry the old historical-twin fields.
 * Modelled on NFL_analytics web/tests/contracts/no-hand-typed-comps.test.ts.
 */
import { describe, expect, it } from 'vitest';
import fs from 'fs';
import path from 'path';

const REPO_ROOT = path.resolve(__dirname, '../../..');
const ENGINE = path.join(REPO_ROOT, 'mlb_player_dna_engine.R');
const WEB_ROOT = path.join(REPO_ROOT, 'web');

/** Drop R comments (a `#` outside a string starts one). */
export function stripComments(src: string): string {
  return src
    .split('\n')
    .map((line) => {
      let quote: string | null = null;
      for (let i = 0; i < line.length; i++) {
        const ch = line[i];
        if (quote) {
          if (ch === '\\') i++;
          else if (ch === quote) quote = null;
        } else if (ch === '"' || ch === "'" || ch === '`') quote = ch;
        else if (ch === '#') return line.slice(0, i);
      }
      return line;
    })
    .join('\n');
}

/** Bodies of every `tribble(...)` call, using balanced parentheses. */
export function tribbleBodies(src: string): string[] {
  const code = stripComments(src);
  const bodies: string[] = [];
  const re = /\btribble\s*\(/g;
  let m: RegExpExecArray | null;
  while ((m = re.exec(code)) !== null) {
    let depth = 1;
    let i = m.index + m[0].length;
    const start = i;
    while (i < code.length && depth > 0) {
      if (code[i] === '(') depth++;
      else if (code[i] === ')') depth--;
      i++;
    }
    bodies.push(code.slice(start, i - 1));
  }
  return bodies;
}

/** True when a tribble body holds a quoted string and a numeric c(...) vector. */
export function isNamedPlayerVectorTable(body: string): boolean {
  const hasQuotedName = /"[^"\n]*[A-Za-z]{2,}[^"\n]*"/.test(body);
  const hasNumericVector = /\bc\(\s*-?\d+(\.\d+)?(\s*,\s*-?\d+(\.\d+)?){2,}\s*\)/.test(body);
  return hasQuotedName && hasNumericVector;
}

describe('mlb_player_dna_engine.R has no hand-typed comparable vectors', () => {
  const src = fs.readFileSync(ENGINE, 'utf-8');
  const code = stripComments(src);

  it('contains no tribble() with a quoted name next to a numeric c() vector', () => {
    const offenders = tribbleBodies(src).filter(isNamedPlayerVectorTable);
    expect(offenders, 'hand-typed player vectors reintroduced in mlb_player_dna_engine.R').toHaveLength(0);
  });

  it('detector flags the pattern it guards against', () => {
    const bad = `batter_comps <- tribble(
      ~comp_name, ~era, ~dna_vector,
      "Some Legend (1990-94 XXX)", "1990-94", c(99, 92, 85, 90, 96)
    )`;
    expect(tribbleBodies(bad).some(isNamedPlayerVectorTable)).toBe(true);
    const harmless = `x <- tribble(~a, ~b, 1, 2)`;
    expect(tribbleBodies(harmless).some(isNamedPlayerVectorTable)).toBe(false);
  });

  it('never selects inputs with a glob, a directory listing or a literal season', () => {
    expect(code).not.toMatch(/Sys\.glob/);
    expect(code).not.toMatch(/list\.files/);
    expect(code).not.toMatch(/\b(19|20)\d{2}\b/);
    expect(code).toMatch(/MLB_CURRENT_SEASON/);
  });

  it('never reads another checkout', () => {
    expect(code).not.toMatch(/MLB Analytics/);
    expect(code).not.toMatch(/"\.\."/);
  });

  it('logs >>> [FAIL] instead of calling stop()', () => {
    expect(code).not.toMatch(/\bstop\s*\(/);
    expect(code).toMatch(/>>> \[FAIL\]/);
  });
});

describe('published /player-dna payload and page carry no historical-twin fields', () => {
  it('player_dna_profiles.json has peerComps and no historicalTwins / era fields', () => {
    const raw = fs.readFileSync(path.join(WEB_ROOT, 'public', 'data', 'player_dna_profiles.json'), 'utf-8');
    expect(raw).not.toMatch(/historicalTwins|eraBaseline|"era"\s*:/);
    expect(raw).toMatch(/"peerComps"\s*:/);
  });

  it('page, components and types no longer mention historical twins or a 1980 era', () => {
    const files = [
      'app/player-dna/page.tsx',
      'components/PlayerDnaClient.tsx',
      'components/PeerCompCard.tsx',
      'components/DnaManifoldScatter.tsx',
      'components/SkillFingerprintPolygon.tsx',
      'lib/playerDnaTypes.ts',
    ];
    for (const f of files) {
      const txt = fs.readFileSync(path.join(WEB_ROOT, f), 'utf-8');
      expect(txt, f).not.toMatch(/historical\s*twin|historicalTwins|1980|legends?\b|16-D/i);
    }
  });
});
