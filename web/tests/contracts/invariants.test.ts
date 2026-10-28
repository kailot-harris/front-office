/**
 * Layer 2 — statistical and structural invariants.
 *
 * Schema validation only proves each number is *in range*. These tests prove
 * the numbers are mutually *coherent*: mutually-exclusive outcomes summing to
 * one, complementary win probabilities, percentiles ordered, declared totals
 * reconciling with their parts.
 *
 * This is the layer that catches a plausible-looking but wrong export — the
 * failure mode that a schema check and a page render both sail straight past.
 */
import { describe, expect, it } from 'vitest';
import {
  LEAGUE,
  coaching,
  diagnostics,
  groupBy,
  matchups,
  playoffs,
  qbs,
  salaryCap,
  standings,
  sumBy,
  teamEpa,
} from '../helpers/datasets';

/** Tolerance for probabilities the export rounds to 3-4 decimals, per team. */
const roundingSlack = (n: number, dp = 3) => (n * 0.5) / 10 ** dp;

describe('standings — league structure', () => {
  const d = standings();

  it(`contains exactly ${LEAGUE.TEAM_COUNT} teams, one per franchise`, () => {
    expect(d.teams).toHaveLength(LEAGUE.TEAM_COUNT);
    expect(new Set(d.teams.map((t) => t.team)).size).toBe(LEAGUE.TEAM_COUNT);
  });

  it(`splits ${LEAGUE.TEAM_COUNT / 2} teams per conference`, () => {
    for (const conf of LEAGUE.CONFERENCES) {
      expect(d.teams.filter((t) => t.conference === conf)).toHaveLength(LEAGUE.TEAM_COUNT / 2);
    }
  });

  it(`has ${LEAGUE.DIVISION_COUNT} divisions of ${LEAGUE.TEAMS_PER_DIVISION}`, () => {
    const byDiv = groupBy(d.teams, (t) => t.division);
    expect(Object.keys(byDiv)).toHaveLength(LEAGUE.DIVISION_COUNT);
    for (const [div, teams] of Object.entries(byDiv)) {
      expect(teams, `${div} has ${teams.length} teams`).toHaveLength(LEAGUE.TEAMS_PER_DIVISION);
    }
  });

  it('division names agree with the conference field', () => {
    for (const t of d.teams) {
      expect(t.division.startsWith(t.conference), `${t.team}: ${t.division} vs ${t.conference}`).toBe(true);
    }
  });

  it('rank is a dense 1..32 permutation', () => {
    const ranks = d.teams.map((t) => t.rank).sort((a, b) => a - b);
    expect(ranks).toEqual(Array.from({ length: LEAGUE.TEAM_COUNT }, (_, i) => i + 1));
  });

  it('rank ordering is consistent with power_rating (rank 1 = strongest)', () => {
    const byRank = [...d.teams].sort((a, b) => a.rank - b.rank);
    for (let i = 1; i < byRank.length; i++) {
      expect(
        byRank[i - 1].power_rating,
        `rank ${byRank[i - 1].rank} (${byRank[i - 1].team}) is rated below rank ${byRank[i].rank} (${byRank[i].team})`,
      ).toBeGreaterThanOrEqual(byRank[i].power_rating);
    }
  });
});

describe('standings — per-team arithmetic', () => {
  const teams = standings().teams;

  it('point_diff === points_for - points_against', () => {
    for (const t of teams) {
      expect(t.point_diff, `${t.team}`).toBe(t.points_for - t.points_against);
    }
  });

  it('net_epa_roll === off_epa_roll - def_epa_roll', () => {
    for (const t of teams) {
      // Each component is rounded to 3dp independently upstream, so the
      // derived difference can legitimately be off by up to 0.001.
      expect(Math.abs(t.net_epa_roll - (t.off_epa_roll - t.def_epa_roll)), `${t.team}`)
        .toBeLessThanOrEqual(0.0011);
    }
  });

  it('wins_p10 <= projected_wins <= wins_p90', () => {
    for (const t of teams) {
      expect(t.wins_p10, `${t.team} p10 above mean`).toBeLessThanOrEqual(t.projected_wins);
      expect(t.wins_p90, `${t.team} p90 below mean`).toBeGreaterThanOrEqual(t.projected_wins);
    }
  });

  it('win_pct_pyth === projected_wins / 17', () => {
    for (const t of teams) {
      expect(t.win_pct_pyth, `${t.team}`).toBeCloseTo(t.projected_wins / LEAGUE.SEASON_GAMES, 2);
    }
  });

  it('games_played equals the schedule-derived completed-game count, per team', () => {
    // RULE: for every team, games_played === schedule_games_completed. Exactly. No slack.
    //
    // These are two independent derivations of the same quantity. games_played travels the
    // model's team-stats path (team_ratings_engine.R -> ratings_df -> export);
    // schedule_games_completed is counted straight off CACHE_SCHEDULES by the exporter
    // (CURRENT_SEASON, game_type == 'REG', both final scores non-NA). If the published payload
    // was assembled from caches that are out of step with each other - the classic case being
    // ratings carried over from an earlier run while the schedule moved on - the two disagree
    // and this test names the teams.
    //
    // Why not the old rule: this check used to be a league-wide spread heuristic (max - min <= 2,
    // with the trailing cohort capped at teams/4). That was a proxy, and a proxy with a shelf
    // life - the trailing cohort is every team whose bye has already passed, which grows all
    // season, so by roughly week 11 the bound would have tripped on perfectly correct data
    // (issue #44). A test that false-fails cannot gate the daily redeploy. The schedule is
    // ground truth; compare against it instead of guessing from the shape of the distribution.
    const mismatched = teams
      .filter((t) => t.games_played !== t.schedule_games_completed)
      .map((t) => `${t.team}: games_played=${t.games_played} vs schedule=${t.schedule_games_completed}`);
    expect(
      mismatched,
      'games_played disagrees with the schedule-derived completed-game count. One of the ' +
        'upstream caches is stale relative to the other - re-run the pipeline rather than ' +
        'relaxing this assertion. Offenders: ' + mismatched.join('; '),
    ).toEqual([]);

    // Sanity floor on the ground-truth field itself: a team cannot have played more than the
    // regular season is long, and all 32 franchises must be represented.
    expect(teams).toHaveLength(LEAGUE.TEAM_COUNT);
    for (const t of teams) {
      expect(t.schedule_games_completed, `${t.team} schedule count out of range`)
        .toBeGreaterThanOrEqual(0);
      expect(t.schedule_games_completed, `${t.team} schedule count out of range`)
        .toBeLessThanOrEqual(LEAGUE.SEASON_GAMES);
    }
  });

  it('deeper playoff rounds are never more likely than shallower ones', () => {
    for (const t of teams) {
      expect(t.division_title_prob, `${t.team}: wins division more often than it makes the field`)
        .toBeLessThanOrEqual(t.playoff_prob + roundingSlack(1));
      expect(t.first_round_bye_prob, `${t.team}: gets a bye more often than it makes the field`)
        .toBeLessThanOrEqual(t.playoff_prob + roundingSlack(1));
      expect(t.conf_champ_prob, `${t.team}: wins conference more often than it makes the field`)
        .toBeLessThanOrEqual(t.playoff_prob + roundingSlack(1));
      expect(t.super_bowl_prob, `${t.team}: wins SB more often than it wins its conference`)
        .toBeLessThanOrEqual(t.conf_champ_prob + roundingSlack(1, 4));
    }
  });
});

