'use client';

import React, { useRef } from 'react';
import { Download } from 'lucide-react';
import { RadarPercentiles } from '@/lib/coachingTypes';
import { exportSvgAsPng } from '@/lib/exportSvgAsPng';

interface CoachRadarProfileProps {
  percentiles: RadarPercentiles;
  coachName: string;
  size?: number;
}

export const CoachRadarProfile: React.FC<CoachRadarProfileProps> = ({
  percentiles,
  coachName,
  size = 280,
}) => {
  const axes = [
    { key: 'atoMastery', label: 'ATO Mastery', value: percentiles.atoMastery, desc: 'Set-piece execution & defensive ATO stops' },
    { key: 'tacticalInnovation', label: 'Tactical xSQ', value: percentiles.tacticalInnovation, desc: 'Scheme shot quality lift over baseline' },
    { key: 'rotationEfficiency', label: 'Rotation Stagger', value: percentiles.rotationEfficiency, desc: 'Star staggering & bench bleed minimization' },
    { key: 'inGameWpa', label: 'In-Game WPA', value: percentiles.inGameWpa, desc: 'Challenge equity & leverage clock tactics' },
    { key: 'playerDevelopment', label: 'Player Dev', value: percentiles.playerDevelopment, desc: 'Young core YoY improvement over age curves' },
  ];

  const center = size / 2;
  const radius = (size / 2) - 45; // Leave padding for labels
  const totalAxes = axes.length;

  // Convert polar coordinates to Cartesian
  const getCoordinates = (index: number, val: number) => {
    const angle = (Math.PI * 2 / totalAxes) * index - Math.PI / 2;
    const r = (val / 100) * radius;
    return {
      x: center + r * Math.cos(angle),
      y: center + r * Math.sin(angle),
    };
  };

  // Polygon points string for the data
  const polygonPoints = axes
    .map((axis, i) => {
      const { x, y } = getCoordinates(i, axis.value);
      return `${x},${y}`;
    })
    .join(' ');

  // Background concentric rings at 20, 40, 60, 80, 100
  const rings = [20, 40, 60, 80, 100];

  const svgRef = useRef<SVGSVGElement | null>(null);

  const handleExportPng = () => {
    if (svgRef.current) {
      exportSvgAsPng(svgRef.current, `${coachName.replace(/\s+/g, '-').toLowerCase()}-radar-profile`);
    }
  };

  return (
    <div className="flex flex-col items-center" title={`5D Tactical Profile: ${coachName}`}>
      <button
        type="button"
        onClick={handleExportPng}
        title="Export PNG"
        aria-label="Export radar chart as PNG"
        className="self-end mb-1 p-1.5 rounded-lg border border-slate-800 text-slate-400 hover:text-white hover:border-slate-600 transition-colors"
      >
        <Download className="w-3.5 h-3.5" />
      </button>
      <div className="relative">
        <svg ref={svgRef} width={size} height={size} className="overflow-visible select-none">
          <defs>
            <radialGradient id="radarFill" cx="50%" cy="50%" r="50%">
              <stop offset="0%" stopColor="#6366f1" stopOpacity="0.45" />
              <stop offset="70%" stopColor="#f59e0b" stopOpacity="0.30" />
              <stop offset="100%" stopColor="#f97316" stopOpacity="0.10" />
            </radialGradient>
            <filter id="glow" x="-20%" y="-20%" width="140%" height="140%">
              <feGaussianBlur stdDeviation="3" result="blur" />
              <feComposite in="SourceGraphic" in2="blur" operator="over" />
            </filter>
          </defs>

          {/* Concentric grid rings */}
          {rings.map((ring) => {
            const ringPoints = axes
              .map((_, i) => {
                const { x, y } = getCoordinates(i, ring);
                return `${x},${y}`;
              })
              .join(' ');
            return (
              <polygon
                key={ring}
                points={ringPoints}
                fill="none"
                stroke="#334155"
                strokeWidth={ring === 100 ? '1.5' : '0.8'}
                strokeDasharray={ring === 100 ? undefined : '3,3'}
                className="transition-all"
              />
            );
          })}

          {/* Radial axis lines */}
          {axes.map((_, i) => {
            const { x, y } = getCoordinates(i, 100);
            return (
              <line
                key={i}
                x1={center}
                y1={center}
                x2={x}
                y2={y}
                stroke="#334155"
                strokeWidth="1"
              />
            );
          })}

          {/* Data Polygon with glowing accent border */}
          <polygon
            points={polygonPoints}
            fill="url(#radarFill)"
            stroke="#f59e0b"
            strokeWidth="2.5"
            strokeLinejoin="round"
            filter="url(#glow)"
            className="transition-all duration-500 ease-out"
          />

          {/* Data Points on vertices */}
          {axes.map((axis, i) => {
            const { x, y } = getCoordinates(i, axis.value);
            return (
              <g key={axis.key}>
                <circle
                  cx={x}
                  cy={y}
                  r="4.5"
                  fill="#fbbf24"
                  stroke="#0f172a"
                  strokeWidth="2"
                  className="transition-all duration-500 hover:scale-125"
                />
              </g>
            );
          })}

          {/* Labels & Percentiles at outer perimeter */}
          {axes.map((axis, i) => {
            const angle = (Math.PI * 2 / totalAxes) * indexToOffset(i) - Math.PI / 2;
            const labelRadius = radius + 24;
            const lx = center + labelRadius * Math.cos(angle);
            const ly = center + labelRadius * Math.sin(angle);

            // Alignment anchor based on x position
            let textAnchor: 'start' | 'middle' | 'end' = 'middle';
            if (lx < center - 15) textAnchor = 'end';
            else if (lx > center + 15) textAnchor = 'start';

            return (
              <g key={`lbl-${axis.key}`} transform={`translate(${lx}, ${ly})`} className="cursor-default">
                <text
                  x="0"
                  y="-4"
                  textAnchor={textAnchor}
                  className="fill-slate-300 text-[10px] font-bold tracking-tight"
                >
                  {axis.label}
                </text>
                <text
                  x="0"
                  y="8"
                  textAnchor={textAnchor}
                  className="fill-amber-400 font-mono text-[10px] font-semibold"
                >
                  {axis.value}th %ile
                </text>
              </g>
            );
          })}
        </svg>
      </div>

      {/* Metric Breakdown Table below radar */}
      <div className="grid grid-cols-2 sm:grid-cols-3 gap-2 mt-4 w-full">
        {axes.map((a) => (
          <div
            key={a.key}
            className="p-2 rounded-lg bg-surface-raised/60 border border-slate-800 flex flex-col justify-between"
            title={a.desc}
          >
            <span className="text-[10px] text-slate-400 font-medium truncate">{a.label}</span>
            <div className="flex items-baseline justify-between mt-1">
              <span className="font-mono text-xs font-bold text-white">{a.value}%</span>
              <span
                className={`text-[9px] font-mono font-semibold px-1 py-0.2 rounded ${
                  a.value >= 80
                    ? 'bg-emerald-500/10 text-emerald-400'
                    : a.value >= 50
                    ? 'bg-amber-500/10 text-amber-400'
                    : 'bg-rose-500/10 text-rose-400'
                }`}
              >
                {a.value >= 80 ? 'Elite' : a.value >= 50 ? 'Above Avg' : 'Developing'}
              </span>
            </div>
          </div>
        ))}
      </div>
    </div>
  );
};

function indexToOffset(i: number): number {
  return i;
}
