'use client';

import React, { useState, useMemo } from 'react';
import {
  PlayoffMatchupsCatalog,
  SeriesSimulationResult,
  TeamPlayoffProfile,
} from '@/lib/playoffTypes';
import { TeamLogo } from '@/components/TeamLogo';
import { SeriesProbRing } from '@/components/SeriesProbRing';
import { TacticalMismatchRadar } from '@/components/TacticalMismatchRadar';
import { RotationMatchupCard } from '@/components/RotationMatchupCard';
import {
  Swords,
  ArrowRightLeft,
  Sparkles,
} from 'lucide-react';

interface PlayoffSeriesClientProps {
  catalog: PlayoffMatchupsCatalog;
}

// Client simulation fallback in case a non-precomputed matchup is selected
function simulateClientFallback(
  pA: TeamPlayoffProfile,
  pB: TeamPlayoffProfile,
  hcaTeam: string,
  seriesLength: number,
  nSims = 5000
): SeriesSimulationResult {
  const winsToClinch = Math.ceil(seriesLength / 2);
  const homeScheduleHca = seriesLength === 3 
    ? [true, true, true] 
    : seriesLength === 5 
    ? [true, true, false, false, true] 
    : [true, true, false, false, false, true, true];

  const hcaIsA = hcaTeam === pA.teamAbbr;
  const aIsHome = hcaIsA ? homeScheduleHca : homeScheduleHca.map((h) => !h);

  const spSlot = seriesLength === 3 
    ? [0, 1, 2] 
    : seriesLength === 5 
    ? [0, 1, 2, 3, 0] 
    : [0, 1, 2, 3, 0, 1, 2];

  const baseEloDiff = pA.baseElo - pB.baseElo;
  const hfaElo = 24.0;
  const mismatchElo = (pA.tacticalRatings.rotationDepth - pB.tacticalRatings.rotationDepth) * 0.15;

  const gameProbA: number[] = [];
  const gameDetails = [];

  for (let g = 0; g < seriesLength; g++) {
    const isHome = aIsHome[g];
    const hfaAdj = isHome ? hfaElo : -hfaElo;
    const spA = pA.starters[spSlot[g]] || pA.starters[0];
    const spB = pB.starters[spSlot[g]] || pB.starters[0];
    const rgsDiff = 4.7 * (spA.rGS - spB.rGS);

    const totalDiff = baseEloDiff + hfaAdj + rgsDiff + mismatchElo;
    const pWin = 1 / (1 + Math.pow(10, -totalDiff / 400));
    gameProbA.push(pWin);

    gameDetails.push({
      gameNumber: g + 1,
      homeTeam: isHome ? pA.teamAbbr : pB.teamAbbr,
      awayTeam: isHome ? pB.teamAbbr : pA.teamAbbr,
      starterA: spA.playerName,
      starterB: spB.playerName,
      starterArGS: spA.rGS,
      starterBrGS: spB.rGS,
      winProbA: Number(pWin.toFixed(3)),
      winProbB: Number((1 - pWin).toFixed(3)),
    });
  }

  let simAWins = 0;
  const distCounts: Record<string, number> = {};
  for (let g = winsToClinch; g <= seriesLength; g++) {
    distCounts[`A_${g}`] = 0;
    distCounts[`B_${g}`] = 0;
  }

  let totalGamesPlayed = 0;

  for (let sim = 0; sim < nSims; sim++) {
    let wA = 0;
    let wB = 0;
    let gIdx = 0;

    while (wA < winsToClinch && wB < winsToClinch) {
      if (Math.random() < gameProbA[gIdx]) {
        wA++;
      } else {
        wB++;
      }
      gIdx++;
    }

    const gamesInSeries = gIdx;
    totalGamesPlayed += gamesInSeries;

    if (wA === winsToClinch) {
      simAWins++;
      distCounts[`A_${gamesInSeries}`]++;
    } else {
      distCounts[`B_${gamesInSeries}`]++;
    }
  }

  const probA = Number((simAWins / nSims).toFixed(3));
  const probB = Number((1 - probA).toFixed(3));

  const calcMl = (prob: number) => {
    if (prob <= 0.01) return 9999;
    if (prob >= 0.99) return -9999;
    if (prob >= 0.5) return Math.round(-(prob / (1 - prob)) * 100);
    return Math.round(((1 - prob) / prob) * 100);
  };

  const gameDistList = Object.keys(distCounts).map((k) => {
    const parts = k.split('_');
    const winner = parts[0] === 'A' ? pA.teamAbbr : pB.teamAbbr;
    return {
      games: Number(parts[1]),
      winner,
      probPct: Number(((distCounts[k] / nSims) * 100).toFixed(1)),
    };
  });

  return {
    teamA: pA.teamAbbr,
    teamB: pB.teamAbbr,
    hcaTeam,
    seriesLength,
    winsToClinch,
    baseEloDiff: Number(baseEloDiff.toFixed(1)),
    tacticalMismatchAdjustment: Number(mismatchElo.toFixed(1)),
    winProbA: probA,
    winProbB: probB,
    fairMlA: calcMl(probA),
    fairMlB: calcMl(probB),
    avgGames: Number((totalGamesPlayed / nSims).toFixed(2)),
    sweepProb: Number(((distCounts[`A_${winsToClinch}`] + distCounts[`B_${winsToClinch}`]) / nSims * 100).toFixed(1)),
    gameDistributions: gameDistList,
    tacticalEdges: [
      {
        title: 'Pitching Rotation Quality & Depth',
        advantageTeam: pA.tacticalRatings.rotationDepth >= pB.tacticalRatings.rotationDepth ? pA.teamAbbr : pB.teamAbbr,
        description: 'Differential in starting pitching game score across projected games.',
        deltaElo: Math.abs(mismatchElo),
      },
    ],
    gameSchedule: gameDetails,
  };
}