describe('standings — mutually exclusive outcomes sum to one', () => {
  const teams = standings().teams;

  it('exactly 7 teams per conference make the playoffs', () => {
    for (const conf of LEAGUE.CONFERENCES) {
      const rows = teams.filter((t) => t.conference === conf);
      expect(sumBy(rows, (t) => t.playoff_prob), `${conf} expected playoff teams`)
        .toBeCloseTo(LEAGUE.SEEDS_PER_CONFERENCE, 1);
    }
  });

  it('exactly one team wins each division', () => {
    const byDiv = groupBy(teams, (t) => t.division);
    const offenders: string[] = [];
    for (const [div, rows] of Object.entries(byDiv)) {
      const total = sumBy(rows, (t) => t.division_title_prob);
      if (Math.abs(total - 1) > LEAGUE.TEAMS_PER_DIVISION * roundingSlack(1) + 0.01) {
        offenders.push(`${div}: Σ division_title_prob = ${total.toFixed(3)}`);
      }
    }
    expect(
      offenders,
      'division_title_prob must sum to 1.000 within each division — exactly one team wins it.\n' +
        offenders.join('\n'),
    ).toEqual([]);
  });

  it('exactly one team per conference gets the first-round bye', () => {
    const offenders: string[] = [];
    for (const conf of LEAGUE.CONFERENCES) {
      const rows = teams.filter((t) => t.conference === conf);
      const total = sumBy(rows, (t) => t.first_round_bye_prob);
      if (Math.abs(total - LEAGUE.BYES_PER_CONFERENCE) > 16 * roundingSlack(1) + 0.01) {
        offenders.push(`${conf}: Σ first_round_bye_prob = ${total.toFixed(3)}`);
      }
    }
    expect(
      offenders,
      'in the 7-seed format only the #1 seed gets a bye, so this must sum to 1.000 per conference.\n' +
        offenders.join('\n'),
    ).toEqual([]);
  });

  it('exactly one team per conference wins the conference', () => {
    const offenders: string[] = [];
    for (const conf of LEAGUE.CONFERENCES) {
      const rows = teams.filter((t) => t.conference === conf);
      const total = sumBy(rows, (t) => t.conf_champ_prob);
      if (Math.abs(total - 1) > 16 * roundingSlack(1, 4) + 0.01) {
        offenders.push(`${conf}: Σ conf_champ_prob = ${total.toFixed(4)}`);
      }
    }
    expect(offenders, `conf_champ_prob must sum to 1.0000 per conference.\n${offenders.join('\n')}`).toEqual([]);
  });

  it('exactly one team wins the Super Bowl', () => {
    const total = sumBy(teams, (t) => t.super_bowl_prob);
    expect(total, 'Σ super_bowl_prob across all 32 teams must be 1.0000').toBeCloseTo(1, 2);
  });
});

