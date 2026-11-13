'use client';

import React, { useEffect } from 'react';
import Link from 'next/link';
import { AlertTriangle, RotateCcw, Home } from 'lucide-react';

// Issue #115: with no app/error.tsx, a render exception thrown inside any
// client component left the user staring at a blank page — Next's default
// error overlay only shows in dev, and production had nothing at all. This
// boundary wraps every route under app/layout.tsx and renders a styled
// fallback using the same surface/accent tokens as the rest of the app
// (see tailwind.config.ts), with a reset button and a link back home.
export default function GlobalError({
  error,
  reset,
}: {
  error: Error & { digest?: string };
  reset: () => void;
}) {
  useEffect(() => {
    // eslint-disable-next-line no-console
    console.error('Unhandled client render error:', error);
  }, [error]);

  return (
    <div className="min-h-[60vh] flex items-center justify-center px-4 py-16">
      <div className="max-w-md w-full bg-surface-raised/90 border border-slate-800 rounded-2xl p-8 shadow-xl text-center space-y-5">
        <div className="mx-auto w-14 h-14 rounded-full bg-rose-500/10 border border-rose-500/30 flex items-center justify-center">
          <AlertTriangle className="w-7 h-7 text-rose-400" />
        </div>

        <div>
          <h1 className="text-xl font-black text-white tracking-tight">Something went wrong</h1>
          <p className="text-sm text-slate-400 mt-2 leading-relaxed">
            This page hit an unexpected error while rendering. You can try again, or head back to
            the dashboard home.
          </p>
          {error?.digest && (
            <p className="text-[11px] font-mono text-slate-400 mt-2">Digest: {error.digest}</p>
          )}
        </div>

        <div className="flex flex-col sm:flex-row items-center justify-center gap-3 pt-1">
          <button
            type="button"
            onClick={() => reset()}
            className="w-full sm:w-auto inline-flex items-center justify-center gap-2 px-4 py-2 rounded-lg text-sm font-bold bg-accent-600 text-white hover:bg-accent-700 transition-colors shadow"
          >
            <RotateCcw className="w-4 h-4" />
            <span>Try Again</span>
          </button>
          <Link
            href="/"
            className="w-full sm:w-auto inline-flex items-center justify-center gap-2 px-4 py-2 rounded-lg text-sm font-bold bg-surface border border-slate-800 text-slate-300 hover:text-white hover:border-slate-600 transition-colors"
          >
            <Home className="w-4 h-4" />
            <span>Back to Home</span>
          </Link>
        </div>
      </div>
    </div>
  );
}
