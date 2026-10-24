'use client';

import React, { useState } from 'react';
import { CalendarClock, CheckCircle2, ChevronDown, Info, Trophy, XCircle } from 'lucide-react';
import { TeamLogo } from '@/components/TeamLogo';
import type {
  BracketSeries,
  BracketForecast,
  PlayoffBracketSeason,
} from '@/lib/playoffTypes';

/**
 * 2026 playoff bracket: for every resolved round, the model's prediction shown
 * beside the result.
 *
 * On the prediction provenance, which is the reason this page is shaped the way
 * it is: the rounds do NOT share a method, deliberately.
 *
 *  - Round 1 has no archived forecast — nothing in this project stored one — so
 *    it is reconstructed after the fact from regular-season ratings only.
 *  - The Semifinals carry the forecast actually recorded on 2026-10-04, before
 *    either series was played. Those are kept exactly as they were recorded,
 *    including the fact that their ratings pooled Round 1's playoff games in.
 *
 * Neither round is a clean held-out test, and this component never says it is.
 * Every prediction renders its own `provenanceLabel` and `ratingBasis` straight
 * from the payload, so the basis travels with the number instead of being
 * summarised once at the top of the page and lost.
 */

const ROUND_ORDER = ['Round 1', 'Semifinals', 'Finals'] as const;

function pct(p: number): string {
  return `${(p * 100).toFixed(1)}%`;
}

/** Per-round provenance chip. Wording comes from the data, not from here. */
function ProvenanceBadge({ series }: { series: BracketSeries }) {
  const { provenance, provenanceLabel } = series.prediction;

  const style =
    provenance === 'archived_forecast'
      ? 'bg-emerald-500/10 text-emerald-300 border-emerald-500/30'
      : provenance === 'round1_reconstruction'
        ? 'bg-sky-500/10 text-sky-300 border-sky-500/30'
        : 'bg-slate-800 text-slate-400 border-slate-700';

  const short =
    provenance === 'archived_forecast'
      ? 'Forecast on record'
      : provenance === 'round1_reconstruction'
        ? 'Reconstructed'
        : 'No prediction';

  return (
    <span
      title={provenanceLabel}
      className={`inline-flex items-center gap-1 text-[10px] font-mono font-bold uppercase tracking-wider px-2 py-0.5 rounded border ${style}`}
    >
      <Info className="w-3 h-3" />
      {short}
    </span>
  );
}

/** The verdict: did the prediction match the result. */
function ResultStatusBadge({ status }: { status: BracketForecast['resultStatus'] }) {
  if (status === 'pending') {
    return (
      <span className="inline-flex items-center gap-1 text-[10px] font-mono font-bold uppercase tracking-wider px-2 py-0.5 rounded border bg-amber-500/10 text-amber-300 border-amber-500/30">
        <CalendarClock className="w-3 h-3" />
        Series in progress
      </span>
    );
  }
  const hit = status === 'correct';
  return (
    <span
      className={`inline-flex items-center gap-1 text-[10px] font-mono font-bold uppercase tracking-wider px-2 py-0.5 rounded border ${
        hit
          ? 'bg-emerald-500/10 text-emerald-300 border-emerald-500/30'
          : 'bg-rose-500/10 text-rose-300 border-rose-500/30'
      }`}
    >
      {hit ? <CheckCircle2 className="w-3 h-3" /> : <XCircle className="w-3 h-3" />}
      {hit ? 'Model called it' : 'Model missed it'}
    </span>
  );
}

