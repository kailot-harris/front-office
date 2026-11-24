import React from 'react';
import Link from 'next/link';
import type {
  BlendWeights,
  Delta,
  FamilyGroup,
  HoldoutCell,
  MomentumMethodologyPayload,
  MomentumVerdict,
} from '@/lib/momentumMethodologyTypes';
import { MethodologyResultsTable } from '@/components/MethodologyResultsTable';
import { GlossaryTerm } from '@/components/GlossaryTerm';
import { HowToReadDisclosure } from '@/components/HowToReadDisclosure';
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
 * /momentum/methodology: how the Momentum Board was tested. Every figure on
 * this page is read from momentum_methodology.json (the study's results file,
 * copied by tools/publish_momentum_methodology.R). Wording only lives here.
 */

export const METHODOLOGY_SECTIONS = [
  { id: 'what-the-board-uses', title: 'What the board uses and why' },
  { id: 'how-it-was-tested', title: 'How it was tested' },
  { id: 'everything-tried', title: 'Everything we tried' },
  { id: 'the-measures', title: 'The measures' },
  { id: 'redundancy', title: 'Measures that say the same thing' },
  { id: 'combination-search', title: 'The combination search' },
  { id: 'blend-weights', title: 'Blend weights per window' },
  { id: 'holdout-and-limits', title: 'Holdout, limits and source' },
] as const;

const card = 'rounded-xl border border-slate-800 bg-surface-raised/60 p-4';
const tableWrap = 'overflow-x-auto rounded-lg border border-slate-800';
const th = 'px-2 py-2 font-semibold';
const td = 'px-2 py-1.5';
const mono = 'font-mono tabular-nums';

const Section: React.FC<{ id: string; title: string; children: React.ReactNode }> = ({ id, title, children }) => (
  <section id={id} aria-labelledby={`${id}-h`} className="space-y-3 scroll-mt-20">
    <h2 id={`${id}-h`} className="text-lg font-semibold text-slate-100">
      {title}
    </h2>
    {children}
  </section>
);

const weightsText = (w: BlendWeights) => `form ${pct(w.form)} / trend ${pct(w.trend)} / Elo change ${pct(w.elo)}`;

const DeltaCell: React.FC<{ d: Delta; domain: [number, number] }> = ({ d, domain }) => (
  <div className="flex items-center gap-2">
    <IntervalBar lo={d.ci_lo} hi={d.ci_hi} point={d.delta} domain={domain} width={96} />
    <span className={`whitespace-nowrap ${mono} text-slate-200`}>
      {fmtSigned(d.delta)} <span className="text-slate-400">{fmtInterval(d.ci_lo, d.ci_hi)}</span>
    </span>
  </div>
);

const groupLabel = (g: FamilyGroup, names: Record<string, string>) =>
  (Array.isArray(g) ? g : [g]).map((x) => names[x] ?? x).join(', ');

