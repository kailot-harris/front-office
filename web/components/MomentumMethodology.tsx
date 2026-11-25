import React from 'react';
import Link from 'next/link';
import type {
  MeasuresFlagRow,
  MomentumMethodologyPayload,
  MomentumVerdict,
  StrongerArmRow,
} from '@/lib/momentumMethodologyTypes';
import { MethodologyResultsTable } from '@/components/MethodologyResultsTable';
import {
  IntervalBar,
  VerdictBadge,
  fmtInterval,
  fmtSigned,
  intervalDomain,
  intervalWord,
  pct,
} from '@/components/MethodologyCharts';

/*
 * /momentum/methodology: how the NFL Momentum Board was built and tested
 * (NFL_analytics#226). Every figure on this page is read from
 * momentum_methodology.json, which tools/publish_momentum_methodology.R copies
 * out of the two study results files (#227 window study, #221 measures study).
 * Only wording lives here; no study number is typed into this file.
 */

export const METHODOLOGY_SECTIONS = [
  { id: 'not-a-forecast', title: 'Recent play, not a forecast' },
  { id: 'windows', title: 'Window lengths' },
  { id: 'carry-over', title: 'Season start: carried games' },
  { id: 'weights-in-use', title: 'Score weights in use' },
  { id: 'flat-surface', title: 'Why the weights are not a finding' },
  { id: 'badges-hidden', title: 'Why flags carry no badge' },
  { id: 'availability', title: 'Key players and data coverage' },
  { id: 'qb-change', title: 'Starting-QB change and other flags' },
  { id: 'everything-tried', title: 'Everything the measures study tried' },
  { id: 'combination-search', title: 'The combination search' },
  { id: 'holdout-and-limits', title: 'Forward test, protocol and limits' },
  { id: 'sources', title: 'Sources' },
] as const;

const card = 'rounded-xl border border-slate-800 bg-surface-raised/60 p-4';
const tableWrap = 'overflow-x-auto rounded-lg border border-slate-800';
const th = 'px-2 py-2 font-semibold text-left';
const td = 'px-2 py-1.5';
const mono = 'font-mono tabular-nums';
const linkClass =
  'text-accent-400 underline underline-offset-2 hover:text-accent-500 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-accent-500 rounded';

const Section: React.FC<{ id: string; title: string; children: React.ReactNode }> = ({ id, title, children }) => (
  <section id={id} aria-labelledby={`${id}-h`} className="space-y-3 scroll-mt-20">
    <h2 id={`${id}-h`} className="text-lg font-semibold text-slate-100">
      {title}
    </h2>
    {children}
  </section>
);

/** Plain-language names for the study targets. Wording only. */
const TARGET_TEXT: Record<string, string> = {
  margin_raw: 'next-game point margin',
  margin_beyond_elo: 'next-game margin beyond what Elo expected',
  win_raw_auc: 'next-game winner (ROC-AUC)',
  win_raw_logloss: 'next-game winner (log loss)',
  win_beyond_elo_logloss_gain: 'next-game winner beyond Elo (log-loss gain)',
  win_beyond_elo_auc_gain: 'next-game winner beyond Elo (ROC-AUC gain)',
  next_game: 'next-game margin beyond Elo',
  margin3_beyond_elo: 'mean margin beyond Elo over the next 3 games',
  next_margin_beyond_elo: 'next-game margin beyond Elo',
  next_game_win: 'next-game winner',
};
const targetText = (t: string) => TARGET_TEXT[t] ?? t;

const COMPONENT_TEXT: Record<string, string> = {
  form: 'form',
  trend: 'trend',
  residual: 'margin vs Elo',
  resid: 'margin vs Elo',
  elo_change: 'Elo change',
  elo: 'Elo change',
};

const CHECK_TEXT: Record<string, string> = {
  ci_above_zero: 'The 95% interval of the gain on unseen seasons is above zero.',
  beats_permutation_p95: 'It beats 95% of the shuffled-outcome runs.',
  stable_selection: 'The same stats and measures are picked in most held-out seasons.',
  sign_holds_most_seasons: 'The gain is positive in most held-out seasons.',
};