/** Left column: what actually happened. */
function ResultPanel({ series }: { series: BracketSeries }) {
  const leaderIsA = series.winsA > series.winsB;

  return (
    <div className="space-y-3">
      <h4 className="text-[10px] font-mono font-bold uppercase tracking-widest text-slate-500">
        Result
      </h4>

      {[
        { abbr: series.teamA, name: series.teamNameA, wins: series.winsA, isLeader: leaderIsA },
        { abbr: series.teamB, name: series.teamNameB, wins: series.winsB, isLeader: !leaderIsA },
      ].map((t) => (
        <div key={t.abbr} className="flex items-center gap-2">
          <TeamLogo team={t.abbr} size="sm" />
          <span
            className={`text-sm flex-1 truncate ${
              t.isLeader ? 'font-bold text-white' : 'text-slate-400'
            }`}
          >
            {t.name}
          </span>
          <span
            className={`text-sm font-mono font-bold ${
              t.isLeader ? 'text-white' : 'text-slate-500'
            }`}
          >
            {t.wins}
          </span>
        </div>
      ))}

      <p className="text-xs text-slate-400 pt-1">
        {series.seriesComplete ? (
          <>
            <span className="font-bold text-white">{series.winnerName}</span> won the series{' '}
            <span className="font-mono">
              {Math.max(series.winsA, series.winsB)}–{Math.min(series.winsA, series.winsB)}
            </span>{' '}
            in {series.gamesPlayed} {series.gamesPlayed === 1 ? 'game' : 'games'}.
          </>
        ) : (
          <>
            {/* Not "won": the box-score feed only has games already played, so an
                unfinished series must not be reported as decided. */}
            <span className="font-bold text-white">{series.winnerName}</span> leads{' '}
            <span className="font-mono">
              {Math.max(series.winsA, series.winsB)}–{Math.min(series.winsA, series.winsB)}
            </span>
            . Series still in progress.
          </>
        )}
      </p>
    </div>
  );
}

/** Right column: what the model said, with its basis attached. */
function PredictionPanel({ series }: { series: BracketSeries }) {
  const f = series.prediction.forecast;

  if (!f) {
    return (
      <div className="space-y-3">
        <h4 className="text-[10px] font-mono font-bold uppercase tracking-widest text-slate-500">
          Prediction
        </h4>
        <p className="text-xs text-slate-400 leading-relaxed">
          {series.prediction.provenanceLabel}
        </p>
      </div>
    );
  }

  const highFavoured = f.pHighSeedWin >= 0.5;

  return (
    <div className="space-y-3">
      <div className="flex items-center justify-between gap-2">
        <h4 className="text-[10px] font-mono font-bold uppercase tracking-widest text-slate-500">
          Prediction
        </h4>
        <span className="text-[10px] font-mono text-slate-500">{f.formatLabel}</span>
      </div>

      {[
        {
          name: f.teamHigh,
          abbr: f.teamHighAbbr,
          seed: f.seedHigh,
          p: f.pHighSeedWin,
          favoured: highFavoured,
        },
        {
          name: f.teamLow,
          abbr: f.teamLowAbbr,
          seed: f.seedLow,
          p: f.pLowSeedWin,
          favoured: !highFavoured,
        },
      ].map((t) => (
        <div key={t.name} className="space-y-1">
          <div className="flex items-center gap-2">
            {t.abbr ? <TeamLogo team={t.abbr} size="sm" /> : null}
            <span
              className={`text-sm flex-1 truncate ${
                t.favoured ? 'font-bold text-white' : 'text-slate-400'
              }`}
            >
              {t.name}
              {t.seed !== null ? (
                <span className="text-[10px] font-mono text-slate-500 ml-1">#{t.seed}</span>
              ) : null}
            </span>
            <span
              className={`text-sm font-mono font-bold ${
                t.favoured ? 'text-accent-400' : 'text-slate-500'
              }`}
            >
              {pct(t.p)}
            </span>
          </div>
          <div className="h-1 w-full rounded bg-slate-800 overflow-hidden">
            <div
              className={`h-full rounded ${t.favoured ? 'bg-accent-500' : 'bg-slate-600'}`}
              style={{ width: `${Math.max(0, Math.min(100, t.p * 100))}%` }}
            />
          </div>
        </div>
      ))}

      <dl className="grid grid-cols-2 gap-x-3 gap-y-1 text-[11px] pt-1">
        <dt className="text-slate-500">Expected length</dt>
        <dd className="text-right font-mono text-slate-300">{f.expectedGames.toFixed(2)} games</dd>
        <dt className="text-slate-500">Net rating edge</dt>
        <dd className="text-right font-mono text-slate-300">
          {(f.netHighAdj - f.netLowAdj >= 0 ? '+' : '') +
            (f.netHighAdj - f.netLowAdj).toFixed(2)}
        </dd>
        {typeof f.fairMlHigh === 'number' ? (
          <>
            <dt className="text-slate-500">Fair moneyline</dt>
            <dd className="text-right font-mono text-slate-300">
              {f.fairMlHigh > 0 ? `+${f.fairMlHigh}` : f.fairMlHigh}
            </dd>
          </>
        ) : null}
      </dl>
    </div>
  );
}

