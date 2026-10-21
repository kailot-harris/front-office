import React from 'react';
import { CalendarRange } from 'lucide-react';
import { formatSeasonLabel, SeasonKind } from '@/lib/season';

/**
 * Marks a figure with the NBA season its underlying data describes.
 *
 * The site projects 2026-2027, but several inputs are still the last completed
 * season (2025-2026) because a full 2026-2027 sample does not exist yet. This
 * badge makes that explicit instead of leaving the reader to assume every
 * number on the page describes the projected season.
 *
 * Renders nothing when `season` is absent: an artifact with no season stamp
 * should show no label rather than a guessed one.
 */
export interface SeasonSourceBadgeProps {
  /** Display span, e.g. '2025-2026', '2026-2027', or 2026 (hoopR end year). */
  season?: string | number | null;
  /** Leading words before the span. Defaults to a kind-aware label. */
  label?: string;
  /** What the span represents. Defaults to 'observed'. */
  kind?: SeasonKind;
  className?: string;
  title?: string;
}

const KIND_LABEL: Record<SeasonKind, string> = {
  projection: 'Projected season',
  observed: 'Observed',
  fallback: 'Fallback season',
  backtest: 'Backtest',
  mixed: 'Inputs observed',
};

const KIND_TITLE: Record<SeasonKind, string> = {
  projection: 'Projected season',
  observed: 'Computed from observed data',
  fallback: 'Fallback: the projected season does not have a usable sample yet',
  backtest: 'Historical backtest',
  mixed: 'Inputs pooled across observed seasons',
};

const KIND_STYLE: Record<SeasonKind, string> = {
  projection:
    'bg-indigo-500/10 text-indigo-300 border-indigo-500/25',
  observed: 'bg-amber-500/10 text-amber-300 border-amber-500/25',
  fallback: 'bg-orange-500/10 text-orange-300 border-orange-500/25',
  backtest: 'bg-emerald-500/10 text-emerald-300 border-emerald-500/25',
  mixed: 'bg-violet-500/10 text-violet-300 border-violet-500/25',
};

export const SeasonSourceBadge: React.FC<SeasonSourceBadgeProps> = ({
  season,
  label,
  kind = 'observed',
  className = '',
  title,
}) => {
  const formatted = formatSeasonLabel(season);
  if (!formatted) return null;

  return (
    <span
      title={title ?? `${KIND_TITLE[kind]} ${formatted}`}
      className={`inline-flex items-center gap-1 px-2 py-0.5 rounded-full text-[11px] font-semibold
        border whitespace-nowrap ${KIND_STYLE[kind]} ${className}`}
    >
      <CalendarRange className="w-3 h-3 flex-shrink-0" aria-hidden="true" />
      <span>
        {label ?? KIND_LABEL[kind]} {formatted}
      </span>
    </span>
  );
};