describe('matchups — schedule integrity', () => {
  const d = matchups();

  it('active_week is one of available_weeks', () => {
    expect(d.available_weeks).toContain(d.active_week);
  });

  it('available_weeks is sorted, unique and gap-free', () => {
    expect(d.available_weeks).toEqual([...new Set(d.available_weeks)].sort((a, b) => a - b));
    for (let i = 1; i < d.available_weeks.length; i++) {
      expect(d.available_weeks[i] - d.available_weeks[i - 1], 'gap in available_weeks').toBe(1);
    }
  });

  it('every week referenced by a game is selectable in the UI', () => {
    const weeksWithGames = [...new Set(d.matchups.map((m) => m.week))].sort((a, b) => a - b);
    const unselectable = weeksWithGames.filter((w) => !d.available_weeks.includes(w));
    expect(unselectable, 'MatchupsClient only renders weeks in available_weeks').toEqual([]);
  });

  it('every selectable week actually has games (no empty slate)', () => {
    const weeksWithGames = new Set(d.matchups.map((m) => m.week));
    const empty = d.available_weeks.filter((w) => !weeksWithGames.has(w));
    expect(empty, 'these week buttons render an empty grid').toEqual([]);
  });

  it(`totals ${LEAGUE.GAMES_PER_SEASON} games across ${LEAGUE.REGULAR_SEASON_WEEKS} weeks`, () => {
    expect(d.matchups).toHaveLength(LEAGUE.GAMES_PER_SEASON);
    expect(d.available_weeks).toHaveLength(LEAGUE.REGULAR_SEASON_WEEKS);
  });

  it('game_id values are unique', () => {
    const ids = d.matchups.map((m) => m.game_id);
    const dupes = ids.filter((id, i) => ids.indexOf(id) !== i);
    expect([...new Set(dupes)]).toEqual([]);
  });

  it('game_id encodes the same season/week/teams as the row', () => {
    // nflverse game_id format: SEASON_WW_AWAY_HOME
    for (const m of d.matchups) {
      const expected = `${m.season}_${String(m.week).padStart(2, '0')}_${m.away_team}_${m.home_team}`;
      expect(m.game_id, 'game_id disagrees with its own row').toBe(expected);
    }
  });

  it('no team plays twice in the same week', () => {
    const offenders: string[] = [];
    for (const [week, games] of Object.entries(groupBy(d.matchups, (m) => String(m.week)))) {
      const appearances = new Map<string, number>();
      for (const g of games) {
        appearances.set(g.home_team, (appearances.get(g.home_team) ?? 0) + 1);
        appearances.set(g.away_team, (appearances.get(g.away_team) ?? 0) + 1);
      }
      for (const [team, n] of appearances) {
        if (n > 1) offenders.push(`week ${week}: ${team} appears ${n}x`);
      }
    }
    expect(offenders).toEqual([]);
  });

  it('no team plays itself', () => {
    expect(d.matchups.filter((m) => m.home_team === m.away_team).map((m) => m.game_id)).toEqual([]);
  });

  it(`each team plays exactly ${LEAGUE.SEASON_GAMES} games`, () => {
    const counts = new Map<string, number>();
    for (const m of d.matchups) {
      counts.set(m.home_team, (counts.get(m.home_team) ?? 0) + 1);
      counts.set(m.away_team, (counts.get(m.away_team) ?? 0) + 1);
    }
    const offenders = [...counts.entries()].filter(([, n]) => n !== LEAGUE.SEASON_GAMES);
    expect(offenders.map(([t, n]) => `${t}: ${n} games`)).toEqual([]);
  });

  it('gameday weekday string matches the actual calendar date', () => {
    const names = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];
    const offenders = d.matchups
      .filter((m) => names[new Date(`${m.gameday}T12:00:00Z`).getUTCDay()] !== m.weekday)
      .map((m) => `${m.game_id}: ${m.gameday} is a ${names[new Date(`${m.gameday}T12:00:00Z`).getUTCDay()]}, labelled ${m.weekday}`);
    expect(offenders.slice(0, 10)).toEqual([]);
  });

  it('gameday ordering is consistent with week ordering', () => {
    const firstDayOf = new Map<number, string>();
    for (const m of d.matchups) {
      const prev = firstDayOf.get(m.week);
      if (!prev || m.gameday < prev) firstDayOf.set(m.week, m.gameday);
    }
    const weeks = [...firstDayOf.keys()].sort((a, b) => a - b);
    for (let i = 1; i < weeks.length; i++) {
      expect(
        firstDayOf.get(weeks[i])! > firstDayOf.get(weeks[i - 1])!,
        `week ${weeks[i]} starts on or before week ${weeks[i - 1]}`,
      ).toBe(true);
    }
  });
});

