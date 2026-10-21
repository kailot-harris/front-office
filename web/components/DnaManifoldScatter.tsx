'use client';

import React, { useRef } from 'react';
import { Download } from 'lucide-react';
import { PlayerDnaProfile } from '@/lib/playerDnaTypes';
import { exportSvgAsPng } from '@/lib/exportSvgAsPng';

interface DnaManifoldScatterProps {
  players: PlayerDnaProfile[];
  selectedPlayer: PlayerDnaProfile;
  onSelectPlayer: (player: PlayerDnaProfile) => void;
  playerType: 'Batter' | 'Pitcher';
}

export const DnaManifoldScatter: React.FC<DnaManifoldScatterProps> = ({
  players,
  selectedPlayer,
  onSelectPlayer,
  playerType,
}) => {
  const width = 500;
  const height = 280;
  const padding = 35;

  const xMin = -30;
  const xMax = 50;
  const yMin = -30;
  const yMax = 50;

  const scaleX = (val: number) => padding + ((val - xMin) / (xMax - xMin)) * (width - 2 * padding);
  const scaleY = (val: number) => height - padding - ((val - yMin) / (yMax - yMin)) * (height - 2 * padding);

  const containerRef = useRef<HTMLDivElement | null>(null);

  const handleExportPng = () => {
    if (containerRef.current) {
      exportSvgAsPng(containerRef.current, `dna-manifold-scatter-${playerType.toLowerCase()}`);
    }
  };

  return (
    <div ref={containerRef} className="flex flex-col p-4 bg-surface/70 rounded-2xl border border-slate-800 shadow-xl">
      <div className="flex items-center justify-between mb-2">
        <div>
          <h4 className="text-xs font-bold text-white uppercase tracking-wider font-mono">
            2D Stylistic Manifold Projection ({playerType}s)
          </h4>
          <p className="text-[11px] text-slate-400">
            {playerType === 'Batter'
              ? 'X: Raw Power & Pull ⟵ Contact & Speed | Y: Discipline & OBP ⟵ Free Swinger'
              : 'X: Pure Stuff+ & Velocity ⟵ Command & Finesse | Y: Workload & Leverage ⟵ Pitch Mix'}
          </p>
        </div>
        <div className="text-right flex items-center gap-2">
          <span className="text-[10px] font-mono bg-surface-raised border border-slate-800 text-sky-400 px-2 py-0.5 rounded">
            N = {players.length} {playerType}s
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

      <div className="relative w-full overflow-hidden flex justify-center my-1">
        <svg viewBox={`0 0 ${width} ${height}`} className="w-full max-w-[500px] h-auto overflow-visible">
          {/* Grid lines */}
          <line
            x1={padding}
            y1={scaleY(0)}
            x2={width - padding}
            y2={scaleY(0)}
            stroke="#1e293b"
            strokeWidth="1"
            strokeDasharray="3,3"
          />
          <line
            x1={scaleX(0)}
            y1={padding}
            x2={scaleX(0)}
            y2={height - padding}
            stroke="#1e293b"
            strokeWidth="1"
            strokeDasharray="3,3"
          />

          {/* Background Points */}
          {players.map((p) => {
            const isSelected = p.playerId === selectedPlayer.playerId;
            const cx = scaleX(p.manifoldX);
            const cy = scaleY(p.manifoldY);

            return (
              <g
                key={p.playerId}
                className="cursor-pointer group"
                onClick={() => onSelectPlayer(p)}
              >
                <circle
                  cx={cx}
                  cy={cy}
                  r={isSelected ? 6.5 : 3.5}
                  fill={
                    isSelected
                      ? '#38bdf8'
                      : playerType === 'Batter'
                      ? 'rgba(14, 165, 233, 0.45)'
                      : 'rgba(245, 158, 11, 0.45)'
                  }
                  stroke={isSelected ? '#ffffff' : 'transparent'}
                  strokeWidth={isSelected ? 2 : 0}
                  className="transition-all duration-200 group-hover:scale-150"
                />
                {isSelected && (
                  <text
                    x={cx}
                    y={cy - 10}
                    textAnchor="middle"
                    className="text-[10px] font-mono font-bold fill-white pointer-events-none"
                  >
                    {p.playerName}
                  </text>
                )}
              </g>
            );
          })}
        </svg>
      </div>

      <div className="flex items-center justify-between text-[10px] font-mono text-slate-500 pt-2 border-t border-slate-800/80">
        <span>Click any dot to load player DNA & historical twins</span>
        <span className="text-sky-400 font-bold">Selected: {selectedPlayer.playerName}</span>
      </div>
    </div>
  );
};
