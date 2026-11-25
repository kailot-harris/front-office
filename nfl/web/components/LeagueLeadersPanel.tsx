'use client';

/**
 * League leaders panel at the top of /players (NFL_analytics#230).
 *
 * Cards grouped as passing, rushing, receiving, defense and impact. Each card
 * shows the top 3 and expands to the top 10, with its own through date. Every
 * number comes from player_leaders.json; nothing is computed or filled in here.
 */
import React, { useState } from 'react';
import type { LeaderCard, LeaderFormat, LeaderRow, PlayerLeadersPayload } from '@/lib/playerLeadersTypes';

const COLLAPSED = 3;
const EXPANDED = 10;
export const NOT_ENOUGH_GAMES = 'Not enough games yet';

export function formatLeaderValue(value: number, format: LeaderFormat): string {
  if (!Number.isFinite(value)) return '—';
  switch (format) {
    case 'pct':
      return `${(value * 100).toFixed(1)}%`;
    case 'cpoe':
      return `${value > 0 ? '+' : ''}${value.toFixed(1)}`;
    case 'epa_play':
      return `${value > 0 ? '+' : ''}${value.toFixed(2)}`;
    case 'epa_total':
      return `${value > 0 ? '+' : ''}${value.toFixed(1)}`;
    case 'yards_play':
      return value.toFixed(2);
    case 'count':
      return Number.isInteger(value) ? String(value) : value.toFixed(1);
    default:
      return value.toFixed(1);
  }
}

function formatNumber(n: number): string {
  return n.toLocaleString('en-US', { maximumFractionDigits: 1 });
}

function rowTitle(r: LeaderRow, card: LeaderCard): string | undefined {
  if (r.sample == null || r.required == null) return undefined;
  return `${formatNumber(r.sample)} ${card.unit_label} (needed ${formatNumber(r.required)} after ${r.team_games_played} team games)`;
}

function LeaderCardView({ card }: { card: LeaderCard }) {
  const [expanded, setExpanded] = useState(false);
  const rows = card.leaders.slice(0, EXPANDED);
  const shown = expanded ? rows : rows.slice(0, COLLAPSED);
  const empty = rows.length === 0;
  const listId = `leaders-${card.key}-list`;
  const emptyText = card.status === 'unavailable' ? (card.status_text ?? 'Data not available') : NOT_ENOUGH_GAMES;

  return (
    <section
      data-testid={`leader-card-${card.key}`}
      data-status={card.status}
      className="bg-surface-raised/60 border border-slate-800 rounded-xl p-4 flex flex-col gap-2"
      aria-labelledby={`leaders-${card.key}-title`}
    >
      <header className="flex items-start justify-between gap-2">
        <h3 id={`leaders-${card.key}-title`} className="text-sm font-semibold text-white">
          {card.label}
          {card.lower_is_better && <span className="ml-1 text-[11px] font-normal text-slate-400">(lowest leads)</span>}
        </h3>
        <span data-testid="leader-through" className="shrink-0 text-[11px] font-mono text-slate-400">
          {card.through_date ? `Through ${card.through_date}` : 'No through date'}
        </span>
      </header>

      {card.noise_note && card.noise_note_text && (
        <p data-testid="leader-noise-note" className="text-[11px] text-amber-300/90">
          {card.noise_note_text}
        </p>
      )}

      {empty ? (
        <div data-testid="leader-empty" className="text-sm text-slate-300 py-2">
          <p className="font-semibold">{emptyText}</p>
          {card.null_reason && <p className="text-[11px] text-slate-400 mt-1">{card.null_reason}</p>}
        </div>
      ) : (
        <>
          <ol id={listId} className="text-sm divide-y divide-slate-800/70">
            {shown.map((r) => (
              <li
                key={r.player_id}
                data-testid="leader-row"
                className="flex items-center gap-2 py-1"
                title={rowTitle(r, card)}
              >
                <span className="w-6 text-right tabular-nums text-slate-400">{r.rank}</span>
                <span className="flex-1 truncate text-slate-100">
                  {r.player}
                  <span className="ml-1 text-[11px] text-slate-400">
                    {r.team}
                    {r.position ? ` · ${r.position}` : ''}
                  </span>
                </span>
                <span className="tabular-nums font-semibold text-emerald-300">
                  {formatLeaderValue(r.value, card.format)}
                </span>
              </li>
            ))}
          </ol>
          {rows.length > COLLAPSED && (
            <button
              type="button"
              aria-expanded={expanded}
              aria-controls={listId}
              onClick={() => setExpanded((v) => !v)}
              className="self-start text-xs font-semibold text-emerald-400 hover:text-emerald-300"
            >
              {expanded ? 'Show top 3' : `Show top ${rows.length}`}
            </button>
          )}
        </>
      )}
      <p className="text-[11px] text-slate-500 mt-auto">
        {card.minimum_full_season == null
          ? 'Season total, no minimum'
          : `Minimum: ${formatNumber(card.minimum_full_season)} ${card.unit_label} over 17 games, scaled to team games played`}
      </p>
    </section>
  );
}

