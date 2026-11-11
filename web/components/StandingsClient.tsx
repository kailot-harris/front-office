'use client';

import React, { useState, useMemo, useEffect, useRef, useCallback } from 'react';
import { TeamProjection, ModelMetadata } from '@/lib/types';
import {
  Trophy,
  TrendingUp,
  TrendingDown,
  Filter,
  ArrowUpDown,
  ArrowUp,
  ArrowDown,
  ShieldAlert,
  Award,
  BarChart2,
  Table,
  ArrowRight,
  Download,
  Flame,
  Snowflake,
  Activity,
  Grid,
} from 'lucide-react';
import { TeamLogo } from '@/components/TeamLogo';
import { PlayoffContendersBoxWhisker } from '@/components/PlayoffContendersBoxWhisker';
import { AnimatedMediaCard } from '@/components/AnimatedMediaCard';
import { exportToCsv } from '@/lib/exportToCsv';
import { NBA_ACTUAL_TEAM_RECORDS, ActualTeamRecord } from '@/lib/actualRecords';

interface StandingsClientProps {
  teams: TeamProjection[];
  metadata?: ModelMetadata;
  initialTab?: 'visualizer' | 'table' | 'divisions';
}

export type StandingsSortField =
  | 'rank'
  | 'team'
  | 'conference'
  | 'division'
  | 'ensemble_mean_wins'
  | 'win_pct'
  | 'percentile_range'
  | 'ensemble_playoff_prob'
  | 'ensemble_title_prob'
  | 'actual_record'
  | 'actual_win_pct'
  | 'current_pace'
  | 'performance_delta'
  | 'point_diff';

export interface EnrichedNbaTeam extends TeamProjection {
  actual: ActualTeamRecord;
  actual_gp: number;
  actual_win_pct: number;
  current_pace: number;
  performance_delta: number;
  point_diff: number;
}

