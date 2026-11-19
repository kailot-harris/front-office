/**
 * Contract tests for ClutchProfile schema compatibility (#168):
 * accepts both new `fourthDownConversionRate` payloads (including `null`
 * when 0 4th-down plays occur) and legacy `fourthDownAggressiveness` payloads.
 */
import { describe, expect, it } from 'vitest';
import { clutchProfileSchema } from '../contracts/schemas';
import { clutch } from '../helpers/datasets';

describe('clutchProfileSchema #168 backward compatibility', () => {
  const sample = clutch().find((p) => p.provenance === 'REAL_CURRENT_SEASON')!;
  const { fourthDownAggressiveness: _legacy, fourthDownConversionRate: _conv, ...withoutFourth } = sample;

  it('accepts new builds emitting fourthDownConversionRate (number or null)', () => {
    expect(
      clutchProfileSchema.safeParse({ ...withoutFourth, fourthDownConversionRate: 66.7 }).success,
    ).toBe(true);
    expect(
      clutchProfileSchema.safeParse({ ...withoutFourth, fourthDownConversionRate: null }).success,
    ).toBe(true);
  });

  it('accepts committed pre-rebuild payloads carrying fourthDownAggressiveness', () => {
    expect(
      clutchProfileSchema.safeParse({ ...withoutFourth, fourthDownAggressiveness: 50 }).success,
    ).toBe(true);
    expect(
      clutchProfileSchema.safeParse({ ...withoutFourth, fourthDownAggressiveness: null }).success,
    ).toBe(true);
  });

  it('rejects payloads missing both fourth-down fields or carrying unexpected keys', () => {
    expect(clutchProfileSchema.safeParse(withoutFourth).success).toBe(false);
    expect(
      clutchProfileSchema.safeParse({
        ...withoutFourth,
        fourthDownConversionRate: 50,
        unexpectedField: 123,
      }).success,
    ).toBe(false);
  });
});
