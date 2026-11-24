import React from 'react';
import type { MomentumVerdict } from '@/lib/momentumMethodologyTypes';

/** Fixed decimals with an explicit sign, e.g. +0.00367. Display formatting only. */
export const fmtSigned = (v: number, digits = 5): string => {
  const s = v.toFixed(digits);
  return v > 0 ? `+${s}` : s;
};

export const fmtInterval = (lo: number, hi: number, digits = 5): string =>
  `[${fmtSigned(lo, digits)}, ${fmtSigned(hi, digits)}]`;

export const pct = (v: number): string => `${Math.round(v * 100)}%`;

/** Where an interval sits against zero, in plain words. */
export const intervalWord = (lo: number, hi: number): 'above zero' | 'below zero' | 'includes zero' =>
  lo > 0 ? 'above zero' : hi < 0 ? 'below zero' : 'includes zero';

/** Shared horizontal scale for interval bars; always includes zero. */
export function intervalDomain(values: { lo: number; hi: number }[]): [number, number] {
  let lo = 0;
  let hi = 0;
  for (const v of values) {
    if (v.lo < lo) lo = v.lo;
    if (v.hi > hi) hi = v.hi;
  }
  if (lo === hi) return [-1, 1];
  const pad = (hi - lo) * 0.04;
  return [lo - pad, hi + pad];
}

interface IntervalBarProps {
  lo: number;
  hi: number;
  point: number;
  domain: [number, number];
  width?: number;
}

/**
 * A 95% interval drawn against a zero line. Decorative: the numbers are always
 * printed beside it, so it is hidden from assistive technology.
 */
export const IntervalBar: React.FC<IntervalBarProps> = ({ lo, hi, point, domain, width = 120 }) => {
  const h = 14;
  const x = (v: number) => ((v - domain[0]) / (domain[1] - domain[0])) * (width - 4) + 2;
  const tone = lo > 0 ? 'stroke-emerald-400 fill-emerald-400' : hi < 0 ? 'stroke-rose-400 fill-rose-400' : 'stroke-slate-300 fill-slate-300';
  return (
    <svg width={width} height={h} viewBox={`0 0 ${width} ${h}`} aria-hidden="true" focusable="false" className="block">
      <line x1={x(0)} x2={x(0)} y1={1} y2={h - 1} className="stroke-slate-600" strokeWidth={1} strokeDasharray="2 2" />
      <line x1={x(lo)} x2={x(hi)} y1={h / 2} y2={h / 2} className={tone} strokeWidth={2} />
      <line x1={x(lo)} x2={x(lo)} y1={h / 2 - 3} y2={h / 2 + 3} className={tone} strokeWidth={1.5} />
      <line x1={x(hi)} x2={x(hi)} y1={h / 2 - 3} y2={h / 2 + 3} className={tone} strokeWidth={1.5} />
      <circle cx={x(point)} cy={h / 2} r={2.5} className={tone} />
    </svg>
  );
};

const VERDICT_STYLE: Record<MomentumVerdict, string> = {
  kept: 'bg-emerald-500/10 text-emerald-300 border-emerald-500/30',
  inconclusive: 'bg-amber-500/10 text-amber-300 border-amber-500/30',
  discarded: 'bg-slate-500/10 text-slate-300 border-slate-500/30',
};

export const VerdictBadge: React.FC<{ verdict: MomentumVerdict }> = ({ verdict }) => (
  <span className={`inline-block rounded-full border px-2 py-0.5 text-[11px] font-semibold ${VERDICT_STYLE[verdict]}`}>
    {verdict}
  </span>
);