const COMPARISON_TEXT: Record<string, string> = {
  elastic_net: 'All features at once, shrunk toward zero (elastic net)',
  greedy_forward: 'Adding the best feature one at a time (greedy forward selection)',
};

/** Window labels in the results files are strings; "std" is season to date. */
const windowLabel = (w: string) => (w === 'std' ? 'season to date' : `${w} games`);

function verdictCounts<T extends { verdict: string }>(rows: T[]): Record<MomentumVerdict, number> {
  const c: Record<MomentumVerdict, number> = { kept: 0, inconclusive: 0, discarded: 0 };
  for (const r of rows) if (r.verdict in c) c[r.verdict as MomentumVerdict] += 1;
  return c;
}

const Check: React.FC<{ ok: boolean; children: React.ReactNode }> = ({ ok, children }) => (
  <li className="flex items-start gap-2">
    <span
      className={`mt-0.5 inline-block shrink-0 rounded-full border px-2 py-0.5 text-[11px] font-semibold ${
        ok ? 'bg-emerald-500/10 text-emerald-300 border-emerald-500/30' : 'bg-rose-500/10 text-rose-300 border-rose-500/30'
      }`}
    >
      {ok ? 'passes' : 'fails'}
    </span>
    <span>{children}</span>
  </li>
);

const IntervalCell: React.FC<{ lo: number; hi: number; point: number; domain: [number, number]; digits?: number }> = ({
  lo,
  hi,
  point,
  domain,
  digits = 5,
}) => (
  <div className="flex items-center gap-2">
    <IntervalBar lo={lo} hi={hi} point={point} domain={domain} width={96} />
    <span className={`whitespace-nowrap ${mono} text-slate-300`}>{fmtInterval(lo, hi, digits)}</span>
  </div>
);

