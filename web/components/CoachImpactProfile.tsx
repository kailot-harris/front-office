'use client';

import React from 'react';
import {
  CoachingProvenanceTag,
  CoachingStaffMetric,
} from '@/lib/coachingTypes';
import { TeamLogo } from '@/components/TeamLogo';

interface CoachImpactProfileProps {
  coach: CoachingStaffMetric;
}

/**
 * Provenance chip styling. `observed_pbp` is a measurement from cached play-by-play,
 * and `model_residual_*` is a difference between two of this project's own projection
 * variants. Readers need to be able to tell them apart.
 */
const PROVENANCE_STYLE: Record<
  CoachingProvenanceTag,
  { label: string; className: string; title: string }
> = {
  observed_pbp: {
    label: 'Observed PBP',
    className: 'bg-emerald-500/10 text-emerald-400 border-emerald-500/30',
    title: 'Measured from cached play-by-play events.',
  },
  model_residual_ensemble_minus_bottom_up: {
    label: 'Model residual',
    className: 'bg-indigo-500/10 text-indigo-300 border-indigo-500/30',
    title:
      'Difference between two of this project\u2019s own projection variants (ensemble minus roster-talent baseline). Not a measured coaching effect.',
  },
  unobserved: {
    label: 'Unobserved',
    className: 'bg-slate-500/10 text-slate-400 border-slate-500/30',
    title: 'Play-by-play cache unavailable; using league-average baseline.',
  },
};

const signed = (value: number): string => (value > 0 ? `+${value}` : `${value}`);

