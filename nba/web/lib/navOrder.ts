/**
 * Shared sidebar order and group structure for every Front Office sport board
 * (front-office #221, #230).
 * This file is byte-identical across the NFL, NBA, WNBA and MLB repos.
 * Labels or groups a sport does not have are simply absent from its sidebar.
 */

export type NavGroupId =
  | 'season-games'
  | 'player'
  | 'front-office'
  | 'visualizations'
  | 'models';

export interface NavGroupDef {
  readonly id: NavGroupId;
  readonly label: string;
  readonly labels: readonly string[];
}

export interface NavGroupResult<T> {
  id: NavGroupId;
  label: string;
  defaultOpen: boolean;
  items: T[];
}

export const NAV_GROUPS: readonly NavGroupDef[] = [
  {
    id: 'season-games',
    label: 'Season & Games',
    labels: [
      'Season Standings',
      'Matchups',
      'Momentum Board',
      'Playoff Simulator',
      '2026 Bracket',
      'Postseason & Bullpen',
      'Team Ratings & EPA',
    ],
  },
  {
    id: 'player',
    label: 'Player',
    labels: [
      'Player Ratings & Projections',
      'Player DNA & Peer Comps',
      'True Clutch Index',
      'Defense',
    ],
  },
  {
    id: 'front-office',
    label: 'Front Office',
    labels: [
      'Payroll & Cap',
      'Coaching Staffs',
      'Offseason Moves',
    ],
  },
  {
    id: 'visualizations',
    label: 'Visualizations',
    labels: [
      'Shot Charts',
      'Passing Charts',
      'Spatial Analytics',
      'Visual Gallery',
    ],
  },
  {
    id: 'models',
    label: 'Models',
    labels: [
      'Model Variants',
      'Diagnostics',
      'Retrospective',
    ],
  },
];

/**
 * Validate that every label in groups belongs to exactly one group.
 * Throws an Error on duplicate labels.
 */
export function validateNavGroups(groups: readonly NavGroupDef[]): Map<string, NavGroupId> {
  const seen = new Map<string, NavGroupId>();
  for (const group of groups) {
    for (const label of group.labels) {
      const existing = seen.get(label);
      if (existing !== undefined) {
        throw new Error(
          `NAV_GROUPS: duplicate nav label "${label}" in "${existing}" and "${group.id}"`,
        );
      }
      seen.set(label, group.id);
    }
  }
  return seen;
}

// Validate at module load so invalid group definitions fail immediately.
validateNavGroups(NAV_GROUPS);

/** Flat ordered list of all known nav labels, derived from NAV_GROUPS. */
export const NAV_ORDER: readonly string[] = NAV_GROUPS.flatMap((g) => g.labels);

/**
 * Group nav items into the 5 shared collapsible sections.
 * - Validates NAV_GROUPS uniqueness and throws if any item's label is missing from NAV_GROUPS.
 * - Preserves each group's canonical label order.
 * - In offseason (`seasonState === 'offseason'`), 'Front Office' moves to the top with `defaultOpen: true`.
 * - Omits groups with zero items.
 */
export function groupNavItems<T extends { label: string }>(
  items: readonly T[],
  seasonState: string | undefined,
): NavGroupResult<T>[] {
  const labelToGroup = validateNavGroups(NAV_GROUPS);
  const buckets = new Map<NavGroupId, T[]>();

  for (const item of items) {
    const groupId = labelToGroup.get(item.label);
    if (!groupId) {
      throw new Error(`groupNavItems: nav label "${item.label}" is not in NAV_GROUPS`);
    }
    const list = buckets.get(groupId);
    if (list) {
      list.push(item);
    } else {
      buckets.set(groupId, [item]);
    }
  }

  const offseason = seasonState === 'offseason';
  const orderedGroups = offseason
    ? [
        ...NAV_GROUPS.filter((g) => g.id === 'front-office'),
        ...NAV_GROUPS.filter((g) => g.id !== 'front-office'),
      ]
    : NAV_GROUPS;

  const result: NavGroupResult<T>[] = [];
  for (const group of orderedGroups) {
    const groupItems = buckets.get(group.id);
    if (!groupItems || groupItems.length === 0) continue;
    const sorted = [...groupItems].sort(
      (a, b) => group.labels.indexOf(a.label) - group.labels.indexOf(b.label),
    );
    result.push({
      id: group.id,
      label: group.label,
      defaultOpen: offseason && group.id === 'front-office',
      items: sorted,
    });
  }
  return result;
}

/**
 * Sort nav items by group and canonical order.
 * In the offseason, Front Office items lead; tabs never leave their group.
 * Throws on a label missing from NAV_GROUPS.
 */
export function orderNavItems<T extends { label: string }>(
  items: readonly T[],
  seasonState: string | undefined,
): T[] {
  return groupNavItems(items, seasonState).flatMap((g) => g.items);
}
