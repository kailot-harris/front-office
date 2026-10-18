'use client';

import React, { useState, useMemo } from 'react';
import { TeamProjection, ModelMetadata } from '@/lib/types';
import { GitCompare } from 'lucide-react';
import { TeamLogo } from '@/components/TeamLogo';
import { BrierScoreComparison } from '@/components/BrierScoreComparison';

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
  const [divergenceSort, setDivergenceSort] = useState<'divergence' | 'alpha' | 'wins'>('divergence');

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
      name: 'Multi-Model Ensemble Blend',
      weightBadge: 'Combined 100%',
      description:
        'Optimal weighted blend aggregating Production Bottom-Up (35%), Bayesian RAPM (25%), Shot-Quality Fatigue (20%), and Latent Style Embeddings (20%).',
      strengths: [
        'Minimizes overall predictive variance and overfitting to single stat engines',
        'Balanced shrinkage against noise in early-season rotation adjustments',
        'Consistently lowest Brier score in historical cross-validation (0.2284 vs 0.237-0.244 for single variants)',
      ],
      methodology:
        'Game-by-game Pythagorean margin expectation computed from linear blend of variant offensive and defensive ratings, simulated over 1,000 independent seasons.',
    },
    variant_bottom_up: {
      id: 'variant_bottom_up',
      name: 'Production Bottom-Up Rotation BPM',
      weightBadge: 'Weight 35%',
      description:
        'Minute-weighted player Box Plus-Minus ratings aggregated over 240-minute active roster rotations.',
      strengths: [
        'Directly reflects depth chart minutes and individual player scoring/rebound efficiency',
        'Highly responsive to player transactions and depth changes',
        'Captures stars minute load impact directly',
      ],
      methodology:
        'Transforms 330 rotation players projected BPM and minutes into team net rating per 100 possessions.',
    },
    variant_rapm: {
      id: 'variant_rapm',
      name: 'Bayesian Stint-Level RAPM',
      weightBadge: 'Weight 25%',
      description:
        'Ridge-regularized adjusted plus-minus stint ratings centered across league possessions.',
      strengths: [
        'Free from box-score bias (screen assists, box-outs, rim deterrence)',
        'Bayesian prior centered to mitigate collinearity among frequent lineup pairings',
        'Isolates lineup interaction effects',
      ],
      methodology:
        'Stint-level possession matrix solved using L2 ridge regression with empirical Bayes hyperparameter tuning.',
    },
    variant_shot_fatigue: {
      id: 'variant_shot_fatigue',
      name: 'Shot Quality & Circadian Travel Fatigue',
      weightBadge: 'Weight 20%',
      description:
        'Bottom-up ratings adjusted for spatial shot-quality regression and travel/circadian rest fatigue.',
      strengths: [
        'Penalizes teams on 3-in-4 nights and back-to-backs crossing multiple time zones',
        'Accounts for expected eFG% based on shot location and defender proximity',
        'Superior accuracy in second halves of road back-to-backs',
      ],
      methodology:
        'Applies fatigue discount factor and expected shot quality differential to adjust baseline team point spreads.',
    },
    variant_embeddings: {
      id: 'variant_embeddings',
      name: '16-D Style Latent Embeddings',
      weightBadge: 'Weight 20%',
      description:
        'Pythagorean expected win probability modulated by 16-dimensional team stylistic similarity matrix.',
      strengths: [
        'Captures stylistic matchup friction (pace clashing, offensive rebounding vs transition defense)',
        'Non-linear team interaction modeling via latent neural embeddings',
        'Identifies stylistic kryptonite matchups between top tier contenders',
      ],
      methodology:
        'Neural graph representations projected to 16 dimensions; cosine similarity modulates expected win margin.',
    },
  };

  // Compute divergence/disagreement metrics for each team across the 4 variants
  const teamsWithDivergence = useMemo(() => {
    return teams.map((t) => {
      const bu = t.variant_bottom_up_mean_wins;
      const rapm = t.variant_rapm_mean_wins;
      const sf = t.variant_shot_fatigue_mean_wins;
      const emb = t.variant_embeddings_mean_wins;
      const values = [bu, rapm, sf, emb];
      const minVal = Math.min(...values);
      const maxVal = Math.max(...values);
      const spread = maxVal - minVal;
      const variance =
        values.reduce((acc, v) => acc + Math.pow(v - t.ensemble_mean_wins, 2), 0) / 4;
      const divergenceStd = Math.sqrt(variance);

      // Which model likes them most/least?
      const modelScores = [
        { model: 'Bottom-Up BPM', wins: bu },
        { model: 'Bayesian RAPM', wins: rapm },
        { model: 'Shot & Fatigue', wins: sf },
        { model: '16-D Embeddings', wins: emb },
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
          variant_bottom_up: bu,
          variant_rapm: rapm,
          variant_shot_fatigue: sf,
          variant_embeddings: emb,
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
                  ? 'bg-indigo-600 text-white shadow-lg shadow-indigo-600/30'
                  : 'bg-slate-900 text-slate-300 hover:text-white hover:bg-slate-800 border border-slate-800'
              }`}
            >
              <span>{detail.name}</span>
              <span
                className={`text-[11px] px-2 py-0.5 rounded-full ${
                  isActive ? 'bg-white/20 text-white' : 'bg-slate-800 text-slate-400'
                }`}
              >
                {detail.weightBadge}
              </span>
            </button>
          );
        })}
      </div>

      {/* Active Variant Architecture Card */}
      <div className="bg-slate-900/80 border border-slate-800 rounded-xl p-6 space-y-4">
        <div className="flex flex-col md:flex-row md:items-center justify-between gap-4">
          <div>
            <div className="flex items-center gap-3">
              <h2 className="text-xl font-bold text-white">{currentVariantInfo.name}</h2>
              <span className="px-2.5 py-0.5 rounded-full text-xs font-semibold bg-indigo-500/20 text-indigo-300 border border-indigo-500/30">
                {currentVariantInfo.weightBadge}
              </span>
            </div>
            <p className="text-slate-300 text-sm mt-1">{currentVariantInfo.description}</p>
          </div>
          <div className="text-xs text-slate-400 bg-slate-950 p-3 rounded-lg border border-slate-800 max-w-sm">
            <span className="text-amber-400 font-semibold block mb-0.5">Methodology:</span>
            {currentVariantInfo.methodology}
          </div>
        </div>

        <div>
          <h4 className="text-xs font-bold uppercase tracking-wider text-slate-400 mb-2">
            Key Architectural Advantages
          </h4>
          <div className="grid grid-cols-1 md:grid-cols-3 gap-3">
            {currentVariantInfo.strengths.map((s, idx) => (
              <div
                key={idx}
                className="bg-slate-950/60 border border-slate-800/80 rounded-lg p-3 text-xs text-slate-300 flex items-start gap-2"
              >
                <div className="w-1.5 h-1.5 rounded-full bg-emerald-400 mt-1 flex-shrink-0" />
                <span>{s}</span>
              </div>
            ))}
          </div>
        </div>
      </div>

      {/* Historical Cross-Validation: Brier Score Calibration Visualization */}
      <BrierScoreComparison />

      {/* Model Divergence & Disagreement Matrix */}
      <div className="space-y-4">
        <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-3">
          <div>
            <h3 className="text-lg font-bold text-white flex items-center gap-2">
              <GitCompare className="w-5 h-5 text-indigo-400" />
              <span>Model Divergence & Disagreement Matrix</span>
            </h3>
            <p className="text-xs text-slate-400">
              Comparing win totals projected across all 4 modeling variants to identify where systems diverge most.
            </p>
          </div>
          <div className="flex items-center gap-2 text-xs">
            <span className="text-slate-400">Sort by:</span>
            <div className="inline-flex rounded-lg bg-slate-950 p-1 border border-slate-800">
              <button
                onClick={() => setDivergenceSort('divergence')}
                className={`px-2.5 py-1 rounded text-xs font-semibold ${
                  divergenceSort === 'divergence'
                    ? 'bg-indigo-600 text-white'
                    : 'text-slate-400 hover:text-white'
                }`}
              >
                Max Spread
              </button>
              <button
                onClick={() => setDivergenceSort('wins')}
                className={`px-2.5 py-1 rounded text-xs font-semibold ${
                  divergenceSort === 'wins' ? 'bg-indigo-600 text-white' : 'text-slate-400 hover:text-white'
                }`}
              >
                Ensemble Wins
              </button>
              <button
                onClick={() => setDivergenceSort('alpha')}
                className={`px-2.5 py-1 rounded text-xs font-semibold ${
                  divergenceSort === 'alpha' ? 'bg-indigo-600 text-white' : 'text-slate-400 hover:text-white'
                }`}
              >
                Team A-Z
              </button>
            </div>
          </div>
        </div>

        {/* Matrix Table */}
        <div className="bg-slate-900/70 border border-slate-800 rounded-xl overflow-hidden shadow-xl">
          <div className="overflow-x-auto">
            <table className="w-full text-left text-sm border-collapse">
              <thead>
                <tr className="bg-slate-950/80 border-b border-slate-800 text-slate-400 text-xs">
                  <th className="py-3 px-4">Team</th>
                  <th className="py-3 px-3 text-center bg-indigo-950/30 text-indigo-300 font-bold">
                    Ensemble
                  </th>
                  <th className="py-3 px-3 text-center">
                    <div>Bottom-Up BPM</div>
                    <div className="text-[10px] text-slate-500 font-normal">35% Weight</div>
                  </th>
                  <th className="py-3 px-3 text-center">
                    <div>Bayesian RAPM</div>
                    <div className="text-[10px] text-slate-500 font-normal">25% Weight</div>
                  </th>
                  <th className="py-3 px-3 text-center">
                    <div>Shot & Fatigue</div>
                    <div className="text-[10px] text-slate-500 font-normal">20% Weight</div>
                  </th>
                  <th className="py-3 px-3 text-center">
                    <div>16-D Embeddings</div>
                    <div className="text-[10px] text-slate-500 font-normal">20% Weight</div>
                  </th>
                  <th className="py-3 px-4 text-center">
                    <div>Variant Spread</div>
                    <div className="text-[10px] text-slate-500 font-normal">Max - Min Δ</div>
                  </th>
                  <th className="py-3 px-4">Model Consensus & Disagreement</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-slate-800/60 font-sans">
                {sortedDivergenceTeams.map((team) => {
                  const bu = team.variantWins.variant_bottom_up;
                  const rapm = team.variantWins.variant_rapm;
                  const sf = team.variantWins.variant_shot_fatigue;
                  const emb = team.variantWins.variant_embeddings;
                  const ens = team.ensemble_mean_wins;

                  const isHighDivergence = team.spread >= 9.0;
                  const isModerateDivergence = team.spread >= 6.0 && team.spread < 9.0;

                  return (
                    <tr
                      key={team.team}
                      className="hover:bg-slate-800/40 transition-colors text-slate-200"
                    >
                      <td className="py-3 px-4">
                        <div className="flex items-center gap-2.5">
                          <div className="w-8 h-8 rounded-lg bg-slate-950/80 border border-slate-800 p-1 flex items-center justify-center flex-shrink-0">
                            <TeamLogo team={team.team} size="sm" />
                          </div>
                          <div>
                            <span className="font-semibold text-white block leading-tight">{team.team_name}</span>
                            <span className="text-[10px] font-mono text-amber-400 font-semibold">{team.team}</span>
                          </div>
                        </div>
                      </td>
                      <td className="py-3 px-3 text-center font-mono font-bold text-indigo-400 bg-indigo-950/20 text-base">
                        {ens.toFixed(1)}
                      </td>
                      <td className="py-3 px-3 text-center font-mono text-xs text-slate-300">
                        <span className={bu > ens ? 'text-emerald-400 font-semibold' : bu < ens ? 'text-rose-400' : ''}>
                          {bu.toFixed(1)}
                        </span>
                      </td>
                      <td className="py-3 px-3 text-center font-mono text-xs text-slate-300">
                        <span className={rapm > ens ? 'text-emerald-400 font-semibold' : rapm < ens ? 'text-rose-400' : ''}>
                          {rapm.toFixed(1)}
                        </span>
                      </td>
                      <td className="py-3 px-3 text-center font-mono text-xs text-slate-300">
                        <span className={sf > ens ? 'text-emerald-400 font-semibold' : sf < ens ? 'text-rose-400' : ''}>
                          {sf.toFixed(1)}
                        </span>
                      </td>
                      <td className="py-3 px-3 text-center font-mono text-xs text-slate-300">
                        <span className={emb > ens ? 'text-emerald-400 font-semibold' : emb < ens ? 'text-rose-400' : ''}>
                          {emb.toFixed(1)}
                        </span>
                      </td>
                      <td className="py-3 px-4 text-center">
                        <span
                          className={`inline-block px-2.5 py-0.5 rounded-full text-xs font-bold font-mono ${
                            isHighDivergence
                              ? 'bg-rose-500/20 text-rose-300 border border-rose-500/30'
                              : isModerateDivergence
                              ? 'bg-amber-500/20 text-amber-300 border border-amber-500/30'
                              : 'bg-emerald-500/10 text-emerald-300 border border-emerald-500/20'
                          }`}
                        >
                          {team.spread.toFixed(1)} W
                        </span>
                      </td>
                      <td className="py-3 px-4 text-xs">
                        <div className="flex items-center gap-1.5">
                          <span className="text-emerald-400 font-medium">
                            +{team.highestModel.model.split(' ')[0]} ({team.highestModel.wins.toFixed(1)})
                          </span>
                          <span className="text-slate-600">•</span>
                          <span className="text-rose-400 font-medium">
                            -{team.lowestModel.model.split(' ')[0]} ({team.lowestModel.wins.toFixed(1)})
                          </span>
                        </div>
                      </td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
        </div>
      </div>
    </div>
  );
};
