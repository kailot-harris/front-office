'use client';

// Sport switcher (front-office#212). This file is byte-identical in all four
// sport repos: keep it sport-agnostic and pass the sport in as a prop.
//
// A click keeps the visitor on the closest page in the target sport:
//   1. the same address, if the target sport has it;
//   2. else the page the shared related-pages table names (+ arrival note);
//   3. else the target's Season Standings ('/') (+ arrival note).
// The table is nav/switcher.json in the aggregator, served at
// <PAGES_BASE_PATH>/nav/switcher.json. If it cannot be loaded, pages every
// sport has keep their address and everything else goes to Season Standings.

import React, { useEffect, useState } from 'react';
import { usePathname } from 'next/navigation';
import { X } from 'lucide-react';

export type SportSlug = 'nfl' | 'nba' | 'wnba' | 'mlb';

export const SPORTS: readonly { slug: SportSlug; label: string }[] = [
  { slug: 'nfl', label: 'NFL' },
  { slug: 'nba', label: 'NBA' },
  { slug: 'wnba', label: 'WNBA' },
  { slug: 'mlb', label: 'MLB' },
];

export interface SwitcherTable {
  sports: Record<string, { label: string; pages: Record<string, string> }>;
  related: Record<string, Record<string, string>>;
}

/** Pages every sport has; used when the table cannot be loaded. */
export const COMMON_PATHS: readonly string[] = [
  '/', '/matchups', '/playoffs', '/players', '/player-dna', '/clutch',
  '/variants', '/diagnostics', '/gallery',
];

const repoBase = process.env.PAGES_BASE_PATH ?? '';
export const SWITCHER_TABLE_URL = `${repoBase}/nav/switcher.json`;

const normalize = (path: string | null | undefined) => {
  if (!path) return '/';
  const p = path.length > 1 && path.endsWith('/') ? path.slice(0, -1) : path;
  return p || '/';
};

export interface SwitchTarget {
  /** Path inside the target sport ('/' or '/shots'), no trailing slash. */
  path: string;
  /** Set when the visitor did not land on the same page: [from label, to label]. */
  note?: [string, string];
}

export function resolveSwitch(
  table: SwitcherTable | null,
  from: SportSlug,
  to: SportSlug,
  currentPath: string,
): SwitchTarget {
  const path = normalize(currentPath);
  if (!table) {
    return COMMON_PATHS.includes(path) ? { path } : { path: '/' };
  }
  const fromPages = table.sports[from]?.pages ?? {};
  const toPages = table.sports[to]?.pages ?? {};
  if (path in toPages) return { path };
  const fromLabel = fromPages[path];
  if (!fromLabel) return { path: '/' };
  const wantLabel = table.related[fromLabel]?.[to] ?? 'Season Standings';
  const hit = Object.entries(toPages).find(([, label]) => label === wantLabel);
  const [toPath, toLabel] = hit ?? ['/', 'Season Standings'];
  return { path: toPath, note: [fromLabel, toLabel] };
}

export function switchHref(to: SportSlug, target: SwitchTarget): string {
  const base = `${repoBase}/${to}${target.path === '/' ? '/' : `${target.path}/`}`;
  if (!target.note) return base;
  const q = new URLSearchParams({ from: target.note[0], to: target.note[1] });
  return `${base}?${q.toString()}`;
}

export const SportSwitcher: React.FC<{ current: SportSlug }> = ({ current }) => {
  const pathname = usePathname();
  const [table, setTable] = useState<SwitcherTable | null>(null);

  useEffect(() => {
    let live = true;
    fetch(SWITCHER_TABLE_URL)
      .then((r) => (r.ok ? r.json() : null))
      .then((t) => { if (live && t?.sports && t?.related) setTable(t); })
      .catch(() => {});
    return () => { live = false; };
  }, []);

  return (
    <nav aria-label="Switch sport" className="px-2 pb-3 border-b border-slate-800/80">
      <ul className="grid grid-cols-4 gap-1 rounded-lg border border-slate-800 p-1">
        {SPORTS.map(({ slug, label }) => {
          const isCurrent = slug === current;
          const href = isCurrent
            ? undefined
            : switchHref(slug, resolveSwitch(table, current, slug, pathname));
          return (
            <li key={slug}>
              <a
                href={href ?? `${repoBase}/${slug}/`}
                aria-current={isCurrent ? 'page' : undefined}
                data-sport={slug}
                className={`flex items-center justify-center gap-1 rounded-md px-1 py-1.5 text-xs font-semibold transition-colors ${
                  isCurrent ? '' : 'text-slate-300 hover:bg-slate-800/60 hover:text-white'
                }`}
                style={
                  isCurrent
                    ? { backgroundColor: `var(--fo-${slug}-accent)`, color: 'var(--fo-on-accent)' }
                    : undefined
                }
              >
                {!isCurrent && (
                  <span
                    aria-hidden="true"
                    className="h-1.5 w-1.5 rounded-full"
                    style={{ backgroundColor: `var(--fo-${slug}-accent)` }}
                  />
                )}
                {label}
              </a>
            </li>
          );
        })}
      </ul>
    </nav>
  );
};

/** One-time note after a switch that could not keep the same page. */
export const SwitchArrivalNote: React.FC<{ current: SportSlug }> = ({ current }) => {
  const [note, setNote] = useState<[string, string] | null>(null);

  useEffect(() => {
    const url = new URL(window.location.href);
    const from = url.searchParams.get('from');
    const to = url.searchParams.get('to');
    if (!from || !to) return;
    setNote([from, to]);
    url.searchParams.delete('from');
    url.searchParams.delete('to');
    window.history.replaceState(window.history.state, '', url.pathname + url.search + url.hash);
  }, []);

  if (!note) return null;
  const sport = SPORTS.find((s) => s.slug === current)?.label ?? current.toUpperCase();
  return (
    <div
      role="status"
      className="mx-4 mt-3 flex items-center justify-between gap-3 rounded-lg border border-slate-700 bg-surface-raised px-3 py-2 text-sm text-slate-200"
    >
      <span>
        No {note[0]} in {sport} — showing {note[1]}.
      </span>
      <button
        type="button"
        onClick={() => setNote(null)}
        aria-label="Dismiss"
        className="rounded p-1 text-slate-400 hover:text-white"
      >
        <X className="h-4 w-4" aria-hidden="true" />
      </button>
    </div>
  );
};
