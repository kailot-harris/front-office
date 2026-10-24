'use client';

import React from 'react';
import { CalendarClock, CheckCircle2, Clock, Home, Info, Plane, Trophy, XCircle } from 'lucide-react';
import { TeamLogo } from '@/components/TeamLogo';
import type { FinalsGamePrediction, FinalsGamePredictionSet } from '@/lib/playoffTypes';

/**
 * Finals-only section of the 2026 bracket page (GitHub issue #94).
 *
 * The bracket tree above this on the page is one prediction per SERIES. This
 * decomposes the single Finals series into its seven games.
 *
 * Two things this component is careful about, both of which it would be easy to
 * get wrong and both of which matter more than the layout:
 *
 *  1. EVERY row carries P(game played) next to its win probability. Games 5-7 of
 *     a best-of-7 may never happen, and a 57% win probability printed on a game
 *     with a 32% chance of existing is a misleading number without its companion.
 *     Unplayable-looking rows are dimmed in proportion, so the table reads at a
 *     glance as "these games are speculative".
 *
 *  2. A game with a real result shows the PRE-GAME prediction beside that result.
 *     A game without one shows a forecast only and is styled differently (dashed
 *     border, no result column, muted). A reader must never have to work out which
 *     of the two they are looking at.
 *
 * Home-court advantage and rest are both surfaced, never modeled here: every
 * number comes off the payload, which the R side derives from the exact
 * series-length DP and calculate_travel_fatigue(). When the schedule ingest could
 * not supply rest, `restApplied` is false and the section says so instead of
 * quietly showing home-court numbers as though they included rest.
 */

function pct(p: number): string {
  return `${(p * 100).toFixed(1)}%`;
}

function signed(p: number): string {
  const v = p * 100;
  return `${v >= 0 ? '+' : ''}${v.toFixed(1)} pp`;
}

/** P(game played), with the "may never be played" case made visually obvious. */
function PlayedChance({ p }: { p: number }) {
  const certain = p >= 0.9999;
  return (
    <div className="flex items-center gap-2">
      <div className="flex-1 h-1.5 rounded bg-slate-800 overflow-hidden min-w-[48px]">
        <div
          className={`h-full rounded ${certain ? 'bg-slate-600' : 'bg-violet-400'}`}
          style={{ width: `${Math.max(0, Math.min(100, p * 100))}%` }}
        />
      </div>
      <span
        className={`font-mono text-[11px] w-14 text-right ${
          certain ? 'text-slate-400' : 'text-violet-300 font-bold'
        }`}
      >
        {certain ? 'Certain' : pct(p)}
      </span>
    </div>
  );
}

