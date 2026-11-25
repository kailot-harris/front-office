'use client';

/**
 * /momentum: the NFL Momentum Board (NFL_analytics#226), read from
 * momentum_board.json. The page sorts, toggles windows and expands rows; it never
 * computes, fills or estimates a value. A value that is not published shows as
 * missing with the reason the JSON gives. No flag carries a significance badge.
 */
import React, { useEffect, useId, useState } from 'react';
import Link from 'next/link';
import { ArrowDown, ArrowUp, ChevronDown, ChevronRight } from 'lucide-react';
import { TeamLogo } from '@/components/TeamLogo';
import { InfoTip } from '@/components/InfoTip';
import { DivergingBars, RankHistoryLine, Sparkline, signed } from '@/components/MomentumCharts';
import type {
  MomentumFlag,
  MomentumPayload,
  MomentumRow,
  MomentumSortOption,
} from '@/lib/momentumTypes';

type Methods = MomentumPayload['methods'];
type FlagDefinition = Methods['flags']['definitions'][number];

/* ------------------------------------------------------------------ copy ---- */

/** Display digits per published sort key. Formatting only; the values are the JSON's. */
const SORT_DIGITS: Record<string, number> = {
  combined_score: 2,
  form_epa: 3,
  opponent_adjusted_margin: 1,
  trend: 3,
  residual: 1,
  elo_change: 1,
  elo_current: 1,
};

/** Sort keys that always have a column; any other selected key adds one column. */
const FIXED_SORT_COLUMNS = ['combined_score', 'form_epa', 'opponent_adjusted_margin', 'elo_change'] as const;

const SORT_HELP: Record<string, string> = {
  combined_score:
    'Weighted sum of four parts, each compared with the other teams that week (z-scores): form, trend, margin against the Elo expectation and Elo change. 0 is average. The weights are listed under "How this is calculated".',
  form_epa:
    "Expected points added per play over the window, offense minus defense allowed, each adjusted for the opponent's level.",
  opponent_adjusted_margin:
    "Average point margin over the window, adjusted for the strength of the opponents faced. Context, not part of the score.",
  trend: "Form over the window minus the team's season-to-date form.",
  residual: 'Average margin per game minus the margin the production Elo model expected before each game.',
  elo_change: 'Change in Elo rating across the window. Elo rises after wins and falls after losses, more for bigger margins and stronger opponents.',
  elo_current: 'Elo rating after the latest game.',
};

const FLAG_GROUP_LABEL: Record<string, string> = {
  luck: 'Luck check',
  context: 'Context only',
  availability: 'Availability',
};

const COMPONENT_LABEL: Record<string, string> = {
  form: 'Form',
  trend: 'Trend',
  residual: 'Margin vs Elo',
  elo_change: 'Elo change',
};

const wp = (v: number) => `${Math.round(v * 100)}%`;
const plural = (n: number, one: string, many = `${one}s`) => `${n} ${n === 1 ? one : many}`;

/** Label for a team's carried-over games, or null when the window is all this season. */
export function carriedLabel(row: MomentumRow, carryMethod: string): string | null {
  if (row.carried_games <= 0) return null;
  const season = row.carried_from_season ?? 'last season';
  const how = carryMethod === 'mean_regress' ? 'regressed to the mean' : `carried over (${carryMethod})`;
  return `Includes ${plural(row.carried_games, 'game')} from ${season}, ${how}`;
}

/* --------------------------------------------------------------- sorting ---- */

/**
 * Sort rows by one of the published sort keys. Unranked teams, and teams with no
 * value for this key, go last. Ties fall back to the momentum rank, then the team
 * code. Nothing is computed: the keys are read as published.
 */
export function sortRows(rows: MomentumRow[], key: string, descending: boolean): MomentumRow[] {
  const dir = descending ? -1 : 1;
  return [...rows].sort((a, b) => {
    const av = a.ranked ? a.sort_keys[key] ?? null : null;
    const bv = b.ranked ? b.sort_keys[key] ?? null : null;
    if (av === null && bv !== null) return 1;
    if (bv === null && av !== null) return -1;
    if (av !== null && bv !== null && av !== bv) return dir * (av - bv);
    if (a.ranked !== b.ranked) return a.ranked ? -1 : 1;
    const ar = a.rank ?? Infinity;
    const br = b.rank ?? Infinity;
    if (ar !== br) return ar - br;
    return a.team.localeCompare(b.team);
  });
}

/* ------------------------------------------------------- small components ---- */

/** A missing value: a dash, with the reason as a tooltip and in text for screen readers. */
const Missing: React.FC<{ reason?: string | null }> = ({ reason }) => (
  <span title={reason ?? undefined} className="text-slate-400">
    <span aria-hidden="true">{'–'}</span>
    <span className="sr-only">Missing{reason ? `: ${reason}` : ''}</span>
  </span>
);

/** Same, with the reason written out. */
const MissingWithReason: React.FC<{ reason: string }> = ({ reason }) => (
  <span className="text-slate-400">Missing: {reason}</span>
);

