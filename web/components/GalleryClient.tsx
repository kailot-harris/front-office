'use client';

import React, { useState, useMemo } from 'react';
import { Film, Image as ImageIcon, Search, Download, Maximize2, X } from 'lucide-react';
import { BASE_PATH } from '@/lib/basePath';

export interface VisualMediaItem {
  id: string;
  filename: string;
  title: string;
  category: 'standings' | 'efficiency' | 'playoffs' | 'shots' | 'predictions' | 'players';
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
    id: 'gif_division_standings_race',
    filename: 'gif_division_standings_race.gif',
    title: 'Division Standings Wins Race',
    category: 'standings',
    description: 'Animated cumulative regular season wins race faceted across all 6 NBA divisions.',
    type: 'gif',
    sizeBytes: 325429,
  },
  {
    id: 'gif_elo_heatmap',
    filename: 'gif_elo_heatmap.gif',
    title: 'Elo Rating & Momentum Heatmap Matrix',
    category: 'standings',
    description: '2D timeline tile matrix mapping weekly Elo rating evolution and momentum shifts across all 30 NBA teams.',
    type: 'gif',
    sizeBytes: 466990,
  },
  {
    id: 'gif_elo_delta_race',
    filename: 'gif_elo_delta_race.gif',
    title: 'Week-over-Week Elo Momentum Race',
    category: 'standings',
    description: 'Power rankings Elo delta bar race displaying surging risers and fallers over time.',
    type: 'gif',
    sizeBytes: 304919,
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
    id: 'gif_pace_efficiency_quadrant',
    filename: 'gif_pace_efficiency_quadrant.gif',
    title: 'Pace vs Net Rating Efficiency Matrix',
    category: 'efficiency',
    description: 'Pace (possessions/48 min) vs Net Rating scatter animating team tactical styles from fast & dominant to methodical grinders.',
    type: 'gif',
    sizeBytes: 314566,
  },
  {
    id: 'gif_pf_pa_scatter_elo',
    filename: 'gif_pf_pa_scatter_elo.gif',
    title: 'Points Scored vs Allowed & Elo Bubble Matrix',
    category: 'efficiency',
    description: 'Offensive output vs defensive resistance scatter with team bubbles dynamically scaled by Elo rating and parity diagonal.',
    type: 'gif',
    sizeBytes: 351496,
  },
  {
    id: 'gif_turnover_margin_race',
    filename: 'gif_turnover_margin_race.gif',
    title: 'Turnover Differential & Ball Security Race',
    category: 'efficiency',
    description: 'Cumulative turnover margin bar race tracking ball security and opponent turnovers forced across all 30 NBA teams.',
    type: 'gif',
    sizeBytes: 290302,
  },
  {
    id: 'gif_upset_timeline',
    filename: 'gif_upset_timeline.gif',
    title: 'Underdog Upset Timeline & Giant-Killer Tracker',
    category: 'standings',
    description: 'Chronological timeline of underdog upsets where pre-game win expectation was under 43%, tracking giant-killing franchises.',
    type: 'gif',
    sizeBytes: 274186,
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
  {
    id: 'gif_player_shot_chart',
    filename: 'gif_player_shot_chart.gif',
    title: 'Player Shot Evolution & Spatial Density Progression',
    category: 'shots',
    description: 'Animated rolling shot distribution and field goal efficiency evolution on regulation NBA half-court with reduced-motion static PNG fallback.',
    type: 'gif',
    sizeBytes: 35689,
  },
  {
    id: 'nba_predictions_today',
    filename: 'nba_predictions_2026-10-20.png',
    title: 'Daily Game Model Predictions & Win Probability Spreads',
    category: 'predictions',
    description: 'Stylized game-day projection graphic illustrating model win probability spreads and projected home/away differentials across slate matchups.',
    type: 'image',
    sizeBytes: 128704,
  },
  {
    id: 'gif_rapm_race',
    filename: 'gif_rapm_race.gif',
    title: 'Top-10 Offensive & Defensive RAPM Bar Race',
    category: 'players',
    description: 'Top-10 Offensive and Defensive Regularized Adjusted Plus-Minus (ORAPM/DRAPM) bar race with ridge shrinkage confidence intervals scaling across sample sizes.',
    type: 'gif',
    sizeBytes: 523082,
  },
  {
    id: 'gif_clutch_shot_worm',
    filename: 'gif_clutch_shot_worm.gif',
    title: 'Clutch Win Probability Worm & Shot Locations',
    category: 'shots',
    description: 'Late-game win probability and score margin worm paired synchronously with half-court shot locations in the final 5 minutes of high-leverage close games.',
    type: 'gif',
    sizeBytes: 297650,
  },
  {
    id: 'gif_rookie_impact_race',
    filename: 'gif_rookie_impact_race.gif',
    title: 'Rookie Class Scoring Volume & Efficiency Accumulator',
    category: 'players',
    description: 'Rookie class scoring volume vs. True Shooting percentage accumulator race with bubbles sized by game appearances.',
    type: 'gif',
    sizeBytes: 472331,
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
