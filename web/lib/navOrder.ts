/**
 * Shared sidebar order for every Front Office sport board (front-office #221).
 * This file is byte-identical across the NFL, NBA, WNBA and MLB repos.
 * Labels a sport does not have are simply absent from its sidebar.
 */
export const NAV_ORDER: readonly string[] = [
  'Season Standings',
  'Matchups',
  'Momentum Board',
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

/** Pages pinned to the top, in this order, while season_state is 'offseason'. */
export const OFFSEASON_FIRST: readonly string[] = ['Offseason Moves', 'Retrospective'];

/**
 * Sort nav items by NAV_ORDER. In the offseason, OFFSEASON_FIRST items lead.
 * Throws on a label missing from NAV_ORDER so the build and tests catch it.
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
    const pinned = offseason ? OFFSEASON_FIRST.indexOf(label) : -1;
    return pinned >= 0 ? pinned - OFFSEASON_FIRST.length : NAV_ORDER.indexOf(label);
  };
  return [...items].sort((a, b) => rank(a.label) - rank(b.label));
}
