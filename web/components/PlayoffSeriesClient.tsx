'use client';

import React, { useState, useMemo } from 'react';
import {
  PlayoffMatchupsCatalog,
  PlayoffSeriesMatchupResult,
  TeamPlayoffProfile,
} from '@/lib/playoffTypes';
import { TeamLogo } from '@/components/TeamLogo';
import { SeasonSourceBadge } from '@/components/SeasonSourceBadge';
import { SEASON_SOURCES } from '@/lib/season';
import { SeriesProbRing } from '@/components/SeriesProbRing';
import { TacticalMismatchRadar } from '@/components/TacticalMismatchRadar';
import { AnimatedMediaCard } from '@/components/AnimatedMediaCard';
import {
  Trophy,
  Swords,
  Sparkles,
  ArrowRightLeft,
  ShieldCheck,
} from 'lucide-react';

interface PlayoffSeriesClientProps {
  catalog: PlayoffMatchupsCatalog;
}

// Client-side Monte Carlo simulator for arbitrary pairings
function simulateClientSeries(
  teamA: TeamPlayoffProfile,
  teamB: TeamPlayoffProfile,
  hcaTeam: string,
  nSims = 10000
): PlayoffSeriesMatchupResult {
  const rawDiff = teamA.playoffNetRtg - teamB.playoffNetRtg;
  let mismatchDelta = 0;
  const edges: { title: string; advantageTeam: string; description: string; deltaMargin: number }[] = [];

  // 1. Pull-up vs Drop
  if (teamA.tacticalRatings.perimeterCreation >= 85 && teamB.tacticalRatings.dropVulnerability >= 65) {
    const pts = Number(((teamB.tacticalRatings.dropVulnerability - 50) * 0.03).toFixed(1));
    mismatchDelta += pts;
    edges.push({
      title: 'Pull-Up 3PT vs Drop Coverage Exploitation',
      advantageTeam: teamA.teamAbbr,
      description: `${teamA.teamAbbr}'s perimeter creators exploit ${teamB.teamAbbr}'s drop coverage.`,
      deltaMargin: pts,
    });
  } else if (teamB.tacticalRatings.perimeterCreation >= 85 && teamA.tacticalRatings.dropVulnerability >= 65) {
    const pts = Number(((teamA.tacticalRatings.dropVulnerability - 50) * 0.03).toFixed(1));
    mismatchDelta -= pts;
    edges.push({
      title: 'Pull-Up 3PT vs Drop Coverage Exploitation',
      advantageTeam: teamB.teamAbbr,
      description: `${teamB.teamAbbr}'s perimeter creators exploit ${teamA.teamAbbr}'s drop coverage.`,
      deltaMargin: pts,
    });
  }

  // 2. Interior Dominance
  const glassDiff = (teamA.tacticalRatings.interiorDominance - teamB.tacticalRatings.interiorDominance) * 0.025;
  if (Math.abs(glassDiff) >= 0.4) {
    const adv = glassDiff > 0 ? teamA.teamAbbr : teamB.teamAbbr;
    mismatchDelta += glassDiff;
    edges.push({
      title: 'Interior Rim & Glass Control',
      advantageTeam: adv,
      description: `${adv} commands a physical interior advantage on second-chance opportunities.`,
      deltaMargin: Number(Math.abs(glassDiff).toFixed(1)),
    });
  }

  const netMargin = Number((rawDiff + mismatchDelta).toFixed(2));
  const hcaPts = 2.8;
  const hcaIsA = hcaTeam === teamA.teamAbbr;
  const homeFlags = [true, true, false, false, true, false, true];
  const sigma = 11.8;

  // Normal CDF approximation
  const normalCdf = (z: number) => {
    const b1 = 0.319381530;
    const b2 = -0.356563782;
    const b3 = 1.781477937;
    const b4 = -1.821255978;
    const b5 = 1.330274429;
    const p = 0.2316419;
    const c2 = 0.39894228;
    if (z >= 0.0) {
      const t = 1.0 / (1.0 + p * z);
      return 1.0 - c2 * Math.exp(-z * z / 2.0) * t * (t * (t * (t * (t * b5 + b4) + b3) + b2) + b1);
    } else {
      const t = 1.0 / (1.0 - p * z);
      return c2 * Math.exp(-z * z / 2.0) * t * (t * (t * (t * (t * b5 + b4) + b3) + b2) + b1);
    }
  };

  const pAHome = normalCdf((netMargin + hcaPts) / sigma);
  const pAAway = normalCdf((netMargin - hcaPts) / sigma);

  let aWins = 0;
  const counts: Record<string, number> = {
    A_4: 0, A_5: 0, A_6: 0, A_7: 0,
    B_4: 0, B_5: 0, B_6: 0, B_7: 0,
  };
  let totalGames = 0;
  let coverMinus15 = 0;

  for (let s = 0; s < nSims; s++) {
    let wA = 0;
    let wB = 0;
    let g = 0;

    while (wA < 4 && wB < 4) {
      const isHcaHome = homeFlags[g];
      const isAHome = hcaIsA ? isHcaHome : !isHcaHome;
      const probA = isAHome ? pAHome : pAAway;

      if (Math.random() < probA) {
        wA++;
      } else {
        wB++;
      }
      g++;
    }

    totalGames += g;
    if (wA === 4) {
      aWins++;
      counts[`A_${g}`]++;
      if (g <= 6) coverMinus15++;
    } else {
      counts[`B_${g}`]++;
    }
  }

  const winProbA = Number((aWins / nSims).toFixed(4));
  const winProbB = Number((1 - winProbA).toFixed(4));

  const fairMlA = winProbA >= 0.5
    ? Math.round(-100 * winProbA / (1 - winProbA))
    : Math.round(100 * (1 - winProbA) / winProbA);
  const fairMlB = winProbB >= 0.5
    ? Math.round(-100 * winProbB / (1 - winProbB))
    : Math.round(100 * (1 - winProbB) / winProbB);

  return {
    teamA: teamA.teamAbbr,
    teamB: teamB.teamAbbr,
    hcaTeam,
    ratingDiffRaw: Number(rawDiff.toFixed(2)),
    tacticalMismatchAdjustment: Number(mismatchDelta.toFixed(2)),
    netRatingMargin: netMargin,
    winProbA,
    winProbB,
    fairMlA,
    fairMlB,
    avgGames: Number((totalGames / nSims).toFixed(2)),
    spreadMinus1_5Prob: Number((coverMinus15 / nSims).toFixed(3)),
    sweepProb: Number(((counts.A_4 + counts.B_4) / nSims * 100).toFixed(1)),
    gameDistributions: [
      { games: 4, winner: teamA.teamAbbr, probPct: Number((counts.A_4 / nSims * 100).toFixed(1)) },
      { games: 5, winner: teamA.teamAbbr, probPct: Number((counts.A_5 / nSims * 100).toFixed(1)) },
      { games: 6, winner: teamA.teamAbbr, probPct: Number((counts.A_6 / nSims * 100).toFixed(1)) },
      { games: 7, winner: teamA.teamAbbr, probPct: Number((counts.A_7 / nSims * 100).toFixed(1)) },
      { games: 4, winner: teamB.teamAbbr, probPct: Number((counts.B_4 / nSims * 100).toFixed(1)) },
      { games: 5, winner: teamB.teamAbbr, probPct: Number((counts.B_5 / nSims * 100).toFixed(1)) },
      { games: 6, winner: teamB.teamAbbr, probPct: Number((counts.B_6 / nSims * 100).toFixed(1)) },
      { games: 7, winner: teamB.teamAbbr, probPct: Number((counts.B_7 / nSims * 100).toFixed(1)) },
    ],
    tacticalEdges: edges,
  };
}

