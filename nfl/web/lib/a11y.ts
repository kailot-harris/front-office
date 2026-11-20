import type { KeyboardEvent } from 'react';

/** aria-sort value for a sortable column header. */
export function ariaSort(active: boolean, ascending: boolean): 'ascending' | 'descending' | 'none' {
  if (!active) return 'none';
  return ascending ? 'ascending' : 'descending';
}

/**
 * Keyboard activation for a clickable, focusable non-button element (a sortable
 * <th>): Enter and Space fire its click handler, as they would on a <button>.
 */
export function activateOnKey(e: KeyboardEvent<HTMLElement>): void {
  if (e.key === 'Enter' || e.key === ' ') {
    e.preventDefault();
    e.currentTarget.click();
  }
}

/**
 * Arrow-key movement for the ARIA tab pattern: put on a role="tablist" element
 * and Left/Right (or Up/Down), Home and End move focus between its tabs and
 * activate the one focused, so a segmented toggle reads and behaves as tabs.
 */
export function tablistKeys(e: KeyboardEvent<HTMLElement>): void {
  const keys = ['ArrowLeft', 'ArrowRight', 'ArrowUp', 'ArrowDown', 'Home', 'End'];
  if (!keys.includes(e.key)) return;
  const tabs = Array.from(e.currentTarget.querySelectorAll<HTMLElement>('[role="tab"]'));
  const current = tabs.indexOf(document.activeElement as HTMLElement);
  if (tabs.length === 0 || current === -1) return;
  e.preventDefault();
  let next = current;
  if (e.key === 'Home') next = 0;
  else if (e.key === 'End') next = tabs.length - 1;
  else if (e.key === 'ArrowLeft' || e.key === 'ArrowUp') next = (current - 1 + tabs.length) % tabs.length;
  else next = (current + 1) % tabs.length;
  tabs[next].focus();
  tabs[next].click();
}
