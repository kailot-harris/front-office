/**
 * Shared sidebar order (front-office #221). This file is byte-identical in
 * every sport repo: do not add sport-specific labels or logic here.
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

/** Labels that move to the top, in this order, while the league is in its offseason. */
export const OFFSEASON_FIRST: readonly string[] = ['Offseason Moves', 'Retrospective'];

/**
 * Sort nav items by NAV_ORDER. When seasonState is 'offseason', the items in
 * OFFSEASON_FIRST come first in that list's order. Throws on any label that is
 * not in NAV_ORDER so a missing entry fails the build and tests.
 */
export function orderNavItems<T extends { label: string }>(
  items: T[],
  seasonState: string | undefined,
): T[] {
  for (const item of items) {
    if (!NAV_ORDER.includes(item.label)) {
      throw new Error(`orderNavItems: nav label "${item.label}" is not in NAV_ORDER`);
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
