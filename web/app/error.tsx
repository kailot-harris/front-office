'use client';

import { useEffect } from 'react';
import Link from 'next/link';
import { AlertTriangle, RotateCcw, Home } from 'lucide-react';

export default function ErrorPage({
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
    <div className="max-w-2xl mx-auto px-4 sm:px-6 lg:px-8 py-20 flex flex-col items-center text-center">
      <div className="bg-surface-raised/90 border border-slate-800 rounded-xl p-8 shadow-xl w-full">
        <div className="mx-auto mb-4 flex items-center justify-center w-14 h-14 rounded-full bg-rose-500/10 border border-rose-500/30">
          <AlertTriangle className="w-7 h-7 text-rose-400" />
        </div>
        <h1 className="text-xl font-bold text-white tracking-tight">Something broke on this page</h1>
        <p className="text-slate-400 text-sm mt-2 leading-relaxed">
          An unexpected error occurred while rendering this view. You can try again, or head back to
          the home page.
        </p>
        {error?.digest && (
          <p className="text-[11px] font-mono text-slate-400 mt-3">Error ref: {error.digest}</p>
        )}

        <div className="flex items-center justify-center gap-3 mt-6">
          <button
            type="button"
            onClick={() => reset()}
            className="inline-flex items-center gap-1.5 px-4 py-2 text-sm font-medium rounded-lg bg-accent-600 hover:bg-accent-700 text-white transition-colors"
          >
            <RotateCcw className="w-4 h-4" />
            Try again
          </button>
          <Link
            href="/"
            className="inline-flex items-center gap-1.5 px-4 py-2 text-sm font-medium rounded-lg bg-slate-800 hover:bg-slate-700 text-slate-200 border border-slate-700 transition-colors"
          >
            <Home className="w-4 h-4" />
            Back to home
          </Link>
        </div>
      </div>
    </div>
  );
}