function SeriesCard({ series }: { series: BracketSeries }) {
  const [open, setOpen] = useState(false);
  const f = series.prediction.forecast;

  return (
    <div className="bg-surface-raised/90 border border-slate-800 hover:border-slate-700 rounded-xl p-5 shadow-lg space-y-4 transition-all">
      <div className="flex items-center justify-between gap-2 flex-wrap">
        <span className="font-mono font-bold text-xs px-2 py-0.5 rounded bg-slate-800 text-amber-400">
          {series.round}
        </span>
        <div className="flex items-center gap-1.5 flex-wrap">
          <ProvenanceBadge series={series} />
          {f ? <ResultStatusBadge status={f.resultStatus} /> : null}
        </div>
      </div>

      {/* Prediction and result side by side for this one series — the whole
          point of the page. Stacks on narrow screens. */}
      <div className="grid grid-cols-1 sm:grid-cols-2 gap-5 sm:divide-x divide-slate-800">
        <ResultPanel series={series} />
        <div className="sm:pl-5">
          <PredictionPanel series={series} />
        </div>
      </div>

      {/* The basis of the number, attached to the number. */}
      {f ? (
        <p className="text-[11px] text-slate-500 leading-relaxed border-t border-slate-800 pt-3">
          <span className="font-bold text-slate-400">{series.prediction.provenanceLabel}</span>{' '}
          {f.ratingBasis}
        </p>
      ) : null}

      <button
        onClick={() => setOpen((v) => !v)}
        className="w-full flex items-center justify-center gap-1 text-[11px] font-mono text-slate-400 hover:text-white transition-colors pt-1"
      >
        <ChevronDown className={`w-3.5 h-3.5 transition-transform ${open ? 'rotate-180' : ''}`} />
        {open ? 'Hide detail' : 'Game scores & length distribution'}
      </button>

      {open ? (
        <div className="grid grid-cols-1 sm:grid-cols-2 gap-5 pt-1">
          <div className="space-y-1">
            <h5 className="text-[10px] font-mono font-bold uppercase tracking-widest text-slate-500 mb-2">
              Games played
            </h5>
            {series.games.map((g, i) => (
              <div key={i} className="flex items-center justify-between text-[11px] font-mono">
                <span className="text-slate-500">
                  G{i + 1} · {g.gameDate}
                </span>
                <span className="text-slate-300">
                  {g.teamA} {g.scoreA} – {g.scoreB} {g.teamB}
                </span>
              </div>
            ))}
          </div>

          <div className="space-y-1">
            <h5 className="text-[10px] font-mono font-bold uppercase tracking-widest text-slate-500 mb-2">
              Predicted series length
            </h5>
            {f ? (
              f.lengthDistribution.map((d) => (
                <div key={d.length} className="flex items-center gap-2 text-[11px] font-mono">
                  <span className="text-slate-500 w-16">{d.label}</span>
                  <div className="flex-1 h-1.5 rounded bg-slate-800 overflow-hidden">
                    <div
                      className={`h-full rounded ${
                        d.length === series.gamesPlayed ? 'bg-amber-400' : 'bg-slate-600'
                      }`}
                      style={{ width: `${Math.max(0, Math.min(100, d.probability * 100))}%` }}
                    />
                  </div>
                  <span className="text-slate-300 w-12 text-right">{pct(d.probability)}</span>
                </div>
              ))
            ) : (
              <p className="text-[11px] text-slate-500">No predicted distribution for this round.</p>
            )}
            {f && series.seriesComplete ? (
              <p className="text-[10px] text-slate-500 pt-2">
                Highlighted bar is the length the series actually ran.
              </p>
            ) : null}
          </div>
        </div>
      ) : null}
    </div>
  );
}

