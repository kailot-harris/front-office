/**
 * Layer 3 — cross-dataset referential integrity.
 *
 * Ten independently-generated JSON files all key on team identity, and
 * `lib/teams.ts` holds an eleventh copy of that key space (the one every
 * `<TeamLogo>`, colour swatch and tooltip resolves against). CLAUDE.md flags
 * NFL player/team ID reconciliation as this project's largest join hazard —
 * four competing ID schemes — so every join point gets an explicit assertion
 * here rather than being trusted to "just work".
 */
import { describe, expect, it } from 'vitest';
import { NFL_TEAMS_METADATA, getTeamColors, getTeamLogoUrl } from '../../lib/teams';
import {
  LEAGUE,
  coaching,
  matchups,
  playoffs,
  qbs,
  salaryCap,
  standings,
  teamEpa,
  valueBets,
} from '../helpers/datasets';

const KNOWN = new Set(Object.keys(NFL_TEAMS_METADATA));

/** Every place a team code enters the app, with the dataset it came from. */
const TEAM_CODE_SOURCES: Array<[string, () => string[]]> = [
  ['standings_projections.teams[].team', () => standings().teams.map((t) => t.team)],
  ['matchups_current_week.matchups[].home_team', () => matchups().matchups.map((m) => m.home_team)],
  ['matchups_current_week.matchups[].away_team', () => matchups().matchups.map((m) => m.away_team)],
  ['team_epa_profiles[].team', () => teamEpa().map((t) => t.team)],
  ['playoff_picture.afc_seeds[].team', () => playoffs().afc_seeds.map((s) => s.team)],
  ['playoff_picture.nfc_seeds[].team', () => playoffs().nfc_seeds.map((s) => s.team)],
  ['playoff_picture.afc_bubble[].team', () => playoffs().afc_bubble.map((b) => b.team)],
  ['playoff_picture.nfc_bubble[].team', () => playoffs().nfc_bubble.map((b) => b.team)],
  ['player_qb_profiles[].team', () => qbs().map((q) => q.team)],
  ['coaching_profiles[].team', () => coaching().map((c) => c.team)],
  ['salary_cap_profiles.teams[].team', () => salaryCap().teams.map((t) => t.team)],
  ['salary_cap_profiles.top_league_contracts[].team', () => salaryCap().top_league_contracts.map((c) => c.team)],
];

describe('every team code resolves against lib/teams.ts', () => {
  it.each(TEAM_CODE_SOURCES)('%s', (label, get) => {
    const unknown = [...new Set(get())].filter((code) => !KNOWN.has(code)).sort();
    expect(
      unknown,
      `${label} uses team code(s) ${JSON.stringify(unknown)} that NFL_TEAMS_METADATA does not define. ` +
        `<TeamLogo> falls back to the raw code for alt text/tooltip and to the default emerald palette ` +
        `for colours, so these render degraded rather than failing loudly.`,
    ).toEqual([]);
  });
});

describe('the datasets agree with each other on team identity', () => {
  it('standings, EPA, coaching and salary-cap all cover the same 32 franchises', () => {
    const sets = {
      standings: new Set(standings().teams.map((t) => t.team)),
      team_epa: new Set(teamEpa().map((t) => t.team)),
      coaching: new Set(coaching().map((c) => c.team)),
      salary_cap: new Set(salaryCap().teams.map((t) => t.team)),
    };
    const reference = sets.standings;
    const diffs: string[] = [];
    for (const [name, set] of Object.entries(sets)) {
      const missing = [...reference].filter((t) => !set.has(t));
      const extra = [...set].filter((t) => !reference.has(t));
      if (missing.length || extra.length) {
        diffs.push(`${name}: missing ${JSON.stringify(missing)}, unexpected ${JSON.stringify(extra)}`);
      }
    }
    expect(diffs, 'the per-page datasets disagree on the league roster').toEqual([]);
  });

  it('team_name strings are identical wherever a dataset repeats them', () => {
    const canonical = new Map(standings().teams.map((t) => [t.team, t.team_name]));
    const diffs: string[] = [];
    const check = (label: string, code: string, name: string) => {
      const want = canonical.get(code);
      if (want && want !== name) diffs.push(`${label} ${code}: "${name}" vs standings "${want}"`);
    };
    for (const t of teamEpa()) check('team_epa_profiles', t.team, t.team_name);
    for (const s of [...playoffs().afc_seeds, ...playoffs().nfc_seeds]) check('playoff seeds', s.team, s.team_name);
    for (const b of [...playoffs().afc_bubble, ...playoffs().nfc_bubble]) check('playoff bubble', b.team, b.team_name);
    for (const m of matchups().matchups) {
      check('matchups home', m.home_team, m.home_team_name);
      check('matchups away', m.away_team, m.away_team_name);
    }
    expect(diffs.slice(0, 10)).toEqual([]);
  });

  it('lib/teams.ts fullName matches the team_name the data ships', () => {
    const diffs = standings()
      .teams.filter((t) => NFL_TEAMS_METADATA[t.team]?.fullName !== t.team_name)
      .map((t) => `${t.team}: data "${t.team_name}" vs lib/teams.ts "${NFL_TEAMS_METADATA[t.team]?.fullName}"`);
    expect(diffs).toEqual([]);
  });

  it('lib/teams.ts division/conference matches the data', () => {
    const diffs = standings()
      .teams.filter((t) => {
        const meta = NFL_TEAMS_METADATA[t.team];
        return meta && (meta.division !== t.division || meta.conference !== t.conference);
      })
      .map((t) => `${t.team}: data ${t.conference}/${t.division} vs metadata ${NFL_TEAMS_METADATA[t.team].conference}/${NFL_TEAMS_METADATA[t.team].division}`);
    expect(diffs).toEqual([]);
  });

  it('value_bets.team uses the same ID space as every other dataset', () => {
    // ValueBet.team is typed as a bare `string` in lib/types.ts, which hides
    // the fact that this file carries FULL TEAM NAMES while every other
    // dataset carries 2-3 letter codes. Wiring value_bets into a component
    // that renders <TeamLogo team={bet.team}> would break on all 32 teams.
    const codes = [...new Set(valueBets().active_bets.map((b) => b.team))];
    const nonCodes = codes.filter((c) => !KNOWN.has(c));
    expect(
      nonCodes.slice(0, 5),
      `value_bets.json identifies teams by full name (e.g. ${JSON.stringify(nonCodes[0] ?? '')}) ` +
        `rather than by the abbreviation used everywhere else.`,
    ).toEqual([]);
  });
});

