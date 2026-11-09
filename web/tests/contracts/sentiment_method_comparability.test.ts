import fs from 'fs';
import path from 'path';
import { describe, it, expect } from 'vitest';
import { DATA_DIR } from '../helpers/datasets';
import type { MediaSentimentPulse, OffseasonMonitorDataset } from '../../lib/offseasonTypes';

/**
 * Issue #171 design decision 6 — guard against silently mixing scoring methods.
 *
 * `MediaSentimentPulseCard` accepts a `trendSlot` prop that nothing currently
 * passes (`OffseasonMonitorClient.tsx` passes only `pulse`), so week-over-week
 * comparison is a latent feature rather than a live one. The risk is the moment
 * somebody wires it up: #171 replaced the syuzhet/bing scorer with
 * sentimentr + udpipe, so any edition published before it landed carries a
 * `meanSentiment` produced by a different instrument. Plotting those as one
 * series would be a chart silently comparing two measurement methods — the same
 * defect shape as #135's seed assumption, displaced into the UI.
 *
 * This suite does NOT require every edition to share one method (history is
 * allowed to contain a method change). It requires that the data stay
 * self-describing, and that anything grouping editions into a comparable series
 * must partition by (method, lexicon, modelVersion).
 */

const DATA_PATH = path.join(DATA_DIR, 'offseason_monitor.json');

function loadDataset(): OffseasonMonitorDataset {
  return JSON.parse(fs.readFileSync(DATA_PATH, 'utf-8')) as OffseasonMonitorDataset;
}

/** The provenance tuple that makes two means comparable at all. */
function comparabilityKey(pulse: MediaSentimentPulse): string {
  return [
    pulse.method ?? 'UNDECLARED',
    pulse.lexicon ?? 'UNDECLARED',
    pulse.modelVersion ?? 'NO_MODEL',
  ].join(' | ');
}

/**
 * The grouping any trend consumer must use. Exported shape mirrors what a
 * future `trendSlot` implementation needs: a series per method, never one
 * series across all editions.
 */
function comparableSeries(
  editions: OffseasonMonitorDataset['editions'],
): Map<string, { weekNumber: number; mean: number }[]> {
  const series = new Map<string, { weekNumber: number; mean: number }[]>();
  for (const ed of editions) {
    const pulse = ed.mediaSentimentPulse;
    if (!pulse || !pulse.available) continue;
    if (typeof pulse.meanSentiment !== 'number') continue;
    const key = comparabilityKey(pulse);
    if (!series.has(key)) series.set(key, []);
    series.get(key)!.push({ weekNumber: ed.weekNumber, mean: pulse.meanSentiment });
  }
  return series;
}

