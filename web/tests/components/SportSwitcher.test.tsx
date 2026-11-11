import { describe, expect, it } from 'vitest';
import { render, screen } from '@testing-library/react';
import { SportSwitcher } from '@/components/SportSwitcher';

/**
 * Regression coverage for #131: the in-app sport switcher ordered leagues
 * NFL, NBA, MLB, WNBA while the landing page (cards + trophy tabs, in the
 * aggregator repo) used NFL, NBA, WNBA, MLB. The switcher must match the
 * landing page order: NFL, NBA, WNBA, MLB.
 */
describe('SportSwitcher order (#131)', () => {
  it('renders leagues in NFL, NBA, WNBA, MLB order', () => {
    render(<SportSwitcher current="nba" />);
    const links = screen.getAllByRole('link');
    const labels = links.map((link) => link.textContent?.trim());
    expect(labels).toEqual(['NFL', 'NBA', 'WNBA', 'MLB']);
  });
});
