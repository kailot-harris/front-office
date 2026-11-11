import { describe, expect, it } from 'vitest';
import { render, screen, fireEvent } from '@testing-library/react';
import { TradeCbaValidator } from '@/components/TradeCbaValidator';
import type { FranchiseCbaProfile } from '@/lib/cbaTypes';

/**
 * Regression coverage for #129:
 *   1. The validator used to accept negative salary input
 *      (`parseFloat(x) || 0` doesn't reject negatives, and the inputs had no
 *      `min` attribute), which could still show "TRADE LEGAL".
 *   2. The validator always applied a flat "125% + $250K" matching rule
 *      regardless of the CBA's actual tiered salary-matching bands below the
 *      first apron. Since those tiers could not be verified against an
 *      authoritative source here, the flat rule is kept but now clearly
 *      labeled as a simplified approximation instead of presented as
 *      fully CBA-accurate.
 */
function taxpayerProfile(overrides: Partial<FranchiseCbaProfile> = {}): FranchiseCbaProfile {
  return {
    teamAbbr: 'AAA',
    teamName: 'Team AAA',
    conference: 'East',
    totalPayroll2026: 205.0, // between luxuryTaxThreshold and firstApron
    totalPayroll2027: 205.0,
    totalPayroll2028: 205.0,
    salaryCap: 165.0,
    luxuryTaxThreshold: 200.4,
    firstApron: 209.0,
    secondApron: 221.7,
    capSpace2026: 0, // not under cap room
    taxSpace2026: -4.6,
    firstApronSpace2026: 4.0,
    secondApronSpace2026: 16.7,
    cbaTier: 'Taxpayer (Below Apron 1)',
    isRepeaterTax: false,
    luxuryTaxBill: 6.0,
    totalFinancialCommitment: 211.0,
    projectedCapSpace2027: 0,
    projectedCapSpace2028: 0,
    ...overrides,
  } as FranchiseCbaProfile;
}

describe('TradeCbaValidator negative-salary clamp and rule labeling (#129)', () => {
  it('never shows TRADE LEGAL when a negative incoming salary is typed', () => {
    render(<TradeCbaValidator profile={taxpayerProfile()} />);

    // Inputs aren't associated to their <label> via `for`/nesting, so query
    // by role: Outgoing is the first number input, Incoming the second.
    const [, incomingInput] = screen.getAllByRole('spinbutton') as HTMLInputElement[];
    expect(incomingInput.min).toBe('0');

    fireEvent.change(incomingInput, { target: { value: '-50' } });

    // A negative incoming salary must clamp to >= 0, never flow through as a
    // negative number. Clamped to 0, this is legitimately legal (0 <= any
    // max) -- that's the correct, non-exploitable outcome -- and no salary
    // violation warning (which would also be computed from the raw negative
    // value) should ever render.
    expect(screen.queryByText(/TRADE LEGAL/i)).not.toBeNull();
    expect(screen.queryByText(/TRADE VIOLATION/i)).toBeNull();
    expect(screen.queryByText(/Salary violation/i)).toBeNull();
  });

  it('clamps a negative outgoing salary input to >= 0 as well', () => {
    render(<TradeCbaValidator profile={taxpayerProfile()} />);
    const [outgoingInput] = screen.getAllByRole('spinbutton') as HTMLInputElement[];
    expect(outgoingInput.min).toBe('0');
    fireEvent.change(outgoingInput, { target: { value: '-25' } });
    // Max legal incoming should reflect outVal clamped to 0 under the flat
    // rule (0 * 1.25 + 0.25 = 0.25), never a negative-derived max.
    expect(screen.getByText('$0.3M')).toBeInTheDocument();
  });

  it('labels the flat matching rule as a simplified approximation for a below-first-apron taxpayer', () => {
    render(<TradeCbaValidator profile={taxpayerProfile()} />);
    expect(screen.getByText(/simplified approximation/i)).toBeInTheDocument();
  });

  it('does not label the dollar-for-dollar rule as an approximation for a first-apron team', () => {
    render(
      <TradeCbaValidator
        profile={taxpayerProfile({ totalPayroll2026: 212.0, cbaTier: 'First Apron Team' })}
      />
    );
    expect(screen.getByText(/100% Dollar-for-Dollar Rule/i)).toBeInTheDocument();
    expect(screen.queryByText(/simplified approximation/i)).not.toBeInTheDocument();
  });
});
