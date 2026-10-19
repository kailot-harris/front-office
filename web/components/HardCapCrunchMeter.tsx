'use client';

import React from 'react';
import { WnbaFranchiseCbaProfile } from '@/lib/cbaTypes';
import { CheckCircle2, UserCheck, AlertTriangle } from 'lucide-react';

interface HardCapCrunchMeterProps {
  profile: WnbaFranchiseCbaProfile;
}

export const HardCapCrunchMeter: React.FC<HardCapCrunchMeterProps> = ({ profile }) => {
  const {
    totalPayroll2026,
    hardSalaryCap,
    capFloor,
    capSpace2026,
    rosterCount,
    twelfthSpotAvailable,
    cbaTier,
    hardCapCrunchIndex,
    corePlayer,
  } = profile;

  // Percentage consumed of hard cap
  const pctConsumed = Math.min(100, Math.max(0, (totalPayroll2026 / hardSalaryCap) * 100));
  const floorPct = (capFloor / hardSalaryCap) * 100; // 90%
  const twelfthRosterThreshold = 0.0788; // $78,831

  return (
    <div className="bg-slate-950/70 border border-slate-800 rounded-xl p-4 shadow-lg space-y-4">
      <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-2 pb-2 border-b border-slate-800">
        <div>
          <div className="flex items-center gap-2">
            <h4 className="text-sm font-bold text-white tracking-tight">
              Hard Cap Utilization & 11-vs-12 Roster Squeeze
            </h4>
            <span
              className={`text-[10px] font-mono px-2 py-0.5 rounded-full border font-bold ${
                twelfthSpotAvailable
                  ? 'bg-emerald-500/10 text-emerald-400 border-emerald-500/30'
                  : 'bg-rose-500/10 text-rose-400 border-rose-500/30'
              }`}
            >
              {cbaTier}
            </span>
          </div>
          <p className="text-xs text-slate-400 mt-0.5">
            WNBA Hard Salary Cap ($1.520M) vs Team Salary Floor ($1.368M)
          </p>
        </div>

        <div className="flex items-center gap-4 text-xs font-mono">
          <div>
            <span className="text-slate-500 text-[10px] block">Roster Spots</span>
            <span
              className={`font-black text-sm flex items-center gap-1 ${
                rosterCount === 12 ? 'text-emerald-400' : 'text-amber-400'
              }`}
            >
              <UserCheck className="w-3.5 h-3.5" />
              {rosterCount} / 12 Active
            </span>
          </div>
          <div>
            <span className="text-slate-500 text-[10px] block">Cap Space</span>
            <span className="font-black text-sm text-indigo-400">
              ${(capSpace2026 * 1000).toFixed(0)}k
            </span>
          </div>
        </div>
      </div>

      {/* Progress Bar Container */}
      <div className="space-y-1.5">
        <div className="flex justify-between text-xs font-mono">
          <span className="text-slate-400">
            Payroll: <strong className="text-white">${(totalPayroll2026 * 1000).toFixed(0)}k</strong>
          </span>
          <span className="text-slate-400">
            Ceiling: <strong className="text-rose-400">${(hardSalaryCap * 1000).toFixed(0)}k</strong>
          </span>
        </div>

        <div className="relative w-full h-4 bg-slate-900 rounded-full overflow-hidden border border-slate-800">
          {/* Minimum Floor Line (90%) */}
          <div
            className="absolute top-0 bottom-0 border-r-2 border-dashed border-amber-400/70 z-10"
            style={{ left: `${floorPct}%` }}
            title="90% Minimum Salary Floor ($1.368M)"
          />

          {/* Payroll Fill */}
          <div
            className={`h-full rounded-full transition-all duration-300 ${
              twelfthSpotAvailable
                ? 'bg-gradient-to-r from-indigo-500 via-emerald-500 to-emerald-400'
                : 'bg-gradient-to-r from-indigo-500 via-amber-500 to-rose-500'
            }`}
            style={{ width: `${pctConsumed}%` }}
          />
        </div>

        <div className="flex justify-between text-[10px] font-mono text-slate-500 pt-0.5">
          <span>$0.0M</span>
          <span className="text-amber-400/90">&larr; Floor: $1.368M (90%)</span>
          <span className="text-rose-400 font-bold">Hard Cap: $1.520M</span>
        </div>
      </div>

      {/* Roster Crunch Notice */}
      <div
        className={`p-3 rounded-lg border flex items-start gap-3 text-xs ${
          twelfthSpotAvailable
            ? 'bg-emerald-950/30 border-emerald-800/60 text-emerald-300'
            : 'bg-rose-950/30 border-rose-800/60 text-rose-300'
        }`}
      >
        {twelfthSpotAvailable ? (
          <CheckCircle2 className="w-4 h-4 text-emerald-400 shrink-0 mt-0.5" />
        ) : (
          <AlertTriangle className="w-4 h-4 text-rose-400 shrink-0 mt-0.5" />
        )}
        <div className="space-y-0.5">
          <div className="font-bold text-slate-100 flex items-center justify-between">
            <span>
              {twelfthSpotAvailable
                ? '12th Player Roster Spot Fully Funded'
                : 'Hard Cap Crunch: 11-Player Roster Restriction'}
            </span>
            <span className="font-mono text-[11px] text-slate-400">
              {hardCapCrunchIndex.toFixed(1)}% Cap Usage
            </span>
          </div>
          <p className="text-[11px] text-slate-400">
            {twelfthSpotAvailable
              ? `Remaining room ($${(capSpace2026 * 1000).toFixed(0)}k) exceeds veteran minimum ($${(twelfthRosterThreshold * 1000).toFixed(0)}k), allowing franchise to carry full 12-woman roster.`
              : `Remaining cap space ($${(capSpace2026 * 1000).toFixed(0)}k) is below the $78,831 minimum salary threshold. Franchise is legally constrained to carry only 11 active players.`}
          </p>
          {corePlayer && corePlayer !== 'Unassigned' && (
            <div className="text-[10px] text-amber-400/90 pt-1 font-mono">
              Core Franchise Designation: <strong>{corePlayer}</strong> (1 Allowed)
            </div>
          )}
        </div>
      </div>
    </div>
  );
};
