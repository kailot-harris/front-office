/**
 * Layer 5 — Content drift: compares hardcoded TSX UI constants to live datasets.
 */
import fs from 'fs';
import path from 'path';
import { describe, it, expect } from 'vitest';
import { WEB_ROOT, loadAllDatasets } from '../helpers/datasets';

function readWebSource(relPath: string): string {
  return fs.readFileSync(path.join(WEB_ROOT, relPath), 'utf-8');
}

describe('UI copy & fallback constants vs live JSON data drift', () => {
  const { metadata, diagnostics, cbtSheet, teams, players } = loadAllDatasets();

  it('Sidebar.tsx and page.tsx simulation copy match projections_models_metadata.json (1,000 sims, 2,430,000 games, 30 clubs, 1,279 players)', () => {
    const sidebarSrc = readWebSource('components/Sidebar.tsx');
    const homePageSrc = readWebSource('app/page.tsx');

    expect(metadata.n_simulations).toBe(1000);
    expect(metadata.postseason_sims).toBe(10000);
    expect(metadata.total_schedule_games).toBe(2430);
    expect(metadata.teams_count).toBe(30);
    expect(teams).toHaveLength(30);
    expect(players).toHaveLength(metadata.players_count);

    expect(sidebarSrc).toContain('30 Clubs');
    expect(sidebarSrc).toContain('10K / 1K Sims');
    expect(sidebarSrc).toContain('2,430 Games');
    expect(sidebarSrc).toContain(`Batters (${metadata.batters_count}) & Pitchers (${metadata.pitchers_count})`);
    expect(homePageSrc).toContain('2,430,000 Games');
    expect(homePageSrc).toContain('4 Distinct Variants');
  });

  it('VariantsClient.tsx model variant weight badges match projections_models_metadata.json weights', () => {
    const variantsSrc = readWebSource('components/VariantsClient.tsx');

    const wBu = Math.round((metadata.models.variant_bottom_up.weight ?? 0) * 100);
    const wRapm = Math.round((metadata.models.variant_rapm.weight ?? 0) * 100);
    const wSf = Math.round((metadata.models.variant_shot_fatigue.weight ?? 0) * 100);
    const wEmb = Math.round((metadata.models.variant_embeddings.weight ?? 0) * 100);

    expect(variantsSrc).toContain(`Weight ${wBu}%`);
    expect(variantsSrc).toContain(`Weight ${wRapm}%`);
    expect(variantsSrc).toContain(`Weight ${wSf}%`);
    expect(variantsSrc).toContain(`Weight ${wEmb}%`);
  });

  it('Sidebar.tsx Brier score badge matches projections_diagnostics.json', () => {
    const sidebarSrc = readWebSource('components/Sidebar.tsx');
    expect(sidebarSrc).toContain(`Brier ${diagnostics.brierScore.toFixed(4)}`);
  });

  it('Sidebar.tsx CBT threshold badge matches cbt_payroll_sheet.json baseThreshold', () => {
    const sidebarSrc = readWebSource('components/Sidebar.tsx');
    expect(cbtSheet.baseThreshold).toBe(244.0);
    expect(sidebarSrc).toContain(`CBT $${Math.round(cbtSheet.baseThreshold)}M`);
  });
});