export function PlayoffBracket2026Client({ bracket }: { bracket: PlayoffBracketSeason }) {
  const { series } = bracket;

  // Empty state: no artifact, or an artifact with no series. `sourceNote` says
  // which, so the page is never silently blank.
  if (series.length === 0) {
    return (
      <div className="space-y-4">
        <header className="pb-4 border-b border-slate-800">
          <h1 className="text-xl font-bold text-white tracking-tight flex items-center gap-2">
            <Trophy className="w-5 h-5 text-amber-400" />
            <span>{bracket.season} Playoff Bracket</span>
          </h1>
        </header>
        <div className="bg-surface-raised/90 border border-slate-800 rounded-xl p-8 text-center space-y-2">
          <p className="text-sm font-bold text-slate-300">No bracket data available yet.</p>
          <p className="text-xs text-slate-500 max-w-xl mx-auto leading-relaxed">
            {bracket.sourceNote ||
              'The postseason box-score cache is empty or missing. Run the pipeline to populate it.'}
          </p>
        </div>
      </div>
    );
  }

  // Group by round, in bracket order, with any unexpected label kept at the end
  // rather than dropped.
  const knownRounds = ROUND_ORDER.filter((r) => series.some((s) => s.round === r));
  const extraRounds = Array.from(new Set(series.map((s) => s.round))).filter(
    (r) => !ROUND_ORDER.includes(r as (typeof ROUND_ORDER)[number])
  );
  const rounds: string[] = [...knownRounds, ...extraRounds];

  const scored = series.filter((s) => s.prediction.forecast && s.seriesComplete);
  const hits = scored.filter((s) => s.prediction.forecast!.resultStatus === 'correct').length;

  return (
    <div className="space-y-8">
      <header className="pb-4 border-b border-slate-800 space-y-2">
        <h1 className="text-xl font-bold text-white tracking-tight flex items-center gap-2">
          <Trophy className="w-5 h-5 text-amber-400" />
          <span>{bracket.season} Playoff Bracket — Prediction vs Result</span>
        </h1>
        <p className="text-xs text-slate-400 max-w-3xl leading-relaxed">
          Every {bracket.season} postseason series, with the model&apos;s prediction beside the
          outcome. The two rounds are predicted on different bases and each card states its own:
          Round 1 is reconstructed after the fact, because no Round 1 forecast was ever recorded;
          the Semifinals show the forecast as it stood on the day it was made and are not
          recomputed.
        </p>
        {scored.length > 0 ? (
          <p className="text-xs text-slate-500 font-mono">
            Favoured side won {hits} of {scored.length} completed series with a prediction.
          </p>
        ) : null}
      </header>

      {rounds.map((round) => {
        const rows = series.filter((s) => s.round === round);
        return (
          <section key={round} className="space-y-4">
            <div className="flex items-baseline justify-between gap-3 flex-wrap">
              <h2 className="text-lg font-bold text-white tracking-tight">{round}</h2>
              {/* Round-level provenance, stated once per round and repeated on
                  each card, so a reader landing mid-page cannot miss it. */}
              <p className="text-[11px] text-slate-500 font-mono">
                {rows[0]?.prediction.provenanceLabel}
              </p>
            </div>
            <div className="grid grid-cols-1 lg:grid-cols-2 gap-4">
              {rows.map((s) => (
                <SeriesCard key={`${s.round}-${s.teamA}-${s.teamB}`} series={s} />
              ))}
            </div>
          </section>
        );
      })}

      {bracket.sourceNote ? (
        <footer className="border-t border-slate-800 pt-4">
          <p className="text-[11px] text-slate-500 leading-relaxed">{bracket.sourceNote}</p>
          {bracket.generatedAt ? (
            <p className="text-[10px] text-slate-600 font-mono mt-1">
              Artifact generated {bracket.generatedAt}
            </p>
          ) : null}
        </footer>
      ) : null}
    </div>
  );
}