describe('lib/teams.ts internal consistency', () => {
  const metas = Object.values(NFL_TEAMS_METADATA);

  it(`defines exactly ${LEAGUE.TEAM_COUNT} franchises`, () => {
    expect(metas).toHaveLength(LEAGUE.TEAM_COUNT);
  });

  it('record key always equals the abbr field', () => {
    const diffs = Object.entries(NFL_TEAMS_METADATA)
      .filter(([key, meta]) => key !== meta.abbr)
      .map(([key, meta]) => `key "${key}" vs abbr "${meta.abbr}"`);
    expect(diffs).toEqual([]);
  });

  it('every espnCode is unique and lowercase', () => {
    const codes = metas.map((m) => m.espnCode);
    expect(codes.filter((c) => c !== c.toLowerCase())).toEqual([]);
    expect(codes.filter((c, i) => codes.indexOf(c) !== i)).toEqual([]);
  });

  it('every fullName is unique', () => {
    const names = metas.map((m) => m.fullName);
    expect(names.filter((n, i) => names.indexOf(n) !== i)).toEqual([]);
  });

  it('fullName is consistent with city and name', () => {
    const diffs = metas
      .filter((m) => m.fullName !== `${m.city} ${m.name}`)
      .map((m) => `${m.abbr}: "${m.fullName}" != "${m.city} ${m.name}"`);
    expect(diffs).toEqual([]);
  });

  it('divisions hold exactly 4 teams and match their conference', () => {
    const byDiv: Record<string, number> = {};
    for (const m of metas) {
      byDiv[m.division] = (byDiv[m.division] ?? 0) + 1;
      expect(m.division.startsWith(m.conference), `${m.abbr}: ${m.division} vs ${m.conference}`).toBe(true);
    }
    expect(Object.keys(byDiv)).toHaveLength(LEAGUE.DIVISION_COUNT);
    for (const [div, n] of Object.entries(byDiv)) expect(n, div).toBe(LEAGUE.TEAMS_PER_DIVISION);
  });

  it('every colour is a 6-digit hex triple', () => {
    const bad: string[] = [];
    for (const m of metas) {
      for (const [slot, value] of Object.entries(m.colors)) {
        if (!/^#[0-9A-Fa-f]{6}$/.test(value)) bad.push(`${m.abbr}.${slot} = "${value}"`);
      }
    }
    expect(bad).toEqual([]);
  });

  it('primary and secondary colours are not identical', () => {
    const bad = metas.filter((m) => m.colors.primary === m.colors.secondary).map((m) => m.abbr);
    expect(bad).toEqual([]);
  });
});

describe('lib/teams.ts helper behaviour', () => {
  it('getTeamLogoUrl maps every known code onto its espnCode', () => {
    for (const meta of Object.values(NFL_TEAMS_METADATA)) {
      expect(getTeamLogoUrl(meta.abbr)).toBe(`https://a.espncdn.com/i/teamlogos/nfl/500/${meta.espnCode}.png`);
    }
  });

  it('getTeamLogoUrl is case-insensitive', () => {
    expect(getTeamLogoUrl('kc')).toBe(getTeamLogoUrl('KC'));
    expect(getTeamLogoUrl('Was')).toBe(getTeamLogoUrl('WAS'));
  });

  it('getTeamLogoUrl degrades to a lowercased code for an unknown team', () => {
    // This is why the LAR/LA mismatch does not produce a visibly broken image:
    // "LAR" is not a metadata key, but it happens to be a valid ESPN slug.
    expect(getTeamLogoUrl('LAR')).toBe('https://a.espncdn.com/i/teamlogos/nfl/500/lar.png');
  });

  it('getTeamLogoUrl never throws on empty or nullish input', () => {
    expect(() => getTeamLogoUrl('')).not.toThrow();
    expect(() => getTeamLogoUrl(undefined as unknown as string)).not.toThrow();
  });

  it('getTeamColors returns the real palette for a known team', () => {
    expect(getTeamColors('KC')).toEqual(NFL_TEAMS_METADATA.KC.colors);
    expect(getTeamColors('kc')).toEqual(NFL_TEAMS_METADATA.KC.colors);
  });

  it('getTeamColors falls back to a neutral palette for an unknown team', () => {
    const fallback = getTeamColors('ZZZ');
    expect(fallback).toEqual({ primary: '#10b981', secondary: '#059669', accent: '#022c22' });
    expect(getTeamColors(undefined as unknown as string)).toEqual(fallback);
  });

  it('the LAR fallback palette is NOT the Rams palette (the visible symptom)', () => {
    // Documents the user-facing consequence of the LA/LAR code mismatch on
    // /salary-cap: the Rams render in the generic emerald fallback.
    expect(getTeamColors('LAR')).not.toEqual(NFL_TEAMS_METADATA.LA.colors);
  });
});