describe('matchups — projection coherence', () => {
  const d = matchups();

  it('home_win_prob + away_win_prob === 1', () => {
    for (const m of d.matchups) {
      expect(m.home_win_prob + m.away_win_prob, `${m.game_id}`).toBeCloseTo(1, 2);
    }
  });

  it('projected_spread is the negation of projected_margin', () => {
    // A home favourite has a positive margin and a negative (laying) spread.
    for (const m of d.matchups) {
      expect(m.projected_spread, `${m.game_id}`).toBeCloseTo(-m.projected_margin, 2);
    }
  });

  it('the favourite by margin is also the favourite by win probability', () => {
    const offenders = d.matchups
      .filter((m) => Math.abs(m.projected_margin) > 0.5)
      .filter((m) => (m.projected_margin > 0) !== (m.home_win_prob > 0.5))
      .map((m) => `${m.game_id}: margin ${m.projected_margin} but home_win_prob ${m.home_win_prob}`);
    expect(offenders).toEqual([]);
  });

  it('rest_diff === home_rest_days - away_rest_days', () => {
    for (const m of d.matchups) {
      expect(m.rest_diff, `${m.game_id}`).toBe(m.home_rest_days - m.away_rest_days);
    }
  });

  it('travel miles measure distance since the previous game, so week 1 is all zeros', () => {
    // Confirmed semantics: a *home* team can carry travel miles (it flew back
    // from a road game), and nobody has travelled before their opener. If this
    // ever flips to "distance to this game", the fatigue inputs change meaning.
    const wk1 = d.matchups.filter((m) => m.week === Math.min(...d.available_weeks));
    const offenders = wk1
      .filter((m) => m.home_travel_miles !== 0 || m.away_travel_miles !== 0)
      .map((m) => `${m.game_id}: ${m.away_travel_miles}/${m.home_travel_miles}`);
    expect(offenders).toEqual([]);
  });

  it('completed games carry a winner consistent with their scores', () => {
    const played = d.matchups.filter((m) => m.is_completed);
    expect(played.length, 'no completed games to check').toBeGreaterThan(0);
    for (const m of played) {
      const home = m.home_score!;
      const away = m.away_score!;
      // NB: actual_winner carries the full franchise name ("Seattle Seahawks"),
      // NOT the 2-3 letter code in home_team/away_team. Mixing those two ID
      // spaces in one row is the join hazard CLAUDE.md warns about, so the
      // test pins the format down rather than guessing at it.
      if (home === away) continue; // ties are covered by their own test below
      const expected = home > away ? m.home_team_name : m.away_team_name;
      expect(m.actual_winner, `${m.game_id} (${away}-${home})`).toBe(expected);
    }
  });

  it('prediction_correct agrees with the projected margin and the result', () => {
    // MatchupCard renders the projected margin and the correct/incorrect badge
    // in the same card, so these two fields must describe the same prediction.
    // They are reconstructed independently in tools/export_web_datasets.R:
    // `projected_margin` is derived back out of `home_win_prob` via
    // `qnorm(h_win_prob) * NFL_MARGIN_SIGMA`, where h_win_prob is chosen by a
    // `pred_winner == h_name` STRING comparison against the graded record.
    // When that comparison picks the wrong side, the card shows a favourite
    // that the badge then contradicts.
    const graded = d.matchups.filter((m) => m.is_completed && m.home_score !== m.away_score);
    const offenders = graded
      .filter((m) => m.prediction_correct !== ((m.projected_margin > 0) === (m.actual_winner === m.home_team_name)))
      .map(
        (m) =>
          `${m.game_id}: margin ${m.projected_margin > 0 ? '+' : ''}${m.projected_margin} favours ` +
          `${m.projected_margin > 0 ? m.home_team : m.away_team}, ${m.actual_winner} won ` +
          `${m.away_score}-${m.home_score}, badge says ${m.prediction_correct ? 'CORRECT' : 'WRONG'}`,
      );
    const flagAccuracy = graded.filter((m) => m.prediction_correct).length / graded.length;
    const marginAccuracy =
      graded.filter((m) => (m.projected_margin > 0) === (m.actual_winner === m.home_team_name)).length / graded.length;
    expect(
      offenders.slice(0, 8),
      `${offenders.length}/${graded.length} completed games contradict themselves. ` +
        `The badges imply ${(flagAccuracy * 100).toFixed(1)}% accuracy; the displayed margins imply ` +
        `${(marginAccuracy * 100).toFixed(1)}%. Both cannot be right.`,
    ).toEqual([]);
  });

  it('a tied game is not credited to either team', () => {
    const ties = d.matchups.filter((m) => m.is_completed && m.home_score === m.away_score);
    const offenders = ties
      .filter((m) => m.actual_winner === m.home_team_name || m.actual_winner === m.away_team_name)
      .map((m) => `${m.game_id} finished ${m.away_score}-${m.away_score} but actual_winner="${m.actual_winner}"`);
    expect(
      offenders,
      'tools/export_web_datasets.R picks the winner with `if (h_score > a_score) h_name else a_name`, ' +
        'which silently awards every tie to the away team.',
    ).toEqual([]);
  });

  it('no game after the active week is marked completed', () => {
    const offenders = d.matchups
      .filter((m) => m.is_completed && m.week > d.active_week)
      .map((m) => `${m.game_id}: week ${m.week} completed, active week is ${d.active_week}`);
    expect(offenders).toEqual([]);
  });

  it('every week before the active week is fully graded', () => {
    // The active week itself may be mid-slate; earlier weeks must not be.
    const offenders: string[] = [];
    for (const [week, games] of Object.entries(groupBy(d.matchups, (m) => String(m.week)))) {
      if (Number(week) >= d.active_week) continue;
      const done = games.filter((g) => g.is_completed).length;
      if (done !== games.length) offenders.push(`week ${week}: ${done}/${games.length} graded`);
    }
    expect(offenders).toEqual([]);
  });

  it('graded games reconcile with the diagnostics game count', () => {
    const completed = d.matchups.filter((m) => m.is_completed).length;
    const graded = diagnostics().n_games_graded;
    const latest = Array.isArray(graded) ? graded[graded.length - 1] : graded;
    expect(completed, 'matchups and model_diagnostics disagree on how many games are in the books')
      .toBe(latest);
  });

  it('key_number_flag uses only the documented vocabulary', () => {
    const VALID = /^(Standard|(3|4|6|7|10)-pt Key)$/;
    const offenders = [...new Set(d.matchups.map((m) => m.key_number_flag))].filter((f) => !VALID.test(f));
    expect(offenders, 'unrecognised key_number_flag value(s)').toEqual([]);
  });

  it('an "N-pt Key" flag really does sit within a point of N', () => {
    const offenders = d.matchups
      .filter((m) => m.key_number_flag !== 'Standard')
      .filter((m) => Math.abs(Math.abs(m.projected_margin) - parseInt(m.key_number_flag, 10)) > 1)
      .map((m) => `${m.game_id}: margin ${m.projected_margin} flagged "${m.key_number_flag}"`);
    expect(offenders.slice(0, 10)).toEqual([]);
  });

  it('every key number advertised on the matchups page is reachable', () => {
    // app/matchups/page.tsx prints a "Key Margin Alerts: 3, 7, 6, 10, 4" chip.
    // If the export never emits one of those, the chip is lying to the user.
    const advertised = [3, 7, 6, 10, 4];
    const emitted = new Set(
      d.matchups.filter((m) => m.key_number_flag !== 'Standard').map((m) => parseInt(m.key_number_flag, 10)),
    );
    const unreachable = advertised.filter((n) => !emitted.has(n));
    expect(unreachable, 'app/matchups/page.tsx advertises key number(s) the data never flags').toEqual([]);
  });
});

