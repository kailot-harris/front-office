'use client';

import React, { useRef } from 'react';
import { Download } from 'lucide-react';
import { PlayerDnaProfile } from '@/lib/playerDnaTypes';
import { exportSvgAsPng } from '@/lib/exportSvgAsPng';

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

  // Domain: X: -30 to +60, Y: -30 to +60
  const xMin = -25;
  const xMax = 55;
  const yMin = -25;
  const yMax = 55;

  const scaleX = (val: number) => padding + ((val - xMin) / (xMax - xMin)) * (width - 2 * padding);
  const scaleY = (val: number) => height - padding - ((val - yMin) / (yMax - yMin)) * (height - 2 * padding);

  const svgRef = useRef<SVGSVGElement | null>(null);

  const handleExportPng = () => {
    if (svgRef.current) {
      exportSvgAsPng(svgRef.current, 'dna-manifold-scatter');
    }
  };

  return (
    <div className="flex flex-col p-4 bg-zinc-950/60 rounded-xl border border-zinc-800/80">
      <div className="flex items-center justify-between mb-2">
        <div>
          <h4 className="text-xs font-semibold text-zinc-300 uppercase tracking-wider">
            2D Stylistic Manifold Projection (t-SNE / PCA)
          </h4>
          <p className="text-[11px] text-zinc-500">
            Horizontal: Shot Creation & Playmaking Hub ⟵ Spot-Up / Finisher
            <br />
            Vertical: Paint Anchor & Rebound Engine ⟵ Perimeter Guard
          </p>
        </div>
        <div className="text-right flex items-center gap-2">
          <span className="text-[10px] font-mono bg-zinc-900 border border-zinc-800 text-sky-400 px-2 py-0.5 rounded">
            N = {players.length} Players
          </span>
          <button
            type="button"
            onClick={handleExportPng}
            title="Export PNG"
            aria-label="Export chart as PNG"
            className="p-1.5 rounded-lg border border-zinc-800 text-zinc-400 hover:text-white hover:border-zinc-600 transition-colors"
          >
            <Download className="w-3.5 h-3.5" />
          </button>
        </div>
      </div>

      <div className="relative w-full overflow-hidden flex justify-center">
        <svg ref={svgRef} viewBox={`0 0 ${width} ${height}`} className="w-full max-w-[500px] h-auto overflow-visible">
          {/* Grid lines */}
          <line x1={padding} y1={scaleY(0)} x2={width - padding} y2={scaleY(0)} stroke="#27272a" strokeWidth="1" strokeDasharray="3,3" />
          <line x1={scaleX(0)} y1={padding} x2={scaleX(0)} y2={height - padding} stroke="#27272a" strokeWidth="1" strokeDasharray="3,3" />

          {/* Background points */}
          {players.map((p) => {
            const isSelected = p.playerId === selectedPlayer.playerId;
            const cx = scaleX(p.manifoldX);
            const cy = scaleY(p.manifoldY);

            const fillColor = p.position === 'G' ? '#38bdf8' : p.position === 'F' ? '#34d399' : '#fbbf24';

            return (
              <circle
                key={p.playerId}
                cx={cx}
                cy={cy}
                r={isSelected ? 6 : 3}
                fill={isSelected ? '#f43f5e' : fillColor}
                stroke={isSelected ? '#fff' : 'none'}
                strokeWidth={isSelected ? 2 : 0}
                opacity={isSelected ? 1.0 : 0.45}
                className="cursor-pointer transition-all hover:opacity-100 hover:r-4"
                onClick={() => onSelectPlayer(p)}
              >
                <title>{`${p.playerName} (${p.team}) - ${p.archetype}`}</title>
              </circle>
            );
          })}

          {/* Active Highlight Pin */}
          <g transform={`translate(${scaleX(selectedPlayer.manifoldX)}, ${scaleY(selectedPlayer.manifoldY)})`}>
            <circle r="8" fill="none" stroke="#f43f5e" strokeWidth="1.5" className="animate-ping" opacity="0.6" />
            <text
              y="-12"
              textAnchor="middle"
              className="text-[10px] font-bold fill-rose-400 select-none pointer-events-none drop-shadow-md"
            >
              {selectedPlayer.playerName}
            </text>
          </g>
        </svg>
      </div>

      <div className="flex items-center justify-center gap-6 mt-2 pt-2 border-t border-zinc-900 text-[11px] text-zinc-400">
        <div className="flex items-center gap-1.5">
          <span className="w-2.5 h-2.5 rounded-full bg-sky-400 inline-block" /> Guards (G)
        </div>
        <div className="flex items-center gap-1.5">
          <span className="w-2.5 h-2.5 rounded-full bg-emerald-400 inline-block" /> Forwards (F)
        </div>
        <div className="flex items-center gap-1.5">
          <span className="w-2.5 h-2.5 rounded-full bg-amber-400 inline-block" /> Centers (C)
        </div>
        <div className="flex items-center gap-1.5">
          <span className="w-2.5 h-2.5 rounded-full bg-rose-500 inline-block" /> Selected
        </div>
      </div>
    </div>
  );
};
