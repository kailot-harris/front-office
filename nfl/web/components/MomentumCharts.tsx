import React from 'react';

/** Fixed decimals with an explicit sign, e.g. +0.12 or -0.40. Display formatting only. */
export const signed = (v: number, digits = 2): string => {
  const s = v.toFixed(digits);
  return v > 0 ? `+${s}` : s;
};

interface SparklineProps {
  points: { week: number; opponent: string; form_epa: number | null }[];
  /** Team name for the accessible label. */
  team: string;
}

/**
 * Opponent-adjusted EPA per play by game, hand-drawn SVG (the site has no charting
 * dependency). Games with no published value are skipped, never filled; the line
 * joins the games that have one. The vertical scale is fitted to the team's own
 * points, so only the shape is comparable across rows.
 */
export const Sparkline: React.FC<SparklineProps> = ({ points, team }) => {
  const valued = points.filter((p): p is { week: number; opponent: string; form_epa: number } => p.form_epa !== null);
  if (valued.length === 0) return null;
  const w = 96;
  const h = 28;
  const pad = 3;
  const first = valued[0];
  const last = valued[valued.length - 1];
  const skipped = points.length - valued.length;
  const label = `${team} opponent-adjusted EPA per play by game: ${
    valued.length === 1
      ? `one game, ${first.form_epa}`
      : `${valued.length} games, from ${first.form_epa} in week ${first.week} to ${last.form_epa} in week ${last.week}`
  }${skipped > 0 ? `; ${skipped} game${skipped === 1 ? '' : 's'} without a value` : ''}`;
  const ys = valued.map((p) => p.form_epa);
  const min = Math.min(...ys);
  const max = Math.max(...ys);
  const span = max - min || 1;
  const x = (i: number) => (valued.length === 1 ? w / 2 : pad + (i * (w - 2 * pad)) / (valued.length - 1));
  const y = (v: number) => (max === min ? h / 2 : h - pad - ((v - min) / span) * (h - 2 * pad));
  const d = valued.map((p, i) => `${i === 0 ? 'M' : 'L'}${x(i).toFixed(1)} ${y(p.form_epa).toFixed(1)}`).join(' ');
  return (
    <svg viewBox={`0 0 ${w} ${h}`} width={w} height={h} role="img" aria-label={label} className="text-accent-400 inline-block align-middle">
      {valued.length > 1 && (
        <path d={d} fill="none" stroke="currentColor" strokeWidth={1.5} strokeLinejoin="round" strokeLinecap="round" />
      )}
      <circle cx={x(valued.length - 1)} cy={y(last.form_epa)} r={2.2} fill="currentColor" />
    </svg>
  );
};

export interface BarItem {
  key: string;
  label: string;
  value: number;
}

/**
 * Diverging bars around zero. Bar length is the published value divided by the
 * largest absolute value in the list (a display scale); the number beside each
 * bar is the published value itself.
 */
export const DivergingBars: React.FC<{ items: BarItem[]; digits?: number }> = ({ items, digits = 2 }) => {
  const maxAbs = Math.max(...items.map((i) => Math.abs(i.value)), 0);
  return (
    <ul className="space-y-1.5">
      {items.map((item) => {
        const pct = maxAbs === 0 ? 0 : (Math.abs(item.value) / maxAbs) * 50;
        return (
          <li key={item.key} className="grid grid-cols-[minmax(0,10rem)_1fr_3.5rem] items-center gap-2 text-xs">
            <span className="text-slate-300">{item.label}</span>
            <span className="relative h-3 rounded bg-slate-800/60" aria-hidden="true">
              <span className="absolute inset-y-0 left-1/2 w-px bg-slate-500" />
              {item.value !== 0 && (
                <span
                  className={`absolute inset-y-0 ${item.value > 0 ? 'left-1/2 bg-emerald-500' : 'right-1/2 bg-rose-500'}`}
                  style={{ width: `${pct}%` }}
                />
              )}
            </span>
            <span className="font-mono tabular-nums text-right text-slate-200">{signed(item.value, digits)}</span>
          </li>
        );
      })}
    </ul>
  );
};

interface RankHistoryProps {
  history: { season: number; week: number; rank: number }[];
  teamCount: number;
  team: string;
}

/** Weekly rank line, rank 1 at the top. A single week draws as one dot. */
export const RankHistoryLine: React.FC<RankHistoryProps> = ({ history, teamCount, team }) => {
  const w = 220;
  const h = 64;
  const padX = 10;
  const padY = 8;
  const x = (i: number) => (history.length === 1 ? w / 2 : padX + (i * (w - 2 * padX)) / (history.length - 1));
  const y = (rank: number) => padY + ((rank - 1) / Math.max(teamCount - 1, 1)) * (h - 2 * padY);
  const d = history.map((p, i) => `${i === 0 ? 'M' : 'L'}${x(i).toFixed(1)} ${y(p.rank).toFixed(1)}`).join(' ');
  const label = `${team} weekly rank history: ${history.map((p) => `${p.season} week ${p.week}, rank ${p.rank}`).join('; ')}`;
  return (
    <svg viewBox={`0 0 ${w} ${h}`} width={w} height={h} role="img" aria-label={label} className="text-accent-400 max-w-full">
      <line x1={padX} x2={w - padX} y1={y(1)} y2={y(1)} stroke="currentColor" strokeOpacity={0.25} strokeDasharray="2 3" />
      <line x1={padX} x2={w - padX} y1={y(teamCount)} y2={y(teamCount)} stroke="currentColor" strokeOpacity={0.25} strokeDasharray="2 3" />
      {history.length > 1 && <path d={d} fill="none" stroke="currentColor" strokeWidth={1.75} strokeLinejoin="round" />}
      {history.map((p, i) => (
        <circle key={`${p.season}-${p.week}`} cx={x(i)} cy={y(p.rank)} r={3} fill="currentColor" />
      ))}
    </svg>
  );
};