describe('playoffs — bracket structure', () => {
  const d = playoffs();

  it.each(['afc', 'nfc'] as const)('%s field is seeds 1..7, no duplicate teams', (conf) => {
    const seeds = conf === 'afc' ? d.afc_seeds : d.nfc_seeds;
    expect(seeds.map((s) => s.seed).sort((a, b) => a - b)).toEqual([1, 2, 3, 4, 5, 6, 7]);
    expect(new Set(seeds.map((s) => s.team)).size).toBe(LEAGUE.SEEDS_PER_CONFERENCE);
  });

  it.each(['afc', 'nfc'] as const)('%s seeds 1-4 are the four division winners', (conf) => {
    const seeds = conf === 'afc' ? d.afc_seeds : d.nfc_seeds;
    const top4 = seeds.filter((s) => s.seed <= 4);
    expect(new Set(top4.map((s) => s.division)).size, 'two division winners from one division').toBe(4);
  });

  it.each(['afc', 'nfc'] as const)('%s seeds 5-7 are wild cards', (conf) => {
    const seeds = conf === 'afc' ? d.afc_seeds : d.nfc_seeds;
    for (const s of seeds.filter((x) => x.seed >= 5)) {
      expect(s.role.toLowerCase(), `seed ${s.seed} ${s.team} role="${s.role}"`).toContain('wild');
    }
  });

  it('the two conferences share no teams', () => {
    const afc = new Set(d.afc_seeds.map((s) => s.team));
    const overlap = d.nfc_seeds.filter((s) => afc.has(s.team)).map((s) => s.team);
    expect(overlap).toEqual([]);
  });

  it('bubble teams are not already in the field', () => {
    const seeded = new Set([...d.afc_seeds, ...d.nfc_seeds].map((s) => s.team));
    const contradictions = [...d.afc_bubble, ...d.nfc_bubble].filter((b) => seeded.has(b.team)).map((b) => b.team);
    expect(contradictions).toEqual([]);
  });

  it('the #1 seed does not play a wild card round', () => {
    for (const seeds of [d.afc_seeds, d.nfc_seeds]) {
      const one = seeds.find((s) => s.seed === 1)!;
      expect(one.wild_card_win_prob, `${one.team} holds the bye yet has a wild-card win prob`).toBe(1);
    }
  });

  it('advancement probabilities are monotonically non-increasing by round', () => {
    for (const s of [...d.afc_seeds, ...d.nfc_seeds]) {
      expect(s.divisional_win_prob, `${s.team}`).toBeLessThanOrEqual(s.wild_card_win_prob + 1e-9);
      expect(s.conf_champ_win_prob, `${s.team}`).toBeLessThanOrEqual(s.divisional_win_prob + 1e-9);
      expect(s.super_bowl_win_prob, `${s.team}`).toBeLessThanOrEqual(s.conf_champ_win_prob + 1e-9);
    }
  });

  it.each(['afc', 'nfc'] as const)('exactly one %s team reaches the Super Bowl', (conf) => {
    const seeds = conf === 'afc' ? d.afc_seeds : d.nfc_seeds;
    expect(sumBy(seeds, (s) => s.conf_champ_win_prob), `Σ ${conf} conf_champ_win_prob`).toBeCloseTo(1, 2);
  });

  it.each(['afc', 'nfc'] as const)('exactly 4 %s teams win in the wild card round', (conf) => {
    // 3 wild card games + the #1 seed on bye = 4 teams in the divisional round.
    const seeds = conf === 'afc' ? d.afc_seeds : d.nfc_seeds;
    expect(sumBy(seeds, (s) => s.wild_card_win_prob)).toBeCloseTo(4, 1);
  });

  it.each(['afc', 'nfc'] as const)('exactly 2 %s teams win in the divisional round', (conf) => {
    const seeds = conf === 'afc' ? d.afc_seeds : d.nfc_seeds;
    expect(sumBy(seeds, (s) => s.divisional_win_prob)).toBeCloseTo(2, 1);
  });

  it('exactly one team wins the Super Bowl', () => {
    expect(sumBy([...d.afc_seeds, ...d.nfc_seeds], (s) => s.super_bowl_win_prob)).toBeCloseTo(1, 2);
  });

  it('seeding is consistent with win_pct within the division-winner and wild-card blocks', () => {
    for (const seeds of [d.afc_seeds, d.nfc_seeds]) {
      for (const block of [seeds.filter((s) => s.seed <= 4), seeds.filter((s) => s.seed >= 5)]) {
        const ordered = [...block].sort((a, b) => a.seed - b.seed);
        for (let i = 1; i < ordered.length; i++) {
          expect(
            ordered[i - 1].win_pct,
            `seed ${ordered[i - 1].seed} (${ordered[i - 1].team}) has a worse record than seed ${ordered[i].seed} (${ordered[i].team})`,
          ).toBeGreaterThanOrEqual(ordered[i].win_pct);
        }
      }
    }
  });
});

describe('playoffs — agreement with the standings dataset', () => {
  it('seeded teams carry the same power_rating in both datasets', () => {
    const byTeam = new Map(standings().teams.map((t) => [t.team, t]));
    for (const s of [...playoffs().afc_seeds, ...playoffs().nfc_seeds]) {
      const st = byTeam.get(s.team);
      expect(st, `${s.team} is seeded but missing from standings`).toBeDefined();
      expect(s.power_rating, `${s.team} power_rating`).toBeCloseTo(st!.power_rating, 1);
    }
  });

  it('every seeded team has a non-trivial playoff_prob in the standings', () => {
    const byTeam = new Map(standings().teams.map((t) => [t.team, t]));
    const offenders = [...playoffs().afc_seeds, ...playoffs().nfc_seeds]
      .filter((s) => (byTeam.get(s.team)?.playoff_prob ?? 0) < 0.25)
      .map((s) => `${s.team} seeded #${s.seed} but playoff_prob=${byTeam.get(s.team)?.playoff_prob}`);
    expect(offenders).toEqual([]);
  });

  it('bubble teams rank below the field on playoff_prob', () => {
    const byTeam = new Map(standings().teams.map((t) => [t.team, t]));
    const d = playoffs();
    for (const conf of ['afc', 'nfc'] as const) {
      const field = (conf === 'afc' ? d.afc_seeds : d.nfc_seeds).map((s) => byTeam.get(s.team)?.playoff_prob ?? 0);
      const worstInField = Math.min(...field);
      for (const b of conf === 'afc' ? d.afc_bubble : d.nfc_bubble) {
        expect(b.playoff_prob, `${b.team} is on the bubble but out-ranks the weakest seed`)
          .toBeLessThanOrEqual(worstInField + 1e-9);
      }
    }
  });
});

