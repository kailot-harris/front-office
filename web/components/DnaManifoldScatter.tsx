'use client';

import React, { useRef } from 'react';
import { Download } from 'lucide-react';
import { PlayerDnaProfile, DnaCategory } from '@/lib/playerDnaTypes';
import { exportSvgAsPng } from '@/lib/exportSvgAsPng';

interface DnaManifoldScatterProps {
  players: PlayerDnaProfile[];
  selectedPlayer: PlayerDnaProfile;
  onSelectPlayer: (player: PlayerDnaProfile) => void;
  playerType: 'Batter' | 'Pitcher';
  // Published category labels, used to describe the axes
  categories: DnaCategory[];
  // Players of this type with both coordinates in the full dataset (known before the full fetch)
  totalPlotted: number;
}

// The axes are the fixed blends of category scores written by mlb_player_dna_engine.R
// (manifoldX / manifoldY). Keep in step with the engine.
const AXIS_FORMULAS: Record<'Batter' | 'Pitcher', { x: [string, number][]; y: [string, number][]; xMinus: string }> = {
  Batter: { x: [['power', 0.65], ['athleticism', 0.35]], xMinus: 'contact', y: [['discipline', 0.75], ['batted_ball', 0.25]] },
  Pitcher: { x: [['arsenal_stuff', 0.65], ['velocity_physics', 0.35]], xMinus: 'command_k', y: [['workload_leverage', 0.7], ['batted_ball', 0.3]] },
};

export const DnaManifoldScatter: React.FC<DnaManifoldScatterProps> = ({
  players,
  selectedPlayer,
  onSelectPlayer,
  playerType,
  categories,
  totalPlotted,
}) => {
  const labelOf = (key: string) => categories.find((c) => c.key === key)?.label ?? key;
  const f = AXIS_FORMULAS[playerType];
  const xText = `X = ${f.x[0][1]} × (${labelOf(f.x[0][0])} − ${labelOf(f.xMinus)}) + ${f.x[1][1]} × (${labelOf(f.x[1][0])} − 50)`;
  const yText = `Y = ${f.y.map(([k, w]) => `${w} × (${labelOf(k)} − 50)`).join(' + ')}`;
  const width = 500;
  const height = 280;
  const padding = 35;

  // Players with a null coordinate (too few measured inputs) are not plotted.
  const plotted = players.filter(
    (p): p is PlayerDnaProfile & { manifoldX: number; manifoldY: number } =>
      p.manifoldX !== null && p.manifoldY !== null,
  );
  // Domain follows the data (rounded out to 10s, always including the origin).
  const xs = plotted.map((p) => p.manifoldX);
  const ys = plotted.map((p) => p.manifoldY);
  const xMin = Math.floor(Math.min(0, ...xs) / 10) * 10 - 5;
  const xMax = Math.ceil(Math.max(0, ...xs) / 10) * 10 + 5;
  const yMin = Math.floor(Math.min(0, ...ys) / 10) * 10 - 5;
  const yMax = Math.ceil(Math.max(0, ...ys) / 10) * 10 + 5;

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
            Style Map: Category-Score Blend ({playerType}s)
          </h4>
          <p className="text-[11px] text-slate-400" data-testid="dna-scatter-axes">
            {xText} | {yText}
          </p>
        </div>
        <div className="text-right flex items-center gap-2">
          <span className="text-[11px] sm:text-[10px] font-mono bg-surface-raised border border-slate-800 text-sky-400 px-2 py-0.5 rounded">
            {plotted.length < totalPlotted ? `N = ${plotted.length} of ${totalPlotted}` : `N = ${plotted.length}`} {playerType}s
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
        <svg
          viewBox={`0 0 ${width} ${height}`}
          className="w-full max-w-[500px] h-auto overflow-visible"
          role="img"
          aria-label={`Style map scatter plot for ${plotted.length} MLB ${playerType}s with ${selectedPlayer.playerName} selected`}
        >
          {/* Grid lines */}
          <line
            x1={padding}
            y1={scaleY(0)}
            x2={width - padding}
            y2={scaleY(0)}
            stroke="var(--tw-c-slate-800)"
            strokeWidth="1"
            strokeDasharray="3,3"
          />
          <line
            x1={scaleX(0)}
            y1={padding}
            x2={scaleX(0)}
            y2={height - padding}
            stroke="var(--tw-c-slate-800)"
            strokeWidth="1"
            strokeDasharray="3,3"
          />

          {/* Background Points */}
          {plotted.map((p) => {
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
                    className="text-[11px] sm:text-[10px] font-mono font-bold fill-white pointer-events-none"
                  >
                    {p.playerName}
                  </text>
                )}
              </g>
            );
          })}
        </svg>
      </div>

      <div className="flex items-center justify-between text-[11px] sm:text-[10px] font-mono text-slate-400 pt-2 border-t border-slate-800/80">
        <span>Click any dot to load player DNA & peer comps</span>
        <span className="text-sky-400 font-bold">Selected: {selectedPlayer.playerName}</span>
      </div>
    </div>
  );
};
