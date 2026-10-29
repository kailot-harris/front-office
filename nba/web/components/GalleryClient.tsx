'use client';

import React, { useState, useMemo } from 'react';
import { Film, Image as ImageIcon, Search, Download, Maximize2, X } from 'lucide-react';
import { BASE_PATH } from '@/lib/basePath';

export interface VisualMediaItem {
  id: string;
  filename: string;
  title: string;
  category: 'standings' | 'efficiency' | 'playoffs';
  description: string;
  type: 'gif' | 'image';
  sizeBytes?: number;
  width?: number;
  height?: number;
}

export const NBA_GALLERY_ITEMS: VisualMediaItem[] = [
  {
    id: 'gif_elo_rank_bump',
    filename: 'gif_elo_rank_bump.gif',
    title: 'League-Wide Elo Rating & Rank Evolution',
    category: 'standings',
    description: 'Animated bump chart illustrating all 30 NBA teams Elo rating movements and ranking transitions across the season.',
    type: 'gif',
    sizeBytes: 437534,
  },
  {
    id: 'gif_point_diff_race',
    filename: 'gif_point_diff_race.gif',
    title: 'Cumulative Point Differential Race',
    category: 'standings',
    description: 'Animated race chart displaying cumulative scoring differential trajectories across all 30 NBA franchises.',
    type: 'gif',
    sizeBytes: 340939,
  },
  {
    id: 'gif_net_rating_quadrant',
    filename: 'gif_net_rating_quadrant.gif',
    title: 'Offensive vs Defensive Efficiency Dynamics',
    category: 'efficiency',
    description: 'Evolution of offensive rating vs defensive rating across the league with championship quadrant dividers.',
    type: 'gif',
    sizeBytes: 299675,
  },
  {
    id: 'build_series_trajectory_gif',
    filename: 'build_series_trajectory_gif.gif',
    title: '7-Game Series Net Rating Trajectory',
    category: 'playoffs',
    description: 'Game-by-game evolution of postseason net rating margin shifts across 7-game series iterations.',
    type: 'gif',
    sizeBytes: 191437,
  },
  {
    id: 'gif_playoff_prob_bump',
    filename: 'gif_playoff_prob_bump.gif',
    title: 'Playoff Seed & Play-In Leverage Bump Trajectory',
    category: 'playoffs',
    description: 'Playoff seed certainty and play-in tournament threshold trajectories across Eastern and Western conference contenders.',
    type: 'gif',
    sizeBytes: 291296,
  },
];

export interface GalleryClientProps {
  mediaItems?: VisualMediaItem[];
}