/** One game. Resolved and unresolved rows are deliberately different objects. */
function GameRow({
  g,
  highAbbr,
  lowAbbr,
  restApplied,
}: {
  g: FinalsGamePrediction;
  highAbbr: string;
  lowAbbr: string;
  restApplied: boolean;
}) {
  const played = g.resultAvailable;
  const pHigh = g.restApplied && g.pHighSeedWinWithRest !== null
    ? g.pHighSeedWinWithRest
    : g.pHighSeedWinHca;
  const favoured = pHigh >= 0.5 ? highAbbr : lowAbbr;
  const hostWonIt =
    played && g.scoreHigh !== null && g.scoreLow !== null
      ? g.hostIsHighSeed
        ? g.scoreHigh > g.scoreLow
        : g.scoreLow > g.scoreHigh
      : null;

  return (
    <div
      className={`rounded-xl p-4 space-y-3 ${
        played
          ? 'bg-surface-raised/90 border border-slate-700'
          : 'bg-slate-900/40 border border-dashed border-slate-700/70 opacity-95'
      }`}
    >
      {/* ---- header: game number, host, state ---- */}
      <div className="flex items-center justify-between gap-3 flex-wrap">
        <div className="flex items-center gap-2">
          <span
            className={`font-mono text-xs font-bold px-2 py-0.5 rounded border ${
              played
                ? 'bg-slate-800 text-white border-slate-600'
                : 'bg-transparent text-slate-400 border-slate-700'
            }`}
          >
            Game {g.game}
          </span>
          <span className="text-[11px] font-mono text-slate-500">{g.gameDate || 'date TBD'}</span>
          <span className="inline-flex items-center gap-1 text-[10px] font-mono uppercase tracking-wider text-slate-400">
            <Home className="w-3 h-3" />
            <TeamLogo team={g.hostAbbr} size="sm" />
            hosts
          </span>
        </div>

        {played ? (
          <span className="inline-flex items-center gap-1 text-[10px] font-mono font-bold uppercase tracking-wider px-2 py-0.5 rounded border bg-slate-800 text-slate-200 border-slate-600">
            <CheckCircle2 className="w-3 h-3" />
            Played
          </span>
        ) : (
          <span className="inline-flex items-center gap-1 text-[10px] font-mono font-bold uppercase tracking-wider px-2 py-0.5 rounded border bg-amber-500/10 text-amber-300 border-amber-500/30">
            <CalendarClock className="w-3 h-3" />
            {g.pGamePlayed >= 0.9999 ? 'Forecast only' : 'If necessary'}
          </span>
        )}
      </div>

      {/* ---- the two numbers every row carries ---- */}
      <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
        <div className="space-y-1">
          <h5 className="text-[10px] font-mono font-bold uppercase tracking-widest text-slate-500">
            {played ? 'Pre-game prediction' : 'Forecast'}
          </h5>
          <div className="flex items-center gap-2">
            <TeamLogo team={favoured} size="sm" />
            <span className="text-sm font-bold text-white">{favoured}</span>
            <span className="font-mono text-sm text-slate-300">
              {pct(pHigh >= 0.5 ? pHigh : 1 - pHigh)}
            </span>
          </div>
          <p className="text-[10px] text-slate-500 font-mono">
            Conditional on the game being played.
          </p>
        </div>

        <div className="space-y-1">
          <h5 className="text-[10px] font-mono font-bold uppercase tracking-widest text-slate-500">
            Chance this game is played
          </h5>
          <PlayedChance p={g.pGamePlayed} />
          <p className="text-[10px] text-slate-500 font-mono">
            P(series reaches game {g.game}).
          </p>
        </div>
      </div>

      {/* ---- home court and rest, per game ---- */}
      <div className="border-t border-slate-800 pt-2 space-y-1">
        <div className="flex items-center gap-2 text-[11px] font-mono text-slate-400 flex-wrap">
          <Info className="w-3 h-3 text-slate-500" />
          <span>
            Home court {g.hostIsHighSeed ? 'favours' : 'works against'} {highAbbr} here
          </span>
          <span className="text-slate-600">|</span>
          <span>HCA only: {pct(g.pHighSeedWinHca)} {highAbbr}</span>
          {restApplied && g.restApplied && g.pHighSeedWinWithRest !== null ? (
            <>
              <span className="text-slate-600">|</span>
              <span className="text-sky-300">
                with rest: {pct(g.pHighSeedWinWithRest)} {highAbbr} (
                {signed(g.pHighSeedWinWithRest - g.pHighSeedWinHca)})
              </span>
            </>
          ) : null}
        </div>

        {restApplied && g.restApplied ? (
          <div className="flex items-center gap-2 text-[11px] font-mono text-slate-500 flex-wrap">
            <Clock className="w-3 h-3" />
            <span>
              {highAbbr} {g.daysRestHigh ?? '?'}d rest{g.backToBackHigh ? ' (B2B)' : ''}
            </span>
            <span className="text-slate-600">|</span>
            <span>
              {lowAbbr} {g.daysRestLow ?? '?'}d rest{g.backToBackLow ? ' (B2B)' : ''}
            </span>
            <span className="text-slate-600">|</span>
            <Plane className="w-3 h-3" />
            <span>
              travel {Math.round(g.travelMilesHigh ?? 0)} / {Math.round(g.travelMilesLow ?? 0)} mi
            </span>
            <span className="text-slate-600">|</span>
            <span>
              drag {(g.fatigueDragHigh ?? 0).toFixed(2)} / {(g.fatigueDragLow ?? 0).toFixed(2)} pts
            </span>
          </div>
        ) : (
          <p className="text-[11px] font-mono text-slate-500">
            Rest and travel not applied to this game — home-court advantage only.
          </p>
        )}
      </div>

      {/* ---- the result, only when there is one ---- */}
      {played ? (
        <div className="border-t border-slate-800 pt-2 space-y-1">
          <h5 className="text-[10px] font-mono font-bold uppercase tracking-widest text-slate-500">
            Actual result
          </h5>
          <div className="flex items-center gap-3 flex-wrap">
            <div className="flex items-center gap-2">
              <TeamLogo team={highAbbr} size="sm" />
              <span className="font-mono text-sm font-bold text-white">{g.scoreHigh}</span>
              <span className="text-slate-600">—</span>
              <span className="font-mono text-sm font-bold text-white">{g.scoreLow}</span>
              <TeamLogo team={lowAbbr} size="sm" />
            </div>
            <span
              className={`inline-flex items-center gap-1 text-[10px] font-mono font-bold uppercase tracking-wider px-2 py-0.5 rounded border ${
                g.resultStatus === 'correct'
                  ? 'bg-emerald-500/10 text-emerald-300 border-emerald-500/30'
                  : 'bg-rose-500/10 text-rose-300 border-rose-500/30'
              }`}
            >
              {g.resultStatus === 'correct' ? (
                <CheckCircle2 className="w-3 h-3" />
              ) : (
                <XCircle className="w-3 h-3" />
              )}
              {g.resultStatus === 'correct' ? 'Favoured side won' : 'Favoured side lost'}
            </span>
            {hostWonIt !== null ? (
              <span className="text-[10px] font-mono text-slate-500">
                {hostWonIt ? 'Host held serve.' : 'Road team stole it.'}
              </span>
            ) : null}
          </div>
        </div>
      ) : g.scheduleCompleted ? (
        // The schedule says this game is final but no box score has landed yet.
        // Labeled, not hidden: the box-score cache lags a live series.
        <p className="text-[11px] font-mono text-amber-300/80 border-t border-slate-800 pt-2">
          The schedule marks this game final, but its box score has not reached the cache yet, so
          only the forecast is shown.
        </p>
      ) : null}
    </div>
  );
}