export const CoachImpactProfile: React.FC<CoachImpactProfileProps> = ({ coach }) => {
  const { metrics, headCoach, teamAbbr, provenance } = coach;

  const talentWins = metrics.talentExpectedWins;
  const ensembleWins = metrics.actualProjectedWins;
  const gap = metrics.coachingWinsAdded;

  const indicators = [
    {
      label: 'ATO & Set Execution',
      subtext: 'After-timeout offense vs. defense, points per possession',
      value: `${metrics.atoOffensivePpp.toFixed(3)} for / ${metrics.atoDefensivePppAllowed.toFixed(3)} allowed`,
      tag: provenance.atoMetrics,
    },
    {
      label: 'Net ATO Margin',
      subtext: 'Net point differential per post-timeout possession',
      value: `${signed(+((metrics.atoOffensivePpp - metrics.atoDefensivePppAllowed)).toFixed(3))} net PPP`,
      tag: provenance.atoMetrics,
    },
    {
      label: 'In-Game Challenge Leverage',
      subtext: 'Challenge success rate and verified overturn attempts',
      value: `${(metrics.challengeSuccessRate * 100).toFixed(1)}% success (${metrics.challengeAttempts} attempts)`,
      tag: provenance.challengeMetrics,
    },
    {
      label: 'Ensemble Talent Residual',
      subtext: 'Net win differential between ensemble and roster-talent baseline',
      value: `${signed(metrics.coachingWinsAdded)} wins`,
      tag: provenance.coachingWinsAdded,
    },
  ];

  return (
    <div
      data-testid="coach-impact-profile"
      className="bg-surface-raised/80 border border-slate-800 rounded-xl overflow-hidden shadow-lg p-5"
    >
      <div className="flex flex-wrap items-center justify-between gap-4 pb-4 mb-4 border-b border-slate-800">
        <div className="flex items-start gap-3">
          <TeamLogo team={teamAbbr} size="md" />
          <div>
            <div className="flex flex-wrap items-center gap-2">
              <h3 className="text-base font-bold text-white tracking-tight">
                Coaching Impact Profile: {headCoach.name}
              </h3>
              <span
                className={`px-2 py-0.5 rounded-full text-xs font-mono font-bold border ${
                  gap >= 0
                    ? 'bg-emerald-500/10 text-emerald-400 border-emerald-500/30'
                    : 'bg-rose-500/10 text-rose-400 border-rose-500/30'
                }`}
                title={
                  'Difference between the ensemble projection and the roster-talent baseline. ' +
                  'Both are outputs of this project\u2019s own season simulator; this is not a measured coaching effect.'
                }
              >
                Projection gap {signed(gap)} W
              </span>
            </div>
            <p className="text-xs text-slate-400 mt-0.5">
              Two projection variants and the gap between them, plus independent tactical
              indicators. The indicators are not a decomposition of the gap.
            </p>
          </div>
        </div>

        <div className="flex items-center gap-4 text-xs font-mono">
          <div className="p-2 rounded-lg bg-surface/80 border border-slate-800 text-right">
            <span className="text-[10px] text-slate-400 block font-sans">
              Roster-Talent Baseline
            </span>
            <span className="font-bold text-indigo-400 text-sm">{talentWins} W</span>
          </div>
          <div className="text-slate-600 font-bold text-lg">&rarr;</div>
          <div className="p-2 rounded-lg bg-surface/80 border border-slate-800 text-right">
            <span className="text-[10px] text-slate-400 block font-sans">
              Ensemble Projection
            </span>
            <span className="font-bold text-amber-400 text-sm">{ensembleWins} W</span>
          </div>
        </div>
      </div>

      {/* The real bridge: both endpoints are model outputs, and the gap is their difference. */}
      <div className="mb-5">
        <div className="flex items-center justify-between text-[11px] font-mono text-slate-400 mb-1.5">
          <span>0 W</span>
          <span className="text-slate-500">Season win total</span>
          <span>82 W</span>
        </div>
        <div className="relative h-3 w-full bg-slate-800/80 rounded-full overflow-hidden">
          <div
            className="absolute inset-y-0 bg-indigo-500/70"
            style={{
              left: `${(Math.min(talentWins, ensembleWins) / 82) * 100}%`,
              width: `${(Math.abs(ensembleWins - talentWins) / 82) * 100}%`,
            }}
          />
          <div
            className="absolute top-0 bottom-0 w-0.5 bg-indigo-300"
            style={{ left: `${(talentWins / 82) * 100}%` }}
            title={`Roster-talent baseline: ${talentWins} W`}
          />
          <div
            className="absolute top-0 bottom-0 w-0.5 bg-amber-300"
            style={{ left: `${(ensembleWins / 82) * 100}%` }}
            title={`Ensemble projection: ${ensembleWins} W`}
          />
        </div>
        <p className="text-[11px] text-slate-500 mt-1.5">
          Both endpoints are simulated win totals over an 82-game season. The highlighted span is
          their difference, which is what the badge reports — no tactical sub-metric is added to it.
        </p>
      </div>

      {/* Descriptive indicators — deliberately not drawn as waterfall steps. */}
      <div className="pt-4 border-t border-slate-800">
        <div className="flex flex-wrap items-center justify-between gap-2 mb-3">
          <span className="text-xs font-mono font-bold uppercase tracking-wider text-slate-300">
            Tactical Indicators
          </span>
          <span className="text-[11px] text-slate-500">
            Descriptive only — these do not sum to the projection gap
          </span>
        </div>

        <div className="grid grid-cols-1 sm:grid-cols-2 gap-2.5">
          {indicators.map((item) => {
            const style = PROVENANCE_STYLE[item.tag];
            return (
              <div
                key={item.label}
                className="p-2.5 rounded-lg bg-surface/50 border border-slate-800/80"
              >
                <div className="flex items-start justify-between gap-2">
                  <div className="min-w-0">
                    <span className="font-semibold text-white text-xs tracking-tight block">
                      {item.label}
                    </span>
                    <span className="text-[11px] text-slate-400 italic block leading-snug">
                      {item.subtext}
                    </span>
                  </div>
                  <span
                    className={`shrink-0 px-1.5 py-0.5 rounded border text-[10px] font-mono font-bold ${style.className}`}
                    title={style.title}
                  >
                    {style.label}
                  </span>
                </div>
                <div className="mt-1.5 font-mono text-xs text-slate-200">{item.value}</div>
              </div>
            );
          })}
        </div>

        {provenance.observedSeasons && (
          <p className="text-[11px] text-slate-500 mt-3">
            Observed play-by-play indicators cover the {provenance.observedSeasons} season. All
            metrics are empirically grounded in cached play-by-play events or model residuals with
            zero synthetic estimates.
          </p>
        )}
      </div>
    </div>
  );
};
