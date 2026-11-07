import React from 'react';
import { Metadata } from 'next';
import Link from 'next/link';
import { Coins, ArrowLeft, ShieldAlert } from 'lucide-react';

export const metadata: Metadata = {
  title: 'CBA Salary Cap Reference (Archived) | WNBA Analytics',
  description:
    'The 2026 WNBA CBA salary cap sheet is currently archived pending integration with verified contract feeds.',
};

export default function CapSheetPage() {
  return (
    <div className="max-w-4xl mx-auto px-4 sm:px-6 lg:px-8 py-16 text-center space-y-6">
      <div className="inline-flex items-center justify-center p-3 bg-amber-500/10 rounded-full border border-amber-500/20 text-amber-400">
        <Coins className="w-8 h-8" />
      </div>
      <div className="space-y-2">
        <div className="inline-flex items-center gap-1.5 px-2.5 py-0.5 rounded-full text-xs font-mono uppercase tracking-wider bg-amber-500/20 text-amber-300 border border-amber-500/30">
          <ShieldAlert className="w-3.5 h-3.5" />
          Page Archived Pending Live Data
        </div>
        <h1 className="text-3xl font-bold text-white tracking-tight">CBA Cap Sheet Archived</h1>
        <p className="text-slate-400 max-w-xl mx-auto text-sm leading-relaxed">
          This feature has been archived pending integration with official WNBA contract feeds and verified payroll databases. Previously published player salary draws have been retired (GitHub issues #128, #140, #141).
        </p>
      </div>
      <div className="pt-4">
        <Link
          href="/"
          className="inline-flex items-center gap-2 px-4 py-2 text-sm font-medium rounded-lg bg-slate-800 hover:bg-slate-700 text-slate-200 border border-slate-700 transition-colors"
        >
          <ArrowLeft className="w-4 h-4" />
          Back to Overview
        </Link>
      </div>
    </div>
  );
}
