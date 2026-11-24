import React from 'react';

/** One decimal place with an explicit sign, e.g. +2.5 or -0.4. Display formatting only. */
export const signed = (v: number, digits = 1): string => {
  const s = v.toFixed(digits);
  return v > 0 ? `+${s}` : s;
};

interface SparklineProps {
  points: { date: string; net_rating: number }[];
  /** Team name for the accessible label. */
  team: string;
}

/**
 * Net rating by game, hand-drawn SVG (the site has no charting dependency).
 * The vertical scale is fitted to the team's own points, so only the shape is
 * comparable across rows; the label states the first and last published values.
 */
export const Sparkline: React.FC<SparklineProps> = ({ points, team }) => {
  const w = 96;
  const h = 28;
  const pad = 3;
  const first = points[0];
  const last = points[points.length - 1];
  const label = `${team} net rating by game: ${
    points.length === 1
      ? `one game, ${first.net_rating}`
      : `${points.length} games, from ${first.net_rating} to ${last.net_rating}`
  }`;
  const ys = points.map((p) => p.net_rating);
  const min = Math.min(...ys);
  const max = Math.max(...ys);
  const span = max - min || 1;
  const x = (i: number) => (points.length === 1 ? w / 2 : pad + (i * (w - 2 * pad)) / (points.length - 1));
  const y = (v: number) => (max === min ? h / 2 : h - pad - ((v - min) / span) * (h - 2 * pad));
  const d = points.map((p, i) => `${i === 0 ? 'M' : 'L'}${x(i).toFixed(1)} ${y(p.net_rating).toFixed(1)}`).join(' ');
  return (
    <svg
      viewBox={`0 0 ${w} ${h}`}
      width={w}
      height={h}
      role="img"
      aria-label={label}
      className="text-accent-400 inline-block align-middle"
    >
      {points.length > 1 && (
        <path d={d} fill="none" stroke="currentColor" strokeWidth={1.5} strokeLinejoin="round" strokeLinecap="round" />
      )}
      <circle cx={x(points.length - 1)} cy={y(last.net_rating)} r={2.2} fill="currentColor" />
    </svg>
  );
};

export interface DriverItem {
  key: string;
  label: string;
  value: number;
}

/**
 * Diverging bars around zero, one per driver. Bar length is the published value
 * divided by the largest absolute value in this team's list (a display scale);
 * the number beside each bar is the published value itself.
 */
export const DriverBars: React.FC<{ items: DriverItem[] }> = ({ items }) => {
  const maxAbs = Math.max(...items.map((i) => Math.abs(i.value)), 0);
  return (
    <ul className="space-y-1.5">
      {items.map((item) => {
        const pct = maxAbs === 0 ? 0 : (Math.abs(item.value) / maxAbs) * 50;
        return (
          <li key={item.key} className="grid grid-cols-[minmax(0,11rem)_1fr_3.5rem] items-center gap-2 text-xs">
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
            <span className="font-mono tabular-nums text-right text-slate-200">{signed(item.value, 2)}</span>
          </li>
        );
      })}
    </ul>
  );
};

interface RankHistoryProps {
  history: { week_start: string; as_of: string; rank: number; combined_score: number }[];
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
  const label = `${team} weekly rank history: ${history
    .map((p) => `week of ${p.week_start}, rank ${p.rank}`)
    .join('; ')}`;
  return (
    <svg
      viewBox={`0 0 ${w} ${h}`}
      width={w}
      height={h}
      role="img"
      aria-label={label}
      className="text-accent-400 max-w-full"
    >
      <line x1={padX} x2={w - padX} y1={y(1)} y2={y(1)} stroke="currentColor" strokeOpacity={0.25} strokeDasharray="2 3" />
      <line x1={padX} x2={w - padX} y1={y(teamCount)} y2={y(teamCount)} stroke="currentColor" strokeOpacity={0.25} strokeDasharray="2 3" />
      {history.length > 1 && (
        <path d={d} fill="none" stroke="currentColor" strokeWidth={1.75} strokeLinejoin="round" />
      )}
      {history.map((p, i) => (
        <circle key={p.week_start} cx={x(i)} cy={y(p.rank)} r={3} fill="currentColor" />
      ))}
    </svg>
  );
};
