import { getTeamsData, getDiagnostics, getPlayoffBracketData } from '@/lib/data';
import { RetrospectiveClient } from '@/components/RetrospectiveClient';

export const metadata = {
  title: '2026 Season Retrospective & Championship Audit | WNBA Analytics',
  description:
    'Comprehensive model audit, championship resolution, and predictive variant benchmarks across the 2026 season.',
};

export default function RetrospectivePage() {
  const teams = getTeamsData();
  const diagnostics = getDiagnostics();
  const bracketData = getPlayoffBracketData();

  return (
    <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8 space-y-6">
      <RetrospectiveClient
        teams={teams}
        diagnostics={diagnostics}
        bracketData={bracketData}
      />
    </div>
  );
}
