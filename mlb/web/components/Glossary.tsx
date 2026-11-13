'use client';

import React, { useEffect, useRef, useState } from 'react';
import { Info } from 'lucide-react';

/**
 * Shared jargon glossary. Terms are derived from this repo's existing native
 * `title` tooltips (CBT zones, WAR/Elo/Pythagenpat explainers, etc.), which
 * don't work on touch devices. This popover opens on tap/click instead, so it
 * works at any viewport width, including 375px mobile.
 */
export const GLOSSARY_TERMS: Record<string, string> = {
  CBT: 'Competitive Balance Tax — MLB’s luxury tax on payrolls above a league-set base threshold ($244M in 2026).',
  WAR: 'Wins Above Replacement — estimated wins a player adds versus a freely available replacement-level player.',
  Pythagenpat:
    'A run-differential win-percentage estimator (an exponent-tuned variant of the Pythagorean expectation) used to project a team’s expected win total from runs scored/allowed.',
  Elo: 'A relative skill-rating system (borrowed from chess) updated after every game based on the result and opponent strength.',
  'Empirical Bayes':
    'A statistical technique that shrinks small-sample player estimates toward a league-wide average, reducing noise from limited playing time.',
  'Leverage Index':
    'Tom Tango’s metric for how much a single plate appearance can swing a game’s win probability; LI = 1.0 is average, higher is more pressure.',
  WPA: 'Win Probability Added — the change in a team’s win probability attributable to a single play or plate appearance.',
  wOBA: 'Weighted On-Base Average — a rate stat that weights each way of reaching base by its actual run value.',
  'Brier Score':
    'Mean squared error between predicted win probabilities and actual outcomes; lower is better, 0.25 is a coin-flip baseline.',
  'Marcel Projection':
    'A simple, transparent baseline projection system that weights a player’s last three seasons, with regression to the mean for small samples.',
  xFIP: 'Expected Fielding Independent Pitching — an ERA estimator built from strikeouts and walks plus a league-average home-run-per-fly-ball rate, isolating a pitcher’s performance from the fielders and luck around them.',
  rGS: 'Tangotiger’s rolling Game Score — a single-number rating of a starting pitcher’s expected performance in a given start, relative to league average.',
  ISO: 'Isolated Power — slugging percentage minus batting average, a rate stat that measures raw extra-base power on its own.',
  IVB: 'Induced Vertical Break — how much a pitch’s vertical movement deviates (due to spin, via the Magnus effect) from a theoretical spin-free trajectory.',
  HB: 'Horizontal Break — how much a pitch moves side-to-side in flight due to spin, relative to a spin-free trajectory.',
  HCA: 'Home-Field/Court Advantage — the statistical edge given to the team playing at home, applied as a rating or win-probability bonus.',
};

interface GlossaryTermProps {
  term: keyof typeof GLOSSARY_TERMS | string;
  children?: React.ReactNode;
  className?: string;
}

/**
 * Wrap a jargon word/abbreviation so it opens a definition popover on tap
 * (and on click/keyboard for desktop). Falls back to rendering the term
 * plain text if it isn't in the glossary.
 */
export const GlossaryTerm: React.FC<GlossaryTermProps> = ({ term, children, className = '' }) => {
  const [open, setOpen] = useState(false);
  const containerRef = useRef<HTMLSpanElement | null>(null);
  const definition = GLOSSARY_TERMS[term];

  useEffect(() => {
    if (!open) return;
    const handleOutside = (e: MouseEvent | TouchEvent) => {
      if (containerRef.current && !containerRef.current.contains(e.target as Node)) {
        setOpen(false);
      }
    };
    const handleKey = (e: KeyboardEvent) => {
      if (e.key === 'Escape') setOpen(false);
    };
    document.addEventListener('mousedown', handleOutside);
    document.addEventListener('touchstart', handleOutside);
    document.addEventListener('keydown', handleKey);
    return () => {
      document.removeEventListener('mousedown', handleOutside);
      document.removeEventListener('touchstart', handleOutside);
      document.removeEventListener('keydown', handleKey);
    };
  }, [open]);

  if (!definition) {
    return <>{children ?? term}</>;
  }

  return (
    <span ref={containerRef} className={`relative inline-flex items-center ${className}`}>
      <button
        type="button"
        onClick={(e) => {
          e.stopPropagation();
          setOpen((v) => !v);
        }}
        aria-expanded={open}
        aria-label={`Definition of ${term}`}
        className="inline-flex items-center gap-0.5 min-h-[24px] min-w-[24px] underline decoration-dotted decoration-slate-500 underline-offset-2 text-inherit touch-manipulation"
      >
        {children ?? term}
        <Info className="w-3 h-3 text-slate-400" aria-hidden="true" />
      </button>
      {open && (
        <span
          role="tooltip"
          className="absolute left-0 top-full z-50 mt-1.5 w-64 max-w-[80vw] rounded-lg border border-slate-700 bg-surface-raised p-3 text-xs leading-relaxed text-slate-200 shadow-2xl"
        >
          <span className="block font-bold text-white mb-1">{term}</span>
          {definition}
        </span>
      )}
    </span>
  );
};
