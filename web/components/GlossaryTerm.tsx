'use client';

import React, { useState, useRef, useEffect } from 'react';
import { HelpCircle } from 'lucide-react';

// Issue #136: this app relies on 62 native `title="..."` tooltips (sort
// column hints, metric explainers) to teach jargon like "RAPM" or
// "Ensemble Wins" — but native title tooltips only fire on :hover, so they
// never work on a touchscreen at all. GlossaryTerm replaces a tooltip with a
// tap-to-open popover that works identically on mouse and touch, derived
// from the same explanatory text that used to live in `title` attributes.

export interface GlossaryDefinition {
  term: string;
  definition: string;
}

// Term list derived from this app's existing `title="..."` tooltip text
// (StandingsClient.tsx sort-header hints, PlayoffSeriesClient.tsx /
// Sidebar.tsx metric explainers, PlayerDnaClient.tsx dossier labels).
export const GLOSSARY: Record<string, GlossaryDefinition> = {
  ensembleWins: {
    term: 'Ensemble Wins',
    definition:
      'Mean projected regular-season win total, averaged across all 4 model variants (RAPM, Bottom-Up, Fatigue, Ensemble) over 1,000 simulated seasons.',
  },
  percentileRange: {
    term: 'Percentile Range (p10-p90)',
    definition:
      "The spread between a team's 10th- and 90th-percentile simulated win totals — a wider range means a less predictable season.",
  },
  playoffProb: {
    term: 'Playoff Probability',
    definition: 'Share of the 1,000 simulated seasons in which this team finishes in a playoff position.',
  },
  titleProb: {
    term: 'Title Probability',
    definition: 'Share of the 1,000 simulated seasons in which this team wins the championship.',
  },
  rapm: {
    term: 'RAPM',
    definition:
      "Regularized Adjusted Plus-Minus — a ridge-regression estimate of a player's point impact per 100 possessions, adjusting for teammates and opponents on the floor.",
  },
  marginSigma: {
    term: 'Margin σ',
    definition:
      'Standard deviation of single-game score differentials around the expected margin. Converts point spreads into win probabilities via the normal CDF.',
  },
  netRatingMargin: {
    term: 'Net Rating Margin',
    definition:
      'Raw playoff net-rating differential between the two teams, adjusted by tactical mismatch deltas (pace, matchup exploits) before home-court advantage is applied.',
  },
  sweepProb: {
    term: 'Sweep Probability',
    definition: 'Share of simulated series this matchup ends in the minimum number of games (a sweep).',
  },
  hca: {
    term: 'HCA (Home-Court Advantage)',
    definition: 'Fixed point bonus added to a team’s expected margin in games played on their home floor.',
  },
  cosineSimilarity: {
    term: 'Cosine Similarity',
    definition:
      "A 0-100% score measuring how closely two players' 12-dimensional skill vectors point in the same direction — higher means more stylistically similar, independent of overall skill level.",
  },
  brierScore: {
    term: 'Brier Score',
    definition:
      'Mean squared error between a predicted win probability and the actual 0/1 outcome, averaged over every resolved game. 0 is a perfect forecaster; 0.25 is what guessing 50/50 every time scores.',
  },
  logLoss: {
    term: 'Log-Loss',
    definition:
      'Cross-entropy loss between predicted win probabilities and actual outcomes. Unlike Brier Score it penalizes confident-and-wrong predictions much more heavily — lower is better.',
  },
};

export type GlossaryKey = keyof typeof GLOSSARY;

interface GlossaryTermProps {
  termKey: GlossaryKey;
  className?: string;
}

export const GlossaryTerm: React.FC<GlossaryTermProps> = ({ termKey, className = '' }) => {
  const [isOpen, setIsOpen] = useState(false);
  const containerRef = useRef<HTMLSpanElement>(null);
  const entry = GLOSSARY[termKey];

  useEffect(() => {
    if (!isOpen) return;
    const handleOutside = (e: MouseEvent | TouchEvent) => {
      if (containerRef.current && !containerRef.current.contains(e.target as Node)) {
        setIsOpen(false);
      }
    };
    const handleEscape = (e: KeyboardEvent) => {
      if (e.key === 'Escape') setIsOpen(false);
    };
    document.addEventListener('click', handleOutside);
    document.addEventListener('touchstart', handleOutside);
    document.addEventListener('keydown', handleEscape);
    return () => {
      document.removeEventListener('click', handleOutside);
      document.removeEventListener('touchstart', handleOutside);
      document.removeEventListener('keydown', handleEscape);
    };
  }, [isOpen]);

  if (!entry) return null;

  return (
    <span ref={containerRef} className={`relative inline-flex items-center ${className}`}>
      <button
        type="button"
        onClick={(e) => {
          e.stopPropagation();
          setIsOpen((v) => !v);
        }}
        aria-expanded={isOpen}
        aria-label={`What does "${entry.term}" mean?`}
        className="touch-manipulation cursor-pointer inline-flex items-center gap-0.5 border-b border-dotted border-slate-500 hover:border-indigo-400 hover:text-indigo-300 transition-colors"
      >
        <span>{entry.term}</span>
        <HelpCircle className="w-3 h-3 text-slate-400" />
      </button>

      {isOpen && (
        <div
          role="tooltip"
          className="absolute left-0 top-full mt-1.5 z-50 w-64 max-w-[85vw] bg-surface-raised border border-slate-700 rounded-lg p-3 shadow-2xl text-left"
        >
          <p className="text-[11px] sm:text-[10px] font-bold text-indigo-400 uppercase tracking-wider mb-1">
            {entry.term}
          </p>
          <p className="text-xs text-slate-300 leading-relaxed">{entry.definition}</p>
        </div>
      )}
    </span>
  );
};