const Num: React.FC<{ v: number | null; digits?: number; sign?: boolean; reason?: string | null }> = ({
  v,
  digits = 2,
  sign = true,
  reason,
}) =>
  v === null ? <Missing reason={reason ?? 'not published'} /> : <>{sign ? signed(v, digits) : v.toFixed(digits)}</>;

const focusRing =
  'focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-accent-500';

const Th: React.FC<{ label: string; help: React.ReactNode; align?: 'left' | 'right'; className?: string }> = ({
  label,
  help,
  align = 'left',
  className = '',
}) => (
  <th scope="col" className={`px-3 py-2 text-left font-semibold whitespace-nowrap ${className}`}>
    <span className="inline-flex items-center gap-0.5">
      {label}
      <InfoTip label={label} align={align}>
        {help}
      </InfoTip>
    </span>
  </th>
);

/** A column header that sorts the board by a published sort key. */
const SortTh: React.FC<{
  option: MomentumSortOption;
  active: boolean;
  descending: boolean;
  onSort: (key: string) => void;
}> = ({ option, active, descending, onSort }) => (
  <th
    scope="col"
    aria-sort={active ? (descending ? 'descending' : 'ascending') : 'none'}
    className="px-3 py-2 text-left font-semibold whitespace-nowrap"
  >
    <span className="inline-flex items-center gap-0.5">
      <button
        type="button"
        onClick={() => onSort(option.key)}
        className={`inline-flex min-h-6 items-center gap-1 rounded text-left hover:text-slate-100 ${focusRing} ${
          active ? 'text-slate-100' : ''
        }`}
      >
        {option.label}
        {active &&
          (descending ? <ArrowDown className="h-3 w-3" aria-hidden="true" /> : <ArrowUp className="h-3 w-3" aria-hidden="true" />)}
        <span className="sr-only">, sort</span>
      </button>
      <InfoTip label={option.label}>{SORT_HELP[option.key] ?? option.label}</InfoTip>
    </span>
  </th>
);

/* ----------------------------------------------------------- detail panel ---- */

/** Scalar entries of a flag's detail object, shown as published. */
function detailPairs(detail: Record<string, unknown> | undefined): [string, string][] {
  if (!detail) return [];
  return Object.entries(detail)
    .filter(([, v]) => typeof v === 'number' || typeof v === 'string' || typeof v === 'boolean')
    .map(([k, v]) => [k.replace(/_/g, ' '), String(v)]);
}

const FlagCard: React.FC<{ flag: MomentumFlag; def: FlagDefinition | undefined }> = ({ flag, def }) => {
  const label = def?.label ?? flag.key;
  const pairs = detailPairs(flag.detail);
  return (
    <li
      data-testid={`flag-${flag.key}`}
      className="rounded-lg border border-slate-800 bg-surface-raised/60 p-3 text-xs space-y-1.5"
    >
      <div className="flex flex-wrap items-center gap-1.5">
        <span className="font-semibold text-slate-100">{label}</span>
        {def && (
          <InfoTip label={label}>
            <span className="block">Value: {def.value}.</span>
            <span className="block mt-1 text-slate-400">Statistic: {def.test}.</span>
          </InfoTip>
        )}
        <span className="ml-auto text-[11px] text-slate-400">{FLAG_GROUP_LABEL[flag.group] ?? flag.group}</span>
      </div>
      <dl className="grid grid-cols-[auto_1fr] gap-x-3 gap-y-0.5">
        <dt className="text-slate-400">Raw value</dt>
        <dd className="font-mono tabular-nums text-slate-200">
          {flag.value === null ? <MissingWithReason reason={flag.null_reason ?? 'not published'} /> : flag.value}
        </dd>
        {flag.statistic !== null && (
          <>
            <dt className="text-slate-400">Statistic</dt>
            <dd className="font-mono tabular-nums text-slate-200">{flag.statistic}</dd>
          </>
        )}
        {flag.n !== null && (
          <>
            <dt className="text-slate-400">Sample</dt>
            <dd className="font-mono tabular-nums text-slate-200">{flag.n}</dd>
          </>
        )}
        {pairs.map(([k, v]) => (
          <React.Fragment key={k}>
            <dt className="text-slate-400">{k}</dt>
            <dd className="font-mono tabular-nums text-slate-200">{v}</dd>
          </React.Fragment>
        ))}
      </dl>
    </li>
  );
};

interface QbDetail {
  current_starter?: { id: string; name: string } | null;
  changed_in_latest_game?: boolean;
  starters_in_window?: { id: string; name: string; starts: number }[];
  carried_games_excluded?: number;
}

interface KeyPlayersDetail {
  key_players?: number;
  games?: number;
  player_games_missed?: number;
  listed_out?: number;
  carried_games_excluded?: number;
  missed_players?: { player?: string; position?: string; games_missed?: number; [k: string]: unknown }[];
}

