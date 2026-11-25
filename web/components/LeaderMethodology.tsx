/**
 * /players/leaders/methodology: how qualifying minimums for the NBA League Leaders
 * panel were set (NBA_analytics#258). Every number on this page is read from
 * web/public/data/leader_methodology.json; nothing is computed or typed in.
 */
import React from 'react';
import Link from 'next/link';
import type { LeaderMethodologyMinimum, LeaderMethodologyPayload } from '@/lib/leaderMethodologyTypes';
import { LeaderMethodologyCharts } from '@/components/LeaderMethodologyCharts';

const card = 'rounded-xl border border-slate-800 bg-surface-raised/60 p-4';
const tableWrap = 'overflow-x-auto rounded-lg border border-slate-800';
const th = 'px-3 py-2 font-semibold text-left';
const td = 'px-3 py-2';
const mono = 'font-mono tabular-nums';

function fmtCorr(r: number | null, lo: number | null, hi: number | null, reason: string | null): React.ReactNode {
  if (r === null || lo === null || hi === null) {
    return (
      <span className="text-slate-500" title={reason ?? undefined}>
        —{reason ? <span className="sr-only"> ({reason})</span> : null}
      </span>
    );
  }
  return (
    <span className={`${mono} whitespace-nowrap text-slate-200`}>
      {r.toFixed(2)} <span className="text-slate-400">[{lo.toFixed(2)}, {hi.toFixed(2)}]</span>
    </span>
  );
}

const GROUP_LABELS: Record<LeaderMethodologyMinimum['group'], string> = {
  counting: 'Counting',
  shooting: 'Shooting',
  rates: 'Rates',
  rapm: 'RAPM',
};

const BUCKET_LABELS: Record<LeaderMethodologyMinimum['bucket'], string> = {
  early: 'Early',
  middle: 'Middle',
  late: 'Late',
  attempts: 'Attempts',
  possessions: 'Possessions',
};

function formatSeasonSpan(seasons: number[]): string {
  if (!seasons.length) return '—';
  return seasons.join(', ');
}

