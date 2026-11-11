'use client';

import { useCallback, useEffect, useRef, useState } from 'react';

/**
 * Tracks horizontal scroll position of a wide, horizontally-scrollable table
 * container so the UI can show a "more columns exist" affordance (e.g. a
 * right-edge fade) that disappears once the user has scrolled to the end.
 */
export function useTableScrollHint<T extends HTMLElement = HTMLDivElement>() {
  const scrollRef = useRef<T>(null);
  const [showScrollHint, setShowScrollHint] = useState(false);

  const recompute = useCallback(() => {
    const el = scrollRef.current;
    if (!el) return;
    const atEnd = el.scrollLeft + el.clientWidth >= el.scrollWidth - 2;
    const scrollable = el.scrollWidth > el.clientWidth + 2;
    setShowScrollHint(scrollable && !atEnd);
  }, []);

  useEffect(() => {
    recompute();
    const el = scrollRef.current;
    if (!el) return;
    const resizeObserver = new ResizeObserver(recompute);
    resizeObserver.observe(el);
    window.addEventListener('resize', recompute);
    return () => {
      resizeObserver.disconnect();
      window.removeEventListener('resize', recompute);
    };
  }, [recompute]);

  return { scrollRef, showScrollHint, onScroll: recompute };
}