describe('team EPA profiles', () => {
  const d = teamEpa();

  it(`covers all ${LEAGUE.TEAM_COUNT} teams exactly once`, () => {
    expect(d).toHaveLength(LEAGUE.TEAM_COUNT);
    expect(new Set(d.map((t) => t.team)).size).toBe(LEAGUE.TEAM_COUNT);
  });

  it('net_epa_per_play === off_epa_per_play - def_epa_per_play', () => {
    for (const t of d) {
      expect(Math.abs(t.net_epa_per_play - (t.off_epa_per_play - t.def_epa_per_play)), `${t.team}`)
        .toBeLessThanOrEqual(0.0011);
    }
  });

  it('league-average offensive and defensive EPA roughly cancel', () => {
    // Every offensive play is some defence's play, so the two league means
    // must be near-identical. A drift here means one side is mis-aggregated.
    const off = sumBy(d, (t) => t.off_epa_per_play) / d.length;
    const def = sumBy(d, (t) => t.def_epa_per_play) / d.length;
    expect(off, `league mean off EPA ${off.toFixed(4)} vs def ${def.toFixed(4)}`).toBeCloseTo(def, 2);
  });

  it('league-average success rate sits in a believable band', () => {
    const off = sumBy(d, (t) => t.off_success_rate) / d.length;
    expect(off).toBeGreaterThan(40);
    expect(off).toBeLessThan(50);
  });

  it('division and conference agree with the standings dataset', () => {
    const byTeam = new Map(standings().teams.map((t) => [t.team, t]));
    for (const t of d) {
      expect(t.division, `${t.team} division`).toBe(byTeam.get(t.team)!.division);
      expect(t.conference, `${t.team} conference`).toBe(byTeam.get(t.team)!.conference);
      expect(t.team_name, `${t.team} name`).toBe(byTeam.get(t.team)!.team_name);
    }
  });

  it('games_in_sample is consistent across the league', () => {
    const vals = d.map((t) => t.games_in_sample);
    expect(Math.max(...vals) - Math.min(...vals), 'EPA sample windows differ by more than a bye week')
      .toBeLessThanOrEqual(1);
  });
});

describe('QB profiles', () => {
  const d = qbs();

  it('every franchise has exactly one listed starter', () => {
    const starters = groupBy(d.filter((q) => q.is_starter), (q) => q.team);
    const offenders = Object.entries(starters)
      .filter(([, rows]) => rows.length !== 1)
      .map(([team, rows]) => `${team}: ${rows.length} starters (${rows.map((r) => r.player_name).join(', ')})`);
    expect(offenders).toEqual([]);
    expect(Object.keys(starters), 'a franchise has no listed starter').toHaveLength(LEAGUE.TEAM_COUNT);
  });

  it('player names are unique (no duplicated depth-chart rows)', () => {
    const names = d.map((q) => q.player_name);
    expect([...new Set(names.filter((n, i) => names.indexOf(n) !== i))]).toEqual([]);
  });

  it('every QB belongs to a team that exists in the standings', () => {
    const known = new Set(standings().teams.map((t) => t.team));
    expect([...new Set(d.map((q) => q.team).filter((t) => !known.has(t)))]).toEqual([]);
  });

  it('the leaderboard filter (starter OR >=35 attempts) yields at least 3 names', () => {
    // PlayersClient slices topEpa/topCpoe to 3; fewer qualifiers renders a
    // short podium rather than crashing, but it signals a broken export.
    const qualified = d.filter((q) => q.is_starter || (q.attempts_2026 ?? 0) >= 35);
    expect(qualified.length).toBeGreaterThanOrEqual(3);
  });

  it('starters are not outnumbered on attempts by their own backups', () => {
    const offenders: string[] = [];
    for (const [team, rows] of Object.entries(groupBy(d, (q) => q.team))) {
      const starter = rows.find((q) => q.is_starter);
      if (!starter) continue;
      const busier = rows.filter((q) => !q.is_starter && (q.attempts_2026 ?? 0) > (starter.attempts_2026 ?? 0));
      for (const b of busier) {
        offenders.push(`${team}: ${b.player_name} (${b.attempts_2026} att) > starter ${starter.player_name} (${starter.attempts_2026} att)`);
      }
    }
    expect(offenders).toEqual([]);
  });

  it('headshot hosts are allow-listed in next.config.mjs', () => {
    const allowed = ['a.espncdn.com', 'static.www.nfl.com', 'static.nfl.com'];
    const hosts = [...new Set(d.map((q) => new URL(q.headshot_url).host))];
    expect(hosts.filter((h) => !allowed.includes(h)), 'next/image would reject these hosts').toEqual([]);
  });
});

describe('coaching profiles', () => {
  const d = coaching();

  it(`covers all ${LEAGUE.TEAM_COUNT} teams exactly once`, () => {
    expect(d).toHaveLength(LEAGUE.TEAM_COUNT);
    expect(new Set(d.map((c) => c.team)).size).toBe(LEAGUE.TEAM_COUNT);
  });

  it('career_record parses and is internally plausible', () => {
    for (const c of d) {
      const [w, l] = c.career_record.split('-').map(Number);
      expect(Number.isFinite(w) && Number.isFinite(l), `${c.team}: "${c.career_record}"`).toBe(true);
      // A coach cannot have more games than ~17 per season of tenure, plus
      // prior stops elsewhere; cap generously at 40 seasons.
      expect(w + l, `${c.head_coach}: ${w + l} career games`).toBeLessThanOrEqual(40 * 20);
    }
  });

  it('tenure of 0-1 years implies a short career record at this stop', () => {
    // Guards against a stale coach row surviving a coaching change.
    const offenders = d
      .filter((c) => c.tenure_years <= 1)
      .filter((c) => {
        const [w, l] = c.career_record.split('-').map(Number);
        return w + l > 17 * 25; // allow a long career elsewhere, flag the absurd
      })
      .map((c) => `${c.team} ${c.head_coach}: tenure ${c.tenure_years}y, record ${c.career_record}`);
    expect(offenders).toEqual([]);
  });

  it('play_caller agrees with the offensive/defensive play-caller split', () => {
    const offenders = d
      .filter((c) => c.offensive_play_caller !== undefined)
      .filter((c) => c.play_caller !== c.offensive_play_caller && c.play_caller !== c.defensive_play_caller)
      .map((c) => `${c.team}: play_caller="${c.play_caller}" but off="${c.offensive_play_caller}" def="${c.defensive_play_caller}"`);
    expect(offenders).toEqual([]);
  });

  it('HC and OC share a name only where the head coach calls the offence', () => {
    // Kyle Shanahan-style setups legitimately list one name in both slots.
    // A duplicate name WITHOUT that designation means one field was overwritten.
    const offenders = d
      .filter((c) => c.offensive_coordinator === c.head_coach)
      .filter((c) => c.offensive_play_caller !== 'Head Coach' && c.play_caller !== 'Head Coach')
      .map((c) => `${c.team}: ${c.head_coach} fills both HC and OC but does not call plays`);
    expect(offenders).toEqual([]);
  });

  it('no coordinator name is duplicated across the offensive and defensive slots', () => {
    const offenders = d
      .filter((c) => c.offensive_coordinator === c.defensive_coordinator)
      .map((c) => `${c.team}: ${c.offensive_coordinator} listed as both OC and DC`);
    expect(offenders).toEqual([]);
  });

  it('fourth_down_aggression_index behaves like a percentile across the league', () => {
    const vals = d.map((c) => c.fourth_down_aggression_index);
    expect(Math.min(...vals), 'no coach near the bottom of the percentile range').toBeLessThan(25);
    expect(Math.max(...vals), 'no coach near the top of the percentile range').toBeGreaterThan(75);
  });

  it('super_bowl_wins totals are not inflated beyond history', () => {
    // 59 Super Bowls have been played; active HCs cannot collectively hold
    // more rings than that.
    expect(sumBy(d, (c) => c.super_bowl_wins)).toBeLessThanOrEqual(59);
  });
});

