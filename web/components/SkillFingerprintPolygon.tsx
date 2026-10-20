'use client';

import React from 'react';
import { BatterCategoryScores, PitcherCategoryScores } from '@/lib/playerDnaTypes';

interface SkillFingerprintPolygonProps {
  playerType: 'Batter' | 'Pitcher';
  categoryScores: BatterCategoryScores | PitcherCategoryScores;
}

export const SkillFingerprintPolygon: React.FC<SkillFingerprintPolygonProps> = ({
  playerType,
  categoryScores,
}) => {
  // 5 axes tailored per player type
  const axes = playerType === 'Batter'
    ? [
        { label: 'Power & Exit Velo', value: (categoryScores as BatterCategoryScores).power || 50, angle: -90 },
        { label: 'In-Zone Contact', value: (categoryScores as BatterCategoryScores).contact || 50, angle: -18 },
        { label: 'Plate Discipline', value: (categoryScores as BatterCategoryScores).discipline || 50, angle: 54 },
        { label: 'Batted Ball Loft', value: (categoryScores as BatterCategoryScores).batted_ball || 50, angle: 126 },
        { label: 'Speed & Defense', value: (categoryScores as BatterCategoryScores).athleticism || 50, angle: 198 },
      ]
    : [
        { label: 'Velo & Physics', value: (categoryScores as PitcherCategoryScores).velocity_physics || 50, angle: -90 },
        { label: 'Stuff+ & Arsenal', value: (categoryScores as PitcherCategoryScores).arsenal_stuff || 50, angle: -18 },
        { label: 'Command & K%', value: (categoryScores as PitcherCategoryScores).command_k || 50, angle: 54 },
        { label: 'Contact Suppress', value: (categoryScores as PitcherCategoryScores).batted_ball || 50, angle: 126 },
        { label: 'Leverage & Workload', value: (categoryScores as PitcherCategoryScores).workload_leverage || 50, angle: 198 },
      ];

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

  const polygonPoints = axes
    .map((axis) => {
      const coords = getCoordinates(axis.value, axis.angle);
      return `${coords.x},${coords.y}`;
    })
    .join(' ');

  return (
    <div className="flex flex-col items-center justify-center p-4 bg-surface/70 rounded-2xl border border-slate-800 shadow-xl">
      <div className="text-xs font-bold text-slate-300 uppercase tracking-wider font-mono mb-2">
        16-D Skill Fingerprint ({playerType})
      </div>

      <svg width={size} height={size} className="overflow-visible my-1">
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
              stroke="#1e293b"
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
              stroke="#334155"
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
        {axes.map((axis, i) => {
          const coords = getCoordinates(axis.value, axis.angle);
          return (
            <circle
              key={i}
              cx={coords.x}
              cy={coords.y}
              r="4.5"
              fill={playerType === 'Batter' ? '#38bdf8' : '#fbbf24'}
              stroke="#0f172a"
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
            <g key={i}>
              <text
                x={lx}
                y={ly - 4}
                textAnchor="middle"
                dominantBaseline="central"
                className="text-[10px] font-mono fill-slate-300 font-bold"
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
                {axis.value}
              </text>
            </g>
          );
        })}
      </svg>
    </div>
  );
};
