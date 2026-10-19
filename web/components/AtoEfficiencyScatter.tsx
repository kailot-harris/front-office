'use client';

import React, { useState } from 'react';
import { CoachingStaffMetric } from '@/lib/coachingTypes';
import { TeamLogo } from '@/components/TeamLogo';
import { Crosshair } from 'lucide-react';

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

  // Bounds for axes in WNBA
  // Offense PPP: 0.82 to 1.15
  // Defense PPP Allowed: 0.76 to 0.98 (Invert X so Right = Lower Allowed / Better Defense)
  const xMin = 0.98; // Left (weaker defense allowed)
  const xMax = 0.76; // Right (elite defense allowed)
  const yMin = 0.82; // Bottom (lower offensive PPP)
  const yMax = 1.15; // Top (elite offensive PPP)

  const width = 760;
  const height = 480;
  const padding = { top: 40, right: 40, bottom: 60, left: 60 };

  const innerWidth = width - padding.left - padding.right;
  const innerHeight = height - padding.top - padding.bottom;

  // Coordinate mappers
  const scaleX = (val: number) => {
    return ((val - xMin) / (xMax - xMin)) * innerWidth;
  };

  const scaleY = (val: number) => {
    return innerHeight - ((val - yMin) / (yMax - yMin)) * innerHeight;
  };

  const midX = scaleX(0.88); // WNBA median defensive PPP allowed
  const midY = scaleY(0.95); // WNBA median offensive PPP

  return (
    <div className="bg-slate-900/80 border border-slate-800 rounded-xl overflow-hidden shadow-lg p-5">
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
          </div>
          <p className="text-xs text-slate-400 mt-1">
            Points Per Possession (PPP) generated vs allowed on half-court set executions out of timeouts.
          </p>
        </div>

        <div className="flex items-center gap-4 text-xs font-medium">
          <div className="flex items-center gap-1.5 text-slate-400">
            <div className="w-3 h-3 rounded-full bg-emerald-500/30 border border-emerald-400" />
            <span>Top-Right = Dual-Dominant</span>
          </div>
          <div className="flex items-center gap-1.5 text-slate-400">
            <div className="w-3 h-3 rounded-full bg-indigo-500/30 border border-indigo-400" />
            <span>Selected</span>
          </div>
        </div>
      </div>

      {/* SVG Canvas */}
      <div className="relative overflow-x-auto">
        <svg
          viewBox={`0 0 ${width} ${height}`}
          className="w-full h-auto min-w-[640px] select-none"
        >
          {/* Quadrant Tint Overlays */}
          {/* Top-Right: Dual Dominant (Green) */}
          <rect
            x={padding.left + midX}
            y={padding.top}
            width={innerWidth - midX}
            height={midY}
            fill="#10b981"
            fillOpacity="0.04"
          />
          {/* Top-Left: Offensive Specialists (Blue) */}
          <rect
            x={padding.left}
            y={padding.top}
            width={midX}
            height={midY}
            fill="#6366f1"
            fillOpacity="0.03"
          />
          {/* Bottom-Right: Defensive Anchors (Amber) */}
          <rect
            x={padding.left + midX}
            y={padding.top + midY}
            width={innerWidth - midX}
            height={innerHeight - midY}
            fill="#f59e0b"
            fillOpacity="0.03"
          />
          {/* Bottom-Left: Sub-Median Execution (Red) */}
          <rect
            x={padding.left}
            y={padding.top + midY}
            width={midX}
            height={innerHeight - midY}
            fill="#ef4444"
            fillOpacity="0.03"
          />

          {/* Quadrant Labels */}
          <text
            x={padding.left + innerWidth - 10}
            y={padding.top + 20}
            textAnchor="end"
            className="fill-emerald-400/60 text-[10px] font-bold uppercase tracking-wider"
          >
            Dual Master (Top Offense & Lockdown Defense)
          </text>
          <text
            x={padding.left + 10}
            y={padding.top + 20}
            textAnchor="start"
            className="fill-indigo-400/60 text-[10px] font-bold uppercase tracking-wider"
          >
            Offensive Wizardry (High Shootout Risk)
          </text>
          <text
            x={padding.left + innerWidth - 10}
            y={padding.top + innerHeight - 12}
            textAnchor="end"
            className="fill-amber-400/60 text-[10px] font-bold uppercase tracking-wider"
          >
            Grind-It-Out Lockdown (Stagnant Sets)
          </text>

          {/* Median Grid Lines */}
          <line
            x1={padding.left + midX}
            y1={padding.top}
            x2={padding.left + midX}
            y2={padding.top + innerHeight}
            stroke="#475569"
            strokeDasharray="4 4"
            strokeWidth="1.5"
          />
          <line
            x1={padding.left}
            y1={padding.top + midY}
            x2={padding.left + innerWidth}
            y2={padding.top + midY}
            stroke="#475569"
            strokeDasharray="4 4"
            strokeWidth="1.5"
          />

          {/* Outer Border */}
          <rect
            x={padding.left}
            y={padding.top}
            width={innerWidth}
            height={innerHeight}
            fill="none"
            stroke="#334155"
            strokeWidth="1"
          />

          {/* Axes Ticks and Labels */}
          {/* X Axis */}
          <text
            x={padding.left + innerWidth / 2}
            y={height - 15}
            textAnchor="middle"
            className="fill-slate-400 text-xs font-semibold"
          >
            Opponent ATO Points Per Possession (Lower = Stifling Defense) →
          </text>

          {/* Y Axis */}
          <text
            x={-(padding.top + innerHeight / 2)}
            y={18}
            transform="rotate(-90)"
            textAnchor="middle"
            className="fill-slate-400 text-xs font-semibold"
          >
            Team ATO Points Per Possession (Higher = Elite Execution) →
          </text>

          {/* Data Points */}
          {coaches.map((c) => {
            const cx = padding.left + scaleX(c.metrics.atoDefensivePppAllowed);
            const cy = padding.top + scaleY(c.metrics.atoOffensivePpp);
            const isSelected = selectedCoach?.teamAbbr === c.teamAbbr;
            const isHovered = hoveredCoach?.teamAbbr === c.teamAbbr;

            return (
              <g
                key={c.teamAbbr}
                className="cursor-pointer transition-transform duration-200"
                onClick={() => onSelectCoach(c)}
                onMouseEnter={() => setHoveredCoach(c)}
                onMouseLeave={() => setHoveredCoach(null)}
              >
                {/* Glow ring if selected */}
                {isSelected && (
                  <circle
                    cx={cx}
                    cy={cy}
                    r={22}
                    fill="none"
                    stroke="#818cf8"
                    strokeWidth="2.5"
                    className="animate-pulse"
                  />
                )}

                {/* Outer halo */}
                <circle
                  cx={cx}
                  cy={cy}
                  r={isHovered ? 16 : 14}
                  fill={isSelected ? '#6366f1' : '#1e293b'}
                  stroke={isSelected ? '#ffffff' : '#475569'}
                  strokeWidth={isHovered ? 2.5 : 1.5}
                />

                {/* Team label inside dot */}
                <text
                  x={cx}
                  y={cy + 3.5}
                  textAnchor="middle"
                  className={`text-[9px] font-mono font-bold select-none pointer-events-none ${
                    isSelected ? 'fill-white' : 'fill-slate-200'
                  }`}
                >
                  {c.teamAbbr}
                </text>

                {/* Coach Name Flag */}
                {(isSelected || isHovered) && (
                  <g className="pointer-events-none">
                    <rect
                      x={cx - 65}
                      y={cy - 34}
                      width={130}
                      height={20}
                      rx={5}
                      fill="#0f172a"
                      stroke="#6366f1"
                      strokeWidth={1}
                    />
                    <text
                      x={cx}
                      y={cy - 20}
                      textAnchor="middle"
                      className="fill-white text-[10px] font-bold select-none"
                    >
                      {c.headCoach.name} ({c.metrics.atoOffensivePpp} / {c.metrics.atoDefensivePppAllowed})
                    </text>
                  </g>
                )}
              </g>
            );
          })}
        </svg>
      </div>

      {/* Selected Coach Quick Card */}
      {selectedCoach && (
        <div className="mt-4 p-3 bg-slate-950/80 rounded-lg border border-slate-800 flex items-center justify-between text-xs">
          <div className="flex items-center gap-2">
            <TeamLogo team={selectedCoach.teamAbbr} size="sm" />
            <div>
              <span className="font-bold text-white">{selectedCoach.headCoach.name}</span>
              <span className="text-slate-400 ml-1">({selectedCoach.teamName})</span>
            </div>
          </div>
          <div className="flex items-center gap-4">
            <div>
              <span className="text-slate-400">Offensive ATO: </span>
              <span className="font-bold text-indigo-400">{selectedCoach.metrics.atoOffensivePpp} PPP</span>
            </div>
            <div>
              <span className="text-slate-400">Defensive Allowed: </span>
              <span className="font-bold text-emerald-400">{selectedCoach.metrics.atoDefensivePppAllowed} PPP</span>
            </div>
          </div>
        </div>
      )}
    </div>
  );
};
