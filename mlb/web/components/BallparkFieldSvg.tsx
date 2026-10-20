'use client';

import React, { useState, useMemo } from 'react';
import {
  getBallparkGeometry,
  getAllBallparks,
  generateBallparkSvgData,
} from '@/lib/ballparks';
import { PlayerBattedBall } from '@/lib/types';
import { Info, MapPin } from 'lucide-react';
import { TeamLogo } from '@/components/TeamLogo';

interface BallparkFieldSvgProps {
  initialTeam?: string;
  battedBalls?: PlayerBattedBall[];
  hoveredBall?: PlayerBattedBall | null;
  onHoverBall?: (ball: PlayerBattedBall | null) => void;
  showParkSelector?: boolean;
  width?: number;
  height?: number;
}

const HIT_COLORS: Record<string, { fill: string; stroke: string; label: string }> = {
  'Home Run': { fill: '#ef4444', stroke: '#fee2e2', label: 'Home Run' },
  'Triple': { fill: '#a855f7', stroke: '#f3e8ff', label: 'Triple' },
  'Double': { fill: '#06b6d4', stroke: '#cffafe', label: 'Double' },
  'Single': { fill: '#10b981', stroke: '#d1fae5', label: 'Single' },
  'Out': { fill: '#64748b', stroke: '#334155', label: 'Out' },
};

