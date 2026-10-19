'use client';

import React, { useState, useMemo } from 'react';
import { PlayerProjection, PlayerSpatialMap, PlayerBattedBall, PlayerPitchItem } from '@/lib/types';
import {
  Compass,
  Crosshair,
  Target,
  Zap,
  Activity,
  Flame,
  CheckCircle2,
  X,
} from 'lucide-react';
import { BallparkFieldSvg } from '@/components/BallparkFieldSvg';

interface PlayerSpatialDropdownProps {
  player: PlayerProjection;
  spatialData?: PlayerSpatialMap | null;
  onClose: () => void;
}

const PITCH_COLORS: Record<string, { bg: string; text: string; fill: string; border: string }> = {
  FF: { bg: 'bg-rose-500/20', text: 'text-rose-400', fill: '#f43f5e', border: '#e11d48' },
  FA: { bg: 'bg-rose-500/20', text: 'text-rose-400', fill: '#f43f5e', border: '#e11d48' },
  SI: { bg: 'bg-amber-500/20', text: 'text-amber-400', fill: '#f59e0b', border: '#d97706' },
  FC: { bg: 'bg-yellow-500/20', text: 'text-yellow-400', fill: '#eab308', border: '#ca8a04' },
  SL: { bg: 'bg-cyan-500/20', text: 'text-cyan-400', fill: '#06b6d4', border: '#0891b2' },
  ST: { bg: 'bg-sky-500/20', text: 'text-sky-400', fill: '#0ea5e9', border: '#0284c7' },
  CH: { bg: 'bg-emerald-500/20', text: 'text-emerald-400', fill: '#10b981', border: '#059669' },
  FS: { bg: 'bg-fuchsia-500/20', text: 'text-fuchsia-400', fill: '#d946ef', border: '#c026d3' },
  CU: { bg: 'bg-purple-500/20', text: 'text-purple-400', fill: '#a855f7', border: '#9333ea' },
  KC: { bg: 'bg-indigo-500/20', text: 'text-indigo-400', fill: '#6366f1', border: '#4f46e5' },
  SV: { bg: 'bg-violet-500/20', text: 'text-violet-400', fill: '#8b5cf6', border: '#7c3aed' },
  KN: { bg: 'bg-slate-500/20', text: 'text-slate-300', fill: '#94a3b8', border: '#64748b' },
};

const HIT_COLORS: Record<string, { fill: string; stroke: string; label: string; textClass: string }> = {
  'Home Run': { fill: '#ef4444', stroke: '#fee2e2', label: 'Home Run', textClass: 'text-rose-400' },
  'Triple': { fill: '#a855f7', stroke: '#f3e8ff', label: 'Triple', textClass: 'text-purple-400' },
  'Double': { fill: '#06b6d4', stroke: '#cffafe', label: 'Double', textClass: 'text-cyan-400' },
  'Single': { fill: '#10b981', stroke: '#d1fae5', label: 'Single', textClass: 'text-emerald-400' },
  'Out': { fill: '#64748b', stroke: '#334155', label: 'Out', textClass: 'text-slate-400' },
};

