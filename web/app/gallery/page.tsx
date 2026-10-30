import { VisualMediaGalleryClient } from '@/components/VisualMediaGalleryClient';

export const metadata = {
  title: 'Visual Media Gallery & Year-End Race Animations | MLB Analytics',
  description: '20 automated animated races, division trajectory plots, October postseason brackets, and sabermetric scatters.',
};

export default function GalleryPage() {
  return (
    <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8 space-y-6">
      <div className="border-b border-slate-800 pb-6">
        <h1 className="text-3xl font-black tracking-tight text-white flex items-center gap-3">
          <span>2026 Season Visual Media Gallery</span>
          <span className="text-sm font-semibold px-2.5 py-0.5 rounded-full bg-sky-500/10 text-sky-400 border border-sky-500/20">
            20 Animated Suites
          </span>
        </h1>
        <p className="text-slate-400 text-sm mt-1">
          High-performance animated GIF visualizers powered by <code className="text-sky-300">mlbplotR</code>, official team crests, and quantitative sabermetric tracking engines.
        </p>
      </div>

      <VisualMediaGalleryClient />
    </div>
  );
}
