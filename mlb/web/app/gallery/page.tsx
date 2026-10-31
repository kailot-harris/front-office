import { VisualMediaGalleryClient } from '@/components/VisualMediaGalleryClient';

export const metadata = {
  title: 'Visual Media Gallery & Year-End Race Animations | MLB Analytics',
  description: '20 automated animated races, division trajectory plots, October postseason brackets, and sabermetric scatters.',
};

export default function GalleryPage() {
  return (
    <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8 space-y-6">
      <div className="relative pb-6">
        <div className="flex flex-col md:flex-row md:items-center justify-between gap-4">
          <div>
            <h1 className="text-3xl font-black tracking-tight text-white flex items-center gap-3">
              <span><span className="text-sky-400">MLB</span> Visual Media Gallery</span>
              <span className="text-sm font-semibold px-2.5 py-0.5 rounded-full bg-sky-500/10 text-sky-400 border border-sky-500/20">
                20 Animated Suites
              </span>
            </h1>
            <p className="text-slate-400 text-sm mt-1">
              High-performance animated GIF visualizers powered by <code className="text-sky-300">mlbplotR</code>, official team crests, and quantitative sabermetric tracking engines.
            </p>
          </div>
        </div>
        <div className="absolute bottom-0 left-0 right-0 h-[2px] bg-gradient-to-r from-sky-400 via-sky-500/40 to-transparent" />
      </div>

      <VisualMediaGalleryClient />
    </div>
  );
}