export function LeagueLeadersPanel({ data }: { data: PlayerLeadersPayload | null }) {
  if (!data) {
    return (
      <section data-testid="league-leaders" className="mb-8 text-sm text-slate-400">
        League leaders are unavailable right now.
      </section>
    );
  }

  const m = data.methods;
  return (
    <section data-testid="league-leaders" aria-labelledby="league-leaders-title" className="mb-10 space-y-4">
      <div>
        <h2 id="league-leaders-title" className="text-xl font-bold text-white">
          League Leaders <span className="text-sm font-semibold text-slate-400">{data.season} regular season</span>
        </h2>
        <p className="text-xs text-slate-400">
          Qualified players only. Each rate card&rsquo;s minimum scales with team games played.
        </p>
      </div>

      {data.groups.map((g) => {
        const cards = data.cards.filter((c) => c.group === g.key);
        if (!cards.length) return null;
        return (
          <div key={g.key} data-testid={`leader-group-${g.key}`} role="group" aria-label={g.label} className="space-y-2">
            <p className="text-xs font-bold uppercase tracking-wider text-slate-400">{g.label}</p>
            <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4 gap-3">
              {cards.map((c) => (
                <LeaderCardView key={c.key} card={c} />
              ))}
            </div>
          </div>
        );
      })}

      <details
        data-testid="leader-methods"
        className="text-xs text-slate-300 bg-surface-raised/40 border border-slate-800 rounded-xl p-4"
      >
        <summary className="cursor-pointer font-semibold text-slate-200">How leaders qualify</summary>
        <div className="mt-3 space-y-2">
          <p>{m.scaling_text}</p>
          <p>
            Rule: <code>{m.scaling_rule}</code>
          </p>
          <p>{m.traded_players}</p>
          <p>{m.ranking}</p>
          <p>{m.impact_note}</p>
          <p>{m.noise_note}</p>
          <p>{m.definitions}</p>
          <p>{m.sample}</p>
          <p>{m.refresh}</p>
          {/* A list, not a <table>: the QB table below is the page's first table. */}
          <p className="font-semibold text-slate-200">Full-season (17-game) minimum per stat</p>
          <ul data-testid="leader-minimums" className="max-w-xl divide-y divide-slate-800/70">
            {m.minimums.map((row) => (
              <li key={row.key} className="flex justify-between gap-3 py-1">
                <span>{row.label}</span>
                <span className="tabular-nums">
                  {row.minimum_full_season == null
                    ? 'None (season total)'
                    : `${formatNumber(row.minimum_full_season)} ${row.unit_label}`}
                </span>
              </li>
            ))}
          </ul>
          <p>{m.not_available}</p>
          <p>{m.nulls}</p>
          <p className="text-slate-500">
            Minimums set by the owner from the leader reliability study, source commit{' '}
            <code>{m.study_source_commit.slice(0, 12)}</code>.
          </p>
        </div>
      </details>
    </section>
  );
}
