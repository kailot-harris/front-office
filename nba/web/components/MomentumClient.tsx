'use client';

import React, { useEffect, useId, useState } from 'react';
import { ChevronDown, ChevronRight } from 'lucide-react';
import { TeamLogo } from '@/components/TeamLogo';
import { InfoTip } from '@/components/InfoTip';
import { DriverBars, RankHistoryLine, Sparkline, signed } from '@/components/MomentumCharts';
import type {
  MomentumFlag,
  MomentumMethods,
  MomentumPayload,
  MomentumRow,
  MomentumSortOption,
} from '@/lib/momentumTypes';

/* ------------------------------------------------------------------ copy ---- */

/** Plain-language labels. Anything not listed here uses the label published in the JSON. */
const SORT_LABEL_OVERRIDES: Record<string, string> = {
  model_residual: 'Beat model expectation by',
};

const DRIVER_LABELS: { key: string; label: string }[] = [
  { key: 'efg_offense', label: 'Shooting efficiency (offense)' },
  { key: 'efg_defense', label: 'Shooting efficiency allowed' },
  { key: 'tov_offense', label: 'Turnovers (own)' },
  { key: 'tov_defense', label: 'Turnovers forced' },
  { key: 'oreb_offense', label: 'Offensive rebounding' },
  { key: 'oreb_defense', label: 'Defensive rebounding' },
  { key: 'ft_rate_offense', label: 'Free-throw rate (own)' },
  { key: 'ft_rate_defense', label: 'Free-throw rate allowed' },
  { key: 'unexplained', label: 'Not explained by these' },
];

const FLAG_HELP: Record<number, string> = {
  1: "Compares the team's actual shooting (effective field-goal %) with what the locations of its shots would predict. A large positive gap can mean hot shooting that fades.",
  2: "How opponents' three-point accuracy compares with the league average. Unusually low accuracy against a team may be luck.",
  3: "Compares the team's win rate with the win rate its points scored and allowed would predict.",
  4: 'Compares the record in close late-game situations with what its late-game scoring would predict.',
  5: "How opponents' free-throw accuracy compares with the league average.",
  6: 'Record in games decided by 3 points or fewer. Close games are partly luck.',
  7: "Marks results that are driven by a single lopsided game rather than the whole window.",
  8: 'How strong the opponents faced in this window were compared with the league average.',
  9: 'Share of the window played at home and with more rest than the opponent.',
  10: 'How often key rotation players did not play, compared with the league rate. Taken from box scores.',
  11: "How much playing time moved among players in this window compared with the season. Taken from box scores.",
};

const FLAG_GROUP_LABEL: Record<string, string> = {
  luck: 'Luck check',
  context: 'Context',
  availability: 'Availability',
};

const ELO_HELP =
  'A rating that rises after wins and falls after losses, by more for bigger margins and tougher opponents.';

const pct = (v: number) => `${(v * 100).toFixed(1)}%`;

/* --------------------------------------------------------------- sorting ---- */

/**
 * Sort rows by one of the published sort keys. Unranked teams, and ranked teams
 * with no value for this key, go last. Ties fall back to the momentum rank, then
 * the team code. Nothing is computed: the keys are read as published.
 */
export function sortRows(rows: MomentumRow[], option: MomentumSortOption): MomentumRow[] {
  const dir = option.descending ? -1 : 1;
  return [...rows].sort((a, b) => {
    const av = a.ranked ? a.sort_keys[option.key] ?? null : null;
    const bv = b.ranked ? b.sort_keys[option.key] ?? null : null;
    if (av === null && bv !== null) return 1;
    if (bv === null && av !== null) return -1;
    if (av !== null && bv !== null && av !== bv) return dir * (av - bv);
    // Teams with enough games stay above unranked teams even when their score is still blank.
    if (a.ranked !== b.ranked) return a.ranked ? -1 : 1;
    const ar = a.rank ?? Infinity;
    const br = b.rank ?? Infinity;
    if (ar !== br) return ar - br;
    return a.team.localeCompare(b.team);
  });
}