describe('salary cap', () => {
  const d = salaryCap();

  it(`covers all ${LEAGUE.TEAM_COUNT} teams exactly once`, () => {
    expect(d.teams).toHaveLength(LEAGUE.TEAM_COUNT);
    expect(new Set(d.teams.map((t) => t.team)).size).toBe(LEAGUE.TEAM_COUNT);
  });

  it('cap_ceiling is expressed in $M, matching how the UI prints it', () => {
    // SalaryCapClient renders `${data.cap_ceiling}M` verbatim. A switch to
    // raw dollars would print "$301200000M".
    expect(d.cap_ceiling).toBeGreaterThan(150);
    expect(d.cap_ceiling).toBeLessThan(600);
  });

  it('positional_spending apy reconciles with total_active_apy', () => {
    for (const t of d.teams) {
      const total = sumBy(Object.values(t.positional_spending), (p) => p.apy);
      expect(total, `${t.team}`).toBeCloseTo(t.total_active_apy, 0);
    }
  });

  it('positional_spending pct sums to 100', () => {
    for (const t of d.teams) {
      const total = sumBy(Object.values(t.positional_spending), (p) => p.pct);
      expect(total, `${t.team}`).toBeCloseTo(100, 0);
    }
  });

  it('positional_spending count sums to total_active_contracts', () => {
    for (const t of d.teams) {
      const total = sumBy(Object.values(t.positional_spending), (p) => p.count);
      expect(total, `${t.team}`).toBe(t.total_active_contracts);
    }
  });

  it('top_paid_players are ordered by APY and are a subset of team spend', () => {
    for (const t of d.teams) {
      for (let i = 1; i < t.top_paid_players.length; i++) {
        expect(t.top_paid_players[i - 1].apy, `${t.team} top_paid_players out of order`)
          .toBeGreaterThanOrEqual(t.top_paid_players[i].apy);
      }
      for (const p of t.top_paid_players) {
        expect(p.apy, `${t.team} ${p.player} APY exceeds the whole team's APY`).toBeLessThanOrEqual(t.total_active_apy);
      }
    }
  });

  it('top_league_contracts is sorted by APY descending', () => {
    const c = d.top_league_contracts;
    for (let i = 1; i < c.length; i++) {
      expect(c[i - 1].apy, `${c[i - 1].player} / ${c[i].player}`).toBeGreaterThanOrEqual(c[i].apy);
    }
  });

  it('apy_cap_pct implies a believable cap for the signing year', () => {
    // apy_cap_pct is measured against the cap in `year_signed`, not the 2026
    // ceiling, so it cannot be checked against cap_ceiling directly. What it
    // CAN be checked against is whether the implied cap is a real NFL cap.
    const offenders = d.top_league_contracts
      .filter((c) => c.apy_cap_pct > 0)
      .map((c) => ({ c, impliedCap: (c.apy / c.apy_cap_pct) * 100 }))
      .filter(({ impliedCap }) => impliedCap < 150 || impliedCap > d.cap_ceiling + 5)
      .map(({ c, impliedCap }) => `${c.player} (${c.year_signed}): apy ${c.apy} at ${c.apy_cap_pct}% implies a $${impliedCap.toFixed(0)}M cap`);
    expect(offenders.slice(0, 8)).toEqual([]);
  });

  it('contract value is at least the guaranteed money', () => {
    const offenders = d.top_league_contracts
      .filter((c) => c.guaranteed > c.value)
      .map((c) => `${c.player}: guaranteed ${c.guaranteed} > value ${c.value}`);
    expect(offenders).toEqual([]);
  });

  it('contract value is roughly apy * years', () => {
    const offenders = d.top_league_contracts
      .filter((c) => Math.abs(c.value - c.apy * c.years) > Math.max(2, c.value * 0.05))
      .map((c) => `${c.player}: value ${c.value} vs apy ${c.apy} x ${c.years}y = ${(c.apy * c.years).toFixed(1)}`);
    expect(offenders).toEqual([]);
  });

  // Issue #48: these three fields were generated by an unseeded `runif()` draw in
  // export_web_datasets.R and published as fact. They were removed rather than
  // re-derived (nflreadr exposes no real per-team dead money). This pins the
  // removal so a future change cannot quietly reintroduce fabricated figures.
  it('does not republish the fabricated dead-money fields (issue #48)', () => {
    const banned = ['dead_money', 'estimated_cap_space', 'cap_health_rating'];
    const offenders = d.teams.flatMap((t) =>
      banned.filter((f) => f in (t as unknown as Record<string, unknown>)).map((f) => `${t.team}.${f}`),
    );
    expect(offenders).toEqual([]);
  });

  it('every top_league_contract belongs to a team in the cap dataset', () => {
    const known = new Set(d.teams.map((t) => t.team));
    expect([...new Set(d.top_league_contracts.map((c) => c.team).filter((t) => !known.has(t)))]).toEqual([]);
  });
});

