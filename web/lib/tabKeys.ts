import type { KeyboardEvent } from 'react';

/**
 * Keyboard support for the ARIA tab pattern (kailot-harris/MLB-Analytics#130).
 * Put on the role="tablist" element: Left/Right (and Up/Down) move to the
 * previous/next tab, Home/End to the first/last, and each move selects the tab.
 */
export function onTabListKeyDown(e: KeyboardEvent<HTMLElement>) {
  const keys = ['ArrowLeft', 'ArrowRight', 'ArrowUp', 'ArrowDown', 'Home', 'End'];
  if (!keys.includes(e.key)) return;
  const tabs = Array.from(e.currentTarget.querySelectorAll<HTMLElement>('[role="tab"]:not([disabled])'));
  const i = tabs.indexOf(document.activeElement as HTMLElement);
  if (i < 0 || tabs.length === 0) return;
  e.preventDefault();
  let next = i;
  if (e.key === 'Home') next = 0;
  else if (e.key === 'End') next = tabs.length - 1;
  else if (e.key === 'ArrowLeft' || e.key === 'ArrowUp') next = (i - 1 + tabs.length) % tabs.length;
  else next = (i + 1) % tabs.length;
  tabs[next].focus();
  tabs[next].click();
}
