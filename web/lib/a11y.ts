import type { KeyboardEvent } from 'react';

/**
 * Props for a sortable table header cell (WNBA#230): `aria-sort` reflects the
 * current order, and the header is focusable and sorts on Enter or Space as
 * well as on click.
 */
export function sortableTh(
  active: boolean,
  ascending: boolean,
  onSort: () => void,
): {
  'aria-sort': 'ascending' | 'descending' | 'none';
  tabIndex: 0;
  onClick: () => void;
  onKeyDown: (e: KeyboardEvent) => void;
} {
  return {
    'aria-sort': active ? (ascending ? 'ascending' : 'descending') : 'none',
    tabIndex: 0,
    onClick: onSort,
    onKeyDown: (e) => {
      if (e.key === 'Enter' || e.key === ' ') {
        e.preventDefault();
        onSort();
      }
    },
  };
}