const QbChange: React.FC<{ flag: MomentumFlag | undefined }> = ({ flag }) => {
  if (!flag) return <MissingWithReason reason="no starting-QB entry published" />;
  if (flag.value === null) return <MissingWithReason reason={flag.null_reason ?? 'not published'} />;
  const d = (flag.detail ?? {}) as QbDetail;
  return (
    <div className="space-y-1 text-xs text-slate-300" data-testid="qb-change">
      <p>
        <span className="font-mono tabular-nums text-slate-100">{flag.value}</span> starting-QB{' '}
        {flag.value === 1 ? 'change' : 'changes'} in the window&apos;s games this season
        {d.current_starter ? <>; current starter {d.current_starter.name}</> : null}
        {d.changed_in_latest_game ? ' (changed in the latest game)' : ''}.
      </p>
      {d.starters_in_window && d.starters_in_window.length > 0 && (
        <p className="text-slate-400">
          Starts in window: {d.starters_in_window.map((s) => `${s.name} ${s.starts}`).join(', ')}
        </p>
      )}
      {!!d.carried_games_excluded && (
        <p className="text-slate-400">{plural(d.carried_games_excluded, 'carried game')} from last season not counted.</p>
      )}
      <p className="text-slate-400">Context only: not part of the score and not a prediction.</p>
    </div>
  );
};

const KeyPlayers: React.FC<{ flag: MomentumFlag | undefined }> = ({ flag }) => {
  if (!flag) return <MissingWithReason reason="no key-players entry published" />;
  if (flag.value === null)
    return (
      <p className="text-xs" data-testid="key-players-missing">
        <MissingWithReason reason={flag.null_reason ?? 'not published'} />
      </p>
    );
  const d = (flag.detail ?? {}) as KeyPlayersDetail;
  return (
    <div className="space-y-1 text-xs text-slate-300" data-testid="key-players-missing">
      <p>
        Raw value <span className="font-mono tabular-nums text-slate-100">{flag.value}</span>
        {d.player_games_missed !== undefined && flag.n !== null && (
          <>
            {' '}
            ({d.player_games_missed} of {flag.n} key player-games missed
            {d.listed_out !== undefined ? `, ${d.listed_out} listed Out` : ''})
          </>
        )}
        . No badge.
      </p>
      {d.missed_players && d.missed_players.length > 0 && (
        <ul className="list-disc pl-5 text-slate-400">
          {d.missed_players.map((p, i) => (
            <li key={`${p.player ?? "player"}-${i}`}>
              {[p.player, p.position, p.games_missed !== undefined ? `${p.games_missed} missed` : null]
                .filter(Boolean)
                .join(', ')}
            </li>
          ))}
        </ul>
      )}
    </div>
  );
};

/**
 * The expanded panel sits inside a table that scrolls sideways, so layout is
 * chosen from the measured width of the scroll container, not the viewport.
 * Until it is measured (server render, tests) viewport breakpoints apply.
 */
const PANEL_STACK_BELOW = 768;
const twoColClass = (w: number | null): string =>
  w === null ? 'grid-cols-1 lg:grid-cols-2' : w >= PANEL_STACK_BELOW ? 'grid-cols-2' : 'grid-cols-1';
const flagGridClass = (w: number | null): string =>
  w === null ? 'grid-cols-1 sm:grid-cols-2 xl:grid-cols-3' : w >= 1100 ? 'grid-cols-3' : w >= 560 ? 'grid-cols-2' : 'grid-cols-1';

