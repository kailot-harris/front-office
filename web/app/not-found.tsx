import Link from 'next/link';
import { Compass, Home } from 'lucide-react';

// Issue #115: with no app/not-found.tsx, a nonexistent route fell through to
// Next's generic unstyled 404 instead of this app's theme. Uses the same
// surface/accent tokens as the rest of the app (see tailwind.config.ts).
export default function NotFound() {
  return (
    <div className="min-h-[60vh] flex items-center justify-center px-4 py-16">
      <div className="max-w-md w-full bg-surface-raised/90 border border-slate-800 rounded-2xl p-8 shadow-xl text-center space-y-5">
        <div className="mx-auto w-14 h-14 rounded-full bg-accent-500/10 border border-accent-500/30 flex items-center justify-center">
          <Compass className="w-7 h-7 text-accent-400" />
        </div>

        <div>
          <h1 className="text-xl font-black text-white tracking-tight">Page Not Found</h1>
          <p className="text-sm text-slate-400 mt-2 leading-relaxed">
            The page you&apos;re looking for doesn&apos;t exist or may have moved.
          </p>
        </div>

        <div className="pt-1">
          <Link
            href="/"
            className="inline-flex items-center justify-center gap-2 px-4 py-2 rounded-lg text-sm font-bold bg-accent-600 text-white hover:bg-accent-700 transition-colors shadow"
          >
            <Home className="w-4 h-4" />
            <span>Back to Home</span>
          </Link>
        </div>
      </div>
    </div>
  );
}
