import { describe, expect, it } from 'vitest';
import { render, screen } from '@testing-library/react';
import React from 'react';
import { MediaSentimentPulseCard } from '../../components/MediaSentimentPulseCard';
import type { MediaSentimentPulse } from '../../lib/offseasonTypes';

/**
 * Shape copied from the Week 1 (2026-11-08) edition in
 * `web/public/data/offseason_monitor.json`, trimmed to the fields the card reads.
 */
function availablePulse(overrides: Partial<MediaSentimentPulse> = {}): MediaSentimentPulse {
  return {
    available: true,
    reason: null,
    articleCount: 47,
    beatItemsSeen: 70,
    offTopicExcluded: 23,
    meanSentiment: 0.0269,
    scrapedCount: 25,
    fallbackCount: 22,
    mostPositive: {
      headline: "Reese proud of Dream's breakthrough, confident team will 'be back'",
      score: 0.0622,
      sourceId: 'espn_wnba_beat',
      url: 'https://www.espn.com/wnba/story/_/id/50344895/',
    },
    mostNegative: {
      headline: 'The Atlanta Dream’s 13-Year Road to Redemption',
      score: 0.0043,
      sourceId: 'winsidr',
      url: 'https://winsidr.com/2026/10/the-atlanta-dreams-13-year-road-to-redemption/',
    },
    extremesMinWords: 40,
    extremesFloorApplied: true,
    extremesEligibleCount: 27,
    teamNamesMasked: true,
    wordBreakdown: {
      available: true,
      reason: null,
      positive: [{ word: 'win', n: 69 }],
      negative: [{ word: 'injury', n: 21 }],
      matchedWords: 1938,
    },
    lexicon: 'syuzhet + bing',
    method: 'syuzhet',
    ...overrides,
  };
}

describe('MediaSentimentPulseCard — available state', () => {
  it('renders the signed mean, both extremes and the off-topic exclusion count', () => {
    render(<MediaSentimentPulseCard pulse={availablePulse()} />);

    expect(screen.getByTestId('media-sentiment-mean').textContent).toBe('+0.0269');
    expect(screen.getByText(/per word/i)).toBeTruthy();

    expect(screen.getByText(/Reese proud of Dream/)).toBeTruthy();
    expect(screen.getByText('+0.0622')).toBeTruthy();
    expect(screen.getByText(/13-Year Road to Redemption/)).toBeTruthy();
    expect(screen.getByText('+0.0043')).toBeTruthy();

    // The relevance filter added in #156 must stay visible: the beat feeds are
    // not WNBA-only, and this count is the evidence the filter is working.
    expect(screen.getByTestId('media-sentiment-offtopic').textContent).toMatch(
      /23 of 70 ingested beat items excluded as off-topic/
    );
  });

  it('links each extreme to its url in a new tab and states the methodology', () => {
    render(<MediaSentimentPulseCard pulse={availablePulse()} />);

    const link = screen.getByRole('link', { name: /Reese proud of Dream/ });
    expect(link.getAttribute('href')).toContain('espn.com');
    expect(link.getAttribute('target')).toBe('_blank');

    expect(screen.getByText(/Franchise names masked before scoring/)).toBeTruthy();
    expect(screen.getByText(/syuzhet \+ bing/)).toBeTruthy();
    expect(
      screen.getByText(/Extremes drawn from the 27 articles of at least 40 words/)
    ).toBeTruthy();
    expect(screen.getByText(/47 articles scored/)).toBeTruthy();
  });

  it('shows the word-breakdown reason instead of chips when it is unavailable', () => {
    render(
      <MediaSentimentPulseCard
        pulse={availablePulse({
          wordBreakdown: {
            available: false,
            reason: 'bing lexicon not installed',
            positive: [],
            negative: [],
          },
        })}
      />
    );

    expect(screen.getByText(/bing lexicon not installed/)).toBeTruthy();
    expect(screen.queryByText(/Top positive words/)).toBeNull();
  });

  it('omits the off-topic line when nothing was excluded', () => {
    render(<MediaSentimentPulseCard pulse={availablePulse({ offTopicExcluded: 0 })} />);
    expect(screen.queryByTestId('media-sentiment-offtopic')).toBeNull();
  });
});

describe('MediaSentimentPulseCard — negative-extreme label flips at the sign boundary', () => {
  // Mirrors tools/offseason/render_memo.R:333. `score >= 0` is inclusive on
  // purpose: an all-positive week has no "most negative" story.
  const cases: [number, string, string][] = [
    [0.0043, 'Least positive', 'Most negative'],
    [0, 'Least positive', 'Most negative'],
    [-0.021, 'Most negative', 'Least positive'],
  ];

  it.each(cases)('score %s renders "%s"', (score, expected, notExpected) => {
    render(
      <MediaSentimentPulseCard
        pulse={availablePulse({
          mostNegative: { headline: 'A story', score, sourceId: 'winsidr', url: null },
        })}
      />
    );

    expect(screen.getByText(expected)).toBeTruthy();
    expect(screen.queryByText(notExpected)).toBeNull();
  });
});

describe('MediaSentimentPulseCard — unavailable and absent states', () => {
  it('renders the reason verbatim and no numeric score when available is false', () => {
    const reason =
      'none of the 70 beat_feeds items mentioned the WNBA or any franchise';
    render(
      <MediaSentimentPulseCard
        pulse={{
          available: false,
          reason,
          articleCount: 0,
          beatItemsSeen: 70,
          scrapedCount: 0,
          fallbackCount: 0,
        }}
      />
    );

    expect(screen.getByText(reason)).toBeTruthy();
    expect(screen.queryByTestId('media-sentiment-mean')).toBeNull();
    // A placeholder value here would be a publishing defect (#129/#133-#135, #138).
    const card = screen.getByTestId('media-sentiment-pulse-card');
    expect(card.textContent).not.toMatch(/[+-]\d+\.\d{4}/);
  });

  it('renders the generic "not computed" wording when the field is absent', () => {
    render(<MediaSentimentPulseCard pulse={undefined} />);

    expect(screen.getByText(/Not computed for this edition/)).toBeTruthy();
    expect(screen.queryByTestId('media-sentiment-mean')).toBeNull();
  });

  it('keeps the header trend slot present in every state so a sparkline can be added later', () => {
    for (const pulse of [undefined, availablePulse()]) {
      const { unmount } = render(<MediaSentimentPulseCard pulse={pulse} />);
      expect(screen.getByTestId('media-sentiment-trend-slot')).toBeTruthy();
      unmount();
    }
  });
});
