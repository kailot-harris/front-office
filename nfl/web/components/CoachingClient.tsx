'use client';

import { useState, useMemo } from 'react';
import { CoachingDataset, CoachingFigure, CoachProfile } from '@/lib/types';
import { TeamLogo } from './TeamLogo';
import { Search, Zap, Clock, SlidersHorizontal, ChevronRight, Download } from 'lucide-react';
import { exportToCsv } from '@/lib/exportToCsv';
import { GlossaryTerm } from './Glossary';
import { HowToRead } from './HowToRead';

interface CoachingClientProps {
  data: CoachingDataset;
}

/** The measured figures, in table order. Every value comes from coaching_profiles.json. */
type FigureKey =
  | 'fourth_down_go_rate'
  | 'nfl4th_go_when_recommended'
  | 'nfl4th_go_when_not_recommended'
  | 'pass_rate_over_expected'
  | 'early_down_pass_rate'
  | 'play_action_rate'
  | 'seconds_per_play'
  | 'challenge_success_rate'
  | 'epa_after_own_timeout'
  | 'timeouts_q1_q3_share'
  | 'unused_timeouts_close_losses';

interface FigureSpec {
  key: FigureKey;
  label: string;
  short: string;
  digits: number;
  suffix: string;
  signed?: boolean;
  definition: string;
}

const FIGURES: FigureSpec[] = [
  {
    key: 'fourth_down_go_rate',
    label: '4th-down go rate',
    short: '4th Go %',
    digits: 1,
    suffix: '%',
    definition:
      'Share of 4th downs where the team ran a play rather than punting or attempting a field goal. Leaves out the last 2:00 of either half and 4th downs at or inside the opponent’s 2-yard line.',
  },
  {
    key: 'nfl4th_go_when_recommended',
    label: 'nfl4th: went when it should',
    short: 'Went (Should)',
    digits: 1,
    suffix: '%',
    definition:
      'Using the nfl4th model: of 4th downs where going for it had the higher estimated win probability, the share where the team went. 4th downs the model gives no estimate for are left out.',
  },
  {
    key: 'nfl4th_go_when_not_recommended',
    label: 'nfl4th: went when it shouldn’t',
    short: 'Went (Shouldn’t)',
    digits: 1,
    suffix: '%',
    definition:
      'Of 4th downs where kicking (punt or field goal) had the higher estimated win probability, the share where the team went.',
  },
  {
    key: 'pass_rate_over_expected',
    label: 'Pass rate over expected',
    short: 'PROE',
    digits: 1,
    suffix: ' pts',
    signed: true,
    definition:
      'Mean of nflverse pass_oe (percentage points above or below the expected pass rate) on 1st and 2nd down with win probability between 20% and 80%.',
  },
  {
    key: 'early_down_pass_rate',
    label: 'Early-down pass rate',
    short: 'Early Pass %',
    digits: 1,
    suffix: '%',
    definition: 'Dropbacks / (dropbacks + runs) on 1st and 2nd down with win probability between 20% and 80%.',
  },
  {
    key: 'play_action_rate',
    label: 'Play-action rate',
    short: 'Play-Action %',
    digits: 1,
    suffix: '%',
    definition:
      'Play-action dropbacks / charted dropbacks, from FTN charting (n is the charted-dropback count). FTN charting can trail play-by-play by a week.',
  },
  {
    key: 'seconds_per_play',
    label: 'Seconds per play',
    short: 'Sec / Play',
    digits: 1,
    suffix: 's',
    definition:
      'Mean game-clock seconds between consecutive offensive snaps (runs and passes) on the same drive, with the score within 7 and both snaps outside the last 2:00 of either half.',
  },
  {
    key: 'challenge_success_rate',
    label: 'Challenge success',
    short: 'Challenge %',
    digits: 1,
    suffix: '%',
    definition:
      'Successful coach challenges / coach challenges. A coach challenge is a play whose nflverse description says the team challenged (for example “Indianapolis challenged …”); booth reviews by the Replay Official are not counted. Success means the ruling was reversed (nflverse replay_or_challenge_result).',
  },
  {
    key: 'epa_after_own_timeout',
    label: 'EPA after own timeout',
    short: 'EPA After TO',
    digits: 3,
    suffix: '',
    signed: true,
    definition:
      'Mean EPA on the next snap after a timeout the team called, counted when that snap is the team’s own offensive play (same game and half).',
  },
  {
    key: 'timeouts_q1_q3_share',
    label: 'Share of timeouts in quarters 1-3',
    short: 'TO Q1-3 %',
    digits: 1,
    suffix: '%',
    definition:
      'Timeouts the team called in quarters 1-3 / all timeouts it called. Timeouts charged for a lost challenge are not counted as called.',
  },
  {
    key: 'unused_timeouts_close_losses',
    label: 'Unused timeouts when trailing at the end',
    short: 'Unused TOs',
    digits: 2,
    suffix: '',
    definition: 'Mean timeouts the team still had on the last play of games it lost by 8 points or fewer.',
  },
];

