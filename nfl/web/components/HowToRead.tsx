'use client';

import React, { useEffect, useState } from 'react';
import { ChevronDown, Lightbulb } from 'lucide-react';

/**
 * One-line "How to read this" disclosure shown under a page header (#136). Collapsed by
 * default; expanded/collapsed state persists per page in localStorage so a reader who opens
 * it once doesn't have to re-open it on every visit.
 */
export interface HowToReadProps {
  /** Stable key identifying the page, e.g. "standings", "teams-epa". Used in the localStorage key. */
  pageKey: string;
  children: React.ReactNode;
}

const storageKey = (pageKey: string) => `nfl-how-to-read:${pageKey}`;

export const HowToRead: React.FC<HowToReadProps> = ({ pageKey, children }) => {
  const [open, setOpen] = useState(false);
  const [hydrated, setHydrated] = useState(false);

  useEffect(() => {
    try {
      const stored = window.localStorage.getItem(storageKey(pageKey));
      if (stored === 'open') setOpen(true);
    } catch {
      // localStorage unavailable (privacy mode, SSR) — fall back to collapsed.
    }
    setHydrated(true);
  }, [pageKey]);

  const toggle = () => {
    const next = !open;
    setOpen(next);
    try {
      window.localStorage.setItem(storageKey(pageKey), next ? 'open' : 'closed');
    } catch {
      // ignore persistence failures
    }
  };

  return (
    <div
      className={`rounded-lg border border-slate-800/80 bg-surface-raised/60 text-xs ${hydrated ? '' : 'invisible'}`}
    >
      <button
        type="button"
        onClick={toggle}
        aria-expanded={open}
        className="w-full min-h-[24px] flex items-center justify-between gap-2 px-3 py-2 text-left text-slate-300 hover:text-white transition-colors"
      >
        <span className="flex items-center gap-1.5 font-semibold">
          <Lightbulb className="w-3.5 h-3.5 text-amber-400" />
          How to read this
        </span>
        <ChevronDown className={`w-3.5 h-3.5 transition-transform ${open ? 'rotate-180' : ''}`} />
      </button>
      {open && <div className="px-3 pb-3 text-slate-400 leading-relaxed">{children}</div>}
    </div>
  );
};
