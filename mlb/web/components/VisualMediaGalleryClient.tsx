'use client';

import React, { useState, useMemo } from 'react';
import { Play, Pause, Download, Filter, Sparkles, Trophy, Flame, BarChart2, Compass } from 'lucide-react';
import { BASE_PATH } from '@/lib/basePath';
import { VisualMediaItem, MLB_VISUAL_MEDIA_ITEMS } from '@/lib/visualMedia';

interface VisualMediaGalleryClientProps {
  initialCategory?: string;
  initialSelectedId?: string;
}

export const VisualMediaGalleryClient: React.FC<VisualMediaGalleryClientProps> = ({
  initialCategory = 'all',
  initialSelectedId,
}) => {
  const [selectedCategory, setSelectedCategory] = useState<string>(initialCategory);
  const [searchQuery, setSearchQuery] = useState<string>('');
  const [selectedItem, setSelectedItem] = useState<VisualMediaItem>(
    MLB_VISUAL_MEDIA_ITEMS.find((m) => m.id === initialSelectedId) || MLB_VISUAL_MEDIA_ITEMS[0]
  );
  const [isPaused, setIsPaused] = useState(false);

  const categories = [
    { id: 'all', label: 'All 20 Animations', count: 20 },
    { id: 'standings', label: 'Standings & Parity', count: 5, icon: Trophy },
    { id: 'postseason', label: 'October Postseason', count: 4, icon: Flame },
    { id: 'trends', label: 'Season Trends', count: 4, icon: BarChart2 },
    { id: 'sabermetrics', label: 'Sabermetric Scatters', count: 4, icon: Compass },
    { id: 'meta', label: 'Synthesis & Finale', count: 3, icon: Sparkles },
  ];

  const filteredItems = useMemo(() => {
    return MLB_VISUAL_MEDIA_ITEMS.filter((item) => {
      if (selectedCategory !== 'all' && item.category !== selectedCategory) {
        return false;
      }
      if (searchQuery.trim() !== '') {
        const q = searchQuery.toLowerCase();
        return item.title.toLowerCase().includes(q) || item.description.toLowerCase().includes(q);
      }
      return true;
    });
  }, [selectedCategory, searchQuery]);

  return (
    <div className="space-y-8">
      {/* Feature Showcase Banner */}
      <div className="relative overflow-hidden rounded-2xl border border-sky-500/30 bg-gradient-to-br from-slate-900 via-slate-900/90 to-indigo-950/40 p-6 sm:p-8 shadow-xl">
        <div className="grid grid-cols-1 lg:grid-cols-12 gap-8 items-center">
          {/* Main Visual Display */}
          <div className="lg:col-span-8 flex flex-col space-y-4">
            <div className="flex items-center justify-between">
              <div className="flex items-center gap-2">
                <span className="text-[10px] font-mono uppercase tracking-wider font-bold px-2 py-0.5 rounded bg-sky-500/20 text-sky-300 border border-sky-500/30">
                  {selectedItem.categoryLabel}
                </span>
                <span className="text-xs text-slate-400 font-mono">
                  Phase {selectedItem.phase} • 2026 Engine
                </span>
              </div>
              <div className="flex items-center gap-2">
                <button
                  onClick={() => setIsPaused(!isPaused)}
                  className="inline-flex items-center gap-1.5 px-3 py-1 text-xs font-semibold rounded-lg bg-slate-800 hover:bg-slate-700 text-slate-200 border border-slate-700 transition-colors"
                >
                  {isPaused ? <Play className="w-3.5 h-3.5 text-emerald-400" /> : <Pause className="w-3.5 h-3.5 text-amber-400" />}
                  {isPaused ? 'Resume GIF' : 'Freeze Frame'}
                </button>
                <a
                  href={`${BASE_PATH}/media/${selectedItem.filename}`}
                  download={selectedItem.filename}
                  className="inline-flex items-center gap-1.5 px-3 py-1 text-xs font-semibold rounded-lg bg-sky-500/20 hover:bg-sky-500/30 text-sky-200 border border-sky-500/40 transition-colors"
                >
                  <Download className="w-3.5 h-3.5" />
                  Save GIF
                </a>
              </div>
            </div>

            <div className="relative aspect-[16/10] sm:aspect-[16/9.5] w-full rounded-xl overflow-hidden bg-slate-950 border border-slate-800 shadow-2xl flex items-center justify-center">
              {/* eslint-disable-next-line @next/next/no-img-element */}
              <img
                src={`${BASE_PATH}/media/${isPaused ? selectedItem.previewPng : selectedItem.filename}`}
                alt={selectedItem.title}
                className="w-full h-full object-contain"
              />
            </div>

            <div>
              <h2 className="text-xl sm:text-2xl font-black text-white tracking-tight">
                {selectedItem.title}
              </h2>
              <p className="text-sm text-slate-300/90 mt-1 leading-relaxed">
                {selectedItem.description}
              </p>
            </div>
          </div>

          {/* Quick-Pick Sidebar in Showcase */}
          <div className="lg:col-span-4 flex flex-col space-y-3 bg-slate-950/60 p-4 rounded-xl border border-slate-800/80">
            <h3 className="text-xs font-mono font-bold uppercase tracking-wider text-slate-400 flex items-center justify-between">
              <span>Suite Playlist</span>
              <span className="text-sky-400">{filteredItems.length} Available</span>
            </h3>
            <div className="max-h-[380px] overflow-y-auto space-y-2 pr-1">
              {filteredItems.map((item) => {
                const isSelected = item.id === selectedItem.id;
                return (
                  <button
                    key={item.id}
                    onClick={() => {
                      setSelectedItem(item);
                      setIsPaused(false);
                    }}
                    className={`w-full text-left p-2.5 rounded-lg border transition-all flex items-start gap-3 ${
                      isSelected
                        ? 'bg-sky-500/15 border-sky-500/50 shadow-md shadow-sky-500/10'
                        : 'bg-slate-900/60 border-slate-800/70 hover:bg-slate-850 hover:border-slate-700'
                    }`}
                  >
                    <div className="w-14 h-10 rounded overflow-hidden flex-shrink-0 bg-slate-950 border border-slate-800">
                      {/* eslint-disable-next-line @next/next/no-img-element */}
                      <img
                        src={`${BASE_PATH}/media/${item.previewPng}`}
                        alt=""
                        className="w-full h-full object-cover"
                      />
                    </div>
                    <div className="min-w-0 flex-1">
                      <div className="text-xs font-bold text-white truncate">
                        {item.title}
                      </div>
                      <div className="text-[10px] text-slate-400 truncate mt-0.5 font-mono">
                        {item.categoryLabel}
                      </div>
                    </div>
                  </button>
                );
              })}
            </div>
          </div>
        </div>
      </div>

      {/* Filter and Category Pills */}
      <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-4 border-b border-slate-800 pb-4">
        <div className="flex flex-wrap items-center gap-2">
          {categories.map((cat) => {
            const isCatActive = selectedCategory === cat.id;
            return (
              <button
                key={cat.id}
                onClick={() => setSelectedCategory(cat.id)}
                className={`px-3 py-1.5 text-xs font-semibold rounded-lg border transition-all flex items-center gap-1.5 ${
                  isCatActive
                    ? 'bg-sky-500 text-white border-sky-400 shadow-sm'
                    : 'bg-slate-900 text-slate-300 border-slate-800 hover:bg-slate-800 hover:text-white'
                }`}
              >
                <span>{cat.label}</span>
                <span
                  className={`text-[10px] px-1.5 py-0.2 rounded-full font-mono ${
                    isCatActive ? 'bg-sky-600 text-white' : 'bg-slate-800 text-slate-400'
                  }`}
                >
                  {cat.count}
                </span>
              </button>
            );
          })}
        </div>

        <div className="relative min-w-[220px]">
          <input
            type="text"
            placeholder="Search animation by name or metric..."
            value={searchQuery}
            onChange={(e) => setSearchQuery(e.target.value)}
            className="w-full bg-slate-900 border border-slate-800 text-slate-200 text-xs rounded-lg px-3 py-2 pl-8 focus:outline-none focus:border-sky-500"
          />
          <Filter className="w-3.5 h-3.5 text-slate-400 absolute left-2.5 top-2.5" />
        </div>
      </div>

      {/* Responsive Visual Grid */}
      <div className="grid grid-cols-1 md:grid-cols-2 xl:grid-cols-3 gap-6">
        {filteredItems.map((item) => {
          const isSelected = item.id === selectedItem.id;
          return (
            <div
              key={item.id}
              className={`rounded-xl border overflow-hidden transition-all flex flex-col justify-between ${
                isSelected
                  ? 'border-sky-500/60 bg-slate-900/90 shadow-lg shadow-sky-500/10'
                  : 'border-slate-800 bg-slate-900/50 hover:border-slate-700 hover:bg-slate-900/80'
              }`}
            >
              <div>
                <div
                  className="relative aspect-[16/10] bg-slate-950 overflow-hidden cursor-pointer group"
                  onClick={() => {
                    setSelectedItem(item);
                    setIsPaused(false);
                    window.scrollTo({ top: 0, behavior: 'smooth' });
                  }}
                >
                  {/* eslint-disable-next-line @next/next/no-img-element */}
                  <img
                    src={`${BASE_PATH}/media/${item.filename}`}
                    alt={item.title}
                    className="w-full h-full object-contain transition-transform duration-300 group-hover:scale-[1.02]"
                    loading="lazy"
                  />
                  <div className="absolute inset-0 bg-slate-950/40 opacity-0 group-hover:opacity-100 transition-opacity flex items-center justify-center gap-2">
                    <span className="px-3 py-1.5 rounded-lg bg-sky-500 text-white text-xs font-bold shadow-md">
                      Play in Showcase &uarr;
                    </span>
                  </div>
                  <div className="absolute top-2 left-2">
                    <span className="text-[10px] font-mono uppercase font-bold px-2 py-0.5 rounded bg-slate-950/80 text-sky-300 border border-sky-500/30">
                      Phase {item.phase}
                    </span>
                  </div>
                </div>

                <div className="p-4 space-y-2">
                  <div className="flex items-center justify-between">
                    <span className="text-[11px] font-mono text-slate-400 uppercase tracking-wide">
                      {item.categoryLabel}
                    </span>
                    <span className="text-[10px] font-mono text-emerald-400 bg-emerald-500/10 px-1.5 py-0.5 rounded border border-emerald-500/20">
                      Animated Loop
                    </span>
                  </div>
                  <h3 className="text-base font-bold text-white tracking-tight leading-snug">
                    {item.title}
                  </h3>
                  <p className="text-xs text-slate-400 line-clamp-2">
                    {item.description}
                  </p>
                </div>
              </div>

              <div className="px-4 pb-4 pt-1 flex items-center justify-between border-t border-slate-800/60 mt-2">
                <button
                  onClick={() => {
                    setSelectedItem(item);
                    setIsPaused(false);
                    window.scrollTo({ top: 0, behavior: 'smooth' });
                  }}
                  className="text-xs font-semibold text-sky-400 hover:text-sky-300 transition-colors inline-flex items-center gap-1"
                >
                  Expand in Player &uarr;
                </button>
                <a
                  href={`${BASE_PATH}/media/${item.filename}`}
                  download={item.filename}
                  className="p-1.5 text-slate-400 hover:text-white rounded bg-slate-800 hover:bg-slate-700 transition-colors"
                  title="Download animated GIF"
                >
                  <Download className="w-3.5 h-3.5" />
                </a>
              </div>
            </div>
          );
        })}
      </div>
    </div>
  );
};
