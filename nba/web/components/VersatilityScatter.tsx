'use client';

import React, { useRef } from 'react';
import { Download } from 'lucide-react';
import { DefensiveProfile } from '@/lib/defenseTypes';
import { exportSvgAsPng } from '@/lib/exportSvgAsPng';

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
  const yMin = 3;   // worst (top on typical inverted plot)
  const yMax = -16; // best (bottom or inverted top)

  // We want more negative (elite rim protection) towards top, so inverted Y:
  const scaleX = (val: number) => padding + ((val - xMin) / (xMax - xMin)) * (width - 2 * padding);
  const scaleY = (val: number) => padding + ((val - yMax) / (yMin - yMax)) * (height - 2 * padding);

  const svgRef = useRef<SVGSVGElement | null>(null);

  const handleExportPng = () => {
    if (svgRef.current) {
      exportSvgAsPng(svgRef.current, 'versatility-scatter');
    }
  };

  return (
    <div className="flex flex-col p-4 bg-zinc-950/60 rounded-xl border border-zinc-800/80">
      <div className="flex items-center justify-between mb-2">
        <div>
          <h4 className="text-xs font-semibold text-zinc-300 uppercase tracking-wider">
            Versatility vs. Rim Deterrence Residual
          </h4>
          <p className="text-[11px] text-zinc-500">
            X: Shannon Entropy H<sub>vers</sub> (Switch Range) ⟵ Single Positional Anchor
            <br />
            Y: Rim DFG% Delta (Top = Elite Rim Fortress & Suppression)
          </p>
        </div>
        <div className="text-right flex items-center gap-2">
          <span className="text-[10px] font-mono bg-zinc-900 border border-zinc-800 text-sky-400 px-2 py-0.5 rounded">
            N = {profiles.length} Defenders
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
          {/* Quadrant Guidelines */}
          <line
            x1={padding}
            y1={scaleY(-5.0)}
            x2={width - padding}
            y2={scaleY(-5.0)}
            stroke="#27272a"
            strokeWidth="1"
            strokeDasharray="3,3"
          />
          <line
            x1={scaleX(75)}
            y1={padding}
            x2={scaleX(75)}
            y2={height - padding}
            stroke="#27272a"
            strokeWidth="1"
            strokeDasharray="3,3"
          />

          {/* Quadrant Labels */}
          <text x={width - padding - 8} y={padding + 14} textAnchor="end" className="text-[9px] fill-emerald-500/60 font-semibold uppercase">
            Switch & Rim Unicorns
          </text>
          <text x={padding + 8} y={padding + 14} textAnchor="start" className="text-[9px] fill-sky-500/60 font-semibold uppercase">
            Paint Fortresses
          </text>
          <text x={width - padding - 8} y={height - padding - 8} textAnchor="end" className="text-[9px] fill-amber-500/60 font-semibold uppercase">
            Perimeter Chameleons
          </text>

          {/* Points */}
          {profiles.map((p) => {
            const isSelected = p.playerId === selectedProfile.playerId;
            const cx = scaleX(p.versatilityScore);
            const cy = scaleY(p.rimDfgDelta);
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
                className="cursor-pointer transition-all hover:opacity-100"
                onClick={() => onSelectProfile(p)}
              >
                <title>{`${p.playerName} (${p.team}) - ${p.defensiveRole} (H_vers: ${p.versatilityScore}, Rim DFG: ${p.rimDfgDelta}%)`}</title>
              </circle>
            );
          })}

          {/* Selected Pin */}
          <g transform={`translate(${scaleX(selectedProfile.versatilityScore)}, ${scaleY(selectedProfile.rimDfgDelta)})`}>
            <circle r="8" fill="none" stroke="#f43f5e" strokeWidth="1.5" className="animate-ping" opacity="0.6" />
            <text
              y="-12"
              textAnchor="middle"
              className="text-[10px] font-bold fill-rose-400 select-none pointer-events-none drop-shadow-md"
            >
              {selectedProfile.playerName} ({selectedProfile.rimDfgDelta > 0 ? `+${selectedProfile.rimDfgDelta}` : selectedProfile.rimDfgDelta}%)
            </text>
          </g>
        </svg>
      </div>

      <div className="flex items-center justify-center gap-6 mt-2 pt-2 border-t border-zinc-900 text-[11px] text-zinc-400">
        <div className="flex items-center gap-1.5">
          <span className="w-2.5 h-2.5 rounded-full bg-sky-400 inline-block" /> Guard (G)
        </div>
        <div className="flex items-center gap-1.5">
          <span className="w-2.5 h-2.5 rounded-full bg-emerald-400 inline-block" /> Forward (F)
        </div>
        <div className="flex items-center gap-1.5">
          <span className="w-2.5 h-2.5 rounded-full bg-amber-400 inline-block" /> Center (C)
        </div>
        <div className="flex items-center gap-1.5">
          <span className="w-2.5 h-2.5 rounded-full bg-rose-500 inline-block" /> Selected
        </div>
      </div>
    </div>
  );
};
