'use client';

import React, { useState, useMemo } from 'react';
import {
  PlayoffMatchupsCatalog,
  PlayoffSeriesMatchupResult,
  TeamPlayoffProfile,
  GameOutcomeProb,
  TacticalEdge,
} from '@/lib/playoffTypes';
import { TeamLogo } from '@/components/TeamLogo';
import { SeriesProbRing } from '@/components/SeriesProbRing';
import { TacticalMismatchRadar } from '@/components/TacticalMismatchRadar';
import {
  Trophy,
  Swords,
  ArrowRightLeft,
  ShieldCheck,
  History,
  ChevronRight,
  ChevronDown,
} from 'lucide-react';

interface PlayoffSeriesClientProps {
  catalog: PlayoffMatchupsCatalog;
}

type SeriesFormat = 'bo3' | 'bo5' | 'bo7';

interface FormatConfig {
  winThreshold: number;
  homeFlags: boolean[];
  label: string;
  roundName: string;
}

const FORMAT_CONFIGS: Record<SeriesFormat, FormatConfig> = {
  bo3: {
    winThreshold: 2,
    homeFlags: [true, false, true],
    label: 'Best-of-3 (1-1-1)',
    roundName: 'First Round',
  },
  bo5: {
    winThreshold: 3,
    homeFlags: [true, true, false, false, true],
    label: 'Best-of-5 (2-2-1)',
    roundName: 'Semifinals',
  },
  bo7: {
    winThreshold: 4,
    homeFlags: [true, true, false, false, true, false, true],
    label: 'Best-of-7 (2-2-1-1-1)',
    roundName: 'WNBA Finals',
  },
};

// Client-side Monte Carlo simulator for arbitrary pairings & formats
function simulateClientSeries(
  teamA: TeamPlayoffProfile,
  teamB: TeamPlayoffProfile,
  hcaTeam: string,
  format: SeriesFormat = 'bo7',
  nSims = 10000
): PlayoffSeriesMatchupResult {
  const rawDiff = teamA.playoffNetRtg - teamB.playoffNetRtg;
  let mismatchDelta = 0;
  const edges: TacticalEdge[] = [];

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
      description: `${adv} commands a physical interior presence on second-chance opportunities.`,
      deltaMargin: Number(Math.abs(glassDiff).toFixed(1)),
    });
  }

  // 3. Switchability
  const switchDiff = (teamA.tacticalRatings.switchability - teamB.tacticalRatings.switchability) * 0.02;
  if (Math.abs(switchDiff) >= 0.3) {
    const adv = switchDiff > 0 ? teamA.teamAbbr : teamB.teamAbbr;
    mismatchDelta += switchDiff;
    edges.push({
      title: 'Defensive Switchability & Mismatch Neutralization',
      advantageTeam: adv,
      description: `${adv}'s switchability extinguishes primary screening actions.`,
      deltaMargin: Number(Math.abs(switchDiff).toFixed(1)),
    });
  }

  const netMargin = Number((rawDiff + mismatchDelta).toFixed(2));
  const hcaPts = 2.4; // WNBA_HCA
  const hcaIsA = hcaTeam === teamA.teamAbbr;
  const sigma = 14.0; // WNBA_MARGIN_SIGMA

  const fmt = FORMAT_CONFIGS[format];
  const { winThreshold, homeFlags } = fmt;

  // Normal CDF approximation
  const normalCdf = (z: number) => {
    const b1 = 0.31938153;
    const b2 = -0.356563782;
    const b3 = 1.781477937;
    const b4 = -1.821255978;
    const b5 = 1.330274429;
    const p = 0.2316419;
    const c2 = 0.39894228;
    if (z >= 0.0) {
      const t = 1.0 / (1.0 + p * z);
      return 1.0 - c2 * Math.exp((-z * z) / 2.0) * t * (t * (t * (t * (t * b5 + b4) + b3) + b2) + b1);
    } else {
      const t = 1.0 / (1.0 - p * z);
      return c2 * Math.exp((-z * z) / 2.0) * t * (t * (t * (t * (t * b5 + b4) + b3) + b2) + b1);
    }
  };

  const pAHome = normalCdf((netMargin + hcaPts) / sigma);
  const pAAway = normalCdf((netMargin - hcaPts) / sigma);

  let aWins = 0;
  const gameCounts: Record<string, number> = {};
  let totalGames = 0;
  let coverMinus1_5 = 0;

  for (let s = 0; s < nSims; s++) {
    let wA = 0;
    let wB = 0;
    let g = 0;

    while (wA < winThreshold && wB < winThreshold) {
      const isHcaHome = homeFlags[g] ?? true;
      const isAHome = hcaIsA ? isHcaHome : !isHcaHome;
      const probA = isAHome ? pAHome : pAAway;

      if (Math.random() < probA) {
        wA++;
      } else {
        wB++;
      }
      g++;
    }

    const seriesLen = wA + wB;
    totalGames += seriesLen;

    if (wA === winThreshold) {
      aWins++;
      const k = `A_${seriesLen}`;
      gameCounts[k] = (gameCounts[k] || 0) + 1;
      if (seriesLen <= winThreshold * 2 - 2) {
        coverMinus1_5++;
      }
    } else {
      const k = `B_${seriesLen}`;
      gameCounts[k] = (gameCounts[k] || 0) + 1;
    }
  }

  const winProbA = Number((aWins / nSims).toFixed(4));
  const winProbB = Number((1 - winProbA).toFixed(4));

  const fairMlA =
    winProbA >= 0.5
      ? Math.round((-100 * winProbA) / (1 - winProbA))
      : Math.round((100 * (1 - winProbA)) / winProbA);
  const fairMlB =
    winProbB >= 0.5
      ? Math.round((-100 * winProbB) / (1 - winProbB))
      : Math.round((100 * (1 - winProbB)) / winProbB);

  const distList: GameOutcomeProb[] = [];
  const minGames = winThreshold;
  const maxGames = winThreshold * 2 - 1;

  for (let g = minGames; g <= maxGames; g++) {
    const cntA = gameCounts[`A_${g}`] || 0;
    distList.push({
      games: g,
      winner: teamA.teamAbbr,
      probPct: Number(((cntA / nSims) * 100).toFixed(1)),
    });
  }

  for (let g = minGames; g <= maxGames; g++) {
    const cntB = gameCounts[`B_${g}`] || 0;
    distList.push({
      games: g,
      winner: teamB.teamAbbr,
      probPct: Number(((cntB / nSims) * 100).toFixed(1)),
    });
  }

  const sweepCount = (gameCounts[`A_${winThreshold}`] || 0) + (gameCounts[`B_${winThreshold}`] || 0);

  return {
    teamA: teamA.teamAbbr,
    teamB: teamB.teamAbbr,
    hcaTeam,
    format,
    ratingDiffRaw: Number(rawDiff.toFixed(2)),
    tacticalMismatchAdjustment: Number(mismatchDelta.toFixed(2)),
    netRatingMargin: netMargin,
    winProbA,
    winProbB,
    fairMlA,
    fairMlB,
    avgGames: Number((totalGames / nSims).toFixed(2)),
    spreadMinus1_5Prob: Number((coverMinus1_5 / nSims).toFixed(3)),
    sweepProb: Number(((sweepCount / nSims) * 100).toFixed(1)),
    gameDistributions: distList,
    tacticalEdges: edges,
  };
}

