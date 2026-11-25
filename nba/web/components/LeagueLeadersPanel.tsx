'use client';

/**
 * League leaders panel at the top of /players (NBA_analytics#254).
 *
 * Cards grouped as scoring, shooting, playmaking, rebounding, defense and impact.
 * Each card shows the top 3 and expands to the top 10; one position filter
 * (All, Guards, Forwards, Centers) applies to every card. Every number comes
 * from player_leaders.json; nothing is computed or filled in here.
 */
import React, { useState } from 'react';
import Link from 'next/link';
import type {
  LeaderCard,
  LeaderFormat,
  LeaderPositionKey,
  PlayerLeadersPayload,
} from '@/lib/playerLeadersTypes';

const COLLAPSED = 3;

export function formatLeaderValue(value: number, format: LeaderFormat): string {
  if (!Number.isFinite(value)) return '—';
  switch (format) {
    case 'pct':
      return `${(value * 100).toFixed(1)}%`;
    case 'rate':
      return `${value.toFixed(1)}%`;
    case 'rapm':
      return `${value > 0 ? '+' : ''}${value.toFixed(2)}`;
    default:
      return value.toFixed(1);
  }
}

function formatSample(n: number): string {
  return Number.isInteger(n) ? n.toLocaleString('en-US') : n.toLocaleString('en-US', { maximumFractionDigits: 1 });
}

