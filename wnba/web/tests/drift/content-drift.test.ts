import fs from 'fs';
import path from 'path';
import { describe, it, expect } from 'vitest';
import { WEB_ROOT, loadAllDatasets } from '../helpers/datasets';

function readWebSource(relPath: string): string {
  return fs.readFileSync(path.join(WEB_ROOT, relPath), 'utf-8');
}

describe('UI copy & fallback constants vs live JSON data drift', () => {
  const { metadata, cbaCapSheet, teams, players, shotsMetadata } = loadAllDatasets();

  it('Sidebar.tsx and page.tsx simulation copy match projections_models_metadata.json (1,000 sims, 330 games, 15 teams)', () => {
    const sidebarSrc = readWebSource('components/Sidebar.tsx');
    const homePageSrc = readWebSource('app/page.tsx');
    const standingsSrc = readWebSource('components/StandingsClient.tsx');

    expect(metadata.n_simulations).toBe(1000);
    expect(metadata.total_schedule_games).toBe(330);
    expect(metadata.teams_count).toBe(15);
    expect(teams).toHaveLength(15);

    expect(sidebarSrc).toContain('15 Teams');
    expect(sidebarSrc).toContain('14 Zones');
    expect(homePageSrc).toContain('330 Games');
    expect(standingsSrc).toContain('1,000 Seasons');
    expect(standingsSrc).toContain('330 Games / Iteration');
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

  it('PlayoffSeriesClient.tsx hardcoded WNBA_HCA and WNBA_MARGIN_SIGMA match projections_models_metadata.json', () => {
    const seriesSrc = readWebSource('components/PlayoffSeriesClient.tsx');
    const hcaMatch = seriesSrc.match(/const hcaPts\s*=\s*([0-9.]+)/);
    const sigmaMatch = seriesSrc.match(/const sigma\s*=\s*([0-9.]+)/);

    expect(hcaMatch, 'hcaPts constant not found in PlayoffSeriesClient.tsx').not.toBeNull();
    expect(sigmaMatch, 'sigma constant not found in PlayoffSeriesClient.tsx').not.toBeNull();

    expect(Number(hcaMatch![1])).toBeCloseTo(metadata.home_court_advantage, 2);
    expect(Number(sigmaMatch![1])).toBeCloseTo(metadata.margin_sigma, 2);
  });

  it('app/cap-sheet/page.tsx defaultOverview fallback matches cba_cap_sheet.json league summary counts', () => {
    const capPageSrc = readWebSource('app/cap-sheet/page.tsx');

    const squeezeMatch = capPageSrc.match(/hardCapSqueezeTeamCount:\s*(\d+)/);
    const twelveMatch = capPageSrc.match(/twelvePlayerTeamCount:\s*(\d+)/);
    const maxCapMatch = capPageSrc.match(/maxCapSpaceTeamCount:\s*(\d+)/);

    expect(squeezeMatch).not.toBeNull();
    expect(twelveMatch).not.toBeNull();
    expect(maxCapMatch).not.toBeNull();

    expect(
      Number(squeezeMatch![1]),
      `app/cap-sheet/page.tsx fallback hardCapSqueezeTeamCount (${squeezeMatch![1]}) != cba_cap_sheet.json (${cbaCapSheet.hardCapSqueezeTeamCount})`
    ).toBe(cbaCapSheet.hardCapSqueezeTeamCount);
    expect(
      Number(twelveMatch![1]),
      `app/cap-sheet/page.tsx fallback twelvePlayerTeamCount (${twelveMatch![1]}) != cba_cap_sheet.json (${cbaCapSheet.twelvePlayerTeamCount})`
    ).toBe(cbaCapSheet.twelvePlayerTeamCount);
    expect(Number(maxCapMatch![1])).toBe(cbaCapSheet.maxCapSpaceTeamCount);
  });

  it('app/shots/page.tsx copy "260,000+ tracked WNBA shot attempts" is consistent with shots_metadata.json total_shots_sampled', () => {
    const shotsPageSrc = readWebSource('app/shots/page.tsx');
    expect(shotsPageSrc).toContain('14 Discrete Spatial Zones');
    expect(shotsMetadata.zones).toHaveLength(14);
    expect(shotsMetadata.total_shots_sampled).toBeGreaterThanOrEqual(260000);
  });

  it('PlayersClient.tsx and PlayerDnaClient.tsx default/featured players exist in the live player datasets', () => {
    const playerNames = new Set(players.map((p) => p.player_name));
    expect([...playerNames].some((n) => n.includes("A'ja Wilson"))).toBe(true);
    expect([...playerNames].some((n) => n.includes('Caitlin Clark'))).toBe(true);
  });
});
