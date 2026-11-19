/**
 * Static guard for NFL_analytics #79.
 *
 * The /dna builder once published "historical comparables" computed against 29 hand-typed
 * five-number vectors for named players. This test reads the builder as text and fails if a
 * `tribble(` block holding a quoted player-name string next to a numeric `c(` vector is
 * (re)introduced. Comps must come from real players in the same season window.
 */
import { describe, expect, it } from 'vitest';
import fs from 'fs';
import path from 'path';

const BUILDER = path.resolve(__dirname, '../../../build_player_dna_dataset.R');

/** Drop R comments (a `#` outside a string starts one). */
function stripComments(src: string): string {
  return src
    .split('\n')
    .map((line) => {
      let quote: string | null = null;
      for (let i = 0; i < line.length; i++) {
        const ch = line[i];
        if (quote) {
          if (ch === '\\') i++;
          else if (ch === quote) quote = null;
        } else if (ch === '"' || ch === "'") quote = ch;
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

describe('build_player_dna_dataset.R has no hand-typed comparable vectors (#79)', () => {
  const src = fs.readFileSync(BUILDER, 'utf-8');

  it('contains no tribble() with a quoted name next to a numeric c() vector', () => {
    const offenders = tribbleBodies(src).filter(isNamedPlayerVectorTable);
    expect(offenders, 'hand-typed player vectors reintroduced in build_player_dna_dataset.R').toHaveLength(0);
  });

  it('detector flags the pattern it guards against', () => {
    const bad = `qb_comps <- tribble(
      ~comp_name, ~era, ~dna_vector,
      "Patrick Mahomes (2018 KC)", "2018", c(97, 92, 85, 90, 96)
    )`;
    expect(tribbleBodies(bad).some(isNamedPlayerVectorTable)).toBe(true);
    const harmless = `x <- tribble(~a, ~b, 1, 2)`;
    expect(tribbleBodies(harmless).some(isNamedPlayerVectorTable)).toBe(false);
  });

  it('never selects inputs with a glob or a literal season', () => {
    const code = stripComments(src);
    expect(code).not.toMatch(/Sys\.glob/);
    expect(code).not.toMatch(/seasons\s*=\s*20\d{2}/);
  });
});
