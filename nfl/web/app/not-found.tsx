import Link from 'next/link';
import { SearchX, Home } from 'lucide-react';

export default function NotFound() {
  return (
    <div className="min-h-[60vh] flex items-center justify-center px-4">
      <div className="max-w-md w-full bg-surface-raised/90 border border-slate-800 rounded-xl p-8 text-center shadow-xl">
        <div className="mx-auto mb-4 w-12 h-12 rounded-full bg-accent-500/10 border border-accent-500/30 flex items-center justify-center">
          <SearchX className="w-6 h-6 text-accent-400" />
        </div>
        <h1 className="text-xl font-bold text-white mb-2">Page not found</h1>
        <p className="text-sm text-slate-400 mb-6">
          The page you&apos;re looking for doesn&apos;t exist or may have moved.
        </p>
        <Link
          href="/"
          className="inline-flex items-center gap-2 px-4 py-2 rounded-lg bg-accent-600 hover:bg-accent-500 text-white text-xs font-bold font-mono transition-colors"
        >
          <Home className="w-3.5 h-3.5" />
          Back to home
        </Link>
      </div>
    </div>
  );
}
