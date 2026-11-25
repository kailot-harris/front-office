'use client';

/**
 * Reliability curves for /players/leaders/methodology (NBA_analytics#258).
 * One SVG chart per group (counting, shooting, rates, RAPM), drawn directly
 * from leader_methodology.json with the study's reference bars (0.5-0.8).
 */
import React, { useState } from 'react';
import type { LeaderMethodologyPayload, LeaderStudyGroup } from '@/lib/leaderMethodologyTypes';

interface CurvePoint {
  x: number;
  y: number;
  lo: number;
  hi: number;
}

interface CurveSeries {
  key: string;
  label: string;
  color: string;
  points: CurvePoint[];
}

const PALETTE = [
  '#f97316', // orange
  '#38bdf8', // sky
  '#34d399', // emerald
  '#a78bfa', // violet
  '#f472b6', // pink
  '#facc15', // yellow
  '#2dd4bf', // teal
  '#fb7185', // rose
];

const RAPM_LABELS: Record<'orapm' | 'drapm' | 'total_rapm', string> = {
  orapm: 'Offensive RAPM',
  drapm: 'Defensive RAPM',
  total_rapm: 'Total RAPM',
};

type CurveMode = 'split_half' | 'spearman_brown';

function ReliabilityChartCard({
  group,
  title,
  xLabel,
  series,
  referenceBars,
  mode,
}: {
  group: LeaderStudyGroup;
  title: string;
  xLabel: string;
  series: CurveSeries[];
  referenceBars: number[];
  mode: CurveMode;
}) {
  const W = 560;
  const H = 260;
  const pad = { top: 16, right: 18, bottom: 38, left: 44 };
  const plotW = W - pad.left - pad.right;
  const plotH = H - pad.top - pad.bottom;

  const allX = series.flatMap((s) => s.points.map((p) => p.x));
  const minX = allX.length ? Math.min(...allX) : 0;
  const maxX = allX.length ? Math.max(...allX) : 1;
  const spanX = maxX > minX ? maxX - minX : 1;

  const allY = series.flatMap((s) => s.points.map((p) => p.y));
  const minY = Math.min(0, ...(allY.length ? allY : [0]));
  const maxY = 1;
  const spanY = maxY - minY;

  const xPx = (x: number) => pad.left + ((x - minX) / spanX) * plotW;
  const yPx = (y: number) => pad.top + ((maxY - Math.max(minY, Math.min(maxY, y))) / spanY) * plotH;

  const xTicks = 5;
  const ticks = Array.from({ length: xTicks }, (_, i) => Math.round(minX + (spanX * i) / (xTicks - 1)));

  return (
    <div
      data-testid={`leader-chart-${group}`}
      className="rounded-xl border border-slate-800 bg-surface-raised/60 p-4 space-y-3"
    >
      <div className="flex items-baseline justify-between gap-2">
        <h3 className="text-sm font-bold text-slate-100">{title}</h3>
        <span className="text-[11px] text-slate-400">
          {mode === 'split_half' ? 'Split-half r' : 'Spearman-Brown (2n)'}
        </span>
      </div>

      <svg
        viewBox={`0 0 ${W} ${H}`}
        className="w-full h-auto"
        role="img"
        aria-label={`${title} reliability curve (${mode === 'split_half' ? 'split-half r' : 'Spearman-Brown'})`}
      >
        {/* Reference bars from study settings */}
        {referenceBars.map((bar) => {
          const y = yPx(bar);
          return (
            <g key={bar}>
              <line
                x1={pad.left}
                x2={W - pad.right}
                y1={y}
                y2={y}
                stroke="#475569"
                strokeDasharray="4 4"
                strokeWidth={1}
              />
              <text x={pad.left - 6} y={y + 3} textAnchor="end" fontSize={10} fill="#94a3b8">
                {bar.toFixed(1)}
              </text>
            </g>
          );
        })}

        {/* Zero and 1.0 baselines */}
        <line x1={pad.left} x2={W - pad.right} y1={yPx(0)} y2={yPx(0)} stroke="#334155" strokeWidth={1} />
        <line x1={pad.left} x2={W - pad.right} y1={yPx(1)} y2={yPx(1)} stroke="#1e293b" strokeWidth={1} />
        <text x={pad.left - 6} y={yPx(0) + 3} textAnchor="end" fontSize={10} fill="#64748b">
          0.0
        </text>
        <text x={pad.left - 6} y={yPx(1) + 3} textAnchor="end" fontSize={10} fill="#64748b">
          1.0
        </text>

        {/* X-axis ticks */}
        {ticks.map((t, idx) => {
          const x = xPx(t);
          return (
            <g key={`${t}-${idx}`}>
              <line x1={x} x2={x} y1={pad.top} y2={H - pad.bottom} stroke="#1e293b" strokeWidth={1} />
              <text x={x} y={H - pad.bottom + 14} textAnchor="middle" fontSize={10} fill="#94a3b8">
                {t.toLocaleString('en-US')}
              </text>
            </g>
          );
        })}
        <text x={pad.left + plotW / 2} y={H - 4} textAnchor="middle" fontSize={10} fill="#94a3b8">
          {xLabel}
        </text>

        {/* Curves */}
        {series.map((s) => {
          if (!s.points.length) return null;
          const d = s.points
            .map((p, idx) => `${idx === 0 ? 'M' : 'L'}${xPx(p.x).toFixed(1)},${yPx(p.y).toFixed(1)}`)
            .join(' ');
          return (
            <path
              key={s.key}
              d={d}
              fill="none"
              stroke={s.color}
              strokeWidth={2}
              strokeLinejoin="round"
              strokeLinecap="round"
            />
          );
        })}
      </svg>

      {/* Legend */}
      <ul className="flex flex-wrap gap-x-4 gap-y-1 text-[11px] text-slate-300">
        {series.map((s) => (
          <li key={s.key} className="flex items-center gap-1.5">
            <span className="inline-block h-2 w-3 rounded-sm" style={{ backgroundColor: s.color }} />
            <span>{s.label}</span>
          </li>
        ))}
      </ul>
    </div>
  );
}

