'use client';

import React, { useState, useEffect } from 'react';
import { ChevronDown, ChevronRight, Lightbulb } from 'lucide-react';

// Issue #136: first-time visitors land on a dense table/chart page with no
// orientation. HowToRead is a one-line "how to read this" disclosure,
// collapsed by default, placed under a page header; whether it's expanded
// is remembered per-page in localStorage so a user who opens it once
// doesn't have to re-open it on every visit.

interface HowToReadProps {
  /** Unique per-page key, e.g. "standings" or "playoff-series". */
  pageKey: string;
  children: React.ReactNode;
}

const storageKey = (pageKey: string) => `wnba:how-to-read:${pageKey}`;

export const HowToRead: React.FC<HowToReadProps> = ({ pageKey, children }) => {
  const [isOpen, setIsOpen] = useState(false);
  const [hydrated, setHydrated] = useState(false);

  useEffect(() => {
    try {
      const stored = window.localStorage.getItem(storageKey(pageKey));
      if (stored === '1') setIsOpen(true);
    } catch {
      // localStorage unavailable (private mode, sandboxed iframe) — default stays collapsed.
    }
    setHydrated(true);
  }, [pageKey]);

  const toggle = () => {
    const next = !isOpen;
    setIsOpen(next);
    try {
      window.localStorage.setItem(storageKey(pageKey), next ? '1' : '0');
    } catch {
      // Ignore write failures — state still works for this session.
    }
  };

  return (
    <div
      className={`text-xs ${hydrated ? '' : 'opacity-0'}`}
      data-testid={`how-to-read-${pageKey}`}
    >
      <button
        type="button"
        onClick={toggle}
        aria-expanded={isOpen}
        className="touch-manipulation cursor-pointer inline-flex items-center gap-1.5 text-slate-400 hover:text-indigo-300 transition-colors py-1"
      >
        {isOpen ? <ChevronDown className="w-3.5 h-3.5" /> : <ChevronRight className="w-3.5 h-3.5" />}
        <Lightbulb className="w-3.5 h-3.5 text-amber-400" />
        <span className="font-semibold">How to read this</span>
      </button>
      {isOpen && (
        <div className="mt-1.5 pl-5 pr-2 text-slate-400 leading-relaxed max-w-3xl">{children}</div>
      )}
    </div>
  );
};
