import React from 'react';
import { Metadata } from 'next';
import fs from 'fs';
import path from 'path';
import {
  OffseasonTransaction,
  OffseasonTeamProfile,
  OffseasonDraftProspect,
} from '@/lib/offseasonTypes';
import { OffseasonClient } from '@/components/OffseasonClient';

export const metadata: Metadata = {
  title: 'Offseason Moves & Expansion Hub | WNBA Analytics',
  description:
    'Track 2026 WNBA offseason transactions, trades, roster grades for all 15 franchises, and the 2026 Draft Board.',
};

async function getOffseasonData(): Promise<{
  transactions: OffseasonTransaction[];
  teams: OffseasonTeamProfile[];
  draft: OffseasonDraftProspect[];
}> {
  try {
    const dataDir = path.join(process.cwd(), 'public', 'data');
    const txPath = path.join(dataDir, 'offseason_transactions.json');
    const teamsPath = path.join(dataDir, 'offseason_teams.json');
    const draftPath = path.join(dataDir, 'offseason_draft.json');

    const transactions = fs.existsSync(txPath)
      ? JSON.parse(fs.readFileSync(txPath, 'utf8'))
      : [];
    const teams = fs.existsSync(teamsPath)
      ? JSON.parse(fs.readFileSync(teamsPath, 'utf8'))
      : [];
    const draft = fs.existsSync(draftPath)
      ? JSON.parse(fs.readFileSync(draftPath, 'utf8'))
      : [];

    return { transactions, teams, draft };
  } catch (err) {
    console.error('Failed to load offseason data:', err);
    return { transactions: [], teams: [], draft: [] };
  }
}

export default async function OffseasonPage() {
  const { transactions, teams, draft } = await getOffseasonData();

  return (
    <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
      <OffseasonClient
        initialTransactions={transactions}
        initialTeams={teams}
        initialDraft={draft}
      />
    </div>
  );
}
