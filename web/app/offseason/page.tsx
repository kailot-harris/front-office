import fs from 'fs';
import path from 'path';
import { Metadata } from 'next';
import { OffseasonTransaction, TeamOffseasonProfile, RookieDraftProfile } from '@/lib/offseasonTypes';
import { OffseasonClient } from '@/components/OffseasonClient';

export const metadata: Metadata = {
  title: '2026-2027 Offseason Moves & Transaction Analytics | NBA Projections',
  description:
    'Comprehensive 2026-2027 offseason roster analysis treating trades, free agent signings, and draft picks as a quantitative space to analyze bottom-up rotation net rating swings, returning minutes continuity, and projected win trajectories.',
};

function getOffseasonTransactions(): OffseasonTransaction[] {
  const filePath = path.join(process.cwd(), 'public', 'data', 'offseason_transactions.json');
  if (!fs.existsSync(filePath)) return [];
  const content = fs.readFileSync(filePath, 'utf-8');
  return JSON.parse(content) as OffseasonTransaction[];
}

function getTeamOffseasonProfiles(): TeamOffseasonProfile[] {
  const filePath = path.join(process.cwd(), 'public', 'data', 'offseason_teams.json');
  if (!fs.existsSync(filePath)) return [];
  const content = fs.readFileSync(filePath, 'utf-8');
  return JSON.parse(content) as TeamOffseasonProfile[];
}

function getDraftProspects(): RookieDraftProfile[] {
  const filePath = path.join(process.cwd(), 'public', 'data', 'offseason_draft.json');
  if (!fs.existsSync(filePath)) return [];
  const content = fs.readFileSync(filePath, 'utf-8');
  return JSON.parse(content) as RookieDraftProfile[];
}

// Note: the full player projections dataset (projections_season_players.json, ~325 KB)
// is intentionally NOT read or passed here. It's only needed by OffseasonClient's Move
// Machine sandbox tab, which fetches it client-side on demand from /data/*.json instead
// of having it serialized into this page's initial HTML (#134).

export default function OffseasonPage() {
  const transactions = getOffseasonTransactions();
  const teams = getTeamOffseasonProfiles();
  const draftProspects = getDraftProspects();

  return (
    <OffseasonClient
      transactions={transactions}
      teams={teams}
      draftProspects={draftProspects}
    />
  );
}