function verdictCounts<T extends { verdict: MomentumVerdict }>(rows: T[]): Record<MomentumVerdict, number> {
  const c: Record<MomentumVerdict, number> = { kept: 0, inconclusive: 0, discarded: 0 };
  for (const r of rows) c[r.verdict] += 1;
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

const CHECK_TEXT: Record<string, string> = {
  ci_above_zero: 'The 95% interval of the gain on unseen seasons is above zero.',
  beats_permutation_p95: 'It beats 95% of the shuffled-outcome runs.',
  stable_selection: 'The same stats and measures (or the same families) are picked in at least half the held-out seasons.',
  sign_holds_most_seasons: 'The gain is positive in most held-out seasons.',
};

const comparisonText = (featureCount: number): Record<string, string> => ({
  elastic_net: `All ${featureCount} features at once, shrunk toward zero (elastic net)`,
  greedy_forward: 'Adding the best feature one at a time (greedy forward selection)',
  board_current_score_w10: 'The board as it is today (momentum score, last 10 games)',
});

export const MomentumMethodology: React.FC<{ data: MomentumMethodologyPayload }> = ({ data }) => {
  const { study, targets, measures, series, single_feature_results: results, families, combination_search: cs } = data;
  const primary = targets.find((t) => t.primary) ?? targets[0];
  const measureName = Object.fromEntries(measures.map((m) => [m.id, m.name]));
  const seriesName = Object.fromEntries(series.map((s) => [s.id, s.name]));
  const allCounts = verdictCounts(results);
  const primaryRows = results.filter((r) => r.target === primary.id);
  const primaryCounts = verdictCounts(primaryRows);
  const sensCounts = verdictCounts(data.single_feature_sensitivity_primary);
  const looSeasons = study.seasons.filter((s) => s.role.startsWith('LOSO'));
  const flagged = study.seasons.filter((s) => s.role.includes('flagged'));
  const holdoutSeason = study.seasons.find((s) => s.role.includes('holdout'));
  const fdrLine = study.protocol.find((p) => p.toLowerCase().includes('false discovery')) ?? '';
  const featuresPerTarget = measures.length * series.length;
  const blend = [...data.blend_weights].sort((a, b) => a.window - b.window);
  const loso = blend.map((b) => ({ window: b.window, word: intervalWord(b.loso_selected.vs_current.ci_lo, b.loso_selected.vs_current.ci_hi) }));
  const blendDomain = intervalDomain(
    blend.flatMap((b) => [b.best_vs_current, b.loso_selected.vs_current, b.nonnegative_regression.vs_current]).map((d) => ({ lo: d.ci_lo, hi: d.ci_hi })),
  );
  const otherDomain = intervalDomain(
    blend
      .flatMap((b) => [b.next5.best_vs_current, b.trend_swap.swap.vs_best_3_component, b.sensitivity_without_2019_20_2020_21.loso_selected_vs_current])
      .map((d) => ({ lo: d.ci_lo, hi: d.ci_hi })),
  );
  const compDomain = intervalDomain([
    { lo: cs.pooled_ci_95[0], hi: cs.pooled_ci_95[1] },
    ...Object.values(cs.comparisons).map((c) => ({ lo: c.ci[0], hi: c.ci[1] })),
    { lo: cs.sensitivity_without_2019_20_2020_21.pooled_ci_95[0], hi: cs.sensitivity_without_2019_20_2020_21.pooled_ci_95[1] },
  ]);
  const stab = cs.selection_stability;
  const perm = cs.permutation;
  const realGain = cs.pooled_r2_gain;
  const permLo = Math.min(perm.mean, perm.p95, perm.max, realGain);
  const permHi = Math.max(perm.mean, perm.p95, perm.max, realGain);
  const permPad = (permHi - permLo) * 0.1 || 1e-6;
  const px = (v: number) => 10 + ((v - (permLo - permPad)) / (permHi - permLo + 2 * permPad)) * 580;
  const measureMeta = measures.map((m) => ({ ...m, counts: verdictCounts(primaryRows.filter((r) => r.measure === m.id)) }));
  const multiClusters = families.feature_clusters_abs_r_0_7.filter((c) => Array.isArray(c) && c.length > 1).length;
  const holdoutCells: { label: string; cell: HoldoutCell }[] = [
    { label: 'Combination search pick', cell: data.holdout.part_a.primary },
    { label: 'Combination search pick', cell: data.holdout.part_a.next5 },
    ...Object.entries(data.holdout.part_b).flatMap(([w, byTarget]) =>
      Object.values(byTarget).map((cell) => ({ label: `Blend weights, window ${w.replace(/^w/, '')}`, cell })),
    ),
  ];
  const shortCommit = data.source_commit.slice(0, 7);
  const nothingBeatCurrent = loso.every((l) => l.word !== 'above zero');
  const comboShape = `${cs.final_choice.series.length} stats x ${cs.final_choice.measures.length} measures`;
  const featureLabel = (f: string) => {
    const [s, m] = f.split('__');
    return `${measureName[m] ?? m} of ${seriesName[s] ?? s}`;
  };

  return (
    <div className="space-y-10">
      <header className="space-y-3">
        <p className="text-xs">
          <Link href="/momentum" className="text-indigo-300 underline-offset-2 hover:underline focus-visible:outline focus-visible:outline-2 focus-visible:outline-accent">
            Back to the Momentum Board
          </Link>
        </p>
        <h1 className="text-2xl font-bold text-slate-100">Momentum Board: methodology and everything we tested</h1>
        <p className="max-w-3xl text-sm text-slate-400">
          {study.title} Study run {study.run_date}. Every number on this page is read from the study&apos;s own results
          file (source commit <span className={mono}>{shortCommit}</span>). Results that found nothing are shown with
          the same weight as results that found something.
        </p>
        <nav aria-label="On this page" className="text-xs">
          <ol className="flex flex-wrap gap-x-4 gap-y-1 text-slate-300">
            {METHODOLOGY_SECTIONS.map((s, i) => (
              <li key={s.id}>
                <a href={`#${s.id}`} className="inline-flex min-h-6 items-center underline-offset-2 hover:underline focus-visible:outline focus-visible:outline-2 focus-visible:outline-accent">
                  {i + 1}. {s.title}
                </a>
              </li>
            ))}
          </ol>
        </nav>
      </header>

      <HowToReadDisclosure pageKey="momentum-methodology">
        Each test asks one thing: does a measure predict a team&apos;s next games better than team strength alone, on
        seasons the model never saw? The gain is that improvement (0 is none; below 0 is worse). The 95% interval is the
        range the gain plausibly falls in; when it includes zero, the measure is not shown to help. Verdicts: kept
        (interval above zero and it survives the correction for testing many ideas), discarded (no gain at all) and
        inconclusive (a small gain whose interval includes zero).
      </HowToReadDisclosure>

      {/* 1 */}
      <Section {...METHODOLOGY_SECTIONS[0]}>
        <div className={`${card} space-y-3 text-sm text-slate-300`}>
          <p>
            The board blends four parts: recent form against the opponents faced, the net rating trend, how a team did
            against the model&apos;s pregame expectation, and its <GlossaryTerm term="Elo" /> change. The study asked two
            questions: does any momentum measure add to team strength (pregame Elo plus season-to-date{' '}
            <GlossaryTerm term="net rating" />), and are the board&apos;s blend weights right?
          </p>
          <ul className="space-y-1.5">
            {blend.map((b) => (
              <li key={b.window}>
                <span className="font-semibold text-slate-100">Last {b.window} games:</span> {b.recommendation}. The
                study tested the three parts that exist in every season at {weightsText(b.current_weights)} (the model
                part exists only for the current season, so it was left out and the rest rescaled).
              </li>
            ))}
          </ul>
          <p>
            <span className="font-semibold text-slate-100">New momentum measures kept:</span> {allCounts.kept} of{' '}
            {results.length} tried ({allCounts.inconclusive} inconclusive, {allCounts.discarded} discarded). The
            combination search verdict: {cs.final_verdict}.
          </p>
          <p>
            <span className="font-semibold text-slate-100">Strength of evidence:</span>{' '}
            {nothingBeatCurrent ? 'no alternative mix earned a change.' : 'at least one window has a better mix.'} Weights picked
            on training seasons only, compared with the current ones on unseen seasons, give a 95% interval that{' '}
            {loso.map((l, i) => (
              <React.Fragment key={l.window}>
                {i > 0 && (i === loso.length - 1 ? ' and ' : ', ')}
                {l.word} at {l.window} games
              </React.Fragment>
            ))}
            .
          </p>
        </div>
      </Section>

      {/* 2 */}
      <Section {...METHODOLOGY_SECTIONS[1]}>
        <ol className="grid gap-3 md:grid-cols-2">
          <li className={card}>
            <h3 className="text-sm font-semibold text-slate-100">1. Train on some seasons, score on an unseen one</h3>
            <p className="mt-1 text-sm text-slate-300">
              Each of the {looSeasons.length} seasons from {looSeasons[0]?.season} to{' '}
              {looSeasons[looSeasons.length - 1]?.season} is held out in turn; everything is fitted on the others and
              scored on the one left out. A measure that only fits noise in the seasons it saw scores badly on the one
              it did not.
            </p>
          </li>
          <li className={card}>
            <h3 className="text-sm font-semibold text-slate-100">2. {holdoutSeason?.season ?? 'The current season'} held back and scored once</h3>
            <p className="mt-1 text-sm text-slate-300">
              {study.holdout}. Because no choice could be changed after seeing it, it cannot be tuned to look good.
            </p>
          </li>
          <li className={card}>
            <h3 className="text-sm font-semibold text-slate-100">3. A correction for testing many ideas</h3>
            <p className="mt-1 text-sm text-slate-300">
              With {featuresPerTarget} features per target, some would look good by luck alone. {fdrLine}. A measure is
              kept only if its 95% interval is above zero and it survives this correction.
            </p>
          </li>
          <li className={card}>
            <h3 className="text-sm font-semibold text-slate-100">4. A shuffled-outcome baseline</h3>
            <p className="mt-1 text-sm text-slate-300">
              The whole search was rerun {perm.runs} times with the outcomes shuffled among teams on each date. That
              shows how good pure chance looks; a real finding has to beat it.
            </p>
          </li>
        </ol>
        <details className={`${card} text-sm text-slate-300`}>
          <summary className="cursor-pointer font-semibold text-slate-100">Full protocol and seasons</summary>
          <ul className="mt-2 list-disc space-y-1 pl-5">
            {study.protocol.map((p) => (
              <li key={p}>{p}</li>
            ))}
          </ul>
          <div className={`${tableWrap} mt-3`} tabIndex={0} role="region" aria-label="Seasons in the study and their role">
            <table className="w-full min-w-[36rem] text-left text-xs">
              <caption className="sr-only">Seasons in the study and their role</caption>
              <thead className="bg-surface-raised/60 text-slate-300">
                <tr>
                  <th scope="col" className={th}>Season</th>
                  <th scope="col" className={th}>Role</th>
                  <th scope="col" className={`${th} text-right`}>Games</th>
                  <th scope="col" className={th}>Dates</th>
                </tr>
              </thead>
              <tbody>
                {study.seasons.map((s) => (
                  <tr key={s.season} className="border-t border-slate-800">
                    <td className={td}>{s.season}</td>
                    <td className={td}>{s.role}</td>
                    <td className={`${td} ${mono} text-right`}>{s.games}</td>
                    <td className={td}>
                      {s.first} to {s.last}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
          <p className="mt-2 text-xs text-slate-400">
            {flagged.map((s) => s.season).join(' and ')} stay in and are flagged; a sensitivity run drops them.
          </p>
        </details>
      </Section>

      {/* 3 */}
      <Section {...METHODOLOGY_SECTIONS[2]}>
        <p className="max-w-3xl text-sm text-slate-300">
          Every stat x measure x target the study scored. &quot;Gain&quot; is how much better the next games are
          predicted than by team strength alone, on seasons the model never saw (0 means no better; negative means
          worse). The bar shows the 95% interval against zero. Targets:{' '}
          {targets.map((t, i) => (
            <React.Fragment key={t.id}>
              {i > 0 && '; '}
              <span className={mono}>{t.id}</span>
              {t.primary ? ' (main)' : ''}: {t.definition}
            </React.Fragment>
          ))}
        </p>
        <MethodologyResultsTable rows={results} targets={targets} measures={measures} series={series} />
      </Section>

      {/* 4 */}
      <Section {...METHODOLOGY_SECTIONS[3]}>
        <p className="max-w-3xl text-sm text-slate-300">
          {measures.length} measures, borrowed from different fields, each applied to {series.length} team stats. Every
          one uses only games already played. Verdicts below are for the main target ({primary.id}).
        </p>
        <ul className="grid gap-3 sm:grid-cols-2 lg:grid-cols-3">
          {measureMeta.map((m) => (
            <li key={m.id} className={card} data-testid="measure-card">
              <h3 className="text-sm font-semibold text-slate-100">{m.name}</h3>
              <p className="text-xs text-slate-400">From {m.field_of_origin}</p>
              <p className="mt-2 text-xs leading-relaxed text-slate-300">{m.forward_only_definition}</p>
              <p className="mt-2 flex flex-wrap gap-1.5 text-xs text-slate-300">
                {(['kept', 'inconclusive', 'discarded'] as MomentumVerdict[]).map((v) => (
                  <span key={v} className="inline-flex items-center gap-1">
                    <VerdictBadge verdict={v} /> {m.counts[v]}
                  </span>
                ))}
              </p>
            </li>
          ))}
        </ul>
      </Section>

      {/* 5 */}
      <Section {...METHODOLOGY_SECTIONS[4]}>
        <p className="max-w-3xl text-sm text-slate-300">
          Groups whose values move closely together, as the study grouped them. When most measures fall in one family,
          they say nearly the same thing about a stat, and the useful choice is the stat, not the measure.{' '}
          {families.feature_clusters_abs_r_0_7.length} clusters of strongly correlated features; {multiClusters} hold
          more than one feature.
        </p>
        <div className="grid gap-3 md:grid-cols-2">
          <div className={card}>
            <h3 className="text-sm font-semibold text-slate-100">Measure families</h3>
            <ul className="mt-2 list-disc space-y-1 pl-5 text-sm text-slate-300">
              {families.measure_families.map((g) => (
                <li key={groupLabel(g, measureName)}>{groupLabel(g, measureName)}</li>
              ))}
            </ul>
          </div>
          <div className={card}>
            <h3 className="text-sm font-semibold text-slate-100">Stat families</h3>
            <ul className="mt-2 list-disc space-y-1 pl-5 text-sm text-slate-300">
              {families.series_families.map((g) => (
                <li key={groupLabel(g, seriesName)}>
                  {groupLabel(g, seriesName)}
                  {!Array.isArray(g) && <span className="text-slate-400"> (stands alone)</span>}
                </li>
              ))}
            </ul>
          </div>
        </div>
        <CorrelationGrid title="Measures: average absolute correlation across stats" ids={measures.map((m) => m.id)} names={measureName} matrix={families.measure_mean_abs_r} />
        <CorrelationGrid title="Stats: average absolute correlation across measures" ids={series.map((s) => s.id)} names={seriesName} matrix={families.series_mean_abs_r} />
      </Section>

      {/* 6 */}
      <Section {...METHODOLOGY_SECTIONS[5]}>
        <p className="max-w-3xl text-sm text-slate-300">
          The search looked for a small set of {comboShape} that predicts {cs.target} better than team strength.
          For each held-out season it ranked stats and measures on the training seasons only, tried{' '}
          {cs.final_choice.of_combinations} combinations, picked the best, then scored it on the unseen season. The gain
          on unseen seasons has no interval per single season; the pooled result below has one.
        </p>
        <div className={tableWrap} tabIndex={0} role="region" aria-label="Combination picked for each held-out season">
          <table className="w-full min-w-[48rem] text-left text-xs">
            <caption className="sr-only">Combination picked for each held-out season</caption>
            <thead className="bg-surface-raised/60 text-slate-300">
              <tr>
                <th scope="col" className={th}>Held-out season</th>
                <th scope="col" className={th}>Stats picked</th>
                <th scope="col" className={th}>Measures picked</th>
                <th scope="col" className={`${th} text-right`}>Gain on training seasons</th>
                <th scope="col" className={`${th} text-right`}>Gain on the unseen season</th>
                <th scope="col" className={`${th} text-right`}>Rows</th>
              </tr>
            </thead>
            <tbody>
              {cs.folds.map((f) => (
                <tr key={f.held_out} className="border-t border-slate-800">
                  <td className={td}>{f.held_out}</td>
                  <td className={td}>{f.series.map((s) => seriesName[s] ?? s).join(', ')}</td>
                  <td className={td}>{f.measures.map((m) => measureName[m] ?? m).join(', ')}</td>
                  <td className={`${td} ${mono} text-right`}>{fmtSigned(f.inner_r2_gain)}</td>
                  <td className={`${td} ${mono} text-right ${f.held_out_r2_gain > 0 ? 'text-emerald-300' : 'text-rose-300'}`}>
                    {fmtSigned(f.held_out_r2_gain)}
                  </td>
                  <td className={`${td} ${mono} text-right`}>{f.held_out_rows}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
        <div className="grid gap-3 md:grid-cols-2">
          <div className={`${card} text-sm text-slate-300 space-y-2`}>
            <h3 className="text-sm font-semibold text-slate-100">Stability</h3>
            <p>
              {stab.distinct_combinations} different combinations in {cs.folds.length} held-out seasons; the gain was
              positive in {stab.seasons_with_positive_gain} of {stab.of_seasons}. A stable pick needed the same choice in{' '}
              {stab.folds_needed}.
            </p>
            <p>
              Picked most often: stats{' '}
              {Object.entries(stab.series_counts)
                .map(([k, v]) => `${seriesName[k] ?? k} ${v}`)
                .join(', ')}
              ; measures{' '}
              {Object.entries(stab.measure_counts)
                .map(([k, v]) => `${measureName[k] ?? k} ${v}`)
                .join(', ')}
              .
            </p>
            <p>
              Final pick on all seasons: {cs.final_choice.series.map((s) => seriesName[s] ?? s).join(', ')} x{' '}
              {cs.final_choice.measures.map((m) => measureName[m] ?? m).join(', ')}.{' '}
              {cs.final_choice.tied_with_best_within_ci} of the other {cs.final_choice.of_combinations - 1} combinations
              tie with it within its interval.
            </p>
          </div>
          <div className={`${card} text-sm text-slate-300`}>
            <h3 className="text-sm font-semibold text-slate-100">Reliability checks (all four needed)</h3>
            <ul className="mt-2 space-y-1.5">
              {Object.entries(cs.reliability_checks).map(([k, ok]) => (
                <Check key={k} ok={ok}>
                  {CHECK_TEXT[k] ?? k}
                </Check>
              ))}
            </ul>
            <p className="mt-2">Verdict: {cs.final_verdict}.</p>
          </div>
        </div>
        <div className={card}>
          <h3 className="text-sm font-semibold text-slate-100">The real search against {perm.runs} shuffled runs</h3>
          <svg viewBox="0 0 600 70" className="mt-2 w-full max-w-2xl" role="img" aria-label={`Real pooled gain ${fmtSigned(realGain)}; shuffled runs: mean ${fmtSigned(perm.mean)}, 95th percentile ${fmtSigned(perm.p95)}, maximum ${fmtSigned(perm.max)}.`}>
            <line x1={10} x2={590} y1={35} y2={35} className="stroke-slate-600" strokeWidth={1} />
            <line x1={px(perm.mean)} x2={px(perm.max)} y1={35} y2={35} className="stroke-slate-400" strokeWidth={6} strokeLinecap="round" />
            {[
              { v: perm.mean, label: 'shuffled mean', y: 14 },
              { v: perm.p95, label: '95th pct', y: 14 },
              { v: perm.max, label: 'max', y: 62 },
            ].map((m) => (
              <g key={m.label}>
                <line x1={px(m.v)} x2={px(m.v)} y1={27} y2={43} className="stroke-slate-300" strokeWidth={1.5} />
                <text x={px(m.v)} y={m.y} textAnchor="middle" className="fill-slate-300 text-[10px]">
                  {m.label}
                </text>
              </g>
            ))}
            <circle cx={px(realGain)} cy={35} r={6} className="fill-indigo-400" />
            <text x={px(realGain)} y={62} textAnchor="middle" className="fill-indigo-300 text-[10px] font-semibold">
              real
            </text>
          </svg>
          <p className="mt-2 text-sm text-slate-300">
            Real pooled gain {fmtSigned(realGain)} {fmtInterval(cs.pooled_ci_95[0], cs.pooled_ci_95[1])}. Shuffled runs:
            mean {fmtSigned(perm.mean)}, 95th percentile {fmtSigned(perm.p95)}, maximum {fmtSigned(perm.max)}.{' '}
            {pct(perm.share_at_or_above_real)} of the shuffled runs did at least as well as the real search.
          </p>
        </div>
        <div className={tableWrap} tabIndex={0} role="region" aria-label="Pooled gain on unseen seasons for each approach">
          <table className="w-full min-w-[44rem] text-left text-xs">
            <caption className="sr-only">Pooled gain on unseen seasons for each approach, with 95% intervals</caption>
            <thead className="bg-surface-raised/60 text-slate-300">
              <tr>
                <th scope="col" className={th}>Approach</th>
                <th scope="col" className={th}>Gain on unseen seasons [95% interval]</th>
              </tr>
            </thead>
            <tbody>
              {[
                { label: `The ${comboShape} combination search`, g: cs.pooled_r2_gain, ci: cs.pooled_ci_95 },
                ...Object.entries(cs.comparisons).map(([k, c]) => ({ label: comparisonText(featuresPerTarget)[k] ?? k, g: c.r2_gain, ci: c.ci })),
                {
                  label: `The same search without ${flagged.map((s) => s.season).join(' and ')}`,
                  g: cs.sensitivity_without_2019_20_2020_21.pooled_r2_gain,
                  ci: cs.sensitivity_without_2019_20_2020_21.pooled_ci_95,
                },
              ].map((r) => (
                <tr key={r.label} className="border-t border-slate-800">
                  <td className={td}>{r.label}</td>
                  <td className={td}>
                    <DeltaCell d={{ delta: r.g, ci_lo: r.ci[0], ci_hi: r.ci[1] }} domain={compDomain} />
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </Section>

      {/* 7 */}
      <Section {...METHODOLOGY_SECTIONS[6]}>
        <p className="max-w-3xl text-sm text-slate-300">
          For each window the study scored every mix of form, trend and Elo change on a grid of {blend[0]?.flatness.of}{' '}
          mixes and compared each with the current mix. &quot;Best on the grid&quot; is chosen with hindsight; the fair test is the mix
          picked on training seasons only. A window&apos;s weights would change only if that fair pick beat the current
          mix with an interval above zero.
        </p>
        <div className={tableWrap} tabIndex={0} role="region" aria-label="Blend weights per window">
          <table className="w-full min-w-[60rem] text-left text-xs">
            <caption className="sr-only">Blend weights per window: current against best, with 95% intervals and how flat the top is</caption>
            <thead className="bg-surface-raised/60 text-slate-300">
              <tr>
                <th scope="col" className={th}>Window</th>
                <th scope="col" className={th}>Current mix (gain)</th>
                <th scope="col" className={th}>Best on the grid (gain)</th>
                <th scope="col" className={th}>Best minus current</th>
                <th scope="col" className={th}>Fair pick minus current</th>
                <th scope="col" className={th}>Non-negative fit minus current</th>
                <th scope="col" className={th}>How flat the top is</th>
              </tr>
            </thead>
            <tbody>
              {blend.map((b) => (
                <tr key={b.window} className="border-t border-slate-800 align-top">
                  <td className={`${td} font-semibold text-slate-100`}>Last {b.window}</td>
                  <td className={td}>
                    {weightsText(b.current_weights)} <span className={`${mono} text-slate-400`}>({fmtSigned(b.current_r2_gain)})</span>
                  </td>
                  <td className={td}>
                    {weightsText(b.best_weights)} <span className={`${mono} text-slate-400`}>({fmtSigned(b.best_r2_gain)})</span>
                  </td>
                  <td className={td}>
                    <DeltaCell d={b.best_vs_current} domain={blendDomain} />
                  </td>
                  <td className={td}>
                    <DeltaCell d={b.loso_selected.vs_current} domain={blendDomain} />
                  </td>
                  <td className={td}>
                    <DeltaCell d={b.nonnegative_regression.vs_current} domain={blendDomain} />
                  </td>
                  <td className={td}>
                    {b.flatness.within_ci_of_best} of {b.flatness.of} mixes within the interval of the best
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
        <p className="text-xs text-slate-400">
          The study stores the best mix and how many grid mixes tie with it, not the score of every mix, so no weight map
          is drawn here.
        </p>
        <div className={tableWrap} tabIndex={0} role="region" aria-label="Further checks on the blend weights">
          <table className="w-full min-w-[56rem] text-left text-xs">
            <caption className="sr-only">Further checks on the blend weights, with 95% intervals</caption>
            <thead className="bg-surface-raised/60 text-slate-300">
              <tr>
                <th scope="col" className={th}>Window</th>
                <th scope="col" className={th}>Each part alone (gain)</th>
                <th scope="col" className={th}>Next 5 games: best minus current</th>
                <th scope="col" className={th}>Best single new measure in place of trend</th>
                <th scope="col" className={th}>Without the flagged seasons: fair pick minus current</th>
              </tr>
            </thead>
            <tbody>
              {blend.map((b) => (
                <tr key={b.window} className="border-t border-slate-800 align-top">
                  <td className={`${td} font-semibold text-slate-100`}>Last {b.window}</td>
                  <td className={`${td} ${mono}`}>
                    form {fmtSigned(b.component_alone_r2_gain.form)}, trend {fmtSigned(b.component_alone_r2_gain.trend)}, Elo{' '}
                    {fmtSigned(b.component_alone_r2_gain.elo)}
                  </td>
                  <td className={td}>
                    <DeltaCell d={b.next5.best_vs_current} domain={otherDomain} />
                  </td>
                  <td className={td}>
                    <span className="block text-slate-400">{featureLabel(b.trend_swap.feature)}</span>
                    <DeltaCell d={b.trend_swap.swap.vs_best_3_component} domain={otherDomain} />
                  </td>
                  <td className={td}>
                    <DeltaCell d={b.sensitivity_without_2019_20_2020_21.loso_selected_vs_current} domain={otherDomain} />
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
        <ul className="space-y-1 text-xs text-slate-400">
          {blend.map((b) => {
            const r = b.residual_small_sample_check;
            return (
              <li key={b.window}>
                Model part, last {b.window} games: {r.label}.{' '}
                {r.ic_4_minus_3
                  ? `${r.rows} rows, ${r.teams} teams; adding it changes the rank correlation by ${fmtSigned(r.ic_4_minus_3.delta)} ${fmtInterval(r.ic_4_minus_3.ci_lo, r.ic_4_minus_3.ci_hi)}.`
                  : `${r.rows} rows, too few to check.`}
              </li>
            );
          })}
        </ul>
      </Section>

      {/* 8 */}
      <Section {...METHODOLOGY_SECTIONS[7]}>
        <div className={`${card} space-y-2 text-sm text-slate-300`}>
          <h3 className="text-sm font-semibold text-slate-100">The {holdoutSeason?.season ?? ''} holdout</h3>
          <p>{data.holdout.note}</p>
          <div className={tableWrap} tabIndex={0} role="region" aria-label="Holdout results">
            <table className="w-full min-w-[40rem] text-left text-xs">
              <caption className="sr-only">Holdout results</caption>
              <thead className="bg-surface-raised/60 text-slate-300">
                <tr>
                  <th scope="col" className={th}>Choice</th>
                  <th scope="col" className={th}>Target</th>
                  <th scope="col" className={`${th} text-right`}>Rows</th>
                  <th scope="col" className={th}>Result</th>
                </tr>
              </thead>
              <tbody>
                {holdoutCells.map(({ label, cell }) => (
                  <tr key={`${label}|${cell.target}`} className="border-t border-slate-800">
                    <td className={td}>{label}</td>
                    <td className={`${td} ${mono}`}>{cell.target}</td>
                    <td className={`${td} ${mono} text-right`}>{cell.rows}</td>
                    <td className={td}>
                      {cell.result}
                      {cell.current_r2_gain !== undefined && cell.best_r2_gain !== undefined
                        ? `: current mix ${fmtSigned(cell.current_r2_gain)}, best mix ${fmtSigned(cell.best_r2_gain)} (point estimates, ${cell.rows} rows, no interval)`
                        : ''}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </div>
        <div className={`${card} text-sm text-slate-300`}>
          <h3 className="text-sm font-semibold text-slate-100">Limits</h3>
          <ul className="mt-2 list-disc space-y-1 pl-5">
            {data.limits.map((l) => (
              <li key={l}>{l}</li>
            ))}
            <li>
              Without {flagged.map((s) => s.season).join(' and ')}, single measures on the main target: {sensCounts.kept}{' '}
              kept, {sensCounts.inconclusive} inconclusive, {sensCounts.discarded} discarded (main run: {primaryCounts.kept},{' '}
              {primaryCounts.inconclusive}, {primaryCounts.discarded}).
            </li>
          </ul>
        </div>
        <dl className={`${card} grid gap-x-6 gap-y-1 text-xs text-slate-300 sm:grid-cols-[auto_1fr]`}>
          <dt className="font-semibold text-slate-100">Study date</dt>
          <dd>{study.run_date}</dd>
          <dt className="font-semibold text-slate-100">Source commit</dt>
          <dd className={`${mono} break-all`}>{data.source_commit}</dd>
          <dt className="font-semibold text-slate-100">Results file sha256</dt>
          <dd className={`${mono} break-all`}>{data.source_sha256}</dd>
          <dt className="font-semibold text-slate-100">Published to the site</dt>
          <dd>{data.published_at}</dd>
          <dt className="font-semibold text-slate-100">Fixed seeds</dt>
          <dd>
            study {study.seeds.study}, shuffles {study.seeds.permutation}, interval resampling: {study.seeds.bootstrap}
          </dd>
          <dt className="font-semibold text-slate-100">Run time</dt>
          <dd>
            {study.runtime_minutes.toFixed(1)} minutes ({study.permutation_minutes.toFixed(1)} for the shuffled runs)
          </dd>
        </dl>
      </Section>
    </div>
  );
};

const CorrelationGrid: React.FC<{ title: string; ids: string[]; names: Record<string, string>; matrix: Record<string, number[]> }> = ({
  title,
  ids,
  names,
  matrix,
}) => (
  <div className={card}>
    <h3 className="text-sm font-semibold text-slate-100">{title}</h3>
    <p className="mt-1 text-xs text-slate-400">0 means unrelated, 1 means they move together. The bar under each value shows its size.</p>
    <div className={`${tableWrap} mt-2`} tabIndex={0} role="region" aria-label={title}>
      <table className="text-xs">
        <caption className="sr-only">{title}</caption>
        <thead>
          <tr>
            <td />
            {ids.map((c) => (
              <th key={c} scope="col" className="px-1 py-1 text-[10px] font-semibold text-slate-300 align-bottom">
                <span className="block max-w-[4.5rem] truncate" title={names[c] ?? c}>
                  {names[c] ?? c}
                </span>
              </th>
            ))}
          </tr>
        </thead>
        <tbody>
          {ids.map((r) => (
            <tr key={r} className="border-t border-slate-800">
              <th scope="row" className="whitespace-nowrap px-2 py-1 text-left font-semibold text-slate-300">
                {names[r] ?? r}
              </th>
              {(matrix[r] ?? []).map((v, i) => (
                <td key={ids[i]} className="px-1 py-1 text-center">
                  <span className={`${mono} text-[10px] text-slate-200`}>{v.toFixed(2)}</span>
                  <span className="mt-0.5 block h-1 rounded bg-slate-800">
                    <span className="block h-1 rounded bg-indigo-400" style={{ width: `${Math.round(v * 100)}%` }} />
                  </span>
                </td>
              ))}
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  </div>
);
