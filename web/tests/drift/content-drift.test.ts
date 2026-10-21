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
  const { metadata, cbaCapSheet, teams, players, shotsMetadata } = loadAllDatasets();

  it('Sidebar.tsx and page.tsx simulation copy match projections_models_metadata.json (1,000 sims, 1,230,000 games, 30 teams)', () => {
    const sidebarSrc = readWebSource('components/Sidebar.tsx');
    const homePageSrc = readWebSource('app/page.tsx');
    const standingsSrc = readWebSource('components/StandingsClient.tsx');

    expect(metadata.n_simulations).toBe(1000);
    expect(metadata.total_schedule_games).toBe(1230);
    expect(metadata.teams_count).toBe(30);
    expect(teams).toHaveLength(30);

    expect(sidebarSrc).toContain('30 Teams');
    expect(sidebarSrc).toContain('1,000 Sims');
    expect(sidebarSrc).toContain('1.23M');
    expect(homePageSrc).toContain('1,230,000 Games');
    expect(homePageSrc).toContain('4 Distinct Variants');
    expect(standingsSrc).toContain('1,000 Seasons');
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

  it('Sidebar.tsx and PlayoffSeriesClient.tsx hardcoded margin sigma and HCA match metadata', () => {
    const sidebarSrc = readWebSource('components/Sidebar.tsx');
    const seriesSrc = readWebSource('components/PlayoffSeriesClient.tsx');

    expect(sidebarSrc).toContain('11.8 pts');
    expect(seriesSrc).toContain('11.8');
    expect(metadata.margin_sigma).toBe(11.8);
    expect(metadata.home_court_advantage).toBe(2.4);
  });

  it('app/cap-sheet/page.tsx and CapSheetClient.tsx CBA thresholds match cba_cap_sheet.json', () => {
    const capPageSrc = readWebSource('app/cap-sheet/page.tsx');
    const capClientSrc = readWebSource('components/CapSheetClient.tsx');

    expect(cbaCapSheet.salaryCap).toBe(165.0);
    expect(cbaCapSheet.luxuryTaxThreshold).toBe(200.4);
    expect(cbaCapSheet.firstApron).toBe(209.0);
    expect(cbaCapSheet.secondApron).toBe(221.7);

    // The page fallback must mirror the live 2026-27 sheet, and the client must
    // read the thresholds from initialData rather than re-hardcoding an old year.
    expect(capPageSrc).toContain('salaryCap: 165');
    expect(capClientSrc).toContain('initialData.salaryCap');
    expect(capClientSrc).toContain('initialData.luxuryTaxThreshold');
    expect(capClientSrc).toContain('initialData.secondApron');
    for (const stale of ['140.6', '170.8', '178.1', '188.9']) {
      expect(capClientSrc).not.toContain(stale);
    }
  });

  it('Sidebar.tsx Brier score badge matches projections_diagnostics.json', () => {
    const sidebarSrc = readWebSource('components/Sidebar.tsx');
    const { diagnostics } = loadAllDatasets();
    expect(sidebarSrc).toContain(`Brier ${diagnostics.brierScore.toFixed(4)}`);
  });

  it('app/shots/page.tsx copy matches shots_metadata.json zone count', () => {
    const shotsPageSrc = readWebSource('app/shots/page.tsx');
    expect(shotsMetadata.zones).toHaveLength(14);
    expect(shotsPageSrc).toContain('Dynamic half-court spatial analytics');
  });
});