describe('model diagnostics', () => {
  const d = diagnostics();
  const asArray = (v: number | number[]): number[] => (Array.isArray(v) ? v : [v]);

  it('ensemble weights sum to 1', () => {
    const w = d.ensemble_weights;
    expect(w.ridge_massey + w.elo_dynamic + w.market_blend).toBeCloseTo(1, 6);
  });

  it('every trajectory series has the same length', () => {
    const lengths = {
      season: asArray(d.season as number | number[]).length,
      last_evaluated: (Array.isArray(d.last_evaluated) ? d.last_evaluated : [d.last_evaluated]).length,
      n_games_graded: asArray(d.n_games_graded).length,
      overall_accuracy: asArray(d.overall_accuracy).length,
      overall_brier: asArray(d.overall_brier).length,
      overall_logloss: asArray(d.overall_logloss).length,
      brier_improvement: asArray(d.brier_improvement).length,
    };
    expect(new Set(Object.values(lengths)).size, `ragged series: ${JSON.stringify(lengths)}`).toBe(1);
  });

  it('n_games_graded is non-decreasing over the trajectory', () => {
    const n = asArray(d.n_games_graded);
    for (let i = 1; i < n.length; i++) {
      expect(n[i], `graded count fell from ${n[i - 1]} to ${n[i]} at index ${i}`).toBeGreaterThanOrEqual(n[i - 1]);
    }
  });

  it('accuracy, brier and logloss stay in valid ranges', () => {
    // overall_accuracy is in PERCENTAGE POINTS (e.g. 66.7), while
    // overall_brier / overall_logloss are proportions. DiagnosticsClient
    // relies on exactly that split (`accuracy.toFixed(1)}%`, no *100), so the
    // mixed units are load-bearing rather than a bug.
    for (const a of asArray(d.overall_accuracy)) {
      expect(a, 'accuracy should be percentage points, not a proportion').toBeGreaterThan(1);
      expect(a).toBeLessThanOrEqual(100);
    }
    for (const b of asArray(d.overall_brier)) {
      expect(b).toBeGreaterThan(0);
      expect(b).toBeLessThanOrEqual(0.25);
    }
    for (const l of asArray(d.overall_logloss)) {
      expect(l).toBeGreaterThan(0);
      expect(l).toBeLessThan(1);
    }
  });

  it('brier_improvement === brier_baseline - overall_brier', () => {
    const brier = asArray(d.overall_brier);
    const improvement = asArray(d.brier_improvement);
    for (let i = 0; i < brier.length; i++) {
      // brier_improvement is the RELATIVE gain over the baseline, expressed in
      // percentage points: (baseline - brier) / baseline * 100.
      const expected = ((d.brier_baseline - brier[i]) / d.brier_baseline) * 100;
      expect(
        Math.abs(improvement[i] - expected) < 0.05,
        `index ${i}: brier_improvement=${improvement[i]} but (0.25-${brier[i]})/0.25*100 = ${expected.toFixed(2)}`,
      ).toBe(true);
    }
  });

  it('the model beats the 0.25 coin-flip Brier baseline', () => {
    for (const b of asArray(d.overall_brier)) expect(b).toBeLessThan(0.25);
  });

  it('calibration bins are ordered, non-overlapping and cover the counts', () => {
    const bins = d.calibration_curve;
    for (let i = 1; i < bins.length; i++) {
      expect(bins[i].predicted_mid, 'calibration bins out of order').toBeGreaterThan(bins[i - 1].predicted_mid);
    }
    expect(sumBy(bins, (b) => b.count), 'no graded predictions in the calibration curve').toBeGreaterThan(0);
  });

  it('calibration bin counts sum to the number of games actually graded', () => {
    // A calibration curve can only be built from games that have been played
    // and scored. If the bin counts total the full 272-game schedule while
    // n_games_graded says far fewer, the curve is not derived from the model's
    // own graded predictions.
    const graded = asArray(d.n_games_graded);
    const latest = graded[graded.length - 1];
    const binned = sumBy(d.calibration_curve, (b) => b.count);
    expect(
      binned,
      `calibration_curve bins total ${binned} games but only ${latest} have been graded — ` +
        'check tools/export_web_datasets.R, where calibration_curve is written as a literal list',
    ).toBe(latest);
  });

  it('brier_baseline is the value DiagnosticsClient recomputes against', () => {
    // DiagnosticsClient recomputes the per-row improvement with a hard-coded
    // 0.25 instead of reading data.brier_baseline. These agree today; this
    // test fails the moment the export changes the baseline and leaves that
    // call site behind.
    expect(d.brier_baseline, 'hard-coded 0.25 in DiagnosticsClient has drifted from the data').toBe(0.25);
  });

  it('calibration is broadly monotonic (higher predicted -> higher actual)', () => {
    // Compare the top and bottom thirds by weight rather than demanding strict
    // monotonicity, which small per-bin counts make noisy.
    const bins = d.calibration_curve.filter((b) => b.count > 0);
    const third = Math.max(1, Math.floor(bins.length / 3));
    const wmean = (rows: typeof bins) => sumBy(rows, (b) => b.actual_win_rate * b.count) / sumBy(rows, (b) => b.count);
    const low = wmean(bins.slice(0, third));
    const high = wmean(bins.slice(-third));
    expect(high, `low-confidence bins hit ${low.toFixed(3)}, high-confidence bins ${high.toFixed(3)}`).toBeGreaterThan(low);
  });

  it('margin_sigma and home_field_adv are in NFL-plausible ranges', () => {
    expect(d.margin_sigma).toBeGreaterThan(10);
    expect(d.margin_sigma).toBeLessThan(18);
    expect(d.home_field_adv).toBeGreaterThan(0);
    expect(d.home_field_adv).toBeLessThan(4);
  });
});