export const PlayoffSeriesClient: React.FC<PlayoffSeriesClientProps> = ({ catalog }) => {
  const teamList = useMemo(() => {
    return Object.values(catalog.teams).sort((a, b) => b.regularWins - a.regularWins);
  }, [catalog.teams]);

  // Selected teams and home court
  const [teamACode, setTeamACode] = useState<string>('OKC');
  const [teamBCode, setTeamBCode] = useState<string>('BOS');
  const [hcaTeam, setHcaTeam] = useState<string>('OKC');

  const profileA = catalog.teams[teamACode] || teamList[0];
  const profileB = catalog.teams[teamBCode] || teamList[1];

  // Check precomputed or simulate live
  const matchupResult = useMemo(() => {
    const precomputed = catalog.sampleMatchups.find(
      (m) =>
        (m.teamA === teamACode && m.teamB === teamBCode && m.hcaTeam === hcaTeam) ||
        (m.teamA === teamBCode && m.teamB === teamACode && m.hcaTeam === hcaTeam)
    );

    if (precomputed) {
      if (precomputed.teamA === teamACode) return precomputed;
      // Invert if A/B are flipped
      return {
        ...precomputed,
        teamA: teamACode,
        teamB: teamBCode,
        winProbA: precomputed.winProbB,
        winProbB: precomputed.winProbA,
        fairMlA: precomputed.fairMlB,
        fairMlB: precomputed.fairMlA,
        netRatingMargin: -precomputed.netRatingMargin,
        ratingDiffRaw: -precomputed.ratingDiffRaw,
      };
    }

    // Run client-side simulation
    return simulateClientSeries(profileA, profileB, hcaTeam);
  }, [catalog.sampleMatchups, teamACode, teamBCode, hcaTeam, profileA, profileB]);

  const swapTeams = () => {
    setTeamACode(teamBCode);
    setTeamBCode(teamACode);
    setHcaTeam(teamBCode);
  };

  const marqueePresets = [
    { label: 'Finals Preview', a: 'OKC', b: 'BOS', hca: 'OKC' },
    { label: 'East Heavyweight', a: 'BOS', b: 'NYK', hca: 'BOS' },
    { label: 'Giannis in Miami vs BOS', a: 'MIA', b: 'BOS', hca: 'BOS' },
    { label: 'West Colosseum', a: 'OKC', b: 'DEN', hca: 'OKC' },
    { label: 'Flagg/Luka vs Trae/AD', a: 'DAL', b: 'LAL', hca: 'DAL' },
    { label: 'Western Grudge', a: 'HOU', b: 'GSW', hca: 'HOU' },
  ];

  return (
    <div className="space-y-6">
      {/* Top Banner */}
      <div className="bg-gradient-to-r from-slate-900 via-slate-900 to-indigo-950/80 border border-slate-800 rounded-2xl p-6 shadow-xl relative overflow-hidden">
        <div className="absolute right-0 top-0 bottom-0 w-96 bg-[radial-gradient(ellipse_at_top_right,_var(--tw-gradient-stops))] from-amber-500/10 via-indigo-500/5 to-transparent pointer-events-none" />

        <div className="flex flex-col md:flex-row md:items-center justify-between gap-4 relative z-10">
          <div>
            <div className="flex items-center gap-2.5">
              <div className="p-2.5 rounded-xl bg-gradient-to-tr from-amber-500 to-orange-600 text-white shadow-lg shadow-orange-500/20">
                <Swords className="w-6 h-6" />
              </div>
              <div>
                <div className="flex items-center gap-2">
                  <h1 className="text-xl sm:text-2xl font-extrabold text-white tracking-tight">
                    7-Game Playoff Series Matchup Simulator
                  </h1>
                  <SeasonSourceBadge
                    season={SEASON_SOURCES.playoffSeries.season}
                    kind="projection"
                    label="Projected season"
                    title={SEASON_SOURCES.playoffSeries.note}
                  />
                </div>
                <p className="text-xs sm:text-sm text-slate-400 mt-0.5">
                  10,000-sim Monte Carlo engine with 8-man playoff rotation contractions, tactical mismatch exploitation, and 2-2-1-1-1 home court advantage.
                </p>
              </div>
            </div>
          </div>

          <div className="flex items-center gap-2 text-xs font-mono">
            <span className="px-3 py-1.5 rounded-lg bg-surface/80 border border-slate-800 text-slate-300">
              σ = 11.8 Margins
            </span>
            <span className="px-3 py-1.5 rounded-lg bg-indigo-500/10 border border-indigo-500/30 text-indigo-400 font-bold">
              10,000 Sims / Run
            </span>
          </div>
        </div>
      </div>

      {/* Preset Matchup Pills */}
      <div className="p-3 rounded-xl bg-surface-raised/60 border border-slate-800 flex items-center gap-2 overflow-x-auto">
        <span className="text-xs font-bold text-slate-400 whitespace-nowrap flex items-center gap-1.5 pl-1">
          <Sparkles className="w-3.5 h-3.5 text-amber-400" />
          Marquee Series:
        </span>
        <div className="flex items-center gap-2">
          {marqueePresets.map((preset) => (
            <button
              key={preset.label}
              onClick={() => {
                setTeamACode(preset.a);
                setTeamBCode(preset.b);
                setHcaTeam(preset.hca);
              }}
              className={`px-2.5 py-1 rounded-lg text-xs font-medium border flex items-center gap-1.5 whitespace-nowrap transition-all ${
                teamACode === preset.a && teamBCode === preset.b
                  ? 'bg-amber-500/20 text-amber-300 border-amber-500/40 shadow-sm'
                  : 'bg-surface text-slate-400 border-slate-800 hover:text-white hover:bg-slate-850'
              }`}
            >
              <TeamLogo team={preset.a} size="xs" />
              <span>vs</span>
              <TeamLogo team={preset.b} size="xs" />
              <span className="text-slate-300 font-semibold">{preset.label}</span>
            </button>
          ))}
        </div>
      </div>

      {/* Team Selection Bar */}
      <div className="p-5 rounded-2xl bg-surface-raised/90 border border-slate-800 shadow-xl grid grid-cols-1 md:grid-cols-12 gap-4 items-center">
        {/* Team A Picker (5 cols) */}
        <div className="md:col-span-5 p-3.5 rounded-xl bg-surface/80 border border-slate-800/90 flex items-center justify-between gap-3">
          <div className="flex items-center gap-3 min-w-0">
            <TeamLogo team={teamACode} size="lg" />
            <div className="min-w-0">
              <span className="text-[10px] text-amber-400 font-bold uppercase tracking-wider block font-mono">
                Team A (Designated)
              </span>
              <select
                value={teamACode}
                onChange={(e) => {
                  const newA = e.target.value;
                  setTeamACode(newA);
                  if (hcaTeam === teamACode) setHcaTeam(newA);
                }}
                className="bg-transparent text-sm font-black text-white focus:outline-none cursor-pointer tracking-tight"
              >
                {teamList.map((tm) => (
                  <option key={tm.teamAbbr} value={tm.teamAbbr} className="bg-surface-raised text-white">
                    {tm.teamName} ({tm.teamAbbr}) • {tm.regularWins} W
                  </option>
                ))}
              </select>
              <span className="text-xs text-slate-400 block mt-0.5">
                8-Man Playoff Net: <span className="font-mono text-amber-400 font-bold">+{profileA.playoffNetRtg}</span> (Reg: +{profileA.regularNetRtg})
              </span>
            </div>
          </div>
          {hcaTeam === teamACode && (
            <span className="text-[10px] font-mono px-2 py-0.5 rounded bg-emerald-500/10 text-emerald-400 border border-emerald-500/30 font-bold whitespace-nowrap">
              Home Court (2-2-1-1-1)
            </span>
          )}
        </div>

        {/* Swap & HCA Toggle Controls (2 cols) */}
        <div className="md:col-span-2 flex flex-col items-center justify-center gap-2">
          <button
            onClick={swapTeams}
            className="p-2 rounded-xl bg-slate-800/80 hover:bg-slate-700 text-slate-300 hover:text-white transition-all shadow"
            title="Swap Teams"
          >
            <ArrowRightLeft className="w-4 h-4" />
          </button>
          <div className="flex items-center gap-1 text-[11px] font-mono text-slate-400">
            <span>HCA:</span>
            <button
              onClick={() => setHcaTeam(hcaTeam === teamACode ? teamBCode : teamACode)}
              className="text-amber-400 font-bold underline cursor-pointer hover:text-amber-300"
            >
              {hcaTeam}
            </button>
          </div>
        </div>

        {/* Team B Picker (5 cols) */}
        <div className="md:col-span-5 p-3.5 rounded-xl bg-surface/80 border border-slate-800/90 flex items-center justify-between gap-3">
          <div className="flex items-center gap-3 min-w-0">
            <TeamLogo team={teamBCode} size="lg" />
            <div className="min-w-0">
              <span className="text-[10px] text-sky-400 font-bold uppercase tracking-wider block font-mono">
                Team B (Opponent)
              </span>
              <select
                value={teamBCode}
                onChange={(e) => {
                  const newB = e.target.value;
                  setTeamBCode(newB);
                  if (hcaTeam === teamBCode) setHcaTeam(newB);
                }}
                className="bg-transparent text-sm font-black text-white focus:outline-none cursor-pointer tracking-tight"
              >
                {teamList.map((tm) => (
                  <option key={tm.teamAbbr} value={tm.teamAbbr} className="bg-surface-raised text-white">
                    {tm.teamName} ({tm.teamAbbr}) • {tm.regularWins} W
                  </option>
                ))}
              </select>
              <span className="text-xs text-slate-400 block mt-0.5">
                8-Man Playoff Net: <span className="font-mono text-sky-400 font-bold">+{profileB.playoffNetRtg}</span> (Reg: +{profileB.regularNetRtg})
              </span>
            </div>
          </div>
          {hcaTeam === teamBCode && (
            <span className="text-[10px] font-mono px-2 py-0.5 rounded bg-emerald-500/10 text-emerald-400 border border-emerald-500/30 font-bold whitespace-nowrap">
              Home Court (2-2-1-1-1)
            </span>
          )}
        </div>
      </div>

      {/* Main Simulation Results Dashboard */}
      <div className="grid grid-cols-1 lg:grid-cols-12 gap-6">
        {/* Left: Series Outcome Probabilities Ring (5 cols) */}
        <div className="lg:col-span-5 bg-surface-raised/80 border border-slate-800 rounded-xl p-5 shadow-lg flex flex-col justify-between">
          <div>
            <div className="flex items-center justify-between pb-3 border-b border-slate-800 mb-3">
              <div className="flex items-center gap-2">
                <Trophy className="w-4 h-4 text-amber-400" />
                <h3 className="text-sm font-bold text-white tracking-tight">
                  10,000-Sim Series Probabilities
                </h3>
              </div>
              <span className="text-xs font-mono font-bold text-amber-400">
                Fair ML: {matchupResult.fairMlA > 0 ? `+${matchupResult.fairMlA}` : matchupResult.fairMlA}
              </span>
            </div>

            <SeriesProbRing
              teamA={teamACode}
              teamB={teamBCode}
              winProbA={matchupResult.winProbA}
              winProbB={matchupResult.winProbB}
              avgGames={matchupResult.avgGames}
              gameDistributions={matchupResult.gameDistributions}
              size={230}
            />
          </div>

          <div className="pt-3 border-t border-slate-800/80 mt-4 flex items-center justify-between text-xs font-mono">
            <span className="text-slate-400">Sweep Probability:</span>
            <span className="font-bold text-white">{matchupResult.sweepProb}%</span>
          </div>
        </div>

        {/* Right: Tactical Mismatch Analysis (7 cols) */}
        <div className="lg:col-span-7">
          <TacticalMismatchRadar
            teamA={teamACode}
            teamB={teamBCode}
            ratingsA={profileA.tacticalRatings}
            ratingsB={profileB.tacticalRatings}
            tacticalEdges={matchupResult.tacticalEdges}
          />
        </div>
      </div>

      {/* Postseason Trajectory & Playoff Leverage Visualizations */}
      <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
        <AnimatedMediaCard
          name="build_series_trajectory_gif"
          title="7-Game Series Net Rating Trajectory"
          alt="Animated 7-game series net rating trajectory showing game-by-game margin swings and series leverage"
          caption="Game-by-game evolution of postseason net rating margin shifts across 7-game series iterations, tracking swing games and pivotal tactical adjustments."
        />
        <AnimatedMediaCard
          name="gif_playoff_prob_bump"
          title="Playoff Seed & Play-In Leverage Bump Trajectory"
          alt="Animated bump chart tracking playoff probability and seed certainty across conference contenders"
          caption="Playoff seed certainty and play-in tournament threshold trajectories across Eastern and Western conference contenders throughout late-season games."
        />
      </div>

      {/* 8-Man Playoff Rotation Side-by-Side Comparison */}
      <div className="bg-surface-raised/80 border border-slate-800 rounded-xl overflow-hidden shadow-lg p-5 space-y-4">
        <div className="flex flex-wrap items-center justify-between gap-3 pb-3 border-b border-slate-800">
          <div>
            <h3 className="text-base font-bold text-white tracking-tight flex items-center gap-2">
              <ShieldCheck className="w-5 h-5 text-indigo-400" />
              <span>8-Man Postseason Rotations & Minutes Compression</span>
            </h3>
            <p className="text-xs text-slate-400 mt-0.5">
              Side-by-side comparison of 8-man postseason depth (Starters 1–5, Sixth Man, and Key Bench), adjusted to 240 team minutes.
            </p>
          </div>

          <div className="flex items-center gap-4 text-xs font-mono">
            <div className="text-right">
              <span className="text-slate-400 block text-[10px]">Top-3 Boost ({teamACode})</span>
              <span className="font-bold text-amber-400">+{profileA.top3TalentBump} PTS/100</span>
            </div>
            <div className="text-right">
              <span className="text-slate-400 block text-[10px]">Top-3 Boost ({teamBCode})</span>
              <span className="font-bold text-sky-400">+{profileB.top3TalentBump} PTS/100</span>
            </div>
          </div>
        </div>

        {/* Rotations Grid: 2 columns for Team A vs Team B */}
        <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
          {/* Team A Rotation */}
          <div className="space-y-2">
            <div className="flex items-center justify-between pb-1 text-xs font-bold text-amber-400 font-mono border-b border-slate-800">
              <div className="flex items-center gap-2">
                <TeamLogo team={teamACode} size="xs" />
                <span>{profileA.teamName} Rotation</span>
              </div>
              <span>Playoff MPG</span>
            </div>
            <div className="space-y-1.5">
              {profileA.rotation.map((p) => (
                <div
                  key={p.playerId}
                  className="p-2 rounded-lg bg-surface/60 border border-slate-800/80 flex items-center justify-between text-xs"
                >
                  <div className="min-w-0">
                    <div className="flex items-center gap-2">
                      <span className="text-[10px] font-mono px-1 py-0.2 rounded bg-slate-800 text-slate-300">
                        {p.position}
                      </span>
                      <span className="font-semibold text-white truncate">{p.playerName}</span>
                      <span className="text-[9px] text-slate-400 italic hidden sm:inline">
                        • {p.role}
                      </span>
                    </div>
                    <span className="text-[10px] text-slate-400 font-mono mt-0.5 block">
                      {p.pts} PPG • {p.reb} RPG • {p.ast} APG • {p.praZscore > 0 ? `+${p.praZscore}` : p.praZscore} PRA z
                    </span>
                  </div>
                  <div className="text-right font-mono font-bold text-amber-400">
                    {p.playoffMpg}m
                  </div>
                </div>
              ))}
            </div>
          </div>

          {/* Team B Rotation */}
          <div className="space-y-2">
            <div className="flex items-center justify-between pb-1 text-xs font-bold text-sky-400 font-mono border-b border-slate-800">
              <div className="flex items-center gap-2">
                <TeamLogo team={teamBCode} size="xs" />
                <span>{profileB.teamName} Rotation</span>
              </div>
              <span>Playoff MPG</span>
            </div>
            <div className="space-y-1.5">
              {profileB.rotation.map((p) => (
                <div
                  key={p.playerId}
                  className="p-2 rounded-lg bg-surface/60 border border-slate-800/80 flex items-center justify-between text-xs"
                >
                  <div className="min-w-0">
                    <div className="flex items-center gap-2">
                      <span className="text-[10px] font-mono px-1 py-0.2 rounded bg-slate-800 text-slate-300">
                        {p.position}
                      </span>
                      <span className="font-semibold text-white truncate">{p.playerName}</span>
                      <span className="text-[9px] text-slate-400 italic hidden sm:inline">
                        • {p.role}
                      </span>
                    </div>
                    <span className="text-[10px] text-slate-400 font-mono mt-0.5 block">
                      {p.pts} PPG • {p.reb} RPG • {p.ast} APG • {p.praZscore > 0 ? `+${p.praZscore}` : p.praZscore} PRA z
                    </span>
                  </div>
                  <div className="text-right font-mono font-bold text-sky-400">
                    {p.playoffMpg}m
                  </div>
                </div>
              ))}
            </div>
          </div>
        </div>
      </div>
    </div>
  );
};
