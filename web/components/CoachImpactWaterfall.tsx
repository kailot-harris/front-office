'use client';

import React from 'react';
import { CoachingStaffMetric } from '@/lib/coachingTypes';
import { TeamLogo } from '@/components/TeamLogo';

interface CoachImpactWaterfallProps {
  coach: CoachingStaffMetric;
}

export const CoachImpactWaterfall: React.FC<CoachImpactWaterfallProps> = ({ coach }) => {
  const { metrics, headCoach, teamAbbr } = coach;

  // Decompose components of the talent-to-wins bridge
  const talentWins = metrics.talentExpectedWins;
  const finalWins = metrics.actualProjectedWins;
  const netLift = metrics.coachingWinsAdded;

  // Breakdown sub-components calibrated to metrics
  const schemeLift = +(metrics.shotQualityLiftEfg * 0.45).toFixed(1);
  const atoLift = +((metrics.atoOffensivePpp - 1.02) * 12 - (metrics.atoDefensivePppAllowed - 0.98) * 8).toFixed(1);
  const staggerLift = +((metrics.rotationStaggerScore - 70) * 0.04).toFixed(1);
  const challengeLift = +(metrics.challengeWpa * 3.5).toFixed(1);

  const steps = [
    {
      label: 'Roster Talent Baseline',
      subtext: 'Expected wins via player RAPM & minutes-weighted quality',
      val: talentWins,
      delta: null,
      type: 'baseline',
      color: 'bg-indigo-600',
    },
    {
      label: 'Tactical Scheme (xSQ Lift)',
      subtext: 'Spacing & 3P/rim generation above shooter baseline',
      val: schemeLift,
      delta: schemeLift >= 0 ? `+${schemeLift}` : `${schemeLift}`,
      type: schemeLift >= 0 ? 'positive' : 'negative',
      color: schemeLift >= 0 ? 'bg-emerald-500' : 'bg-rose-500',
    },
    {
      label: 'ATO & Set Execution',
      subtext: 'Point differential on post-timeout plays',
      val: atoLift,
      delta: atoLift >= 0 ? `+${atoLift}` : `${atoLift}`,
      type: atoLift >= 0 ? 'positive' : 'negative',
      color: atoLift >= 0 ? 'bg-emerald-500' : 'bg-rose-500',
    },
    {
      label: 'Rotation & Staggering',
      subtext: 'Star staggering to avoid non-star bench bleed',
      val: staggerLift,
      delta: staggerLift >= 0 ? `+${staggerLift}` : `${staggerLift}`,
      type: staggerLift >= 0 ? 'positive' : 'negative',
      color: staggerLift >= 0 ? 'bg-emerald-500' : 'bg-rose-500',
    },
    {
      label: 'In-Game Challenge WPA',
      subtext: 'Late-game clock & review leverage equity',
      val: challengeLift,
      delta: challengeLift >= 0 ? `+${challengeLift}` : `${challengeLift}`,
      type: challengeLift >= 0 ? 'positive' : 'negative',
      color: challengeLift >= 0 ? 'bg-emerald-500' : 'bg-rose-500',
    },
    {
      label: 'Ensemble Projected Wins',
      subtext: 'Final simulated win projection including coaching',
      val: finalWins,
      delta: null,
      type: 'final',
      color: 'bg-amber-500',
    },
  ];

  return (
    <div className="bg-slate-900/80 border border-slate-800 rounded-xl overflow-hidden shadow-lg p-5">
      <div className="flex flex-wrap items-center justify-between gap-4 pb-4 mb-4 border-b border-slate-800">
        <div className="flex items-center gap-3">
          <TeamLogo team={teamAbbr} size="md" />
          <div>
            <div className="flex items-center gap-2">
              <h3 className="text-base font-bold text-white tracking-tight">
                Talent-to-Wins Bridge: {headCoach.name}
              </h3>
              <span
                className={`px-2 py-0.5 rounded-full text-xs font-mono font-bold border ${
                  netLift >= 0
                    ? 'bg-emerald-500/10 text-emerald-400 border-emerald-500/30'
                    : 'bg-rose-500/10 text-rose-400 border-rose-500/30'
                }`}
              >
                {netLift >= 0 ? `+${netLift} Wins Added` : `${netLift} Wins Lost`}
              </span>
            </div>
            <p className="text-xs text-slate-400 mt-0.5">
              Decomposing roster baseline expectations into tactical scheme lift, ATO execution, and in-game decisions.
            </p>
          </div>
        </div>

        <div className="flex items-center gap-4 text-xs font-mono">
          <div className="p-2 rounded-lg bg-slate-950/80 border border-slate-800 text-right">
            <span className="text-[10px] text-slate-400 block font-sans">Roster Baseline</span>
            <span className="font-bold text-indigo-400 text-sm">{talentWins} Wins</span>
          </div>
          <div className="text-slate-600 font-bold text-lg">→</div>
          <div className="p-2 rounded-lg bg-slate-950/80 border border-slate-800 text-right">
            <span className="text-[10px] text-slate-400 block font-sans">Final Projection</span>
            <span className="font-bold text-amber-400 text-sm">{finalWins} Wins</span>
          </div>
        </div>
      </div>

      {/* Step Waterfall Bars */}
      <div className="space-y-3.5">
        {steps.map((step, idx) => {
          const isBaselineOrFinal = step.type === 'baseline' || step.type === 'final';
          const maxWinsScale = 65;
          const pct = Math.min(100, Math.max(10, (Math.abs(step.val) / maxWinsScale) * 100));

          return (
            <div key={idx} className="p-2.5 rounded-lg bg-slate-950/50 border border-slate-800/80">
              <div className="flex items-center justify-between text-xs mb-1.5">
                <div className="flex items-center gap-2">
                  <span className="font-mono text-[10px] font-bold text-slate-500 w-4">
                    {idx + 1}.
                  </span>
                  <span className="font-semibold text-white tracking-tight">{step.label}</span>
                  <span className="hidden sm:inline text-[11px] text-slate-400 italic">
                    • {step.subtext}
                  </span>
                </div>
                <div className="font-mono font-bold">
                  {step.delta ? (
                    <span
                      className={`text-xs px-1.5 py-0.5 rounded ${
                        step.type === 'positive'
                          ? 'bg-emerald-500/10 text-emerald-400'
                          : 'bg-rose-500/10 text-rose-400'
                      }`}
                    >
                      {step.delta} W
                    </span>
                  ) : (
                    <span className="text-sm text-slate-200">{step.val} W</span>
                  )}
                </div>
              </div>

              {/* Bar visualization */}
              <div className="h-2 w-full bg-slate-800/80 rounded-full overflow-hidden flex">
                <div
                  className={`h-full ${step.color} transition-all duration-500 rounded-full`}
                  style={{ width: `${isBaselineOrFinal ? pct : Math.min(100, Math.abs(step.val) * 12)}%` }}
                />
              </div>
            </div>
          );
        })}
      </div>
    </div>
  );
};
