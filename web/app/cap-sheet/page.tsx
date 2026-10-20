import React from 'react';
import { getCbtPayrollOverview } from '@/lib/data';
import { CapSheetClient } from '@/components/CapSheetClient';

export const metadata = {
  title: 'MLB Luxury Tax (CBT) & Payroll Architect | MLB Analytics',
  description:
    'Comprehensive 2026 Competitive Balance Tax (CBT) thresholds, repeater penalties, luxury tax surcharge calculation, and 3-year franchise payroll commitments across all 30 MLB clubs.',
};

export default function CapSheetPage() {
  const overview = getCbtPayrollOverview();

  return (
    <div className="min-h-screen bg-surface text-slate-100 p-4 md:p-8">
      <CapSheetClient overview={overview} />
    </div>
  );
}