export const BallparkFieldSvg: React.FC<BallparkFieldSvgProps> = ({
  initialTeam = 'LAD',
  battedBalls = [],
  hoveredBall = null,
  onHoverBall,
  showParkSelector = true,
  width = 520,
  height = 460,
}) => {
  const [selectedTeam, setSelectedTeam] = useState<string>(initialTeam);
  const allParks = useMemo(() => getAllBallparks(), []);
  const park = useMemo(() => getBallparkGeometry(selectedTeam), [selectedTeam]);

  // SVG coordinate system
  const homeX = width / 2;
  const homeY = height - 45;
  const scale = 0.88; // Pixels per foot

  // Geometry calculations
  const svgData = useMemo(() => {
    return generateBallparkSvgData(park, homeX, homeY, scale);
  }, [park, homeX, homeY, scale]);

  return (
    <div className="w-full flex flex-col items-center select-none space-y-3">
      {/* Ballpark Header & Selector Bar */}
      {showParkSelector && (
        <div className="w-full flex flex-col sm:flex-row sm:items-center justify-between gap-3 bg-surface/80 border border-slate-800/90 rounded-xl p-3">
          <div className="flex items-center gap-2.5">
            <TeamLogo team={park.team} size="sm" />
            <div>
              <div className="flex items-center gap-2">
                <span className="font-bold text-white text-sm">{park.parkName}</span>
                <span className="text-[11px] font-mono px-2 py-0.5 rounded bg-slate-800 text-slate-300">
                  {park.team}
                </span>
                <span className="text-[10px] font-mono px-1.5 py-0.2 rounded bg-indigo-500/15 text-indigo-300 border border-indigo-500/30">
                  {park.roofType}
                </span>
              </div>
              <div className="text-[11px] text-slate-400 flex items-center gap-1.5 mt-0.5">
                <MapPin className="w-3 h-3 text-slate-500" />
                <span>{park.cityState}</span>
                <span className="text-slate-600">•</span>
                <span>{park.surface}</span>
                <span className="text-slate-600">•</span>
                <span>{park.foulTerritory} Foul Ground</span>
              </div>
            </div>
          </div>

          <div className="flex items-center gap-2">
            <label htmlFor="park-select" className="text-xs text-slate-400 font-mono">
              Overlay Park:
            </label>
            <select
              id="park-select"
              value={selectedTeam}
              onChange={(e) => setSelectedTeam(e.target.value)}
              className="bg-surface-raised border border-slate-700 text-white text-xs rounded-lg px-2.5 py-1.5 font-mono focus:outline-none focus:ring-1 focus:ring-indigo-500"
            >
              {allParks.map((p) => (
                <option key={p.team} value={p.team}>
                  {p.team} — {p.parkName}
                </option>
              ))}
            </select>
          </div>
        </div>
      )}

      {/* Main SVG Diamond Canvas */}
      <div className="relative w-full aspect-[520/460] max-w-[520px]">
        <svg
          viewBox={`0 0 ${width} ${height}`}
          className="w-full h-full overflow-visible"
        >
          <defs>
            {/* Outfield Grass Radial Gradient */}
            <radialGradient id="ballparkGrass" cx="50%" cy="90%" r="90%">
              <stop offset="0%" stopColor="#064e3b" stopOpacity="0.5" />
              <stop offset="65%" stopColor="#022c22" stopOpacity="0.8" />
              <stop offset="100%" stopColor="#091422" stopOpacity="0.95" />
            </radialGradient>

            {/* Infield Dirt Gradient */}
            <radialGradient id="ballparkDirt" cx="50%" cy="75%" r="75%">
              <stop offset="0%" stopColor="#78350f" stopOpacity="0.45" />
              <stop offset="100%" stopColor="#451a03" stopOpacity="0.65" />
            </radialGradient>

            {/* Warning Track Texture Gradient */}
            <radialGradient id="warningTrack" cx="50%" cy="85%" r="85%">
              <stop offset="0%" stopColor="#92400e" stopOpacity="0.6" />
              <stop offset="100%" stopColor="#713f12" stopOpacity="0.85" />
            </radialGradient>

            {/* 3D Wall Extrusion Filter */}
            <filter id="wallGlow" x="-20%" y="-20%" width="140%" height="140%">
              <feDropShadow dx="0" dy="2" stdDeviation="3" floodColor="#38bdf8" floodOpacity="0.3" />
            </filter>
            <filter id="highWallGlow" x="-20%" y="-20%" width="140%" height="140%">
              <feDropShadow dx="0" dy="3" stdDeviation="4" floodColor="#f59e0b" floodOpacity="0.5" />
            </filter>
          </defs>

          {/* Foul Ground Perimeter & Backstop */}
          <path
            d={svgData.backstopPolygon}
            fill="#0f172a"
            stroke="#1e293b"
            strokeWidth="1.2"
          />

          {/* Fair Territory Solid Grass Polygon (Exact shape of the outfield wall) */}
          <path
            d={svgData.fairTerritoryPolygon}
            fill="url(#ballparkGrass)"
            stroke="#1e293b"
            strokeWidth="1"
          />

          {/* Warning Track Ribbon (15 ft buffer inward along the wall contour) */}
          <path
            d={svgData.warningTrackPolygon}
            fill="url(#warningTrack)"
            stroke="#b45309"
            strokeWidth="0.8"
            opacity="0.8"
          />

          {/* Foul Lines extending to poles */}
          {svgData.wallPoints.length > 0 && (
            <>
              {/* Left Field Foul Line (Home to LF vertex) */}
              <line
                x1={homeX}
                y1={homeY}
                x2={svgData.wallPoints[0].x}
                y2={svgData.wallPoints[0].y}
                stroke="#e2e8f0"
                strokeWidth="1.6"
              />
              {/* Right Field Foul Line (Home to RF vertex) */}
              <line
                x1={homeX}
                y1={homeY}
                x2={svgData.wallPoints[svgData.wallPoints.length - 1].x}
                y2={svgData.wallPoints[svgData.wallPoints.length - 1].y}
                stroke="#e2e8f0"
                strokeWidth="1.6"
              />

              {/* Foul Poles */}
              <circle
                cx={svgData.wallPoints[0].x}
                cy={svgData.wallPoints[0].y}
                r="4.5"
                fill="#fbbf24"
                stroke="#d97706"
                strokeWidth="1.5"
              />
              <circle
                cx={svgData.wallPoints[svgData.wallPoints.length - 1].x}
                cy={svgData.wallPoints[svgData.wallPoints.length - 1].y}
                r="4.5"
                fill="#fbbf24"
                stroke="#d97706"
                strokeWidth="1.5"
              />
            </>
          )}

          {/* Distance Reference Arcs (200', 300', 400') */}
          {[200, 300, 400].map((ft) => {
            const r = ft * scale;
            const leftX = homeX - r * Math.sin(Math.PI / 4);
            const leftY = homeY - r * Math.cos(Math.PI / 4);
            const rightX = homeX + r * Math.sin(Math.PI / 4);
            const rightY = homeY - r * Math.cos(Math.PI / 4);

            return (
              <g key={ft}>
                <path
                  d={`M ${leftX} ${leftY} A ${r} ${r} 0 0 1 ${rightX} ${rightY}`}
                  fill="none"
                  stroke="#1e293b"
                  strokeWidth="1"
                  strokeDasharray="3 4"
                />
                <text
                  x={homeX + 4}
                  y={homeY - r + 11}
                  fill="#475569"
                  fontSize="8.5"
                  fontFamily="monospace"
                >
                  {ft}&apos;
                </text>
              </g>
            );
          })}

          {/* Infield Dirt Structure */}
          {/* Radius ~155 ft from mound / home */}
          <path
            d={`M ${homeX - 110} ${homeY - 110} A 155 155 0 0 1 ${homeX + 110} ${homeY - 110} L ${homeX} ${homeY} Z`}
            fill="url(#ballparkDirt)"
            stroke="#334155"
            strokeWidth="1"
          />

          {/* Historic Keyhole Dirt Strip (if park.hasKeyholeDirt e.g. ARI, DET) */}
          {park.hasKeyholeDirt && (
            <path
              d={`M ${homeX - 4.5} ${homeY - 12} L ${homeX - 4.5} ${homeY - 55} L ${homeX + 4.5} ${homeY - 55} L ${homeX + 4.5} ${homeY - 12} Z`}
              fill="#78350f"
              stroke="#92400e"
              strokeWidth="0.8"
              opacity="0.9"
            />
          )}

          {/* Infield Diamond (90-ft basepaths: ~79px at scale 0.88) */}
          {/* 1B: (homeX + 55, homeY - 55), 2B: (homeX, homeY - 110), 3B: (homeX - 55, homeY - 55) */}
          <polygon
            points={`${homeX},${homeY} ${homeX + 55},${homeY - 55} ${homeX},${homeY - 110} ${homeX - 55},${homeY - 55}`}
            fill="#020617"
            fillOpacity="0.6"
            stroke="#64748b"
            strokeWidth="1.2"
          />

          {/* Pitcher's Mound (60.5 ft = 53.2 px) */}
          <circle
            cx={homeX}
            cy={homeY - 53.2}
            r="5.5"
            fill="#78350f"
            stroke="#b45309"
            strokeWidth="1"
          />
          {/* Pitcher's Rubber */}
          <rect
            x={homeX - 2.2}
            y={homeY - 54.2}
            width="4.4"
            height="1.5"
            fill="#f8fafc"
          />

          {/* Bases (1B, 2B, 3B diamonds) */}
          <rect
            x={homeX + 52.5}
            y={homeY - 57.5}
            width="5.5"
            height="5.5"
            fill="#f8fafc"
            transform={`rotate(45 ${homeX + 55} ${homeY - 55})`}
          />
          <rect
            x={homeX - 2.75}
            y={homeY - 112.75}
            width="5.5"
            height="5.5"
            fill="#f8fafc"
            transform={`rotate(45 ${homeX} ${homeY - 110})`}
          />
          <rect
            x={homeX - 57.5}
            y={homeY - 57.5}
            width="5.5"
            height="5.5"
            fill="#f8fafc"
            transform={`rotate(45 ${homeX - 55} ${homeY - 55})`}
          />

          {/* Home Plate */}
          <polygon
            points={`${homeX},${homeY} ${homeX - 4.5},${homeY + 3.5} ${homeX - 4.5},${homeY + 7} ${homeX + 4.5},${homeY + 7} ${homeX + 4.5},${homeY + 3.5}`}
            fill="#f8fafc"
          />

          {/* Outfield Wall Base Path (All segments) */}
          <path
            d={svgData.wallPath}
            fill="none"
            stroke="#0284c7"
            strokeWidth="2.5"
            strokeLinecap="round"
            strokeLinejoin="round"
            filter="url(#wallGlow)"
          />

          {/* High Wall 3D Extrusion Highlights (e.g. Green Monster, Oracle Cove, Target Field, Camden) */}
          {svgData.highWallSegments.map((seg, idx) => (
            <g key={idx}>
              {/* 3D Shadow Line */}
              <line
                x1={seg.x1}
                y1={seg.y1}
                x2={seg.x2}
                y2={seg.y2}
                stroke="#f59e0b"
                strokeWidth="4.5"
                strokeLinecap="square"
                filter="url(#highWallGlow)"
              />
              <line
                x1={seg.x1}
                y1={seg.y1}
                x2={seg.x2}
                y2={seg.y2}
                stroke="#fef08a"
                strokeWidth="2"
                strokeLinecap="round"
              />
            </g>
          ))}

          {/* Wall Distance & Architectural Landmark Markers */}
          {svgData.wallPoints
            .filter((p) => p.isKeyMarker || p.label)
            .map((p, idx) => {
              const isHigh = p.wallHeight >= 14;
              return (
                <g key={idx} className="cursor-default">
                  <circle
                    cx={p.x}
                    cy={p.y}
                    r={isHigh ? 4 : 3}
                    fill={isHigh ? '#f59e0b' : '#38bdf8'}
                    stroke="#ffffff"
                    strokeWidth="1.2"
                  />
                  {p.label && (
                    <text
                      x={p.x + (p.angle > 0 ? 6 : p.angle < 0 ? -6 : 0)}
                      y={p.y - 7}
                      textAnchor={p.angle > 10 ? 'start' : p.angle < -10 ? 'end' : 'middle'}
                      fill={isHigh ? '#fbbf24' : '#7dd3fc'}
                      fontSize="9"
                      fontFamily="monospace"
                      fontWeight="bold"
                    >
                      {p.label}
                    </text>
                  )}
                </g>
              );
            })}

          {/* Plotted Batted Balls */}
          {battedBalls.map((b, idx) => {
            const svgX = homeX + b.x * scale;
            const svgY = homeY - b.y * scale;
            const colorCfg = HIT_COLORS[b.hit_type] || HIT_COLORS['Out'];
            const isHovered = hoveredBall === b;
            const isHR = b.hit_type === 'Home Run';

            return (
              <g
                key={idx}
                className="cursor-pointer transition-transform duration-150"
                onMouseEnter={() => onHoverBall?.(b)}
                onMouseLeave={() => onHoverBall?.(null)}
                onClick={() => onHoverBall?.(b)}
              >
                {(isHR || isHovered) && (
                  <circle
                    cx={svgX}
                    cy={svgY}
                    r={isHovered ? 13 : 9}
                    fill={colorCfg.fill}
                    fillOpacity={isHovered ? 0.45 : 0.25}
                    className={isHR ? 'animate-pulse' : ''}
                  />
                )}
                <circle
                  cx={svgX}
                  cy={svgY}
                  r={isHovered ? 6.5 : isHR ? 5.5 : 4}
                  fill={colorCfg.fill}
                  stroke={isHovered ? '#ffffff' : colorCfg.stroke}
                  strokeWidth={isHovered ? 2 : 1}
                />
              </g>
            );
          })}
        </svg>

        {/* Hover Tooltip Overlay */}
        {hoveredBall && (
          <div className="absolute top-2 left-2 right-2 sm:right-auto sm:max-w-xs bg-surface/95 border border-indigo-500/40 rounded-lg p-3 shadow-2xl pointer-events-none text-xs space-y-1.5 z-20 backdrop-blur-md">
            <div className="flex items-center justify-between">
              <span className="font-bold uppercase tracking-wider text-white">
                {hoveredBall.hit_type}
              </span>
              <span className="font-mono text-slate-400">{hoveredBall.dist} ft</span>
            </div>
            <div className="grid grid-cols-2 gap-2 font-mono text-[11px] text-slate-300">
              <div>
                EV: <strong className="text-white">{hoveredBall.ev} mph</strong>
              </div>
              <div>
                LA: <strong className="text-white">{hoveredBall.la}°</strong>
              </div>
              <div>
                Spray: <strong className="text-white">{hoveredBall.bearing}°</strong>
              </div>
              <div>
                HR in: <strong className="text-amber-400">{hoveredBall.parks_hr_count}/30 Parks</strong>
              </div>
            </div>
          </div>
        )}
      </div>

      {/* Iconic Features List */}
      <div className="w-full flex items-center justify-between text-xs bg-surface-raised/60 border border-slate-800 rounded-lg px-3 py-2 flex-wrap gap-2">
        <div className="flex items-center gap-1.5 text-slate-400 text-[11px]">
          <Info className="w-3.5 h-3.5 text-indigo-400 shrink-0" />
          <span className="font-semibold text-slate-300">Architectural Profile:</span>
          <span>{park.iconicFeatures.join(' • ')}</span>
        </div>
      </div>
    </div>
  );
};
