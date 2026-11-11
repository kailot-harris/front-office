import { describe, it, expect } from 'vitest';
import { GLOSSARY_TERMS } from '@/components/Glossary';

describe('components/Glossary.tsx shared jargon glossary', () => {
  it('defines non-empty definitions for every recurring jargon term surfaced on cap-sheet, diagnostics, and clutch', () => {
    const requiredTerms = ['CBT', 'WAR', 'Pythagenpat', 'Elo', 'Empirical Bayes', 'Leverage Index', 'WPA', 'wOBA', 'Brier Score'];
    for (const term of requiredTerms) {
      expect(GLOSSARY_TERMS[term]).toBeTruthy();
      expect(GLOSSARY_TERMS[term].length).toBeGreaterThan(10);
    }
  });
});