describe('media sentiment pulse: scoring-method comparability (#171)', () => {
  it('every available pulse declares the method and lexicon behind its number', () => {
    const { editions } = loadDataset();
    const available = editions
      .map((e) => e.mediaSentimentPulse)
      .filter((p): p is MediaSentimentPulse => !!p && p.available);

    // A number with no stated provenance is the thing that makes mixing
    // undetectable, so an undeclared method is a contract violation even when
    // only one edition exists.
    for (const pulse of available) {
      expect(typeof pulse.method).toBe('string');
      expect(pulse.method!.length).toBeGreaterThan(0);
      expect(typeof pulse.lexicon).toBe('string');
      expect(pulse.lexicon!.length).toBeGreaterThan(0);
    }
  });

  it('a POS-disambiguated pulse names its pinned model version', () => {
    const { editions } = loadDataset();
    for (const ed of editions) {
      const pulse = ed.mediaSentimentPulse;
      if (!pulse?.available) continue;
      if (!pulse.posDisambiguated) continue;
      // A model bump is a published-value change, so the version has to travel
      // with the number or two editions cannot be told apart.
      expect(typeof pulse.modelVersion).toBe('string');
      expect(pulse.modelVersion!.length).toBeGreaterThan(0);
    }
  });

  it('method and lexicon agree with each other on every edition', () => {
    const { editions } = loadDataset();
    for (const ed of editions) {
      const pulse = ed.mediaSentimentPulse;
      if (!pulse?.available) continue;
      if (pulse.method === 'sentimentr + udpipe') {
        expect(pulse.lexicon).toBe('jockers_rinker');
        expect(pulse.posDisambiguated).toBe(true);
      }
      // The retired scorer must never claim the new scorer's provenance.
      // Note: an edition legitimately still carrying method "syuzhet" is NOT a
      // failure. The shipped Week 1 payload was published under the old scorer
      // and simply recomputes on the next pipeline run; this suite's job is to
      // keep that edition *labelled*, not to demand it be rewritten.
      if (pulse.method === 'syuzhet') {
        expect(pulse.posDisambiguated).not.toBe(true);
        expect(pulse.modelVersion).toBeUndefined();
      }
    }
  });

  it('editions with differing method are not treated as one comparable series', () => {
    const { editions } = loadDataset();

    // Synthesize the mixed-method history this guard exists for: today's data
    // holds a single edition, so asserting only on live data would pass
    // vacuously and keep passing after the defect is introduced.
    const real = editions.find((e) => e.mediaSentimentPulse?.available);
    expect(real).toBeDefined();
    const basePulse = real!.mediaSentimentPulse!;

    const oldMethod: MediaSentimentPulse = {
      ...basePulse,
      meanSentiment: 0.0269,
      method: 'syuzhet',
      lexicon: 'syuzhet + bing',
      posDisambiguated: false,
      modelVersion: undefined,
    };
    const newMethod: MediaSentimentPulse = {
      ...basePulse,
      meanSentiment: 0.059,
      method: 'sentimentr + udpipe',
      lexicon: 'jockers_rinker',
      posDisambiguated: true,
      modelVersion: 'english-ewt-ud-2.5-191206',
    };

    const mixed = [
      { ...real!, weekNumber: 1, mediaSentimentPulse: oldMethod },
      { ...real!, weekNumber: 2, mediaSentimentPulse: newMethod },
    ];

    const series = comparableSeries(mixed as OffseasonMonitorDataset['editions']);

    // Two methods => two series. A single series here would mean a trend line
    // plotting 0.0269 and 0.0590 as if one instrument produced both.
    expect(series.size).toBe(2);
    for (const points of series.values()) {
      expect(points).toHaveLength(1);
    }
    expect(comparabilityKey(oldMethod)).not.toBe(comparabilityKey(newMethod));

    // Same method but a different pinned model is also not comparable.
    const bumpedModel: MediaSentimentPulse = {
      ...newMethod,
      modelVersion: 'english-ewt-ud-2.6-999999',
    };
    expect(comparabilityKey(newMethod)).not.toBe(comparabilityKey(bumpedModel));
  });

  it('editions sharing full provenance do form a single comparable series', () => {
    const { editions } = loadDataset();
    const real = editions.find((e) => e.mediaSentimentPulse?.available);
    expect(real).toBeDefined();
    const pulse = real!.mediaSentimentPulse!;

    const sameMethod = [
      { ...real!, weekNumber: 1, mediaSentimentPulse: { ...pulse, meanSentiment: 0.05 } },
      { ...real!, weekNumber: 2, mediaSentimentPulse: { ...pulse, meanSentiment: 0.06 } },
    ];
    const series = comparableSeries(sameMethod as OffseasonMonitorDataset['editions']);
    expect(series.size).toBe(1);
    expect([...series.values()][0]).toHaveLength(2);
  });

  it('the trend chart is still unwired, so this guard runs ahead of the consumer', () => {
    // Documents the premise above: if trendSlot ever starts receiving a value,
    // whoever wires it must partition by comparabilityKey() first. If this
    // assertion fails, read the top-of-file comment before "fixing" it.
    const clientPath = path.join(__dirname, '..', '..', 'components', 'OffseasonMonitorClient.tsx');
    const src = fs.readFileSync(clientPath, 'utf-8');
    expect(src).not.toMatch(/trendSlot\s*=/);
  });
});
