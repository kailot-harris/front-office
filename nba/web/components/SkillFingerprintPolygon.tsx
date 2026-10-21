'use client';

import React, { useRef } from 'react';
import { Download } from 'lucide-react';
import { CategoryScores } from '@/lib/playerDnaTypes';
import { exportSvgAsPng } from '@/lib/exportSvgAsPng';

interface SkillFingerprintPolygonProps {
  categoryScores: CategoryScores;
}

export const SkillFingerprintPolygon: React.FC<SkillFingerprintPolygonProps> = ({
  categoryScores,
}) => {
  // 5 axes: Finishing (Top), Shooting (Top-Right), Playmaking (Bottom-Right), Defense (Bottom-Left), Rebounding (Top-Left)
  const axes = [
    { label: 'Finishing', value: categoryScores.finishing, angle: -90 },
    { label: 'Shooting', value: categoryScores.shooting, angle: -18 },
    { label: 'Playmaking', value: categoryScores.playmaking, angle: 54 },
    { label: 'Defense', value: categoryScores.defense, angle: 126 },
    { label: 'Rebounding', value: categoryScores.rebounding, angle: 198 },
  ];

  const size = 260;
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

  const polygonPoints = axes
    .map((axis) => {
      const coords = getCoordinates(axis.value, axis.angle);
      return `${coords.x},${coords.y}`;
    })
    .join(' ');

  const containerRef = useRef<HTMLDivElement | null>(null);

  const handleExportPng = () => {
    if (containerRef.current) {
      exportSvgAsPng(containerRef.current, 'skill-fingerprint-polygon');
    }
  };

  return (
    <div ref={containerRef} className="flex flex-col items-center justify-center p-3 bg-zinc-950/60 rounded-xl border border-zinc-800/80">
      <div className="w-full flex items-center justify-between mb-1">
        <div className="text-xs font-semibold text-zinc-400 uppercase tracking-wider">
          Skill Fingerprint (16-D Aggregate)
        </div>
        <button
          type="button"
          onClick={handleExportPng}
          title="Export PNG"
          aria-label="Export chart as PNG"
          data-export-exclude
          className="p-1.5 rounded-lg border border-zinc-800 text-zinc-400 hover:text-white hover:border-zinc-600 transition-colors"
        >
          <Download className="w-3.5 h-3.5" />
        </button>
      </div>
      <svg width={size} height={size} className="overflow-visible">
        {/* Background Concentric Rings (25%, 50%, 75%, 100%) */}
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
              stroke="#27272a"
              strokeWidth={level === 1.0 ? '1.5' : '1'}
              strokeDasharray={level === 1.0 ? 'none' : '3,3'}
            />
          );
        })}

        {/* Axis Lines */}
        {axes.map((axis, i) => {
          const end = getAxisEnd(axis.angle);
          return (
            <line
              key={i}
              x1={center}
              y1={center}
              x2={end.x}
              y2={end.y}
              stroke="#3f3f46"
              strokeWidth="1"
            />
          );
        })}

        {/* Data Filled Polygon */}
        <polygon
          points={polygonPoints}
          fill="rgba(56, 189, 248, 0.25)"
          stroke="#38bdf8"
          strokeWidth="2.5"
          className="transition-all duration-500"
        />

        {/* Data Point Dots & Labels */}
        {axes.map((axis, i) => {
          const coords = getCoordinates(axis.value, axis.angle);
          const labelCoords = getCoordinates(120, axis.angle);
          return (
            <g key={i}>
              <circle
                cx={coords.x}
                cy={coords.y}
                r="4.5"
                fill="#0284c7"
                stroke="#e0f2fe"
                strokeWidth="1.5"
              />
              <text
                x={labelCoords.x}
                y={labelCoords.y}
                textAnchor="middle"
                dominantBaseline="central"
                className="text-[11px] font-medium fill-zinc-300"
              >
                {axis.label}
              </text>
              <text
                x={labelCoords.x}
                y={labelCoords.y + 12}
                textAnchor="middle"
                dominantBaseline="central"
                className="text-[10px] font-bold fill-sky-400"
              >
                {Math.round(axis.value)}
              </text>
            </g>
          );
        })}
      </svg>
      <div className="text-[11px] text-zinc-500 mt-2 text-center">
        Normalized percentile tier across active NBA benchmarks
      </div>
    </div>
  );
};
