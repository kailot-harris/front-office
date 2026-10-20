'use client';

import React from 'react';
import { ShieldAlert, AlertTriangle, CheckCircle2, DollarSign } from 'lucide-react';
import { FranchiseCbtProfile } from '@/lib/cbtTypes';

interface CbtThermometerProps {
  team: FranchiseCbtProfile;
}

export const CbtThermometer: React.FC<CbtThermometerProps> = ({ team }) => {
  const maxAxis = 350; // $350M upper scale limit
  const baseT = team.baseThreshold;   // 244
  const t1 = team.tier1Threshold;      // 264
  const t2 = team.tier2Threshold;      // 284
  const t3 = team.tier3Threshold;      // 304

  const payrollPct = Math.min(100, Math.max(0, (team.payroll2026 / maxAxis) * 100));
  const basePct = (baseT / maxAxis) * 100;
  const t1Pct = (t1 / maxAxis) * 100;
  const t2Pct = (t2 / maxAxis) * 100;
  const t3Pct = (t3 / maxAxis) * 100;

  // Determine bar gradient based on threshold breached
  const getBarGradient = () => {
    if (team.payroll2026 > t3) return 'from-amber-500 via-rose-500 to-red-600 shadow-rose-500/30';
    if (team.payroll2026 > t2) return 'from-sky-500 via-amber-500 to-rose-500 shadow-amber-500/20';
    if (team.payroll2026 > baseT) return 'from-sky-500 via-cyan-400 to-amber-400 shadow-sky-500/20';
    return 'from-emerald-500 via-teal-400 to-sky-400 shadow-emerald-500/20';
  };

  return (
    <div className="bg-surface-raised/90 border border-slate-800 rounded-xl p-5 shadow-xl">
      <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-3 mb-4">
        <div>
          <div className="flex items-center gap-2">
            <h3 className="font-bold text-white text-base">CBT Threshold Thermometer</h3>
            <span className={`text-[11px] font-semibold px-2 py-0.5 rounded-full border ${
              team.payroll2026 > baseT
                ? 'bg-rose-500/10 border-rose-500/30 text-rose-400'
                : 'bg-emerald-500/10 border-emerald-500/30 text-emerald-400'
            }`}>
              {team.cbtTier}
            </span>
          </div>
          <p className="text-xs text-slate-400 mt-0.5">
            2026 Tax Threshold: ${baseT.toFixed(1)}M • Tax Bill: ${team.cbtTaxBill.toFixed(2)}M
          </p>
        </div>

        <div className="flex items-center gap-2">
          {team.isRepeater && (
            <span className="text-[10.5px] font-bold bg-amber-500/15 border border-amber-500/40 text-amber-300 px-2 py-0.5 rounded">
              Repeater Tax Rates Active
            </span>
          )}
          <div className="text-right">
            <span className="text-[10px] text-slate-400 block uppercase tracking-wider">Total Commit</span>
            <span className="font-mono font-extrabold text-base text-white">
              ${team.totalCommitment.toFixed(1)}M
            </span>
          </div>
        </div>
      </div>

      {/* Progress Bar Container */}
      <div className="relative pt-6 pb-2">
        {/* Track */}
        <div className="h-4 w-full bg-surface rounded-full border border-slate-800 overflow-hidden relative">
          {/* Shaded Threshold Regions */}
          <div
            className="absolute top-0 bottom-0 bg-amber-500/10 border-r border-amber-500/30"
            style={{ left: `${basePct}%`, width: `${t2Pct - basePct}%` }}
            title="Tier 1-2 Surcharge Zone"
          />
          <div
            className="absolute top-0 bottom-0 bg-rose-500/15 border-r border-rose-500/30"
            style={{ left: `${t2Pct}%`, width: `${t3Pct - t2Pct}%` }}
            title="Draft Pick Penalty Zone"
          />
          <div
            className="absolute top-0 bottom-0 bg-red-600/20"
            style={{ left: `${t3Pct}%`, right: 0 }}
            title="Cohen Tax Mega Zone"
          />

          {/* Active Fill */}
          <div
            className={`h-full rounded-full bg-gradient-to-r transition-all duration-700 ease-out shadow-lg ${getBarGradient()}`}
            style={{ width: `${payrollPct}%` }}
          />
        </div>

        {/* Marker Labels */}
        <div className="relative w-full h-8 mt-2 text-[10px] font-mono text-slate-400">
          {/* Base CBT */}
          <div
            className="absolute -translate-x-1/2 flex flex-col items-center"
            style={{ left: `${basePct}%` }}
          >
            <div className="w-0.5 h-2 bg-slate-600 mb-0.5" />
            <span className="text-slate-300 font-semibold">${baseT}M</span>
            <span className="text-[9px] text-slate-400">Base</span>
          </div>

          {/* Tier 1 */}
          <div
            className="absolute -translate-x-1/2 flex flex-col items-center"
            style={{ left: `${t1Pct}%` }}
          >
            <div className="w-0.5 h-2 bg-amber-500/60 mb-0.5" />
            <span className="text-amber-400/90">${t1}M</span>
            <span className="text-[9px] text-amber-400/70">T1</span>
          </div>

          {/* Tier 2 */}
          <div
            className="absolute -translate-x-1/2 flex flex-col items-center"
            style={{ left: `${t2Pct}%` }}
          >
            <div className="w-0.5 h-2 bg-rose-500/60 mb-0.5" />
            <span className="text-rose-400/90">${t2}M</span>
            <span className="text-[9px] text-rose-400/70">Draft -10</span>
          </div>

          {/* Tier 3 */}
          <div
            className="absolute -translate-x-1/2 flex flex-col items-center"
            style={{ left: `${t3Pct}%` }}
          >
            <div className="w-0.5 h-2 bg-red-500 mb-0.5" />
            <span className="text-red-400 font-bold">${t3}M</span>
            <span className="text-[9px] text-red-400">Cohen</span>
          </div>
        </div>
      </div>

      {/* Penalty Badges & Status Details */}
      <div className="grid grid-cols-1 sm:grid-cols-3 gap-3 mt-4 pt-4 border-t border-slate-800/80 text-xs">
        <div className="flex items-center gap-2 p-2.5 rounded-lg bg-surface/60 border border-slate-800">
          <DollarSign className="w-4 h-4 text-emerald-400 flex-shrink-0" />
          <div className="min-w-0">
            <div className="text-[10px] text-slate-400">CBT Tax Rate Applied</div>
            <div className="font-semibold text-slate-200 truncate">{team.penalties.taxRateDescription}</div>
          </div>
        </div>

        <div className="flex items-center gap-2 p-2.5 rounded-lg bg-surface/60 border border-slate-800">
          {team.penalties.draftPickDrop10 ? (
            <AlertTriangle className="w-4 h-4 text-amber-400 flex-shrink-0" />
          ) : (
            <CheckCircle2 className="w-4 h-4 text-slate-400 flex-shrink-0" />
          )}
          <div className="min-w-0">
            <div className="text-[10px] text-slate-400">Draft Selection Status</div>
            <div className={`font-semibold truncate ${team.penalties.draftPickDrop10 ? 'text-amber-300' : 'text-slate-400'}`}>
              {team.penalties.draftPickDrop10 ? 'Top Pick Dropped 10 Spots' : 'Protected (No Penalty)'}
            </div>
          </div>
        </div>

        <div className="flex items-center gap-2 p-2.5 rounded-lg bg-surface/60 border border-slate-800">
          {team.penalties.internationalPoolReduction ? (
            <ShieldAlert className="w-4 h-4 text-rose-400 flex-shrink-0" />
          ) : (
            <CheckCircle2 className="w-4 h-4 text-slate-400 flex-shrink-0" />
          )}
          <div className="min-w-0">
            <div className="text-[10px] text-slate-400">Intl Pool & Rev Sharing</div>
            <div className={`font-semibold truncate ${team.penalties.internationalPoolReduction ? 'text-rose-400' : 'text-slate-300'}`}>
              {team.penalties.internationalPoolReduction ? '-$1.0M Intl Pool Slashed' : (team.penalties.revenueShareEligible ? 'Revenue Share Eligible' : 'Standard')}
            </div>
          </div>
        </div>
      </div>
    </div>
  );
};
