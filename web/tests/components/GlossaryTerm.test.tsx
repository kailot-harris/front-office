import { describe, expect, it } from 'vitest';
import { render, screen, fireEvent } from '@testing-library/react';
import React from 'react';
import { GlossaryTerm } from '../../components/GlossaryTerm';

// Issue #136: native `title="..."` tooltips never fire on touch, so this
// repo's 62 jargon tooltips were invisible on mobile. GlossaryTerm replaces
// them with a tap-to-open popover — these tests simulate a tap (a plain
// click event, same as what a touchscreen dispatches) rather than hover.

describe('GlossaryTerm — issue #136 tap-to-open glossary', () => {
  it('is closed by default (no definition text visible)', () => {
    render(<GlossaryTerm termKey="rapm" />);
    expect(screen.queryByText(/Regularized Adjusted Plus-Minus/i)).toBeNull();
  });

  it('opens its definition popover on a single tap/click', () => {
    render(<GlossaryTerm termKey="rapm" />);
    const trigger = screen.getByRole('button', { name: /RAPM/i });
    fireEvent.click(trigger);
    expect(screen.getByText(/Regularized Adjusted Plus-Minus/i)).toBeDefined();
    expect(trigger.getAttribute('aria-expanded')).toBe('true');
  });

  it('closes again on a second tap', () => {
    render(<GlossaryTerm termKey="ensembleWins" />);
    const trigger = screen.getByRole('button', { name: /Ensemble Wins/i });
    fireEvent.click(trigger);
    expect(screen.queryByText(/mean projected regular-season win total/i)).toBeDefined();
    fireEvent.click(trigger);
    expect(screen.queryByText(/mean projected regular-season win total/i)).toBeNull();
  });
});
