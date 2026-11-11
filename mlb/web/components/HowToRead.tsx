'use client';

import React, { useEffect, useState } from 'react';
import { ChevronDown, HelpCircle } from 'lucide-react';

interface HowToReadProps {
  /** Unique key per page, used for the localStorage persistence key. */
  pageKey: string;
  children: React.ReactNode;
}

const storageKey = (pageKey: string) => `front-office-mlb:how-to-read:${pageKey}`;

/**
 * One-line "How to read this" disclosure, collapsed by default. Expanded
 * state persists per-page in localStorage so a visitor who opens it once
 * doesn't have to re-open it on every visit.
 */
export const HowToRead: React.FC<HowToReadProps> = ({ pageKey, children }) => {
  const [open, setOpen] = useState(false);
  const [hydrated, setHydrated] = useState(false);

  useEffect(() => {
    try {
      const stored = window.localStorage.getItem(storageKey(pageKey));
      if (stored === '1') setOpen(true);
    } catch {
      // localStorage unavailable (private browsing, etc.) — default to collapsed.
    }
    setHydrated(true);
  }, [pageKey]);

  const toggle = () => {
    const next = !open;
    setOpen(next);
    try {
      window.localStorage.setItem(storageKey(pageKey), next ? '1' : '0');
    } catch {
      // ignore
    }
  };

  return (
    <div
      className={`rounded-lg border border-slate-800 bg-surface-raised/50 text-xs text-slate-300 ${
        hydrated ? '' : 'opacity-0'
      }`}
    >
      <button
        type="button"
        onClick={toggle}
        aria-expanded={open}
        className="flex w-full min-h-[24px] items-center justify-between gap-2 px-3 py-2 text-left font-semibold text-slate-300 hover:text-white touch-manipulation"
      >
        <span className="flex items-center gap-1.5">
          <HelpCircle className="w-3.5 h-3.5 text-sky-400" />
          How to read this
        </span>
        <ChevronDown className={`w-3.5 h-3.5 transition-transform ${open ? 'rotate-180' : ''}`} />
      </button>
      {open && <div className="px-3 pb-3 leading-relaxed text-slate-400">{children}</div>}
    </div>
  );
};
