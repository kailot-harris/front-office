'use client';

import React from 'react';
import { FranchiseCbaProfile } from '@/lib/cbaTypes';

interface ApronThermometerProps {
  profile: FranchiseCbaProfile;
}

export const ApronThermometer: React.FC<ApronThermometerProps> = ({ profile }) => {
  const { totalPayroll2026, salaryCap, luxuryTaxThreshold, firstApron, secondApron } = profile;

  // Scale bounds ($M): min 110 to max 225
  const minVal = 115;
  const maxVal = 225;
  const span = maxVal - minVal;

  const toPct = (val: number) => {
    return Math.max(0, Math.min(100, ((val - minVal) / span) * 100));
  };

  const capPct = toPct(salaryCap);
  const taxPct = toPct(luxuryTaxThreshold);
  const a1Pct = toPct(firstApron);
  const a2Pct = toPct(secondApron);
  const payrollPct = toPct(totalPayroll2026);

  // Status color
  const getFillColor = () => {
    if (totalPayroll2026 > secondApron) return 'bg-rose-500';
    if (totalPayroll2026 > firstApron) return 'bg-orange-500';
    if (totalPayroll2026 > luxuryTaxThreshold) return 'bg-amber-500';
    if (totalPayroll2026 > salaryCap) return 'bg-indigo-500';
    return 'bg-emerald-500';
  };

  return (
    <div className="bg-surface/70 border border-slate-800 rounded-xl p-4 space-y-3 select-none">
      <div className="flex items-center justify-between text-xs">
        <div className="flex items-center gap-2">
          <span className="font-bold text-white tracking-tight">CBA Apron Thermometer</span>
          <span className="font-mono text-[10px] text-slate-400">2026-27 Payroll Horizon</span>
        </div>
        <div className="font-mono font-bold">
          <span className="text-slate-400 text-[11px] mr-1.5">Payroll:</span>
          <span className="text-white text-sm">${totalPayroll2026.toFixed(1)}M</span>
        </div>
      </div>

      {/* Visual Gauge Track */}
      <div className="relative pt-6 pb-4">
        {/* Threshold Markers */}
        <div className="absolute top-0 left-0 right-0 h-4 text-[9px] font-mono font-bold text-slate-400 pointer-events-none">
          {/* Cap */}
          <div className="absolute -translate-x-1/2 text-center" style={{ left: `${capPct}%` }}>
            <span className="block text-emerald-400">CAP</span>
            <span className="text-slate-500 text-[8px]">${salaryCap}M</span>
          </div>
          {/* Tax */}
          <div className="absolute -translate-x-1/2 text-center" style={{ left: `${taxPct}%` }}>
            <span className="block text-amber-400">TAX</span>
            <span className="text-slate-500 text-[8px]">${luxuryTaxThreshold}M</span>
          </div>
          {/* Apron 1 */}
          <div className="absolute -translate-x-1/2 text-center" style={{ left: `${a1Pct}%` }}>
            <span className="block text-orange-400">1st APR</span>
            <span className="text-slate-500 text-[8px]">${firstApron}M</span>
          </div>
          {/* Apron 2 */}
          <div className="absolute -translate-x-1/2 text-center" style={{ left: `${a2Pct}%` }}>
            <span className="block text-rose-400">2nd APR</span>
            <span className="text-slate-500 text-[8px]">${secondApron}M</span>
          </div>
        </div>

        {/* Track bar */}
        <div className="h-3 w-full bg-surface-raised rounded-full overflow-hidden flex relative border border-slate-800">
          {/* Filled current payroll */}
          <div
            className={`h-full ${getFillColor()} rounded-full transition-all duration-500 relative`}
            style={{ width: `${payrollPct}%` }}
          />

          {/* Vertical guidelines */}
          <div className="absolute top-0 bottom-0 w-0.5 bg-emerald-500/60 z-10" style={{ left: `${capPct}%` }} />
          <div className="absolute top-0 bottom-0 w-0.5 bg-amber-500/60 z-10" style={{ left: `${taxPct}%` }} />
          <div className="absolute top-0 bottom-0 w-0.5 bg-orange-500/60 z-10" style={{ left: `${a1Pct}%` }} />
          <div className="absolute top-0 bottom-0 w-0.5 bg-rose-500/60 z-10" style={{ left: `${a2Pct}%` }} />
        </div>

        {/* Current Payroll Pointer */}
        <div
          className="absolute bottom-0 -translate-x-1/2 transition-all duration-500 flex flex-col items-center"
          style={{ left: `${payrollPct}%` }}
        >
          <div className="w-2 h-2 rotate-45 bg-white shadow-sm" />
          <span className="text-[9px] font-mono font-black text-white bg-slate-800 px-1.5 py-0.2 rounded border border-slate-700 whitespace-nowrap mt-0.5">
            ${totalPayroll2026.toFixed(1)}M
          </span>
        </div>
      </div>

      {/* Headroom Status Pills */}
      <div className="grid grid-cols-2 sm:grid-cols-4 gap-2 pt-2 border-t border-slate-800/80 text-[11px] font-mono">
        <div className="p-1.5 rounded bg-surface-raised/80 border border-slate-800">
          <span className="text-[9px] text-slate-400 block font-sans">Cap Space</span>
          <span className={`font-bold ${profile.capSpace2026 > 0 ? 'text-emerald-400' : 'text-slate-500'}`}>
            {profile.capSpace2026 > 0 ? `+$${profile.capSpace2026}M` : '$0.0M'}
          </span>
        </div>
        <div className="p-1.5 rounded bg-surface-raised/80 border border-slate-800">
          <span className="text-[9px] text-slate-400 block font-sans">Tax Cushion</span>
          <span className={`font-bold ${profile.taxSpace2026 >= 0 ? 'text-emerald-400' : 'text-amber-400'}`}>
            {profile.taxSpace2026 >= 0 ? `+$${profile.taxSpace2026}M` : `-$${Math.abs(profile.taxSpace2026)}M (Tax)`}
          </span>
        </div>
        <div className="p-1.5 rounded bg-surface-raised/80 border border-slate-800">
          <span className="text-[9px] text-slate-400 block font-sans">1st Apron Room</span>
          <span className={`font-bold ${profile.firstApronSpace2026 >= 0 ? 'text-emerald-400' : 'text-orange-400'}`}>
            {profile.firstApronSpace2026 >= 0 ? `+$${profile.firstApronSpace2026}M` : `-$${Math.abs(profile.firstApronSpace2026)}M`}
          </span>
        </div>
        <div className="p-1.5 rounded bg-surface-raised/80 border border-slate-800">
          <span className="text-[9px] text-slate-400 block font-sans">2nd Apron Room</span>
          <span className={`font-bold ${profile.secondApronSpace2026 >= 0 ? 'text-emerald-400' : 'text-rose-400'}`}>
            {profile.secondApronSpace2026 >= 0 ? `+$${profile.secondApronSpace2026}M` : `-$${Math.abs(profile.secondApronSpace2026)}M (Breached)`}
          </span>
        </div>
      </div>
    </div>
  );
};
