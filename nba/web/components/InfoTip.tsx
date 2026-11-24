'use client';

import React, { useEffect, useId, useRef, useState } from 'react';
import { Info } from 'lucide-react';

interface InfoTipProps {
  /** Name of the thing being explained; becomes the button's accessible name. */
  label: string;
  children: React.ReactNode;
  /** Which edge of the button the tooltip lines up with (use "right" near the right edge). */
  align?: 'left' | 'right';
}

/**
 * An (i) button with a tooltip. Opens on hover, keyboard focus or click/tap, and
 * closes on Escape, blur or an outside click, so it works without a mouse and on
 * touch screens. The tooltip is linked to the button with aria-describedby.
 */
export const InfoTip: React.FC<InfoTipProps> = ({ label, children, align = 'left' }) => {
  const id = useId();
  const [hover, setHover] = useState(false);
  const [focus, setFocus] = useState(false);
  const [pinned, setPinned] = useState(false);
  const ref = useRef<HTMLSpanElement>(null);
  const open = hover || focus || pinned;

  useEffect(() => {
    if (!open) return;
    const onKey = (e: KeyboardEvent) => {
      if (e.key === 'Escape') {
        setHover(false);
        setFocus(false);
        setPinned(false);
      }
    };
    const onClick = (e: MouseEvent) => {
      if (ref.current && !ref.current.contains(e.target as Node)) setPinned(false);
    };
    document.addEventListener('keydown', onKey);
    document.addEventListener('click', onClick);
    return () => {
      document.removeEventListener('keydown', onKey);
      document.removeEventListener('click', onClick);
    };
  }, [open]);

  return (
    <span
      ref={ref}
      className="relative inline-flex items-center normal-case font-normal"
      onMouseEnter={() => setHover(true)}
      onMouseLeave={() => setHover(false)}
    >
      <button
        type="button"
        aria-label={`About ${label}`}
        aria-describedby={open ? id : undefined}
        onFocus={() => setFocus(true)}
        onBlur={() => setFocus(false)}
        onClick={(e) => {
          e.stopPropagation();
          setPinned((v) => !v);
        }}
        className="min-w-6 min-h-6 inline-flex items-center justify-center rounded text-slate-400 hover:text-accent-400 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-1 focus-visible:outline-accent"
      >
        <Info className="w-3.5 h-3.5" aria-hidden="true" />
      </button>
      {open && (
        <span
          role="tooltip"
          id={id}
          className={`absolute z-50 top-full mt-1 w-64 max-w-[80vw] p-3 rounded-lg bg-surface-raised border border-slate-700 shadow-xl text-xs text-left text-slate-200 leading-relaxed whitespace-normal ${
            align === 'right' ? 'right-0' : 'left-0'
          }`}
        >
          {children}
        </span>
      )}
    </span>
  );
};
