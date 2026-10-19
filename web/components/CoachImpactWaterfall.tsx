'use client';

import React from 'react';
import { CoachingStaffMetric } from '@/lib/coachingTypes';
import { TeamLogo } from '@/components/TeamLogo';

interface CoachImpactWaterfallProps {
  coach: CoachingStaffMetric;
}

export const CoachImpactWaterfall: React.FC<CoachImpactWaterfallProps> = ({ coach }) => {
  const { metrics, headCoach, teamAbbr } = coach;

  // Decompose components of the talent-to-wins bridge (44-game WNBA scale)
  const talentWins = metrics.talentExpectedWins;
  const finalWins = metrics.actualProjectedWins;
  const netLift = metrics.coachingWinsAdded;

  // Breakdown sub-components calibrated to WNBA metrics
  const schemeLift = +(metrics.shotQualityLiftEfg * 0.35).toFixed(1);
  const atoLift = +((metrics.atoOffensivePpp - 0.95) * 8 - (metrics.atoDefensivePppAllowed - 0.88) * 6).toFixed(1);
  const staggerLift = +((metrics.rotationStaggerScore - 70) * 0.03).toFixed(1);
  const challengeLift = +(metrics.challengeWpa * 2.5).toFixed(1);

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
      label: 'Final Projected Wins',
      subtext: 'Ensemble projection with system adjustments',
      val: finalWins,
      delta: netLift >= 0 ? `+${netLift} W Net` : `${netLift} W Net`,
      type: 'final',
      color: 'bg-gradient-to-r from-indigo-500 to-amber-500',
    },
  ];

  return (
    <div className="bg-slate-900/60 border border-slate-800 rounded-xl p-5 shadow-lg space-y-5">
      <div className="flex items-center justify-between border-b border-slate-800 pb-4">
        <div className="flex items-center gap-3">
          <TeamLogo team={teamAbbr} size="md" />
          <div>
            <h3 className="text-base font-bold text-white tracking-tight">
              Talent-to-Wins Waterfall Decomposition
            </h3>
            <p className="text-xs text-slate-400">
              {headCoach.name} ({teamAbbr}) • 44-Game WNBA System Residual
            </p>
          </div>
        </div>

        <div className="text-right">
          <span className="text-xs text-slate-400 block">Net Coaching Lift</span>
          <span
            className={`text-lg font-black ${
              netLift >= 0 ? 'text-emerald-400' : 'text-rose-400'
            }`}
          >
            {netLift >= 0 ? `+${netLift}` : netLift} Wins
          </span>
        </div>
      </div>

      <div className="space-y-3">
        {steps.map((step, idx) => (
          <div
            key={idx}
            className="flex flex-col sm:flex-row sm:items-center justify-between gap-2 p-3 rounded-lg bg-slate-950/60 border border-slate-800/80 hover:border-slate-700 transition-colors"
          >
            <div className="space-y-0.5">
              <div className="flex items-center gap-2">
                <span className="text-xs font-bold text-slate-200">{step.label}</span>
                {step.delta && (
                  <span
                    className={`text-[11px] font-mono font-bold px-1.5 py-0.2 rounded ${
                      step.type === 'positive'
                        ? 'bg-emerald-500/10 text-emerald-400 border border-emerald-500/20'
                        : step.type === 'negative'
                        ? 'bg-rose-500/10 text-rose-400 border border-rose-500/20'
                        : 'bg-indigo-500/10 text-indigo-400 border border-indigo-500/20'
                    }`}
                  >
                    {step.delta}
                  </span>
                )}
              </div>
              <p className="text-[11px] text-slate-400">{step.subtext}</p>
            </div>

            <div className="flex items-center gap-3 self-end sm:self-auto">
              <div className="w-24 sm:w-32 bg-slate-800 h-2 rounded-full overflow-hidden">
                <div
                  className={`h-full ${step.color} transition-all duration-500`}
                  style={{
                    width: `${Math.min(100, Math.max(8, (step.val / 44) * 100))}%`,
                  }}
                />
              </div>
              <span className="text-xs font-mono font-bold text-slate-100 w-12 text-right">
                {step.val.toFixed(1)} W
              </span>
            </div>
          </div>
        ))}
      </div>
    </div>
  );
};
