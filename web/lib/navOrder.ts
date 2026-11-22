/**
 * One sidebar order shared by every sport (front-office #221).
 * This file is byte-identical across the four sport repos; do not add
 * sport-specific entries here.
 */
export const NAV_ORDER: readonly string[] = [
  'Season Standings',
  'Matchups',
  'Playoff Simulator',
  '2026 Bracket',
  'Postseason & Bullpen',
  'Team Ratings & EPA',
  'Payroll & Cap',
  'Coaching Staffs',
  'Offseason Moves',
  'Player Ratings & Projections',
  'Player DNA & Peer Comps',
  'True Clutch Index',
  'Defense',
  'Shot Charts',
  'Passing Charts',
  'Spatial Analytics',
  'Model Variants',
  'Diagnostics',
  'Retrospective',
  'Visual Gallery',
];

/** Pages that move to the top, in this order, while the league is in its offseason. */
export const OFFSEASON_FIRST: readonly string[] = ['Offseason Moves', 'Retrospective'];

export function orderNavItems<T extends { label: string }>(
  items: T[],
  seasonState: string | undefined,
): T[] {
  for (const item of items) {
    if (!NAV_ORDER.includes(item.label)) {
      throw new Error(`Nav label "${item.label}" is not in NAV_ORDER (web/lib/navOrder.ts)`);
    }
  }
  const offseason = seasonState === 'offseason';
  const rank = (label: string): number => {
    if (offseason) {
      const first = OFFSEASON_FIRST.indexOf(label);
      if (first !== -1) return first - OFFSEASON_FIRST.length;
    }
    return NAV_ORDER.indexOf(label);
  };
  return [...items].sort((a, b) => rank(a.label) - rank(b.label));
}