export const PlayerSpatialDropdown: React.FC<PlayerSpatialDropdownProps> = ({
  player,
  spatialData,
  onClose,
}) => {
  const isBatter = player.player_type === 'Batter';

  // Batter state
  const [batterFilter, setBatterFilter] = useState<'all' | 'hits' | 'hrs' | 'xbh' | 'hard_hit'>('all');
  const [hoveredBall, setHoveredBall] = useState<PlayerBattedBall | null>(null);

  // Pitcher state
  const [pitcherFilter, setPitcherFilter] = useState<string>('all');
  const [hoveredPitch, setHoveredPitch] = useState<PlayerPitchItem | null>(null);

  // Filtered batted balls
  const displayedBalls = useMemo(() => {
    if (!spatialData?.batted_balls) return [];
    const list = spatialData.batted_balls;
    if (batterFilter === 'hits') {
      return list.filter((b) => b.hit_type !== 'Out');
    }
    if (batterFilter === 'hrs') {
      return list.filter((b) => b.hit_type === 'Home Run');
    }
    if (batterFilter === 'xbh') {
      return list.filter((b) => b.hit_type === 'Double' || b.hit_type === 'Triple' || b.hit_type === 'Home Run');
    }
    if (batterFilter === 'hard_hit') {
      return list.filter((b) => b.ev >= 95.0);
    }
    return list;
  }, [spatialData?.batted_balls, batterFilter]);

  // Filtered pitches
  const displayedPitches = useMemo(() => {
    if (!spatialData?.pitches) return [];
    const list = spatialData.pitches;
    if (pitcherFilter === 'strikes') {
      return list.filter((p) => p.is_strike);
    }
    if (pitcherFilter === 'whiffs') {
      return list.filter((p) => p.result === 'swinging_strike');
    }
    if (pitcherFilter !== 'all') {
      return list.filter((p) => p.pitch_type === pitcherFilter);
    }
    return list;
  }, [spatialData?.pitches, pitcherFilter]);

  if (!spatialData) {
    return (
      <div className="p-8 text-center bg-slate-900/90 border border-slate-800 rounded-xl space-y-3">
        <div className="w-6 h-6 border-2 border-indigo-500 border-t-transparent rounded-full animate-spin mx-auto" />
        <div className="text-sm font-semibold text-slate-300">
          Loading spatial mapping telemetry for {player.player_name}...
        </div>
      </div>
    );
  }

  return (
    <div className="relative bg-slate-950/95 border border-indigo-500/30 rounded-xl p-5 shadow-2xl backdrop-blur-md space-y-5 animate-in fade-in duration-200">
      {/* Top Header Bar */}
      <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-4 border-b border-slate-800/80 pb-4">
        <div className="flex items-center gap-3">
          <div className="p-2.5 rounded-lg bg-indigo-500/10 border border-indigo-500/20 text-indigo-400">
            {isBatter ? <Compass className="w-5 h-5" /> : <Crosshair className="w-5 h-5" />}
          </div>
          <div>
            <div className="flex items-center gap-2">
              <h3 className="text-lg font-black text-white">{player.player_name}</h3>
              <span className="text-xs font-mono px-2 py-0.5 rounded bg-slate-800 text-slate-300">
                {player.team} • {player.position}
              </span>
              {spatialData.is_statcast_tracked ? (
                <span className="flex items-center gap-1 text-[11px] font-semibold px-2 py-0.5 rounded-full bg-emerald-500/15 text-emerald-400 border border-emerald-500/30">
                  <CheckCircle2 className="w-3 h-3" />
                  Verified Statcast Tracked
                </span>
              ) : (
                <span className="flex items-center gap-1 text-[11px] font-semibold px-2 py-0.5 rounded-full bg-indigo-500/15 text-indigo-300 border border-indigo-500/30">
                  <Zap className="w-3 h-3" />
                  Calibrated Statcast Trajectory
                </span>
              )}
            </div>
            <p className="text-xs text-slate-400 mt-0.5">
              {isBatter
                ? `Field Spray Chart & 3D Batted Ball Geometry (${spatialData.sample_size} Tracked Events)`
                : `Strike Zone Heatmap, Arsenal Breaks & Plate Geometry (${spatialData.sample_size} Tracked Pitches)`}
            </p>
          </div>
        </div>

        {/* Filter Controls & Close Button */}
        <div className="flex items-center gap-2 flex-wrap">
          {isBatter ? (
            <div className="inline-flex rounded-lg bg-slate-900 border border-slate-800 p-0.5 text-xs font-medium flex-wrap gap-0.5">
              <button
                type="button"
                onClick={() => setBatterFilter('all')}
                className={`px-2.5 py-1.5 rounded-md transition-colors ${
                  batterFilter === 'all'
                    ? 'bg-indigo-600 text-white font-bold'
                    : 'text-slate-400 hover:text-white'
                }`}
              >
                All Balls ({spatialData.batted_balls?.length ?? 0})
              </button>
              <button
                type="button"
                onClick={() => setBatterFilter('hits')}
                className={`px-2.5 py-1.5 rounded-md transition-colors ${
                  batterFilter === 'hits'
                    ? 'bg-indigo-600 text-white font-bold'
                    : 'text-slate-400 hover:text-white'
                }`}
              >
                Hits ({spatialData.batter_summary?.hits ?? 0})
              </button>
              <button
                type="button"
                onClick={() => setBatterFilter('hrs')}
                className={`px-2.5 py-1.5 rounded-md transition-colors ${
                  batterFilter === 'hrs'
                    ? 'bg-indigo-600 text-white font-bold'
                    : 'text-slate-400 hover:text-white'
                }`}
              >
                HRs ({spatialData.batter_summary?.home_runs ?? 0})
              </button>
              <button
                type="button"
                onClick={() => setBatterFilter('xbh')}
                className={`px-2.5 py-1.5 rounded-md transition-colors ${
                  batterFilter === 'xbh'
                    ? 'bg-indigo-600 text-white font-bold'
                    : 'text-slate-400 hover:text-white'
                }`}
              >
                XBH
              </button>
              <button
                type="button"
                onClick={() => setBatterFilter('hard_hit')}
                className={`px-2.5 py-1.5 rounded-md transition-colors ${
                  batterFilter === 'hard_hit'
                    ? 'bg-indigo-600 text-white font-bold'
                    : 'text-slate-400 hover:text-white'
                }`}
              >
                95+ mph ({spatialData.batted_balls?.filter((b) => b.ev >= 95.0).length ?? 0})
              </button>
            </div>
          ) : (
            <div className="inline-flex rounded-lg bg-slate-900 border border-slate-800 p-0.5 text-xs font-medium flex-wrap gap-0.5">
              <button
                type="button"
                onClick={() => setPitcherFilter('all')}
                className={`px-2.5 py-1.5 rounded-md transition-colors ${
                  pitcherFilter === 'all'
                    ? 'bg-indigo-600 text-white font-bold'
                    : 'text-slate-400 hover:text-white'
                }`}
              >
                All Pitches ({spatialData.pitches?.length ?? 0})
              </button>
              <button
                type="button"
                onClick={() => setPitcherFilter('whiffs')}
                className={`px-2.5 py-1.5 rounded-md transition-colors ${
                  pitcherFilter === 'whiffs'
                    ? 'bg-indigo-600 text-white font-bold'
                    : 'text-slate-400 hover:text-white'
                }`}
              >
                Whiffs ({spatialData.pitches?.filter((p) => p.result === 'swinging_strike').length ?? 0})
              </button>
              <button
                type="button"
                onClick={() => setPitcherFilter('strikes')}
                className={`px-2.5 py-1.5 rounded-md transition-colors ${
                  pitcherFilter === 'strikes'
                    ? 'bg-indigo-600 text-white font-bold'
                    : 'text-slate-400 hover:text-white'
                }`}
              >
                Strikes
              </button>
              {spatialData.pitcher_summary?.arsenal.slice(0, 5).map((a) => (
                <button
                  key={a.pitch_type}
                  type="button"
                  onClick={() => setPitcherFilter(pitcherFilter === a.pitch_type ? 'all' : a.pitch_type)}
                  className={`px-2.5 py-1.5 rounded-md transition-colors ${
                    pitcherFilter === a.pitch_type
                      ? 'bg-indigo-600 text-white font-bold'
                      : 'text-slate-400 hover:text-white'
                  }`}
                >
                  {a.pitch_type} ({a.count})
                </button>
              ))}
            </div>
          )}

          <button
            type="button"
            onClick={onClose}
            className="p-1.5 rounded-lg bg-slate-800/80 hover:bg-slate-700 text-slate-400 hover:text-white transition-colors"
            title="Close Map"
          >
            <X className="w-4 h-4" />
          </button>
        </div>
      </div>

      {/* Main Interactive Map & Analytics Body */}
      {isBatter ? (
        /* BATTER SPRAY CHART & SUMMARY */
        <div className="grid grid-cols-1 lg:grid-cols-12 gap-6 items-start">
          {/* Left Column: Field SVG Spray Chart with Accurate Multi-Segment Ballpark Geometries */}
          <div className="lg:col-span-7 bg-slate-900/90 border border-slate-800 rounded-xl p-4 flex flex-col items-center relative">
            <BallparkFieldSvg
              initialTeam={player.team}
              battedBalls={displayedBalls}
              hoveredBall={hoveredBall}
              onHoverBall={setHoveredBall}
              showParkSelector={true}
            />

            {/* Chart Legend */}
            <div className="flex items-center justify-center gap-4 flex-wrap mt-2 text-xs font-mono">
              {Object.entries(HIT_COLORS).map(([key, cfg]) => (
                <div key={key} className="flex items-center gap-1.5">
                  <span className="w-2.5 h-2.5 rounded-full" style={{ backgroundColor: cfg.fill }} />
                  <span className="text-slate-300">{cfg.label}</span>
                </div>
              ))}
            </div>
          </div>


          {/* Right Column: Quantitative Batter Analytics */}
          <div className="lg:col-span-5 space-y-4">
            {/* 4 Metric Badges */}
            <div className="grid grid-cols-2 gap-3">
              <div className="bg-slate-900/90 border border-slate-800 rounded-xl p-3.5 space-y-1">
                <div className="text-[11px] text-slate-400 font-mono flex items-center justify-between">
                  <span>AVG EXIT VELO</span>
                  <Flame className="w-3.5 h-3.5 text-amber-400" />
                </div>
                <div className="text-xl font-mono font-bold text-white">
                  {spatialData.batter_summary?.avg_ev ?? 0}{' '}
                  <span className="text-xs text-slate-400 font-normal">mph</span>
                </div>
                <div className="text-[10px] text-amber-400 font-mono">
                  Hard Hit: {spatialData.batter_summary?.hard_hit_pct ?? 0}% (≥95 mph)
                </div>
              </div>

              <div className="bg-slate-900/90 border border-slate-800 rounded-xl p-3.5 space-y-1">
                <div className="text-[11px] text-slate-400 font-mono flex items-center justify-between">
                  <span>PEAK EXIT VELO</span>
                  <Zap className="w-3.5 h-3.5 text-rose-400" />
                </div>
                <div className="text-xl font-mono font-bold text-rose-400">
                  {spatialData.batter_summary?.max_ev ?? 0}{' '}
                  <span className="text-xs text-slate-400 font-normal">mph</span>
                </div>
                <div className="text-[10px] text-slate-400 font-mono">Max projected barrel</div>
              </div>

              <div className="bg-slate-900/90 border border-slate-800 rounded-xl p-3.5 space-y-1">
                <div className="text-[11px] text-slate-400 font-mono flex items-center justify-between">
                  <span>MAX DISTANCE</span>
                  <Target className="w-3.5 h-3.5 text-sky-400" />
                </div>
                <div className="text-xl font-mono font-bold text-white">
                  {spatialData.batter_summary?.max_dist ?? 0}{' '}
                  <span className="text-xs text-slate-400 font-normal">ft</span>
                </div>
                <div className="text-[10px] text-sky-400 font-mono">
                  Avg LA: {spatialData.batter_summary?.avg_la ?? 0}°
                </div>
              </div>

              <div className="bg-slate-900/90 border border-slate-800 rounded-xl p-3.5 space-y-1">
                <div className="text-[11px] text-slate-400 font-mono flex items-center justify-between">
                  <span>HITS / HOME RUNS</span>
                  <Compass className="w-3.5 h-3.5 text-emerald-400" />
                </div>
                <div className="text-xl font-mono font-bold text-emerald-400">
                  {spatialData.batter_summary?.hits ?? 0}{' '}
                  <span className="text-xs text-slate-400 font-normal">
                    ({spatialData.batter_summary?.home_runs ?? 0} HR)
                  </span>
                </div>
                <div className="text-[10px] text-slate-400 font-mono">
                  Sample: {spatialData.batter_summary?.total_balls ?? 0} balls
                </div>
              </div>
            </div>

            {/* Directional Spray Distribution (Pull / Center / Oppo) */}
            <div className="bg-slate-900/90 border border-slate-800 rounded-xl p-4 space-y-3">
              <div className="flex items-center justify-between text-xs">
                <span className="font-semibold text-white">Directional Spray Distribution</span>
                <span className="text-[11px] text-slate-400 font-mono">Shift Sensitivity</span>
              </div>

              {/* Stacked Percentage Bar */}
              <div className="w-full h-3 rounded-full overflow-hidden flex bg-slate-950 border border-slate-800">
                <div
                  style={{ width: `${spatialData.batter_summary?.pull_pct ?? 35}%` }}
                  className="bg-indigo-500 transition-all duration-300"
                  title={`Pull: ${spatialData.batter_summary?.pull_pct ?? 0}%`}
                />
                <div
                  style={{ width: `${spatialData.batter_summary?.center_pct ?? 35}%` }}
                  className="bg-sky-500 transition-all duration-300"
                  title={`Center: ${spatialData.batter_summary?.center_pct ?? 0}%`}
                />
                <div
                  style={{ width: `${spatialData.batter_summary?.oppo_pct ?? 30}%` }}
                  className="bg-emerald-500 transition-all duration-300"
                  title={`Oppo: ${spatialData.batter_summary?.oppo_pct ?? 0}%`}
                />
              </div>

              <div className="grid grid-cols-3 text-center text-xs font-mono pt-1">
                <div>
                  <div className="text-indigo-400 font-bold">
                    {spatialData.batter_summary?.pull_pct ?? 0}%
                  </div>
                  <div className="text-[10px] text-slate-400">Pull Field</div>
                </div>
                <div>
                  <div className="text-sky-400 font-bold">
                    {spatialData.batter_summary?.center_pct ?? 0}%
                  </div>
                  <div className="text-[10px] text-slate-400">Center Field</div>
                </div>
                <div>
                  <div className="text-emerald-400 font-bold">
                    {spatialData.batter_summary?.oppo_pct ?? 0}%
                  </div>
                  <div className="text-[10px] text-slate-400">Opposite Field</div>
                </div>
              </div>
            </div>

            {/* Recent Batted Ball Inspect Box */}
            <div className="bg-slate-900/80 border border-slate-800/80 rounded-xl p-3.5 text-xs space-y-2">
              <div className="flex items-center justify-between text-slate-300 font-semibold">
                <span>Selected Batted Ball Telemetry</span>
                <span className="text-[10px] font-mono text-slate-500">Hover or click any dot</span>
              </div>
              {hoveredBall ? (
                <div className="p-2.5 rounded-lg bg-slate-950 border border-slate-800 font-mono text-xs space-y-1">
                  <div className="flex items-center justify-between">
                    <span className="text-white font-bold">{hoveredBall.event}</span>
                    <span className={HIT_COLORS[hoveredBall.hit_type]?.textClass ?? 'text-white'}>
                      {hoveredBall.hit_type}
                    </span>
                  </div>
                  <div className="text-[11px] text-slate-400 flex items-center justify-between pt-1">
                    <span>
                      Exit Velocity: <strong className="text-white">{hoveredBall.ev} mph</strong>
                    </span>
                    <span>
                      Distance: <strong className="text-white">{hoveredBall.dist} ft</strong>
                    </span>
                  </div>
                  <div className="text-[11px] text-slate-400 flex items-center justify-between">
                    <span>
                      Launch Angle: <strong className="text-white">{hoveredBall.la}°</strong>
                    </span>
                    <span>
                      Spray Bearing: <strong className="text-white">{hoveredBall.bearing}°</strong>
                    </span>
                  </div>
                </div>
              ) : (
                <div className="p-3 text-center text-slate-500 font-mono text-[11px]">
                  Hover over any dot on the field chart to view Statcast launch vector, exit velocity, and 30-ballpark HR outcome.
                </div>
              )}
            </div>
          </div>
        </div>
      ) : (
        /* PITCHER STRIKE ZONE & ARSENAL SUMMARY */
        <div className="grid grid-cols-1 lg:grid-cols-12 gap-6 items-start">
          {/* Left Column: Strike Zone SVG */}
          <div className="lg:col-span-6 bg-slate-900/90 border border-slate-800 rounded-xl p-4 flex flex-col items-center relative">
            <div className="w-full flex items-center justify-between text-xs text-slate-400 mb-2 font-mono">
              <span className="flex items-center gap-1.5">
                <span className="w-2 h-2 rounded-full bg-indigo-400" />
                <span>Catcher / Umpire Perspective</span>
              </span>
              <span>Plate Width [-0.85, +0.85 ft]</span>
            </div>

            {/* Strike Zone SVG Canvas */}
            <div className="relative w-full max-w-[420px] aspect-[420/400]">
              <svg viewBox="-2.2 0.3 4.4 4.5" className="w-full h-full overflow-visible select-none">
                <defs>
                  {/* Strike Zone Background Gradient */}
                  <linearGradient id="zoneGrad" x1="0" y1="0" x2="0" y2="1">
                    <stop offset="0%" stopColor="#1e1b4b" stopOpacity="0.4" />
                    <stop offset="100%" stopColor="#0f172a" stopOpacity="0.6" />
                  </linearGradient>
                </defs>

                {/* Home Plate at Ground Level (under the strike zone) */}
                <polygon
                  points="-0.71,4.05 0.71,4.05 0.71,4.20 0,4.35 -0.71,4.20"
                  fill="#334155"
                  stroke="#64748b"
                  strokeWidth="0.03"
                />

                {/* Batter Box Guidelines (Left & Right) */}
                <rect x="-1.9" y="1.3" width="0.7" height="2.7" fill="none" stroke="#1e293b" strokeWidth="0.03" strokeDasharray="0.08 0.08" rx="0.1" />
                <rect x="1.2" y="1.3" width="0.7" height="2.7" fill="none" stroke="#1e293b" strokeWidth="0.03" strokeDasharray="0.08 0.08" rx="0.1" />
                <text x="-1.55" y="2.7" fill="#334155" fontSize="0.18" textAnchor="middle" fontFamily="monospace">
                  RHB
                </text>
                <text x="1.55" y="2.7" fill="#334155" fontSize="0.18" textAnchor="middle" fontFamily="monospace">
                  LHB
                </text>

                {/* Outer Shadow Zone Perimeter (Chase Boundary: 1.1 to 3.9 ft z, ±1.15 ft x) */}
                <rect
                  x="-1.15"
                  y="1.1"
                  width="2.3"
                  height="2.8"
                  fill="none"
                  stroke="#1e293b"
                  strokeWidth="0.03"
                  strokeDasharray="0.05 0.05"
                  rx="0.08"
                />

                {/* Rulebook Strike Zone Box [-0.85 to 0.85 ft x, 1.5 to 3.5 ft z -> svg y 1.5 to 3.5] */}
                <rect
                  x="-0.85"
                  y="1.5"
                  width="1.7"
                  height="2.0"
                  fill="url(#zoneGrad)"
                  stroke="#6366f1"
                  strokeWidth="0.04"
                  rx="0.05"
                />

                {/* 3x3 Strike Zone Grid Lines */}
                <line x1="-0.283" y1="1.5" x2="-0.283" y2="3.5" stroke="#3730a3" strokeWidth="0.02" strokeDasharray="0.04 0.04" />
                <line x1="0.283" y1="1.5" x2="0.283" y2="3.5" stroke="#3730a3" strokeWidth="0.02" strokeDasharray="0.04 0.04" />
                <line x1="-0.85" y1="2.167" x2="0.85" y2="2.167" stroke="#3730a3" strokeWidth="0.02" strokeDasharray="0.04 0.04" />
                <line x1="-0.85" y1="2.833" x2="0.85" y2="2.833" stroke="#3730a3" strokeWidth="0.02" strokeDasharray="0.04 0.04" />

                {/* Standard MLB Statcast Zone Numbers: 1-3 (Top), 4-6 (Middle), 7-9 (Bottom) */}
                <text x="-0.56" y="1.9" fill="#4338ca" fontSize="0.14" textAnchor="middle" fontFamily="monospace">1</text>
                <text x="0" y="1.9" fill="#4338ca" fontSize="0.14" textAnchor="middle" fontFamily="monospace">2</text>
                <text x="0.56" y="1.9" fill="#4338ca" fontSize="0.14" textAnchor="middle" fontFamily="monospace">3</text>
                <text x="-0.56" y="2.57" fill="#4338ca" fontSize="0.14" textAnchor="middle" fontFamily="monospace">4</text>
                <text x="0" y="2.57" fill="#4338ca" fontSize="0.14" textAnchor="middle" fontFamily="monospace">5</text>
                <text x="0.56" y="2.57" fill="#4338ca" fontSize="0.14" textAnchor="middle" fontFamily="monospace">6</text>
                <text x="-0.56" y="3.24" fill="#4338ca" fontSize="0.14" textAnchor="middle" fontFamily="monospace">7</text>
                <text x="0" y="3.24" fill="#4338ca" fontSize="0.14" textAnchor="middle" fontFamily="monospace">8</text>
                <text x="0.56" y="3.24" fill="#4338ca" fontSize="0.14" textAnchor="middle" fontFamily="monospace">9</text>

                {/* Plotted Pitches */}
                {displayedPitches.map((pt, idx) => {
                  const colorConfig = PITCH_COLORS[pt.pitch_type] || PITCH_COLORS['FF'];
                  const isHovered = hoveredPitch === pt;
                  const isWhiff = pt.result === 'swinging_strike';

                  // Statcast Z coordinates:
                  // 3.5 ft (top of zone) -> svgY = 1.5
                  // 1.5 ft (bottom of zone) -> svgY = 3.5
                  // Ground level (0 ft) -> svgY = 5.0
                  const svgX = pt.px;
                  const svgY = 5.0 - pt.pz;

                  return (
                    <g
                      key={idx}
                      className="cursor-pointer transition-transform duration-150"
                      onMouseEnter={() => setHoveredPitch(pt)}
                      onMouseLeave={() => setHoveredPitch(null)}
                      onClick={() => setHoveredPitch(pt)}
                    >
                      {/* Whiff or hover halo */}
                      {(isWhiff || isHovered) && (
                        <circle
                          cx={svgX}
                          cy={svgY}
                          r={isHovered ? 0.16 : 0.12}
                          fill={colorConfig.fill}
                          fillOpacity={isHovered ? 0.4 : 0.25}
                        />
                      )}
                      <circle
                        cx={svgX}
                        cy={svgY}
                        r={isHovered ? 0.085 : isWhiff ? 0.075 : 0.06}
                        fill={colorConfig.fill}
                        stroke={isHovered ? '#ffffff' : colorConfig.border}
                        strokeWidth={0.015}
                      />
                    </g>
                  );
                })}
              </svg>

              {/* Pitch Tooltip Overlay */}
              {hoveredPitch && (
                <div className="absolute top-2 left-2 right-2 sm:right-auto sm:max-w-xs bg-slate-950/95 border border-indigo-500/40 rounded-lg p-3 shadow-xl pointer-events-none text-xs space-y-1.5 z-20 backdrop-blur-md">
                  <div className="flex items-center justify-between">
                    <span className="font-bold text-white flex items-center gap-1.5">
                      <span
                        className="w-2.5 h-2.5 rounded-full"
                        style={{ backgroundColor: PITCH_COLORS[hoveredPitch.pitch_type]?.fill ?? '#f43f5e' }}
                      />
                      {hoveredPitch.pitch_name} ({hoveredPitch.pitch_type})
                    </span>
                    <span className="font-mono text-amber-400 font-bold">{hoveredPitch.velo} mph</span>
                  </div>
                  <div className="grid grid-cols-2 gap-2 font-mono text-[11px] text-slate-300">
                    <div>
                      Result: <strong className="text-white capitalize">{hoveredPitch.result.replace('_', ' ')}</strong>
                    </div>
                    <div>
                      Zone: <strong className={hoveredPitch.in_zone ? 'text-emerald-400' : 'text-slate-400'}>
                        {hoveredPitch.in_zone ? 'In Zone' : 'Shadow/Ball'}
                      </strong>
                    </div>
                    <div>
                      H-Break: <strong className="text-white">{hoveredPitch.pfx_x}&quot;</strong>
                    </div>
                    <div>
                      IVB: <strong className="text-white">{hoveredPitch.pfx_z}&quot;</strong>
                    </div>
                  </div>
                </div>
              )}
            </div>

            {/* Pitch Type Legend */}
            <div className="flex items-center justify-center gap-3 flex-wrap mt-3 text-xs font-mono">
              {spatialData.pitcher_summary?.arsenal.map((a) => {
                const colorConfig = PITCH_COLORS[a.pitch_type] || PITCH_COLORS['FF'];
                return (
                  <button
                    key={a.pitch_type}
                    type="button"
                    onClick={() => setPitcherFilter(pitcherFilter === a.pitch_type ? 'all' : a.pitch_type)}
                    className={`flex items-center gap-1.5 px-2 py-0.5 rounded transition-all ${
                      pitcherFilter === a.pitch_type ? 'bg-white/10 ring-1 ring-white' : 'hover:bg-slate-800'
                    }`}
                  >
                    <span className="w-2.5 h-2.5 rounded-full" style={{ backgroundColor: colorConfig.fill }} />
                    <span className="text-slate-300">{a.pitch_type}</span>
                    <span className="text-[10px] text-slate-500 font-mono">({a.avg_velo} mph)</span>
                  </button>
                );
              })}
            </div>
          </div>

          {/* Right Column: Pitcher Command & Arsenal Metrics */}
          <div className="lg:col-span-6 space-y-4">
            {/* 4 Metric Badges */}
            <div className="grid grid-cols-2 gap-3">
              <div className="bg-slate-900/90 border border-slate-800 rounded-xl p-3.5 space-y-1">
                <div className="text-[11px] text-slate-400 font-mono flex items-center justify-between">
                  <span>AVG VELOCITY</span>
                  <Flame className="w-3.5 h-3.5 text-rose-400" />
                </div>
                <div className="text-xl font-mono font-bold text-white">
                  {spatialData.pitcher_summary?.avg_velo ?? 0}{' '}
                  <span className="text-xs text-slate-400 font-normal">mph</span>
                </div>
                <div className="text-[10px] text-rose-400 font-mono">
                  Peak: {spatialData.pitcher_summary?.max_velo ?? 0} mph
                </div>
              </div>

              <div className="bg-slate-900/90 border border-slate-800 rounded-xl p-3.5 space-y-1">
                <div className="text-[11px] text-slate-400 font-mono flex items-center justify-between">
                  <span>STRIKE %</span>
                  <Activity className="w-3.5 h-3.5 text-emerald-400" />
                </div>
                <div className="text-xl font-mono font-bold text-emerald-400">
                  {spatialData.pitcher_summary?.strike_pct ?? 0}%
                </div>
                <div className="text-[10px] text-slate-400 font-mono">
                  Called: {spatialData.pitcher_summary?.called_strike_pct ?? 0}%
                </div>
              </div>

              <div className="bg-slate-900/90 border border-slate-800 rounded-xl p-3.5 space-y-1">
                <div className="text-[11px] text-slate-400 font-mono flex items-center justify-between">
                  <span>ZONE RATE</span>
                  <Target className="w-3.5 h-3.5 text-indigo-400" />
                </div>
                <div className="text-xl font-mono font-bold text-indigo-300">
                  {spatialData.pitcher_summary?.zone_pct ?? 0}%
                </div>
                <div className="text-[10px] text-slate-400 font-mono">Rulebook 3x3 boundaries</div>
              </div>

              <div className="bg-slate-900/90 border border-slate-800 rounded-xl p-3.5 space-y-1">
                <div className="text-[11px] text-slate-400 font-mono flex items-center justify-between">
                  <span>WHIFF % (SWG STR)</span>
                  <Zap className="w-3.5 h-3.5 text-amber-400" />
                </div>
                <div className="text-xl font-mono font-bold text-amber-300">
                  {spatialData.pitcher_summary?.whiff_pct ?? 0}%
                </div>
                <div className="text-[10px] text-amber-400/80 font-mono">Swinging strike rate</div>
              </div>
            </div>

            {/* Arsenal Breakdown Table */}
            <div className="bg-slate-900/90 border border-slate-800 rounded-xl overflow-hidden shadow-lg">
              <div className="px-4 py-2.5 bg-slate-950/60 border-b border-slate-800 flex items-center justify-between text-xs">
                <span className="font-semibold text-white">Pitch Arsenal & 3D Movement Profiles</span>
                <span className="text-[11px] font-mono text-slate-400">IVB vs. HB (inches)</span>
              </div>
              <div className="overflow-x-auto">
                <table className="w-full text-left text-xs font-mono">
                  <thead className="bg-slate-950/40 text-slate-400 border-b border-slate-800/80">
                    <tr>
                      <th className="py-2 px-3">Pitch</th>
                      <th className="py-2 px-2 text-right">Usage</th>
                      <th className="py-2 px-2 text-right">Velo</th>
                      <th className="py-2 px-2 text-right">H-Break</th>
                      <th className="py-2 px-2 text-right">IVB</th>
                      <th className="py-2 px-3 text-right">Whiff %</th>
                    </tr>
                  </thead>
                  <tbody className="divide-y divide-slate-800/50">
                    {spatialData.pitcher_summary?.arsenal.map((a) => {
                      const colorConfig = PITCH_COLORS[a.pitch_type] || PITCH_COLORS['FF'];
                      return (
                        <tr
                          key={a.pitch_type}
                          onClick={() => setPitcherFilter(pitcherFilter === a.pitch_type ? 'all' : a.pitch_type)}
                          className={`hover:bg-slate-800/40 transition-colors cursor-pointer ${
                            pitcherFilter === a.pitch_type ? 'bg-indigo-950/30 font-bold' : ''
                          }`}
                        >
                          <td className="py-2 px-3">
                            <div className="flex items-center gap-1.5">
                              <span
                                className="w-2 h-2 rounded-full"
                                style={{ backgroundColor: colorConfig.fill }}
                              />
                              <span className="text-white font-semibold">{a.pitch_name}</span>
                              <span className="text-[10px] text-slate-400">({a.pitch_type})</span>
                            </div>
                          </td>
                          <td className="py-2 px-2 text-right text-slate-200">{a.pct}%</td>
                          <td className="py-2 px-2 text-right text-amber-300 font-bold">{a.avg_velo}</td>
                          <td className="py-2 px-2 text-right text-slate-300">
                            {a.avg_hb > 0 ? `+${a.avg_hb}"` : `${a.avg_hb}"`}
                          </td>
                          <td className="py-2 px-2 text-right text-slate-300">
                            {a.avg_ivb > 0 ? `+${a.avg_ivb}"` : `${a.avg_ivb}"`}
                          </td>
                          <td className="py-2 px-3 text-right text-rose-400 font-bold">{a.whiff_pct}%</td>
                        </tr>
                      );
                    })}
                  </tbody>
                </table>
              </div>
            </div>

            {/* Selected Pitch Inspect Box */}
            <div className="bg-slate-900/80 border border-slate-800/80 rounded-xl p-3.5 text-xs space-y-2">
              <div className="flex items-center justify-between text-slate-300 font-semibold">
                <span>Selected Pitch Telemetry</span>
                <span className="text-[10px] font-mono text-slate-500">Hover or click any pitch</span>
              </div>
              {hoveredPitch ? (
                <div className="p-2.5 rounded-lg bg-slate-950 border border-slate-800 font-mono text-xs space-y-1">
                  <div className="flex items-center justify-between">
                    <span className="text-white font-bold flex items-center gap-1.5">
                      <span
                        className="w-2 h-2 rounded-full"
                        style={{ backgroundColor: PITCH_COLORS[hoveredPitch.pitch_type]?.fill ?? '#f43f5e' }}
                      />
                      {hoveredPitch.pitch_name} ({hoveredPitch.pitch_type})
                    </span>
                    <span className="text-amber-300 font-bold">{hoveredPitch.velo} mph</span>
                  </div>
                  <div className="text-[11px] text-slate-400 flex items-center justify-between pt-1">
                    <span>
                      Result: <strong className="text-white capitalize">{hoveredPitch.result.replace('_', ' ')}</strong>
                    </span>
                    <span>
                      Zone Coord: <strong className="text-white">({hoveredPitch.px}&apos;, {hoveredPitch.pz}&apos;)</strong>
                    </span>
                  </div>
                  <div className="text-[11px] text-slate-400 flex items-center justify-between">
                    <span>
                      H-Break: <strong className="text-white">{hoveredPitch.pfx_x}&quot;</strong>
                    </span>
                    <span>
                      IVB: <strong className="text-white">{hoveredPitch.pfx_z}&quot;</strong>
                    </span>
                  </div>
                </div>
              ) : (
                <div className="p-3 text-center text-slate-500 font-mono text-[11px]">
                  Hover over any pitch dot in the strike zone to inspect velocity, horizontal break, induced vertical break, and umpire decision.
                </div>
              )}
            </div>
          </div>
        </div>
      )}
    </div>
  );
};