/* ------------------------------------------------------- small components ---- */

/** A missing value: a dash for sighted users, the reason as a hover tooltip and in text for screen readers. */
const Missing: React.FC<{ reason?: string | null }> = ({ reason }) => (
  <span title={reason ?? undefined} className="text-slate-400">
    <span aria-hidden="true">{'–'}</span>
    <span className="sr-only">Missing{reason ? `: ${reason}` : ''}</span>
  </span>
);

/** Same, but with the reason written out where a keyboard user can read it. */
const MissingWithReason: React.FC<{ reason: string }> = ({ reason }) => (
  <span className="text-slate-400">
    <span aria-hidden="true">{'–'} </span>
    <span>Missing: {reason}</span>
  </span>
);

const Th: React.FC<{
  label: string;
  help: React.ReactNode;
  align?: 'left' | 'right';
  className?: string;
}> = ({ label, help, align = 'left', className = '' }) => (
  <th scope="col" className={`px-3 py-2 text-left font-semibold whitespace-nowrap ${className}`}>
    <span className="inline-flex items-center gap-0.5">
      {label}
      <InfoTip label={label} align={align}>
        {help}
      </InfoTip>
    </span>
  </th>
);

/* ----------------------------------------------------------- detail panel ---- */

const FlagCard: React.FC<{ flag: MomentumFlag; label: string }> = ({ flag, label }) => {
  const help = FLAG_HELP[flag.id] ?? label;
  return (
    <li className="rounded-lg border border-slate-800 bg-surface-raised/60 p-3 text-xs space-y-1.5">
      <div className="flex flex-wrap items-center gap-1.5">
        <span className="font-semibold text-slate-100">{label}</span>
        <InfoTip label={label}>
          <span className="block">{help}</span>
          <span className="block mt-1 text-slate-400">
            A badge appears only when the result is statistically significant (z-score of 1.96 or more in size).
          </span>
        </InfoTip>
        {flag.significant && (
          <span className="inline-flex rounded-full border border-amber-500/60 bg-amber-500/15 px-2 py-0.5 text-[11px] font-semibold text-amber-300">
            Significant
          </span>
        )}
        <span className="ml-auto text-[11px] text-slate-400">{FLAG_GROUP_LABEL[flag.group] ?? flag.group}</span>
      </div>
      <dl className="grid grid-cols-[auto_1fr] gap-x-3 gap-y-0.5">
        <dt className="text-slate-400">Value</dt>
        <dd className="font-mono tabular-nums text-slate-200">
          {flag.value === null ? (
            <MissingWithReason reason={flag.null_reason ?? 'not published'} />
          ) : (
            flag.value
          )}
        </dd>
        <dt className="text-slate-400">z-score</dt>
        <dd className="font-mono tabular-nums text-slate-200">
          {flag.statistic === null ? (
            <MissingWithReason reason={flag.null_reason ?? 'not published'} />
          ) : (
            flag.statistic
          )}
        </dd>
        {flag.n != null && (
          <>
            <dt className="text-slate-400">Sample</dt>
            <dd className="font-mono tabular-nums text-slate-200">{flag.n}</dd>
          </>
        )}
      </dl>
    </li>
  );
};

/**
 * The expanded panel sits inside a table that scrolls sideways, so the browser
 * viewport says nothing about how much room it has (the sidebar takes some).
 * Layout is therefore chosen from the measured width of the scroll container.
 * Until it is measured (server render, tests) the viewport breakpoints apply.
 */
const PANEL_STACK_BELOW = 768;

const twoColClass = (w: number | null): string =>
  w === null ? 'grid-cols-1 lg:grid-cols-2' : w >= PANEL_STACK_BELOW ? 'grid-cols-2' : 'grid-cols-1';

const flagGridClass = (w: number | null): string =>
  w === null
    ? 'grid-cols-1 sm:grid-cols-2 xl:grid-cols-3'
    : w >= 1100
      ? 'grid-cols-3'
      : w >= 560
        ? 'grid-cols-2'
        : 'grid-cols-1';

