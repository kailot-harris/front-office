'use client';

import React, { useRef } from 'react';
import { Download } from 'lucide-react';
import { BatterCategoryScores, PitcherCategoryScores, DnaCategory, DnaDimension } from '@/lib/playerDnaTypes';
import { exportSvgAsPng } from '@/lib/exportSvgAsPng';

interface SkillFingerprintPolygonProps {
  playerType: 'Batter' | 'Pitcher';
  categoryScores: BatterCategoryScores | PitcherCategoryScores;
  // Published by the engine: one axis per category, labelled with its published label.
  categories: DnaCategory[];
  dimensions: DnaDimension[];
}

export const SkillFingerprintPolygon: React.FC<SkillFingerprintPolygonProps> = ({
  playerType,
  categoryScores,
  categories,
  dimensions,
}) => {
  // One axis per published category, evenly spaced from the top. A null category (too
  // few measured inputs) is left out of the polygon and labelled "—", never drawn as a
  // filler value. Each axis tooltip lists the dimensions averaged into it.
  const scores = categoryScores as unknown as Record<string, number | null>;
  const axes: { key: string; label: string; members: string[]; value: number | null; angle: number }[] = categories.map(
    (c, i) => ({
      key: c.key,
      label: c.label,
      members: dimensions.filter((d) => d.category === c.key).map((d) => d.label),
      value: scores[c.key] ?? null,
      angle: -90 + (360 / Math.max(categories.length, 1)) * i,
    }),
  );

  const size = 280;
  const center = size / 2;
  const radius = 95;

  const getCoordinates = (value: number, angleDeg: number) => {
    const angleRad = (angleDeg * Math.PI) / 180;
    const r = (Math.max(0, Math.min(100, value)) / 100) * radius;
    return {
      x: center + r * Math.cos(angleRad),
      y: center + r * Math.sin(angleRad),
    };
  };

  const getAxisEnd = (angleDeg: number) => {
    const angleRad = (angleDeg * Math.PI) / 180;
    return {
      x: center + radius * Math.cos(angleRad),
      y: center + radius * Math.sin(angleRad),
    };
  };

  const plotted = axes.filter((axis): axis is (typeof axes)[number] & { value: number } => axis.value !== null);
  const polygonPoints = plotted
    .map((axis) => {
      const coords = getCoordinates(axis.value, axis.angle);
      return `${coords.x},${coords.y}`;
    })
    .join(' ');

  const containerRef = useRef<HTMLDivElement | null>(null);

  const handleExportPng = () => {
    if (containerRef.current) {
      exportSvgAsPng(containerRef.current, `skill-fingerprint-${playerType.toLowerCase()}`);
    }
  };

  return (
    <div ref={containerRef} className="flex flex-col items-center justify-center p-4 bg-surface/70 rounded-2xl border border-slate-800 shadow-xl relative">
      <button
        type="button"
        onClick={handleExportPng}
        title="Export PNG"
        aria-label="Export chart as PNG"
        data-export-exclude
        className="absolute top-3 right-3 p-1.5 rounded-lg border border-slate-800 text-slate-400 hover:text-white hover:border-slate-600 transition-colors"
      >
        <Download className="w-3.5 h-3.5" />
      </button>
      <div className="text-xs font-bold text-slate-300 uppercase tracking-wider font-mono">
        Skill Fingerprint ({playerType})
      </div>
      <div className="text-[11px] text-slate-400 mb-2" data-testid="dna-radar-caption">
        {categories.length} category averages of the {dimensions.length} {playerType.toLowerCase()} skill percentiles
      </div>

      <svg
        width={size}
        height={size}
        className="overflow-visible my-1"
        role="img"
        aria-label={`Player skill fingerprint radar chart for ${playerType}`}
      >
        {/* Concentric Grid Rings */}
        {[0.25, 0.5, 0.75, 1.0].map((level) => {
          const points = axes
            .map((axis) => {
              const coords = getCoordinates(level * 100, axis.angle);
              return `${coords.x},${coords.y}`;
            })
            .join(' ');

          return (
            <polygon
              key={level}
              points={points}
              fill="none"
              stroke="var(--tw-c-slate-800)"
              strokeWidth="1"
              strokeDasharray={level < 1.0 ? '2,2' : undefined}
            />
          );
        })}

        {/* Axis Spokes */}
        {axes.map((axis, i) => {
          const end = getAxisEnd(axis.angle);
          return (
            <line
              key={i}
              x1={center}
              y1={center}
              x2={end.x}
              y2={end.y}
              stroke="var(--tw-c-slate-700)"
              strokeWidth="1"
            />
          );
        })}

        {/* Skill Polygon */}
        <polygon
          points={polygonPoints}
          fill={playerType === 'Batter' ? 'rgba(14, 165, 233, 0.25)' : 'rgba(245, 158, 11, 0.22)'}
          stroke={playerType === 'Batter' ? '#0ea5e9' : '#f59e0b'}
          strokeWidth="2.5"
          className="transition-all duration-700 ease-out"
        />

        {/* Skill Vertices */}
        {plotted.map((axis, i) => {
          const coords = getCoordinates(axis.value, axis.angle);
          return (
            <circle
              key={i}
              cx={coords.x}
              cy={coords.y}
              r="4.5"
              fill={playerType === 'Batter' ? '#38bdf8' : '#fbbf24'}
              stroke="var(--tw-c-slate-900)"
              strokeWidth="2"
            />
          );
        })}

        {/* Axis Labels */}
        {axes.map((axis, i) => {
          const angleRad = (axis.angle * Math.PI) / 180;
          const labelDist = radius + 24;
          const lx = center + labelDist * Math.cos(angleRad);
          const ly = center + labelDist * Math.sin(angleRad);

          return (
            <g key={i} data-testid="dna-radar-axis">
              <title>{`${axis.label}: average of ${axis.members.join(', ')}`}</title>
              <text
                x={lx}
                y={ly - 4}
                textAnchor="middle"
                dominantBaseline="central"
                className="text-[11px] sm:text-[10px] font-mono fill-slate-300 font-bold"
              >
                {axis.label}
              </text>
              <text
                x={lx}
                y={ly + 8}
                textAnchor="middle"
                dominantBaseline="central"
                className={`text-[10.5px] font-mono font-black ${
                  playerType === 'Batter' ? 'fill-sky-400' : 'fill-amber-400'
                }`}
              >
                {axis.value ?? '—'}
              </text>
            </g>
          );
        })}
      </svg>
    </div>
  );
};
