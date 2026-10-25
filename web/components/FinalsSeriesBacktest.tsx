'use client';

import React from 'react';
import { AlertTriangle, ArrowRight, History } from 'lucide-react';
import { TeamLogo } from '@/components/TeamLogo';
import type {
  FinalsBacktestInfoSet,
  FinalsSeriesBacktestSet,
} from '@/lib/playoffTypes';

/**
 * Walk-forward Finals series backtest.
 *
 * The bracket tree above shows one prediction per series, and its Finals row is
 * deliberately blank: no contemporaneous Finals forecast was ever logged, because
 * the archived record was written on 2026-10-04 while the matchup was still
 * undetermined. This section does NOT fill that hole in. It answers a different,
 * weaker question — "what would the model have said, given only the games played
 * at each point?" — and it is required to say so out loud.
 *
 * Three things this component is careful about:
 *
 *  1. The reconstruction disclaimer (`provenance`) is rendered unconditionally and
 *     above the numbers, not tucked into a footnote. A reader must not be able to
 *     take these for archived calls.
 *
 *  2. Each row shows the live forecast AND the from-0-0 counterfactual. The gap
 *     between them is the entire analytical content of the backtest: it separates
 *     "the model re-rated the teams" from "the series score changed". Showing only
 *     the headline number would make the swing unattributable.
 *
 *  3. Nothing is modeled here. Every figure comes off the payload, which the R side
 *     computes with the same exact DP the production engine uses (asserted equal at
 *     the 0-0 state by tools/finals_series_backtest.R's validate_against_production()).
 */

function pct(p: number): string {
  return `${(p * 100).toFixed(1)}%`;
}

function ml(v: number): string {
  return v >= 0 ? `+${v}` : `${v}`;
}

/**
 * The artifact's `provenance` string opens with its own "RECONSTRUCTION, not an
 * archived forecast." sentence, because it has to stand alone for consumers that
 * are not this page. Here the same sentence is already the styled lead-in, so
 * repeating it verbatim reads as a stutter. Strip only that exact opener — never
 * anything else, since the rest of the string is the substantive disclaimer and
 * must survive intact. If the R side ever rewords it, the match simply fails and
 * the full string renders: a duplicated sentence, not a dropped one.
 */
const LEADING_DISCLAIMER = /^\s*RECONSTRUCTION,\s*not an archived forecast\.\s*/i;

function stripLeadingDisclaimer(provenance: string): string {
  return provenance.replace(LEADING_DISCLAIMER, '');
}

function signedPp(delta: number): string {
  const v = delta * 100;
  return `${v >= 0 ? '+' : ''}${v.toFixed(1)} pp`;
}

/** Win-probability bar, high seed from the left. */
function ProbBar({ p }: { p: number }) {
  const w = Math.max(0, Math.min(100, p * 100));
  return (
    <div className="flex h-2 w-full overflow-hidden rounded bg-slate-800">
      <div className="h-full bg-violet-400" style={{ width: `${w}%` }} />
      <div className="h-full bg-amber-500/70" style={{ width: `${100 - w}%` }} />
    </div>
  );
}

function InfoSetRow({
  s,
  prev,
  highAbbr,
  lowAbbr,
}: {
  s: FinalsBacktestInfoSet;
  prev: FinalsBacktestInfoSet | null;
  highAbbr: string;
  lowAbbr: string;
}) {
  const move = prev ? s.pHighSeries - prev.pHighSeries : null;
  // The scoreboard-only counterfactual: same ratings, replayed from 0-0. If the
  // live number and this one move together, the ratings did the work.
  const fromZero = s.pHighSeriesFromZero;

  return (
    <tr className="border-t border-slate-800 align-top">
      <td className="py-3 pr-3">
        <div className="font-semibold text-slate-200">{s.label}</div>
        <div className="font-mono text-[11px] text-slate-500">
          data through {s.cutoffDate}
        </div>
        <div className="mt-1 font-mono text-[11px] text-slate-400">
          {highAbbr} {s.stateHigh}&ndash;{s.stateLow} {lowAbbr}
        </div>
      </td>

      <td className="py-3 pr-3 font-mono text-[11px] text-slate-400">
        <div>
          {highAbbr} {s.netAdjHigh >= 0 ? '+' : ''}
          {s.netAdjHigh.toFixed(2)}
        </div>
        <div>
          {lowAbbr} {s.netAdjLow >= 0 ? '+' : ''}
          {s.netAdjLow.toFixed(2)}
        </div>
        <div className="mt-1 text-slate-600">
          {s.nGamesHigh}/{s.nGamesLow} games
        </div>
      </td>

      <td className="py-3 pr-3 min-w-[160px]">
        <ProbBar p={s.pHighSeries} />
        <div className="mt-1 flex items-baseline justify-between gap-2">
          <span className="font-mono text-sm font-bold text-violet-300">
            {pct(s.pHighSeries)}
          </span>
          <span className="font-mono text-[11px] text-slate-500">
            {ml(s.fairMlHigh)} / {ml(s.fairMlLow)}
          </span>
        </div>
        {move !== null && (
          <div
            className={`mt-0.5 font-mono text-[11px] ${
              move >= 0 ? 'text-emerald-400' : 'text-rose-400'
            }`}
          >
            {signedPp(move)} vs previous
          </div>
        )}
      </td>

      <td className="py-3 pr-3 font-mono text-[11px] text-slate-400">
        {fromZero === null ? (
          <span className="text-slate-600">&mdash;</span>
        ) : (
          <>
            <div>{pct(fromZero)}</div>
            <div className="text-slate-600">ratings only</div>
          </>
        )}
      </td>

      <td className="py-3 font-mono text-[11px] text-slate-400">
        <div className="text-slate-300">{s.expectedLength.toFixed(2)} games</div>
        <div className="mt-1 flex flex-wrap gap-x-2">
          {s.lengthDistribution.map((d) => (
            <span key={d.length}>
              {d.length}g&nbsp;{(d.probability * 100).toFixed(0)}%
            </span>
          ))}
        </div>
      </td>
    </tr>
  );
}

