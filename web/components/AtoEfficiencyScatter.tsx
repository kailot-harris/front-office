'use client';

import React, { useState, useRef } from 'react';
import { CoachingStaffMetric } from '@/lib/coachingTypes';
import { TeamLogo } from '@/components/TeamLogo';
import { Crosshair, Download } from 'lucide-react';
import { exportSvgAsPng } from '@/lib/exportSvgAsPng';

interface AtoEfficiencyScatterProps {
  coaches: CoachingStaffMetric[];
  selectedCoach: CoachingStaffMetric | null;
  onSelectCoach: (coach: CoachingStaffMetric) => void;
}

export const AtoEfficiencyScatter: React.FC<AtoEfficiencyScatterProps> = ({
  coaches,
  selectedCoach,
  onSelectCoach,
}) => {
  const [hoveredCoach, setHoveredCoach] = useState<CoachingStaffMetric | null>(null);
  const svgRef = useRef<SVGSVGElement | null>(null);

  const handleExportPng = () => {
    if (svgRef.current) {
      exportSvgAsPng(svgRef.current, 'ato-efficiency-scatter');
    }
  };

  // Bounds for axes
  // Offense PPP: 0.92 to 1.20
  // Defense PPP Allowed: 0.86 to 1.10 (Invert X so Right = Lower Allowed / Better Defense)
  const xMin = 1.10; // Left (weaker defense)
  const xMax = 0.86; // Right (elite defense)
  const yMin = 0.92; // Bottom (lower offensive PPP)
  const yMax = 1.20; // Top (elite offensive PPP)

  const width = 760;
  const height = 480;
  const padding = { top: 40, right: 40, bottom: 60, left: 60 };

  const innerWidth = width - padding.left - padding.right;
  const innerHeight = height - padding.top - padding.bottom;

  // Coordinate mappers
  // X: xMin (1.10) maps to 0, xMax (0.86) maps to innerWidth
  const scaleX = (val: number) => {
    return ((val - xMin) / (xMax - xMin)) * innerWidth;
  };

  // Y: yMin (0.92) maps to innerHeight, yMax (1.20) maps to 0
  const scaleY = (val: number) => {
    return innerHeight - ((val - yMin) / (yMax - yMin)) * innerHeight;
  };

  const midX = scaleX(0.98); // League median defensive PPP allowed
  const midY = scaleY(1.05); // League median offensive PPP

  return (
    <div className="bg-surface-raised/80 border border-slate-800 rounded-xl overflow-hidden shadow-lg p-5">
      {/* Header Info */}
      <div className="flex flex-wrap items-center justify-between gap-4 mb-4 pb-4 border-b border-slate-800">
        <div>
          <div className="flex items-center gap-2">
            <div className="p-1.5 rounded-lg bg-orange-500/10 text-orange-400">
              <Crosshair className="w-5 h-5" />
            </div>
            <h3 className="text-base font-bold text-white tracking-tight">
              In-Game ATO (After-Timeout) Tactical Matrix
            </h3>
            <span className="text-xs px-2 py-0.5 rounded-full bg-slate-800 border border-slate-700 text-slate-300 font-mono">
              30 Franchises
            </span>
          </div>
          <p className="text-xs text-slate-400 mt-1">
            Points Per Possession (PPP) on initial offensive sets post-timeout vs. opponent ATO suppression. Top-right denotes dual-threat mastery.
          </p>
        </div>

        {/* Legend pills */}
        <div className="flex items-center gap-3 text-xs">
          <div className="flex items-center gap-1.5 text-slate-400">
            <span className="w-2.5 h-2.5 rounded-full bg-emerald-500"></span>
            <span>CIR ≥ 80 (Elite)</span>
          </div>
          <div className="flex items-center gap-1.5 text-slate-400">
            <span className="w-2.5 h-2.5 rounded-full bg-amber-500"></span>
            <span>CIR 65-79</span>
          </div>
          <div className="flex items-center gap-1.5 text-slate-400">
            <span className="w-2.5 h-2.5 rounded-full bg-slate-500"></span>
            <span>CIR &lt; 65</span>
          </div>
          <button
            type="button"
            onClick={handleExportPng}
            title="Export PNG"
            aria-label="Export chart as PNG"
            className="p-1.5 rounded-lg border border-slate-800 text-slate-400 hover:text-white hover:border-slate-600 transition-colors"
          >
            <Download className="w-3.5 h-3.5" />
          </button>
        </div>
      </div>

      {/* SVG Canvas */}
      <div className="relative flex justify-center overflow-x-auto">
        <svg
          ref={svgRef}
          viewBox={`0 0 ${width} ${height}`}
          className="w-full max-w-[760px] select-none font-sans"
        >
          <g transform={`translate(${padding.left}, ${padding.top})`}>
            {/* Quadrant Background shading */}
            {/* Top-Right: Elite Dual Threat */}
            <rect
              x={midX}
              y={0}
              width={innerWidth - midX}
              height={midY}
              fill="#10b981"
              fillOpacity="0.04"
            />
            {/* Top-Left: Offensive Architects */}
            <rect
              x={0}
              y={0}
              width={midX}
              height={midY}
              fill="#6366f1"
              fillOpacity="0.03"
            />
            {/* Bottom-Right: Defensive Anchors */}
            <rect
              x={midX}
              y={midY}
              width={innerWidth - midX}
              height={innerHeight - midY}
              fill="#0ea5e9"
              fillOpacity="0.03"
            />
            {/* Bottom-Left: Developing */}
            <rect
              x={0}
              y={midY}
              width={midX}
              height={innerHeight - midY}
              fill="#64748b"
              fillOpacity="0.02"
            />

            {/* Quadrant Divider Guidelines */}
            <line
              x1={midX}
              y1={0}
              x2={midX}
              y2={innerHeight}
              stroke="#334155"
              strokeDasharray="4,4"
              strokeWidth="1.2"
            />
            <line
              x1={0}
              y1={midY}
              x2={innerWidth}
              y2={midY}
              stroke="#334155"
              strokeDasharray="4,4"
              strokeWidth="1.2"
            />

            {/* Quadrant Annotations */}
            <text
              x={innerWidth - 12}
              y={18}
              textAnchor="end"
              className="fill-emerald-400 text-[11px] font-bold tracking-wider uppercase opacity-90"
            >
              ★ Elite Dual-Threat Tacticians
            </text>
            <text
              x={12}
              y={18}
              textAnchor="start"
              className="fill-indigo-400 text-[11px] font-bold tracking-wider uppercase opacity-75"
            >
              Offensive Architects
            </text>
            <text
              x={innerWidth - 12}
              y={innerHeight - 12}
              textAnchor="end"
              className="fill-sky-400 text-[11px] font-bold tracking-wider uppercase opacity-75"
            >
              Defensive Anchors
            </text>
            <text
              x={12}
              y={innerHeight - 12}
              textAnchor="start"
              className="fill-slate-500 text-[11px] font-bold tracking-wider uppercase opacity-60"
            >
              Developing Schemes
            </text>

            {/* Grid & Axis Ticks */}
            {[0.95, 1.00, 1.05, 1.10, 1.15].map((tick) => {
              const y = scaleY(tick);
              return (
                <g key={`y-${tick}`}>
                  <line x1={0} y1={y} x2={innerWidth} y2={y} stroke="#1e293b" strokeWidth="1" />
                  <text
                    x={-10}
                    y={y + 4}
                    textAnchor="end"
                    className="fill-slate-500 font-mono text-[10px]"
                  >
                    {tick.toFixed(2)}
                  </text>
                </g>
              );
            })}

            {[1.08, 1.04, 1.00, 0.96, 0.92, 0.88].map((tick) => {
              const x = scaleX(tick);
              return (
                <g key={`x-${tick}`}>
                  <line x1={x} y1={0} x2={x} y2={innerHeight} stroke="#1e293b" strokeWidth="1" />
                  <text
                    x={x}
                    y={innerHeight + 18}
                    textAnchor="middle"
                    className="fill-slate-500 font-mono text-[10px]"
                  >
                    {tick.toFixed(2)}
                  </text>
                </g>
              );
            })}

            {/* Axis Titles */}
            <text
              x={innerWidth / 2}
              y={innerHeight + 42}
              textAnchor="middle"
              className="fill-slate-400 text-xs font-semibold"
            >
              Defensive ATO Suppression → (Lower PPP Allowed = Stifling Defense)
            </text>

            <text
              transform="rotate(-90)"
              x={-innerHeight / 2}
              y={-40}
              textAnchor="middle"
              className="fill-slate-400 text-xs font-semibold"
            >
              Offensive ATO Execution (Points Per Possession) →
            </text>

            {/* Scatter Plot Points */}
            {coaches.map((c) => {
              const cx = scaleX(c.metrics.atoDefensivePppAllowed);
              const cy = scaleY(c.metrics.atoOffensivePpp);
              const isSelected = selectedCoach?.teamAbbr === c.teamAbbr;
              const isHovered = hoveredCoach?.teamAbbr === c.teamAbbr;

              const cir = c.metrics.coachImpactRating;
              const dotColor = cir >= 80 ? '#10b981' : cir >= 65 ? '#f59e0b' : '#64748b';

              return (
                <g
                  key={c.teamAbbr}
                  transform={`translate(${cx}, ${cy})`}
                  className="cursor-pointer transition-transform duration-200"
                  onClick={() => onSelectCoach(c)}
                  onMouseEnter={() => setHoveredCoach(c)}
                  onMouseLeave={() => setHoveredCoach(null)}
                >
                  {/* Selection pulse ring */}
                  {(isSelected || isHovered) && (
                    <circle
                      r="18"
                      fill={dotColor}
                      fillOpacity="0.25"
                      stroke={dotColor}
                      strokeWidth="1.5"
                      className="animate-pulse"
                    />
                  )}

                  {/* Core marker circle */}
                  <circle
                    r={isSelected ? '9' : isHovered ? '8' : '6.5'}
                    fill={dotColor}
                    stroke="#0f172a"
                    strokeWidth="1.5"
                    className="transition-all"
                  />

                  {/* Team Label on point */}
                  <text
                    x="9"
                    y="3"
                    className={`font-mono text-[9px] font-bold select-none transition-all ${
                      isSelected
                        ? 'fill-amber-400 font-extrabold text-[11px]'
                        : isHovered
                        ? 'fill-white font-bold'
                        : 'fill-slate-400'
                    }`}
                  >
                    {c.teamAbbr}
                  </text>
                </g>
              );
            })}
          </g>
        </svg>

        {/* Hover / Active Floating Tooltip */}
        {hoveredCoach && (
          <div className="absolute top-4 right-6 pointer-events-none bg-surface/95 border border-slate-700/80 rounded-xl p-3 shadow-2xl backdrop-blur-md w-64 z-20">
            <div className="flex items-center gap-2.5 pb-2 mb-2 border-b border-slate-800">
              <TeamLogo team={hoveredCoach.teamAbbr} size="sm" />
              <div className="min-w-0">
                <div className="text-xs font-bold text-white truncate">
                  {hoveredCoach.headCoach.name}
                </div>
                <div className="text-[10px] text-slate-400">
                  {hoveredCoach.teamAbbr} • {hoveredCoach.headCoach.coachingTree} Tree
                </div>
              </div>
              <div className="ml-auto text-right">
                <span className="text-[10px] text-slate-400 block">CIR</span>
                <span className="text-xs font-mono font-bold text-amber-400">
                  {hoveredCoach.metrics.coachImpactRating}
                </span>
              </div>
            </div>

            <div className="grid grid-cols-2 gap-2 text-[11px]">
              <div className="p-1.5 bg-surface-raised/80 rounded border border-slate-800/80">
                <span className="text-[9px] text-slate-400 block">Off ATO PPP</span>
                <span className="font-mono font-bold text-emerald-400">
                  {hoveredCoach.metrics.atoOffensivePpp.toFixed(3)}
                </span>
              </div>
              <div className="p-1.5 bg-surface-raised/80 rounded border border-slate-800/80">
                <span className="text-[9px] text-slate-400 block">Def ATO PPP</span>
                <span className="font-mono font-bold text-sky-400">
                  {hoveredCoach.metrics.atoDefensivePppAllowed.toFixed(3)}
                </span>
              </div>
              <div className="p-1.5 bg-surface-raised/80 rounded border border-slate-800/80">
                <span className="text-[9px] text-slate-400 block">Challenge Win %</span>
                <span className="font-mono font-bold text-amber-400">
                  {(hoveredCoach.metrics.challengeSuccessRate * 100).toFixed(1)}%
                </span>
              </div>
              <div className="p-1.5 bg-surface-raised/80 rounded border border-slate-800/80">
                <span className="text-[9px] text-slate-400 block">Scheme Lift (xSQ)</span>
                <span className="font-mono font-bold text-indigo-400">
                  +{hoveredCoach.metrics.shotQualityLiftEfg}% eFG
                </span>
              </div>
            </div>
            <div className="mt-2 text-[9px] text-slate-500 italic text-center">
              Click marker to inspect full profile
            </div>
          </div>
        )}
      </div>
    </div>
  );
};
