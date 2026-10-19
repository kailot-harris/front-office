'use client';

import React, { useState } from 'react';
import { FranchiseCbaProfile } from '@/lib/cbaTypes';
import { CheckCircle2, AlertTriangle, Calculator } from 'lucide-react';

interface TradeCbaValidatorProps {
  profile: FranchiseCbaProfile;
}

export const TradeCbaValidator: React.FC<TradeCbaValidatorProps> = ({ profile }) => {
  const [outgoingSalary, setOutgoingSalary] = useState<string>('25.0');
  const [incomingSalary, setIncomingSalary] = useState<string>('26.5');
  const [isAggregating, setIsAggregating] = useState<boolean>(false);
  const [sendingCash, setSendingCash] = useState<boolean>(false);

  const outVal = parseFloat(outgoingSalary) || 0;
  const inVal = parseFloat(incomingSalary) || 0;

  const isSecondApron = profile.totalPayroll2026 > profile.secondApron;
  const isFirstApron = profile.totalPayroll2026 > profile.firstApron;
  const isUnderCap = profile.capSpace2026 > 0;

  // Max incoming salary allowed
  let maxIncomingAllowed = 0;
  let matchingPctLabel = '';

  if (isUnderCap) {
    maxIncomingAllowed = outVal + profile.capSpace2026;
    matchingPctLabel = 'Absorb into Cap Space';
  } else if (isSecondApron || isFirstApron) {
    maxIncomingAllowed = outVal * 1.0;
    matchingPctLabel = '100% Dollar-for-Dollar Rule';
  } else {
    maxIncomingAllowed = outVal * 1.25 + 0.25;
    matchingPctLabel = '125% + $250K Rule';
  }

  // Legality checks
  const failsSalaryMatch = inVal > maxIncomingAllowed;
  const failsAggregation = isSecondApron && isAggregating;
  const failsCash = isSecondApron && sendingCash;

  const isLegal = !failsSalaryMatch && !failsAggregation && !failsCash;

  return (
    <div className="bg-slate-950/70 border border-slate-800 rounded-xl p-4 space-y-4">
      <div className="flex items-center justify-between pb-2 border-b border-slate-800">
        <div className="flex items-center gap-2">
          <Calculator className="w-4 h-4 text-indigo-400" />
          <h4 className="text-xs font-bold text-white tracking-tight">
            CBA Trade Machine & Salary Matching Validator
          </h4>
        </div>
        <span
          className={`px-2 py-0.5 rounded-full text-[10px] font-mono font-bold flex items-center gap-1 border ${
            isLegal
              ? 'bg-emerald-500/10 text-emerald-400 border-emerald-500/30'
              : 'bg-rose-500/10 text-rose-400 border-rose-500/30'
          }`}
        >
          {isLegal ? <CheckCircle2 className="w-3 h-3" /> : <AlertTriangle className="w-3 h-3" />}
          {isLegal ? 'TRADE LEGAL' : 'TRADE VIOLATION'}
        </span>
      </div>

      {/* Input Fields */}
      <div className="grid grid-cols-2 gap-3 text-xs">
        <div>
          <label className="text-[10px] text-slate-400 block mb-1 font-mono">
            Outgoing Salary ($M)
          </label>
          <input
            type="number"
            step="0.5"
            value={outgoingSalary}
            onChange={(e) => setOutgoingSalary(e.target.value)}
            className="w-full bg-slate-900 border border-slate-800 rounded-lg px-2.5 py-1.5 text-xs text-white font-mono focus:outline-none focus:border-indigo-500"
          />
        </div>
        <div>
          <label className="text-[10px] text-slate-400 block mb-1 font-mono">
            Incoming Salary ($M)
          </label>
          <input
            type="number"
            step="0.5"
            value={incomingSalary}
            onChange={(e) => setIncomingSalary(e.target.value)}
            className="w-full bg-slate-900 border border-slate-800 rounded-lg px-2.5 py-1.5 text-xs text-white font-mono focus:outline-none focus:border-indigo-500"
          />
        </div>
      </div>

      {/* Toggles for Second Apron specific rules */}
      <div className="grid grid-cols-2 gap-2 text-[11px]">
        <label className="flex items-center gap-2 cursor-pointer text-slate-300">
          <input
            type="checkbox"
            checked={isAggregating}
            onChange={(e) => setIsAggregating(e.target.checked)}
            className="rounded bg-slate-900 border-slate-700 text-indigo-600 focus:ring-0"
          />
          <span>Aggregating 2+ Outgoing Players</span>
        </label>
        <label className="flex items-center gap-2 cursor-pointer text-slate-300">
          <input
            type="checkbox"
            checked={sendingCash}
            onChange={(e) => setSendingCash(e.target.checked)}
            className="rounded bg-slate-900 border-slate-700 text-indigo-600 focus:ring-0"
          />
          <span>Sending Cash Considerations</span>
        </label>
      </div>

      {/* Regulatory Diagnostic Feedback */}
      <div className="p-2.5 rounded-lg bg-slate-900/80 border border-slate-800 text-[11px] space-y-1">
        <div className="flex items-center justify-between">
          <span className="text-slate-400">Rule Applied:</span>
          <span className="font-mono font-bold text-amber-400">{matchingPctLabel}</span>
        </div>
        <div className="flex items-center justify-between">
          <span className="text-slate-400">Max Legal Incoming:</span>
          <span className="font-mono font-bold text-white">${maxIncomingAllowed.toFixed(1)}M</span>
        </div>

        {failsSalaryMatch && (
          <div className="text-rose-400 text-[10px] pt-1 border-t border-slate-800 font-medium">
            ⚠ Salary violation: Incoming exceeds maximum allowed by ${(inVal - maxIncomingAllowed).toFixed(1)}M.
          </div>
        )}
        {failsAggregation && (
          <div className="text-rose-400 text-[10px] pt-1 border-t border-slate-800 font-medium">
            ⚠ CBA Second Apron restriction: Cannot combine/aggregate two or more player salaries.
          </div>
        )}
        {failsCash && (
          <div className="text-rose-400 text-[10px] pt-1 border-t border-slate-800 font-medium">
            ⚠ CBA Second Apron restriction: Sending cash in trades is strictly prohibited.
          </div>
        )}
      </div>
    </div>
  );
};
