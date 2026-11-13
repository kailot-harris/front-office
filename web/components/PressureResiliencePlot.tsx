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

  // Filter to players with meaningful clutch volume (>= 5 clutch FGA) and non-null FG%
  const qualified = profiles.filter((p) => p.clutchFga >= 5 && p.clutchFgPct !== null);

  const width = 600;
  const height = 400;
  const padding = { top: 30, right: 30, bottom: 50, left: 60 };

  // X-axis: clutchFga (0 to 90 FGA)
  const minX = 0;
  const maxX = 90;

  // Y-axis: clutchFgPct (20% to 80%)
  const minY = 20;
  const maxY = 80;

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

  // Threshold lines: 20 FGA volume, 50.0% FG%
  const thresholdX = scaleX(20);
  const avgY = scaleY(50.0);

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
            Clutch Volume & Efficiency Matrix
          </h3>
          <p className="text-xs text-slate-400">
            Real Clutch Field Goal % vs Clutch Shot Attempts (≤ 5 pt margin, final 5:00 4Q/OT)
          </p>
        </div>
        <div className="flex items-center gap-2">
          <div className="text-[11px] font-mono text-slate-400 bg-surface-raised px-2.5 py-1 rounded border border-slate-800">
            Min. 5 Clutch FGA ({qualified.length} closers)
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
            x={thresholdX}
            y={padding.top}
            width={Math.max(0, width - padding.right - thresholdX)}
            height={Math.max(0, avgY - padding.top)}
            fill="#10b981"
            fillOpacity={0.05}
          />
          <rect
            x={padding.left}
            y={avgY}
            width={Math.max(0, thresholdX - padding.left)}
            height={Math.max(0, height - padding.bottom - avgY)}
            fill="#64748b"
            fillOpacity={0.03}
          />

          {/* Quadrant Watermark Labels */}
          <text
            x={width - padding.right - 12}
            y={padding.top + 20}
            fill="#10b981"
            fillOpacity={0.5}
            fontSize={11}
            fontWeight={700}
            textAnchor="end"
          >
            ELITE HIGH-VOLUME CLOSERS
          </text>
          <text
            x={padding.left + 12}
            y={padding.top + 20}
            fill="#818cf8"
            fillOpacity={0.5}
            fontSize={11}
            fontWeight={700}
            textAnchor="start"
          >
            EFFICIENT SECONDARY OPTIONS
          </text>
          <text
            x={width - padding.right - 12}
            y={height - padding.bottom - 12}
            fill="#f59e0b"
            fillOpacity={0.5}
            fontSize={11}
            fontWeight={700}
            textAnchor="end"
          >
            HEAVY-VOLUME CONTESTED
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
            SITUATIONAL ROLE OPTIONS
          </text>

          {/* Grid lines: FGA */}
          {[10, 20, 30, 40, 50, 60, 70, 80].map((xVal) => (
            <g key={xVal}>
              <line
                x1={scaleX(xVal)}
                y1={padding.top}
                x2={scaleX(xVal)}
                y2={height - padding.bottom}
                stroke={xVal === 20 ? '#475569' : '#1e293b'}
                strokeWidth={xVal === 20 ? 1.5 : 1}
                strokeDasharray={xVal === 20 ? '4 3' : undefined}
              />
              <text
                x={scaleX(xVal)}
                y={height - padding.bottom + 18}
                fill="#64748b"
                fontSize={10}
                textAnchor="middle"
                fontFamily="monospace"
              >
                {xVal}
              </text>
            </g>
          ))}

          {/* Grid lines: FG% */}
          {[30, 40, 50, 60, 70].map((yVal) => (
            <g key={yVal}>
              <line
                x1={padding.left}
                y1={scaleY(yVal)}
                x2={width - padding.right}
                y2={scaleY(yVal)}
                stroke={yVal === 50 ? '#475569' : '#1e293b'}
                strokeWidth={yVal === 50 ? 1.5 : 1}
                strokeDasharray={yVal === 50 ? '4 3' : undefined}
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

          {/* Axis labels */}
          <text
            x={(width + padding.left - padding.right) / 2}
            y={height - 12}
            fill="#94a3b8"
            fontSize={11}
            fontWeight={600}
            textAnchor="middle"
          >
            Clutch Field Goal Attempts (FGA) &rarr;
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
            Clutch Field Goal % &rarr;
          </text>

          {/* Player dots */}
          {qualified.map((p) => {
            const cx = scaleX(p.clutchFga);
            const cy = scaleY(p.clutchFgPct ?? 50);
            const isSelected = p.playerId === selectedPlayerId;
            const isHovered = hoveredProfile?.playerId === p.playerId;

            let fillColor = '#60a5fa'; // default sky
            if ((p.clutchFgPct ?? 0) >= 55 && (p.clutchPoints ?? 0) >= 30) {
              fillColor = '#10b981'; // cold-blooded emerald
            } else if ((p.clutchFgPct ?? 0) >= 50) {
              fillColor = '#a855f7'; // hyper efficient purple
            } else if (p.clutchFga >= 20 && (p.clutchFgPct ?? 0) < 50) {
              fillColor = '#f59e0b'; // volume contested amber
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
                {(isSelected || isHovered || p.clutchFga >= 35) && (
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
              <span className="text-slate-400 font-mono text-[11px] sm:text-[10px]">
                {hoveredProfile.team} &middot; {hoveredProfile.position}
              </span>
            </div>
            <div className="text-[11px] text-indigo-400 font-medium">
              {hoveredProfile.clutchArchetype}
            </div>
            <div className="grid grid-cols-2 gap-x-4 gap-y-1 text-slate-300 pt-1 font-mono text-[11px] sm:text-[10px]">
              <div>Clutch FG%: <span className="text-emerald-400 font-bold">{hoveredProfile.clutchFgPct !== null ? `${hoveredProfile.clutchFgPct.toFixed(1)}%` : 'N/A'}</span></div>
              <div>Clutch PTS: <span className="text-amber-400 font-bold">{hoveredProfile.clutchPoints ?? 'N/A'}</span></div>
              <div>Clutch FGA: <span className="text-slate-100 font-bold">{hoveredProfile.clutchFga}</span></div>
              <div>Points / FGA: <span className="text-indigo-300 font-bold">{hoveredProfile.clutchPpp !== null ? hoveredProfile.clutchPpp.toFixed(2) : 'N/A'}</span></div>
              <div className="col-span-2 text-[11px] sm:text-[9px] text-slate-400">Source: {hoveredProfile.provenance}</div>
            </div>
          </div>
        )}
      </div>

      <div className="flex items-center gap-2 text-[11px] text-slate-400 pt-1 border-t border-slate-900">
        <AlertCircle className="w-3.5 h-3.5 text-slate-400 shrink-0" />
        <span>
          <strong>Real Play-by-Play Tracking</strong>: Clutch situations defined as 4th quarter or overtime, &le; 5:00 remaining, score margin &le; 5 points. Sourced from <code>cache/player_pbp_features.rds</code>. Players with &lt; 5 clutch FGA emit typed NA to prevent small-sample distortion.
        </span>
      </div>
    </div>
  );
};