const MomentumDetail: React.FC<{
  row: MomentumRow;
  id: string;
  teamCount: number;
  methods: Methods;
  panelWidth: number | null;
}> = ({ row, id, teamCount, methods, panelWidth }) => {
  const defs = Object.fromEntries(methods.flags.definitions.map((d) => [d.key, d]));
  const luck = row.flags.filter((f) => f.group === 'luck');
  const context = row.flags.filter((f) => f.group === 'context');
  const qb = row.flags.find((f) => f.key === 'starting_qb_change');
  const kpm = row.flags.find((f) => f.key === 'key_players_missing');
  const cs = row.combined_score;
  const comps: { key: string; z: number | null; w: number }[] = [
    { key: 'form', z: cs.components.form_z, w: cs.weights.form },
    { key: 'trend', z: cs.components.trend_z, w: cs.weights.trend },
    { key: 'residual', z: cs.components.residual_z, w: cs.weights.residual },
    { key: 'elo_change', z: cs.components.elo_change_z, w: cs.weights.elo_change },
  ];
  const zBars = comps
    .filter((c): c is { key: string; z: number; w: number } => c.z !== null)
    .map((c) => ({ key: c.key, label: `${COMPONENT_LABEL[c.key]} (weight ${wp(c.w)})`, value: c.z }));
  const ep = row.epa_splits;
  const next = row.schedule_strength.next_opponent;
  const carried = carriedLabel(row, methods.carry_over.method);
  const sec = 'space-y-2';
  const h3 = 'text-sm font-semibold text-slate-100';
  const dl = 'grid grid-cols-[auto_1fr] gap-x-4 gap-y-1 text-xs';
  const dt = 'text-slate-400';
  const dd = 'font-mono tabular-nums text-slate-200';

  return (
    <div
      id={id}
      role="region"
      aria-label={`${row.team_name} details`}
      data-testid="momentum-detail"
      className="sticky left-0 box-border min-w-0 max-w-full space-y-5 p-4"
      style={panelWidth !== null ? { width: panelWidth } : undefined}
    >
      {carried && (
        <p data-testid="momentum-detail-carried" className="rounded-md border border-amber-500/30 bg-amber-500/10 px-3 py-2 text-xs text-amber-200">
          {carried}. {row.current_season_games_in_window} of the window&apos;s {row.games_in_window} games are from this season.
        </p>
      )}
      <div className={`grid gap-6 ${twoColClass(panelWidth)}`}>
        <section aria-labelledby={`${id}-numbers`} className={sec}>
          <h3 id={`${id}-numbers`} className={h3}>
            Key numbers
          </h3>
          <dl className={dl}>
            <dt className={dt}>Form (adj. EPA/play)</dt>
            <dd className={dd}>
              <Num v={row.form.epa_per_play} digits={3} />
              {row.form.rank !== null && <span className="text-slate-400"> (rank {row.form.rank})</span>}
            </dd>
            <dt className={dt}>Season-to-date form</dt>
            <dd className={dd}>
              <Num v={row.form.season_to_date} digits={3} />
            </dd>
            <dt className={dt}>Opponent-adjusted margin</dt>
            <dd className={dd}>
              <Num v={row.form.opponent_adjusted_margin} digits={1} />
              {row.form.opponent_adjusted_margin_rank !== null && (
                <span className="text-slate-400"> (rank {row.form.opponent_adjusted_margin_rank})</span>
              )}
            </dd>
            <dt className={dt}>Margin vs Elo expectation</dt>
            <dd className={dd}>
              <Num v={row.residual.per_game} digits={1} /> <span className="text-slate-400">per game</span>
            </dd>
            <dt className={dt}>Elo</dt>
            <dd className={dd}>
              {row.elo.current.toFixed(1)} (rank {row.elo.rank}); <Num v={row.elo.change_in_window} digits={1} /> in window,{' '}
              <Num v={row.elo.change_since_last_week} digits={1} reason={row.elo.change_since_last_week_null_reason} /> since last
              week
            </dd>
            <dt className={dt}>Opponents faced (mean Elo)</dt>
            <dd className={dd}>
              <Num v={row.schedule_strength.faced_window} digits={1} sign={false} /> in window,{' '}
              <Num v={row.schedule_strength.faced_season} digits={1} sign={false} /> season
            </dd>
          </dl>
        </section>

        <section aria-labelledby={`${id}-epa`} className={sec}>
          <h3 id={`${id}-epa`} className={h3}>
            EPA splits
          </h3>
          <p className="text-xs text-slate-400">Per play over the window. Defense is EPA allowed: lower is better.</p>
          <dl className={dl}>
            <dt className={dt}>Offense, opponent-adjusted</dt>
            <dd className={dd}>
              <Num v={ep.offense_adjusted} digits={3} /> <span className="text-slate-400">(change vs season </span>
              <Num v={ep.offense_adjusted_change} digits={3} />
              <span className="text-slate-400">)</span>
            </dd>
            <dt className={dt}>Defense, opponent-adjusted</dt>
            <dd className={dd}>
              <Num v={ep.defense_adjusted} digits={3} /> <span className="text-slate-400">(change vs season </span>
              <Num v={ep.defense_adjusted_change} digits={3} />
              <span className="text-slate-400">)</span>
            </dd>
            <dt className={dt}>Pass offense / rush offense</dt>
            <dd className={dd}>
              <Num v={ep.pass_offense} digits={3} /> / <Num v={ep.rush_offense} digits={3} />
            </dd>
            <dt className={dt}>Pass defense / rush defense</dt>
            <dd className={dd}>
              <Num v={ep.pass_defense} digits={3} /> / <Num v={ep.rush_defense} digits={3} />
            </dd>
            <dt className={dt}>Success rate, offense / defense</dt>
            <dd className={dd}>
              <Num v={ep.success_offense} digits={3} sign={false} /> / <Num v={ep.success_defense} digits={3} sign={false} />
            </dd>
          </dl>
        </section>
      </div>

      <section aria-labelledby={`${id}-score`} className={sec}>
        <h3 id={`${id}-score`} className={h3}>
          Combined score parts
        </h3>
        <p className="text-xs text-slate-400">
          Each part as a z-score against the other teams this week; the score is the weighted sum.
        </p>
        {cs.value === null ? (
          <p className="text-xs">
            <MissingWithReason reason={cs.null_reason ?? 'not published'} />
          </p>
        ) : (
          <DivergingBars items={zBars} />
        )}
      </section>

      <section aria-labelledby={`${id}-flags`} className={sec}>
        <h3 id={`${id}-flags`} className={h3}>
          Luck checks (raw values)
        </h3>
        <p className="text-xs text-slate-400">
          Raw values only, no significance badge: {methods.flags.significance_hidden_reason}
        </p>
        <ul className={`grid gap-2 ${flagGridClass(panelWidth)}`}>
          {luck.map((f) => (
            <FlagCard key={f.key} flag={f} def={defs[f.key]} />
          ))}
        </ul>
      </section>

      <section aria-labelledby={`${id}-context`} className={sec}>
        <h3 id={`${id}-context`} className={h3}>
          Context
        </h3>
        <p className="text-xs text-slate-400">Opponent strength, home share and rest are context only, not judgements.</p>
        <ul className={`grid gap-2 ${flagGridClass(panelWidth)}`}>
          {context.map((f) => (
            <FlagCard key={f.key} flag={f} def={defs[f.key]} />
          ))}
        </ul>
      </section>

      <div className={`grid gap-6 ${twoColClass(panelWidth)}`}>
        <section aria-labelledby={`${id}-kpm`} className={sec}>
          <h3 id={`${id}-kpm`} className={h3}>
            Key players missing
          </h3>
          <KeyPlayers flag={kpm} />
        </section>
        <section aria-labelledby={`${id}-qb`} className={sec}>
          <h3 id={`${id}-qb`} className={h3}>
            Starting-QB change
          </h3>
          <QbChange flag={qb} />
        </section>
      </div>

      <div className={`grid gap-6 ${twoColClass(panelWidth)}`}>
        <section aria-labelledby={`${id}-next`} className={sec}>
          <h3 id={`${id}-next`} className={h3}>
            Next opponent
          </h3>
          {next === null ? (
            <p className="text-xs">
              <MissingWithReason reason={row.schedule_strength.next_opponent_null_reason ?? 'no game scheduled'} />
            </p>
          ) : (
            <p className="text-xs text-slate-300" data-testid="next-opponent">
              Week {next.week}, {next.date}: {next.home ? 'vs' : 'at'} {next.opponent}
              {next.opponent_elo !== null && (
                <>
                  {' '}
                  (Elo {next.opponent_elo.toFixed(1)}
                  {next.opponent_elo_rank !== null && <>, rank {next.opponent_elo_rank}</>})
                </>
              )}
              .
            </p>
          )}
        </section>
        <section aria-labelledby={`${id}-history`} className={sec}>
          <h3 id={`${id}-history`} className={h3}>
            Rank history
          </h3>
          {row.rank_history.length === 0 ? (
            <p className="text-xs">
              <MissingWithReason reason={`weekly history starts ${methods.rank_history.starts ?? 'after the first completed week'}`} />
            </p>
          ) : (
            <>
              <RankHistoryLine history={row.rank_history} teamCount={teamCount} team={row.team_name} />
              <ul className="text-xs text-slate-300 space-y-0.5">
                {row.rank_history.map((h) => (
                  <li key={`${h.season}-${h.week}`} className="font-mono tabular-nums">
                    {h.season} week {h.week}: rank {h.rank}
                    {h.carried_games > 0 && <span className="text-slate-400"> ({plural(h.carried_games, 'carried game')})</span>}
                  </li>
                ))}
              </ul>
            </>
          )}
        </section>
      </div>
    </div>
  );
};

