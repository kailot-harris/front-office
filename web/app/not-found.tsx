import Link from 'next/link';
import { Compass, Home } from 'lucide-react';

export default function NotFound() {
  return (
    <div className="max-w-2xl mx-auto px-4 sm:px-6 lg:px-8 py-20 flex flex-col items-center text-center">
      <div className="bg-surface-raised/90 border border-slate-800 rounded-xl p-8 shadow-xl w-full">
        <div className="mx-auto mb-4 flex items-center justify-center w-14 h-14 rounded-full bg-sky-500/10 border border-sky-500/30">
          <Compass className="w-7 h-7 text-sky-400" />
        </div>
        <h1 className="text-xl font-bold text-white tracking-tight">
          <span className="text-sky-400">404</span> &mdash; Page not found
        </h1>
        <p className="text-slate-400 text-sm mt-2 leading-relaxed">
          This route doesn&apos;t exist, or may have moved. Check the link, or head back to the
          home page.
        </p>

        <div className="flex items-center justify-center gap-3 mt-6">
          <Link
            href="/"
            className="inline-flex items-center gap-1.5 px-4 py-2 text-sm font-medium rounded-lg bg-accent-600 hover:bg-accent-700 text-white transition-colors"
          >
            <Home className="w-4 h-4" />
            Back to home
          </Link>
        </div>
      </div>
    </div>
  );
}
