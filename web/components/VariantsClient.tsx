'use client';

import React, { useState, useMemo } from 'react';
import { TeamProjection, ModelMetadata } from '@/lib/types';
import { GitCompare, CheckCircle2, Layers, Download } from 'lucide-react';
import { TeamLogo } from '@/components/TeamLogo';
import { BrierScoreComparison } from '@/components/BrierScoreComparison';
import { exportToCsv } from '@/lib/exportToCsv';

interface VariantsClientProps {
  teams: TeamProjection[];
  metadata?: ModelMetadata;
}

type VariantKey =
  | 'ensemble'
  | 'variant_bottom_up'
  | 'variant_rapm'
  | 'variant_shot_fatigue'
  | 'variant_embeddings';

export const VariantsClient: React.FC<VariantsClientProps> = ({ teams }) => {
  const [activeVariant, setActiveVariant] = useState<VariantKey>('ensemble');
  const [divergenceSort, setDivergenceSort] = useState<'divergence' | 'alpha' | 'wins'>(
    'divergence'
  );

  const variantDetails: Record<
    VariantKey,
    {
      id: VariantKey;
      name: string;
      weightBadge: string;
      description: string;
      strengths: string[];
      methodology: string;
    }
  > = {
    ensemble: {
      id: 'ensemble',
      name: 'Multi-Model Sabermetric Blend',
      weightBadge: 'Combined 100%',
      description:
        'Optimal linear blend aggregating 4-Factor Starting-Pitcher Elo (35%), Hierarchical Empirical Bayes Talent (25%), Pythagenpat Run-Expectation (20%), and Marcel + Bullpen Fatigue (20%).',
      strengths: [
        'Balances game-level starting pitcher quality with park-neutralized true roster talent',
        'Strips out one-run sequencing luck while accounting for multi-year Marcel aging curves',
        'Lowest walk-forward Brier score (0.2438) and log-loss across 2,430 MLB regular-season games',
      ],
      methodology:
        'Synthesizes all four sabermetric engines into true-talent team win probabilities, simulated across 1,000 independent 162-game schedules and 10,000 postseason brackets.',
    },
    variant_bottom_up: {
      id: 'variant_bottom_up',
      name: '4-Factor Starting-Pitcher Elo',
      weightBadge: 'Weight 35%',
      description:
        'Dynamic team Elo rating adjusted for Home Field Advantage (+14.9 Elo), travel/rest, and Tangotiger rolling Starting Pitcher Game Score (4.7 × ΔrGS).',
      strengths: [
        'Directly captures ace vs. #5 starter rotation matchup swings in daily & series play',
        'Empirically derived constants across 2,432 games (tools/derive_mlb_constants.R)',
        'Adapts rapidly to in-season rotation call-ups, trades, and breakouts',
      ],
      methodology:
        'Computes pre-game adjusted Elo from base team rating plus 4.7 Elo points per starter rGS point above team rotation average.',
    },
    variant_rapm: {
      id: 'variant_rapm',
      name: 'Hierarchical Empirical Bayes Talent',
      weightBadge: 'Weight 25%',
      description:
        'Closed-form empirical Bayes partial pooling (Beta-Binomial for rates, Normal-Normal for continuous metrics) across all 630 batters and 649 pitchers.',
      strengths: [
        'Neutralizes 30-venue FanGraphs park factors before computing posterior talent',
        'Sample-size adaptive shrinkage (B_i = σ²_i / (σ²_i + τ²)) prevents small-PA outlier distortion',
        'Aggregates pooled batter wOBA/ISO and pitcher xFIP/K%/BB% into net team talent z-scores',
      ],
      methodology:
        'Solves closed-form method-of-moments prior hyperparameters per stat and pools individual players toward league mean proportional to PA/IP.',
    },
    variant_shot_fatigue: {
      id: 'variant_shot_fatigue',
      name: 'Pythagenpat Run-Expectation',
      weightBadge: 'Weight 20%',
      description:
        'David Smyth’s variable-exponent run differential baseline ((RS + RA)/G)^0.287 isolating underlying scoring margin from cluster luck.',
      strengths: [
        'Accounts for dynamic run-scoring environments via variable exponent γ ≈ 1.79–1.91',
        'Identifies teams overperforming or underperforming their run differential in 1-run games',
        'Provides a rock-solid macro anchor free from player-level roster join noise',
      ],
      methodology:
        'Computes Pythagenpat expected win percentage from runs scored and runs allowed per game, regressed toward .500 for out-of-sample projection.',
    },
    variant_embeddings: {
      id: 'variant_embeddings',
      name: 'Marcel 3-Yr & Bullpen Fatigue',
      weightBadge: 'Weight 20%',
      description:
        'Tom Tango’s 3-year 5/4/3 weighted player projections with age curves combined with relief-pitcher workload & velocity decline diagnostics.',
      strengths: [
        'Incorporates multi-year track record (5/4/3 weights) and piecewise age adjustments (±0.6%/yr)',
        'Penalizes clubs with overtaxed high-leverage bullpens and back-to-back reliever usage',
        'Captures late-inning bullpen vulnerability in tight division races',
      ],
      methodology:
        'Combines playing-time-weighted Marcel OBP/ERA projections with team bullpen vulnerability scores from mlb_bullpen_fatigue.R.',
    },
  };

  // Compute divergence/disagreement metrics for each team across the 4 MLB variants
  const teamsWithDivergence = useMemo(() => {
    return teams.map((t) => {
      const elo = t.variant_bottom_up_mean_wins;
      const bayes = t.variant_rapm_mean_wins;
      const pyth = t.variant_shot_fatigue_mean_wins;
      const marcel = t.variant_embeddings_mean_wins;
      const values = [elo, bayes, pyth, marcel];
      const minVal = Math.min(...values);
      const maxVal = Math.max(...values);
      const spread = maxVal - minVal;
      const variance =
        values.reduce((acc, v) => acc + Math.pow(v - t.ensemble_mean_wins, 2), 0) / 4;
      const divergenceStd = Math.sqrt(variance);

      const modelScores = [
        { model: 'Pitcher Elo', wins: elo },
        { model: 'Empirical Bayes', wins: bayes },
        { model: 'Pythagenpat', wins: pyth },
        { model: 'Marcel + Bullpen', wins: marcel },
      ];
      modelScores.sort((a, b) => b.wins - a.wins);

      return {
        ...t,
        spread,
        divergenceStd,
        highestModel: modelScores[0],
        lowestModel: modelScores[3],
        variantWins: {
          ensemble: t.ensemble_mean_wins,
          variant_bottom_up: elo,
          variant_rapm: bayes,
          variant_shot_fatigue: pyth,
          variant_embeddings: marcel,
        },
        variantPlayoffs: {
          ensemble: t.ensemble_playoff_prob,
          variant_bottom_up: t.variant_bottom_up_playoff_prob,
          variant_rapm: t.variant_rapm_playoff_prob,
          variant_shot_fatigue: t.variant_shot_fatigue_playoff_prob,
          variant_embeddings: t.variant_embeddings_playoff_prob,
        },
        variantTitle: {
          ensemble: t.ensemble_title_prob,
          variant_bottom_up: t.variant_bottom_up_title_prob,
          variant_rapm: t.variant_rapm_title_prob,
          variant_shot_fatigue: t.variant_shot_fatigue_title_prob,
          variant_embeddings: t.variant_embeddings_title_prob,
        },
      };
    });
  }, [teams]);

  const sortedDivergenceTeams = useMemo(() => {
    return [...teamsWithDivergence].sort((a, b) => {
      if (divergenceSort === 'divergence') return b.spread - a.spread;
      if (divergenceSort === 'alpha') return a.team.localeCompare(b.team);
      return b.ensemble_mean_wins - a.ensemble_mean_wins;
    });
  }, [teamsWithDivergence, divergenceSort]);

  const currentVariantInfo = variantDetails[activeVariant];

  const handleExportCsv = () => {
    exportToCsv(
      sortedDivergenceTeams as unknown as Record<string, unknown>[],
      [
        { key: 'team_name', label: 'Franchise' },
        { key: 'league', label: 'League' },
        { key: 'ensemble_mean_wins', label: 'Ensemble Wins' },
        { key: 'variant_bottom_up_mean_wins', label: 'Pitcher Elo (35%)' },
        { key: 'variant_rapm_mean_wins', label: 'Emp. Bayes (25%)' },
        { key: 'variant_shot_fatigue_mean_wins', label: 'Pythagenpat (20%)' },
        { key: 'variant_embeddings_mean_wins', label: 'Marcel+BP (20%)' },
        { key: 'spread', label: 'Max Spread (Delta W)' },
      ],
      'model-divergence-matrix'
    );
  };

  return (
    <div className="space-y-6">
      {/* Variant Selector Tabs */}
      <div className="flex flex-wrap items-center gap-2 border-b border-slate-800 pb-3">
        {(Object.keys(variantDetails) as VariantKey[]).map((key) => {
          const detail = variantDetails[key];
          const isActive = activeVariant === key;
          return (
            <button
              key={key}
              onClick={() => setActiveVariant(key)}
              className={`flex items-center gap-2 px-4 py-2.5 rounded-lg text-sm font-semibold transition-all ${
                isActive
                  ? 'bg-accent-600 text-white shadow-lg shadow-accent-600/30'
                  : 'bg-surface-raised text-slate-300 hover:text-white hover:bg-slate-800 border border-slate-800'
              }`}
            >
              <span>{detail.name}</span>
              <span
                className={`text-[11px] px-2 py-0.5 rounded-full font-mono ${
                  isActive ? 'bg-white/20 text-white' : 'bg-slate-800 text-slate-400'
                }`}
              >
                {detail.weightBadge}
              </span>
            </button>
          );
        })}
      </div>

      {/* Selected Variant Explainer Card */}
      <div className="bg-surface-raised/80 border border-slate-800 rounded-xl p-6 space-y-4 shadow-lg">
        <div className="flex flex-col md:flex-row md:items-center justify-between gap-2 border-b border-slate-800/80 pb-4">
          <div>
            <div className="flex items-center gap-2.5">
              <Layers className="w-5 h-5 text-indigo-400" />
              <h2 className="text-xl font-bold text-white">{currentVariantInfo.name}</h2>
              <span className="text-xs font-mono px-2.5 py-0.5 rounded-full bg-indigo-500/15 text-indigo-300 border border-indigo-500/30 font-semibold">
                {currentVariantInfo.weightBadge}
              </span>
            </div>
            <p className="text-sm text-slate-300 mt-1.5">{currentVariantInfo.description}</p>
          </div>
        </div>

        <div className="grid grid-cols-1 md:grid-cols-2 gap-6 pt-1">
          <div className="space-y-2">
            <h3 className="text-xs font-bold uppercase tracking-wider text-amber-400">
              Key Modeling Strengths
            </h3>
            <ul className="space-y-1.5">
              {currentVariantInfo.strengths.map((s, idx) => (
                <li key={idx} className="flex items-start gap-2 text-xs text-slate-300">
                  <CheckCircle2 className="w-4 h-4 text-emerald-400 flex-shrink-0 mt-0.5" />
                  <span>{s}</span>
                </li>
              ))}
            </ul>
          </div>
          <div className="space-y-2">
            <h3 className="text-xs font-bold uppercase tracking-wider text-sky-400">
              Mathematical Specification
            </h3>
            <p className="text-xs text-slate-300 leading-relaxed bg-surface/70 p-3.5 rounded-lg border border-slate-800 font-mono">
              {currentVariantInfo.methodology}
            </p>
          </div>
        </div>
      </div>

      {/* Walk-Forward Brier Score Comparison */}
      <BrierScoreComparison />

      {/* 30-Team Model Divergence Matrix */}
      <div className="bg-surface-raised/80 border border-slate-800 rounded-xl overflow-hidden shadow-xl">
        <div className="p-5 bg-surface/70 border-b border-slate-800 flex flex-col sm:flex-row sm:items-center justify-between gap-4">
          <div>
            <h3 className="text-base font-bold text-white flex items-center gap-2">
              <GitCompare className="w-5 h-5 text-indigo-400" />
              <span>30-Franchise Model Divergence Matrix (162-Game Wins)</span>
            </h3>
            <p className="text-xs text-slate-400 mt-0.5">
              Quantifying where Pitcher Elo, Empirical Bayes, Pythagenpat, and Marcel/Bullpen disagree most strongly.
            </p>
          </div>

          <div className="flex items-center gap-2 text-xs">
            <button
              type="button"
              onClick={handleExportCsv}
              title="Export CSV"
              aria-label="Export table as CSV"
              data-export-exclude
              className="p-1.5 rounded-lg border border-slate-800 text-slate-400 hover:text-white hover:border-slate-600 transition-colors"
            >
              <Download className="w-3.5 h-3.5" />
            </button>
            <span className="text-slate-400 font-medium">Sort Matrix:</span>
            <div className="inline-flex rounded-lg bg-surface-raised p-1 border border-slate-800">
              {(
                [
                  { id: 'divergence', label: 'Max Spread (ΔW)' },
                  { id: 'wins', label: 'Ensemble Wins' },
                  { id: 'alpha', label: 'Team A-Z' },
                ] as const
              ).map((opt) => (
                <button
                  key={opt.id}
                  onClick={() => setDivergenceSort(opt.id)}
                  className={`px-2.5 py-1 rounded-md font-semibold transition-all ${
                    divergenceSort === opt.id
                      ? 'bg-accent-600 text-white shadow-sm'
                      : 'text-slate-400 hover:text-white'
                  }`}
                >
                  {opt.label}
                </button>
              ))}
            </div>
          </div>
        </div>

        <div className="overflow-x-auto">
          <table className="w-full text-left border-collapse">
            <thead>
              <tr className="border-b border-slate-800 bg-surface/90 text-[11px] font-bold uppercase tracking-wider text-slate-400">
                <th className="py-3.5 px-4">Franchise</th>
                <th className="py-3.5 px-3 text-right text-indigo-300">Ensemble</th>
                <th className="py-3.5 px-3 text-right">Pitcher Elo (35%)</th>
                <th className="py-3.5 px-3 text-right">Emp. Bayes (25%)</th>
                <th className="py-3.5 px-3 text-right">Pythagenpat (20%)</th>
                <th className="py-3.5 px-3 text-right">Marcel+BP (20%)</th>
                <th className="py-3.5 px-3 text-right">Max Spread (ΔW)</th>
                <th className="py-3.5 px-4">Highest / Lowest Engine</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-slate-800/60 text-sm">
              {sortedDivergenceTeams.map((t) => (
                <tr key={t.team} className="hover:bg-slate-800/40 transition-colors">
                  <td className="py-3 px-4">
                    <div className="flex items-center gap-2.5">
                      <TeamLogo team={t.team} size="sm" />
                      <div>
                        <span className="font-bold text-white">{t.team_name}</span>
                        <span className="text-[10px] font-mono text-slate-400 ml-1.5">
                          ({t.league})
                        </span>
                      </div>
                    </div>
                  </td>
                  <td className="py-3 px-3 text-right font-mono font-bold text-indigo-300 bg-indigo-950/20">
                    {t.ensemble_mean_wins.toFixed(1)}W
                  </td>
                  <td className="py-3 px-3 text-right font-mono text-slate-200">
                    {t.variant_bottom_up_mean_wins.toFixed(1)}
                  </td>
                  <td className="py-3 px-3 text-right font-mono text-slate-200">
                    {t.variant_rapm_mean_wins.toFixed(1)}
                  </td>
                  <td className="py-3 px-3 text-right font-mono text-slate-200">
                    {t.variant_shot_fatigue_mean_wins.toFixed(1)}
                  </td>
                  <td className="py-3 px-3 text-right font-mono text-slate-200">
                    {t.variant_embeddings_mean_wins.toFixed(1)}
                  </td>
                  <td className="py-3 px-3 text-right font-mono">
                    <span
                      className={`px-2 py-0.5 rounded text-xs font-bold ${
                        t.spread >= 8.0
                          ? 'bg-rose-500/20 text-rose-300 border border-rose-500/30'
                          : t.spread >= 4.5
                          ? 'bg-amber-500/20 text-amber-300 border border-amber-500/30'
                          : 'bg-slate-800 text-slate-300'
                      }`}
                    >
                      {t.spread.toFixed(1)}W
                    </span>
                  </td>
                  <td className="py-3 px-4 text-xs font-mono">
                    <div className="flex flex-wrap items-center gap-1.5">
                      <span className="px-1.5 py-0.5 rounded bg-emerald-500/15 text-emerald-400">
                        ▲ {t.highestModel.model} ({t.highestModel.wins.toFixed(0)}W)
                      </span>
                      <span className="px-1.5 py-0.5 rounded bg-rose-500/15 text-rose-400">
                        ▼ {t.lowestModel.model} ({t.lowestModel.wins.toFixed(0)}W)
                      </span>
                    </div>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </div>
    </div>
  );
};
