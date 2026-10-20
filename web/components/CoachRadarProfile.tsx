'use client';

import React from 'react';
import { RadarPercentiles } from '@/lib/coachingTypes';

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

  return (
    <div className="flex flex-col items-center" title={`5D Tactical Profile: ${coachName}`}>
      <div className="relative">
        <svg width={size} height={size} className="overflow-visible select-none">
          <defs>
            <radialGradient id="radarFillWnba" cx="50%" cy="50%" r="50%">
              <stop offset="0%" stopColor="#6366f1" stopOpacity="0.45" />
              <stop offset="70%" stopColor="#8b5cf6" stopOpacity="0.30" />
              <stop offset="100%" stopColor="#ec4899" stopOpacity="0.10" />
            </radialGradient>
            <filter id="glowWnba" x="-20%" y="-20%" width="140%" height="140%">
              <feGaussianBlur stdDeviation="3" result="blur" />
              <feComposite in="SourceGraphic" in2="blur" operator="over" />
            </filter>
          </defs>

          {/* Concentric Polygonal Background Rings */}
          {rings.map((ring) => {
            const points = axes
              .map((_, i) => {
                const { x, y } = getCoordinates(i, ring);
                return `${x},${y}`;
              })
              .join(' ');

            return (
              <polygon
                key={ring}
                points={points}
                fill="none"
                stroke="#334155"
                strokeWidth={ring === 100 ? '1.5' : '1'}
                strokeDasharray={ring < 100 ? '3 3' : 'none'}
                opacity={ring === 100 ? 0.8 : 0.4}
              />
            );
          })}

          {/* Radial Spokes from Center */}
          {axes.map((_, i) => {
            const edge = getCoordinates(i, 100);
            return (
              <line
                key={i}
                x1={center}
                y1={center}
                x2={edge.x}
                y2={edge.y}
                stroke="#334155"
                strokeWidth="1"
                opacity={0.5}
              />
            );
          })}

          {/* Filled Tactical Area */}
          <polygon
            points={polygonPoints}
            fill="url(#radarFillWnba)"
            stroke="#818cf8"
            strokeWidth="2.5"
            filter="url(#glowWnba)"
            className="transition-all duration-300 ease-out"
          />

          {/* Data Vertex Dots */}
          {axes.map((axis, i) => {
            const point = getCoordinates(i, axis.value);
            return (
              <g key={i}>
                <circle
                  cx={point.x}
                  cy={point.y}
                  r={4.5}
                  fill="#c084fc"
                  stroke="#ffffff"
                  strokeWidth="1.5"
                  className="transition-all duration-300"
                />
              </g>
            );
          })}

          {/* Axis Labels */}
          {axes.map((axis, i) => {
            const labelPos = getCoordinates(i, 118);
            // Alignment tweaks based on angle position
            let textAnchor: 'middle' | 'end' | 'start' = 'middle';
            if (labelPos.x < center - 10) textAnchor = 'end';
            else if (labelPos.x > center + 10) textAnchor = 'start';

            return (
              <text
                key={i}
                x={labelPos.x}
                y={labelPos.y + 4}
                textAnchor={textAnchor}
                className="fill-slate-300 text-[11px] font-semibold tracking-tight pointer-events-none select-none"
              >
                {axis.label}
              </text>
            );
          })}
        </svg>
      </div>

      {/* Axis Breakdown Badges */}
      <div className="grid grid-cols-2 gap-x-4 gap-y-1.5 mt-4 text-[11px] w-full max-w-[280px]">
        {axes.map((axis) => (
          <div key={axis.key} className="flex justify-between items-center text-slate-400 bg-surface-raised/50 px-2 py-0.5 rounded border border-slate-800/80">
            <span className="truncate pr-1">{axis.label}</span>
            <span className="font-mono font-bold text-indigo-400">{axis.value}th</span>
          </div>
        ))}
      </div>
    </div>
  );
};