/* -------------------------------------------------------------- the table ---- */

const RankChange: React.FC<{ row: MomentumRow }> = ({ row }) => {
  if (row.rank_change_week === null) {
    return <Missing reason={row.rank_change_week_null_reason ?? (row.ranked ? 'not published' : 'unranked')} />;
  }
  const c = row.rank_change_week;
  if (c === 0) {
    return (
      <span className="text-slate-300">
        <span aria-hidden="true">0</span>
        <span className="sr-only">No change in rank since last week</span>
      </span>
    );
  }
  const up = c > 0;
  return (
    <span className={`font-mono tabular-nums ${up ? 'text-emerald-400' : 'text-rose-400'}`}>
      <span aria-hidden="true">
        {up ? '▲' : '▼'} {Math.abs(c)}
      </span>
      <span className="sr-only">
        {up ? 'Up' : 'Down'} {plural(Math.abs(c), 'place')} since last week
      </span>
    </span>
  );
};

const SortValue: React.FC<{ row: MomentumRow; sortKey: string }> = ({ row, sortKey }) => {
  const v = row.sort_keys[sortKey] ?? null;
  if (v === null) return <Missing reason={row.combined_score.null_reason ?? 'not published for this team'} />;
  const digits = SORT_DIGITS[sortKey] ?? 2;
  return <>{sortKey === 'elo_current' ? v.toFixed(digits) : signed(v, digits)}</>;
};

interface BoardRowProps {
  row: MomentumRow;
  windowSize: number;
  expanded: boolean;
  onToggle: () => void;
  extraSortKey: string | null;
  colSpan: number;
  teamCount: number;
  methods: Methods;
  panelWidth: number | null;
}

