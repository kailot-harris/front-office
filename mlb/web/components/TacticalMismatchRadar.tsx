'use client';

import React, { useRef } from 'react';
import { Download } from 'lucide-react';
import { MlbTacticalRatings } from '@/lib/playoffTypes';
import { exportSvgAsPng } from '@/lib/exportSvgAsPng';

interface TacticalMismatchRadarProps {
  teamA: string;
  teamB: string;
  ratingsA: MlbTacticalRatings;
  ratingsB: MlbTacticalRatings;
}

export const TacticalMismatchRadar: React.FC<TacticalMismatchRadarProps> = ({
  teamA,
  teamB,
  ratingsA,
  ratingsB,
}) => {
  const axes = [
    { key: 'rotationDepth', label: 'Rotation Depth', desc: 'Top-4 Starter rGS & Quality' },
    { key: 'bullpenLeverage', label: 'Bullpen Leverage', desc: 'Late-Inning Shutdown & Fatigue' },
    { key: 'powerIso', label: 'Power & ISO', desc: 'Lineup Isolated Power & HRs' },
    { key: 'contactDiscipline', label: 'Contact & Disc.', desc: 'In-Zone Contact & K-Avoidance' },
    { key: 'defenseFielding', label: 'Defensive Run Prev.', desc: 'OAA & Catcher Framing' },
  ] as const;

  const size = 260;
  const center = size / 2;
  const radius = center - 35;
  const numAxes = axes.length;

  const getCoordinates = (value: number, index: number) => {
    const angle = (Math.PI * 2 / numAxes) * index - Math.PI / 2;
    const r = (value / 100) * radius;
    const x = center + r * Math.cos(angle);
    const y = center + r * Math.sin(angle);
    return { x, y };
  };

  // Generate polygon points for Team A and Team B
  const pointsA = axes.map((axis, i) => {
    const val = ratingsA[axis.key] || 50;
    const { x, y } = getCoordinates(val, i);
    return `${x},${y}`;
  }).join(' ');

  const pointsB = axes.map((axis, i) => {
    const val = ratingsB[axis.key] || 50;
    const { x, y } = getCoordinates(val, i);
    return `${x},${y}`;
  }).join(' ');

  // Grid circles
  const gridLevels = [0.25, 0.5, 0.75, 1.0];

  const containerRef = useRef<HTMLDivElement | null>(null);

  const handleExportPng = () => {
    if (containerRef.current) {
      exportSvgAsPng(containerRef.current, `tactical-mismatch-radar-${teamA}-vs-${teamB}`);
    }
  };

  return (
    <div ref={containerRef} className="bg-surface-raised/90 border border-slate-800 rounded-2xl p-5 shadow-xl flex flex-col justify-between">
      <div className="flex items-center justify-between border-b border-slate-800/80 pb-3 mb-2">
        <div>
          <h3 className="text-sm font-bold text-white uppercase tracking-wider font-mono">
            5-Axis Tactical Radar
          </h3>
          <p className="text-xs text-slate-400">Sabermetric Strengths & Mismatches</p>
        </div>
        <div className="flex items-center gap-3 text-xs font-mono">
          <span className="flex items-center gap-1.5 text-sky-400 font-bold">
            <span className="w-2.5 h-2.5 rounded-full bg-sky-500" />
            {teamA}
          </span>
          <span className="flex items-center gap-1.5 text-amber-400 font-bold">
            <span className="w-2.5 h-2.5 rounded-full bg-amber-500" />
            {teamB}
          </span>
          <button
            type="button"
            onClick={handleExportPng}
            title="Export PNG"
            aria-label="Export chart as PNG"
            data-export-exclude
            className="p-1.5 rounded-lg border border-slate-800 text-slate-400 hover:text-white hover:border-slate-600 transition-colors"
          >
            <Download className="w-3.5 h-3.5" />
          </button>
        </div>
      </div>

      <div className="flex items-center justify-center my-1 relative">
        <svg width={size} height={size} className="overflow-visible">
          {/* Concentric grid circles */}
          {gridLevels.map((level, idx) => (
            <circle
              key={idx}
              cx={center}
              cy={center}
              r={radius * level}
              fill="none"
              stroke="currentColor"
              className="text-slate-800"
              strokeDasharray={idx < 3 ? '2,2' : undefined}
            />
          ))}

          {/* Radial axis lines */}
          {axes.map((_, i) => {
            const { x, y } = getCoordinates(100, i);
            return (
              <line
                key={i}
                x1={center}
                y1={center}
                x2={x}
                y2={y}
                stroke="currentColor"
                className="text-slate-800/80"
              />
            );
          })}

          {/* Team B Polygon (amber) */}
          <polygon
            points={pointsB}
            fill="rgba(245, 158, 11, 0.18)"
            stroke="#f59e0b"
            strokeWidth="2"
            className="transition-all duration-700 ease-out"
          />

          {/* Team A Polygon (sky) */}
          <polygon
            points={pointsA}
            fill="rgba(14, 165, 233, 0.22)"
            stroke="#0ea5e9"
            strokeWidth="2.5"
            className="transition-all duration-700 ease-out"
          />

          {/* Axis Labels */}
          {axes.map((axis, i) => {
            const { x, y } = getCoordinates(115, i);
            return (
              <text
                key={i}
                x={x}
                y={y}
                textAnchor="middle"
                dominantBaseline="central"
                className="text-[10px] font-mono fill-slate-300 font-semibold"
              >
                {axis.label}
              </text>
            );
          })}
        </svg>
      </div>

      {/* Axis Rating Breakdown Cards */}
      <div className="mt-3 pt-3 border-t border-slate-800/80 grid grid-cols-5 gap-1.5 text-center">
        {axes.map((axis, i) => {
          const valA = ratingsA[axis.key];
          const valB = ratingsB[axis.key];
          const advA = valA >= valB;
          return (
            <div key={i} className="bg-surface/60 p-1.5 rounded-lg border border-slate-800/60">
              <span className="text-[9.5px] font-mono text-slate-400 block truncate" title={axis.desc}>
                {axis.label}
              </span>
              <div className="flex items-center justify-center gap-1 font-mono text-[11px] font-bold mt-0.5">
                <span className={advA ? 'text-sky-400 font-black' : 'text-slate-400'}>{valA}</span>
                <span className="text-slate-600">:</span>
                <span className={!advA ? 'text-amber-400 font-black' : 'text-slate-400'}>{valB}</span>
              </div>
            </div>
          );
        })}
      </div>
    </div>
  );
};