export function LeaderMethodologyCharts({ data }: { data: LeaderMethodologyPayload }) {
  const [mode, setMode] = useState<CurveMode>('split_half');
  const bars = data.settings.reference_bars;

  const statSeriesForGroup = (group: 'counting' | 'shooting' | 'rates'): CurveSeries[] =>
    Object.entries(data.stats)
      .filter(([, st]) => st.group === group)
      .map(([key, st], idx) => ({
        key,
        label: st.label,
        color: PALETTE[idx % PALETTE.length],
        points: st.split_half
          .filter((pt) => (mode === 'split_half' ? pt.r !== null : pt.r_sb !== null))
          .map((pt) => ({
            x: mode === 'split_half' ? pt.n : pt.sb_sample,
            y: (mode === 'split_half' ? pt.r : pt.r_sb) as number,
            lo: (mode === 'split_half' ? pt.r_lo : pt.r_sb_lo) as number,
            hi: (mode === 'split_half' ? pt.r_hi : pt.r_sb_hi) as number,
          })),
      }));

  const rapmMeasures: ('orapm' | 'drapm' | 'total_rapm')[] = ['orapm', 'drapm', 'total_rapm'];
  const rapmSeries: CurveSeries[] = rapmMeasures.map((m, idx) => ({
    key: m,
    label: RAPM_LABELS[m],
    color: PALETTE[idx % PALETTE.length],
    points: data.rapm.thresholds
      .filter((pt) => pt.measure === m)
      .map((pt) => ({
        x: mode === 'split_half' ? pt.lo : pt.lo * 2,
        y: mode === 'split_half' ? pt.r : pt.r_sb,
        lo: mode === 'split_half' ? pt.r_lo : pt.r_sb_lo,
        hi: mode === 'split_half' ? pt.r_hi : pt.r_sb_hi,
      })),
  }));

  return (
    <div className="space-y-4">
      <div className="flex flex-wrap items-center justify-between gap-2">
        <p className="text-xs text-slate-400">
          Dashed horizontal lines show the study&rsquo;s reference bars ({bars.join(', ')}).
        </p>
        <div role="group" aria-label="Reliability curve mode" className="flex gap-1">
          <button
            type="button"
            aria-pressed={mode === 'split_half'}
            onClick={() => setMode('split_half')}
            className={`px-3 py-1 rounded-full text-xs font-semibold border ${
              mode === 'split_half'
                ? 'bg-orange-500/20 text-orange-300 border-orange-500/40'
                : 'text-slate-300 border-slate-700 hover:border-slate-500'
            }`}
          >
            Split-half r (n)
          </button>
          <button
            type="button"
            aria-pressed={mode === 'spearman_brown'}
            onClick={() => setMode('spearman_brown')}
            className={`px-3 py-1 rounded-full text-xs font-semibold border ${
              mode === 'spearman_brown'
                ? 'bg-orange-500/20 text-orange-300 border-orange-500/40'
                : 'text-slate-300 border-slate-700 hover:border-slate-500'
            }`}
          >
            Spearman-Brown (2n)
          </button>
        </div>
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-2 gap-4">
        <ReliabilityChartCard
          group="counting"
          title="Counting stats (per game)"
          xLabel={mode === 'split_half' ? 'Games per half (n)' : 'Projected sample (games, 2n)'}
          series={statSeriesForGroup('counting')}
          referenceBars={bars}
          mode={mode}
        />
        <ReliabilityChartCard
          group="shooting"
          title="Shooting percentages"
          xLabel={mode === 'split_half' ? 'Attempts per half (n)' : 'Projected sample (attempts, 2n)'}
          series={statSeriesForGroup('shooting')}
          referenceBars={bars}
          mode={mode}
        />
        <ReliabilityChartCard
          group="rates"
          title="Rates (Basketball Reference definitions)"
          xLabel={mode === 'split_half' ? 'Minutes per half (n)' : 'Projected sample (minutes, 2n)'}
          series={statSeriesForGroup('rates')}
          referenceBars={bars}
          mode={mode}
        />
        <ReliabilityChartCard
          group="rapm"
          title="RAPM (possessions per side)"
          xLabel={mode === 'split_half' ? 'Min possessions per side in each half (k)' : 'Season equivalent (2k per side)'}
          series={rapmSeries}
          referenceBars={bars}
          mode={mode}
        />
      </div>
    </div>
  );
}
