import { describe, expect, it } from 'vitest';
import { render } from '@testing-library/react';
import { ApronThermometer } from '@/components/ApronThermometer';
import { FranchiseCapTable } from '@/components/FranchiseCapTable';
import { CapSheetClient } from '@/components/CapSheetClient';
import { loadAllDatasets } from '../helpers/datasets';
import type { FranchiseCbaProfile } from '@/lib/cbaTypes';

/**
 * #113: NBA cap pages crashed on a single null number. Cap figures were
 * formatted with `value.toFixed()` with no guard; a null in the published
 * JSON (how R writes NA) threw during render and blanked the page. This is
 * the regression guard standing in for the aggregator's component fuzzer
 * (not available inside this repo's worktree): it clones the real cba_cap_sheet
 * payload and nulls out every numeric field ApronThermometer, FranchiseCapTable
 * and CapSheetClient render, then asserts the components still mount with no
 * "NaN" / "Infinity" / "undefined" text anywhere in the output.
 */
const { cbaCapSheet } = loadAllDatasets();

function nullOutNumbers<T extends object>(obj: T, keys: (keyof T)[]): T {
  const clone: Record<string, unknown> = { ...(obj as Record<string, unknown>) };
  for (const key of keys) {
    clone[key as string] = null;
  }
  return clone as unknown as T;
}

const realTeam = cbaCapSheet.teams[0];

const nulledTeam: FranchiseCbaProfile = {
  ...nullOutNumbers(realTeam, [
    'totalPayroll2026',
    'totalPayroll2027',
    'totalPayroll2028',
    'salaryCap',
    'luxuryTaxThreshold',
    'firstApron',
    'secondApron',
    'capSpace2026',
    'taxSpace2026',
    'firstApronSpace2026',
    'secondApronSpace2026',
    'luxuryTaxBill',
    'totalFinancialCommitment',
    'projectedCapSpace2027',
    'projectedCapSpace2028',
  ]),
  contracts: realTeam.contracts.map((c) =>
    nullOutNumbers(c, ['salary2026', 'salary2027', 'salary2028']),
  ),
};

function textHasForbiddenTokens(container: HTMLElement): string[] {
  const text = container.textContent || '';
  return ['NaN', 'Infinity', 'undefined'].filter((token) => text.includes(token));
}

describe('cap-sheet components survive null numeric fields (#113)', () => {
  it('ApronThermometer does not crash and renders no NaN/Infinity/undefined', () => {
    const { container } = render(<ApronThermometer profile={nulledTeam} />);
    expect(textHasForbiddenTokens(container)).toEqual([]);
  });

  it('FranchiseCapTable does not crash and renders no NaN/Infinity/undefined', () => {
    const { container } = render(<FranchiseCapTable profile={nulledTeam} />);
    expect(textHasForbiddenTokens(container)).toEqual([]);
  });

  it('CapSheetClient does not crash and renders no NaN/Infinity/undefined with a nulled team in the list', () => {
    const initialData = {
      ...cbaCapSheet,
      teams: [nulledTeam, ...cbaCapSheet.teams.slice(1)],
    };
    const { container } = render(<CapSheetClient initialData={initialData} />);
    expect(textHasForbiddenTokens(container)).toEqual([]);
  });
});
