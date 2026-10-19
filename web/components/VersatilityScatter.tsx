'use client';

import React from 'react';
import { DefensiveProfile } from '@/lib/defenseTypes';

interface VersatilityScatterProps {
  profiles: DefensiveProfile[];
  selectedProfile: DefensiveProfile;
  onSelectProfile: (profile: DefensiveProfile) => void;
}

export const VersatilityScatter: React.FC<VersatilityScatterProps> = ({
  profiles,
  selectedProfile,
  onSelectProfile,
}) => {
  const width = 500;
  const height = 300;
  const padding = 40;

  // X-axis: Positional Versatility H_vers (40 to 100)
  // Y-axis: Rim DFG Delta (-16 to +4) -> Lower is better / more elite rim protection
  const xMin = 45;
  const xMax = 100;
  const yMin = 3;   // worst
  const yMax = -16; // best

  // Inverted Y so elite rim protection is at the top:
  const scaleX = (val: number) => padding + ((val - xMin) / (xMax - xMin)) * (width - 2 * padding);
  const scaleY = (val: number) => padding + ((val - yMax) / (yMin - yMax)) * (height - 2 * padding);

  return (
    <div className="flex flex-col p-4 bg-slate-950/60 rounded-xl border border-slate-800/80">
      <div className="flex items-center justify-between mb-2">
        <div>
          <h4 className="text-xs font-semibold text-slate-300 uppercase tracking-wider">
            Versatility vs. Rim Deterrence Residual
          </h4>
          <p className="text-[11px] text-slate-500">
            X: Shannon Entropy $H_{'{'}vers{'}'}$ (Switch Range) ⟵ Single Positional Anchor
            <br />
            Y: Rim DFG% Delta (Top = Elite Rim Fortress & Suppression)
          </p>
        </div>
        <div className="text-right">
          <span className="text-[10px] font-mono bg-slate-900 border border-slate-800 text-indigo-400 px-2 py-0.5 rounded">
            N = {profiles.length} Defenders
          </span>
        </div>
      </div>

      <div className="relative w-full overflow-hidden flex justify-center">
        <svg viewBox={`0 0 ${width} ${height}`} className="w-full max-w-[500px] h-auto overflow-visible select-none">
          {/* Quadrant Guidelines */}
          <line
            x1={padding}
            y1={scaleY(-5.0)}
            x2={width - padding}
            y2={scaleY(-5.0)}
            stroke="#334155"
            strokeDasharray="3 3"
          />
          <line
            x1={scaleX(75)}
            y1={padding}
            x2={scaleX(75)}
            y2={height - padding}
            stroke="#334155"
            strokeDasharray="3 3"
          />

          {/* Quadrant Labels */}
          <text
            x={width - padding - 8}
            y={padding + 16}
            textAnchor="end"
            className="fill-indigo-400 text-[10px] font-bold tracking-tight opacity-70"
          >
            Universal Disruptors (High Switch + Rim)
          </text>
          <text
            x={padding + 8}
            y={padding + 16}
            textAnchor="start"
            className="fill-emerald-400 text-[10px] font-bold tracking-tight opacity-70"
          >
            Traditional Anchors (Elite Paint Wall)
          </text>
          <text
            x={width - padding - 8}
            y={height - padding - 8}
            textAnchor="end"
            className="fill-amber-400 text-[10px] font-bold tracking-tight opacity-70"
          >
            Switchable Perimeter Guards
          </text>

          {/* Axis Lines */}
          <line x1={padding} y1={height - padding} x2={width - padding} y2={height - padding} stroke="#475569" />
          <line x1={padding} y1={padding} x2={padding} y2={height - padding} stroke="#475569" />

          {/* Dots */}
          {profiles.map((p) => {
            const cx = scaleX(p.versatilityScore);
            const cy = scaleY(p.rimDfgDelta);
            const isSelected = p.playerId === selectedProfile.playerId;

            let dotColor = '#64748b';
            if (p.defensiveRole.includes('Anchor') || p.defensiveRole.includes('Fortress')) dotColor = '#10b981';
            else if (p.defensiveRole.includes('Eraser') || p.defensiveRole.includes('Switch')) dotColor = '#6366f1';
            else if (p.defensiveRole.includes('Stopper')) dotColor = '#f59e0b';

            return (
              <g
                key={p.playerId}
                className="cursor-pointer transition-all duration-150"
                onClick={() => onSelectProfile(p)}
              >
                {isSelected && (
                  <circle
                    cx={cx}
                    cy={cy}
                    r={12}
                    fill="none"
                    stroke="#818cf8"
                    strokeWidth={2}
                    className="animate-pulse"
                  />
                )}
                <circle
                  cx={cx}
                  cy={cy}
                  r={isSelected ? 6 : 4}
                  fill={isSelected ? '#ffffff' : dotColor}
                  stroke={isSelected ? '#4f46e5' : '#0f172a'}
                  strokeWidth={1.5}
                  opacity={isSelected ? 1 : 0.85}
                />
              </g>
            );
          })}
        </svg>
      </div>

      <div className="flex items-center justify-between mt-2 pt-2 border-t border-slate-800/80 text-[11px] text-slate-400">
        <span>Selected: <strong className="text-white">{selectedProfile.playerName}</strong> ({selectedProfile.team})</span>
        <span className="font-mono text-indigo-400">H_vers: {selectedProfile.versatilityScore} | Rim Δ: {selectedProfile.rimDfgDelta}%</span>
      </div>
    </div>
  );
};
