'use client';

import React from 'react';
import { PlayerDnaProfile } from '@/lib/playerDnaTypes';

interface DnaManifoldScatterProps {
  players: PlayerDnaProfile[];
  selectedPlayer: PlayerDnaProfile;
  onSelectPlayer: (player: PlayerDnaProfile) => void;
}

export const DnaManifoldScatter: React.FC<DnaManifoldScatterProps> = ({
  players,
  selectedPlayer,
  onSelectPlayer,
}) => {
  // SVG Dimensions
  const width = 500;
  const height = 300;
  const padding = 35;

  // Domain: X: -35 to +55, Y: -35 to +55
  const xMin = -30;
  const xMax = 55;
  const yMin = -30;
  const yMax = 55;

  const scaleX = (val: number) => padding + ((val - xMin) / (xMax - xMin)) * (width - 2 * padding);
  const scaleY = (val: number) => height - padding - ((val - yMin) / (yMax - yMin)) * (height - 2 * padding);

  return (
    <div className="flex flex-col p-4 bg-slate-950/60 rounded-xl border border-slate-800/80">
      <div className="flex items-center justify-between mb-2">
        <div>
          <h4 className="text-xs font-semibold text-slate-300 uppercase tracking-wider">
            2D Stylistic Manifold Projection (t-SNE / PCA)
          </h4>
          <p className="text-[11px] text-slate-500">
            Horizontal: Shot Creation & Playmaking Hub ⟵ Spot-Up / Finisher
            <br />
            Vertical: Paint Anchor & Rebound Engine ⟵ Perimeter Guard
          </p>
        </div>
        <div className="text-right">
          <span className="text-[10px] font-mono bg-slate-900 border border-slate-800 text-indigo-400 px-2 py-0.5 rounded">
            N = {players.length} Players
          </span>
        </div>
      </div>

      <div className="relative w-full overflow-hidden flex justify-center">
        <svg viewBox={`0 0 ${width} ${height}`} className="w-full max-w-[500px] h-auto overflow-visible select-none">
          {/* Grid lines */}
          <line x1={padding} y1={scaleY(0)} x2={width - padding} y2={scaleY(0)} stroke="#334155" strokeWidth="1" strokeDasharray="3 3" />
          <line x1={scaleX(0)} y1={padding} x2={scaleX(0)} y2={height - padding} stroke="#334155" strokeWidth="1" strokeDasharray="3 3" />

          {/* Background points */}
          {players.map((p) => {
            const isSelected = p.playerId === selectedPlayer.playerId;
            const cx = scaleX(p.manifoldX);
            const cy = scaleY(p.manifoldY);

            let dotColor = '#64748b';
            if (p.position === 'G') dotColor = '#818cf8';
            else if (p.position === 'F') dotColor = '#34d399';
            else if (p.position === 'C') dotColor = '#fbbf24';

            return (
              <g
                key={p.playerId}
                className="cursor-pointer transition-all duration-150"
                onClick={() => onSelectPlayer(p)}
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
                  opacity={isSelected ? 1 : 0.8}
                />
              </g>
            );
          })}
        </svg>
      </div>

      <div className="flex items-center justify-between mt-2 pt-2 border-t border-slate-800/80 text-[11px] text-slate-400">
        <span>Selected: <strong className="text-white">{selectedPlayer.playerName}</strong> ({selectedPlayer.team})</span>
        <span className="font-mono text-indigo-400">[{selectedPlayer.manifoldX}, {selectedPlayer.manifoldY}]</span>
      </div>
    </div>
  );
};