function LeaderCardView({ card, position }: { card: LeaderCard; position: LeaderPositionKey }) {
  const [expanded, setExpanded] = useState(false);
  const rows = card.leaders[position] ?? [];
  const shown = expanded ? rows : rows.slice(0, COLLAPSED);
  const empty = rows.length === 0;
  const listId = `leaders-${card.key}-list`;

  return (
    <section
      data-testid={`leader-card-${card.key}`}
      data-status={card.status}
      className="bg-surface-raised/60 border border-slate-800 rounded-xl p-4 flex flex-col gap-2"
      aria-labelledby={`leaders-${card.key}-title`}
    >
      <header className="flex items-start justify-between gap-2">
        <h4 id={`leaders-${card.key}-title`} className="text-sm font-bold text-white">
          {card.label}
          {card.lower_is_better && (
            <span className="ml-1 text-[11px] font-normal text-slate-400">(lowest leads)</span>
          )}
        </h4>
        <span data-testid="leader-through" className="shrink-0 text-[11px] text-slate-400">
          {card.through_date ? `Through ${card.through_date}` : 'Through date unavailable'}
        </span>
      </header>

      {card.noise_note && card.noise_note_text && (
        <p data-testid="leader-noise-note" className="text-[11px] text-amber-300/90">
          {card.noise_note_text}
        </p>
      )}

      {empty ? (
        <div data-testid="leader-empty" className="text-sm text-slate-300 py-2">
          <p className="font-semibold">Not enough games yet</p>
          {card.status !== 'ok' && card.null_reason && (
            <p className="text-[11px] text-slate-400 mt-1">{card.null_reason}</p>
          )}
        </div>
      ) : (
        <>
          <ol id={listId} className="text-sm divide-y divide-slate-800/70">
            {shown.map((r) => (
              <li
                key={r.player_id}
                data-testid="leader-row"
                className="flex items-center gap-2 py-1"
                title={`${formatSample(r.sample)} ${card.unit_label} (needed ${formatSample(r.required)})`}
              >
                <span className="w-6 text-right tabular-nums text-slate-400">{r.rank}</span>
                <span className="flex-1 truncate text-slate-100">
                  {r.player}
                  <span className="ml-1 text-[11px] text-slate-400">
                    {r.team}
                    {r.position ? ` · ${r.position}` : ''}
                  </span>
                </span>
                <span className="tabular-nums font-semibold text-orange-300">
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
              className="self-start text-xs font-semibold text-orange-400 hover:text-orange-300"
            >
              {expanded ? 'Show top 3' : `Show top ${Math.min(rows.length, 10)}`}
            </button>
          )}
        </>
      )}
      <p className="text-[11px] text-slate-500 mt-auto">
        Minimum: {card.minimum_full_season.toLocaleString('en-US')} {card.unit_label}
        {card.minimum_minutes_full_season
          ? ` and ${card.minimum_minutes_full_season.toLocaleString('en-US')} minutes`
          : ''}{' '}
        over a full season, scaled
      </p>
    </section>
  );
}

export function LeagueLeadersPanel({ data }: { data: PlayerLeadersPayload | null }) {
  const [position, setPosition] = useState<LeaderPositionKey>('all');

  if (!data) {
    return (
      <section data-testid="league-leaders" className="text-sm text-slate-400">
        League leaders are unavailable right now.
      </section>
    );
  }

  const m = data.methods;
  return (
    <section data-testid="league-leaders" aria-labelledby="league-leaders-title" className="space-y-4">
      <div className="flex flex-col sm:flex-row sm:items-end justify-between gap-3">
        <div>
          <h2 id="league-leaders-title" className="text-xl font-black text-white">
            League Leaders <span className="text-sm font-semibold text-slate-400">{data.season}</span>
          </h2>
          <p className="text-xs text-slate-400">
            Qualified players only. Each card&rsquo;s minimum scales with team games played.
          </p>
        </div>
        <div role="group" aria-label="Filter leaders by position" className="flex gap-1">
          {data.position_filters.map((p) => (
            <button
              key={p.key}
              type="button"
              aria-pressed={position === p.key}
              data-testid={`leader-filter-${p.key}`}
              onClick={() => setPosition(p.key)}
              className={`px-3 py-1 rounded-full text-xs font-semibold border ${
                position === p.key
                  ? 'bg-orange-500/20 text-orange-300 border-orange-500/40'
                  : 'text-slate-300 border-slate-700 hover:border-slate-500'
              }`}
            >
              {p.label}
            </button>
          ))}
        </div>
      </div>
      <p className="text-[11px] text-slate-400">{m.position_note}</p>

      {data.groups.map((g) => {
        const cards = data.cards.filter((c) => c.group === g.key);
        if (!cards.length) return null;
        return (
          <div key={g.key} data-testid={`leader-group-${g.key}`} className="space-y-2">
            <h3 className="text-xs font-bold uppercase tracking-wider text-slate-400">{g.label}</h3>
            <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4 gap-3">
              {cards.map((c) => (
                <LeaderCardView key={`${c.key}-${position}`} card={c} position={position} />
              ))}
            </div>
          </div>
        );
      })}

      <details data-testid="leader-methods" className="text-xs text-slate-300 bg-surface-raised/40 border border-slate-800 rounded-xl p-4">
        <summary className="cursor-pointer font-semibold text-slate-200">How leaders qualify</summary>
        <div className="mt-3 space-y-2">
          <p>{m.scaling_text}</p>
          <p>
            Rule: <code>{m.scaling_rule}</code>
          </p>
          <p>{m.traded_players}</p>
          <p>{m.ranking}</p>
          <p>{m.noise_note}</p>
          <p>{m.sample}</p>
          <p>{m.refresh}</p>
          <table className="w-full max-w-xl text-left">
            <caption className="sr-only">Full-season minimum per stat</caption>
            <thead>
              <tr className="text-slate-400">
                <th scope="col" className="py-1 pr-3 font-semibold">Stat</th>
                <th scope="col" className="py-1 font-semibold">Full-season minimum</th>
              </tr>
            </thead>
            <tbody>
              {m.minimums.map((row) => (
                <tr key={row.key} className="border-t border-slate-800/70">
                  <td className="py-1 pr-3">{row.label}</td>
                  <td className="py-1 tabular-nums">
                    {row.minimum_full_season.toLocaleString('en-US')} {row.unit_label}
                    {row.minimum_minutes_full_season
                      ? ` and ${row.minimum_minutes_full_season.toLocaleString('en-US')} minutes`
                      : ''}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
          <p>{m.nulls}</p>
          <p className="text-slate-500">
            Minimums from the leader reliability study, source commit <code>{m.study_source_commit.slice(0, 12)}</code>.{' '}
            <Link
              href="/players/leaders/methodology"
              className="text-orange-400 hover:text-orange-300 underline underline-offset-2"
            >
              Full methodology and reliability curves
            </Link>
          </p>
        </div>
      </details>
    </section>
  );
}
