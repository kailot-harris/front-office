'use client';

import React, { useState, useEffect } from 'react';
import { ChevronDown, ChevronUp, Info } from 'lucide-react';

interface HowToReadDisclosureProps {
  /** Unique key for this page, used to namespace the localStorage entry (#136). */
  pageKey: string;
  /** One-line (or short) explanation of how to read this page's content. */
  children: React.ReactNode;
}

const STORAGE_PREFIX = 'howToRead:';

/**
 * Collapsed-by-default "How to read this" disclosure shown under a page's header.
 * Open/closed state persists per-page in localStorage so a visitor who opens it once
 * doesn't have to re-open it on every visit (#136).
 */
export const HowToReadDisclosure: React.FC<HowToReadDisclosureProps> = ({ pageKey, children }) => {
  const storageKey = `${STORAGE_PREFIX}${pageKey}`;
  const [open, setOpen] = useState(false);
  const [hydrated, setHydrated] = useState(false);

  useEffect(() => {
    try {
      const stored = window.localStorage.getItem(storageKey);
      if (stored === 'open') setOpen(true);
    } catch {
      // localStorage unavailable (private mode, etc.) — fall back to collapsed default.
    }
    setHydrated(true);
  }, [storageKey]);

  const toggle = () => {
    const next = !open;
    setOpen(next);
    try {
      window.localStorage.setItem(storageKey, next ? 'open' : 'closed');
    } catch {
      // ignore persistence failures
    }
  };

  return (
    <div
      className={`rounded-lg border border-slate-800 bg-surface-raised/60 text-sm ${hydrated ? '' : 'opacity-0'}`}
    >
      <button
        type="button"
        onClick={toggle}
        aria-expanded={open}
        className="min-h-6 w-full flex items-center justify-between gap-2 px-3 py-2 text-left text-slate-300 hover:text-white transition-colors"
      >
        <span className="inline-flex items-center gap-1.5 font-semibold">
          <Info className="w-3.5 h-3.5 text-indigo-400" />
          How to read this
        </span>
        {open ? <ChevronUp className="w-3.5 h-3.5" /> : <ChevronDown className="w-3.5 h-3.5" />}
      </button>
      {open && <div className="px-3 pb-3 text-slate-400 leading-relaxed">{children}</div>}
    </div>
  );
};
