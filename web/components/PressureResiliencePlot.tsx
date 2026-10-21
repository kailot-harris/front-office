'use client';

import React, { useState, useRef } from 'react';
import { ClutchProfile } from '@/lib/clutchTypes';
import { AlertCircle, Download } from 'lucide-react';
import { exportSvgAsPng } from '@/lib/exportSvgAsPng';

interface PressureResiliencePlotProps {
  profiles: ClutchProfile[];
  selectedPlayerId: string;
  onSelectPlayer: (id: string) => void;
}

export const PressureResiliencePlot: React.FC<PressureResiliencePlotProps> = ({
  profiles,
  selectedPlayerId,
  onSelectPlayer,
}) => {
  const [hoveredProfile, setHoveredProfile] = useState<ClutchProfile | null>(null);

  // Filter to players with meaningful clutch volume (e.g. >= 8 clutch FGA)
  const qualified = profiles.filter((p) => p.shotBreakdown.totalClutchFga >= 8);

  const width = 600;
  const height = 400;
  const padding = { top: 30, right: 30, bottom: 50, left: 60 };

  // X-axis: tovFragility (-4.0% to +8.0%)
  const minX = -4;
  const maxX = 8;

  // Y-axis: clutchTsPct (30% to 75%)
  const minY = 30;
  const maxY = 75;

  const scaleX = (val: number) => {
    const clamped = Math.max(minX, Math.min(maxX, val));
    return (
      padding.left +
      ((clamped - minX) / (maxX - minX)) * (width - padding.left - padding.right)
    );
  };

  const scaleY = (val: number) => {
    const clamped = Math.max(minY, Math.min(maxY, val));
    return (
      height -
      padding.bottom -
      ((clamped - minY) / (maxY - minY)) * (height - padding.top - padding.bottom)
    );
  };

  // Zero / threshold lines
  const zeroX = scaleX(0); // 0% delta TOV
  const avgY = scaleY(53.0); // ~53% WNBA average clutch TS%

  const containerRef = useRef<HTMLDivElement | null>(null);

  const handleExportPng = () => {
    if (containerRef.current) {
      exportSvgAsPng(containerRef.current, 'pressure-resilience-plot');
    }
  };

  return (
    <div ref={containerRef} className="bg-surface/70 border border-slate-800 rounded-xl p-5 space-y-4">
      <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-2">
        <div>
          <h3 className="text-sm font-bold text-slate-100 flex items-center gap-2">
            <span className="w-2.5 h-2.5 rounded-full bg-rose-500 animate-pulse" />
            Pressure Resilience & Fragility Matrix
          </h3>
          <p className="text-xs text-slate-400">
            Clutch True Shooting % vs Turnover Fragility (ΔTOV%) under &le; 5 pt leverage
          </p>
        </div>
        <div className="flex items-center gap-2">
          <div className="text-[11px] font-mono text-slate-500 bg-surface-raised px-2.5 py-1 rounded border border-slate-800">
            Min. 8 Clutch FGA ({qualified.length} players)
          </div>
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

      <div className="relative w-full aspect-[3/2] sm:aspect-[16/9] max-h-[420px]">
        <svg
          viewBox={`0 0 ${width} ${height}`}
          className="w-full h-full select-none overflow-visible"
        >
          {/* Quadrant shading */}
          <rect
            x={padding.left}
            y={padding.top}
            width={Math.max(0, zeroX - padding.left)}
            height={Math.max(0, avgY - padding.top)}
            fill="#10b981"
            fillOpacity={0.04}
          />
          <rect
            x={zeroX}
            y={avgY}
            width={Math.max(0, width - padding.right - zeroX)}
            height={Math.max(0, height - padding.bottom - avgY)}
            fill="#f43f5e"
            fillOpacity={0.04}
          />

          {/* Quadrant Watermark Labels */}
          <text
            x={padding.left + 12}
            y={padding.top + 20}
            fill="#10b981"
            fillOpacity={0.5}
            fontSize={11}
            fontWeight={700}
            textAnchor="start"
          >
            COLD-BLOODED CLOSERS
          </text>
          <text
            x={width - padding.right - 12}
            y={padding.top + 20}
            fill="#f59e0b"
            fillOpacity={0.5}
            fontSize={11}
            fontWeight={700}
            textAnchor="end"
          >
            HIGH-VARIANCE VOLUME
          </text>
          <text
            x={padding.left + 12}
            y={height - padding.bottom - 12}
            fill="#64748b"
            fillOpacity={0.5}
            fontSize={11}
            fontWeight={700}
            textAnchor="start"
          >
            LOW-ERROR ROLE PLAYERS
          </text>
          <text
            x={width - padding.right - 12}
            y={height - padding.bottom - 12}
            fill="#f43f5e"
            fillOpacity={0.5}
            fontSize={11}
            fontWeight={700}
            textAnchor="end"
          >
            HIGH-PRESSURE FRAGILE
          </text>

          {/* Grid lines */}
          {[-2, 0, 2, 4, 6].map((xVal) => (
            <g key={xVal}>
              <line
                x1={scaleX(xVal)}
                y1={padding.top}
                x2={scaleX(xVal)}
                y2={height - padding.bottom}
                stroke={xVal === 0 ? '#475569' : '#1e293b'}
                strokeWidth={xVal === 0 ? 1.5 : 1}
                strokeDasharray={xVal === 0 ? '4 3' : undefined}
              />
              <text
                x={scaleX(xVal)}
                y={height - padding.bottom + 18}
                fill="#64748b"
                fontSize={10}
                textAnchor="middle"
                fontFamily="monospace"
              >
                {xVal > 0 ? `+${xVal}%` : `${xVal}%`}
              </text>
            </g>
          ))}

          {[35, 45, 55, 65].map((yVal) => (
            <g key={yVal}>
              <line
                x1={padding.left}
                y1={scaleY(yVal)}
                x2={width - padding.right}
                y2={scaleY(yVal)}
                stroke="#1e293b"
                strokeWidth={1}
              />
              <text
                x={padding.left - 10}
                y={scaleY(yVal) + 3}
                fill="#64748b"
                fontSize={10}
                textAnchor="end"
                fontFamily="monospace"
              >
                {yVal}%
              </text>
            </g>
          ))}

          {/* Average clutch TS% reference line */}
          <line
            x1={padding.left}
            y1={avgY}
            x2={width - padding.right}
            y2={avgY}
            stroke="#475569"
            strokeWidth={1.5}
            strokeDasharray="4 3"
          />

          {/* Axis labels */}
          <text
            x={(width + padding.left - padding.right) / 2}
            y={height - 12}
            fill="#94a3b8"
            fontSize={11}
            fontWeight={600}
            textAnchor="middle"
          >
            Turnover Fragility (ΔTOV% Under Pressure) &rarr;
          </text>

          <text
            x={18}
            y={(height + padding.top - padding.bottom) / 2}
            fill="#94a3b8"
            fontSize={11}
            fontWeight={600}
            textAnchor="middle"
            transform={`rotate(-90, 18, ${(height + padding.top - padding.bottom) / 2})`}
          >
            Clutch True Shooting % &rarr;
          </text>

          {/* Player dots */}
          {qualified.map((p) => {
            const cx = scaleX(p.tovFragility);
            const cy = scaleY(p.clutchTsPct);
            const isSelected = p.playerId === selectedPlayerId;
            const isHovered = hoveredProfile?.playerId === p.playerId;

            let fillColor = '#60a5fa'; // default blue
            if (p.tovFragility <= 0 && p.clutchTsPct >= 53) {
              fillColor = '#10b981'; // cold-blooded emerald
            } else if (p.tovFragility > 2 && p.clutchTsPct < 50) {
              fillColor = '#f43f5e'; // fragile rose
            } else if (p.clutchTsPct >= 58) {
              fillColor = '#a855f7'; // hyper efficient purple
            }

            return (
              <g
                key={p.playerId}
                className="cursor-pointer transition-transform duration-150"
                onClick={() => onSelectPlayer(p.playerId)}
                onMouseEnter={() => setHoveredProfile(p)}
                onMouseLeave={() => setHoveredProfile(null)}
              >
                {isSelected && (
                  <circle
                    cx={cx}
                    cy={cy}
                    r={12}
                    fill="none"
                    stroke="#38bdf8"
                    strokeWidth={2}
                    strokeDasharray="3 2"
                    className="animate-spin origin-center"
                  />
                )}
                <circle
                  cx={cx}
                  cy={cy}
                  r={isSelected || isHovered ? 7 : 4.5}
                  fill={fillColor}
                  fillOpacity={isSelected || isHovered ? 1 : 0.75}
                  stroke={isSelected ? '#ffffff' : '#0f172a'}
                  strokeWidth={1.5}
                />
                {(isSelected || isHovered || p.usciScore >= 80) && (
                  <text
                    x={cx}
                    y={cy - 9}
                    fill={isSelected ? '#38bdf8' : '#cbd5e1'}
                    fontSize={isSelected ? 10 : 8.5}
                    fontWeight={isSelected ? 700 : 500}
                    textAnchor="middle"
                    className="pointer-events-none drop-shadow"
                  >
                    {p.playerName.split(' ').pop()}
                  </text>
                )}
              </g>
            );
          })}
        </svg>

        {/* Floating tooltip */}
        {hoveredProfile && (
          <div
            className="absolute top-3 right-3 pointer-events-none bg-surface-raised/95 border border-slate-700 p-3 rounded-lg shadow-xl text-xs space-y-1 z-20 backdrop-blur-sm"
          >
            <div className="font-bold text-white flex items-center justify-between gap-3">
              <span>{hoveredProfile.playerName}</span>
              <span className="text-slate-400 font-mono text-[10px]">
                {hoveredProfile.team} &middot; {hoveredProfile.position}
              </span>
            </div>
            <div className="text-[11px] text-indigo-400 font-medium">
              {hoveredProfile.clutchArchetype}
            </div>
            <div className="grid grid-cols-2 gap-x-4 gap-y-1 text-slate-300 pt-1 font-mono text-[10px]">
              <div>Clutch TS%: <span className="text-emerald-400 font-bold">{hoveredProfile.clutchTsPct.toFixed(1)}%</span></div>
              <div>ΔTS%: <span className={hoveredProfile.tsDelta >= 0 ? 'text-emerald-400' : 'text-rose-400'}>{hoveredProfile.tsDelta >= 0 ? `+${hoveredProfile.tsDelta.toFixed(1)}%` : `${hoveredProfile.tsDelta.toFixed(1)}%`}</span></div>
              <div>ΔTOV%: <span className={hoveredProfile.tovFragility <= 0 ? 'text-emerald-400' : 'text-rose-400'}>{hoveredProfile.tovFragility >= 0 ? `+${hoveredProfile.tovFragility.toFixed(1)}%` : `${hoveredProfile.tovFragility.toFixed(1)}%`}</span></div>
              <div>USCI Score: <span className="text-indigo-300 font-bold">{hoveredProfile.usciScore.toFixed(0)}</span></div>
            </div>
          </div>
        )}
      </div>

      <div className="flex items-center gap-2 text-[11px] text-slate-500 pt-1 border-t border-slate-900">
        <AlertCircle className="w-3.5 h-3.5 text-slate-400 shrink-0" />
        <span>
          <strong>Turnover Fragility (ΔTOV%)</strong> measures the spike in turnover rate during final 5:00 (&le; 5 pt margin) relative to non-clutch minutes. Negative values indicate ball security under full-court defensive pressure.
        </span>
      </div>
    </div>
  );
};
