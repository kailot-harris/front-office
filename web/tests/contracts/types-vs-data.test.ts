/**
 * Layer 1b — does `lib/types.ts` still tell the truth about the data?
 *
 * `lib/data.ts` reads every dataset with `JSON.parse(...) as T`, which means a
 * declared union in `lib/types.ts` is an unchecked promise, not a constraint.
 * If the R export starts emitting a value outside the union, the compiler stays
 * green and any `switch`/lookup keyed on that union silently falls through.
 *
 * These tests read the union literals straight out of the `lib/types.ts`
 * SOURCE and compare them against the distinct values actually present in
 * `public/data/`, so the declaration and the data cannot drift apart unnoticed.
 */
import { describe, expect, it } from 'vitest';
import fs from 'fs';
import path from 'path';
import { REPO_WEB_ROOT, coaching, matchups, media, qbs, standings, teamEpa } from '../helpers/datasets';

const TYPES_SRC = fs.readFileSync(path.join(REPO_WEB_ROOT, 'lib', 'types.ts'), 'utf-8');

/**
 * Pull the string-literal union declared for `field` out of the types source.
 * e.g. `play_caller: 'Head Coach' | 'Offensive Coordinator';` -> both literals.
 */
function declaredUnion(field: string): string[] {
  const re = new RegExp(`^\\s*${field}\\??:\\s*([^;]+);`, 'm');
  const m = TYPES_SRC.match(re);
  if (!m) throw new Error(`could not find a declaration for "${field}" in lib/types.ts`);
  const literals = m[1].match(/'([^']*)'/g);
  if (!literals) throw new Error(`"${field}" in lib/types.ts is not a string-literal union: ${m[1].trim()}`);
  return literals.map((l) => l.slice(1, -1));
}

const distinct = (values: readonly (string | undefined)[]): string[] =>
  Array.from(new Set(values.filter((v): v is string => typeof v === 'string'))).sort();

describe('lib/types.ts string unions cover every value in the data', () => {
  it('CoachProfile.timeout_management_grade', () => {
    const declared = declaredUnion('timeout_management_grade');
    const actual = distinct(coaching().map((c) => c.timeout_management_grade));
    const uncovered = actual.filter((v) => !declared.includes(v));
    expect(
      uncovered,
      `coaching_profiles.json emits grade(s) ${JSON.stringify(uncovered)} that lib/types.ts does not declare. ` +
        `Declared: ${JSON.stringify(declared)}. Widen the union (or fix the export).`,
    ).toEqual([]);
  });

  it('CoachProfile.play_caller', () => {
    const declared = declaredUnion('play_caller');
    const actual = distinct(coaching().map((c) => c.play_caller));
    expect(actual.filter((v) => !declared.includes(v))).toEqual([]);
  });

  it('CoachProfile.offensive_play_caller / defensive_play_caller', () => {
    const offDeclared = declaredUnion('offensive_play_caller');
    const defDeclared = declaredUnion('defensive_play_caller');
    expect(distinct(coaching().map((c) => c.offensive_play_caller)).filter((v) => !offDeclared.includes(v))).toEqual([]);
    expect(distinct(coaching().map((c) => c.defensive_play_caller)).filter((v) => !defDeclared.includes(v))).toEqual([]);
  });

  it('VisualMediaItem.category and .type', () => {
    const catDeclared = declaredUnion('category');
    const typeDeclared = declaredUnion('type');
    expect(distinct(media().map((m) => m.category)).filter((v) => !catDeclared.includes(v))).toEqual([]);
    expect(distinct(media().map((m) => m.type)).filter((v) => !typeDeclared.includes(v))).toEqual([]);
  });

  it('conference unions on TeamStanding and TeamEpaProfile', () => {
    const declared = declaredUnion('conference');
    expect(distinct(standings().teams.map((t) => t.conference)).filter((v) => !declared.includes(v))).toEqual([]);
    expect(distinct(teamEpa().map((t) => t.conference)).filter((v) => !declared.includes(v))).toEqual([]);
  });
});

describe('lib/types.ts optional fields reflect real optionality', () => {
  it('QbProfile.is_starter / attempts_2026 are declared optional and are in fact always present', () => {
    // Both are declared `?:` in lib/types.ts. If the export always supplies
    // them, the optional marker forces needless `?? 0` guards at every call
    // site; if it ever stops supplying them, those guards are load-bearing.
    // Either way the suite records which world we are in.
    const rows = qbs();
    const missingStarter = rows.filter((q) => q.is_starter === undefined).length;
    const missingAttempts = rows.filter((q) => q.attempts_2026 === undefined).length;
    expect({ missingStarter, missingAttempts }).toEqual({ missingStarter: 0, missingAttempts: 0 });
  });

  it('MatchupGame completion fields travel together', () => {
    // A game is either fully graded (both scores + winner + correctness) or
    // carries none of them. A half-populated row would make MatchupCard render
    // a score box with a blank in it.
    const broken = matchups().matchups.filter((m) => {
      const graded = [m.home_score, m.away_score, m.actual_winner, m.prediction_correct];
      const present = graded.filter((k) => k !== undefined && k !== null).length;
      return present !== 0 && present !== graded.length;
    });
    expect(
      broken.map((m) => m.game_id),
      'these games are partially graded — MatchupCard would render blank scores',
    ).toEqual([]);
  });

  it('is_completed agrees with whether the score fields are populated', () => {
    const offenders = matchups().matchups
      .filter((m) => Boolean(m.is_completed) !== (m.home_score !== null && m.home_score !== undefined))
      .map((m) => `${m.game_id}: is_completed=${m.is_completed} but home_score=${m.home_score}`);
    expect(offenders.slice(0, 10)).toEqual([]);
  });

  it('ungraded games use null, which lib/types.ts does not admit', () => {
    // This records the single most load-bearing type inaccuracy in the app:
    // `home_score?: number` says the field is `number | undefined`, but the
    // export ships `null`. Every consumer in components/ currently guards with
    // `is_completed` or `=== true`, so nothing renders wrong today — but a
    // future `if (m.home_score !== undefined)` check would be silently true
    // for all 180 unplayed games.
    //
    // Fix: widen lib/types.ts to `home_score?: number | null` (and the same
    // for away_score / actual_winner / prediction_correct), then delete this
    // test's expectation that nulls are present.
    const ungraded = matchups().matchups.filter((m) => !m.is_completed);
    expect(ungraded.length, 'no ungraded games in the dataset to inspect').toBeGreaterThan(0);

    const declaresNull = /home_score\?:[^;]*\bnull\b/.test(TYPES_SRC);
    const shipsNull = ungraded.every((m) => m.home_score === null);

    expect(
      !shipsNull || declaresNull,
      shipsNull
        ? 'matchups_current_week.json ships null scores for ungraded games, but lib/types.ts ' +
          'declares `home_score?: number` (no null). Widen the type.'
        : 'lib/types.ts now admits null but the data no longer ships it — tighten the type back.',
    ).toBe(true);
  });
});
