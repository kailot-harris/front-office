import { describe, expect, it, beforeEach } from 'vitest';
import { render, screen, fireEvent, cleanup } from '@testing-library/react';
import React from 'react';
import { HowToRead } from '../../components/HowToRead';

// Issue #136: the "How to read this" disclosure is collapsed by default and
// remembers its open/closed state per page in localStorage.

describe('HowToRead — issue #136 persisted disclosure', () => {
  beforeEach(() => {
    window.localStorage.clear();
    cleanup();
  });

  it('is collapsed by default', () => {
    render(
      <HowToRead pageKey="test-page">
        <span>Explainer body text</span>
      </HowToRead>
    );
    expect(screen.queryByText('Explainer body text')).toBeNull();
  });

  it('expands on click and persists that choice to localStorage', () => {
    render(
      <HowToRead pageKey="test-page">
        <span>Explainer body text</span>
      </HowToRead>
    );
    fireEvent.click(screen.getByRole('button', { name: /How to read this/i }));
    expect(screen.getByText('Explainer body text')).toBeDefined();
    expect(window.localStorage.getItem('wnba:how-to-read:test-page')).toBe('1');
  });

  it('restores the expanded state from localStorage on a later mount', async () => {
    window.localStorage.setItem('wnba:how-to-read:test-page', '1');
    render(
      <HowToRead pageKey="test-page">
        <span>Explainer body text</span>
      </HowToRead>
    );
    expect(await screen.findByText('Explainer body text')).toBeDefined();
  });

  it('uses independent storage per pageKey', () => {
    render(
      <HowToRead pageKey="page-a">
        <span>A body</span>
      </HowToRead>
    );
    fireEvent.click(screen.getByRole('button', { name: /How to read this/i }));
    expect(window.localStorage.getItem('wnba:how-to-read:page-a')).toBe('1');
    expect(window.localStorage.getItem('wnba:how-to-read:page-b')).toBeNull();
  });
});