const BoardRow: React.FC<BoardRowProps> = ({
  row,
  windowSize,
  expanded,
  onToggle,
  extraSortKey,
  colSpan,
  teamCount,
  methods,
  panelWidth,
}) => {
  const detailId = `momentum-detail-${row.team}-${windowSize}`;
  const greyed = !row.ranked;
  const carried = carriedLabel(row, methods.carry_over.method);
  const td = 'px-3 py-2 whitespace-nowrap font-mono tabular-nums';
  return (
    <>
      <tr
        data-team={row.team}
        data-ranked={row.ranked ? 'true' : 'false'}
        className={`border-t border-slate-800/70 ${greyed ? 'bg-slate-900/40 text-slate-400' : 'text-slate-200'}`}
      >
        <td className="px-3 py-2">
          <button
            type="button"
            onClick={onToggle}
            aria-expanded={expanded}
            aria-controls={expanded ? detailId : undefined}
            className={`flex min-h-8 items-center gap-2 text-left rounded ${focusRing}`}
          >
            {expanded ? (
              <ChevronDown className="w-4 h-4 shrink-0" aria-hidden="true" />
            ) : (
              <ChevronRight className="w-4 h-4 shrink-0" aria-hidden="true" />
            )}
            <TeamLogo team={row.team} size="sm" />
            <span>
              <span className={`block font-semibold ${greyed ? 'text-slate-300' : 'text-slate-100'}`}>{row.team_name}</span>
              <span className="block text-[11px] text-slate-400 font-mono">
                {row.record.wins}-{row.record.losses}
                {row.record.ties > 0 ? `-${row.record.ties}` : ''}
              </span>
              {carried && (
                <span data-testid="carried-label" className="block text-[11px] text-amber-300 whitespace-normal max-w-[14rem]">
                  {carried}
                </span>
              )}
            </span>
          </button>
        </td>
        <td className="px-3 py-2 whitespace-nowrap">
          {row.ranked && row.rank !== null ? (
            <span className="font-mono tabular-nums font-semibold">
              <span className="sr-only">Rank </span>#{row.rank}
            </span>
          ) : (
            <span className="text-xs">
              <span className="sr-only">Unranked: </span>
              {row.games_in_window} of {windowSize} games
            </span>
          )}
        </td>
        <td className="px-3 py-2 whitespace-nowrap">
          <RankChange row={row} />
        </td>
        {FIXED_SORT_COLUMNS.map((k) => (
          <td key={k} className={td}>
            <SortValue row={row} sortKey={k} />
          </td>
        ))}
        {extraSortKey && (
          <td className={td}>
            <SortValue row={row} sortKey={extraSortKey} />
          </td>
        )}
        <td className="px-3 py-2 whitespace-nowrap text-xs">
          {row.schedule_strength.next_opponent ? (
            <>
              {row.schedule_strength.next_opponent.home ? 'vs' : 'at'} {row.schedule_strength.next_opponent.opponent}
            </>
          ) : (
            <Missing reason={row.schedule_strength.next_opponent_null_reason} />
          )}
        </td>
        <td className="px-3 py-2">
          {row.sparkline.some((p) => p.form_epa !== null) ? (
            <Sparkline points={row.sparkline} team={row.team_name} />
          ) : (
            <Missing reason="no game-by-game form published" />
          )}
        </td>
      </tr>
      {expanded && (
        <tr className="bg-surface-raised/40">
          <td colSpan={colSpan} className="p-0">
            <MomentumDetail row={row} id={detailId} teamCount={teamCount} methods={methods} panelWidth={panelWidth} />
          </td>
        </tr>
      )}
    </>
  );
};

/* ---------------------------------------------------------- methods panel ---- */