export const StandingsClient: React.FC<StandingsClientProps> = ({ teams, initialTab = 'visualizer' }) => {
  const [activeTab, setActiveTab] = useState<'visualizer' | 'table' | 'divisions'>(initialTab);
  const [selectedConference, setSelectedConference] = useState<'All' | 'East' | 'West'>('All');
  const [selectedDivision, setSelectedDivision] = useState<string>('All');
  const [tableMode, setTableMode] = useState<'projections' | 'reality'>('projections');
  const [sortBy, setSortBy] = useState<StandingsSortField>('ensemble_mean_wins');
  const [sortOrder, setSortOrder] = useState<'asc' | 'desc'>('desc');

  // #118: at narrow viewports most of this 9-column table is off-screen with
  // no affordance. The Team column is pinned via `sticky left-0`, and this
  // scroll-fade hint on the right edge disappears once scrolled to the end.
  const scrollContainerRef = useRef<HTMLDivElement>(null);
  const [showScrollHint, setShowScrollHint] = useState(true);

  const updateScrollHint = useCallback(() => {
    const el = scrollContainerRef.current;
    if (!el) return;
    const atEnd = el.scrollLeft + el.clientWidth >= el.scrollWidth - 4;
    setShowScrollHint(el.scrollWidth > el.clientWidth && !atEnd);
  }, []);

  useEffect(() => {
    if (typeof window !== 'undefined') {
      const params = new URLSearchParams(window.location.search);
      const tabParam = params.get('view') || params.get('tab');
      if (tabParam === 'table' || tabParam === 'visualizer' || tabParam === 'divisions') {
        setActiveTab(tabParam);
      }
      const modeParam = params.get('mode');
      if (modeParam === 'reality' || modeParam === 'projections') {
        setTableMode(modeParam);
      }
    }
  }, []);

  const handleTabChange = (tab: 'visualizer' | 'table' | 'divisions') => {
    setActiveTab(tab);
    if (typeof window !== 'undefined') {
      const url = new URL(window.location.href);
      url.searchParams.set('view', tab);
      url.searchParams.delete('tab');
      window.history.replaceState(null, '', url.toString());
    }
  };

  const handleModeChange = (mode: 'projections' | 'reality') => {
    setTableMode(mode);
    if (mode === 'reality') {
      setSortBy('performance_delta');
      setSortOrder('desc');
    } else {
      setSortBy('ensemble_mean_wins');
      setSortOrder('desc');
    }
    if (typeof window !== 'undefined') {
      const url = new URL(window.location.href);
      url.searchParams.set('mode', mode);
      window.history.replaceState(null, '', url.toString());
    }
  };

  const divisions = useMemo(() => {
    const set = new Set(teams.map((t) => t.division));
    return Array.from(set).sort();
  }, [teams]);

  // Enrich teams with real actual games and win pace calculations
  const enrichedTeams: EnrichedNbaTeam[] = useMemo(() => {
    return teams.map((team) => {
      const actual = NBA_ACTUAL_TEAM_RECORDS[team.team] || {
        wins: 0,
        losses: 0,
        pointsFor: 0,
        pointsAgainst: 0,
      };
      const actual_gp = actual.wins + actual.losses;
      const actual_win_pct = actual_gp > 0 ? actual.wins / actual_gp : 0;
      const current_pace = actual_win_pct * 82;
      const performance_delta = current_pace - team.ensemble_mean_wins;
      const point_diff = actual.pointsFor - actual.pointsAgainst;

      return {
        ...team,
        actual,
        actual_gp,
        actual_win_pct,
        current_pace,
        performance_delta,
        point_diff,
      };
    });
  }, [teams]);

  // Outperformers and underperformers callouts
  const topOverperformers = useMemo(() => {
    return [...enrichedTeams]
      .filter((t) => t.actual_gp > 0)
      .sort((a, b) => b.performance_delta - a.performance_delta)
      .slice(0, 3);
  }, [enrichedTeams]);

  const topUnderperformers = useMemo(() => {
    return [...enrichedTeams]
      .filter((t) => t.actual_gp > 0)
      .sort((a, b) => a.performance_delta - b.performance_delta)
      .slice(0, 3);
  }, [enrichedTeams]);

  const filteredTeams = useMemo(() => {
    return enrichedTeams
      .filter((t) => {
        if (selectedConference !== 'All' && t.conference !== selectedConference) return false;
        if (selectedDivision !== 'All' && t.division !== selectedDivision) return false;
        return true;
      })
      .sort((a, b) => {
        let cmp = 0;
        if (sortBy === 'team') {
          cmp = a.team_name.localeCompare(b.team_name);
        } else if (sortBy === 'conference') {
          cmp = a.conference.localeCompare(b.conference) || b.ensemble_mean_wins - a.ensemble_mean_wins;
        } else if (sortBy === 'division') {
          cmp = a.division.localeCompare(b.division) || b.ensemble_mean_wins - a.ensemble_mean_wins;
        } else if (sortBy === 'rank') {
          cmp = (a.rank ?? 0) - (b.rank ?? 0);
        } else if (sortBy === 'percentile_range') {
          const rangeA = a.ensemble_p90 - a.ensemble_p10;
          const rangeB = b.ensemble_p90 - b.ensemble_p10;
          cmp = rangeA - rangeB;
        } else if (sortBy === 'actual_record') {
          cmp = (a.actual.wins - a.actual.losses) - (b.actual.wins - b.actual.losses);
        } else if (sortBy === 'actual_win_pct') {
          cmp = a.actual_win_pct - b.actual_win_pct;
        } else if (sortBy === 'current_pace') {
          cmp = a.current_pace - b.current_pace;
        } else if (sortBy === 'performance_delta') {
          cmp = a.performance_delta - b.performance_delta;
        } else if (sortBy === 'point_diff') {
          cmp = a.point_diff - b.point_diff;
        } else {
          const valA = (a[sortBy as keyof TeamProjection] as number) ?? 0;
          const valB = (b[sortBy as keyof TeamProjection] as number) ?? 0;
          cmp = valA - valB;
        }
        return sortOrder === 'desc' ? -cmp : cmp;
      });
  }, [enrichedTeams, selectedConference, selectedDivision, sortBy, sortOrder]);

  useEffect(() => {
    updateScrollHint();
  }, [updateScrollHint, filteredTeams.length, tableMode, activeTab]);

  const handleExportCsv = () => {
    if (tableMode === 'reality') {
      exportToCsv(
        filteredTeams.map((t) => ({
          team: t.team,
          team_name: t.team_name,
          conference: t.conference,
          division: t.division,
          actual_record: `${t.actual.wins}-${t.actual.losses}`,
          actual_win_pct: (t.actual_win_pct * 100).toFixed(1) + '%',
          points_for: t.actual.pointsFor,
          points_against: t.actual.pointsAgainst,
          point_diff: t.point_diff > 0 ? `+${t.point_diff}` : `${t.point_diff}`,
          projected_wins: t.ensemble_mean_wins.toFixed(1),
          current_pace_82g: t.current_pace.toFixed(1),
          performance_delta: (t.performance_delta > 0 ? '+' : '') + t.performance_delta.toFixed(1),
        })),
        [
          { key: 'team', label: 'Team' },
          { key: 'team_name', label: 'Team Name' },
          { key: 'conference', label: 'Conf' },
          { key: 'division', label: 'Div' },
          { key: 'actual_record', label: 'Actual Record' },
          { key: 'actual_win_pct', label: 'Win %' },
          { key: 'points_for', label: 'Points For' },
          { key: 'points_against', label: 'Points Against' },
          { key: 'point_diff', label: 'Point Diff' },
          { key: 'projected_wins', label: 'Projected Wins (82G)' },
          { key: 'current_pace_82g', label: '82G Win Pace' },
          { key: 'performance_delta', label: 'Performance Delta' },
        ],
        'nba-standings-vs-projections'
      );
    } else {
      exportToCsv(
        filteredTeams as unknown as Record<string, unknown>[],
        [
          { key: 'rank', label: 'Rank' },
          { key: 'team_name', label: 'Team' },
          { key: 'conference', label: 'Conf' },
          { key: 'division', label: 'Div' },
          { key: 'ensemble_mean_wins', label: 'Ensemble Wins' },
          { key: 'win_pct', label: 'Win %' },
          { key: 'ensemble_playoff_prob', label: 'Playoffs' },
          { key: 'ensemble_title_prob', label: 'Title Prob' },
        ],
        'nba-standings'
      );
    }
  };

  const handleSort = (field: StandingsSortField) => {
    if (sortBy === field) {
      setSortOrder(sortOrder === 'asc' ? 'desc' : 'asc');
    } else {
      setSortBy(field);
      // Alphabetical and rank default to asc, stats default to desc
      if (field === 'team' || field === 'conference' || field === 'division' || field === 'rank') {
        setSortOrder('asc');
      } else {
        setSortOrder('desc');
      }
    }
  };

  const renderSortIndicator = (field: StandingsSortField) => {
    if (sortBy !== field) {
      return <ArrowUpDown className="w-3.5 h-3.5 text-slate-500 opacity-40 group-hover:opacity-100 transition-opacity" />;
    }
    return sortOrder === 'asc' ? (
      <ArrowUp className="w-3.5 h-3.5 text-indigo-400 font-bold" />
    ) : (
      <ArrowDown className="w-3.5 h-3.5 text-indigo-400 font-bold" />
    );
  };

  const topTitleFavorite = [...teams].sort((a, b) => b.ensemble_title_prob - a.ensemble_title_prob)[0];
  const topWinProjected = [...teams].sort((a, b) => b.ensemble_mean_wins - a.ensemble_mean_wins)[0];
  const mostVolatileTeam = [...teams].sort((a, b) => b.ensemble_sd_wins - a.ensemble_sd_wins)[0];

  return (
    <div className="space-y-6">
      {/* Top Stat Highlights */}
      <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4">
        <div className="bg-surface-raised/60 border border-slate-800 rounded-xl p-4 flex items-center gap-3.5">
          <div className="relative flex-shrink-0">
            <div className="w-12 h-12 rounded-xl bg-surface/80 border border-slate-800 flex items-center justify-center p-1.5 shadow-inner">
              <TeamLogo team={topTitleFavorite?.team} size="lg" />
            </div>
            <div className="absolute -bottom-1 -right-1 p-1 bg-amber-500/20 text-amber-400 rounded-md border border-amber-500/30 shadow">
              <Trophy className="w-3.5 h-3.5" />
            </div>
          </div>
          <div className="min-w-0">
            <div className="text-xs text-slate-400 uppercase font-semibold">Title Favorite</div>
            <div className="text-lg font-bold text-white flex items-baseline gap-2 truncate">
              <span className="truncate">{topTitleFavorite?.team_name}</span>
              <span className="text-xs font-semibold text-amber-400 flex-shrink-0">
                {(topTitleFavorite?.ensemble_title_prob * 100).toFixed(1)}%
              </span>
            </div>
            <div className="text-xs text-slate-400">{topTitleFavorite?.ensemble_mean_wins.toFixed(1)} proj wins</div>
          </div>
        </div>

        <div className="bg-surface-raised/60 border border-slate-800 rounded-xl p-4 flex items-center gap-3.5">
          <div className="relative flex-shrink-0">
            <div className="w-12 h-12 rounded-xl bg-surface/80 border border-slate-800 flex items-center justify-center p-1.5 shadow-inner">
              <TeamLogo team={topWinProjected?.team} size="lg" />
            </div>
            <div className="absolute -bottom-1 -right-1 p-1 bg-emerald-500/20 text-emerald-400 rounded-md border border-emerald-500/30 shadow">
              <TrendingUp className="w-3.5 h-3.5" />
            </div>
          </div>
          <div className="min-w-0">
            <div className="text-xs text-slate-400 uppercase font-semibold">Top Projected Seed</div>
            <div className="text-lg font-bold text-white flex items-baseline gap-2 truncate">
              <span className="truncate">{topWinProjected?.team_name}</span>
              <span className="text-xs font-semibold text-emerald-400 flex-shrink-0">
                {topWinProjected?.ensemble_mean_wins.toFixed(1)}W
              </span>
            </div>
            <div className="text-xs text-slate-400">Win Pct {(topWinProjected?.win_pct * 100).toFixed(1)}%</div>
          </div>
        </div>

        <div className="bg-surface-raised/60 border border-slate-800 rounded-xl p-4 flex items-center gap-4">
          <div className="p-3 bg-indigo-500/10 text-indigo-400 rounded-lg flex-shrink-0">
            <Award className="w-6 h-6" />
          </div>
          <div>
            <div className="text-xs text-slate-400 uppercase font-semibold">Monte Carlo Iterations</div>
            <div className="text-xl font-bold text-white">1,000 Seasons</div>
            <div className="text-xs text-slate-400">1,230 Games / Iteration (4 Variants)</div>
          </div>
        </div>

        <div className="bg-surface-raised/60 border border-slate-800 rounded-xl p-4 flex items-center gap-3.5">
          <div className="relative flex-shrink-0">
            <div className="w-12 h-12 rounded-xl bg-surface/80 border border-slate-800 flex items-center justify-center p-1.5 shadow-inner">
              <TeamLogo team={mostVolatileTeam?.team} size="lg" />
            </div>
            <div className="absolute -bottom-1 -right-1 p-1 bg-rose-500/20 text-rose-400 rounded-md border border-rose-500/30 shadow">
              <ShieldAlert className="w-3.5 h-3.5" />
            </div>
          </div>
          <div className="min-w-0">
            <div className="text-xs text-slate-400 uppercase font-semibold">Highest Variance</div>
            <div className="text-lg font-bold text-white flex items-baseline gap-2 truncate">
              <span className="truncate">{mostVolatileTeam?.team_name}</span>
              <span className="text-xs font-semibold text-rose-400 flex-shrink-0">
                ±{mostVolatileTeam?.ensemble_sd_wins.toFixed(1)} SD
              </span>
            </div>
            <div className="text-xs text-slate-400">Range: {mostVolatileTeam?.ensemble_p10.toFixed(0)} - {mostVolatileTeam?.ensemble_p90.toFixed(0)} wins</div>
          </div>
        </div>
      </div>

      {/* League Performance Callouts Banner */}
      <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
        {/* Overperformers Podium */}
        <div className="bg-gradient-to-br from-emerald-950/30 via-surface-raised/80 to-surface-raised/60 border border-emerald-500/30 rounded-2xl p-4 shadow-lg">
          <div className="flex items-center justify-between mb-3 border-b border-emerald-500/20 pb-2">
            <div className="flex items-center gap-2">
              <div className="p-1.5 rounded-lg bg-emerald-500/20 text-emerald-400">
                <Flame className="w-4 h-4" />
              </div>
              <h3 className="text-xs font-bold font-mono uppercase tracking-wider text-emerald-300">
                League Overperformers (vs Preseason Projections)
              </h3>
            </div>
            <span className="text-[10px] font-mono px-2 py-0.5 rounded bg-emerald-500/10 text-emerald-400 border border-emerald-500/20">
              Win Pace Delta &gt; 0
            </span>
          </div>

          <div className="grid grid-cols-1 sm:grid-cols-3 gap-2.5">
            {topOverperformers.map((t, idx) => (
              <div
                key={t.team}
                className="bg-surface/70 border border-slate-800/90 rounded-xl p-3 flex flex-col justify-between hover:border-emerald-500/40 transition-colors shadow-sm"
              >
                <div className="flex items-center gap-2 mb-2">
                  <span className="text-[10px] font-mono font-bold text-slate-500 w-3">#{idx + 1}</span>
                  <TeamLogo team={t.team} size="sm" />
                  <div className="min-w-0">
                    <span className="font-bold text-xs text-white block truncate">{t.team_name}</span>
                    <span className="text-[10px] font-mono text-slate-400">
                      {t.actual.wins}-{t.actual.losses} ({(t.actual_win_pct * 100).toFixed(0)}%)
                    </span>
                  </div>
                </div>
                <div className="pt-1.5 border-t border-slate-800/80 flex items-center justify-between font-mono text-xs">
                  <span className="text-[10px] text-slate-400">Pace: {t.current_pace.toFixed(1)}W</span>
                  <span className="font-bold text-emerald-400 flex items-center gap-0.5">
                    <TrendingUp className="w-3 h-3" />
                    +{t.performance_delta.toFixed(1)}
                  </span>
                </div>
              </div>
            ))}
          </div>
        </div>

        {/* Underperformers Podium */}
        <div className="bg-gradient-to-br from-rose-950/30 via-surface-raised/80 to-surface-raised/60 border border-rose-500/30 rounded-2xl p-4 shadow-lg">
          <div className="flex items-center justify-between mb-3 border-b border-rose-500/20 pb-2">
            <div className="flex items-center gap-2">
              <div className="p-1.5 rounded-lg bg-rose-500/20 text-rose-400">
                <Snowflake className="w-4 h-4" />
              </div>
              <h3 className="text-xs font-bold font-mono uppercase tracking-wider text-rose-300">
                League Underperformers (vs Preseason Projections)
              </h3>
            </div>
            <span className="text-[10px] font-mono px-2 py-0.5 rounded bg-rose-500/10 text-rose-400 border border-rose-500/20">
              Win Pace Delta &lt; 0
            </span>
          </div>

          <div className="grid grid-cols-1 sm:grid-cols-3 gap-2.5">
            {topUnderperformers.map((t, idx) => (
              <div
                key={t.team}
                className="bg-surface/70 border border-slate-800/90 rounded-xl p-3 flex flex-col justify-between hover:border-rose-500/40 transition-colors shadow-sm"
              >
                <div className="flex items-center gap-2 mb-2">
                  <span className="text-[10px] font-mono font-bold text-slate-500 w-3">#{idx + 1}</span>
                  <TeamLogo team={t.team} size="sm" />
                  <div className="min-w-0">
                    <span className="font-bold text-xs text-white block truncate">{t.team_name}</span>
                    <span className="text-[10px] font-mono text-slate-400">
                      {t.actual.wins}-{t.actual.losses} ({(t.actual_win_pct * 100).toFixed(0)}%)
                    </span>
                  </div>
                </div>
                <div className="pt-1.5 border-t border-slate-800/80 flex items-center justify-between font-mono text-xs">
                  <span className="text-[10px] text-slate-400">Pace: {t.current_pace.toFixed(1)}W</span>
                  <span className="font-bold text-rose-400 flex items-center gap-0.5">
                    <TrendingDown className="w-3 h-3" />
                    {t.performance_delta.toFixed(1)}
                  </span>
                </div>
              </div>
            ))}
          </div>
        </div>
      </div>

      {/* View Switcher: Playoff Contenders Snapshot vs Full League Standings Table */}
      <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-4 bg-surface-raised/60 p-2.5 rounded-2xl border border-slate-800">
        <div className="flex flex-wrap sm:inline-flex rounded-xl bg-surface p-1.5 border border-slate-800/80 shadow-inner relative z-20 w-full sm:w-auto gap-1 sm:gap-0" role="tablist">
          <button
            type="button"
            role="tab"
            id="tab-btn-visualizer"
            aria-selected={activeTab === 'visualizer'}
            onClick={() => handleTabChange('visualizer')}
            className={`cursor-pointer select-none touch-manipulation flex-1 sm:flex-initial flex items-center justify-center gap-2.5 px-4 sm:px-5 py-2.5 rounded-lg text-xs sm:text-sm font-bold transition-all relative z-20 ${
              activeTab === 'visualizer'
                ? 'bg-accent-600 text-white shadow-lg shadow-accent-600/40 ring-1 ring-accent-400/50'
                : 'text-slate-400 hover:text-white hover:bg-surface-raised'
            }`}
          >
            <BarChart2 className="w-4 h-4 pointer-events-none text-amber-400" />
            <span className="pointer-events-none">Playoff Contenders (Box-Whisker)</span>
            <span
              className={`text-[10px] px-2 py-0.5 rounded font-mono pointer-events-none ${
                activeTab === 'visualizer' ? 'bg-white/20 text-white font-bold' : 'bg-slate-800 text-slate-400'
              }`}
            >
              Visualizer
            </span>
          </button>

          <button
            type="button"
            role="tab"
            id="tab-btn-table"
            aria-selected={activeTab === 'table'}
            onClick={() => handleTabChange('table')}
            className={`cursor-pointer select-none touch-manipulation flex-1 sm:flex-initial flex items-center justify-center gap-2.5 px-4 sm:px-5 py-2.5 rounded-lg text-xs sm:text-sm font-bold transition-all relative z-20 ${
              activeTab === 'table'
                ? 'bg-accent-600 text-white shadow-lg shadow-accent-600/40 ring-1 ring-accent-400/50'
                : 'text-slate-400 hover:text-white hover:bg-surface-raised'
            }`}
          >
            <Table className="w-4 h-4 pointer-events-none text-indigo-300" />
            <span className="pointer-events-none">Full Standings Table</span>
            <span
              className={`text-[10px] px-2 py-0.5 rounded font-mono pointer-events-none ${
                activeTab === 'table' ? 'bg-white/20 text-white font-bold' : 'bg-slate-800 text-slate-400'
              }`}
            >
              30 Teams
            </span>
          </button>

          <button
            type="button"
            role="tab"
            id="tab-btn-divisions"
            aria-selected={activeTab === 'divisions'}
            onClick={() => handleTabChange('divisions')}
            className={`cursor-pointer select-none touch-manipulation flex-1 sm:flex-initial flex items-center justify-center gap-2.5 px-4 sm:px-5 py-2.5 rounded-lg text-xs sm:text-sm font-bold transition-all relative z-20 ${
              activeTab === 'divisions'
                ? 'bg-accent-600 text-white shadow-lg shadow-accent-600/40 ring-1 ring-accent-400/50'
                : 'text-slate-400 hover:text-white hover:bg-surface-raised'
            }`}
          >
            <Grid className="w-4 h-4 pointer-events-none text-emerald-400" />
            <span className="pointer-events-none">6 Divisions</span>
          </button>
        </div>

        {/* Global Projections vs Reality Mode Toggle Pill */}
        <div className="inline-flex rounded-lg bg-surface p-1 border border-slate-800 self-start md:self-auto">
          <button
            type="button"
            onClick={() => handleModeChange('projections')}
            className={`cursor-pointer select-none px-3 py-1.5 text-xs font-semibold rounded-md transition-all ${
              tableMode === 'projections'
                ? 'bg-accent-600 text-white shadow-sm'
                : 'text-slate-400 hover:text-white'
            }`}
          >
            Model Projections
          </button>
          <button
            type="button"
            onClick={() => handleModeChange('reality')}
            className={`cursor-pointer select-none px-3 py-1.5 text-xs font-semibold rounded-md transition-all flex items-center gap-1.5 ${
              tableMode === 'reality'
                ? 'bg-accent-600 text-white shadow-sm'
                : 'text-slate-400 hover:text-white'
            }`}
          >
            <Activity className="w-3.5 h-3.5 text-emerald-400" />
            <span>Projections vs. Actual</span>
          </button>
        </div>

        <div className="text-xs text-slate-400 flex items-center gap-2 px-2">
          <span>Active View:</span>
          <span className="font-semibold text-slate-200">
            {activeTab === 'visualizer'
              ? 'Playoff Contenders Distribution Snapshot'
              : activeTab === 'divisions'
              ? '6 Divisions (Divisional Landscape)'
              : 'All 30 NBA Franchises (Sortable Metrics)'}
          </span>
        </div>
      </div>

      {activeTab === 'visualizer' ? (
        /* Tab 1: Playoff Contenders Box-Whisker Visualization */
        <div className="space-y-4">
          <PlayoffContendersBoxWhisker teams={teams} />

          {/* Dynamic Trajectory and Race Visualizations */}
          <div className="grid grid-cols-1 lg:grid-cols-2 gap-6 pt-2">
            <AnimatedMediaCard
              name="gif_elo_rank_bump"
              title="League-Wide Elo Rating and Rank Evolution"
              alt="Animated bump chart illustrating all 30 NBA teams Elo rating movements and ranking transitions across the season"
              caption="Tracks daily Elo rating oscillations and divisional rank transitions across all 30 NBA franchises, with reduced-motion static final standing support."
            />
            <AnimatedMediaCard
              name="gif_point_diff_race"
              title="Cumulative Point Differential Race"
              alt="Animated race chart displaying cumulative scoring differential trajectories across all 30 NBA franchises"
              caption="Cumulative game-by-game point margin trajectories showing true underlying scoring strength and separation between elite contenders and lottery teams."
            />
          </div>
          <div className="flex justify-end pt-1">
            <button
              type="button"
              onClick={() => handleTabChange('table')}
              className="cursor-pointer select-none inline-flex items-center gap-2 text-xs font-semibold text-indigo-400 hover:text-indigo-300 bg-surface-raised border border-slate-800 px-4 py-2 rounded-lg hover:bg-slate-800 transition-colors shadow"
            >
              <span>Explore All 30 Teams in Standings Table</span>
              <ArrowRight className="w-3.5 h-3.5" />
            </button>
          </div>
        </div>
      ) : activeTab === 'table' ? (
        /* Tab 2: Full Standings Table */
        <div className="space-y-4">
          {/* Filter and Control Bar */}
          <div className="bg-surface-raised/80 border border-slate-800 rounded-xl p-4 flex flex-wrap items-center justify-between gap-4">
            <div className="flex flex-wrap items-center gap-3">
              <div className="flex items-center gap-2">
                <span className="text-xs font-semibold text-slate-200">
                  {tableMode === 'reality' ? 'Projections vs. Actual Table' : 'Model Projections Table'}
                </span>
                <span className="text-slate-600">•</span>
                <span className="text-xs text-slate-400 font-mono">
                  {tableMode === 'reality' ? '82-Game Pace Benchmarking' : 'Ensemble Monte Carlo Projections'}
                </span>
              </div>

              <div className="h-4 w-px bg-slate-800 hidden sm:block" />

              <div className="flex items-center gap-2 text-slate-400 text-sm font-medium">
                <Filter className="w-4 h-4" />
                <span>Filter By:</span>
              </div>

              {/* Conference filter pills */}
              <div className="inline-flex rounded-lg bg-surface p-1 border border-slate-800">
                {(['All', 'East', 'West'] as const).map((conf) => (
                  <button
                    key={conf}
                    onClick={() => setSelectedConference(conf)}
                    className={`cursor-pointer select-none px-3 py-1.5 text-xs font-semibold rounded-md transition-all ${
                      selectedConference === conf
                        ? 'bg-accent-600 text-white shadow-sm'
                        : 'text-slate-400 hover:text-white'
                    }`}
                  >
                    {conf} {conf !== 'All' ? 'Conf' : 'Leagues'}
                  </button>
                ))}
              </div>

              {/* Division select dropdown */}
              <div className="flex items-center gap-2">
                <label className="text-xs text-slate-400">Division:</label>
                <select
                  aria-label="Filter by division"
                  value={selectedDivision}
                  onChange={(e) => setSelectedDivision(e.target.value)}
                  className="bg-surface border border-slate-800 text-xs text-slate-200 rounded-lg px-3 py-1.5 focus:outline-none focus:border-indigo-500"
                >
                  <option value="All">All Divisions</option>
                  {divisions.map((div) => (
                    <option key={div} value={div}>
                      {div}
                    </option>
                  ))}
                </select>
              </div>
            </div>

            <div className="flex items-center gap-3">
              <div className="text-xs text-slate-400">
                Showing <span className="font-bold text-slate-200">{filteredTeams.length}</span> of 30 teams
              </div>
              <button
                type="button"
                onClick={handleExportCsv}
                title="Export CSV"
                aria-label="Export standings table as CSV"
                className="p-1.5 rounded-lg border border-slate-800 text-slate-400 hover:text-white hover:border-slate-600 transition-colors"
              >
                <Download className="w-3.5 h-3.5" />
              </button>
            </div>
          </div>

          {/* Main Standings Table */}
          <div className="bg-surface-raised/70 border border-slate-800 rounded-xl shadow-xl overflow-hidden relative">
            <div ref={scrollContainerRef} onScroll={updateScrollHint} className="overflow-x-auto">
              <table className="w-full text-left text-sm border-collapse">
                <thead>
                  <tr className="bg-surface/80 border-b border-slate-800 text-slate-400 font-medium text-xs select-none">
                    <th
                      onClick={() => handleSort('rank')}
                      className="py-3.5 px-4 w-14 text-center cursor-pointer hover:text-white transition-colors group hidden sm:table-cell"
                      title="Click to sort by rank"
                    >
                      <div className="flex items-center justify-center gap-1">
                        <span className={sortBy === 'rank' ? 'text-indigo-400 font-bold' : ''}>Rank</span>
                        {renderSortIndicator('rank')}
                      </div>
                    </th>
                    <th
                      onClick={() => handleSort('team')}
                      className="py-3.5 px-4 cursor-pointer hover:text-white transition-colors group sticky left-0 z-10 bg-surface border-r border-slate-800"
                      title="Click to sort alphabetically by team name"
                    >
                      <div className="flex items-center gap-1.5">
                        <span className={sortBy === 'team' ? 'text-indigo-400 font-bold' : ''}>Team</span>
                        {renderSortIndicator('team')}
                      </div>
                    </th>
                    <th
                      onClick={() => handleSort('conference')}
                      className="py-3.5 px-3 text-center cursor-pointer hover:text-white transition-colors group hidden sm:table-cell"
                      title="Click to sort by conference"
                    >
                      <div className="flex items-center justify-center gap-1">
                        <span className={sortBy === 'conference' ? 'text-indigo-400 font-bold' : ''}>Conf</span>
                        {renderSortIndicator('conference')}
                      </div>
                    </th>
                    <th
                      onClick={() => handleSort('division')}
                      className="py-3.5 px-3 text-center cursor-pointer hover:text-white transition-colors group hidden sm:table-cell"
                      title="Click to sort by division"
                    >
                      <div className="flex items-center justify-center gap-1">
                        <span className={sortBy === 'division' ? 'text-indigo-400 font-bold' : ''}>Div</span>
                        {renderSortIndicator('division')}
                      </div>
                    </th>

                    {tableMode === 'reality' ? (
                      /* Projections vs Reality Columns */
                      <>
                        <th
                          onClick={() => handleSort('actual_record')}
                          className="py-3.5 px-3 text-center cursor-pointer hover:text-white transition-colors group"
                          title="Click to sort by actual record"
                        >
                          <div className="flex items-center justify-center gap-1.5">
                            <span className={sortBy === 'actual_record' ? 'text-indigo-400 font-bold' : ''}>
                              Actual Rec (W-L)
                            </span>
                            {renderSortIndicator('actual_record')}
                          </div>
                        </th>
                        <th
                          onClick={() => handleSort('actual_win_pct')}
                          className="py-3.5 px-3 cursor-pointer hover:text-white transition-colors text-right group"
                          title="Click to sort by actual win percentage"
                        >
                          <div className="flex items-center justify-end gap-1.5">
                            <span className={sortBy === 'actual_win_pct' ? 'text-indigo-400 font-bold' : ''}>
                              Win %
                            </span>
                            {renderSortIndicator('actual_win_pct')}
                          </div>
                        </th>
                        <th
                          onClick={() => handleSort('point_diff')}
                          className="py-3.5 px-3 cursor-pointer hover:text-white transition-colors text-right group"
                          title="Click to sort by scoring differential"
                        >
                          <div className="flex items-center justify-end gap-1.5">
                            <span className={sortBy === 'point_diff' ? 'text-indigo-400 font-bold' : ''}>
                              Point Diff
                            </span>
                            {renderSortIndicator('point_diff')}
                          </div>
                        </th>
                        <th
                          onClick={() => handleSort('ensemble_mean_wins')}
                          className="py-3.5 px-4 cursor-pointer hover:text-white transition-colors text-right group"
                          title="Click to sort by preseason projected ensemble wins"
                        >
                          <div className="flex items-center justify-end gap-1.5">
                            <span className={sortBy === 'ensemble_mean_wins' ? 'text-indigo-400 font-bold' : ''}>
                              Proj Wins (82G)
                            </span>
                            {renderSortIndicator('ensemble_mean_wins')}
                          </div>
                        </th>
                        <th
                          onClick={() => handleSort('current_pace')}
                          className="py-3.5 px-4 cursor-pointer hover:text-white transition-colors text-right group"
                          title="Click to sort by 82-game win pace"
                        >
                          <div className="flex items-center justify-end gap-1.5">
                            <span className={sortBy === 'current_pace' ? 'text-indigo-400 font-bold' : ''}>
                              Current Win Pace
                            </span>
                            {renderSortIndicator('current_pace')}
                          </div>
                        </th>
                        <th
                          onClick={() => handleSort('performance_delta')}
                          className="py-3.5 px-4 cursor-pointer hover:text-white transition-colors text-right group"
                          title="Click to sort by performance delta (Pace - Proj Wins)"
                        >
                          <div className="flex items-center justify-end gap-1.5">
                            <span className={sortBy === 'performance_delta' ? 'text-indigo-400 font-bold' : ''}>
                              Performance Delta
                            </span>
                            {renderSortIndicator('performance_delta')}
                          </div>
                        </th>
                      </>
                    ) : (
                      /* Standard Projections Model Columns */
                      <>
                        <th
                          onClick={() => handleSort('ensemble_mean_wins')}
                          className="py-3.5 px-4 cursor-pointer hover:text-white transition-colors group"
                          title="Click to sort by projected ensemble wins"
                        >
                          <div className="flex items-center gap-1.5">
                            <span className={sortBy === 'ensemble_mean_wins' ? 'text-indigo-400 font-bold' : ''}>
                              Ensemble Wins
                            </span>
                            {renderSortIndicator('ensemble_mean_wins')}
                          </div>
                        </th>
                        <th
                          onClick={() => handleSort('win_pct')}
                          className="py-3.5 px-3 cursor-pointer hover:text-white transition-colors text-right group"
                          title="Click to sort by win percentage"
                        >
                          <div className="flex items-center justify-end gap-1.5">
                            <span className={sortBy === 'win_pct' ? 'text-indigo-400 font-bold' : ''}>Win %</span>
                            {renderSortIndicator('win_pct')}
                          </div>
                        </th>
                        <th
                          onClick={() => handleSort('percentile_range')}
                          className="py-3.5 px-4 min-w-[200px] cursor-pointer hover:text-white transition-colors group"
                          title="Click to sort by distribution width (p90 - p10 variance)"
                        >
                          <div className="flex items-center gap-1.5">
                            <span className={sortBy === 'percentile_range' ? 'text-indigo-400 font-bold' : ''}>
                              10th - 90th Percentile Range
                            </span>
                            {renderSortIndicator('percentile_range')}
                          </div>
                        </th>
                        <th
                          onClick={() => handleSort('ensemble_playoff_prob')}
                          className="py-3.5 px-4 cursor-pointer hover:text-white transition-colors text-right group"
                          title="Click to sort by playoff probability"
                        >
                          <div className="flex items-center justify-end gap-1.5">
                            <span className={sortBy === 'ensemble_playoff_prob' ? 'text-indigo-400 font-bold' : ''}>
                              Playoffs
                            </span>
                            {renderSortIndicator('ensemble_playoff_prob')}
                          </div>
                        </th>
                        <th
                          onClick={() => handleSort('ensemble_title_prob')}
                          className="py-3.5 px-4 cursor-pointer hover:text-white transition-colors text-right group"
                          title="Click to sort by title probability"
                        >
                          <div className="flex items-center justify-end gap-1.5">
                            <span className={sortBy === 'ensemble_title_prob' ? 'text-indigo-400 font-bold' : ''}>
                              Title Prob
                            </span>
                            {renderSortIndicator('ensemble_title_prob')}
                          </div>
                        </th>
                      </>
                    )}
                  </tr>
                </thead>
                <tbody className="divide-y divide-slate-800/60 font-sans">
                  {filteredTeams.map((team, idx) => {
                    const minScale = 15;
                    const maxScale = 68;
                    const rangeSpan = maxScale - minScale;
                    const p10Pct = Math.max(0, Math.min(100, ((team.ensemble_p10 - minScale) / rangeSpan) * 100));
                    const p90Pct = Math.max(0, Math.min(100, ((team.ensemble_p90 - minScale) / rangeSpan) * 100));
                    const medianPct = Math.max(0, Math.min(100, ((team.ensemble_mean_wins - minScale) / rangeSpan) * 100));
                    const barWidth = Math.max(2, p90Pct - p10Pct);

                    const isPlayoffLock = team.ensemble_playoff_prob >= 0.85;
                    const isPlayoffBubble = team.ensemble_playoff_prob >= 0.35 && team.ensemble_playoff_prob < 0.85;

                    return (
                      <tr
                        key={team.team}
                        className="hover:bg-slate-800/40 transition-colors group text-slate-200"
                      >
                        <td className="py-3 px-4 text-center text-xs font-mono text-slate-400 hidden sm:table-cell">
                          {idx + 1}
                        </td>
                        <td className="py-3 px-4 sticky left-0 z-10 bg-surface-raised border-r border-slate-800">
                          <div className="flex items-center gap-3">
                            <div className="w-10 h-10 rounded-lg bg-surface/80 border border-slate-800 p-1 flex items-center justify-center flex-shrink-0 group-hover:border-slate-700 transition-colors">
                              <TeamLogo team={team.team} size="md" />
                            </div>
                            <div>
                              <div className="font-semibold text-white group-hover:text-indigo-400 transition-colors flex items-center gap-2">
                                <span>{team.team_name}</span>
                                <span className="text-[10px] font-mono px-1.5 py-0.2 rounded bg-slate-800/80 text-amber-400 border border-slate-700/60 font-semibold">
                                  {team.team}
                                </span>
                              </div>
                              <div className="text-xs text-slate-400">
                                {team.proj_wins.toFixed(1)}W - {team.proj_losses.toFixed(1)}L
                              </div>
                            </div>
                          </div>
                        </td>
                        <td className="py-3 px-3 text-center hidden sm:table-cell">
                          <span
                            className={`px-2 py-0.5 rounded text-xs font-semibold ${
                              team.conference === 'East'
                                ? 'bg-blue-500/10 text-blue-400 border border-blue-500/20'
                                : 'bg-red-500/10 text-red-400 border border-red-500/20'
                            }`}
                          >
                            {team.conference}
                          </span>
                        </td>
                        <td className="py-3 px-3 text-center text-xs text-slate-400 hidden sm:table-cell">{team.division}</td>

                        {tableMode === 'reality' ? (
                          /* Projections vs Reality Table Cells */
                          <>
                            <td className="py-3 px-3 text-center font-mono font-bold text-white">
                              {team.actual.wins}-{team.actual.losses}
                            </td>
                            <td className="py-3 px-3 text-right font-mono font-medium text-slate-300">
                              {(team.actual_win_pct * 100).toFixed(1)}%
                            </td>
                            <td className="py-3 px-3 text-right font-mono font-bold">
                              <span
                                className={
                                  team.point_diff > 0
                                    ? 'text-cyan-400'
                                    : team.point_diff < 0
                                    ? 'text-amber-400'
                                    : 'text-slate-400'
                                }
                              >
                                {team.point_diff > 0 ? `+${team.point_diff}` : team.point_diff}
                              </span>
                            </td>
                            <td className="py-3 px-4 text-right font-mono font-semibold text-slate-300">
                              {team.ensemble_mean_wins.toFixed(1)}W
                            </td>
                            <td className="py-3 px-4 text-right font-mono font-bold text-white text-base">
                              {team.current_pace.toFixed(1)}W
                            </td>
                            <td className="py-3 px-4 text-right font-mono font-bold">
                              <span
                                className={`inline-flex items-center gap-1 px-2.5 py-1 rounded-md text-xs font-mono font-bold ${
                                  team.performance_delta > 0
                                    ? 'bg-emerald-500/20 text-emerald-300 border border-emerald-500/30'
                                    : team.performance_delta < 0
                                    ? 'bg-rose-500/20 text-rose-300 border border-rose-500/30'
                                    : 'bg-slate-800 text-slate-400'
                                }`}
                              >
                                {team.performance_delta > 0 ? (
                                  <TrendingUp className="w-3.5 h-3.5 text-emerald-400" />
                                ) : team.performance_delta < 0 ? (
                                  <TrendingDown className="w-3.5 h-3.5 text-rose-400" />
                                ) : null}
                                {team.performance_delta > 0
                                  ? `+${team.performance_delta.toFixed(1)}`
                                  : team.performance_delta.toFixed(1)}
                              </span>
                            </td>
                          </>
                        ) : (
                          /* Projections Model Cells */
                          <>
                            <td className="py-3 px-4">
                              <div className="font-bold text-white text-base">
                                {team.ensemble_mean_wins.toFixed(1)}
                              </div>
                              <div className="text-xs text-slate-400 font-mono">
                                SD: ±{team.ensemble_sd_wins.toFixed(1)}
                              </div>
                            </td>
                            <td className="py-3 px-3 text-right font-mono font-medium text-slate-300">
                              {(team.win_pct * 100).toFixed(1)}%
                            </td>
                            <td className="py-3 px-4">
                              <div className="space-y-1">
                                <div className="flex items-center justify-between text-[11px] text-slate-400 font-mono">
                                  <span>p10: {team.ensemble_p10.toFixed(0)}</span>
                                  <span className="text-slate-300 font-semibold">{team.ensemble_mean_wins.toFixed(1)}</span>
                                  <span>p90: {team.ensemble_p90.toFixed(0)}</span>
                                </div>
                                <div className="relative w-full h-2.5 bg-slate-800 rounded-full overflow-hidden">
                                  {/* 10th to 90th percentile bar */}
                                  <div
                                    className="absolute top-0 bottom-0 bg-indigo-500/40 rounded-full"
                                    style={{ left: `${p10Pct}%`, width: `${barWidth}%` }}
                                  />
                                  {/* Mean dot marker */}
                                  <div
                                    className="absolute top-0 bottom-0 w-1.5 bg-amber-400 rounded-full shadow"
                                    style={{ left: `${medianPct}%` }}
                                  />
                                </div>
                              </div>
                            </td>
                            <td className="py-3 px-4 text-right">
                              <span
                                className={`inline-block px-2.5 py-1 rounded-md text-xs font-bold font-mono ${
                                  isPlayoffLock
                                    ? 'bg-emerald-500/20 text-emerald-300 border border-emerald-500/30'
                                    : isPlayoffBubble
                                    ? 'bg-amber-500/20 text-amber-300 border border-amber-500/30'
                                    : 'bg-slate-800 text-slate-400'
                                }`}
                              >
                                {(team.ensemble_playoff_prob * 100).toFixed(1)}%
                              </span>
                            </td>
                            <td className="py-3 px-4 text-right">
                              <span
                                className={`inline-block px-2 py-0.5 rounded text-xs font-bold font-mono ${
                                  team.ensemble_title_prob >= 0.05
                                    ? 'bg-amber-400/20 text-amber-300 border border-amber-400/30'
                                    : 'text-slate-400'
                                }`}
                              >
                                {(team.ensemble_title_prob * 100).toFixed(1)}%
                              </span>
                            </td>
                          </>
                        )}
                      </tr>
                    );
                  })}
                </tbody>
              </table>
            </div>
            {showScrollHint && (
              <div
                aria-hidden="true"
                className="pointer-events-none absolute top-0 right-0 bottom-0 w-10 bg-gradient-to-l from-surface-raised to-transparent sm:hidden"
              />
            )}
          </div>

          <div className="flex justify-end pt-1">
            <button
              type="button"
              onClick={() => handleTabChange('visualizer')}
              className="cursor-pointer select-none inline-flex items-center gap-2 text-xs font-semibold text-indigo-400 hover:text-indigo-300 bg-surface-raised border border-slate-800 px-4 py-2 rounded-lg hover:bg-slate-800 transition-colors shadow"
            >
              <BarChart2 className="w-3.5 h-3.5 pointer-events-none" />
              <span className="pointer-events-none">Switch to Playoff Contenders Visualizer</span>
            </button>
          </div>
        </div>
      ) : (
        /* Tab 3: 6 Divisions View */
        <div className="space-y-6">
          <div className="flex items-center justify-between text-xs text-slate-400 font-mono px-1">
            <span>
              {tableMode === 'reality'
                ? 'Sorted by Actual Win % • Benchmarked against 82-Game Pace'
                : 'Sorted by Ensemble Projected Wins'}
            </span>
            <span>6 Divisions • 30 Franchises</span>
          </div>

          <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
            {divisions.map((divName) => {
              const divTeams = enrichedTeams
                .filter((t) => t.division === divName)
                .sort((a, b) => {
                  if (tableMode === 'reality') {
                    return (
                      b.actual_win_pct - a.actual_win_pct ||
                      b.current_pace - a.current_pace ||
                      b.point_diff - a.point_diff
                    );
                  }
                  return b.ensemble_mean_wins - a.ensemble_mean_wins;
                });
              const isEast = divTeams[0]?.conference === 'East';

              return (
                <div
                  key={divName}
                  className="bg-surface-raised/80 border border-slate-800 rounded-xl overflow-hidden shadow-md flex flex-col justify-between"
                >
                  <div className="p-3 bg-surface/80 border-b border-slate-800 flex items-center justify-between">
                    <span className="font-bold text-xs text-white font-mono flex items-center gap-1.5">
                      <span className={`w-2 h-2 rounded-full ${isEast ? 'bg-blue-500' : 'bg-red-500'}`} />
                      {divName} Division
                    </span>
                    <span className="text-[10px] font-mono text-slate-500">5 Teams</span>
                  </div>

                  <div className="p-2 space-y-1.5 divide-y divide-slate-800/40">
                    {divTeams.map((team, idx) => (
                      <div
                        key={team.team}
                        className="pt-1.5 first:pt-0 flex items-center justify-between hover:bg-slate-800/40 p-1.5 rounded-lg transition-colors"
                      >
                        <div className="flex items-center gap-2 min-w-0">
                          <span className="text-[10px] font-mono text-slate-500 font-bold w-3">
                            {idx + 1}
                          </span>
                          <TeamLogo team={team.team} size="sm" />
                          <div className="min-w-0">
                            <span className="font-semibold text-xs text-white block truncate">
                              {team.team_name}
                            </span>
                            {tableMode === 'reality' ? (
                              <span className="text-[10px] font-mono text-slate-400">
                                {team.actual.wins}-{team.actual.losses} • Diff:{' '}
                                <strong
                                  className={
                                    team.point_diff > 0
                                      ? 'text-cyan-400'
                                      : team.point_diff < 0
                                      ? 'text-amber-400'
                                      : 'text-slate-400'
                                  }
                                >
                                  {team.point_diff > 0 ? `+${team.point_diff}` : team.point_diff}
                                </strong>
                              </span>
                            ) : (
                              <span className="text-[10px] font-mono text-slate-400">
                                PO: {(team.ensemble_playoff_prob * 100).toFixed(0)}% • Title:{' '}
                                {(team.ensemble_title_prob * 100).toFixed(0)}%
                              </span>
                            )}
                          </div>
                        </div>

                        <div className="text-right flex-shrink-0">
                          {tableMode === 'reality' ? (
                            <>
                              <span className="text-xs font-mono font-bold text-white block">
                                {team.current_pace.toFixed(1)}W pace
                              </span>
                              <span
                                className={`inline-flex items-center gap-0.5 text-[10px] font-mono font-bold ${
                                  team.performance_delta > 0
                                    ? 'text-emerald-400'
                                    : team.performance_delta < 0
                                    ? 'text-rose-400'
                                    : 'text-slate-400'
                                }`}
                              >
                                {team.performance_delta > 0 ? (
                                  <Flame className="w-2.5 h-2.5" />
                                ) : team.performance_delta < 0 ? (
                                  <Snowflake className="w-2.5 h-2.5" />
                                ) : null}
                                {team.performance_delta > 0
                                  ? `+${team.performance_delta.toFixed(1)}W`
                                  : `${team.performance_delta.toFixed(1)}W`}
                              </span>
                            </>
                          ) : (
                            <>
                              <span className="text-xs font-mono font-bold text-white block">
                                {team.ensemble_mean_wins.toFixed(1)}W
                              </span>
                              <span className="text-[10px] font-mono text-indigo-400">
                                {(team.win_pct * 100).toFixed(1)}% win
                              </span>
                            </>
                          )}
                        </div>
                      </div>
                    ))}
                  </div>
                </div>
              );
            })}
          </div>
        </div>
      )}
    </div>
  );
};