export const PlayoffSeriesClient: React.FC<PlayoffSeriesClientProps> = ({ catalog }) => {
  const teamsList = useMemo(() => {
    return Object.values(catalog.teams).sort((a, b) => b.regularWins - a.regularWins);
  }, [catalog.teams]);

  // Default matchup: NYY (Yankees) vs LAD (Dodgers) - classic World Series
  const [teamACode, setTeamACode] = useState<string>('NYY');
  const [teamBCode, setTeamBCode] = useState<string>('LAD');
  const [seriesLength, setSeriesLength] = useState<3 | 5 | 7>(7);
  const [hcaOverride, setHcaOverride] = useState<'A' | 'B'>('A');

  const profileA = catalog.teams[teamACode] || teamsList[0];
  const profileB = catalog.teams[teamBCode] || teamsList[1];

  const hcaTeam = hcaOverride === 'A' ? profileA.teamAbbr : profileB.teamAbbr;

  // Swap teams button
  const handleSwap = () => {
    const temp = teamACode;
    setTeamACode(teamBCode);
    setTeamBCode(temp);
    setHcaOverride(hcaOverride === 'A' ? 'B' : 'A');
  };

  // Find precomputed matchup or fallback to client simulation
  const seriesResult: SeriesSimulationResult = useMemo(() => {
    const key1 = `${teamACode}_vs_${teamBCode}`;
    const key2 = `${teamBCode}_vs_${teamACode}`;

    const precomputed = catalog.matchups[key1] || catalog.matchups[key2];

    if (precomputed) {
      const match =
        seriesLength === 7
          ? precomputed.series7
          : seriesLength === 5
          ? precomputed.series5
          : precomputed.series3;

      // If team order matches key
      if (precomputed.teamA === teamACode) {
        return match;
      } else {
        // Invert results if user swapped perspective
        return {
          ...match,
          teamA: teamACode,
          teamB: teamBCode,
          winProbA: match.winProbB,
          winProbB: match.winProbA,
          fairMlA: match.fairMlB,
          fairMlB: match.fairMlA,
          baseEloDiff: -match.baseEloDiff,
          tacticalMismatchAdjustment: -match.tacticalMismatchAdjustment,
        };
      }
    }

    // Dynamic client simulation fallback
    return simulateClientFallback(profileA, profileB, hcaTeam, seriesLength);
  }, [catalog.matchups, teamACode, teamBCode, seriesLength, hcaTeam, profileA, profileB]);

  return (
    <div className="space-y-6">
      {/* Hero Header Banner */}
      <div className="bg-gradient-to-r from-slate-900 via-indigo-950/40 to-slate-900 border border-indigo-900/30 rounded-2xl p-6 shadow-xl relative overflow-hidden">
        <div className="absolute right-0 top-0 bottom-0 w-96 bg-[radial-gradient(ellipse_at_top_right,_var(--tw-gradient-stops))] from-indigo-500/10 via-sky-500/5 to-transparent pointer-events-none" />

        <div className="flex flex-col lg:flex-row lg:items-center justify-between gap-6 relative z-10">
          <div>
            <div className="flex items-center gap-2 mb-1.5">
              <span className="px-2.5 py-0.5 rounded-full text-[11px] font-semibold bg-indigo-500/10 text-indigo-400 border border-indigo-500/20 flex items-center gap-1 font-mono">
                <Swords className="w-3.5 h-3.5" /> Postseason Matchup Engine
              </span>
              <span className="text-xs text-slate-400 font-mono">10,000 Monte Carlo Series</span>
            </div>
            <h1 className="text-2xl sm:text-3xl font-extrabold tracking-tight text-white">
              Interactive Playoff Series Simulator
            </h1>
            <p className="text-sm text-slate-300 max-w-2xl mt-1">
              Pair any two MLB clubs across 3-game (Wild Card), 5-game (Division Series), or 7-game (LCS/World Series) formats.
              Models scheduled starting pitcher rGS, bullpen fatigue leverage, and tactical mismatch levers.
            </p>
          </div>

          {/* Series Length Selector */}
          <div className="flex items-center gap-2 bg-slate-950/80 p-1.5 rounded-xl border border-slate-800 self-start lg:self-auto font-mono text-xs">
            <button
              type="button"
              onClick={() => setSeriesLength(3)}
              className={`px-3 py-2 rounded-lg font-bold transition-all ${
                seriesLength === 3
                  ? 'bg-indigo-600 text-white shadow-md shadow-indigo-600/30'
                  : 'text-slate-400 hover:text-white'
              }`}
            >
              Best-of-3 (WC)
            </button>
            <button
              type="button"
              onClick={() => setSeriesLength(5)}
              className={`px-3 py-2 rounded-lg font-bold transition-all ${
                seriesLength === 5
                  ? 'bg-indigo-600 text-white shadow-md shadow-indigo-600/30'
                  : 'text-slate-400 hover:text-white'
              }`}
            >
              Best-of-5 (DS)
            </button>
            <button
              type="button"
              onClick={() => setSeriesLength(7)}
              className={`px-3 py-2 rounded-lg font-bold transition-all ${
                seriesLength === 7
                  ? 'bg-indigo-600 text-white shadow-md shadow-indigo-600/30'
                  : 'text-slate-400 hover:text-white'
              }`}
            >
              Best-of-7 (CS/WS)
            </button>
          </div>
        </div>
      </div>

      {/* Matchup Selection Bar */}
      <div className="bg-slate-900/90 border border-slate-800 rounded-2xl p-4 shadow-xl grid grid-cols-1 md:grid-cols-12 gap-4 items-center">
        {/* Team A Selector */}
        <div className="md:col-span-5 bg-slate-950/80 border border-slate-800/80 rounded-xl p-3 flex items-center gap-3">
          <TeamLogo team={teamACode} size="lg" />
          <div className="flex-1 min-w-0">
            <span className="text-[10px] uppercase font-mono font-bold text-sky-400 block">Team A (High Seed Option)</span>
            <select
              value={teamACode}
              onChange={(e) => setTeamACode(e.target.value)}
              className="w-full bg-transparent text-white font-bold text-sm sm:text-base focus:outline-none cursor-pointer truncate"
            >
              {teamsList.map((t) => (
                <option key={t.teamAbbr} value={t.teamAbbr} className="bg-slate-900 text-white">
                  {t.fullName} ({t.regularWins} Proj Wins)
                </option>
              ))}
            </select>
            <div className="flex items-center gap-2 text-[11px] text-slate-400 font-mono mt-0.5">
              <span>Elo: <strong className="text-white">{profileA.baseElo}</strong></span>
              <span>•</span>
              <button
                type="button"
                onClick={() => setHcaOverride('A')}
                className={`px-1.5 py-0.2 rounded text-[10px] font-bold ${
                  hcaTeam === teamACode ? 'bg-sky-500/20 text-sky-300 border border-sky-500/40' : 'text-slate-500'
                }`}
              >
                {hcaTeam === teamACode ? '★ Has Home Field' : 'Set as HCA'}
              </button>
            </div>
          </div>
        </div>

        {/* Swap Button */}
        <div className="md:col-span-2 flex justify-center">
          <button
            type="button"
            onClick={handleSwap}
            className="p-3 rounded-full bg-slate-800 hover:bg-slate-700 text-slate-300 hover:text-white border border-slate-700 transition-all shadow-md group"
            title="Swap Home/Away & Matchup Positions"
          >
            <ArrowRightLeft className="w-5 h-5 group-hover:rotate-180 transition-transform duration-300" />
          </button>
        </div>

        {/* Team B Selector */}
        <div className="md:col-span-5 bg-slate-950/80 border border-slate-800/80 rounded-xl p-3 flex items-center gap-3">
          <TeamLogo team={teamBCode} size="lg" />
          <div className="flex-1 min-w-0">
            <span className="text-[10px] uppercase font-mono font-bold text-amber-400 block">Team B (Challenger)</span>
            <select
              value={teamBCode}
              onChange={(e) => setTeamBCode(e.target.value)}
              className="w-full bg-transparent text-white font-bold text-sm sm:text-base focus:outline-none cursor-pointer truncate"
            >
              {teamsList.map((t) => (
                <option key={t.teamAbbr} value={t.teamAbbr} className="bg-slate-900 text-white">
                  {t.fullName} ({t.regularWins} Proj Wins)
                </option>
              ))}
            </select>
            <div className="flex items-center gap-2 text-[11px] text-slate-400 font-mono mt-0.5">
              <span>Elo: <strong className="text-white">{profileB.baseElo}</strong></span>
              <span>•</span>
              <button
                type="button"
                onClick={() => setHcaOverride('B')}
                className={`px-1.5 py-0.2 rounded text-[10px] font-bold ${
                  hcaTeam === teamBCode ? 'bg-amber-500/20 text-amber-300 border border-amber-500/40' : 'text-slate-500'
                }`}
              >
                {hcaTeam === teamBCode ? '★ Has Home Field' : 'Set as HCA'}
              </button>
            </div>
          </div>
        </div>
      </div>

      {/* Main Analysis Grid: Donut Probability Ring + Tactical Radar */}
      <div className="grid grid-cols-1 lg:grid-cols-12 gap-6">
        {/* Left Column: Donut Ring & Tactical Edges (6 cols) */}
        <div className="lg:col-span-6 space-y-6">
          <SeriesProbRing
            teamA={teamACode}
            teamB={teamBCode}
            winProbA={seriesResult.winProbA}
            winProbB={seriesResult.winProbB}
            fairMlA={seriesResult.fairMlA}
            fairMlB={seriesResult.fairMlB}
            sweepProb={seriesResult.sweepProb}
            avgGames={seriesResult.avgGames}
            gameDistributions={seriesResult.gameDistributions}
            seriesLength={seriesLength}
          />

          {/* Tactical Edges Callout Card */}
          <div className="bg-slate-900/90 border border-slate-800 rounded-2xl p-5 shadow-xl space-y-3">
            <div className="flex items-center gap-2 border-b border-slate-800/80 pb-2">
              <Sparkles className="w-4 h-4 text-amber-400" />
              <h3 className="text-xs font-bold text-white uppercase tracking-wider font-mono">
                Key Sabermetric Tactical Edges
              </h3>
            </div>

            {seriesResult.tacticalEdges && seriesResult.tacticalEdges.length > 0 ? (
              <div className="space-y-2.5">
                {seriesResult.tacticalEdges.map((edge, i) => {
                  const isA = edge.advantageTeam === teamACode;
                  return (
                    <div
                      key={i}
                      className={`p-3 rounded-xl border text-xs ${
                        isA
                          ? 'bg-sky-950/20 border-sky-900/40 text-slate-300'
                          : 'bg-amber-950/20 border-amber-900/40 text-slate-300'
                      }`}
                    >
                      <div className="flex items-center justify-between font-mono mb-1">
                        <span className="font-bold text-white flex items-center gap-1.5">
                          <span
                            className={`w-2 h-2 rounded-full ${isA ? 'bg-sky-400' : 'bg-amber-400'}`}
                          />
                          {edge.title}
                        </span>
                        <span
                          className={`font-mono text-[10.5px] font-bold px-1.5 py-0.5 rounded ${
                            isA ? 'bg-sky-500/20 text-sky-300' : 'bg-amber-500/20 text-amber-300'
                          }`}
                        >
                          +{edge.deltaElo} Elo ({edge.advantageTeam})
                        </span>
                      </div>
                      <p className="text-[11.5px] text-slate-400 leading-relaxed">
                        {edge.description}
                      </p>
                    </div>
                  );
                })}
              </div>
            ) : (
              <div className="p-3 bg-slate-950/50 rounded-xl border border-slate-800 text-xs text-slate-400 font-mono">
                Evenly balanced tactical matchup; neither club holds an extreme swing edge in rotation whiff rate or bullpen leverage.
              </div>
            )}
          </div>
        </div>

        {/* Right Column: 5-Axis Tactical Radar & Tale of the Tape (6 cols) */}
        <div className="lg:col-span-6 space-y-6">
          <TacticalMismatchRadar
            teamA={teamACode}
            teamB={teamBCode}
            ratingsA={profileA.tacticalRatings}
            ratingsB={profileB.tacticalRatings}
          />

          {/* Tale of the Tape Summary Table */}
          <div className="bg-slate-900/90 border border-slate-800 rounded-2xl p-5 shadow-xl space-y-3 font-mono">
            <h3 className="text-xs font-bold text-white uppercase tracking-wider border-b border-slate-800/80 pb-2">
              Postseason Tale of the Tape
            </h3>

            <div className="space-y-2 text-xs">
              <div className="flex items-center justify-between p-2 rounded bg-slate-950/60 border border-slate-800/50">
                <span className="text-sky-400 font-bold">{profileA.regularWins} Wins</span>
                <span className="text-slate-400 text-[11px]">Regular Season Record</span>
                <span className="text-amber-400 font-bold">{profileB.regularWins} Wins</span>
              </div>

              <div className="flex items-center justify-between p-2 rounded bg-slate-950/60 border border-slate-800/50">
                <span className="text-sky-400 font-bold">{profileA.baseElo}</span>
                <span className="text-slate-400 text-[11px]">Base Team Elo Rating</span>
                <span className="text-amber-400 font-bold">{profileB.baseElo}</span>
              </div>

              <div className="flex items-center justify-between p-2 rounded bg-slate-950/60 border border-slate-800/50">
                <span className="text-sky-400 font-bold">rGS {profileA.starters[0]?.rGS}</span>
                <span className="text-slate-400 text-[11px]">Ace Starter Rating (Game 1)</span>
                <span className="text-amber-400 font-bold">rGS {profileB.starters[0]?.rGS}</span>
              </div>

              <div className="flex items-center justify-between p-2 rounded bg-slate-950/60 border border-slate-800/50">
                <span className="text-sky-400 font-bold">xFIP {profileA.relievers[0]?.xFip}</span>
                <span className="text-slate-400 text-[11px]">Closer / High-LI Shutdown</span>
                <span className="text-amber-400 font-bold">xFIP {profileB.relievers[0]?.xFip}</span>
              </div>

              <div className="flex items-center justify-between p-2 rounded bg-slate-950/60 border border-slate-800/50">
                <span className="text-sky-400 font-bold">wOBA {profileA.lineupCore[0]?.wOBA.toFixed(3)}</span>
                <span className="text-slate-400 text-[11px]">Lineup Anchor wOBA</span>
                <span className="text-amber-400 font-bold">wOBA {profileB.lineupCore[0]?.wOBA.toFixed(3)}</span>
              </div>
            </div>
          </div>
        </div>
      </div>

      {/* Bottom Section: Rotation & Game-by-Game Schedule */}
      <RotationMatchupCard
        teamA={teamACode}
        teamB={teamBCode}
        profileA={profileA}
        profileB={profileB}
        gameSchedule={seriesResult.gameSchedule}
      />
    </div>
  );
};
