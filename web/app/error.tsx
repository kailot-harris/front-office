'use client';

import { useEffect } from 'react';
import Link from 'next/link';
import { AlertTriangle, RotateCcw, Home } from 'lucide-react';

export default function Error({
  error,
  reset,
}: {
  error: Error & { digest?: string };
  reset: () => void;
}) {
  useEffect(() => {
    // eslint-disable-next-line no-console
    console.error(error);
  }, [error]);

  return (
    <div className="min-h-[60vh] flex items-center justify-center px-4">
      <div className="max-w-md w-full bg-surface-raised/90 border border-slate-800 rounded-xl p-8 text-center shadow-xl">
        <div className="mx-auto mb-4 w-12 h-12 rounded-full bg-amber-500/10 border border-amber-500/30 flex items-center justify-center">
          <AlertTriangle className="w-6 h-6 text-amber-400" />
        </div>
        <h1 className="text-xl font-bold text-white mb-2">Something went wrong</h1>
        <p className="text-sm text-slate-400 mb-6">
          This page hit an unexpected error while rendering. You can try again, or head back to
          the home page.
        </p>
        <div className="flex items-center justify-center gap-3">
          <button
            onClick={() => reset()}
            className="inline-flex items-center gap-2 px-4 py-2 rounded-lg bg-accent-600 hover:bg-accent-500 text-white text-xs font-bold font-mono transition-colors"
          >
            <RotateCcw className="w-3.5 h-3.5" />
            Try again
          </button>
          <Link
            href="/"
            className="inline-flex items-center gap-2 px-4 py-2 rounded-lg bg-surface border border-slate-800 text-slate-300 hover:text-white hover:border-slate-600 text-xs font-bold font-mono transition-colors"
          >
            <Home className="w-3.5 h-3.5" />
            Back to home
          </Link>
        </div>
      </div>
    </div>
  );
}