export const GalleryClient: React.FC<GalleryClientProps> = ({ mediaItems = NBA_GALLERY_ITEMS }) => {
  const [selectedCategory, setSelectedCategory] = useState<string>('ALL');
  const [searchQuery, setSearchQuery] = useState<string>('');
  const [activeMedia, setActiveMedia] = useState<VisualMediaItem | null>(null);

  const categories = useMemo(() => {
    const set = new Set(mediaItems.map((m) => m.category).filter(Boolean));
    return ['ALL', ...Array.from(set).sort()];
  }, [mediaItems]);

  const filteredMedia = useMemo(() => {
    return mediaItems.filter((item) => {
      const matchesSearch =
        item.title.toLowerCase().includes(searchQuery.toLowerCase()) ||
        item.filename.toLowerCase().includes(searchQuery.toLowerCase()) ||
        (item.description && item.description.toLowerCase().includes(searchQuery.toLowerCase()));

      const matchesCategory = selectedCategory === 'ALL' || item.category === selectedCategory;

      return matchesSearch && matchesCategory;
    });
  }, [mediaItems, searchQuery, selectedCategory]);

  return (
    <div className="space-y-8">
      {/* Header */}
      <div>
        <div className="flex items-center gap-2 mb-1">
          <span className="text-xs font-mono font-medium text-emerald-400 bg-emerald-950/60 border border-emerald-800/60 px-2 py-0.5 rounded-full">
            Pipeline Visual Gallery
          </span>
          <span className="text-xs font-mono text-slate-400">
            {mediaItems.length} Visual Artifacts Synced
          </span>
        </div>
        <h1 className="text-2xl sm:text-3xl font-bold tracking-tight text-white">
          Automated Visualizations & Dynamic Race Gallery
        </h1>
        <p className="text-slate-400 text-sm mt-1 max-w-3xl">
          High-resolution animated races, weekly Elo trajectory plots, division standing progressions,
          and opponent-adjusted heatmaps generated directly by the R analytical pipeline.
        </p>
      </div>

      {/* Filter and Category Pills */}
      <div className="flex flex-col sm:flex-row gap-3 items-center justify-between bg-surface-raised/90 border border-slate-800 p-3.5 rounded-xl">
        {/* Category Pills */}
        <div className="flex items-center gap-1.5 overflow-x-auto w-full sm:w-auto pb-1 sm:pb-0">
          {categories.map((cat) => (
            <button
              key={cat}
              onClick={() => setSelectedCategory(cat)}
              className={`px-3 py-1.5 rounded-lg text-xs font-mono capitalize whitespace-nowrap transition-all ${
                selectedCategory === cat
                  ? 'bg-accent-500 text-slate-950 font-bold shadow-md'
                  : 'bg-surface text-slate-400 hover:text-white border border-slate-800'
              }`}
            >
              {cat === 'ALL' ? 'All Visuals' : cat}
            </button>
          ))}
        </div>

        {/* Search */}
        <div className="relative w-full sm:w-72">
          <Search className="w-4 h-4 text-slate-400 absolute left-3 top-1/2 -translate-y-1/2" />
          <input
            type="text"
            placeholder="Search visual title or file..."
            value={searchQuery}
            onChange={(e) => setSearchQuery(e.target.value)}
            className="w-full bg-surface border border-slate-800 rounded-lg pl-9 pr-3 py-1.5 text-xs text-white placeholder-slate-500 focus:outline-none focus:border-emerald-500"
          />
        </div>
      </div>

      {/* Media Grid */}
      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
        {filteredMedia.map((item) => {
          const isGif = item.type === 'gif' || item.filename.endsWith('.gif');
          const mediaUrl = `${BASE_PATH}/media/${item.filename}`;
          const companionPng = `${BASE_PATH}/media/${item.id}.png`;

          return (
            <div
              key={item.filename}
              className="bg-surface-raised/90 border border-slate-800 hover:border-slate-700 rounded-xl overflow-hidden shadow-lg flex flex-col justify-between group transition-all"
            >
              <div>
                {/* Media Preview Box */}
                <div
                  className="relative w-full aspect-video bg-surface border-b border-slate-800 cursor-pointer overflow-hidden flex items-center justify-center"
                  onClick={() => setActiveMedia(item)}
                >
                  <picture className="w-full h-full">
                    <source media="(prefers-reduced-motion: reduce)" srcSet={companionPng} />
                    {/* eslint-disable-next-line @next/next/no-img-element */}
                    <img
                      src={mediaUrl}
                      alt={item.title}
                      className="w-full h-full object-cover group-hover:scale-105 transition-transform duration-300"
                    />
                  </picture>

                  {/* Badge Overlay */}
                  <div className="absolute top-2.5 left-2.5 flex items-center gap-1.5">
                    <span className="bg-surface/80 backdrop-blur border border-slate-800 text-[10px] font-mono px-2 py-0.5 rounded text-white flex items-center gap-1">
                      {isGif ? <Film className="w-3 h-3 text-cyan-400" /> : <ImageIcon className="w-3 h-3 text-emerald-400" />}
                      {isGif ? 'ANIMATION' : 'STATIC PLOT'}
                    </span>
                  </div>

                  {/* Hover Maximizer Icon */}
                  <div className="absolute inset-0 bg-surface/40 opacity-0 group-hover:opacity-100 flex items-center justify-center transition-opacity">
                    <span className="p-2.5 rounded-full bg-surface-raised/90 text-white border border-slate-700 shadow-xl flex items-center gap-1.5 text-xs font-mono">
                      <Maximize2 className="w-4 h-4 text-emerald-400" /> Fullscreen
                    </span>
                  </div>
                </div>

                {/* Details */}
                <div className="p-4">
                  <div className="flex items-start justify-between gap-2 mb-1">
                    <h2 className="text-sm font-semibold text-white group-hover:text-emerald-400 transition-colors">
                      {item.title}
                    </h2>
                  </div>
                  <p className="text-xs text-slate-400 line-clamp-2 leading-relaxed">
                    {item.description || 'Generated by R automated pipeline.'}
                  </p>
                </div>
              </div>

              {/* Card Footer */}
              <div className="px-4 py-2.5 bg-surface/60 border-t border-slate-800/80 flex items-center justify-between text-[11px] font-mono text-slate-400">
                <span className="capitalize">{item.category}</span>
                {item.sizeBytes && (
                  <span className="text-slate-500">{(item.sizeBytes / 1024).toFixed(0)} KB</span>
                )}
              </div>
            </div>
          );
        })}
      </div>

      {/* Fullscreen Modal View */}
      {activeMedia && (
        <div className="fixed inset-0 z-50 bg-surface/80 backdrop-blur-md flex items-center justify-center p-4">
          <div className="bg-surface-raised border border-slate-800 rounded-2xl max-w-4xl w-full max-h-[90vh] overflow-hidden flex flex-col shadow-2xl">
            {/* Modal Header */}
            <div className="flex items-center justify-between p-4 border-b border-slate-800">
              <div>
                <h2 className="text-base font-bold text-white flex items-center gap-2">
                  {activeMedia.title}
                  <span className="text-xs font-mono font-normal text-emerald-400 bg-emerald-950 px-2 py-0.5 rounded border border-emerald-800">
                    {activeMedia.category}
                  </span>
                </h2>
                <p className="text-xs text-slate-400 font-mono mt-0.5">{activeMedia.filename}</p>
              </div>
              <button
                onClick={() => setActiveMedia(null)}
                className="p-1.5 rounded-lg bg-slate-800 hover:bg-slate-700 text-slate-400 hover:text-white transition-colors"
                aria-label="Close modal"
              >
                <X className="w-5 h-5" />
              </button>
            </div>

            {/* Modal Image Display */}
            <div className="p-4 bg-surface flex items-center justify-center overflow-auto max-h-[65vh]">
              {/* eslint-disable-next-line @next/next/no-img-element */}
              <img
                src={`${BASE_PATH}/media/${activeMedia.filename}`}
                alt={activeMedia.title}
                className="max-h-[60vh] max-w-full object-contain rounded-lg border border-slate-800"
              />
            </div>

            {/* Modal Footer */}
            <div className="p-4 border-t border-slate-800 flex items-center justify-between text-xs text-slate-400">
              <span>{activeMedia.description}</span>
              <div className="flex items-center gap-2">
                <a
                  href={`${BASE_PATH}/media/${activeMedia.id}.png`}
                  download={`${activeMedia.id}.png`}
                  className="flex items-center gap-1.5 px-3 py-1.5 rounded bg-surface border border-slate-700 text-slate-200 font-bold font-mono hover:bg-slate-800 transition-colors"
                >
                  <Download className="w-4 h-4 text-slate-400" /> PNG Frame
                </a>
                <a
                  href={`${BASE_PATH}/media/${activeMedia.filename}`}
                  download={activeMedia.filename}
                  className="flex items-center gap-1.5 px-3 py-1.5 rounded bg-emerald-500 text-slate-950 font-bold font-mono hover:bg-emerald-400 transition-colors"
                >
                  <Download className="w-4 h-4" /> Download GIF
                </a>
              </div>
            </div>
          </div>
        </div>
      )}
    </div>
  );
};

export default GalleryClient;