export const PlayoffSeriesClient: React.FC<PlayoffSeriesClientProps> = ({ catalog }) => {
  const teamKeys = useMemo(() => Object.keys(catalog.teams || {}), [catalog.teams]);

  // Tab State: 'simulator' | 'historical'
  const [activeTab, setActiveTab] = useState<'simulator' | 'historical'>('simulator');

  // Matchup Selection
  const [teamACode, setTeamACode] = useState<string>(teamKeys.includes('NY') ? 'NY' : teamKeys[0] || 'NY');
  const [teamBCode, setTeamBCode] = useState<string>(teamKeys.includes('MIN') ? 'MIN' : teamKeys[1] || 'MIN');
  const [hcaTeam, setHcaTeam] = useState<string>(teamACode);
  const [format, setFormat] = useState<SeriesFormat>('bo7');

  // Historical Bracket Year
  const bracketYears = useMemo(() => Object.keys(catalog.historicalBrackets || {}).sort().reverse(), [catalog.historicalBrackets]);
  const [selectedYear, setSelectedYear] = useState<string>(bracketYears[0] || '2025');
  const [expandedSeries, setExpandedSeries] = useState<Record<number, boolean>>({});

  const teamA = catalog.teams[teamACode];
  const teamB = catalog.teams[teamBCode];

  // Run simulation
  const result = useMemo(() => {
    if (!teamA || !teamB) return null;
    return simulateClientSeries(teamA, teamB, hcaTeam, format);
  }, [teamA, teamB, hcaTeam, format]);

  const handleSwap = () => {
    const oldA = teamACode;
    setTeamACode(teamBCode);
    setTeamBCode(oldA);
    setHcaTeam(teamBCode);
  };

  const handleQuickMatchup = (a: string, b: string, h: string, fmt: SeriesFormat = 'bo7') => {
    setTeamACode(a);
    setTeamBCode(b);
    setHcaTeam(h);
    setFormat(fmt);
  };

  const toggleSeriesExpand = (idx: number) => {
    setExpandedSeries((prev) => ({ ...prev, [idx]: !prev[idx] }));
  };

  return (
    <div className="space-y-8 pb-16">
      {/* Page Header */}
      <div className="flex flex-col md:flex-row md:items-center justify-between pb-6 border-b border-slate-800 gap-4">
        <div>
          <div className="flex items-center gap-2 text-xs font-mono font-bold text-amber-400 tracking-wider uppercase mb-1">
            <Trophy className="w-4 h-4" />
            <span>WNBA Postseason Engine</span>
          </div>
          <h1 className="text-3xl font-black text-white tracking-tight">
            Playoff Series Simulator
          </h1>
          <p className="text-sm text-slate-400 mt-1 max-w-3xl leading-relaxed">
            10,000-sim Monte Carlo playoff series simulator with 8-man rotation shortening
            (200 team-minute WNBA regulation scale), pairwise tactical mismatch adjustments,
            and complete historical bracket game logs.
          </p>
        </div>

        {/* Tab Switcher */}
        <div className="flex items-center bg-surface-raised border border-slate-800 rounded-lg p-1 self-start md:self-auto">
          <button
            onClick={() => setActiveTab('simulator')}
            className={`flex items-center gap-2 px-4 py-2 rounded-md text-xs font-bold transition-all ${
              activeTab === 'simulator'
                ? 'bg-accent-600 text-white shadow-md'
                : 'text-slate-400 hover:text-white'
            }`}
          >
            <Swords className="w-4 h-4" />
            <span>Series Simulator</span>
          </button>
          <button
            onClick={() => setActiveTab('historical')}
            className={`flex items-center gap-2 px-4 py-2 rounded-md text-xs font-bold transition-all ${
              activeTab === 'historical'
                ? 'bg-accent-600 text-white shadow-md'
                : 'text-slate-400 hover:text-white'
            }`}
          >
            <History className="w-4 h-4" />
            <span>Historical Brackets</span>
          </button>
        </div>
      </div>

      {activeTab === 'simulator' ? (
        <>
          {/* Marquee Quick-Select Bar */}
          <div className="space-y-2">
            <span className="text-[11px] font-bold text-slate-400 uppercase tracking-wider block">
              Marquee Postseason Pairings
            </span>
            <div className="flex flex-wrap gap-2">
              <button
                onClick={() => handleQuickMatchup('NY', 'MIN', 'NY', 'bo7')}
                className="px-3 py-1.5 rounded-full text-xs font-mono font-bold bg-surface-raised border border-slate-800 hover:border-amber-500/60 text-slate-300 hover:text-amber-400 transition-all flex items-center gap-2"
              >
                <span>NY vs MIN</span>
                <span className="text-[10px] text-amber-500 font-semibold">(2024/2026 Finals Rematch)</span>
              </button>
              <button
                onClick={() => handleQuickMatchup('LV', 'NY', 'LV', 'bo7')}
                className="px-3 py-1.5 rounded-full text-xs font-mono font-bold bg-surface-raised border border-slate-800 hover:border-amber-500/60 text-slate-300 hover:text-amber-400 transition-all flex items-center gap-2"
              >
                <span>LV vs NY</span>
                <span className="text-[10px] text-slate-500 font-semibold">(Heavyweight Clash)</span>
              </button>
              <button
                onClick={() => handleQuickMatchup('MIN', 'LV', 'MIN', 'bo5')}
                className="px-3 py-1.5 rounded-full text-xs font-mono font-bold bg-surface-raised border border-slate-800 hover:border-amber-500/60 text-slate-300 hover:text-amber-400 transition-all flex items-center gap-2"
              >
                <span>MIN vs LV</span>
                <span className="text-[10px] text-slate-500 font-semibold">(West Finals Bo5)</span>
              </button>
              <button
                onClick={() => handleQuickMatchup('IND', 'CHI', 'IND', 'bo3')}
                className="px-3 py-1.5 rounded-full text-xs font-mono font-bold bg-surface-raised border border-slate-800 hover:border-amber-500/60 text-slate-300 hover:text-amber-400 transition-all flex items-center gap-2"
              >
                <span>IND vs CHI</span>
                <span className="text-[10px] text-slate-500 font-semibold">(Midwest Bo3)</span>
              </button>
              <button
                onClick={() => handleQuickMatchup('CON', 'IND', 'CON', 'bo5')}
                className="px-3 py-1.5 rounded-full text-xs font-mono font-bold bg-surface-raised border border-slate-800 hover:border-amber-500/60 text-slate-300 hover:text-amber-400 transition-all flex items-center gap-2"
              >
                <span>CON vs IND</span>
                <span className="text-[10px] text-slate-500 font-semibold">(East Semifinals)</span>
              </button>
              <button
                onClick={() => handleQuickMatchup('GS', 'LA', 'GS', 'bo3')}
                className="px-3 py-1.5 rounded-full text-xs font-mono font-bold bg-surface-raised border border-slate-800 hover:border-amber-500/60 text-slate-300 hover:text-amber-400 transition-all flex items-center gap-2"
              >
                <span>GS vs LA</span>
                <span className="text-[10px] text-slate-500 font-semibold">(California Clash)</span>
              </button>
            </div>
          </div>

          {/* Matchup Setup Panel */}
          <div className="bg-surface-raised/90 border border-slate-800 rounded-2xl p-6 shadow-xl">
            <div className="grid grid-cols-1 lg:grid-cols-12 gap-6 items-center">
              {/* Team A Picker */}
              <div className="lg:col-span-4 bg-surface/60 border border-slate-800 rounded-xl p-4 space-y-3">
                <div className="flex items-center justify-between">
                  <span className="text-xs font-mono uppercase tracking-wider text-amber-400 font-bold">
                    Team A
                  </span>
                  <span className="text-[10px] font-mono px-2 py-0.5 rounded bg-slate-800 text-slate-400">
                    {teamA?.conference}ern Conf
                  </span>
                </div>
                <div className="flex items-center gap-3">
                  <TeamLogo team={teamACode} size="lg" />
                  <div className="flex-1">
                    <select
                      value={teamACode}
                      onChange={(e) => {
                        const newA = e.target.value;
                        setTeamACode(newA);
                        if (hcaTeam === teamACode) setHcaTeam(newA);
                      }}
                      className="w-full bg-surface-raised border border-slate-700 rounded-lg px-3 py-2 text-sm font-bold text-white focus:outline-none focus:border-amber-500"
                    >
                      {teamKeys.map((k) => (
                        <option key={k} value={k} disabled={k === teamBCode}>
                          {catalog.teams[k]?.teamName || k} ({k})
                        </option>
                      ))}
                    </select>
                    <div className="flex items-center gap-2 mt-1.5 text-xs text-slate-400">
                      <span>Wins: <strong className="text-white font-mono">{teamA?.regularWins}</strong></span>
                      <span>•</span>
                      <span>Playoff Net: <strong className="text-amber-400 font-mono">+{teamA?.playoffNetRtg}</strong></span>
                    </div>
                  </div>
                </div>
              </div>

              {/* Controls: Swap, Format & HCA */}
              <div className="lg:col-span-4 flex flex-col items-center justify-center space-y-4">
                <button
                  onClick={handleSwap}
                  className="p-2.5 rounded-full bg-slate-800 hover:bg-slate-700 text-slate-300 hover:text-white transition-all border border-slate-700 shadow-md group"
                  title="Swap Teams"
                >
                  <ArrowRightLeft className="w-4 h-4 group-hover:scale-110 transition-transform" />
                </button>

                {/* Series Format Selector */}
                <div className="w-full space-y-1">
                  <span className="text-[10px] font-mono text-slate-400 uppercase tracking-wider block text-center">
                    Postseason Round Format
                  </span>
                  <div className="grid grid-cols-3 gap-1 bg-surface p-1 rounded-lg border border-slate-800">
                    {(['bo3', 'bo5', 'bo7'] as SeriesFormat[]).map((fmt) => (
                      <button
                        key={fmt}
                        onClick={() => setFormat(fmt)}
                        className={`py-1.5 text-[11px] font-mono font-bold rounded-md transition-all text-center ${
                          format === fmt
                            ? 'bg-accent-600 text-white shadow-sm'
                            : 'text-slate-400 hover:text-white hover:bg-surface-raised'
                        }`}
                      >
                        {fmt === 'bo3' ? 'Bo3 (R1)' : fmt === 'bo5' ? 'Bo5 (Semis)' : 'Bo7 (Finals)'}
                      </button>
                    ))}
                  </div>
                  <span className="text-[10px] text-slate-500 text-center block font-mono">
                    {FORMAT_CONFIGS[format].label} — Win {FORMAT_CONFIGS[format].winThreshold} to advance
                  </span>
                </div>

                {/* Home Court Selector */}
                <div className="w-full space-y-1">
                  <span className="text-[10px] font-mono text-slate-400 uppercase tracking-wider block text-center">
                    Home-Court Advantage (+2.40 PTS)
                  </span>
                  <div className="grid grid-cols-2 gap-1 bg-surface p-1 rounded-lg border border-slate-800">
                    <button
                      onClick={() => setHcaTeam(teamACode)}
                      className={`py-1 text-xs font-mono font-bold rounded-md transition-all ${
                        hcaTeam === teamACode
                          ? 'bg-amber-500/20 text-amber-300 border border-amber-500/40'
                          : 'text-slate-400 hover:text-white'
                      }`}
                    >
                      {teamACode} HCA
                    </button>
                    <button
                      onClick={() => setHcaTeam(teamBCode)}
                      className={`py-1 text-xs font-mono font-bold rounded-md transition-all ${
                        hcaTeam === teamBCode
                          ? 'bg-sky-500/20 text-sky-300 border border-sky-500/40'
                          : 'text-slate-400 hover:text-white'
                      }`}
                    >
                      {teamBCode} HCA
                    </button>
                  </div>
                </div>
              </div>

              {/* Team B Picker */}
              <div className="lg:col-span-4 bg-surface/60 border border-slate-800 rounded-xl p-4 space-y-3">
                <div className="flex items-center justify-between">
                  <span className="text-xs font-mono uppercase tracking-wider text-sky-400 font-bold">
                    Team B
                  </span>
                  <span className="text-[10px] font-mono px-2 py-0.5 rounded bg-slate-800 text-slate-400">
                    {teamB?.conference}ern Conf
                  </span>
                </div>
                <div className="flex items-center gap-3">
                  <TeamLogo team={teamBCode} size="lg" />
                  <div className="flex-1">
                    <select
                      value={teamBCode}
                      onChange={(e) => {
                        const newB = e.target.value;
                        setTeamBCode(newB);
                        if (hcaTeam === teamBCode) setHcaTeam(newB);
                      }}
                      className="w-full bg-surface-raised border border-slate-700 rounded-lg px-3 py-2 text-sm font-bold text-white focus:outline-none focus:border-sky-500"
                    >
                      {teamKeys.map((k) => (
                        <option key={k} value={k} disabled={k === teamACode}>
                          {catalog.teams[k]?.teamName || k} ({k})
                        </option>
                      ))}
                    </select>
                    <div className="flex items-center gap-2 mt-1.5 text-xs text-slate-400">
                      <span>Wins: <strong className="text-white font-mono">{teamB?.regularWins}</strong></span>
                      <span>•</span>
                      <span>Playoff Net: <strong className="text-sky-400 font-mono">+{teamB?.playoffNetRtg}</strong></span>
                    </div>
                  </div>
                </div>
              </div>
            </div>
          </div>

          {result && (
            <>
              {/* Stat Highlights Bar */}
              <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
                <div className="bg-surface-raised/80 border border-slate-800 rounded-xl p-4 shadow">
                  <span className="text-[10px] font-mono uppercase tracking-wider text-slate-400 block font-bold">
                    Fair Series Moneyline
                  </span>
                  <div className="flex items-center justify-between mt-1">
                    <span className="font-mono text-lg font-black text-amber-400">
                      {result.fairMlA > 0 ? `+${result.fairMlA}` : result.fairMlA}
                    </span>
                    <span className="text-xs text-slate-500">vs</span>
                    <span className="font-mono text-lg font-black text-sky-400">
                      {result.fairMlB > 0 ? `+${result.fairMlB}` : result.fairMlB}
                    </span>
                  </div>
                  <span className="text-[10px] text-slate-500 mt-1 block">Zero-vig implied probability</span>
                </div>

                <div className="bg-surface-raised/80 border border-slate-800 rounded-xl p-4 shadow">
                  <span className="text-[10px] font-mono uppercase tracking-wider text-slate-400 block font-bold">
                    Expected Series Length
                  </span>
                  <span className="font-mono text-2xl font-black text-white mt-1 block">
                    {result.avgGames} Games
                  </span>
                  <span className="text-[10px] text-slate-500 mt-0.5 block">
                    {FORMAT_CONFIGS[format].roundName} ({format.toUpperCase()})
                  </span>
                </div>

                <div className="bg-surface-raised/80 border border-slate-800 rounded-xl p-4 shadow">
                  <span className="text-[10px] font-mono uppercase tracking-wider text-slate-400 block font-bold">
                    Series Sweep Probability
                  </span>
                  <span className="font-mono text-2xl font-black text-indigo-400 mt-1 block">
                    {result.sweepProb}%
                  </span>
                  <span className="text-[10px] text-slate-500 mt-0.5 block">
                    {FORMAT_CONFIGS[format].winThreshold}-0 outcome likelihood
                  </span>
                </div>

                <div className="bg-surface-raised/80 border border-slate-800 rounded-xl p-4 shadow">
                  <span className="text-[10px] font-mono uppercase tracking-wider text-slate-400 block font-bold">
                    Net Rating Margin
                  </span>
                  <span className="font-mono text-2xl font-black text-emerald-400 mt-1 block">
                    {result.netRatingMargin > 0 ? `+${result.netRatingMargin}` : result.netRatingMargin}
                  </span>
                  <span className="text-[10px] text-slate-500 mt-0.5 block">
                    Raw {result.ratingDiffRaw > 0 ? `+${result.ratingDiffRaw}` : result.ratingDiffRaw} / Mismatch {result.tacticalMismatchAdjustment > 0 ? `+${result.tacticalMismatchAdjustment}` : result.tacticalMismatchAdjustment}
                  </span>
                </div>
              </div>

              {/* Main Simulation Visuals: Prob Ring + Tactical Radar */}
              <div className="grid grid-cols-1 lg:grid-cols-12 gap-8 items-start">
                {/* Left: Prob Ring & Exact Scoreline Breakdown */}
                <div className="lg:col-span-5 bg-surface-raised/80 border border-slate-800 rounded-2xl p-6 shadow-lg space-y-6">
                  <div className="text-center">
                    <h3 className="text-sm font-bold text-white tracking-tight">
                      Monte Carlo Series Win Probabilities
                    </h3>
                    <p className="text-xs text-slate-400 mt-0.5">
                      Empirical normal CDF distribution with WNBA home margin variance (σ=14.0)
                    </p>
                  </div>

                  <SeriesProbRing
                    teamA={result.teamA}
                    teamB={result.teamB}
                    winProbA={result.winProbA}
                    winProbB={result.winProbB}
                    avgGames={result.avgGames}
                    gameDistributions={result.gameDistributions}
                    fairMlA={result.fairMlA}
                    fairMlB={result.fairMlB}
                  />

                  {/* Scoreline Distribution Table */}
                  <div className="pt-4 border-t border-slate-800/80 space-y-2">
                    <div className="flex items-center justify-between text-xs font-bold text-slate-300">
                      <span>Exact Outcome Probabilities</span>
                      <span className="font-mono text-[10px] text-slate-500">10,000 Sims</span>
                    </div>

                    <div className="grid grid-cols-2 gap-2 text-xs">
                      {/* Team A Outcomes */}
                      <div className="space-y-1.5 bg-surface/60 p-2.5 rounded-lg border border-slate-800/80">
                        <span className="font-bold text-amber-400 text-[11px] block">{result.teamA} Wins</span>
                        {result.gameDistributions
                          .filter((d) => d.winner === result.teamA)
                          .map((d) => (
                            <div key={`a_${d.games}`} className="flex items-center justify-between font-mono text-[11px]">
                              <span className="text-slate-400">in {d.games} games</span>
                              <span className="font-bold text-slate-200">{d.probPct}%</span>
                            </div>
                          ))}
                      </div>

                      {/* Team B Outcomes */}
                      <div className="space-y-1.5 bg-surface/60 p-2.5 rounded-lg border border-slate-800/80">
                        <span className="font-bold text-sky-400 text-[11px] block">{result.teamB} Wins</span>
                        {result.gameDistributions
                          .filter((d) => d.winner === result.teamB)
                          .map((d) => (
                            <div key={`b_${d.games}`} className="flex items-center justify-between font-mono text-[11px]">
                              <span className="text-slate-400">in {d.games} games</span>
                              <span className="font-bold text-slate-200">{d.probPct}%</span>
                            </div>
                          ))}
                      </div>
                    </div>
                  </div>
                </div>

                {/* Right: Tactical Mismatch Radar */}
                <div className="lg:col-span-7 space-y-6">
                  {teamA && teamB && (
                    <TacticalMismatchRadar
                      teamA={result.teamA}
                      teamB={result.teamB}
                      ratingsA={teamA.tacticalRatings}
                      ratingsB={teamB.tacticalRatings}
                      tacticalEdges={result.tacticalEdges}
                    />
                  )}
                </div>
              </div>

              {/* 8-Man Playoff Rotation Shortening Breakdown */}
              <div className="bg-surface-raised/80 border border-slate-800 rounded-2xl p-6 shadow-xl space-y-4">
                <div className="flex flex-col sm:flex-row sm:items-center justify-between pb-3 border-b border-slate-800 gap-2">
                  <div>
                    <h3 className="text-base font-bold text-white tracking-tight flex items-center gap-2">
                      <ShieldCheck className="w-4 h-4 text-emerald-400" />
                      <span>Postseason Rotation Contraction (8-Man Model)</span>
                    </h3>
                    <p className="text-xs text-slate-400 mt-0.5">
                      WNBA regulation 40-minute scaling: benches contract to an 8-woman rotation totaling exactly 200 player-minutes.
                    </p>
                  </div>
                  <div className="text-[11px] font-mono text-slate-400">
                    Talent Leverage: <strong className="text-amber-400">+{teamA?.top3TalentBump}</strong> ({teamACode}) vs <strong className="text-sky-400">+{teamB?.top3TalentBump}</strong> ({teamBCode})
                  </div>
                </div>

                <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
                  {/* Team A Rotation */}
                  <div className="space-y-3">
                    <div className="flex items-center gap-2 text-xs font-bold text-amber-400">
                      <TeamLogo team={teamACode} size="xs" />
                      <span>{teamA?.teamName} Playoff Rotation</span>
                    </div>

                    <div className="overflow-x-auto border border-slate-800 rounded-lg">
                      <table className="w-full text-left text-xs font-mono">
                        <thead className="bg-surface text-slate-400 border-b border-slate-800">
                          <tr>
                            <th className="px-3 py-2">Player</th>
                            <th className="px-2 py-2">Pos</th>
                            <th className="px-2 py-2 text-right">Reg MPG</th>
                            <th className="px-2 py-2 text-right text-amber-400 font-bold">Playoff MPG</th>
                            <th className="px-2 py-2 text-right">PTS</th>
                            <th className="px-2 py-2 text-right">REB</th>
                            <th className="px-2 py-2 text-right">AST</th>
                            <th className="px-2 py-2 text-center">Role</th>
                          </tr>
                        </thead>
                        <tbody className="divide-y divide-slate-800/60 bg-surface-raised/60">
                          {teamA?.rotation.map((p, idx) => (
                            <tr key={idx} className="hover:bg-slate-800/40">
                              <td className="px-3 py-2 font-semibold text-slate-200 truncate max-w-[120px]">
                                {p.playerName}
                              </td>
                              <td className="px-2 py-2 text-slate-400">{p.position}</td>
                              <td className="px-2 py-2 text-right text-slate-400">{p.regularMpg}</td>
                              <td className="px-2 py-2 text-right text-amber-400 font-bold">{p.playoffMpg}</td>
                              <td className="px-2 py-2 text-right text-slate-300">{p.pts}</td>
                              <td className="px-2 py-2 text-right text-slate-300">{p.reb}</td>
                              <td className="px-2 py-2 text-right text-slate-300">{p.ast}</td>
                              <td className="px-2 py-2 text-center">
                                <span
                                  className={`text-[9px] px-1.5 py-0.5 rounded font-sans font-bold ${
                                    p.role === 'Starter'
                                      ? 'bg-amber-500/20 text-amber-300 border border-amber-500/30'
                                      : p.role === 'Sixth Man'
                                      ? 'bg-indigo-500/20 text-indigo-300 border border-indigo-500/30'
                                      : 'bg-slate-800 text-slate-400'
                                  }`}
                                >
                                  {p.role}
                                </span>
                              </td>
                            </tr>
                          ))}
                        </tbody>
                      </table>
                    </div>
                  </div>

                  {/* Team B Rotation */}
                  <div className="space-y-3">
                    <div className="flex items-center gap-2 text-xs font-bold text-sky-400">
                      <TeamLogo team={teamBCode} size="xs" />
                      <span>{teamB?.teamName} Playoff Rotation</span>
                    </div>

                    <div className="overflow-x-auto border border-slate-800 rounded-lg">
                      <table className="w-full text-left text-xs font-mono">
                        <thead className="bg-surface text-slate-400 border-b border-slate-800">
                          <tr>
                            <th className="px-3 py-2">Player</th>
                            <th className="px-2 py-2">Pos</th>
                            <th className="px-2 py-2 text-right">Reg MPG</th>
                            <th className="px-2 py-2 text-right text-sky-400 font-bold">Playoff MPG</th>
                            <th className="px-2 py-2 text-right">PTS</th>
                            <th className="px-2 py-2 text-right">REB</th>
                            <th className="px-2 py-2 text-right">AST</th>
                            <th className="px-2 py-2 text-center">Role</th>
                          </tr>
                        </thead>
                        <tbody className="divide-y divide-slate-800/60 bg-surface-raised/60">
                          {teamB?.rotation.map((p, idx) => (
                            <tr key={idx} className="hover:bg-slate-800/40">
                              <td className="px-3 py-2 font-semibold text-slate-200 truncate max-w-[120px]">
                                {p.playerName}
                              </td>
                              <td className="px-2 py-2 text-slate-400">{p.position}</td>
                              <td className="px-2 py-2 text-right text-slate-400">{p.regularMpg}</td>
                              <td className="px-2 py-2 text-right text-sky-400 font-bold">{p.playoffMpg}</td>
                              <td className="px-2 py-2 text-right text-slate-300">{p.pts}</td>
                              <td className="px-2 py-2 text-right text-slate-300">{p.reb}</td>
                              <td className="px-2 py-2 text-right text-slate-300">{p.ast}</td>
                              <td className="px-2 py-2 text-center">
                                <span
                                  className={`text-[9px] px-1.5 py-0.5 rounded font-sans font-bold ${
                                    p.role === 'Starter'
                                      ? 'bg-sky-500/20 text-sky-300 border border-sky-500/30'
                                      : p.role === 'Sixth Man'
                                      ? 'bg-indigo-500/20 text-indigo-300 border border-indigo-500/30'
                                      : 'bg-slate-800 text-slate-400'
                                  }`}
                                >
                                  {p.role}
                                </span>
                              </td>
                            </tr>
                          ))}
                        </tbody>
                      </table>
                    </div>
                  </div>
                </div>
              </div>
            </>
          )}
        </>
      ) : (
        /* Historical Postseason Brackets Tab */
        <div className="space-y-6">
          <div className="flex flex-col sm:flex-row sm:items-center justify-between pb-4 border-b border-slate-800 gap-4">
            <div>
              <h2 className="text-lg font-bold text-white tracking-tight flex items-center gap-2">
                <History className="w-5 h-5 text-amber-400" />
                <span>Historical Postseason Series Archive</span>
              </h2>
              <p className="text-xs text-slate-400 mt-0.5">
                Real playoff series outcomes and game-by-game scores from 2022 to 2025.
              </p>
            </div>

            {/* Year Selector */}
            <div className="flex items-center gap-1.5 bg-surface-raised border border-slate-800 p-1 rounded-lg">
              {bracketYears.map((yr) => (
                <button
                  key={yr}
                  onClick={() => setSelectedYear(yr)}
                  className={`px-3 py-1.5 rounded-md text-xs font-mono font-bold transition-all ${
                    selectedYear === yr
                      ? 'bg-accent-600 text-white shadow'
                      : 'text-slate-400 hover:text-white hover:bg-slate-800'
                  }`}
                >
                  {yr}
                </button>
              ))}
            </div>
          </div>

          {/* Series Cards */}
          <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
            {(catalog.historicalBrackets?.[selectedYear] || []).map((series, idx) => {
              const isExpanded = !!expandedSeries[idx];
              const isWinnerA = series.winner === series.teamA;

              return (
                <div
                  key={idx}
                  className="bg-surface-raised/90 border border-slate-800 hover:border-slate-700 rounded-xl p-5 shadow-lg space-y-4 transition-all"
                >
                  <div className="flex items-center justify-between text-xs">
                    <span className="font-mono font-bold px-2 py-0.5 rounded bg-slate-800 text-amber-400">
                      {series.round}
                    </span>
                    <span className="text-slate-500 font-mono text-[11px]">
                      {series.gamesPlayed} of {series.seriesLength} Games
                    </span>
                  </div>

                  {/* Team A vs Team B Row */}
                  <div className="grid grid-cols-12 items-center gap-2 py-2">
                    {/* Team A */}
                    <div className={`col-span-5 flex items-center gap-2 ${isWinnerA ? 'text-white' : 'text-slate-400'}`}>
                      <TeamLogo team={series.teamA} size="md" />
                      <div className="truncate">
                        <span className="text-sm font-bold block truncate">{series.teamNameA}</span>
                        <span className="text-[10px] font-mono text-slate-500">{series.teamA}</span>
                      </div>
                    </div>

                    {/* Result Center */}
                    <div className="col-span-2 text-center">
                      <span className="text-xs font-bold text-slate-500 block uppercase">VS</span>
                    </div>

                    {/* Team B */}
                    <div className={`col-span-5 flex items-center gap-2 justify-end text-right ${!isWinnerA ? 'text-white' : 'text-slate-400'}`}>
                      <div className="truncate">
                        <span className="text-sm font-bold block truncate">{series.teamNameB}</span>
                        <span className="text-[10px] font-mono text-slate-500">{series.teamB}</span>
                      </div>
                      <TeamLogo team={series.teamB} size="md" />
                    </div>
                  </div>

                  {/* Winner Banner */}
                  <div className="flex items-center justify-between pt-2 border-t border-slate-800/80 text-xs">
                    <div className="flex items-center gap-1.5">
                      <Trophy className="w-3.5 h-3.5 text-amber-400" />
                      <span className="text-slate-400">Winner:</span>
                      <strong className="text-amber-400">{series.winnerName}</strong>
                    </div>

                    <button
                      onClick={() => toggleSeriesExpand(idx)}
                      className="text-xs text-slate-400 hover:text-white flex items-center gap-1 transition-colors"
                    >
                      <span>{isExpanded ? 'Hide Games' : 'Game Scores'}</span>
                      {isExpanded ? <ChevronDown className="w-3.5 h-3.5" /> : <ChevronRight className="w-3.5 h-3.5" />}
                    </button>
                  </div>

                  {/* Expandable Game Box Scores */}
                  {isExpanded && series.games && series.games.length > 0 && (
                    <div className="pt-3 border-t border-slate-800/60 space-y-2">
                      <div className="space-y-1.5">
                        {series.games.map((g, gIdx) => (
                          <div
                            key={gIdx}
                            className="flex items-center justify-between bg-surface px-3 py-1.5 rounded-lg border border-slate-800/60 text-xs font-mono"
                          >
                            <span className="text-slate-500 text-[10px]">Game {gIdx + 1} ({g.gameDate})</span>
                            <div className="flex items-center gap-3">
                              <span className={g.scoreA > g.scoreB ? 'text-amber-400 font-bold' : 'text-slate-400'}>
                                {g.teamA} {g.scoreA}
                              </span>
                              <span className="text-slate-600">-</span>
                              <span className={g.scoreB > g.scoreA ? 'text-sky-400 font-bold' : 'text-slate-400'}>
                                {g.teamB} {g.scoreB}
                              </span>
                            </div>
                          </div>
                        ))}
                      </div>
                    </div>
                  )}
                </div>
              );
            })}
          </div>
        </div>
      )}
    </div>
  );
};