const LABEL_BY_KEY: Record<string, string> = Object.fromEntries(FIGURES.map((f) => [f.key, f.label]));

function insufficientText(fig: CoachingFigure): string {
  return `insufficient sample (n = ${fig.n}, needs ${fig.min_n})`;
}

function formatFigure(fig: CoachingFigure, spec: FigureSpec): string {
  if (fig.value === null) return insufficientText(fig);
  const sign = spec.signed && fig.value > 0 ? '+' : '';
  return `${sign}${fig.value.toFixed(spec.digits)}${spec.suffix}`;
}

function FigureCell({ fig, spec }: { fig: CoachingFigure; spec: FigureSpec }) {
  if (fig.value === null) {
    return (
      <span className="text-[10px] font-sans text-slate-500 whitespace-normal" data-insufficient>
        {insufficientText(fig)}
      </span>
    );
  }
  return <span className="text-slate-200">{formatFigure(fig, spec)}</span>;
}

/** Sort with nulls always last, whatever the direction. */
function compareFigures(a: CoachingFigure, b: CoachingFigure, asc: boolean): number {
  if (a.value === null && b.value === null) return 0;
  if (a.value === null) return 1;
  if (b.value === null) return -1;
  return asc ? a.value - b.value : b.value - a.value;
}

function topBy(coaches: CoachProfile[], key: FigureKey, n = 3): CoachProfile[] {
  return [...coaches]
    .filter((c) => c[key].value !== null)
    .sort((a, b) => compareFigures(a[key], b[key], false))
    .slice(0, n);
}

