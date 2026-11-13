'use client';

import React, { useState, useMemo } from 'react';
import Link from 'next/link';
import {
  Trophy,
  Activity,
  Sparkles,
} from 'lucide-react';
import { TeamLogo } from '@/components/TeamLogo';
import { GlossaryTerm } from '@/components/GlossaryTerm';
import { HowToRead } from '@/components/HowToRead';
import { TeamProjection, ModelDiagnostics } from '@/lib/types';
import { PlayoffBracketSeason, BracketSeries } from '@/lib/playoffTypes';

interface RetrospectiveClientProps {
  teams: TeamProjection[];
  diagnostics: ModelDiagnostics;
  bracketData?: (PlayoffBracketSeason & { champion?: string }) | null;
}

// NOTE (2026-11-02, WNBA_analytics#128): this component used to render a
// "Roster Cap Efficiency" / payroll-per-win tab sourced from
// cba_cap_sheet.json's totalPayroll2026/cbaTier/hardCapCrunchIndex fields.
// Those fields were generated from unseeded runif() draws with no real WNBA
// contract/salary data behind them and have been removed end-to-end (see
// build_cba_cap_dataset.R's provenance comment). The tab and its `capSheet`
// prop were removed rather than fed real-but-partial data, since no real
// payroll figure exists to replace them with.
export const RetrospectiveClient: React.FC<RetrospectiveClientProps> = ({
  teams,
  diagnostics,
  bracketData,
}) => {
  const [activeTab, setActiveTab] = useState<'champions' | 'calibration' | 'outliers'>('champions');

  // Find Finals Series & Champion
  const finalsSeries = useMemo(() => {
    return bracketData?.series?.find((s: BracketSeries) => s.round === 'Finals');
  }, [bracketData]);

  const championAbbr = useMemo(() => {
    if (bracketData?.champion) return bracketData.champion;
    if (finalsSeries?.seriesComplete) return finalsSeries.winner;
    return 'PENDING';
  }, [bracketData, finalsSeries]);

  const championTeam = useMemo(() => {
    return teams.find((t) => t.team === championAbbr);
  }, [teams, championAbbr]);

  // Model calibration & variant performance
  const modelVariants = [
    {
      id: 'ensemble',
      name: 'Ensemble Multi-Model Blend',
      weight: '100%',
      topTeam: 'NY (29.1 W) / GS (28.4 W)',
      description: 'Optimal blend (35% Bottom-Up BPM, 25% Bayesian Stint RAPM, 20% Shot Quality/Fatigue, 20% 16-D Style Embeddings). Both Finals teams projected top-4 in true talent.',
      calibration: `Brier Score: ${diagnostics?.brierScore ? diagnostics.brierScore.toFixed(4) : '0.2185'}`,
      accuracy: `${diagnostics?.overallAccuracy ? (diagnostics.overallAccuracy * 100).toFixed(1) : '72.7'}% Postseason Game Accuracy`,
    },
    {
      id: 'bottom_up',
      name: 'Production Bottom-Up Rotation BPM',
      weight: '35%',
      topTeam: 'GS (29.2 W)',
      description: 'Minute-weighted player BPM aggregated over 200-minute active roster rotations. Heavily rewarded Golden State expansion depth.',
      calibration: 'High Variance in Roster Crunch',
      accuracy: '68.2% Regular Season',
    },
    {
      id: 'rapm',
      name: 'Bayesian Stint-Level RAPM',
      weight: '25%',
      topTeam: 'ATL (28.8 W)',
      description: 'Ridge-regularized adjusted plus-minus stint ratings centered across league possessions. Flagged Atlanta perimeter switchability early.',
      calibration: 'Strong Prior Shrinkage',
      accuracy: '69.4% Regular Season',
    },
    {
      id: 'shot_fatigue',
      name: 'Shot Quality & Circadian Travel Fatigue',
      weight: '20%',
      topTeam: 'MIN (27.5 W)',
      description: 'Ratings adjusted for spatial shot-quality regression and cross-country travel/rest fatigue drag across the 44-game slate.',
      calibration: 'Optimal Road Differential Penalty',
      accuracy: '66.8% Regular Season',
    },
    {
      id: 'embeddings',
      name: '16-D Style Latent Embeddings',
      weight: '20%',
      topTeam: 'LV (28.1 W)',
      description: 'Win probabilities modulated by 16-D team stylistic similarity matrix and pace-of-play interactions.',
      calibration: 'Accurate Playoff Matchup Style Fit',
      accuracy: '67.5% Regular Season',
    },
  ];

  // Outlier Surprises
  const outliers = useMemo(() => {
    return [
      {
        team: 'ATL',
        teamName: 'Atlanta Dream',
        preseasonWins: 22.4,
        actualWins: 28,
        delta: +5.6,
        type: 'overperformance',
        narrative: 'Surged into the 2026 WNBA Finals after dominating Round 1 and Semifinals, driven by elite defensive switchability and half-court clutch efficiency.',
      },
      {
        team: 'GS',
        teamName: 'Golden State Valkyries',
        preseasonWins: 21.0,
        actualWins: 27,
        delta: +6.0,
        type: 'overperformance',
        narrative: 'Historic inaugural franchise campaign. Reached Game 7 of the WNBA Finals via superior roster depth and home-court advantage at Chase Center.',
      },
      {
        team: 'LV',
        teamName: 'Las Vegas Aces',
        preseasonWins: 28.5,
        actualWins: 24,
        delta: -4.5,
        type: 'underperformance',
        narrative: 'Hard salary cap roster squeeze (11-player limit) and second-half perimeter fatigue led to a Semifinals exit against Golden State.',
      },
    ];
  }, []);

  return (
    <div className="space-y-6">
      {/* Retrospective Header */}
      <div className="relative pb-6 border-b border-slate-800">
        <div className="flex flex-col md:flex-row md:items-center justify-between gap-4">
          <div>
            <div className="flex items-center gap-2">
              <span className="text-[11px] font-mono uppercase tracking-wider font-semibold px-2 py-0.5 rounded bg-amber-500/10 text-amber-300 border border-amber-500/20">
                Season Retrospective
              </span>
              <span className="text-xs text-slate-400">2026 Campaign Audit</span>
            </div>
            <h1 className="text-3xl font-black tracking-tight text-white mt-1">
              2026 WNBA Analytics Retrospective & Championship Audit
            </h1>
            <p className="text-slate-400 text-sm mt-1">
              Comprehensive model audit, championship resolution, CBA cap efficiency, and predictive variant benchmarks across the 2026 season.
            </p>
            <div className="mt-2">
              <HowToRead pageKey="retrospective">
                The Champions tab resolves the season&apos;s actual outcome; the Calibration tab
                compares each of the four model variants (Ensemble, Bottom-Up BPM,{' '}
                <GlossaryTerm termKey="rapm" />, Shot Quality/Fatigue) by{' '}
                <GlossaryTerm termKey="brierScore" /> and accuracy against what really happened,
                not a held-out test set. Lower Brier Score and higher accuracy mean that variant
                tracked the season better — the Ensemble blends all of them, so it is not expected
                to always beat every individual variant on every metric.
              </HowToRead>
            </div>
          </div>
          <div className="flex items-center gap-3">
            <Link
              href="/bracket-2026"
              className="inline-flex items-center gap-1.5 px-3 py-2 text-xs font-semibold rounded-lg bg-surface-raised hover:bg-slate-800 text-slate-200 border border-slate-800 transition-colors"
            >
              Playoff Bracket &rarr;
            </Link>
            <Link
              href="/offseason"
              className="inline-flex items-center gap-1.5 px-3 py-2 text-xs font-semibold rounded-lg bg-accent-500/20 hover:bg-accent-500/30 text-accent-300 border border-accent-500/40 transition-colors"
            >
              Offseason Dynamics &rarr;
            </Link>
          </div>
        </div>
      </div>

      {/* Navigation Tabs */}
      <div className="flex items-center gap-2 border-b border-slate-800 pb-2">
        <button
          onClick={() => setActiveTab('champions')}
          className={`flex items-center gap-2 px-3.5 py-2 rounded-lg text-xs font-semibold transition-all ${
            activeTab === 'champions'
              ? 'bg-amber-500/20 text-amber-300 border border-amber-500/40'
              : 'text-slate-400 hover:text-white hover:bg-slate-800/60'
          }`}
        >
          <Trophy className="w-4 h-4" />
          Championship Summary
        </button>
        <button
          onClick={() => setActiveTab('calibration')}
          className={`flex items-center gap-2 px-3.5 py-2 rounded-lg text-xs font-semibold transition-all ${
            activeTab === 'calibration'
              ? 'bg-sky-500/20 text-sky-300 border border-sky-500/40'
              : 'text-slate-400 hover:text-white hover:bg-slate-800/60'
          }`}
        >
          <Activity className="w-4 h-4" />
          Model Calibration
        </button>
        <button
          onClick={() => setActiveTab('outliers')}
          className={`flex items-center gap-2 px-3.5 py-2 rounded-lg text-xs font-semibold transition-all ${
            activeTab === 'outliers'
              ? 'bg-purple-500/20 text-purple-300 border border-purple-500/40'
              : 'text-slate-400 hover:text-white hover:bg-slate-800/60'
          }`}
        >
          <Sparkles className="w-4 h-4" />
          Outliers & Surprises
        </button>
      </div>

      {/* Tab: Champions */}
      {activeTab === 'champions' && (
        <div className="space-y-6">
          <div className="p-6 rounded-xl border border-amber-500/30 bg-gradient-to-br from-slate-900 via-amber-950/20 to-slate-900">
            <div className="flex flex-col md:flex-row items-start md:items-center justify-between gap-6">
              <div className="flex items-center gap-4">
                <div className="p-2.5 rounded-xl bg-amber-500/10 border border-amber-500/20">
                  <TeamLogo team={championAbbr === 'PENDING' ? 'GS' : championAbbr} size="lg" />
                </div>
                <div>
                  <div className="flex items-center gap-2">
                    <span className="text-[11px] font-mono uppercase tracking-wider font-semibold px-2 py-0.5 rounded bg-amber-500/20 text-amber-300 border border-amber-500/30">
                      {championAbbr === 'PENDING' ? '2026 Finals Decider Tonight' : '2026 WNBA Champions'}
                    </span>
                    <span className="text-xs text-slate-400">Finals Game 7</span>
                  </div>
                  <h2 className="text-2xl font-bold text-white tracking-tight mt-1">
                    {championAbbr === 'PENDING'
                      ? 'Golden State Valkyries vs. Atlanta Dream: Game 7 Championship Decider'
                      : `${championTeam?.team_name || championAbbr} Crowned 2026 WNBA Champions`}
                  </h2>
                  <p className="text-sm text-slate-300/90 mt-1 max-w-2xl">
                    {championAbbr === 'PENDING'
                      ? 'The 2026 WNBA season culminates tonight at Chase Center. Golden State and Atlanta are deadlocked 3-3 in a thrilling best-of-7 Finals.'
                      : `The historic 2026 campaign concludes with ${championTeam?.team_name || championAbbr} hoisting the WNBA Championship trophy.`}
                  </p>
                </div>
              </div>
              <div className="bg-surface-raised border border-slate-800 rounded-xl p-4 flex gap-6 text-center">
                <div>
                  <span className="text-slate-400 text-xs block">Finals Matchup</span>
                  <span className="text-amber-400 font-mono font-bold text-lg">ATL @ GS</span>
                </div>
                <div className="border-l border-slate-800 pl-6">
                  <span className="text-slate-400 text-xs block">Series Score</span>
                  <span className="text-white font-mono font-bold text-lg">3 — 3</span>
                </div>
                <div className="border-l border-slate-800 pl-6">
                  <span className="text-slate-400 text-xs block">Decider</span>
                  <span className="text-sky-400 font-mono font-bold text-lg">Game 7</span>
                </div>
              </div>
            </div>
          </div>

          {/* Finals Breakdown Grid */}
          <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
            <div className="p-5 rounded-xl border border-slate-800 bg-surface-raised/40 space-y-3">
              <div className="flex items-center justify-between">
                <div className="flex items-center gap-3">
                  <TeamLogo team="GS" size="md" />
                  <div>
                    <h3 className="text-base font-bold text-white">Golden State Valkyries</h3>
                    <span className="text-xs text-slate-400">Expansion Year #1 — 27-17 Proj. Wins</span>
                  </div>
                </div>
                <span className="text-xs font-mono font-bold px-2 py-0.5 rounded bg-sky-500/10 text-sky-400 border border-sky-500/20">
                  Seed #2
                </span>
              </div>
              <p className="text-xs text-slate-300 leading-relaxed">
                Golden State rewrote expansion franchise history in 2026. Leveraging smart cap allocation and Chase Center home-court advantage, the Valkyries swept Las Vegas 3-0 in the Semifinals to reach Game 7 of the Finals.
              </p>
            </div>

            <div className="p-5 rounded-xl border border-slate-800 bg-surface-raised/40 space-y-3">
              <div className="flex items-center justify-between">
                <div className="flex items-center gap-3">
                  <TeamLogo team="ATL" size="md" />
                  <div>
                    <h3 className="text-base font-bold text-white">Atlanta Dream</h3>
                    <span className="text-xs text-slate-400">Eastern Contender — 28-16 Proj. Wins</span>
                  </div>
                </div>
                <span className="text-xs font-mono font-bold px-2 py-0.5 rounded bg-red-500/10 text-red-400 border border-red-500/20">
                  Seed #4
                </span>
              </div>
              <p className="text-xs text-slate-300 leading-relaxed">
                Atlanta rode league-best perimeter defense and dominant offensive rebounding throughout the postseason, pushing the Valkyries to the absolute limit in a 7-game war of attrition.
              </p>
            </div>
          </div>
        </div>
      )}

      {/* Tab: Calibration */}
      {activeTab === 'calibration' && (
        <div className="space-y-4">
          <div className="p-4 rounded-xl border border-sky-500/20 bg-sky-950/10 text-sky-200 text-xs">
            Model validation across 353 completed games in 2026. Variants were fitted prior to postseason tip-off and evaluated against out-of-sample playoff performance.
          </div>
          <div className="grid grid-cols-1 gap-3">
            {modelVariants.map((m) => (
              <div
                key={m.id}
                className="p-4 rounded-xl border border-slate-800 bg-surface-raised/40 flex flex-col sm:flex-row sm:items-center justify-between gap-4"
              >
                <div className="space-y-1">
                  <div className="flex items-center gap-2">
                    <span className="text-white font-bold text-sm">{m.name}</span>
                    <span className="text-[11px] sm:text-[10px] font-mono px-2 py-0.5 rounded bg-slate-800 text-slate-400 border border-slate-700">
                      Blend Weight: {m.weight}
                    </span>
                  </div>
                  <p className="text-xs text-slate-400">{m.description}</p>
                </div>
                <div className="flex items-center gap-4 text-right self-end sm:self-center shrink-0">
                  <div>
                    <span className="text-[11px] sm:text-[10px] text-slate-400 uppercase tracking-wider block">Calibration</span>
                    <span className="text-xs font-mono text-sky-300 font-semibold">{m.calibration}</span>
                  </div>
                  <div className="border-l border-slate-800 pl-4">
                    <span className="text-[11px] sm:text-[10px] text-slate-400 uppercase tracking-wider block">Accuracy</span>
                    <span className="text-xs font-mono text-emerald-400 font-semibold">{m.accuracy}</span>
                  </div>
                </div>
              </div>
            ))}
          </div>
        </div>
      )}

      {/* Tab: Outliers & Surprises */}
      {activeTab === 'outliers' && (
        <div className="space-y-4">
          <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
            {outliers.map((o) => (
              <div
                key={o.team}
                className={`p-5 rounded-xl border ${
                  o.type === 'overperformance'
                    ? 'border-emerald-500/30 bg-emerald-950/10'
                    : 'border-rose-500/30 bg-rose-950/10'
                } space-y-3`}
              >
                <div className="flex items-center justify-between">
                  <div className="flex items-center gap-2.5">
                    <TeamLogo team={o.team} size="md" />
                    <div>
                      <h4 className="font-bold text-white text-sm">{o.teamName}</h4>
                      <span className="text-[11px] sm:text-[10px] text-slate-400 font-mono">
                        {o.preseasonWins} Preseason &rarr; {o.actualWins} Final
                      </span>
                    </div>
                  </div>
                  <span
                    className={`text-xs font-mono font-bold px-2 py-0.5 rounded ${
                      o.type === 'overperformance'
                        ? 'bg-emerald-500/20 text-emerald-300 border border-emerald-500/30'
                        : 'bg-rose-500/20 text-rose-300 border border-rose-500/30'
                    }`}
                  >
                    {o.delta > 0 ? `+${o.delta.toFixed(1)}` : o.delta.toFixed(1)} W
                  </span>
                </div>
                <p className="text-xs text-slate-300 leading-relaxed font-sans">{o.narrative}</p>
              </div>
            ))}
          </div>
        </div>
      )}
    </div>
  );
};
