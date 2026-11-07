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

  // Breakdown sub-components calibrated to authentic WNBA metrics
  // Net ATO efficiency impact (Offensive PPP vs Defensive PPP allowed)
  const atoNet = metrics.atoOffensivePpp - metrics.atoDefensivePppAllowed;
  const atoLift = +(atoNet * 6.0).toFixed(1);

  // In-game review leverage (relative to ~40% league average challenge success)
  const challengeLift = +((metrics.challengeSuccessRate - 0.40) * 2.0).toFixed(1);

  // System tactical residual (spacing, rotations, and synergy beyond roster talent)
  const systemResidual = +(netLift - atoLift - challengeLift).toFixed(1);

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
      label: 'ATO & Set Execution',
      subtext: 'Net point differential on post-timeout half-court plays',
      val: atoLift,
      delta: atoLift >= 0 ? `+${atoLift}` : `${atoLift}`,
      type: atoLift >= 0 ? 'positive' : 'negative',
      color: atoLift >= 0 ? 'bg-emerald-500' : 'bg-rose-500',
    },
    {
      label: 'In-Game Challenge Leverage',
      subtext: 'Win equity added from official review overturns',
      val: challengeLift,
      delta: challengeLift >= 0 ? `+${challengeLift}` : `${challengeLift}`,
      type: challengeLift >= 0 ? 'positive' : 'negative',
      color: challengeLift >= 0 ? 'bg-emerald-500' : 'bg-rose-500',
    },
    {
      label: 'System & Tactical Residual',
      subtext: 'Scheme spacing, rotation synergy & pace adjustments',
      val: systemResidual,
      delta: systemResidual >= 0 ? `+${systemResidual}` : `${systemResidual}`,
      type: systemResidual >= 0 ? 'positive' : 'negative',
      color: systemResidual >= 0 ? 'bg-emerald-500' : 'bg-rose-500',
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
    <div className="bg-surface-raised/60 border border-slate-800 rounded-xl p-5 shadow-lg space-y-5">
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
            className="flex flex-col sm:flex-row sm:items-center justify-between gap-2 p-3 rounded-lg bg-surface/60 border border-slate-800/80 hover:border-slate-700 transition-colors"
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