export default function CoachingClient({ data }: CoachingClientProps) {
  const coaches = data.teams;
  const [searchQuery, setSearchQuery] = useState('');
  const [selectedCoach, setSelectedCoach] = useState<CoachProfile | null>(null);
  const [sortField, setSortField] = useState<FigureKey | 'tenure_seasons'>('fourth_down_go_rate');
  const [sortAsc, setSortAsc] = useState(false);

  const filteredCoaches = useMemo(() => {
    const q = searchQuery.toLowerCase();
    return coaches
      .filter((c) => c.head_coach.toLowerCase().includes(q) || c.team.toLowerCase().includes(q))
      .sort((a, b) => {
        if (sortField === 'tenure_seasons') {
          return sortAsc ? a.tenure_seasons - b.tenure_seasons : b.tenure_seasons - a.tenure_seasons;
        }
        return compareFigures(a[sortField], b[sortField], sortAsc);
      });
  }, [coaches, searchQuery, sortField, sortAsc]);

  const topGoRate = useMemo(() => topBy(coaches, 'fourth_down_go_rate'), [coaches]);
  const topProe = useMemo(() => topBy(coaches, 'pass_rate_over_expected'), [coaches]);
  const longestTenured = useMemo(
    () => [...coaches].sort((a, b) => b.tenure_seasons - a.tenure_seasons).slice(0, 3),
    [coaches],
  );

  const buildDate = data.generated_at.slice(0, 10);

  const toggleSort = (key: FigureKey | 'tenure_seasons') => {
    if (sortField === key) setSortAsc(!sortAsc);
    else {
      setSortField(key);
      setSortAsc(false);
    }
  };

  const handleExportCsv = () => {
    const rows = filteredCoaches.map((c) => {
      const row: Record<string, unknown> = {
        team: c.team,
        head_coach: c.head_coach,
        since_week: c.since_week,
        games_coached: c.games_coached,
        tenure_seasons: c.tenure_seasons,
        career_record: c.career_record,
        super_bowl_wins: c.super_bowl_wins,
      };
      for (const f of FIGURES) {
        row[f.key] = c[f.key].value;
        row[`${f.key}_n`] = c[f.key].n;
        row[`${f.key}_min_n`] = c[f.key].min_n;
      }
      return row;
    });
    exportToCsv(
      rows,
      [
        { key: 'team', label: 'Team' },
        { key: 'head_coach', label: 'Head Coach' },
        { key: 'since_week', label: 'Since Week' },
        { key: 'games_coached', label: 'Games Coached' },
        { key: 'tenure_seasons', label: 'Tenure (Seasons)' },
        { key: 'career_record', label: 'Career Record (1999+)' },
        { key: 'super_bowl_wins', label: 'Super Bowl Wins (1999+)' },
        ...FIGURES.flatMap((f) => [
          { key: f.key, label: f.label },
          { key: `${f.key}_n`, label: `${f.label} n` },
          { key: `${f.key}_min_n`, label: `${f.label} min n` },
        ]),
      ],
      'nfl-coaching-profiles',
    );
  };

  const sortArrow = (key: FigureKey | 'tenure_seasons') => (sortField === key ? (sortAsc ? ' ↑' : ' ↓') : '');

  return (
    <div className="space-y-8">
      {/* Header */}
      <div className="relative pb-6">
        <div>
          <div className="flex flex-wrap items-center gap-2 mb-1">
            <span className="text-xs font-mono font-medium text-emerald-400 bg-emerald-950/60 border border-emerald-800/60 px-2 py-0.5 rounded-full">
              Coaching Analysis & In-Game Decisions
            </span>
            <span className="text-xs font-mono text-slate-400">{coaches.length} NFL Head Coaches</span>
            <span className="text-xs font-mono text-slate-400" data-testid="coaching-build-info">
              {data.season} season, through week {data.through_week} &middot; built {buildDate}
            </span>
          </div>
          <h1 className="text-2xl sm:text-3xl font-bold tracking-tight text-white">
            <span className="text-emerald-400">NFL</span> Head Coach Decision Profiles
          </h1>
          <p className="text-slate-400 text-sm mt-1 max-w-3xl">
            Measured {data.season} decision tendencies for each team&rsquo;s current head coach: 4th-down go rate,
            Pass Rate Over Expected (<GlossaryTerm term="PROE" className="text-slate-300" />), play-action rate, pace,
            challenges and timeouts. Every figure is computed from nflverse data on each daily build.
          </p>
        </div>
        <div className="absolute bottom-0 left-0 right-0 h-[2px] bg-gradient-to-r from-emerald-400 via-emerald-500/40 to-transparent" />
      </div>

      <HowToRead pageKey="coaching">
        <p>
          Each card covers only the games coached by the team&rsquo;s current head coach this season (&ldquo;since week
          N&rdquo;), taken from the nflverse schedule. Every number is measured from nflverse play-by-play, FTN
          charting and the nfl4th model, and carries its sample size n. A figure whose sample is below its minimum is
          shown as &ldquo;insufficient sample (n = X, needs Y)&rdquo; instead of a number; no default or league
          average is ever filled in.
        </p>
        <h3 className="mt-3 mb-1 font-semibold text-slate-300">Definitions</h3>
        <dl className="space-y-1.5">
          {FIGURES.map((f) => (
            <div key={f.key}>
              <dt className="inline font-semibold text-slate-300">{f.label}: </dt>
              <dd className="inline">{f.definition}</dd>
            </div>
          ))}
          <div>
            <dt className="inline font-semibold text-slate-300">Tenure with team: </dt>
            <dd className="inline">Consecutive seasons, ending this one, as this team&rsquo;s head coach, from schedules.</dd>
          </div>
          <div>
            <dt className="inline font-semibold text-slate-300">Career record and Super Bowl wins: </dt>
            <dd className="inline">
              Regular-season plus playoff W-L-T across all teams, and Super Bowls won, from nflverse schedules, which
              start in {data.history_start_season}. A coach whose first game in that data is in{' '}
              {data.history_start_season} is flagged as possibly truncated: games before {data.history_start_season}{' '}
              are not counted.
            </dd>
          </div>
        </dl>
        <p className="mt-2">
          The two nfl4th figures are model estimates: they compare a team&rsquo;s choice with the nfl4th package&rsquo;s
          estimated win probability for going for it versus kicking, not with a known right answer.
        </p>
        <h3 className="mt-3 mb-1 font-semibold text-slate-300">Minimum samples</h3>
        <p>
          minimum = max(floor, ceiling(per-game rate &times; games coached)). Below it the figure is shown as
          &ldquo;insufficient sample (n = X, needs Y)&rdquo;.
        </p>
        <table className="mt-1 text-[11px] font-mono" data-testid="coaching-min-sample-table">
          <thead>
            <tr className="text-slate-300">
              <th className="pr-4 text-left font-semibold">Figure</th>
              <th className="pr-4 text-right font-semibold">Per game</th>
              <th className="text-right font-semibold">Floor</th>
            </tr>
          </thead>
          <tbody>
            {data.min_sample_rules.map((r) => (
              <tr key={r.metric}>
                <td className="pr-4">{LABEL_BY_KEY[r.metric] ?? r.metric}</td>
                <td className="pr-4 text-right">{r.per_game === null ? 'fixed' : r.per_game}</td>
                <td className="text-right">{r.floor}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </HowToRead>

      {/* KPI Cards / Leaders */}
      <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
        <div className="bg-surface-raised/90 border border-slate-800 rounded-xl p-4 shadow-lg">
          <div className="flex items-center justify-between pb-3 border-b border-slate-800 mb-3">
            <div className="flex items-center gap-2">
              <Zap className="w-4 h-4 text-emerald-400" />
              <h2 className="text-sm font-semibold text-white">4th-Down Go Rate Leaders</h2>
            </div>
            <span className="text-[11px] sm:text-[10px] font-mono text-slate-400">Went for it</span>
          </div>
          <div className="space-y-2">
            {topGoRate.map((c, i) => (
              <div
                key={c.team}
                onClick={() => setSelectedCoach(c)}
                className="flex items-center justify-between p-2 rounded-lg bg-surface/50 hover:bg-slate-800/60 cursor-pointer border border-slate-800/60 transition-colors"
              >
                <div className="flex items-center gap-2.5">
                  <span className="text-xs font-mono font-bold text-slate-500 w-4">#{i + 1}</span>
                  <TeamLogo team={c.team} size="sm" />
                  <div>
                    <div className="text-xs font-medium text-white">{c.head_coach}</div>
                    <div className="text-[11px] sm:text-[10px] text-slate-400 font-mono">
                      {c.team} &bull; n = {c.fourth_down_go_rate.n}
                    </div>
                  </div>
                </div>
                <span className="text-xs font-mono font-bold text-emerald-400">
                  {formatFigure(c.fourth_down_go_rate, FIGURES[0])}
                </span>
              </div>
            ))}
          </div>
        </div>

        <div className="bg-surface-raised/90 border border-slate-800 rounded-xl p-4 shadow-lg">
          <div className="flex items-center justify-between pb-3 border-b border-slate-800 mb-3">
            <div className="flex items-center gap-2">
              <SlidersHorizontal className="w-4 h-4 text-cyan-400" />
              <h2 className="text-sm font-semibold text-white">
                Pass Rate Over Expected (<GlossaryTerm term="PROE" className="text-cyan-300" />)
              </h2>
            </div>
            <span className="text-[11px] sm:text-[10px] font-mono text-slate-400">Early downs</span>
          </div>
          <div className="space-y-2">
            {topProe.map((c, i) => (
              <div
                key={c.team}
                onClick={() => setSelectedCoach(c)}
                className="flex items-center justify-between p-2 rounded-lg bg-surface/50 hover:bg-slate-800/60 cursor-pointer border border-slate-800/60 transition-colors"
              >
                <div className="flex items-center gap-2.5">
                  <span className="text-xs font-mono font-bold text-slate-500 w-4">#{i + 1}</span>
                  <TeamLogo team={c.team} size="sm" />
                  <div>
                    <div className="text-xs font-medium text-white">{c.head_coach}</div>
                    <div className="text-[11px] sm:text-[10px] text-slate-400 font-mono">
                      {c.team} &bull; n = {c.pass_rate_over_expected.n}
                    </div>
                  </div>
                </div>
                <span className="text-xs font-mono font-bold text-cyan-400">
                  {formatFigure(c.pass_rate_over_expected, FIGURES[3])}
                </span>
              </div>
            ))}
          </div>
        </div>

        <div className="bg-surface-raised/90 border border-slate-800 rounded-xl p-4 shadow-lg">
          <div className="flex items-center justify-between pb-3 border-b border-slate-800 mb-3">
            <div className="flex items-center gap-2">
              <Clock className="w-4 h-4 text-indigo-400" />
              <h2 className="text-sm font-semibold text-white">Franchise Stability</h2>
            </div>
            <span className="text-[11px] sm:text-[10px] font-mono text-slate-400">Seasons with team</span>
          </div>
          <div className="space-y-2">
            {longestTenured.map((c, i) => (
              <div
                key={c.team}
                onClick={() => setSelectedCoach(c)}
                className="flex items-center justify-between p-2 rounded-lg bg-surface/50 hover:bg-slate-800/60 cursor-pointer border border-slate-800/60 transition-colors"
              >
                <div className="flex items-center gap-2.5">
                  <span className="text-xs font-mono font-bold text-slate-500 w-4">#{i + 1}</span>
                  <TeamLogo team={c.team} size="sm" />
                  <div>
                    <div className="text-xs font-medium text-white">{c.head_coach}</div>
                    <div className="text-[11px] sm:text-[10px] text-slate-400 font-mono">
                      {c.team} &bull; career {c.career_record}
                      {c.career_possibly_truncated ? '*' : ''}
                    </div>
                  </div>
                </div>
                <span className="text-xs font-mono font-bold text-indigo-400">{c.tenure_seasons} Seasons</span>
              </div>
            ))}
          </div>
        </div>
      </div>

      {/* Search */}
      <div className="flex flex-col sm:flex-row gap-3 items-center justify-between bg-surface-raised/90 border border-slate-800 p-3.5 rounded-xl">
        <div className="relative w-full sm:w-80">
          <Search className="w-4 h-4 text-slate-400 absolute left-3 top-1/2 -translate-y-1/2" />
          <input
            type="text"
            placeholder="Search coach or team..."
            value={searchQuery}
            onChange={(e) => setSearchQuery(e.target.value)}
            className="w-full bg-surface border border-slate-800 rounded-lg pl-9 pr-3 py-1.5 text-xs text-white placeholder-slate-500 focus:outline-none focus:border-emerald-500"
          />
        </div>
        <span className="text-[11px] font-mono text-slate-400">
          * career figures possibly truncated: first game in the data is in {data.history_start_season}
        </span>
      </div>

      {/* Coaches Table */}
      <div className="bg-surface-raised/90 border border-slate-800 rounded-xl overflow-hidden shadow-xl">
        <div className="flex items-center justify-end px-4 py-2 border-b border-slate-800">
          <button
            type="button"
            onClick={handleExportCsv}
            title="Export CSV"
            aria-label="Export coaching table as CSV"
            data-export-exclude
            className="p-1.5 rounded-lg border border-slate-800 text-slate-400 hover:text-white hover:border-slate-600 transition-colors"
          >
            <Download className="w-3.5 h-3.5" />
          </button>
        </div>
        <div className="overflow-x-auto">
          <table className="w-full text-left text-xs font-mono" data-testid="coaching-table">
            <thead className="bg-surface/80 text-slate-400 uppercase text-[11px] sm:text-[10px] tracking-wider border-b border-slate-800">
              <tr>
                <th className="px-4 py-3">Team</th>
                <th className="px-3 py-3">Head Coach</th>
                <th
                  className="px-3 py-3 text-right cursor-pointer hover:text-white whitespace-nowrap"
                  onClick={() => toggleSort('tenure_seasons')}
                >
                  Tenure{sortArrow('tenure_seasons')}
                </th>
                <th className="px-3 py-3 whitespace-nowrap">Career</th>
                {FIGURES.map((f) => (
                  <th
                    key={f.key}
                    className="px-3 py-3 text-right cursor-pointer hover:text-white whitespace-nowrap"
                    onClick={() => toggleSort(f.key)}
                    aria-sort={sortField === f.key ? (sortAsc ? 'ascending' : 'descending') : 'none'}
                  >
                    {f.short}
                    {sortArrow(f.key)}
                  </th>
                ))}
                <th className="px-4 py-3 text-center">Action</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-slate-800/60">
              {filteredCoaches.map((c) => {
                const isSelected = selectedCoach?.team === c.team;
                return (
                  <tr
                    key={c.team}
                    onClick={() => setSelectedCoach(c)}
                    className={`hover:bg-slate-800/40 transition-colors cursor-pointer ${
                      isSelected ? 'bg-accent-950/20 border-l-2 border-accent-500' : ''
                    }`}
                  >
                    <td className="px-4 py-3">
                      <div className="flex items-center gap-2">
                        <TeamLogo team={c.team} size="xs" />
                        <span className="font-bold text-white">{c.team}</span>
                      </div>
                    </td>
                    <td className="px-3 py-3 font-sans">
                      <div className="font-semibold text-white whitespace-nowrap">{c.head_coach}</div>
                      <div className="text-[10px] font-mono text-slate-500 whitespace-nowrap">
                        since week {c.since_week ?? '—'} &middot; {c.games_coached} games
                      </div>
                    </td>
                    <td className="px-3 py-3 text-right text-slate-400 whitespace-nowrap">{c.tenure_seasons} yrs</td>
                    <td className="px-3 py-3 text-slate-400 whitespace-nowrap">
                      {c.career_record}
                      {c.career_possibly_truncated ? '*' : ''}
                    </td>
                    {FIGURES.map((f) => (
                      <td key={f.key} className="px-3 py-3 text-right min-w-[7rem]">
                        <FigureCell fig={c[f.key]} spec={f} />
                      </td>
                    ))}
                    <td className="px-4 py-3 text-center">
                      <ChevronRight className="w-4 h-4 text-slate-500 inline group-hover:text-white" />
                    </td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        </div>
      </div>

      {/* Selected Coach Card */}
      {selectedCoach && (
        <div className="bg-surface-raised/90 border border-emerald-500/50 rounded-xl p-5 shadow-2xl relative">
          <div className="flex flex-col sm:flex-row items-start sm:items-center justify-between pb-4 border-b border-slate-800 gap-4">
            <div className="flex items-center gap-4">
              <TeamLogo team={selectedCoach.team} size="xl" />
              <div>
                <h2 className="text-xl font-bold text-white flex items-center gap-2">
                  {selectedCoach.head_coach}
                  <span className="text-xs font-mono font-normal text-emerald-400 bg-emerald-950 px-2 py-0.5 rounded border border-emerald-800">
                    {selectedCoach.team} &bull; since week {selectedCoach.since_week ?? '—'} &bull;{' '}
                    {selectedCoach.games_coached} games
                  </span>
                </h2>
                <p className="text-xs text-slate-400 font-mono mt-0.5">
                  Tenure {selectedCoach.tenure_seasons} seasons &bull; Career {selectedCoach.career_record} (
                  {selectedCoach.career_games} games) &bull; {selectedCoach.super_bowl_wins} Super Bowl wins
                </p>
                {selectedCoach.career_possibly_truncated && (
                  <p className="text-[11px] text-amber-400 font-mono mt-1" data-testid="coaching-truncation-flag">
                    Career figures possibly truncated: nflverse schedules start in {data.history_start_season}, the
                    season of this coach&rsquo;s first game in the data.
                  </p>
                )}
              </div>
            </div>

            <button
              onClick={() => setSelectedCoach(null)}
              className="text-xs font-mono text-slate-400 hover:text-white px-2.5 py-1 rounded bg-slate-800"
            >
              Close Details
            </button>
          </div>

          <div className="grid grid-cols-2 sm:grid-cols-4 gap-4 pt-4">
            {FIGURES.map((f) => {
              const fig = selectedCoach[f.key];
              return (
                <div key={f.key} className="bg-surface/60 p-3 rounded-lg border border-slate-800">
                  <span className="text-[11px] sm:text-[10px] font-mono uppercase text-slate-500 block">{f.label}</span>
                  {fig.value === null ? (
                    <span className="text-[11px] font-mono text-slate-400 block mt-0.5">{insufficientText(fig)}</span>
                  ) : (
                    <>
                      <span className="text-sm font-mono font-bold text-emerald-400 block mt-0.5">
                        {formatFigure(fig, f)}
                      </span>
                      <span className="text-[10px] font-mono text-slate-500 block">n = {fig.n}</span>
                    </>
                  )}
                </div>
              );
            })}
          </div>
        </div>
      )}

      <p className="text-[11px] font-mono text-slate-500">
        Play-action data: FTN Data via nflverse (CC-BY-SA 4.0)
        {data.play_action_through_week !== null ? `, charted through week ${data.play_action_through_week}` : ''}.
        Play-by-play, schedules and 4th-down model estimates: nflverse and nfl4th.
      </p>
    </div>
  );
}
