'use client';

import { useState } from 'react';
import { QbProfile } from '@/lib/types';
import { TeamLogo } from './TeamLogo';
import Image from 'next/image';

interface QbEfficiencyScatterProps {
  qbs: QbProfile[];
  onSelectQb?: (qb: QbProfile) => void;
  selectedQb?: QbProfile | null;
}

export default function QbEfficiencyScatter({
  qbs,
  onSelectQb,
  selectedQb,
}: QbEfficiencyScatterProps) {
  const [hoveredQb, setHoveredQb] = useState<QbProfile | null>(null);

  // Filter QBs with valid numeric ratings
  const validQbs = qbs.filter(
    (q) =>
      typeof q.off_epa_roll === 'number' &&
      !isNaN(q.off_epa_roll) &&
      typeof q.off_cpoe_roll === 'number' &&
      !isNaN(q.off_cpoe_roll)
  );

  if (validQbs.length === 0) {
    return (
      <div className="p-8 text-center text-slate-500 bg-slate-900/60 rounded-xl border border-slate-800">
        No quarterback efficiency coordinates available.
      </div>
    );
  }

  // Bounds for X (EPA/play) and Y (CPOE %)
  // Typical EPA/play ranges from -0.30 to +0.35
  // Typical CPOE ranges from -10.0 to +12.0
  const minEpa = -0.25;
  const maxEpa = 0.35;
  const minCpoe = -10.0;
  const maxCpoe = 12.0;

  const toPercentX = (epa: number) => {
    const clamped = Math.max(minEpa, Math.min(maxEpa, epa));
    return ((clamped - minEpa) / (maxEpa - minEpa)) * 100;
  };

  const toPercentY = (cpoe: number) => {
    const clamped = Math.max(minCpoe, Math.min(maxCpoe, cpoe));
    // SVG / CSS coordinate: 0% is top (high CPOE), 100% is bottom (low CPOE)
    return 100 - ((clamped - minCpoe) / (maxCpoe - minCpoe)) * 100;
  };

  const zeroEpaX = toPercentX(0.0);
  const zeroCpoeY = toPercentY(0.0);

  return (
    <div className="bg-slate-900/90 border border-slate-800 rounded-xl p-5 shadow-xl relative overflow-hidden flex flex-col">
      {/* Header */}
      <div className="flex flex-col sm:flex-row sm:items-center justify-between pb-4 border-b border-slate-800 gap-2 mb-4">
        <div>
          <h3 className="text-base font-semibold text-white flex items-center gap-2">
            Quarterback Composite Tier Matrix
            <span className="text-xs font-mono font-normal text-emerald-400 bg-emerald-950/60 border border-emerald-800/60 px-2 py-0.5 rounded-full">
              EPA/Play vs. CPOE
            </span>
          </h3>
          <p className="text-xs text-slate-400">
            Rolling EPA per dropback (efficiency) vs Completion % Over Expected (accuracy & difficulty).
          </p>
        </div>

        {/* Legend */}
        <div className="flex items-center gap-3 text-[11px] text-slate-400 font-mono">
          <span className="flex items-center gap-1.5">
            <span className="w-2.5 h-2.5 rounded-full bg-emerald-500"></span>
            Tier 1: Elite
          </span>
          <span className="flex items-center gap-1.5">
            <span className="w-2.5 h-2.5 rounded-full bg-blue-500"></span>
            Tier 2: Positive
          </span>
          <span className="flex items-center gap-1.5">
            <span className="w-2.5 h-2.5 rounded-full bg-amber-500"></span>
            Tier 3: Mixed
          </span>
          <span className="flex items-center gap-1.5">
            <span className="w-2.5 h-2.5 rounded-full bg-rose-500"></span>
            Tier 4: Sub-par
          </span>
        </div>
      </div>

      {/* Scatter Canvas */}
      <div className="relative w-full h-[420px] sm:h-[480px] bg-slate-950/60 rounded-lg border border-slate-800/80 p-6 select-none">
        {/* Quadrant Background Labels */}
        <div className="absolute top-4 right-4 text-right pointer-events-none">
          <div className="text-xs font-bold font-mono tracking-wider text-emerald-400/30 uppercase">
            Elite Playmakers
          </div>
          <div className="text-[10px] text-slate-500/40 font-mono">+EPA / +CPOE</div>
        </div>

        <div className="absolute top-4 left-4 text-left pointer-events-none">
          <div className="text-xs font-bold font-mono tracking-wider text-cyan-400/30 uppercase">
            Ball Placement Artists
          </div>
          <div className="text-[10px] text-slate-500/40 font-mono">-EPA / +CPOE</div>
        </div>

        <div className="absolute bottom-4 right-4 text-right pointer-events-none">
          <div className="text-xs font-bold font-mono tracking-wider text-amber-400/30 uppercase">
            Scheme & Deep Shot Drivers
          </div>
          <div className="text-[10px] text-slate-500/40 font-mono">+EPA / -CPOE</div>
        </div>

        <div className="absolute bottom-4 left-4 text-left pointer-events-none">
          <div className="text-xs font-bold font-mono tracking-wider text-rose-400/30 uppercase">
            Struggling / Low Margin
          </div>
          <div className="text-[10px] text-slate-500/40 font-mono">-EPA / -CPOE</div>
        </div>

        {/* Quadrant Divider Grid Lines */}
        <div
          className="absolute top-0 bottom-0 border-l border-dashed border-slate-700/60"
          style={{ left: `${zeroEpaX}%` }}
        >
          <span className="absolute top-1 -translate-x-1/2 bg-slate-900 border border-slate-700 px-1.5 py-0.5 rounded text-[9px] font-mono text-slate-400">
            0.0 EPA
          </span>
        </div>
        <div
          className="absolute left-0 right-0 border-t border-dashed border-slate-700/60"
          style={{ top: `${zeroCpoeY}%` }}
        >
          <span className="absolute left-1 -translate-y-1/2 bg-slate-900 border border-slate-700 px-1.5 py-0.5 rounded text-[9px] font-mono text-slate-400">
            0.0% CPOE
          </span>
        </div>

        {/* Scatter Points (Quarterbacks) */}
        {validQbs.map((qb) => {
          const posX = toPercentX(qb.off_epa_roll);
          const posY = toPercentY(qb.off_cpoe_roll);
          const isSelected = selectedQb?.player_name === qb.player_name;
          const isHovered = hoveredQb?.player_name === qb.player_name;

          // Color by composite score
          const isElite = qb.off_epa_roll > 0.08 && qb.off_cpoe_roll > 1.0;
          const isGood = qb.off_epa_roll > 0 && qb.off_cpoe_roll > -2.0;

          return (
            <div
              key={`${qb.player_name}-${qb.team}`}
              className="absolute -translate-x-1/2 -translate-y-1/2 transition-transform duration-150 cursor-pointer group"
              style={{
                left: `${posX}%`,
                top: `${posY}%`,
                zIndex: isSelected ? 40 : isHovered ? 30 : isElite ? 20 : 10,
              }}
              onClick={() => onSelectQb && onSelectQb(qb)}
              onMouseEnter={() => setHoveredQb(qb)}
              onMouseLeave={() => setHoveredQb(null)}
            >
              {/* Point Node */}
              <div
                className={`relative rounded-full transition-all flex items-center justify-center p-0.5 shadow-md ${
                  isSelected
                    ? 'ring-2 ring-emerald-400 scale-125 bg-emerald-950'
                    : isHovered
                    ? 'ring-2 ring-cyan-400 scale-125 bg-slate-900'
                    : isElite
                    ? 'border-2 border-emerald-400/80 bg-slate-900/90'
                    : isGood
                    ? 'border border-blue-400/70 bg-slate-900/90'
                    : 'border border-slate-600 bg-slate-900/90'
                }`}
              >
                {qb.headshot_url ? (
                  <div className="relative w-6 h-6 rounded-full overflow-hidden bg-slate-800">
                    <Image
                      src={qb.headshot_url}
                      alt={qb.player_name}
                      fill
                      sizes="24px"
                      className="object-cover object-top"
                      unoptimized
                    />
                  </div>
                ) : (
                  <div className="w-5 h-5 flex items-center justify-center">
                    <TeamLogo team={qb.team} size="xs" />
                  </div>
                )}

                {/* Team Mini Badge */}
                <span className="absolute -bottom-1 -right-1 bg-slate-950 border border-slate-800 text-[8px] font-mono px-0.5 rounded text-slate-300">
                  {qb.team}
                </span>
              </div>

              {/* Point Label (Always visible for Elite or on Hover/Selected) */}
              {(isHovered || isSelected || isElite) && (
                <div
                  className={`absolute left-1/2 -translate-x-1/2 mt-1.5 px-2 py-0.5 rounded text-[10px] font-mono whitespace-nowrap border pointer-events-none shadow-xl ${
                    isSelected
                      ? 'bg-emerald-950 text-emerald-200 border-emerald-600 z-50'
                      : isHovered
                      ? 'bg-slate-900 text-cyan-300 border-cyan-500 z-50'
                      : 'bg-slate-900/90 text-slate-200 border-slate-700/80'
                  }`}
                >
                  <span className="font-semibold">{qb.player_name.split(' ').pop()}</span>
                  <span className="ml-1 opacity-75">
                    ({qb.off_epa_roll > 0 ? '+' : ''}
                    {qb.off_epa_roll.toFixed(2)})
                  </span>
                </div>
              )}
            </div>
          );
        })}
      </div>

      {/* Axis Footer */}
      <div className="flex justify-between items-center text-[11px] font-mono text-slate-400 pt-3 border-t border-slate-800/80 mt-2">
        <span>← Lower Offensive EPA (Inefficient)</span>
        <span className="text-slate-300 font-semibold">Offensive EPA / Play</span>
        <span>Higher Offensive EPA (Explosive) →</span>
      </div>
    </div>
  );
}
