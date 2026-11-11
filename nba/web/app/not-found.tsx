import React from 'react';
import Link from 'next/link';
import { Compass, Home } from 'lucide-react';

/**
 * #115: there was no app/not-found.tsx, so an unmatched route fell through to
 * Next's generic 404 instead of this app's own look. Styled with the same
 * surface/accent tokens used across the rest of the app (see
 * tailwind.config.ts: `surface`, `surface-raised`, `accent-*`).
 */
export default function NotFound() {
  return (
    <div className="min-h-[60vh] flex items-center justify-center p-6">
      <div className="max-w-md w-full bg-surface-raised/80 border border-slate-800 rounded-2xl p-8 text-center shadow-xl">
        <div className="mx-auto mb-4 w-12 h-12 rounded-xl bg-accent-500/10 text-accent-400 border border-accent-500/30 flex items-center justify-center">
          <Compass className="w-6 h-6" />
        </div>
        <h1 className="text-lg font-bold text-white tracking-tight mb-1.5">
          Page not found
        </h1>
        <p className="text-sm text-slate-400 mb-6">
          This route does not exist. It may have moved, or the link may be out
          of date.
        </p>
        <div className="flex items-center justify-center">
          <Link
            href="/"
            className="inline-flex items-center gap-2 px-4 py-2 rounded-lg bg-accent-600 text-white text-sm font-semibold hover:bg-accent-700 transition-colors"
          >
            <Home className="w-4 h-4" />
            Go home
          </Link>
        </div>
      </div>
    </div>
  );
}