export const MomentumMethodology: React.FC<{ data: MomentumMethodologyPayload }> = ({ data }) => {
  const rw = data.rolling_window;
  const mm = data.momentum_measures;
  const board = data.board;
  const srcRw = data.sources.rolling_window;
  const srcMm = data.sources.momentum_measures;
  const nba = srcRw.nba_comparison_weights;
  const order = board.weights_order;
  const boardWindows = board.windows.map(String);

  /* ---- headline: the beyond-Elo intervals of the window study ---- */
  // Rows with n = 0 had no games to score (e.g. a window longer than a reset season allows).
  const beyond: StrongerArmRow[] = rw.stronger_arm.table.filter((r) => r.n > 0 && r.lo !== null);
  const beyondUnscored = rw.stronger_arm.table.length - beyond.length;
  const beyondAbove = beyond.filter((r) => r.lo! > 0).length;
  const beyondTargets = Array.from(new Set(beyond.map((r) => r.target)));
  const weightRows = rw.weights.table;
  const weightBestAbove = weightRows.filter((r) => r.best_lo > 0).length;
  const singleCounts = verdictCounts(mm.single_feature_results);
  const cs = mm.combination_search;

  /* ---- windows ---- */
  const selections = rw.stronger_arm.selections;
  const replication = rw.replication_arm.best;
  const detection = rw.flags.detection.filter((d) => boardWindows.includes(d.window));
  const flagKeys = Array.from(new Set(detection.map((d) => d.flag)));
  const maxDetection = (w: string) => Math.max(...detection.filter((d) => d.window === w).map((d) => d.simulated_detection_rate));

  /* ---- weights ---- */
  const inUse = boardWindows
    .map((w) => rw.weights.detail.find((r) => r.method === board.carry_method && r.window === w && r.target === board.weights_target))
    .filter((r): r is NonNullable<typeof r> => r !== undefined);
  const weightsDomain = intervalDomain(
    inUse.flatMap((r) => [
      { lo: r.best_ci[0], hi: r.best_ci[1] },
      { lo: r.nba_ci[0], hi: r.nba_ci[1] },
      { lo: r.best_minus_nba_ci[0], hi: r.best_minus_nba_ci[1] },
    ]),
  );
  const flatAll = weightRows.filter((r) => r.n_within === Math.max(...weightRows.map((x) => x.n_within))).length;
  const diffIncludesZero = weightRows.filter((r) => r.diff_lo <= 0 && r.diff_hi >= 0).length;
  const tableDomain = intervalDomain(weightRows.map((r) => ({ lo: r.diff_lo, hi: r.diff_hi })));

  /* ---- measures flags ---- */
  const flagRows: MeasuresFlagRow[] = mm.flags.rows;
  const flagDomain = intervalDomain(
    flagRows.filter((r) => r.added_to_baseline).map((r) => ({ lo: r.added_to_baseline!.ci_95[0], hi: r.added_to_baseline!.ci_95[1] })),
  );

  const compDomain = intervalDomain([
    { lo: cs.pooled_ci_95[0], hi: cs.pooled_ci_95[1] },
    ...Object.values(cs.comparisons).map((c) => ({ lo: c.ci[0], hi: c.ci[1] })),
  ]);

  return (
    <article className="space-y-10">
      <header className="space-y-3">
        <p className="text-xs">
          <Link href="/momentum" className={linkClass}>
            Back to the Momentum Board
          </Link>
        </p>
        <h1 className="text-2xl font-bold text-slate-100">Momentum Board methodology</h1>
        <p className="text-sm text-slate-400 max-w-3xl">
          How the board is built, and everything the two studies behind it tested. Every number on this page is read from
          the studies&apos; results files at a fixed commit (listed under Sources).
        </p>
        <nav aria-label="On this page" className={card}>
          <h2 className="text-sm font-semibold text-slate-100 mb-2">On this page</h2>
          <ol className="grid gap-1 text-xs sm:grid-cols-2">
            {METHODOLOGY_SECTIONS.map((s) => (
              <li key={s.id}>
                <a href={`#${s.id}`} className={`inline-flex min-h-6 items-center ${linkClass}`}>
                  {s.title}
                </a>
              </li>
            ))}
          </ol>
        </nav>
      </header>

      <Section id="not-a-forecast" title="Recent play, not a forecast">
        <div className={`${card} space-y-2 text-sm text-slate-300`} data-testid="methodology-headline">
          <p>
            The board describes how teams have played lately. It does not predict the next game. Once a team&apos;s Elo rating
            is known, recent form added nothing that could be measured:
          </p>
          <ul className="list-disc pl-5 space-y-1">
            <li>
              Window study: <span className={mono}>{beyondAbove}</span> of <span className={mono}>{beyond.length}</span>{' '}
              scored combinations of stat, season-start method and window had a 95% interval above zero for what they add
              to Elo ({beyondTargets.map(targetText).join('; ')})
              {beyondUnscored > 0 ? `; ${beyondUnscored} more had no games to score` : ''}.
            </li>
            <li>
              Score weights: <span className={mono}>{weightBestAbove}</span> of <span className={mono}>{weightRows.length}</span>{' '}
              best weightings had a 95% interval above zero for {targetText(board.weights_target)}.
            </li>
            <li>
              Measures study: <span className={mono}>{singleCounts.kept}</span> of{' '}
              <span className={mono}>{mm.single_feature_results.length}</span> single measures kept (
              {singleCounts.inconclusive} inconclusive, {singleCounts.discarded} discarded). Combination search: {cs.final_verdict}.
            </li>
          </ul>
          <p className="text-xs text-slate-400">
            Baseline in the measures study: {mm.study.baseline}. Elo in the window study: {rw.meta.elo}.
          </p>
        </div>
      </Section>

      <Section id="windows" title="Window lengths">
        <p className="text-sm text-slate-300">
          The board shows the last {board.windows.join(', ')} games. The shortest is the noisiest: with so few games the luck
          checks below can almost never tell a real change from chance. The window study picked windows by this rule:{' '}
          {rw.stronger_arm.selection_rule}.
        </p>
        <div className={tableWrap} tabIndex={0} role="region" aria-label="Window selections">
          <table className="w-full min-w-[44rem] text-xs">
            <caption className="sr-only">Best and chosen window for each stat, season-start method and target</caption>
            <thead className="bg-surface-raised/60 text-slate-300">
              <tr>
                <th scope="col" className={th}>Stat</th>
                <th scope="col" className={th}>Season start</th>
                <th scope="col" className={th}>Target</th>
                <th scope="col" className={th}>Best window</th>
                <th scope="col" className={th}>Shortest inside its interval</th>
                <th scope="col" className={th}>Windows inside</th>
              </tr>
            </thead>
            <tbody>
              {selections.map((s) => (
                <tr key={`${s.feature}|${s.method}|${s.target}`} className="border-t border-slate-800 text-slate-300">
                  <td className={td}>{s.feature}</td>
                  <td className={td}>{s.method}</td>
                  <td className={td}>{targetText(s.target)}</td>
                  <td className={`${td} ${mono}`}>
                    {windowLabel(s.best)} <span className="text-slate-400">({s.best_score} [{s.best_lo}, {s.best_hi}])</span>
                  </td>
                  <td className={`${td} ${mono}`}>
                    {windowLabel(s.chosen)} <span className="text-slate-400">({s.chosen_score})</span>
                  </td>
                  <td className={`${td} ${mono} text-slate-400`}>{s.windows_within}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
        <p className="text-sm text-slate-300">
          Replication of the original rolling-window model on the {rw.replication_arm.test_season} season:
        </p>
        <div className={tableWrap} tabIndex={0} role="region" aria-label="Replication results">
          <table className="w-full min-w-[36rem] text-xs">
            <thead className="bg-surface-raised/60 text-slate-300">
              <tr>
                <th scope="col" className={th}>Variant</th>
                <th scope="col" className={th}>Best window</th>
                <th scope="col" className={th}>ROC-AUC [95%]</th>
                <th scope="col" className={th}>Test games</th>
                <th scope="col" className={th}>Windows inside the best interval</th>
              </tr>
            </thead>
            <tbody>
              {replication.map((r) => (
                <tr key={r.variant} className="border-t border-slate-800 text-slate-300">
                  <td className={td}>{r.variant}</td>
                  <td className={`${td} ${mono}`}>{r.best_window}</td>
                  <td className={`${td} ${mono}`}>
                    {r.roc_auc} [{r.auc_lo}, {r.auc_hi}]
                  </td>
                  <td className={`${td} ${mono}`}>{r.test_games}</td>
                  <td className={`${td} ${mono} text-slate-400`}>{r.windows_inside_best_interval}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </Section>

      <Section id="carry-over" title="Season start: carried games">
        <p className="text-sm text-slate-300">
          Early in a season a team has fewer games than the window. The board uses the{' '}
          <span className="font-semibold text-slate-100">{board.carry_method}</span> method and labels every team whose window
          includes last season&apos;s games. The methods the study compared:
        </p>
        <dl className={`${card} grid gap-2 text-xs sm:grid-cols-[auto_1fr]`}>
          {Object.entries(rw.meta.offseason_methods).map(([k, v]) => (
            <React.Fragment key={k}>
              <dt className={`font-semibold ${k === board.carry_method ? 'text-accent-400' : 'text-slate-100'}`}>
                {k}
                {k === board.carry_method ? ' (board)' : ''}
              </dt>
              <dd className="text-slate-300">{v}</dd>
            </React.Fragment>
          ))}
        </dl>
        <p className="text-xs text-slate-400">Opponent adjustment: {rw.meta.opponent_adjustment}.</p>
      </Section>

      <Section id="weights-in-use" title="Score weights in use">
        <p className="text-sm text-slate-300">
          The combined score is a weighted sum of {rw.weights.components.map((c) => COMPONENT_TEXT[c] ?? c).join(', ')}, each{' '}
          {rw.weights.standardisation}. Weights searched: {rw.weights.grid}. Scored by {rw.weights.score}. The board uses the
          best weighting at each window ({board.carry_method}, {targetText(board.weights_target)}):
        </p>
        <div className={tableWrap} tabIndex={0} role="region" aria-label="Weights in use">
          <table className="w-full min-w-[48rem] text-xs" data-testid="methodology-weights">
            <thead className="bg-surface-raised/60 text-slate-300">
              <tr>
                <th scope="col" className={th}>Window</th>
                {order.map((c) => (
                  <th key={c} scope="col" className={`${th} text-right`}>
                    {COMPONENT_TEXT[c] ?? c}
                  </th>
                ))}
                <th scope="col" className={th}>Held-out R² [95%]</th>
                <th scope="col" className={th}>Equal weights R² [95%]</th>
                <th scope="col" className={th}>Form only R² [95%]</th>
              </tr>
            </thead>
            <tbody>
              {inUse.map((r) => (
                <tr key={r.window} className="border-t border-slate-800 text-slate-300">
                  <th scope="row" className={`${td} text-left font-normal`}>
                    {windowLabel(r.window)}
                  </th>
                  {r.best_weights.map((w, i) => (
                    <td key={order[i]} className={`${td} ${mono} text-right text-slate-100`}>
                      {pct(w)}
                    </td>
                  ))}
                  <td className={td}>
                    <IntervalCell lo={r.best_ci[0]} hi={r.best_ci[1]} point={r.best_r2} domain={weightsDomain} />
                  </td>
                  <td className={`${td} ${mono}`}>{fmtInterval(r.equal_ci[0], r.equal_ci[1])}</td>
                  <td className={`${td} ${mono}`}>{fmtInterval(r.form_only_ci[0], r.form_only_ci[1])}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
        <p className="text-xs text-slate-400">{board.selection}</p>
      </Section>

      <Section id="flat-surface" title="Why the weights are not a finding">
        <div className={`${card} space-y-2 text-sm text-slate-300`} data-testid="methodology-flat">
          <p>
            The score surface is flat. At every board window,{' '}
            {inUse.map((r, i) => (
              <React.Fragment key={r.window}>
                {i > 0 ? '; ' : ''}
                <span className={mono}>{r.flat_n_within_best_ci}</span> weightings ({pct(r.flat_share_within)}) at {r.window}{' '}
                games
              </React.Fragment>
            ))}{' '}
            score inside the best weighting&apos;s 95% interval. Across all {weightRows.length} method, window and target cells,{' '}
            {flatAll} have the most weightings inside, and in {diffIncludesZero} of {weightRows.length} the best weighting&apos;s
            lead over the NBA-style weighting has an interval that includes zero.
          </p>
          <p>
            The NBA board&apos;s weighting, form {pct(nba.form)} / trend {pct(nba.trend)} / margin vs Elo {pct(nba.residual)} /
            Elo change {pct(nba.elo_change)}, was equally supported:
          </p>
          <ul className="list-disc pl-5 space-y-1 text-xs">
            {inUse.map((r) => (
              <li key={r.window} className="flex flex-wrap items-center gap-2">
                <span>{windowLabel(r.window)}: best minus NBA-style</span>
                <IntervalCell
                  lo={r.best_minus_nba_ci[0]}
                  hi={r.best_minus_nba_ci[1]}
                  point={r.best_minus_nba}
                  domain={weightsDomain}
                />
                <span className="text-slate-400">({intervalWord(r.best_minus_nba_ci[0], r.best_minus_nba_ci[1])})</span>
              </li>
            ))}
          </ul>
          <p className="text-xs text-slate-400" data-testid="nba-weights-provenance">
            {nba.provenance.note} {nba.provenance.rule} Source: {nba.provenance.file} line {nba.provenance.line} at commit{' '}
            <span className={mono}>{nba.provenance.commit.slice(0, 7)}</span>.
          </p>
        </div>
        <details className={card}>
          <summary className="cursor-pointer text-sm font-semibold text-slate-100">
            Every weighting cell ({weightRows.length})
          </summary>
          <div className={`${tableWrap} mt-3`} tabIndex={0} role="region" aria-label="Every weighting cell">
            <table className="w-full min-w-[48rem] text-xs">
              <thead className="bg-surface-raised/60 text-slate-300">
                <tr>
                  <th scope="col" className={th}>Season start</th>
                  <th scope="col" className={th}>Window</th>
                  <th scope="col" className={th}>Best weighting</th>
                  <th scope="col" className={th}>Best R²</th>
                  <th scope="col" className={th}>NBA-style R²</th>
                  <th scope="col" className={th}>Best minus NBA-style [95%]</th>
                  <th scope="col" className={th}>Inside best interval</th>
                </tr>
              </thead>
              <tbody>
                {weightRows.map((r) => (
                  <tr key={`${r.method}|${r.window}|${r.target}`} className="border-t border-slate-800 text-slate-300">
                    <td className={td}>{r.method}</td>
                    <td className={`${td} ${mono}`}>{r.window}</td>
                    <td className={`${td} ${mono}`}>{r.best}</td>
                    <td className={`${td} ${mono}`}>{fmtSigned(r.best_r2, 6)}</td>
                    <td className={`${td} ${mono}`}>{fmtSigned(r.nba_r2, 6)}</td>
                    <td className={td}>
                      <IntervalCell lo={r.diff_lo} hi={r.diff_hi} point={(r.diff_lo + r.diff_hi) / 2} domain={tableDomain} digits={6} />
                    </td>
                    <td className={`${td} ${mono}`}>{r.n_within}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
          <p className="mt-2 text-[11px] text-slate-400">The dot on each bar marks the interval midpoint; the table does not publish a point difference.</p>
        </details>
      </Section>

      <Section id="badges-hidden" title="Why flags carry no badge">
        <p className="text-sm text-slate-300" data-testid="methodology-badges">
          A badge would claim a flag is unusual beyond chance. Simulation shows the luck checks rarely detect a real effect in
          this few games: at the board windows the highest simulated detection rate is{' '}
          {boardWindows.map((w, i) => (
            <React.Fragment key={w}>
              {i > 0 ? ', ' : ''}
              <span className={mono}>{pct(maxDetection(w))}</span> at {w} games
            </React.Fragment>
          ))}
          , all below the {pct(rw.flags.power_threshold)} detection rate a badge would need. So the board shows raw values only.
          Opponent strength, home share and rest are context, not judgements. {rw.flags.note}.
        </p>
        <div className={tableWrap} tabIndex={0} role="region" aria-label="Simulated detection rates">
          <table className="w-full min-w-[40rem] text-xs">
            <caption className="sr-only">Simulated detection rate of each flag at the board windows</caption>
            <thead className="bg-surface-raised/60 text-slate-300">
              <tr>
                <th scope="col" className={th}>Flag</th>
                <th scope="col" className={th}>Statistic</th>
                {boardWindows.map((w) => (
                  <th key={w} scope="col" className={`${th} text-right`}>
                    {w} games
                  </th>
                ))}
              </tr>
            </thead>
            <tbody>
              {flagKeys.map((k) => {
                const def = rw.flags.definitions[k];
                return (
                  <tr key={k} className="border-t border-slate-800 text-slate-300 align-top">
                    <th scope="row" className={`${td} text-left font-normal text-slate-100`}>
                      {def?.label ?? k}
                      {def?.caveat ? <span className="block text-[11px] text-slate-400">{def.caveat}</span> : null}
                    </th>
                    <td className={`${td} text-slate-400`}>{def?.test ?? ''}</td>
                    {boardWindows.map((w) => {
                      const d = detection.find((x) => x.flag === k && x.window === w);
                      return (
                        <td key={w} className={`${td} ${mono} text-right`}>
                          {d ? pct(d.simulated_detection_rate) : '–'}
                        </td>
                      );
                    })}
                  </tr>
                );
              })}
            </tbody>
          </table>
        </div>
      </Section>

      <Section id="availability" title="Key players and data coverage">
        <p className="text-sm text-slate-300">
          Key players missing is shown as a raw share with no badge. Injury and snap data are both complete (at least{' '}
          {pct(rw.availability.covered_threshold)} of team-weeks) from {rw.availability.fully_covered_from}; before that, or when
          a feed is missing, the board shows the reason instead of a value. League rate across{' '}
          {rw.availability.key_players.team_seasons} team-seasons: {pct(rw.availability.key_players.rate_league)} of key
          player-games missed.
        </p>
        <div className={tableWrap} tabIndex={0} role="region" aria-label="Availability data coverage">
          <table className="w-full min-w-[28rem] text-xs">
            <thead className="bg-surface-raised/60 text-slate-300">
              <tr>
                <th scope="col" className={th}>Season</th>
                <th scope="col" className={`${th} text-right`}>Injury report coverage</th>
                <th scope="col" className={`${th} text-right`}>Snap count coverage</th>
                <th scope="col" className={th}>Both complete</th>
              </tr>
            </thead>
            <tbody>
              {rw.availability.coverage.map((c) => (
                <tr key={c.season} className="border-t border-slate-800 text-slate-300">
                  <td className={`${td} ${mono}`}>{c.season}</td>
                  <td className={`${td} ${mono} text-right`}>{pct(c.injury_share)}</td>
                  <td className={`${td} ${mono} text-right`}>{pct(c.snaps_share)}</td>
                  <td className={td}>{c.both_full ? 'yes' : 'no'}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </Section>

      <Section id="qb-change" title="Starting-QB change and other flags">
        <p className="text-sm text-slate-300">
          The measures study tested these flags on their own, each added to its baseline. The board shows a starting-QB change
          as context only: it is not part of the score and carries no badge.
        </p>
        <dl className={`${card} grid gap-2 text-xs sm:grid-cols-[auto_1fr]`}>
          {Object.entries(mm.flags.definitions).map(([k, v]) => (
            <React.Fragment key={k}>
              <dt className="font-semibold text-slate-100">{k}</dt>
              <dd className="text-slate-300">{v}</dd>
            </React.Fragment>
          ))}
        </dl>
        <div className={tableWrap} tabIndex={0} role="region" aria-label="Flag results">
          <table className="w-full min-w-[52rem] text-xs" data-testid="methodology-flag-rows">
            <thead className="bg-surface-raised/60 text-slate-300">
              <tr>
                <th scope="col" className={th}>Flag</th>
                <th scope="col" className={th}>Target</th>
                <th scope="col" className={`${th} text-right`}>Flagged rows</th>
                <th scope="col" className={th}>Gain over baseline [95%]</th>
                <th scope="col" className={th}>Verdict</th>
                <th scope="col" className={th}>Reason</th>
              </tr>
            </thead>
            <tbody>
              {flagRows.map((r) => (
                <tr key={`${r.flag}|${r.target}`} className="border-t border-slate-800 text-slate-300 align-top">
                  <td className={td}>
                    {r.flag}
                    <span className="block text-[11px] text-slate-400">{r.definition}</span>
                  </td>
                  <td className={td}>{targetText(r.target)}</td>
                  <td className={`${td} ${mono} text-right`}>
                    {r.flagged_rows} of {r.rows}
                  </td>
                  <td className={td}>
                    {r.added_to_baseline ? (
                      <>
                        <span className={`${mono} text-slate-100`}>{fmtSigned(r.added_to_baseline.r2_gain)}</span>
                        <IntervalCell
                          lo={r.added_to_baseline.ci_95[0]}
                          hi={r.added_to_baseline.ci_95[1]}
                          point={r.added_to_baseline.r2_gain}
                          domain={flagDomain}
                        />
                      </>
                    ) : (
                      <span className="text-slate-400">not modelled (descriptive row)</span>
                    )}
                  </td>
                  <td className={td}>
                    <VerdictBadge verdict={r.verdict} />
                  </td>
                  <td className={td}>{r.reason}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </Section>

      <Section id="everything-tried" title="Everything the measures study tried">
        <p className="text-sm text-slate-300">
          {mm.series.length} stats x {mm.measures.length} measures (borrowed from{' '}
          {Array.from(new Set(mm.measures.map((m) => m.field_of_origin.replace(/\s*\(.*\)$/, '')))).join(', ')}), each tested against{' '}
          {mm.targets.length} targets. {mm.study.title}
        </p>
        <details className={card}>
          <summary className="cursor-pointer text-sm font-semibold text-slate-100">The measures and stats</summary>
          <div className="mt-3 grid gap-4 text-xs md:grid-cols-2">
            <dl className="space-y-2">
              {mm.measures.map((m) => (
                <div key={m.id}>
                  <dt className="font-semibold text-slate-100">
                    {m.name} <span className="font-normal text-slate-400">({m.field_of_origin})</span>
                  </dt>
                  <dd className="text-slate-300">{m.forward_only_definition}</dd>
                </div>
              ))}
            </dl>
            <dl className="space-y-2">
              {mm.series.map((s) => (
                <div key={s.id}>
                  <dt className="font-semibold text-slate-100">{s.name}</dt>
                  <dd className="text-slate-300">{s.definition}</dd>
                </div>
              ))}
              {mm.targets.map((t) => (
                <div key={t.id}>
                  <dt className="font-semibold text-slate-100">
                    Target: {t.id}
                    {t.primary ? ' (main)' : ''}
                  </dt>
                  <dd className="text-slate-300">{t.definition}</dd>
                </div>
              ))}
            </dl>
          </div>
        </details>
        <MethodologyResultsTable rows={mm.single_feature_results} targets={mm.targets} measures={mm.measures} series={mm.series} />
      </Section>

      <Section id="combination-search" title="The combination search">
        <div className={`${card} space-y-3 text-sm text-slate-300`}>
          <p>
            Best combination for {targetText(cs.target)} ({cs.rows} rows): pooled gain{' '}
            <span className={mono}>{fmtSigned(cs.pooled_r2_gain)}</span>
          </p>
          <IntervalCell lo={cs.pooled_ci_95[0]} hi={cs.pooled_ci_95[1]} point={cs.pooled_r2_gain} domain={compDomain} />
          <ul className="space-y-1 text-xs">
            {Object.entries(cs.comparisons).map(([k, c]) => (
              <li key={k} className="flex flex-wrap items-center gap-2">
                <span>{COMPARISON_TEXT[k] ?? k}:</span>
                <span className={mono}>{fmtSigned(c.r2_gain)}</span>
                <IntervalCell lo={c.ci[0]} hi={c.ci[1]} point={c.r2_gain} domain={compDomain} />
              </li>
            ))}
          </ul>
          <p className="text-xs">
            Shuffled-outcome baseline ({cs.permutation.runs} runs): mean {fmtSigned(cs.permutation.mean)}, 95th percentile{' '}
            {fmtSigned(cs.permutation.p95)}, max {fmtSigned(cs.permutation.max)}; {pct(cs.permutation.share_at_or_above_real)} of
            runs did as well as the real search.
          </p>
          <p className="text-xs">
            Chosen: stats {cs.final_choice.series.join(', ')}; measures {cs.final_choice.measures.join(', ')}.
          </p>
          <ul className="space-y-1 text-xs">
            {Object.entries(cs.reliability_checks).map(([k, v]) => (
              <Check key={k} ok={v}>
                {CHECK_TEXT[k] ?? k}
              </Check>
            ))}
          </ul>
          <p className="text-xs font-semibold text-slate-100">Verdict: {cs.final_verdict}</p>
        </div>
      </Section>

      <Section id="holdout-and-limits" title="Forward test, protocol and limits">
        <div className={`${card} space-y-2 text-xs text-slate-300`}>
          <p>Forward test: {mm.study.holdout}</p>
          <p>{mm.holdout.note}</p>
          <details>
            <summary className="cursor-pointer pt-2 font-semibold text-slate-100">Protocol</summary>
            <ul className="mt-1 list-disc pl-5 space-y-0.5">
              {mm.study.protocol.map((p) => (
                <li key={p}>{p}</li>
              ))}
            </ul>
          </details>
          <details>
            <summary className="cursor-pointer pt-2 font-semibold text-slate-100">
              Limits, as the measures study recorded them before the board existed
            </summary>
            <ul className="mt-1 list-disc pl-5 space-y-0.5">
              {mm.limits.map((l) => (
                <li key={l}>{l}</li>
              ))}
            </ul>
          </details>
          <p className="text-slate-400">
            Window study: seasons {rw.meta.seasons_loso[0]}-{rw.meta.seasons_loso[rw.meta.seasons_loso.length - 1]} left out one
            at a time, {rw.meta.n_boot} bootstrap resamples, {rw.meta.n_sim} simulations per flag.
          </p>
        </div>
      </Section>

      <Section id="sources" title="Sources">
        <ul className={`${card} space-y-2 text-xs text-slate-300`} data-testid="methodology-sources">
          {[srcRw, srcMm].map((s) => (
            <li key={s.file}>
              <span className="text-slate-100">{s.file}</span> (issue #{s.issue}, merged in #{s.merged_in}), commit{' '}
              <span className={mono}>{s.commit.slice(0, 7)}</span>; report {s.report}; script {s.script}.
            </li>
          ))}
          <li>
            Board settings:{' '}
            <a href={board.settings_url} className={linkClass}>
              owner decisions on issue #{data.board_issue}
            </a>
            .
          </li>
        </ul>
        <p className="text-xs">
          <Link href="/momentum" className={linkClass}>
            Back to the Momentum Board
          </Link>
        </p>
      </Section>
    </article>
  );
};