export const MethodsPanel: React.FC<{ methods: Methods; windows: number[] }> = ({ methods, windows }) => {
  const [open, setOpen] = useState(false);
  const id = useId();
  const cs = methods.combined_score;
  const components = Object.keys(cs.components) as (keyof typeof cs.components)[];
  return (
    <section className="rounded-xl border border-slate-800 bg-surface-raised/60">
      <h2 className="text-sm font-semibold">
        <button
          type="button"
          aria-expanded={open}
          aria-controls={id}
          onClick={() => setOpen((v) => !v)}
          className={`flex w-full items-center justify-between gap-2 px-4 py-3 text-left text-slate-100 rounded-xl ${focusRing}`}
        >
          <span>How this is calculated</span>
          {open ? <ChevronDown className="w-4 h-4" aria-hidden="true" /> : <ChevronRight className="w-4 h-4" aria-hidden="true" />}
        </button>
      </h2>
      {open && (
        <div id={id} data-testid="methods-panel" className="space-y-4 px-4 pb-4 text-xs leading-relaxed text-slate-300">
          <div>
            <h3 className="font-semibold text-slate-100">Not a forecast</h3>
            <p>{methods.summary}</p>
          </div>
          <div>
            <h3 className="font-semibold text-slate-100">Windows</h3>
            <p>
              Last {windows.join(', ')} games. {methods.windows.note} The board opens on {methods.windows.default_rule}.
            </p>
          </div>
          <div>
            <h3 className="font-semibold text-slate-100">Season start</h3>
            <p>{methods.carry_over.definition}</p>
          </div>
          <div>
            <h3 className="font-semibold text-slate-100">Form</h3>
            <p>{methods.form}</p>
          </div>
          <div>
            <h3 className="font-semibold text-slate-100">Combined score</h3>
            <ul className="list-disc pl-5 space-y-0.5">
              {components.map((k) => (
                <li key={k}>
                  {COMPONENT_LABEL[k] ?? k}: {cs.components[k]}
                </li>
              ))}
            </ul>
            <p className="mt-1">
              {cs.standardisation} Score = {cs.formula}.
            </p>
            <div className="mt-2 overflow-x-auto">
              <table className="text-xs" data-testid="weights-in-use">
                <caption className="text-left text-slate-400 pb-1">Weights in use</caption>
                <thead>
                  <tr className="text-slate-300">
                    <th scope="col" className="pr-4 text-left font-semibold">
                      Window
                    </th>
                    {components.map((k) => (
                      <th key={k} scope="col" className="pr-4 text-right font-semibold">
                        {COMPONENT_LABEL[k] ?? k}
                      </th>
                    ))}
                  </tr>
                </thead>
                <tbody>
                  {windows.map((w) => (
                    <tr key={w}>
                      <th scope="row" className="pr-4 text-left font-normal">
                        {w} games
                      </th>
                      {components.map((k) => (
                        <td key={k} className="pr-4 text-right font-mono tabular-nums">
                          {cs.weights[String(w)]?.[k] ?? '–'}
                        </td>
                      ))}
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
            <p className="mt-1">{cs.weights_source}</p>
            <p className="mt-1" data-testid="flat-surface">
              {cs.flat_surface}
            </p>
            <p className="mt-1">{cs.refit}</p>
          </div>
          <div>
            <h3 className="font-semibold text-slate-100">Flags</h3>
            <p data-testid="badges-hidden">{methods.flags.significance_hidden_reason}</p>
            <p className="mt-1">
              Context only: {methods.flags.context_only.map((k) => methods.flags.definitions.find((d) => d.key === k)?.label ?? k).join(', ')}.
            </p>
            <ul className="mt-1 list-disc pl-5 space-y-0.5">
              {methods.flags.definitions.map((d) => (
                <li key={d.key}>
                  <span className="text-slate-100">{d.label}</span>: {d.value}.
                </li>
              ))}
            </ul>
            <p className="mt-1">{methods.flags.key_players_missing}</p>
            <p className="mt-1">{methods.flags.starting_qb_change}</p>
            <p className="mt-1">{methods.flags.detail_source}</p>
          </div>
          <div>
            <h3 className="font-semibold text-slate-100">Elo</h3>
            <p>
              {String(methods.elo.model)}. Expected margin: {String(methods.elo.expected_margin)}.
            </p>
          </div>
          <div>
            <h3 className="font-semibold text-slate-100">Rank history</h3>
            <p>{methods.rank_history.rule}</p>
          </div>
          <p>Values that cannot be computed are shown as missing, with the reason. Nothing is imputed or synthesised.</p>
        </div>
      )}
      <p className="px-4 pb-3 text-xs">
        <Link
          href="/momentum/methodology"
          className={`inline-flex min-h-6 items-center text-accent-400 underline underline-offset-2 hover:text-accent-500 ${focusRing}`}
        >
          Full methodology and everything we tested
        </Link>
      </p>
    </section>
  );
};

/* ----------------------------------------------------------------- client ---- */

export const MomentumClient: React.FC<{ data: MomentumPayload | null }> = ({ data }) => {
  const [windowSize, setWindowSize] = useState<number | null>(data?.default_window ?? null);
  const [sortKey, setSortKey] = useState<string>(data?.sort_options[0]?.key ?? 'combined_score');
  const [descending, setDescending] = useState<boolean>(data?.sort_options[0]?.descending ?? true);
  const [expanded, setExpanded] = useState<Record<string, boolean>>({});
  const ids = useId();
  const [scrollEl, setScrollEl] = useState<HTMLDivElement | null>(null);
  const [panelWidth, setPanelWidth] = useState<number | null>(null);

  useEffect(() => {
    if (!scrollEl) return;
    const measure = () => {
      const w = Math.floor(scrollEl.clientWidth);
      if (w > 0) setPanelWidth(w);
    };
    measure();
    if (typeof ResizeObserver === 'undefined') return;
    const ro = new ResizeObserver(measure);
    ro.observe(scrollEl);
    return () => ro.disconnect();
  }, [scrollEl]);

  if (!data || windowSize === null || !data.boards[String(windowSize)]) {
    return (
      <div className="space-y-4">
        <h1 className="text-2xl font-bold text-slate-100">Momentum Board</h1>
        <p className="text-sm text-slate-400">The momentum data is unavailable right now.</p>
      </div>
    );
  }

  const board = data.boards[String(windowSize)];
  const sortOptions = data.sort_options;
  const sort = sortOptions.find((o) => o.key === sortKey) ?? sortOptions[0];
  const optionFor = (k: string) => sortOptions.find((o) => o.key === k);
  const rows = sortRows(board.rows, sort.key, descending);
  const rankedRows = board.rows.filter((r) => r.ranked).length;
  const extraSortKey = (FIXED_SORT_COLUMNS as readonly string[]).includes(sort.key) ? null : sort.key;
  const colSpan = 3 + FIXED_SORT_COLUMNS.length + (extraSortKey ? 1 : 0) + 2;
  const windows = [...data.windows].sort((a, b) => a - b);
  const methods = data.methods;

  const chooseSort = (key: string) => {
    const opt = optionFor(key);
    if (!opt) return;
    if (key === sort.key) setDescending((d) => !d);
    else {
      setSortKey(key);
      setDescending(opt.descending);
    }
  };

  return (
    <div className="space-y-6">
      <header className="space-y-2">
        <h1 className="text-2xl font-bold text-slate-100">Momentum Board</h1>
        <p className="text-sm text-slate-400 max-w-3xl">
          How each team has played recently: form against the opponents faced, its trend, results against the Elo
          expectation and Elo change. {data.season} regular season, through week {data.through_week} ({data.through_date}).
        </p>
        <p className="text-xs">
          <Link
            href="/momentum/methodology"
            className={`inline-flex min-h-6 items-center text-accent-400 underline underline-offset-2 hover:text-accent-500 ${focusRing}`}
          >
            Methodology and everything we tested
          </Link>
        </p>
      </header>

      <p
        data-testid="momentum-not-forecast"
        className="max-w-3xl rounded-lg border border-amber-500/40 bg-amber-500/10 px-3 py-2 text-sm text-amber-100"
      >
        <span className="font-semibold">Recent play, not a forecast.</span> {methods.summary}
      </p>

      <div className="flex flex-wrap items-end gap-x-6 gap-y-3">
        <div>
          <div id={`${ids}-window`} className="mb-1 text-xs font-semibold text-slate-300">
            Games in window
          </div>
          <div role="group" aria-labelledby={`${ids}-window`} className="inline-flex flex-wrap gap-1.5">
            {windows.map((n) => {
              const b = data.boards[String(n)];
              return (
                <button
                  key={n}
                  type="button"
                  aria-pressed={windowSize === n}
                  onClick={() => setWindowSize(n)}
                  className={`min-h-8 rounded-md px-3 py-1 text-xs font-semibold transition-colors ${focusRing} ${
                    windowSize === n
                      ? 'bg-fo-accent text-on-accent shadow-sm'
                      : 'bg-slate-800/80 text-slate-300 hover:text-slate-100 hover:bg-slate-800'
                  }`}
                >
                  {b?.label ?? `Last ${n} games`}
                </button>
              );
            })}
          </div>
        </div>
        <div>
          <label htmlFor={`${ids}-sort`} className="mb-1 block text-xs font-semibold text-slate-300">
            Sort by
          </label>
          <select
            id={`${ids}-sort`}
            value={sort.key}
            onChange={(e) => {
              const opt = optionFor(e.target.value);
              if (!opt) return;
              setSortKey(opt.key);
              setDescending(opt.descending);
            }}
            className={`min-h-8 rounded-md border border-slate-700 bg-surface-raised px-2 py-1 text-xs text-slate-100 ${focusRing}`}
          >
            {sortOptions.map((o) => (
              <option key={o.key} value={o.key}>
                {o.label}
              </option>
            ))}
          </select>
        </div>
      </div>

      {board.noisiest && (
        <p data-testid="momentum-noisiest" className="text-xs text-slate-400">
          {board.label}: {methods.windows.note}
        </p>
      )}

      {board.carried_team_count > 0 && (
        <p data-testid="momentum-carried-note" className="rounded-lg border border-amber-500/30 bg-amber-500/10 px-3 py-2 text-xs text-amber-200">
          {plural(board.carried_team_count, 'team')}&apos; windows include games from last season, regressed to the mean; each
          is labelled below.
        </p>
      )}

      <p role="status" className="sr-only">
        Showing {board.label}, sorted by {sort.label}. {rankedRows} of {board.rows.length} teams ranked.
      </p>

      <div ref={setScrollEl} data-testid="momentum-scroll" className="relative overflow-x-auto rounded-xl border border-slate-800">
        <table className="w-full min-w-[52rem] text-sm">
          <caption className="sr-only">
            Momentum board, {board.label}, sorted by {sort.label}
          </caption>
          <thead className="bg-surface-raised/80 text-xs text-slate-300">
            <tr>
              <Th label="Team" help="Team and record. Select a team to open its details: EPA splits, raw flags, availability and rank history." />
              <Th
                label="Rank"
                help="Position by combined score among teams with a full window. A team with fewer games shows its games so far and has no rank."
              />
              <Th label="Change" help="Places gained (up) or lost (down) since last week's board." />
              {FIXED_SORT_COLUMNS.map((k) => {
                const opt = optionFor(k);
                return opt ? (
                  <SortTh key={k} option={opt} active={sort.key === k} descending={descending} onSort={chooseSort} />
                ) : null;
              })}
              {extraSortKey && optionFor(extraSortKey) && (
                <SortTh option={optionFor(extraSortKey)!} active descending={descending} onSort={chooseSort} />
              )}
              <Th label="Next" help="Next scheduled opponent (vs = home, at = away)." />
              <Th
                label="Form by game"
                align="right"
                help="Opponent-adjusted EPA per play game by game this season. Each line is scaled to that team's own range, so compare shapes, not heights."
              />
            </tr>
          </thead>
          <tbody>
            {rows.map((row) => (
              <BoardRow
                key={row.team}
                row={row}
                windowSize={windowSize}
                expanded={!!expanded[row.team]}
                onToggle={() => setExpanded((s) => ({ ...s, [row.team]: !s[row.team] }))}
                extraSortKey={extraSortKey}
                colSpan={colSpan}
                teamCount={board.team_count}
                methods={methods}
                panelWidth={panelWidth}
              />
            ))}
          </tbody>
        </table>
      </div>

      <MethodsPanel methods={methods} windows={windows} />
    </div>
  );
};
