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
    <div ref={containerRef} className="flex flex-col items-center justify-center p-3 bg-surface/60 rounded-xl border border-slate-800/80">
      <div className="w-full flex items-center justify-between mb-1">
        <div className="text-xs font-semibold text-slate-400 uppercase tracking-wider">
          Skill Fingerprint (16-D Aggregate)
        </div>
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
      <svg width={size} height={size} className="overflow-visible select-none">
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
              stroke="#334155"
              strokeWidth={level === 1.0 ? '1.5' : '1'}
              strokeDasharray={level < 1.0 ? '2 2' : 'none'}
              opacity={level === 1.0 ? 0.8 : 0.4}
            />
          );
        })}

        {/* Radial Spokes from Center */}
        {axes.map((axis, i) => {
          const angleRad = (axis.angle * Math.PI) / 180;
          const endX = center + radius * Math.cos(angleRad);
          const endY = center + radius * Math.sin(angleRad);

          return (
            <line
              key={i}
              x1={center}
              y1={center}
              x2={endX}
              y2={endY}
              stroke="#334155"
              strokeWidth="1"
              opacity={0.5}
            />
          );
        })}

        {/* Data Polygon Fill */}
        <polygon
          points={polygonPoints}
          fill="#6366f1"
          fillOpacity="0.35"
          stroke="#818cf8"
          strokeWidth="2.5"
          className="transition-all duration-300"
        />

        {/* Data Vertices */}
        {axes.map((axis, i) => {
          const coords = getCoordinates(axis.value, axis.angle);
          return (
            <circle
              key={i}
              cx={coords.x}
              cy={coords.y}
              r={4}
              fill="#c084fc"
              stroke="#ffffff"
              strokeWidth="1.5"
            />
          );
        })}

        {/* Labels */}
        {axes.map((axis, i) => {
          const angleRad = (axis.angle * Math.PI) / 180;
          const labelDist = radius + 20;
          const lx = center + labelDist * Math.cos(angleRad);
          const ly = center + labelDist * Math.sin(angleRad);

          let anchor: 'middle' | 'start' | 'end' = 'middle';
          if (Math.cos(angleRad) > 0.3) anchor = 'start';
          else if (Math.cos(angleRad) < -0.3) anchor = 'end';

          return (
            <text
              key={i}
              x={lx}
              y={ly + 4}
              textAnchor={anchor}
              className="fill-slate-300 text-[10px] font-semibold select-none"
            >
              {axis.label} ({axis.value})
            </text>
          );
        })}
      </svg>
    </div>
  );
};
