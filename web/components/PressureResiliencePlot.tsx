'use client';

import React, { useRef } from 'react';
import { Download } from 'lucide-react';
import { ClutchProfile } from '@/lib/clutchTypes';
import { exportSvgAsPng } from '@/lib/exportSvgAsPng';

interface PressureResiliencePlotProps {
  profiles: ClutchProfile[];
  selectedProfile: ClutchProfile;
  onSelectProfile: (profile: ClutchProfile) => void;
}

export const PressureResiliencePlot: React.FC<PressureResiliencePlotProps> = ({
  profiles,
  selectedProfile,
  onSelectProfile,
}) => {
  const width = 500;
  const height = 300;
  const padding = 40;

  // X-axis: Turnover Fragility Delta TOV% (-5.0% to +5.0%) -> Lower/Negative is better ball security
  // Y-axis: Clutch True Shooting % (42% to 68%) -> Higher is better
  //
  // The domain is taken from the data. It used to be fixed at +/-4.5 and 44-68,
  // which fitted the old placeholder values; the play-by-play-derived metrics
  // range far wider, so a third of the points were drawn outside the chart and
  // past the edge of the page. The old bounds are kept as a minimum so a narrow
  // dataset does not zoom in misleadingly, and x stays symmetric about zero so
  // the "no change" line sits in the middle.
  const finite = (v: number | null | undefined): v is number =>
    typeof v === 'number' && Number.isFinite(v);
  const xValues = profiles.map((p) => p.tovFragility).filter(finite);
  const yValues = profiles.map((p) => p.clutchTsPct).filter(finite);
  const xExtent = Math.max(4.5, Math.ceil(Math.max(0, ...xValues.map(Math.abs))));
  const xMin = -xExtent;
  const xMax = xExtent;
  const yMin = Math.min(44, Math.floor(Math.min(44, ...yValues)));
  const yMax = Math.max(68, Math.ceil(Math.max(68, ...yValues)));

  const scaleX = (val: number) => padding + ((val - xMin) / (xMax - xMin)) * (width - 2 * padding);
  const scaleY = (val: number) => height - padding - ((val - yMin) / (yMax - yMin)) * (height - 2 * padding);

  const containerRef = useRef<HTMLDivElement | null>(null);

  const handleExportPng = () => {
    if (containerRef.current) {
      exportSvgAsPng(containerRef.current, 'pressure-resilience-plot');
    }
  };

  const validProfiles = profiles.filter(
    (p): p is ClutchProfile & { clutchTsPct: number; tovFragility: number } =>
      p.clutchTsPct != null && p.tovFragility != null
  );

  return (
    <div ref={containerRef} className="flex flex-col p-4 bg-zinc-950/60 rounded-xl border border-zinc-800/80">
      <div className="flex items-center justify-between mb-2">
        <div>
          <h4 className="text-xs font-semibold text-zinc-300 uppercase tracking-wider">
            Pressure Resilience: Clutch TS% vs. Turnover Fragility
          </h4>
          <p className="text-[11px] text-zinc-500">
            X: ΔTOV% (Left = Ice-Cold Ball Security ⟵ Right = Turnover Fragile)
            <br />
            Y: Clutch True Shooting % (Top = Lethal Scoring Efficiency)
          </p>
        </div>
        <div className="text-right flex items-center gap-2">
          <span className="text-[11px] sm:text-[10px] font-mono bg-zinc-900 border border-zinc-800 text-rose-400 px-2 py-0.5 rounded">
            N = {validProfiles.length} Closers
          </span>
          <button
            type="button"
            onClick={handleExportPng}
            title="Export PNG"
            aria-label="Export chart as PNG"
            data-export-exclude
            className="p-1.5 rounded-lg border border-zinc-800 text-zinc-400 hover:text-white hover:border-zinc-600 transition-colors"
          >
            <Download className="w-3.5 h-3.5" />
          </button>
        </div>
      </div>

      <div className="relative w-full overflow-hidden flex justify-center">
        <svg viewBox={`0 0 ${width} ${height}`} className="w-full max-w-[500px] h-auto overflow-visible">
          {/* Quadrant Axis Lines */}
          <line
            x1={padding}
            y1={scaleY(55.0)}
            x2={width - padding}
            y2={scaleY(55.0)}
            stroke="#27272a"
            strokeWidth="1"
            strokeDasharray="3,3"
          />
          <line
            x1={scaleX(0.0)}
            y1={padding}
            x2={scaleX(0.0)}
            y2={height - padding}
            stroke="#27272a"
            strokeWidth="1"
            strokeDasharray="3,3"
          />

          {/* Quadrant Labels */}
          <text x={padding + 8} y={padding + 14} textAnchor="start" className="text-[11px] sm:text-[9px] fill-emerald-500/60 font-semibold uppercase">
            Ice-Cold Closers (High TS%, Low TOV)
          </text>
          <text x={width - padding - 8} y={padding + 14} textAnchor="end" className="text-[11px] sm:text-[9px] fill-amber-500/60 font-semibold uppercase">
            High-Risk Shotmakers
          </text>
          <text x={padding + 8} y={height - padding - 8} textAnchor="start" className="text-[11px] sm:text-[9px] fill-sky-500/60 font-semibold uppercase">
            Safe Connectors
          </text>

          {/* Scatter Points */}
          {validProfiles.map((p) => {
            const isSelected = p.playerId === selectedProfile.playerId;
            const cx = scaleX(p.tovFragility);
            const cy = scaleY(p.clutchTsPct);
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
                <title>{`${p.playerName} (${p.team}) - Clutch TS: ${p.clutchTsPct}%, ΔTOV: ${p.tovFragility > 0 ? '+' : ''}${p.tovFragility}%`}</title>
              </circle>
            );
          })}

          {/* Selected Player Pin */}
          {selectedProfile.tovFragility != null && selectedProfile.clutchTsPct != null && (
            <g transform={`translate(${scaleX(selectedProfile.tovFragility)}, ${scaleY(selectedProfile.clutchTsPct)})`}>
              <circle r="8" fill="none" stroke="#f43f5e" strokeWidth="1.5" className="animate-ping" opacity="0.6" />
              <text
                y="-12"
                textAnchor="middle"
                className="text-[11px] sm:text-[10px] font-bold fill-rose-400 select-none pointer-events-none drop-shadow-md"
              >
                {selectedProfile.playerName} ({selectedProfile.clutchTsPct}%)
              </text>
            </g>
          )}
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
