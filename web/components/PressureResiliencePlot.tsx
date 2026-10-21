'use client';

import React, { useRef } from 'react';
import { Download } from 'lucide-react';
import { ClutchProfile } from '@/lib/clutchTypes';
import { exportSvgAsPng } from '@/lib/exportSvgAsPng';

interface PressureResiliencePlotProps {
  profiles: ClutchProfile[];
  selectedProfile: ClutchProfile;
  onSelectProfile: (profile: ClutchProfile) => void;
  playerType: 'Batter' | 'Pitcher';
}

export const PressureResiliencePlot: React.FC<PressureResiliencePlotProps> = ({
  profiles,
  selectedProfile,
  onSelectProfile,
  playerType,
}) => {
  const width = 500;
  const height = 280;
  const padding = 42;

  // Domain scaling based on player type
  const isBatter = playerType === 'Batter';

  const xMin = isBatter ? 0.280 : 0.230;
  const xMax = isBatter ? 0.430 : 0.370;
  const yMin = isBatter ? -0.045 : -0.060;
  const yMax = isBatter ? 0.065 : 0.045;

  const scaleX = (val: number) => padding + ((val - xMin) / (xMax - xMin)) * (width - 2 * padding);
  const scaleY = (val: number) => height - padding - ((val - yMin) / (yMax - yMin)) * (height - 2 * padding);

  const containerRef = useRef<HTMLDivElement | null>(null);

  const handleExportPng = () => {
    if (containerRef.current) {
      exportSvgAsPng(containerRef.current, `pressure-resilience-plot-${playerType.toLowerCase()}`);
    }
  };

  return (
    <div ref={containerRef} className="flex flex-col p-4 bg-surface/70 rounded-2xl border border-slate-800 shadow-xl space-y-2">
      <div className="flex items-center justify-between">
        <div>
          <h4 className="text-xs font-bold text-white uppercase tracking-wider font-mono">
            Pressure Resilience Plot ({playerType}s)
          </h4>
          <p className="text-[11px] text-slate-400">
            {isBatter
              ? 'X: Base wOBA (Talent) | Y: ΔwOBA Clutch (Top = Ice in Veins)'
              : 'X: Base wOBA Against (Talent) | Y: ΔwOBA Against (Bottom = Lockdown Eraser)'}
          </p>
        </div>
        <div className="text-right flex items-center gap-2">
          <span className="text-[10px] font-mono bg-surface-raised border border-slate-800 text-rose-400 px-2 py-0.5 rounded font-bold">
            N = {profiles.length} {playerType}s
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
          {/* Zero Delta Horizontal Line */}
          <line
            x1={padding}
            y1={scaleY(0)}
            x2={width - padding}
            y2={scaleY(0)}
            stroke="#334155"
            strokeWidth="1.5"
            strokeDasharray="4,4"
          />

          {/* Median Vertical Line */}
          <line
            x1={scaleX(isBatter ? 0.335 : 0.300)}
            y1={padding}
            x2={scaleX(isBatter ? 0.335 : 0.300)}
            y2={height - padding}
            stroke="#1e293b"
            strokeWidth="1"
            strokeDasharray="2,2"
          />

          {/* Scatter Points */}
          {profiles.map((p) => {
            const isSelected = p.playerId === selectedProfile.playerId;
            const cx = scaleX(p.baseMetricVal);
            const cy = scaleY(p.deltaClutch);

            const isClutchElite = isBatter ? p.deltaClutch >= 0.025 : p.deltaClutch <= -0.025;

            return (
              <g
                key={p.playerId}
                className="cursor-pointer group"
                onClick={() => onSelectProfile(p)}
              >
                <circle
                  cx={cx}
                  cy={cy}
                  r={isSelected ? 7 : isClutchElite ? 4.5 : 3.5}
                  fill={
                    isSelected
                      ? '#f43f5e'
                      : isClutchElite
                      ? '#38bdf8'
                      : 'rgba(148, 163, 184, 0.45)'
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
                    className="text-[10.5px] font-mono font-bold fill-white pointer-events-none"
                  >
                    {p.playerName} ({p.deltaClutch > 0 ? `+${p.deltaClutch}` : p.deltaClutch})
                  </text>
                )}
              </g>
            );
          })}
        </svg>
      </div>

      <div className="flex items-center justify-between text-[10px] font-mono text-slate-500 pt-2 border-t border-slate-800/80">
        <span>Click any dot to load player clutch profile</span>
        <span className="text-rose-400 font-bold">Selected: {selectedProfile.playerName}</span>
      </div>
    </div>
  );
};
