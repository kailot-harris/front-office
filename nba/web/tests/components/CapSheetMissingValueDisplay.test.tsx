import { describe, expect, it } from 'vitest';
import { render, within } from '@testing-library/react';
import { ApronThermometer } from '@/components/ApronThermometer';
import { FranchiseCapTable } from '@/components/FranchiseCapTable';
import { CapSheetClient } from '@/components/CapSheetClient';
import { MISSING_VALUE } from '@/lib/format';
import { loadAllDatasets } from '../helpers/datasets';
import type { FranchiseCbaProfile } from '@/lib/cbaTypes';

/**
 * #113 follow-up: "Do not invent fallback numbers." CapSheetNullFields.test.tsx
 * proves the cap components no longer crash on a null/NaN figure. This suite
 * proves they also no longer *invent* a figure for one: a null or non-finite
 * value must render as the bare em dash, never as "$0.0M", "UFA", "+—" or
 * "-— (Tax)", and never with a sign or a good/bad colour.
 *
 * Data meaning (build_cba_cap_dataset.R + web/public/data/cba_cap_sheet.json):
 * a contract year with no salary is written as 0, and a team under the tax
 * line has luxuryTaxBill 0 and capSpace 0 -- never null. So 0 keeps its
 * "UFA" / "$0.0M" display, and only null / non-finite becomes the em dash.
 */
const { cbaCapSheet } = loadAllDatasets();
const realTeam = cbaCapSheet.teams[0];

const TEAM_NUMERIC_KEYS: (keyof FranchiseCbaProfile)[] = [
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
];

function teamWithMissing(missing: unknown): FranchiseCbaProfile {
  const clone: Record<string, unknown> = { ...(realTeam as unknown as Record<string, unknown>) };
  for (const key of TEAM_NUMERIC_KEYS) clone[key as string] = missing;
  clone.contracts = realTeam.contracts.map((c) => ({
    ...c,
    salary2026: missing,
    salary2027: missing,
    salary2028: missing,
  }));
  return clone as unknown as FranchiseCbaProfile;
}

const INVENTED_TOKENS = ['$0.0M', 'UFA', '+—', '-—'];
const MEANINGFUL_COLOURS = /emerald|amber|orange|rose/;

function inventedTokens(el: HTMLElement): string[] {
  const text = el.textContent || '';
  return INVENTED_TOKENS.filter((t) => text.includes(t));
}

/** The value span rendered right after a label span. */
function valueAfterLabel(container: HTMLElement, label: string): HTMLElement {
  const labelEl = within(container).getByText(label);
  const value = labelEl.nextElementSibling as HTMLElement | null;
  if (!value) throw new Error(`no value element after label "${label}"`);
  return value;
}

const MISSING_CASES: Array<{ label: string; value: unknown }> = [
  { label: 'null', value: null },
  { label: 'NaN', value: NaN },
];

describe.each(MISSING_CASES)('cap figures that are $label show only the em dash (#113)', ({ value }) => {
  const team = teamWithMissing(value);

  it('ApronThermometer headroom pills show only the em dash, unsigned and uncoloured', () => {
    const { container } = render(<ApronThermometer profile={team} />);
    for (const label of ['Cap Space', 'Tax Cushion', '1st Apron Room', '2nd Apron Room']) {
      const el = valueAfterLabel(container, label);
      expect(el.textContent, label).toBe(MISSING_VALUE);
      expect(el.className, label).not.toMatch(MEANINGFUL_COLOURS);
    }
    expect(inventedTokens(container)).toEqual([]);
  });

  it('FranchiseCapTable room figures and future salary cells show only the em dash', () => {
    const { container } = render(<FranchiseCapTable profile={team} />);
    for (const label of ['2027 Room:', '2028 Room:']) {
      const el = valueAfterLabel(container, label);
      expect(el.textContent, label).toBe(MISSING_VALUE);
      expect(el.className, label).not.toMatch(MEANINGFUL_COLOURS);
    }
    const rows = container.querySelectorAll('tbody tr');
    expect(rows.length).toBe(team.contracts.length);
    rows.forEach((row) => {
      const cells = row.querySelectorAll('td');
      expect(cells[2].textContent).toBe(MISSING_VALUE);
      expect(cells[3].textContent).toBe(MISSING_VALUE);
      expect(cells[4].textContent).toBe(MISSING_VALUE);
    });
    expect(inventedTokens(container)).toEqual([]);
  });

  it('CapSheetClient tax bill for the affected team shows only the em dash', () => {
    const initialData = {
      ...cbaCapSheet,
      teams: [team, ...cbaCapSheet.teams.slice(1)],
    };
    const { container } = render(<CapSheetClient initialData={initialData} />);
    const teamName = within(container).getAllByText(team.teamName)[0];
    const row = teamName.closest('div.cursor-pointer') as HTMLElement;
    expect(row).not.toBeNull();
    const bill = valueAfterLabel(row, 'Tax Bill');
    expect(bill.textContent).toBe(MISSING_VALUE);
    expect(bill.className).not.toMatch(MEANINGFUL_COLOURS);
  });
});

