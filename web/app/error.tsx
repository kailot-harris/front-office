'use client';

import React, { useEffect } from 'react';
import Link from 'next/link';
import { AlertTriangle, Home, RotateCcw } from 'lucide-react';

/**
 * #115: there was no app/error.tsx, so any render exception thrown inside a
 * client component left a blank page -- Next.js has nothing to fall back to
 * without this file. Styled with the same surface/accent tokens used across
 * the rest of the app (see tailwind.config.ts: `surface`, `surface-raised`,
 * `accent-*`) rather than inventing a new palette.
 */
export default function Error({
  error,
  reset,
}: {
  error: Error & { digest?: string };
  reset: () => void;
}) {
  useEffect(() => {
    // eslint-disable-next-line no-console
    console.error('Unhandled render error:', error);
  }, [error]);

  return (
    <div className="min-h-[60vh] flex items-center justify-center p-6">
      <div className="max-w-md w-full bg-surface-raised/80 border border-slate-800 rounded-2xl p-8 text-center shadow-xl">
        <div className="mx-auto mb-4 w-12 h-12 rounded-xl bg-rose-500/10 text-rose-400 border border-rose-500/30 flex items-center justify-center">
          <AlertTriangle className="w-6 h-6" />
        </div>
        <h1 className="text-lg font-bold text-white tracking-tight mb-1.5">
          Something went wrong
        </h1>
        <p className="text-sm text-slate-400 mb-6">
          This page hit an unexpected error while rendering. You can try again,
          or head back to the home page.
        </p>
        <div className="flex items-center justify-center gap-3">
          <button
            type="button"
            onClick={() => reset()}
            className="inline-flex items-center gap-2 px-4 py-2 rounded-lg bg-accent-600 text-white text-sm font-semibold hover:bg-accent-700 transition-colors"
          >
            <RotateCcw className="w-4 h-4" />
            Try again
          </button>
          <Link
            href="/"
            className="inline-flex items-center gap-2 px-4 py-2 rounded-lg border border-slate-800 text-slate-300 text-sm font-semibold hover:text-white hover:border-slate-600 transition-colors"
          >
            <Home className="w-4 h-4" />
            Go home
          </Link>
        </div>
      </div>
    </div>
  );
}