export function LeaderMethodology({ data }: { data: LeaderMethodologyPayload }) {
  const noiseRows = data.minimums.filter((m) => m.noise_note);
  const { scaling_example: ex } = data;

  return (
    <article className="space-y-8 text-sm text-slate-300 leading-relaxed">
      {/* Header */}
      <header className="space-y-3 border-b border-slate-800 pb-6">
        <div className="flex flex-wrap items-center justify-between gap-2 text-xs text-slate-400">
          <Link href="/players" className="text-orange-400 hover:text-orange-300 font-semibold">
            &larr; Back to League Leaders on /players
          </Link>
          <span>
            Study run {data.study_run_date ?? 'unavailable'} · Commit{' '}
            <code className="text-slate-300">{data.source_commit.slice(0, 12)}</code>
          </span>
        </div>
        <h1 className="text-2xl sm:text-3xl font-black text-white">
          League Leaders Methodology: Qualifying Minimums
        </h1>
        <p className="text-slate-300 max-w-3xl">
          How each qualifying bar on the{' '}
          <Link href="/players" className="text-orange-400 hover:text-orange-300 underline underline-offset-2">
            League Leaders panel
          </Link>{' '}
          was set from the {data.issue} reliability study ({data.player_seasons.toLocaleString('en-US')} regular-season
          player-seasons).
        </p>
      </header>

      {/* 1. Why minimums */}
      <section id="why-minimums" aria-labelledby="why-minimums-h" className="space-y-3">
        <h2 id="why-minimums-h" className="text-lg font-semibold text-slate-100">
          1. Why minimums
        </h2>
        <div className={`${card} space-y-2`}>
          <p>
            A player with a handful of big games should not top a season leader list. At the same time, a single
            game-share rule for every stat is too strict for stats that settle quickly (like points or rebounds per game)
            and too loose for noisy stats (like steals per game, three-point percentage, or RAPM).
          </p>
          <p>
            Instead of one blanket cutoff, each stat has its own full-season bar matched to how quickly its sample
            stabilizes, scaled linearly as the season progresses.
          </p>
        </div>
      </section>

      {/* 2. Method */}
      <section id="method" aria-labelledby="method-h" className="space-y-3">
        <h2 id="method-h" className="text-lg font-semibold text-slate-100">
          2. Method, in plain language
        </h2>
        <div className={`${card} space-y-3`}>
          <ul className="list-disc pl-5 space-y-2">
            <li>
              <strong className="text-slate-100">Split-half reliability:</strong> Each player-season&rsquo;s games are
              ordered by date; odd-numbered games form one half and even-numbered games form the other. At sample size{' '}
              <code>n</code>, the stat is computed on each half and correlated across players (Pearson <code>r</code>).
            </li>
            <li>
              <strong className="text-slate-100">Spearman-Brown projection:</strong>{' '}
              <code>2r / (1 + r)</code> projects the reliability of a full <code>2n</code>-unit sample from the{' '}
              <code>n</code>-unit split-half correlation.
            </li>
            <li>
              <strong className="text-slate-100">Rest-of-season check:</strong> Compares a player&rsquo;s first{' '}
              <code>n</code> units against all remaining games that season, using only player-seasons whose remainder
              also holds at least <code>n</code> units.
            </li>
            <li>
              <strong className="text-slate-100">95% bootstrap bands:</strong> Player-seasons are resampled with
              replacement ({data.settings.n_boot.toLocaleString('en-US')} resamples, seed {data.settings.seed}), and
              the 2.5th and 97.5th percentiles form the 95% interval. Points with fewer than{' '}
              {data.settings.min_players_per_point} player-seasons are omitted.
            </li>
            <li>
              <strong className="text-slate-100">Seasons used:</strong> NBA regular seasons{' '}
              {formatSeasonSpan(data.settings.seasons)} ({data.player_seasons.toLocaleString('en-US')} player-seasons).
              No values are imputed.
            </li>
          </ul>
        </div>
      </section>

      {/* 3. Curves */}
      <section id="curves" aria-labelledby="curves-h" className="space-y-3">
        <h2 id="curves-h" className="text-lg font-semibold text-slate-100">
          3. Reliability curves
        </h2>
        <LeaderMethodologyCharts data={data} />
      </section>

      {/* 4. Minimums */}
      <section id="minimums" aria-labelledby="minimums-h" className="space-y-3">
        <h2 id="minimums-h" className="text-lg font-semibold text-slate-100">
          4. Owner-chosen minimums
        </h2>
        <div className={`${card} space-y-2`}>
          <p className="text-slate-200 font-medium">
            The owner chose each minimum below after reviewing the reliability curves; the study measured reliability
            only and did not choose them.
          </p>
          <p>
            Counting stats fall into early, middle, and late game-count buckets (with turnovers per game also carrying a
            minutes floor). Shooting percentages use separate attempt minimums per shot type. Rates use early, middle,
            and late minute buckets, and RAPM uses possessions per side.
          </p>
        </div>

        <div className={tableWrap} role="region" aria-label="Qualifying minimums and reliability">
          <table className="w-full text-xs">
            <thead className="bg-slate-900/80 text-slate-400">
              <tr>
                <th scope="col" className={th}>Stat</th>
                <th scope="col" className={th}>Group</th>
                <th scope="col" className={th}>Bucket</th>
                <th scope="col" className={th}>Full-season minimum</th>
                <th scope="col" className={th}>Split-half r [95%]</th>
                <th scope="col" className={th}>Spearman-Brown [95%]</th>
                <th scope="col" className={th}>Rest-of-season r [95%]</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-slate-800/70">
              {data.minimums.map((m) => (
                <tr key={m.key} data-testid={`minimum-row-${m.key}`} className="hover:bg-slate-900/40">
                  <td className={`${td} font-medium text-slate-100`}>
                    {m.label}
                    {m.noise_note && (
                      <span className="ml-1.5 inline-block rounded bg-amber-500/15 px-1.5 py-0.5 text-[10px] font-semibold text-amber-300">
                        noise note
                      </span>
                    )}
                  </td>
                  <td className={td}>{GROUP_LABELS[m.group]}</td>
                  <td className={td}>{BUCKET_LABELS[m.bucket]}</td>
                  <td className={`${td} ${mono} text-orange-300`}>
                    {m.minimum_full_season.toLocaleString('en-US')} {m.unit_label}
                    {m.minimum_minutes_full_season
                      ? ` + ${m.minimum_minutes_full_season.toLocaleString('en-US')} min`
                      : ''}
                  </td>
                  <td className={td}>
                    {fmtCorr(
                      m.reliability.split_half_r,
                      m.reliability.split_half_lo,
                      m.reliability.split_half_hi,
                      null,
                    )}
                  </td>
                  <td className={td}>
                    {fmtCorr(
                      m.reliability.spearman_brown_r,
                      m.reliability.spearman_brown_lo,
                      m.reliability.spearman_brown_hi,
                      m.reliability.spearman_brown_null_reason,
                    )}
                  </td>
                  <td className={td}>
                    {fmtCorr(
                      m.reliability.rest_of_season_r,
                      m.reliability.rest_of_season_lo,
                      m.reliability.rest_of_season_hi,
                      m.reliability.rest_of_season_null_reason,
                    )}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
        <p className="text-xs text-slate-400">
          Note: 3-point % Spearman-Brown at its minimum is omitted because the study grid does not evaluate half of
          that attempt count; its exact split-half and rest-of-season correlations at the full minimum are shown.
          Rest-of-season checks were not run for RAPM because RAPM is a joint ridge fit over all players.
        </p>
      </section>

      {/* 5. Scaling */}
      <section id="scaling" aria-labelledby="scaling-h" className="space-y-3">
        <h2 id="scaling-h" className="text-lg font-semibold text-slate-100">
          5. In-season scaling
        </h2>
        <div className={`${card} space-y-3`}>
          <p>
            Every full-season minimum scales linearly with the player&rsquo;s current team&rsquo;s games played over an{' '}
            {ex.base_games}-game season:
          </p>
          <p className="rounded bg-slate-900/80 px-3 py-2 font-mono text-xs text-orange-300">
            required = minimum &times; team_games_played / {ex.base_games}
          </p>
          <p className="text-xs text-slate-400">
            Worked example at {ex.team_games_played} team games played ({ex.team_games_played} / {ex.base_games}):
          </p>
          <ul className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-2 text-xs">
            {ex.examples.map((item) => (
              <li key={item.key} className="rounded border border-slate-800 bg-slate-900/50 px-3 py-2">
                <span className="font-semibold text-slate-100">{item.label}:</span>{' '}
                <span className={mono}>
                  {item.minimum_full_season.toLocaleString('en-US')} &rarr; {item.required.toLocaleString('en-US')}{' '}
                  {item.unit_label}
                </span>
              </li>
            ))}
          </ul>
        </div>
      </section>

      {/* 6. Noise notes */}
      <section id="noise-notes" aria-labelledby="noise-notes-h" className="space-y-3">
        <h2 id="noise-notes-h" className="text-lg font-semibold text-slate-100">
          6. Why some cards carry a noise note
        </h2>
        <div className={`${card} space-y-3`}>
          <p>
            Even at full-season qualifying minimums, shooting percentages driven by three-point variance and single-season
            RAPM retain substantial noise. Those cards carry a warning banner so readers treat the exact ordering as
            rough:
          </p>
          <ul className="space-y-1.5 text-xs">
            {noiseRows.map((m) => (
              <li key={m.key} className="flex flex-wrap items-baseline justify-between gap-2 border-t border-slate-800/70 pt-1.5">
                <span className="font-semibold text-amber-300">{m.label}</span>
                <span className="text-slate-300">
                  Minimum {m.minimum_full_season.toLocaleString('en-US')} {m.unit_label} &middot; split-half r{' '}
                  {fmtCorr(
                    m.reliability.split_half_r,
                    m.reliability.split_half_lo,
                    m.reliability.split_half_hi,
                    null,
                  )}
                  {m.reliability.spearman_brown_r !== null && (
                    <>
                      {' '}
                      &middot; Spearman-Brown{' '}
                      {fmtCorr(
                        m.reliability.spearman_brown_r,
                        m.reliability.spearman_brown_lo,
                        m.reliability.spearman_brown_hi,
                        null,
                      )}
                    </>
                  )}
                </span>
              </li>
            ))}
          </ul>
        </div>
      </section>

      {/* 7. Caveats & Source */}
      <section id="caveats" aria-labelledby="caveats-h" className="space-y-3">
        <h2 id="caveats-h" className="text-lg font-semibold text-slate-100">
          7. Caveats and source traceability
        </h2>
        <div className={`${card} space-y-2`}>
          <ul className="list-disc pl-5 space-y-1.5">
            <li>
              The study pool includes every player-season from deep bench to stars. Separating players near the top of a
              leader list is harder than pool-wide correlations suggest.
            </li>
            <li>
              RAPM&rsquo;s ridge shrinkage (lambda = {data.settings.rapm_lambda.toLocaleString('en-US')}) pulls
              low-exposure players toward zero in both halves, flattening its curve.
            </li>
            <li>
              The RAPM bootstrap resamples player-seasons from fitted pairs and does not refit the ridge model, so its
              intervals omit fitting uncertainty.
            </li>
            <li>Qualifying minimums are re-checked each offseason.</li>
          </ul>
          <p className="pt-2 border-t border-slate-800 text-xs text-slate-400">
            Source study: <code>{data.source_commit}</code> &middot; Run date: {data.study_run_date ?? 'unavailable'}{' '}
            &middot; SHA-256: <code className="break-all">{data.source_sha256}</code>
          </p>
        </div>
      </section>
    </article>
  );
}