describe('finite cap figures keep their existing display (#113)', () => {
  it('0 cap space / 0 tax bill render "$0.0M" and a 0 contract year renders "UFA"', () => {
    const zeroTeam: FranchiseCbaProfile = {
      ...realTeam,
      capSpace2026: 0,
      luxuryTaxBill: 0,
      projectedCapSpace2027: 0,
      projectedCapSpace2028: 0,
      taxSpace2026: -12.34,
      firstApronSpace2026: 0,
      secondApronSpace2026: -1,
      contracts: [{ ...realTeam.contracts[0], salary2026: 10, salary2027: 0, salary2028: 0 }],
    };

    const thermo = render(<ApronThermometer profile={zeroTeam} />).container;
    expect(valueAfterLabel(thermo, 'Cap Space').textContent).toBe('$0.0M');
    expect(valueAfterLabel(thermo, 'Tax Cushion').textContent).toBe('-$12.3M (Tax)');
    expect(valueAfterLabel(thermo, 'Tax Cushion').className).toContain('text-amber-400');
    expect(valueAfterLabel(thermo, '1st Apron Room').textContent).toBe('+$0.0M');
    expect(valueAfterLabel(thermo, '1st Apron Room').className).toContain('text-emerald-400');
    expect(valueAfterLabel(thermo, '2nd Apron Room').textContent).toBe('-$1.0M (Breached)');

    const table = render(<FranchiseCapTable profile={zeroTeam} />).container;
    expect(valueAfterLabel(table, '2027 Room:').textContent).toBe('$0.0M');
    expect(valueAfterLabel(table, '2028 Room:').textContent).toBe('$0.0M');
    const cells = table.querySelectorAll('tbody tr td');
    expect(cells[2].textContent).toBe('$10.0M');
    expect(cells[3].textContent).toBe('UFA');
    expect(cells[4].textContent).toBe('UFA');

    const client = render(
      <CapSheetClient initialData={{ ...cbaCapSheet, teams: [zeroTeam, ...cbaCapSheet.teams.slice(1)] }} />,
    ).container;
    const row = within(client).getAllByText(zeroTeam.teamName)[0].closest('div.cursor-pointer') as HTMLElement;
    expect(valueAfterLabel(row, 'Tax Bill').textContent).toBe('$0.0M');
  });

  it('positive figures keep their sign and colour', () => {
    const richTeam: FranchiseCbaProfile = {
      ...realTeam,
      capSpace2026: 5.25,
      taxSpace2026: 3,
      projectedCapSpace2027: 7.5,
      luxuryTaxBill: 20.06,
    };
    const thermo = render(<ApronThermometer profile={richTeam} />).container;
    expect(valueAfterLabel(thermo, 'Cap Space').textContent).toBe('+$5.3M');
    expect(valueAfterLabel(thermo, 'Cap Space').className).toContain('text-emerald-400');
    expect(valueAfterLabel(thermo, 'Tax Cushion').textContent).toBe('+$3.0M');
    const table = render(<FranchiseCapTable profile={richTeam} />).container;
    expect(valueAfterLabel(table, '2027 Room:').textContent).toBe('+$7.5M');
    const client = render(
      <CapSheetClient initialData={{ ...cbaCapSheet, teams: [richTeam, ...cbaCapSheet.teams.slice(1)] }} />,
    ).container;
    const row = within(client).getAllByText(richTeam.teamName)[0].closest('div.cursor-pointer') as HTMLElement;
    const bill = valueAfterLabel(row, 'Tax Bill');
    expect(bill.textContent).toBe('$20.1M');
    expect(bill.className).toContain('text-amber-400');
  });
});