const MomentumDetail: React.FC<{
  row: MomentumRow;
  id: string;
  teamCount: number;
  flagLabels: Record<number, string>;
  rankHistoryStarts: string;
  panelWidth: number | null;
}> = ({ row, id, teamCount, flagLabels, rankHistoryStarts, panelWidth }) => {
  const drivers = DRIVER_LABELS.filter((d) => typeof row.drivers[d.key] === 'number').map((d) => ({
    key: d.key,
    label: d.label,
    value: row.drivers[d.key] as number,
  }));
  const allZero = drivers.every((d) => d.value === 0);
  const wholeSeason = row.games_in_window === row.games_played;
  const sp = row.drivers.shot_profile;
  const next = row.schedule_strength.next_week;
  const resid = row.model_residual;

  return (
    <div
      id={id}
      role="region"
      aria-label={`${row.team_name} details`}
      data-testid="momentum-detail"
      className="sticky left-0 box-border min-w-0 max-w-full space-y-5 p-4"
      style={panelWidth !== null ? { width: panelWidth } : undefined}
    >
      <div className={`grid gap-6 ${twoColClass(panelWidth)}`}>
        <section aria-labelledby={`${id}-drivers`} className="space-y-2">
          <h3 id={`${id}-drivers`} className="text-sm font-semibold text-slate-100">
            What is driving it
          </h3>
          <p className="text-xs text-slate-400">
            Net rating points per 100 possessions, this window compared with the team&apos;s games before it.
          </p>
          {drivers.length > 0 ? (
            <DriverBars items={drivers} />
          ) : (
            <p className="text-xs">
              <MissingWithReason
                reason={typeof row.drivers.null_reason === 'string' ? row.drivers.null_reason : 'no driver breakdown published'}
              />
            </p>
          )}
          {allZero && drivers.length > 0 && wholeSeason && (
            <p className="text-xs text-slate-400">
              Every driver is 0 because this window covers all {row.games_played} games of the team&apos;s season so far.
            </p>
          )}
          {sp && sp.rim_attempt_share != null && (
            <p className="text-xs text-slate-400">
              Shot mix: {pct(sp.rim_attempt_share)} at the rim, {pct(sp.mid_attempt_share ?? 0)} mid-range,{' '}
              {pct(sp.three_attempt_share ?? 0)} from three.
            </p>
          )}
        </section>

        <section aria-labelledby={`${id}-numbers`} className="space-y-2">
          <h3 id={`${id}-numbers`} className="text-sm font-semibold text-slate-100">
            Key numbers
          </h3>
          <dl className="grid grid-cols-[auto_1fr] gap-x-4 gap-y-1 text-xs">
            <dt className="text-slate-400">Net rating</dt>
            <dd className="font-mono tabular-nums text-slate-200">
              {signed(row.ratings.net.value, 2)}{' '}
              {row.ratings.net.change === null ? (
                <MissingWithReason reason={row.ratings.net.change_null_reason ?? 'change not available'} />
              ) : (
                <>({signed(row.ratings.net.change, 2)} vs earlier games)</>
              )}
            </dd>
            <dt className="text-slate-400">Beat model expectation by</dt>
            <dd className="font-mono tabular-nums text-slate-200">
              {resid.value === null ? (
                <MissingWithReason reason={resid.null_reason ?? 'not published'} />
              ) : (
                <>
                  {signed(resid.value, 2)} points per game over {resid.residual_games_in_window} of{' '}
                  {row.games_in_window} games
                </>
              )}
            </dd>
            <dt className="text-slate-400">Form vs opponents faced</dt>
            <dd className="font-mono tabular-nums text-slate-200">
              {row.opponent_adjusted_form.value === null ? (
                <MissingWithReason reason="not published" />
              ) : (
                signed(row.opponent_adjusted_form.value, 2)
              )}
            </dd>
            <dt className="text-slate-400">Elo rating</dt>
            <dd className="font-mono tabular-nums text-slate-200">
              {row.elo.current.toFixed(1)} (rank {row.elo.rank})
            </dd>
            <dt className="text-slate-400">Opponents faced, win %</dt>
            <dd className="font-mono tabular-nums text-slate-200">
              {pct(row.schedule_strength.faced_window)} in window, {pct(row.schedule_strength.faced_season)} season
            </dd>
          </dl>
        </section>
      </div>

      <section aria-labelledby={`${id}-flags`} className="space-y-2">
        <h3 id={`${id}-flags`} className="text-sm font-semibold text-slate-100">
          Flags
        </h3>
        <p className="text-xs text-slate-400">
          Checks for results that may not last. The raw value and z-score are always shown; the badge appears only
          for a significant result.
        </p>
        <ul className={`grid gap-2 ${flagGridClass(panelWidth)}`}>
          {row.flags.map((f) => (
            <FlagCard key={f.id} flag={f} label={flagLabels[f.id] ?? f.key} />
          ))}
        </ul>
      </section>

      <div className={`grid gap-6 ${twoColClass(panelWidth)}`}>
        <section aria-labelledby={`${id}-next`} className="space-y-2">
          <h3 id={`${id}-next`} className="text-sm font-semibold text-slate-100">
            Next week&apos;s schedule strength
          </h3>
          {next.games === 0 || next.opponent_win_pct === null ? (
            <p className="text-xs">
              <MissingWithReason reason={next.null_reason ?? 'no games scheduled in the next 7 days'} />
            </p>
          ) : (
            <>
              <p className="text-xs text-slate-300">
                {next.games} {next.games === 1 ? 'game' : 'games'} against opponents winning{' '}
                {pct(next.opponent_win_pct)} of their games
                {next.rank !== null && <> (rank {next.rank}, where 1 is the hardest)</>}.
              </p>
              <ul className="text-xs text-slate-300 space-y-0.5">
                {next.opponents.map((o) => (
                  <li key={`${o.date}-${o.opponent}`} className="font-mono tabular-nums">
                    {o.date} {o.home ? 'vs' : 'at'} {o.opponent} ({pct(o.opponent_win_pct)})
                  </li>
                ))}
              </ul>
            </>
          )}
        </section>

        <section aria-labelledby={`${id}-history`} className="space-y-2">
          <h3 id={`${id}-history`} className="text-sm font-semibold text-slate-100">
            Rank history
          </h3>
          {row.rank_history.length === 0 ? (
            <p className="text-xs">
              <MissingWithReason reason={`weekly history starts ${rankHistoryStarts}`} />
            </p>
          ) : (
            <>
              <RankHistoryLine history={row.rank_history} teamCount={teamCount} team={row.team_name} />
              <ul className="text-xs text-slate-300 space-y-0.5">
                {row.rank_history.map((h) => (
                  <li key={h.week_start} className="font-mono tabular-nums">
                    Week of {h.week_start}: rank {h.rank}
                  </li>
                ))}
              </ul>
              <p className="text-xs text-slate-400">
                One snapshot per week, starting {rankHistoryStarts}. Earlier weeks are not reconstructed.
              </p>
            </>
          )}
        </section>
      </div>
    </div>
  );
};

