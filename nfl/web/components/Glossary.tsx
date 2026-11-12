'use client';

import React, { useState } from 'react';
import { HelpCircle, X, BookOpen } from 'lucide-react';

/**
 * Shared jargon glossary (#136). 28 native `title` tooltips sitewide don't fire on touch, so
 * mobile/tablet readers had no way to look up EPA/CPOE/etc. Terms are the recurring
 * abbreviations already used (without explanation) across StandingsClient, TeamsClient,
 * PlayersClient, ClutchClient and Sidebar's own margin-sigma explainer.
 */
export interface GlossaryEntry {
  term: string;
  definition: string;
}

export const GLOSSARY_TERMS: GlossaryEntry[] = [
  {
    term: 'EPA',
    definition:
      'Expected Points Added: how many points a play added or cost relative to the average outcome from that down/distance/field position, averaged per play.',
  },
  {
    term: 'CPOE',
    definition:
      'Completion Percentage Over Expected: a QB’s actual completion rate minus the rate expected given each throw’s depth, location and difficulty.',
  },
  {
    term: 'Elo',
    definition:
      'A team-strength rating (borrowed from chess) that rises after wins and falls after losses, weighted by opponent strength and margin.',
  },
  {
    term: 'Margin σ (Sigma)',
    definition:
      'The standard deviation of single-game score differentials around the expected margin — used to convert a projected point spread into a win probability.',
  },
  {
    term: 'HFA / HCA',
    definition: 'Home Field (or Home Court) Advantage: the average point bump a team gets from playing at home.',
  },
  {
    term: 'Monte Carlo Simulation',
    definition:
      'Running the season (or a playoff bracket) thousands of times with randomized outcomes drawn from each game’s win probability, then averaging the results.',
  },
  {
    term: 'Power Rating',
    definition: 'A single composite number summarizing a team’s overall strength, blending multiple models.',
  },
  {
    term: 'Success Rate',
    definition: 'The share of plays that gain enough yardage to be considered "successful" for that down and distance.',
  },
  {
    term: 'Market Blend',
    definition: 'The portion of a projection derived from sportsbook market lines rather than this app’s own models.',
  },
  {
    term: 'Brier Score',
    definition:
      'The average squared error between a predicted win probability and the actual outcome (0 or 1). Lower is better; 0 is a perfect forecast, 0.25 is a coin flip guessed every time.',
  },
  {
    term: 'Log Loss',
    definition:
      'Cross-entropy loss: like the Brier score, it grades predicted win probabilities against actual outcomes, but penalizes confident-and-wrong predictions much more heavily. Lower is better.',
  },
  {
    term: 'APY',
    definition:
      'Average Per Year: a contract’s total guaranteed and likely-to-be-paid value divided by its length, used to compare deals of different durations on equal footing.',
  },
  {
    term: 'PROE',
    definition:
      'Pass Rate Over Expected: how much more (or less) often a team actually passes compared to what down, distance, score, and time situation would predict for a league-average team.',
  },
];

/** Looks up a glossary entry by term (case-insensitive, ignoring parenthetical text). */
export function findGlossaryEntry(term: string): GlossaryEntry | undefined {
  const needle = term.toLowerCase();
  return GLOSSARY_TERMS.find((e) => e.term.toLowerCase() === needle);
}

/**
 * A single inline glossary term: shows as a dotted-underline label that opens a small
 * definition popover on tap/click (not a native `title`, so it actually works on touch).
 */
export const GlossaryTerm: React.FC<{ term: string; className?: string }> = ({ term, className }) => {
  const [open, setOpen] = useState(false);
  const entry = findGlossaryEntry(term);
  if (!entry) return <span className={className}>{term}</span>;

  return (
    <span className="relative inline-block">
      <button
        type="button"
        onClick={() => setOpen((v) => !v)}
        className={`cursor-help underline decoration-dotted decoration-slate-500 underline-offset-2 hover:text-white min-w-[24px] min-h-[24px] inline-flex items-center ${className ?? ''}`}
        aria-expanded={open}
        aria-label={`Glossary: ${entry.term}`}
      >
        {term}
      </button>
      {open && (
        <>
          <div className="fixed inset-0 z-40 bg-transparent" onClick={() => setOpen(false)} />
          <div className="absolute left-0 top-full mt-1.5 z-50 w-64 bg-surface-raised border border-slate-700 rounded-lg p-3 shadow-2xl text-left animate-in fade-in zoom-in-95 duration-150">
            <div className="flex items-center justify-between gap-2 mb-1">
              <span className="text-xs font-bold text-emerald-400">{entry.term}</span>
              <button
                onClick={() => setOpen(false)}
                className="min-w-[24px] min-h-[24px] flex items-center justify-center text-slate-400 hover:text-white rounded"
                aria-label="Close definition"
              >
                <X className="w-3.5 h-3.5" />
              </button>
            </div>
            <p className="text-[11px] text-slate-300 leading-relaxed">{entry.definition}</p>
          </div>
        </>
      )}
    </span>
  );
};

/**
 * A standalone "Glossary" button + full-term popover, for pages that reference several
 * jargon terms without inlining `GlossaryTerm` everywhere (e.g. a dense table header).
 * Opens on tap at any viewport width, including 375px mobile.
 */
export const GlossaryButton: React.FC<{ className?: string }> = ({ className }) => {
  const [open, setOpen] = useState(false);

  return (
    <span className="relative inline-block">
      <button
        type="button"
        onClick={() => setOpen((v) => !v)}
        aria-expanded={open}
        aria-label="Open glossary of terms used on this page"
        className={`min-w-[24px] min-h-[24px] inline-flex items-center gap-1.5 px-2.5 py-1 rounded-lg border border-slate-700 bg-surface-raised/80 text-[11px] font-mono text-slate-300 hover:text-white hover:border-slate-600 transition-colors ${className ?? ''}`}
      >
        <HelpCircle className="w-3.5 h-3.5" />
        <span>Glossary</span>
      </button>
      {open && (
        <>
          <div className="fixed inset-0 z-40 bg-transparent" onClick={() => setOpen(false)} />
          <div className="absolute right-0 top-full mt-1.5 z-50 w-72 sm:w-80 max-h-96 overflow-y-auto bg-surface-raised border border-slate-700 rounded-xl p-3.5 shadow-2xl space-y-2.5 animate-in fade-in zoom-in-95 duration-150">
            <div className="flex items-center justify-between border-b border-slate-800 pb-2">
              <div className="flex items-center gap-1.5 text-xs font-bold text-emerald-400">
                <BookOpen className="w-3.5 h-3.5" />
                <span>Glossary</span>
              </div>
              <button
                onClick={() => setOpen(false)}
                className="min-w-[24px] min-h-[24px] flex items-center justify-center rounded text-slate-400 hover:text-white hover:bg-slate-800"
                aria-label="Close glossary"
              >
                <X className="w-3.5 h-3.5" />
              </button>
            </div>
            <dl className="space-y-2.5">
              {GLOSSARY_TERMS.map((entry) => (
                <div key={entry.term}>
                  <dt className="text-[11px] font-bold text-slate-200">{entry.term}</dt>
                  <dd className="text-[11px] text-slate-400 leading-relaxed">{entry.definition}</dd>
                </div>
              ))}
            </dl>
          </div>
        </>
      )}
    </span>
  );
};