export function FinalsSeriesBacktest({ data }: { data: FinalsSeriesBacktestSet }) {
  const { matchup, infoSets, games, provenance, sourceNote } = data;

  if (!matchup || infoSets.length === 0) {
    return (
      <section className="mt-10">
        <h2 className="flex items-center gap-2 text-xl font-bold text-slate-100">
          <History className="h-5 w-5 text-violet-400" />
          Series forecast backtest
        </h2>
        <p className="mt-2 rounded-lg border border-slate-800 bg-slate-900/60 p-4 text-sm text-slate-400">
          {sourceNote || 'No Finals series backtest is available.'}
        </p>
      </section>
    );
  }

  const first = infoSets[0];
  const last = infoSets[infoSets.length - 1];
  const totalMove = last.pHighSeries - first.pHighSeries;

  return (
    <section className="mt-10">
      <h2 className="flex items-center gap-2 text-xl font-bold text-slate-100">
        <History className="h-5 w-5 text-violet-400" />
        Series forecast backtest
      </h2>

      {/* The disclaimer is deliberately the first thing under the heading. */}
      <div className="mt-3 flex gap-3 rounded-lg border border-amber-500/30 bg-amber-500/5 p-4">
        <AlertTriangle className="mt-0.5 h-4 w-4 shrink-0 text-amber-400" />
        <p className="text-[13px] leading-relaxed text-amber-200/90">
          <span className="font-semibold text-amber-300">
            Reconstruction, not an archived forecast.{' '}
          </span>
          {stripLeadingDisclaimer(provenance)}
        </p>
      </div>

      <div className="mt-4 flex flex-wrap items-center gap-3 text-sm text-slate-300">
        <TeamLogo team={matchup.teamHighAbbr} size="sm" />
        <span className="font-semibold">{matchup.teamHigh}</span>
        <span className="text-slate-600">vs</span>
        <TeamLogo team={matchup.teamLowAbbr} size="sm" />
        <span className="font-semibold">{matchup.teamLow}</span>
        <span className="ml-2 font-mono text-[11px] text-slate-500">
          {games.length} game{games.length === 1 ? '' : 's'} played
        </span>
      </div>

      <div className="mt-4 overflow-x-auto rounded-lg border border-slate-800 bg-slate-900/60 p-4">
        <table className="w-full text-left text-sm">
          <thead>
            <tr className="text-[11px] uppercase tracking-wide text-slate-500">
              <th className="pb-2 pr-3 font-medium">Forecast point</th>
              <th className="pb-2 pr-3 font-medium">Net rating</th>
              <th className="pb-2 pr-3 font-medium">
                P({matchup.teamHighAbbr} wins series)
              </th>
              <th className="pb-2 pr-3 font-medium">Replayed from 0&ndash;0</th>
              <th className="pb-2 font-medium">Series length</th>
            </tr>
          </thead>
          <tbody>
            {infoSets.map((s, i) => (
              <InfoSetRow
                key={s.label}
                s={s}
                prev={i === 0 ? null : infoSets[i - 1]}
                highAbbr={matchup.teamHighAbbr}
                lowAbbr={matchup.teamLowAbbr}
              />
            ))}
          </tbody>
        </table>
      </div>

      <div className="mt-4 flex items-center gap-2 font-mono text-[12px] text-slate-400">
        <span>{pct(first.pHighSeries)}</span>
        <ArrowRight className="h-3.5 w-3.5 text-slate-600" />
        <span className="font-bold text-violet-300">{pct(last.pHighSeries)}</span>
        <span className="text-slate-600">
          ({signedPp(totalMove)} for {matchup.teamHighAbbr} across {games.length} games)
        </span>
      </div>

      {/*
        Editorial explanation. Every figure it quotes is in the table above, and
        its one derived claim is readable off that table too: after G4 the live
        number (48.0%) sits ABOVE the from-0-0 replay (44.2%), so being 2-2 is
        worth roughly +4pp to the high seed, which is what "the scoreboard alone
        would have left Golden State ahead" means applied to the 51.3% opener.
      */}
      <div className="mt-4 rounded-lg border border-slate-800 bg-slate-900/60 p-4">
        <h3 className="text-sm font-semibold text-slate-200">
          Why the prediction changed midway through the series
        </h3>
        <p className="mt-2 text-[13px] leading-relaxed text-slate-400">
          The model re-rates both teams after every game, so a Finals result is not
          only scoreboard news &mdash; it is fresh evidence about how good each side
          actually is. Golden State opened at a +8.63 adjusted net rating against
          Atlanta&rsquo;s +8.76: level on merit, with the Valkyries favoured purely on
          home court. Atlanta&rsquo;s 97&ndash;71 Game 3 win was the hinge. It dragged
          Golden State&rsquo;s season-long scoring margin down by more than a point and
          lifted Atlanta&rsquo;s, flipping the rating edge outright. Conditioning on the
          2&ndash;2 scoreboard alone would still have left Golden State narrowly ahead,
          so almost the whole swing is the ratings update rather than the series score.
        </p>
      </div>
    </section>
  );
}