/* -------------------------------------------------------------- the table ---- */

const EloCell: React.FC<{ value: number }> = ({ value }) => (
  <span
    className={`font-mono tabular-nums ${
      value > 0 ? 'text-emerald-400' : value < 0 ? 'text-rose-400' : 'text-slate-300'
    }`}
  >
    {signed(value, 1)}
  </span>
);

const RankChange: React.FC<{ row: MomentumRow; historyStarts: string }> = ({ row, historyStarts }) => {
  if (row.rank_change_7d === null) {
    return (
      <Missing
        reason={
          row.ranked
            ? `Rank from 7 days ago is not available yet; weekly history starts ${historyStarts}`
            : 'Unranked teams have no rank change'
        }
      />
    );
  }
  const c = row.rank_change_7d;
  if (c === 0) {
    return (
      <span className="text-slate-300">
        <span aria-hidden="true">0</span>
        <span className="sr-only">No change in rank over 7 days</span>
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
        {up ? 'Up' : 'Down'} {Math.abs(c)} {Math.abs(c) === 1 ? 'place' : 'places'} over 7 days
      </span>
    </span>
  );
};

interface BoardRowProps {
  row: MomentumRow;
  windowSize: number;
  expanded: boolean;
  onToggle: () => void;
  sort: MomentumSortOption;
  showSortColumn: boolean;
  colSpan: number;
  teamCount: number;
  flagLabels: Record<number, string>;
  historyStarts: string;
  panelWidth: number | null;
}

const BoardRow: React.FC<BoardRowProps> = ({
  row,
  windowSize,
  expanded,
  onToggle,
  sort,
  showSortColumn,
  colSpan,
  teamCount,
  flagLabels,
  historyStarts,
  panelWidth,
}) => {
  const detailId = `momentum-detail-${row.team}-${windowSize}`;
  const sortValue = row.sort_keys[sort.key] ?? null;
  const greyed = !row.ranked;
  return (
    <>
      <tr
        data-team={row.team}
        data-ranked={row.ranked ? 'true' : 'false'}
        className={`border-t border-slate-800/70 ${
          greyed ? 'bg-slate-900/40 text-slate-400' : 'text-slate-200'
        }`}
      >
        <td className="px-3 py-2">
          <button
            type="button"
            onClick={onToggle}
            aria-expanded={expanded}
            aria-controls={expanded ? detailId : undefined}
            className="flex min-h-8 items-center gap-2 text-left rounded focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-accent"
          >
            {expanded ? (
              <ChevronDown className="w-4 h-4 shrink-0" aria-hidden="true" />
            ) : (
              <ChevronRight className="w-4 h-4 shrink-0" aria-hidden="true" />
            )}
            <TeamLogo team={row.team} size="sm" />
            <span>
              <span className={`block font-semibold ${greyed ? 'text-slate-300' : 'text-slate-100'}`}>
                {row.team_name}
              </span>
              <span className="block text-[11px] text-slate-400 font-mono">
                {row.record.wins}-{row.record.losses}
              </span>
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
          <RankChange row={row} historyStarts={historyStarts} />
        </td>
        <td className="px-3 py-2 whitespace-nowrap font-mono tabular-nums">
          {row.combined_score.value === null ? (
            <Missing reason={row.combined_score.null_reason ?? 'Not ranked for this window'} />
          ) : (
            signed(row.combined_score.value, 2)
          )}
        </td>
        {showSortColumn && (
          <td className="px-3 py-2 whitespace-nowrap font-mono tabular-nums">
            {sortValue === null ? (
              <Missing
                reason={
                  row.ranked
                    ? row.combined_score.null_reason ?? 'Not available for this sort'
                    : 'Unranked teams have no value for this sort'
                }
              />
            ) : (
              <>
                {sort.key === 'schedule_strength' ? pct(sortValue) : signed(sortValue, sort.key === 'model_residual' ? 2 : 1)}
                {sort.key === 'model_residual' && (
                  <span className="ml-1 text-[11px] text-slate-400">
                    ({row.model_residual.residual_games_in_window} games)
                  </span>
                )}
              </>
            )}
          </td>
        )}
        <td className="px-3 py-2 whitespace-nowrap">
          <EloCell value={row.elo.change_7d} />
        </td>
        <td className="px-3 py-2 whitespace-nowrap">
          <EloCell value={row.elo.change_14d} />
        </td>
        <td className="px-3 py-2">
          {row.sparkline.length > 0 ? (
            <Sparkline points={row.sparkline} team={row.team_name} />
          ) : (
            <Missing reason="No trend line is published for unranked teams" />
          )}
        </td>
      </tr>
      {expanded && (
        <tr className="bg-surface-raised/40">
          <td colSpan={colSpan} className="p-0">
            <MomentumDetail
              row={row}
              id={detailId}
              teamCount={teamCount}
              flagLabels={flagLabels}
              rankHistoryStarts={historyStarts}
              panelWidth={panelWidth}
            />
          </td>
        </tr>
      )}
    </>
  );
};

/* ---------------------------------------------------------- methods panel ---- */

const MethodsPanel: React.FC<{ methods: MomentumMethods }> = ({ methods }) => {
  const [open, setOpen] = useState(false);
  const id = useId();
  const w = methods.combined_score.weights;
  const elo = methods.elo;
  const cov = methods.model_residual.coverage;
  const minGames = methods.model_residual.min_games_for_rank.split(': ').pop() ?? '';
  const samples = [...methods.combined_score.validation.current_season, ...methods.combined_score.validation.previous_season];
  const wp = (v: number) => `${Math.round(v * 100)}%`;
  return (
    <section className="rounded-xl border border-slate-800 bg-surface-raised/60">
      <h2 className="text-sm font-semibold">
        <button
          type="button"
          aria-expanded={open}
          aria-controls={id}
          onClick={() => setOpen((v) => !v)}
          className="flex w-full items-center justify-between gap-2 px-4 py-3 text-left text-slate-100 rounded-xl focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-accent"
        >
          <span>How this is calculated</span>
          {open ? <ChevronDown className="w-4 h-4" aria-hidden="true" /> : <ChevronRight className="w-4 h-4" aria-hidden="true" />}
        </button>
      </h2>
      {open && (
        <div id={id} className="space-y-4 px-4 pb-4 text-xs leading-relaxed text-slate-300">
          <div>
            <h3 className="font-semibold text-slate-100">Windows and ranking</h3>
            <p>
              The board looks at each team&apos;s last {methods.windows.sizes.join(', ')} games. A team that has played
              fewer games than the window is shown over the games it has played, greyed out and without a rank.
            </p>
          </div>
          <div>
            <h3 className="font-semibold text-slate-100">Momentum score</h3>
            <p>
              Each part is compared with the other ranked teams, then combined: {wp(w.form)} form against the
              opponents faced (adjusted for opponent strength, home court and fatigue), {wp(w.trend)} net rating
              trend against the season, {wp(w.residual)} beating the model&apos;s expectation, and {wp(w.elo)} Elo
              change. If any part is unavailable the score is left missing and the team is unranked. Nothing is
              filled in or estimated.
            </p>
            <p className="mt-1">
              Possessions: {methods.possessions} Ratings: {methods.ratings}
            </p>
          </div>
          <div>
            <h3 className="font-semibold text-slate-100">Beat model expectation by</h3>
            <p>
              The average gap, in points per game, between a team&apos;s actual margin and the margin the site&apos;s
              model predicted before tip-off. It uses only games with a recorded pregame prediction:{' '}
              {cov.panel_games_with_margin} of {cov.panel_games} games this season have one. Games without one are
              skipped, never filled. A team needs enough such games in the window to be ranked on this: {minGames}.
            </p>
          </div>
          <div>
            <h3 className="font-semibold text-slate-100">Elo</h3>
            <p>
              Ratings start from {elo.mean} and carry {Math.round(elo.season_carry * 100)}% of last season&apos;s final
              rating into the new season. Each game moves the winner up and the loser down by the same amount, with
              K = {elo.k} and a home-court bonus of {elo.home_advantage_elo} Elo points. Bigger margins move it more:
              the margin multiplier is {elo.margin_multiplier}.
            </p>
          </div>
          <div>
            <h3 className="font-semibold text-slate-100">What is driving it</h3>
            <p>
              A regression of game net rating on shooting, turnovers, rebounding and free-throw rate (for and
              against) over every team game this season. Each driver is its weight times how much that factor
              changed in the window compared with the team&apos;s games before the window. With fewer than 5 earlier games
              there is no comparison, so the drivers are left blank.
            </p>
          </div>
          <div>
            <h3 className="font-semibold text-slate-100">Schedule strength</h3>
            <p>{methods.schedule_strength}</p>
          </div>
          <div>
            <h3 className="font-semibold text-slate-100">Flags</h3>
            <p>
              Eleven checks for results that may not last. A badge appears only when the z-score is 1.96 or more in
              size (a 5% test; the two availability checks look in one direction only). The raw value and z-score
              are always shown.
            </p>
            <ul className="mt-1 list-disc pl-5 space-y-0.5">
              {methods.flags.definitions.map((d) => (
                <li key={d.id}>{d.label}</li>
              ))}
            </ul>
            <p className="mt-1">
              Missing players come from box scores (who did not play, and minutes), not from injury reports.
            </p>
          </div>
          <div>
            <h3 className="font-semibold text-slate-100">Rank history</h3>
            <p>
              One snapshot per week, starting {methods.rank_history.starts}. Earlier weeks are not reconstructed.
            </p>
          </div>
          <div>
            <h3 className="font-semibold text-slate-100">How well it has worked</h3>
            <p>
              Mean rank correlation between the score on a date and each team&apos;s average scoring margin over its next
              5 games (1 is perfect, 0 is no relationship), with an equal-weight blend for comparison. Descriptive
              only: overlapping windows make the dates not independent.
            </p>
            <ul className="mt-1 list-disc pl-5 space-y-0.5">
              {samples.map((s) => (
                <li key={s.sample}>
                  {s.sample}:{' '}
                  {s.available && s.mean_ic !== undefined
                    ? `${s.mean_ic.toFixed(2)} over ${s.n_dates} dates (equal-weight ${s.equal_weight_mean_ic?.toFixed(2)})`
                    : `not available yet${s.reason ? ` (${s.reason})` : ''}`}
                </li>
              ))}
            </ul>
          </div>
          <p>Values that cannot be computed are shown as missing, with the reason. Nothing is imputed or synthesised.</p>
        </div>
      )}
    </section>
  );
};

/* ----------------------------------------------------------------- client ---- */

export const MomentumClient: React.FC<{ data: MomentumPayload | null }> = ({ data }) => {
  const [windowSize, setWindowSize] = useState<number>(data?.default_window ?? 18);
  const [sortKey, setSortKey] = useState<string>(data?.sort_options[0]?.key ?? 'combined_score');
  const [expanded, setExpanded] = useState<Record<string, boolean>>({});
  const sortId = useId();
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

  if (!data || !data.boards[String(windowSize)]) {
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
  const sortLabel = (o: MomentumSortOption) => SORT_LABEL_OVERRIDES[o.key] ?? o.label;
  const rows = sortRows(board.rows, sort);
  const rankedRows = board.rows.filter((r) => r.ranked).length;
  const showSortColumn = sort.key !== 'combined_score';
  const colSpan = showSortColumn ? 8 : 7;
  const flagLabels = Object.fromEntries(data.methods.flags.definitions.map((d) => [d.id, d.label]));
  const historyStarts = data.methods.rank_history.starts;
  const weights = data.methods.combined_score.weights;
  const wp = (v: number) => `${Math.round(v * 100)}%`;
  const windows = [...data.windows].sort((a, b) => a - b);

  const sortHelp: Record<string, React.ReactNode> = {
    model_residual: (
      <>
        Average points per game above (positive) or below (negative) the margin the site&apos;s model predicted
        before tip-off, over the window&apos;s games that have a recorded prediction. The number of such games is
        shown beside each value.
      </>
    ),
    net_rating_change: "Net rating over the window minus net rating over the team's games before the window, in points per 100 possessions. Blank when the team has fewer than 5 earlier games.",
    elo_change_7d: `Change in Elo over the last 7 days. ${ELO_HELP}`,
    elo_change_14d: `Change in Elo over the last 14 days. ${ELO_HELP}`,
    schedule_strength: 'Average win percentage of the opponents faced in the window.',
  };

  return (
    <div className="space-y-6">
      <header className="space-y-2">
        <h1 className="text-2xl font-bold text-slate-100">Momentum Board</h1>
        <p className="text-sm text-slate-400 max-w-3xl">
          Which teams are trending up or down. The momentum score blends recent form against the opponents faced,
          the net rating trend, how a team did against the model&apos;s expectation, and its Elo change. {data.season}{' '}
          season, through {data.through_date}.
        </p>
      </header>

      <div className="flex flex-wrap items-end gap-x-6 gap-y-3">
        <div>
          <div id={`${sortId}-window`} className="mb-1 text-xs font-semibold text-slate-300">
            Games in window
          </div>
          <div role="group" aria-labelledby={`${sortId}-window`} className="inline-flex gap-1.5">
            {windows.map((n) => (
              <button
                key={n}
                type="button"
                aria-pressed={windowSize === n}
                onClick={() => setWindowSize(n)}
                className={`min-h-8 rounded-md px-3 py-1 text-xs font-semibold transition-colors focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-accent ${
                  windowSize === n
                    ? 'bg-accent-600 text-white shadow-sm'
                    : 'bg-slate-800/80 text-slate-300 hover:text-slate-100 hover:bg-slate-800'
                }`}
              >
                Last {n}
              </button>
            ))}
          </div>
        </div>
        <div>
          <label htmlFor={sortId} className="mb-1 block text-xs font-semibold text-slate-300">
            Sort by
          </label>
          <select
            id={sortId}
            value={sort.key}
            onChange={(e) => setSortKey(e.target.value)}
            className="min-h-8 rounded-md border border-slate-700 bg-surface-raised px-2 py-1 text-xs text-slate-100 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-accent"
          >
            {sortOptions.map((o) => (
              <option key={o.key} value={o.key}>
                {sortLabel(o)}
              </option>
            ))}
          </select>
        </div>
      </div>

      <p role="status" className="sr-only">
        Showing the last {windowSize} games, sorted by {sortLabel(sort)}. {rankedRows} of {board.rows.length} teams
        ranked.
      </p>

      {rankedRows < board.rows.length && board.note && (
        <p
          data-testid="momentum-note"
          className="rounded-lg border border-slate-700 bg-surface-raised/60 px-3 py-2 text-sm text-slate-200"
        >
          {board.note}
        </p>
      )}

      <div ref={setScrollEl} data-testid="momentum-scroll" className="relative overflow-x-auto rounded-xl border border-slate-800">
        <table className="w-full min-w-[44rem] text-sm">
          <caption className="sr-only">
            Momentum board, last {windowSize} games, sorted by {sortLabel(sort)}
          </caption>
          <thead className="bg-surface-raised/80 text-xs text-slate-300">
            <tr>
              <Th
                label="Team"
                help="Team and record. Select a team name to open its details: drivers, flags, schedule and rank history."
              />
              <Th
                label="Rank"
                help="Position by momentum score among teams that have played the full window. A team with fewer games shows its games so far instead and has no rank."
              />
              <Th
                label="Rank change"
                help={`Places gained (up) or lost (down) in the momentum rank compared with 7 days earlier. It needs weekly history, which starts ${historyStarts}.`}
              />
              <Th
                label="Momentum score"
                help={`Higher means stronger recent form than other ranked teams; 0 is average. ${wp(weights.form)} form against opponents faced, ${wp(weights.trend)} net rating trend, ${wp(weights.residual)} beating model expectation, ${wp(weights.elo)} Elo change.`}
              />
              {showSortColumn && (
                <Th
                  label={sortLabel(sort)}
                  help={sortHelp[sort.key] ?? sortLabel(sort)}
                />
              )}
              <Th label="Elo 7d" help={`Change in Elo over the last 7 days. ${ELO_HELP}`} />
              <Th label="Elo 14d" help={`Change in Elo over the last 14 days. ${ELO_HELP}`} />
              <Th
                label="Trend"
                align="right"
                help="Net rating (points scored minus allowed per 100 possessions) game by game across the window. Each line is scaled to that team's own range, so compare shapes, not heights."
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
                sort={sort}
                showSortColumn={showSortColumn}
                colSpan={colSpan}
                teamCount={board.team_count}
                flagLabels={flagLabels}
                historyStarts={historyStarts}
                panelWidth={panelWidth}
              />
            ))}
          </tbody>
        </table>
      </div>

      <MethodsPanel methods={data.methods} />
    </div>
  );
};
