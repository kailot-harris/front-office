import { getTeamsData, getDiagnostics, getCapSheetData, getPlayoffBracketData } from '@/lib/data';
import { RetrospectiveClient } from '@/components/RetrospectiveClient';

export const metadata = {
  title: '2026 Season Retrospective & Championship Audit | WNBA Analytics',
  description:
    'Comprehensive model audit, championship resolution, CBA cap efficiency, and predictive variant benchmarks across the 2026 season.',
};

export default function RetrospectivePage() {
  const teams = getTeamsData();
  const diagnostics = getDiagnostics();
  const capSheet = getCapSheetData();
  const bracketData = getPlayoffBracketData();

  return (
    <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8 space-y-6">
      <RetrospectiveClient
        teams={teams}
        diagnostics={diagnostics}
        capSheet={capSheet ?? undefined}
        bracketData={bracketData}
      />
    </div>
  );
}
