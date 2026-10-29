import { Metadata } from 'next';
import { getTeamsData, getDiagnostics, getPostseasonOpsData, getCbtPayrollOverview } from '@/lib/data';
import { RetrospectiveClient } from '@/components/RetrospectiveClient';

export const metadata: Metadata = {
  title: '2026 Season Retrospective & Calibration Audit | MLB Analytics',
  description:
    'Full 2026 MLB season debrief evaluating Milwaukee Brewers championship metrics, walk-forward Brier scores, model variant accuracy, and payroll efficiency.',
};

export default function RetrospectivePage() {
  const teams = getTeamsData();
    const diagnostics = getDiagnostics();
  const postseasonOps = getPostseasonOpsData();
  const cbtOverview = getCbtPayrollOverview();

  return (
    <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8 space-y-6">
      <RetrospectiveClient
        teams={teams}
                diagnostics={diagnostics}
        postseasonOps={postseasonOps}
        cbtSheet={cbtOverview}
      />
    </div>
  );
}