export function FinalsGamePredictions({ finals }: { finals: FinalsGamePredictionSet }) {
  const { matchup, games } = finals;

  // Empty state: no determined Finals matchup, or no games. No hypothetical
  // pairing is invented; `sourceNote` carries the reason.
  if (!matchup || games.length === 0) {
    return (
      <section className="space-y-3">
        <h2 className="text-lg font-bold text-white tracking-tight flex items-center gap-2">
          <Trophy className="w-4 h-4 text-amber-400" />
          Finals — game by game
        </h2>
        <div className="bg-surface-raised/90 border border-slate-800 rounded-xl p-8 text-center space-y-2">
          <p className="text-sm font-bold text-slate-300">
            No Finals matchup is determined yet.
          </p>
          <p className="text-xs text-slate-500 max-w-xl mx-auto leading-relaxed">
            {finals.sourceNote ||
              'Game-by-game Finals predictions appear here once both semifinal series have resolved.'}
          </p>
        </div>
      </section>
    );
  }

  const highAbbr = matchup.teamHighAbbr;
  const lowAbbr = matchup.teamLowAbbr;

  return (
    <section className="space-y-4">
      <div className="space-y-2">
        <h2 className="text-lg font-bold text-white tracking-tight flex items-center gap-2">
          <Trophy className="w-4 h-4 text-amber-400" />
          Finals — game by game
        </h2>
        <p className="text-xs text-slate-400 max-w-3xl leading-relaxed">
          The one Finals series broken into its seven games. Each row shows which side hosts
          (home-court advantage changes sign with the host), the chance the home-court side wins
          that game, and — because games 5 to 7 of a best-of-7 may never happen — the chance the
          game is played at all. A game already played shows its pre-game prediction beside the
          actual result; the rest show a forecast only.
        </p>
        <div className="flex items-center gap-3 flex-wrap text-xs font-mono text-slate-400">
          <span className="inline-flex items-center gap-1">
            <TeamLogo team={highAbbr} size="sm" />
            <span className="text-white font-bold">#{matchup.seedHigh} {matchup.teamHigh}</span>
            <span className="text-slate-500">(home court)</span>
          </span>
          <span className="text-slate-600">vs</span>
          <span className="inline-flex items-center gap-1">
            <TeamLogo team={lowAbbr} size="sm" />
            <span className="text-white font-bold">#{matchup.seedLow} {matchup.teamLow}</span>
          </span>
          <span className="text-slate-600">|</span>
          <span>
            {matchup.seriesComplete ? 'Final' : 'Series'} {matchup.winsHigh}-{matchup.winsLow}
          </span>
          <span className="text-slate-600">|</span>
          <span>{finals.formatLabel}</span>
          <span className="text-slate-600">|</span>
          <span>expected {matchup.expectedGames} games</span>
        </div>

        {!finals.restApplied ? (
          <p className="text-[11px] font-mono text-amber-300/90 border border-amber-500/30 bg-amber-500/5 rounded px-3 py-2">
            Home-court advantage only — rest and travel are not applied to these games.{' '}
            {finals.restNote}
          </p>
        ) : null}
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-2 gap-4">
        {games.map((g) => (
          <GameRow
            key={g.game}
            g={g}
            highAbbr={highAbbr}
            lowAbbr={lowAbbr}
            restApplied={finals.restApplied}
          />
        ))}
      </div>

      {finals.sourceNote ? (
        <p className="text-[11px] text-slate-500 leading-relaxed">{finals.sourceNote}</p>
      ) : null}
    </section>
  );
}
