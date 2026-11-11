'use client';

import React, { useState, useRef, useEffect } from 'react';
import { HelpCircle } from 'lucide-react';

// Shared jargon glossary for recurring stat/finance terms (EPA-equivalent metrics, RAPM,
// CBA aprons, Brier score, etc). Native `title` tooltips don't work on touch devices
// (#136), so this renders a click/tap-to-toggle popover instead of relying on hover.
export const GLOSSARY: Record<string, string> = {
  RAPM:
    'Regularized Adjusted Plus-Minus — a player\'s estimated point impact per 100 possessions after statistically isolating teammates and opponents.',
  BPM: 'Box Plus-Minus — a box-score-based estimate of a player\'s contribution in points per 100 possessions versus a league-average player.',
  PRA: 'Points + Rebounds + Assists, a common fantasy/production composite stat.',
  'Brier score':
    'A calibration metric for probabilistic forecasts: the mean squared error between predicted win probabilities and actual outcomes. Lower is better (0 is perfect).',
  apron:
    'A luxury-tax-adjacent payroll threshold under the NBA\'s Collective Bargaining Agreement. Crossing the first or second apron triggers escalating roster-building restrictions (e.g. limits on trades, free-agent signings, and exceptions).',
  'first apron':
    'The lower of two hard payroll thresholds above the luxury tax line. Teams over it lose access to certain trade exceptions and cannot acquire players via sign-and-trade.',
  'second apron':
    'The higher payroll threshold. Teams over it face the strictest roster-building restrictions, including a frozen first-round pick and a ban on aggregating salaries in trades.',
  'z-score':
    'A statistic expressed in standard deviations from the league-average value, used to compare players across different scales or seasons.',
  'margin sigma':
    'The modeled standard deviation of single-game score differentials around the expected margin, used to convert point-spread projections into win probabilities.',
  'Monte Carlo':
    'A simulation technique that replays a season (or many seasons) thousands of times with randomized outcomes to estimate probability distributions like playoff odds.',
  embeddings:
    'A learned numerical representation of a player\'s style or skill profile, positioned in a multi-dimensional space so similar players sit close together.',
  manifold:
    'A lower-dimensional surface that high-dimensional player data (e.g. 16-D skill vectors) is projected onto so it can be visualized or compared.',
};

interface GlossaryTermProps {
  /** Glossary key to look up in GLOSSARY. Falls back to `term` itself if not a lookup key. */
  term: keyof typeof GLOSSARY | string;
  /** Optional override text instead of the term itself as the trigger label. */
  label?: string;
  className?: string;
}

/**
 * Inline jargon helper: renders the term/abbreviation with a small (?) trigger that opens
 * a popover on click/tap (not just hover, so it works on touch devices) with a plain-language
 * definition. Closes on outside click, Escape, or a second tap of the trigger.
 */
export const GlossaryTerm: React.FC<GlossaryTermProps> = ({ term, label, className = '' }) => {
  const [open, setOpen] = useState(false);
  const containerRef = useRef<HTMLSpanElement>(null);
  const definition = GLOSSARY[term] ?? GLOSSARY[term.toLowerCase()];

  useEffect(() => {
    if (!open) return;
    const handleClick = (e: MouseEvent) => {
      if (containerRef.current && !containerRef.current.contains(e.target as Node)) {
        setOpen(false);
      }
    };
    const handleKey = (e: KeyboardEvent) => {
      if (e.key === 'Escape') setOpen(false);
    };
    document.addEventListener('click', handleClick);
    document.addEventListener('keydown', handleKey);
    return () => {
      document.removeEventListener('click', handleClick);
      document.removeEventListener('keydown', handleKey);
    };
  }, [open]);

  if (!definition) {
    // Unknown term: render plain text, no popover affordance.
    return <span className={className}>{label ?? term}</span>;
  }

  return (
    <span ref={containerRef} className={`relative inline-flex items-center gap-0.5 ${className}`}>
      <span>{label ?? term}</span>
      <button
        type="button"
        onClick={(e) => {
          e.stopPropagation();
          setOpen((v) => !v);
        }}
        aria-expanded={open}
        aria-label={`What does ${label ?? term} mean?`}
        className="min-w-6 min-h-6 inline-flex items-center justify-center text-slate-500 hover:text-indigo-400 transition-colors"
      >
        <HelpCircle className="w-3.5 h-3.5" />
      </button>
      {open && (
        <span
          role="tooltip"
          className="absolute z-50 top-full left-0 mt-1 w-64 max-w-[80vw] p-3 rounded-lg bg-surface-raised border border-slate-700 shadow-xl text-xs font-normal text-slate-200 leading-relaxed normal-case"
        >
          <strong className="block text-slate-100 mb-1">{label ?? term}</strong>
          {definition}
        </span>
      )}
    </span>
  );
};
