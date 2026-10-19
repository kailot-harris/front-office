'use client';

import { useState, useMemo } from 'react';
import { CoachProfile } from '@/lib/types';
import { TeamLogo } from './TeamLogo';
import { Search, Zap, Clock, SlidersHorizontal, ChevronRight } from 'lucide-react';

interface CoachingClientProps {
  initialCoaches: CoachProfile[];
}

export default function CoachingClient({ initialCoaches }: CoachingClientProps) {
  const [searchQuery, setSearchQuery] = useState('');
  const [playCallerFilter, setPlayCallerFilter] = useState<string>('ALL');
  const [selectedCoach, setSelectedCoach] = useState<CoachProfile | null>(null);
  const [sortField, setSortField] = useState<keyof CoachProfile>('fourth_down_aggression_index');
  const [sortAsc, setSortAsc] = useState(false);

  const filteredCoaches = useMemo(() => {
    return initialCoaches
      .filter((c) => {
        const matchesSearch =
          c.head_coach.toLowerCase().includes(searchQuery.toLowerCase()) ||
          c.team.toLowerCase().includes(searchQuery.toLowerCase()) ||
          c.offensive_scheme.toLowerCase().includes(searchQuery.toLowerCase()) ||
          c.offensive_coordinator.toLowerCase().includes(searchQuery.toLowerCase()) ||
          c.defensive_coordinator.toLowerCase().includes(searchQuery.toLowerCase());

        const matchesPlayCaller =
          playCallerFilter === 'ALL' || c.play_caller === playCallerFilter;

        return matchesSearch && matchesPlayCaller;
      })
      .sort((a, b) => {
        const aVal = a[sortField];
        const bVal = b[sortField];
        if (typeof aVal === 'number' && typeof bVal === 'number') {
          return sortAsc ? aVal - bVal : bVal - aVal;
        }
        return sortAsc
          ? String(aVal).localeCompare(String(bVal))
          : String(bVal).localeCompare(String(aVal));
      });
  }, [initialCoaches, searchQuery, playCallerFilter, sortField, sortAsc]);

  const topAggressive = useMemo(() => {
    return [...initialCoaches]
      .sort((a, b) => b.fourth_down_aggression_index - a.fourth_down_aggression_index)
      .slice(0, 3);
  }, [initialCoaches]);

  const topProe = useMemo(() => {
    return [...initialCoaches]
      .sort((a, b) => b.pass_rate_over_expected - a.pass_rate_over_expected)
      .slice(0, 3);
  }, [initialCoaches]);

  const longestTenured = useMemo(() => {
    return [...initialCoaches]
      .sort((a, b) => b.tenure_years - a.tenure_years)
      .slice(0, 3);
  }, [initialCoaches]);

  return (
    <div className="space-y-8">
      {/* Header */}
      <div>
        <div className="flex items-center gap-2 mb-1">
          <span className="text-xs font-mono font-medium text-emerald-400 bg-emerald-950/60 border border-emerald-800/60 px-2 py-0.5 rounded-full">
            Coaching Analysis & In-Game Decision Matrix
          </span>
          <span className="text-xs font-mono text-slate-400">
            32 NFL Head Coaches & Staffs
          </span>
        </div>
        <h1 className="text-2xl sm:text-3xl font-bold tracking-tight text-white">
          Head Coach Decision Profiles & Staff Architecture
        </h1>
        <p className="text-slate-400 text-sm mt-1 max-w-3xl">
          Analytical evaluation of NFL coaching decision tendencies: 4th-down go-for-it aggression percentiles,
          Pass Rate Over Expected (PROE), play-action frequency, game pace, and timeout leverage.
        </p>
      </div>

      {/* KPI Cards / Leaders */}
      <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
        {/* Most Aggressive on 4th Down */}
        <div className="bg-slate-900/90 border border-slate-800 rounded-xl p-4 shadow-lg">
          <div className="flex items-center justify-between pb-3 border-b border-slate-800 mb-3">
            <div className="flex items-center gap-2">
              <Zap className="w-4 h-4 text-emerald-400" />
              <h2 className="text-sm font-semibold text-white">4th-Down Aggression Leaders</h2>
            </div>
            <span className="text-[10px] font-mono text-slate-400">Percentile</span>
          </div>
          <div className="space-y-2">
            {topAggressive.map((c, i) => (
              <div
                key={c.team}
                onClick={() => setSelectedCoach(c)}
                className="flex items-center justify-between p-2 rounded-lg bg-slate-950/50 hover:bg-slate-800/60 cursor-pointer border border-slate-800/60 transition-colors"
              >
                <div className="flex items-center gap-2.5">
                  <span className="text-xs font-mono font-bold text-slate-500 w-4">#{i + 1}</span>
                  <TeamLogo team={c.team} size="sm" />
                  <div>
                    <div className="text-xs font-medium text-white">{c.head_coach}</div>
                    <div className="text-[10px] text-slate-400 font-mono">{c.team} • {c.offensive_scheme.split('/')[0]}</div>
                  </div>
                </div>
                <span className="text-xs font-mono font-bold text-emerald-400">
                  {c.fourth_down_aggression_index}th %ile
                </span>
              </div>
            ))}
          </div>
        </div>

        {/* Highest PROE (Pass-Happy) */}
        <div className="bg-slate-900/90 border border-slate-800 rounded-xl p-4 shadow-lg">
          <div className="flex items-center justify-between pb-3 border-b border-slate-800 mb-3">
            <div className="flex items-center gap-2">
              <SlidersHorizontal className="w-4 h-4 text-cyan-400" />
              <h2 className="text-sm font-semibold text-white">Pass Rate Over Expected</h2>
            </div>
            <span className="text-[10px] font-mono text-slate-400">Air Raid / Spread</span>
          </div>
          <div className="space-y-2">
            {topProe.map((c, i) => (
              <div
                key={c.team}
                onClick={() => setSelectedCoach(c)}
                className="flex items-center justify-between p-2 rounded-lg bg-slate-950/50 hover:bg-slate-800/60 cursor-pointer border border-slate-800/60 transition-colors"
              >
                <div className="flex items-center gap-2.5">
                  <span className="text-xs font-mono font-bold text-slate-500 w-4">#{i + 1}</span>
                  <TeamLogo team={c.team} size="sm" />
                  <div>
                    <div className="text-xs font-medium text-white">{c.head_coach}</div>
                    <div className="text-[10px] text-slate-400 font-mono">{c.team} • {c.play_caller} Calls</div>
                  </div>
                </div>
                <span className="text-xs font-mono font-bold text-cyan-400">
                  +{c.pass_rate_over_expected.toFixed(1)}%
                </span>
              </div>
            ))}
          </div>
        </div>

        {/* Longest Tenured */}
        <div className="bg-slate-900/90 border border-slate-800 rounded-xl p-4 shadow-lg">
          <div className="flex items-center justify-between pb-3 border-b border-slate-800 mb-3">
            <div className="flex items-center gap-2">
              <Clock className="w-4 h-4 text-indigo-400" />
              <h2 className="text-sm font-semibold text-white">Franchise Stability</h2>
            </div>
            <span className="text-[10px] font-mono text-slate-400">Tenure</span>
          </div>
          <div className="space-y-2">
            {longestTenured.map((c, i) => (
              <div
                key={c.team}
                onClick={() => setSelectedCoach(c)}
                className="flex items-center justify-between p-2 rounded-lg bg-slate-950/50 hover:bg-slate-800/60 cursor-pointer border border-slate-800/60 transition-colors"
              >
                <div className="flex items-center gap-2.5">
                  <span className="text-xs font-mono font-bold text-slate-500 w-4">#{i + 1}</span>
                  <TeamLogo team={c.team} size="sm" />
                  <div>
                    <div className="text-xs font-medium text-white">{c.head_coach}</div>
                    <div className="text-[10px] text-slate-400 font-mono">{c.team} • {c.super_bowl_wins} Rings</div>
                  </div>
                </div>
                <span className="text-xs font-mono font-bold text-indigo-400">
                  {c.tenure_years} Seasons
                </span>
              </div>
            ))}
          </div>
        </div>
      </div>

      {/* Filter and Search Bar */}
      <div className="flex flex-col sm:flex-row gap-3 items-center justify-between bg-slate-900/90 border border-slate-800 p-3.5 rounded-xl">
        <div className="relative w-full sm:w-80">
          <Search className="w-4 h-4 text-slate-400 absolute left-3 top-1/2 -translate-y-1/2" />
          <input
            type="text"
            placeholder="Search coach, coordinator, team, or scheme..."
            value={searchQuery}
            onChange={(e) => setSearchQuery(e.target.value)}
            className="w-full bg-slate-950 border border-slate-800 rounded-lg pl-9 pr-3 py-1.5 text-xs text-white placeholder-slate-500 focus:outline-none focus:border-emerald-500"
          />
        </div>

        <div className="flex items-center gap-3 w-full sm:w-auto">
          <div className="flex items-center gap-2">
            <label className="text-xs font-mono text-slate-400 whitespace-nowrap">Offensive Caller:</label>
            <select
              aria-label="Filter by offensive play caller"
              value={playCallerFilter}
              onChange={(e) => setPlayCallerFilter(e.target.value)}
              className="bg-slate-950 border border-slate-800 rounded-lg px-2.5 py-1.5 text-xs text-white focus:outline-none focus:border-emerald-500 font-mono"
            >
              <option value="ALL">All Roles</option>
              <option value="Head Coach">Head Coach</option>
              <option value="Offensive Coordinator">Offensive Coordinator</option>
            </select>
          </div>
        </div>
      </div>

      {/* Coaches Table */}
      <div className="bg-slate-900/90 border border-slate-800 rounded-xl overflow-hidden shadow-xl">
        <div className="overflow-x-auto">
          <table className="w-full text-left text-xs font-mono">
            <thead className="bg-slate-950/80 text-slate-400 uppercase text-[10px] tracking-wider border-b border-slate-800">
              <tr>
                <th className="px-4 py-3">Team</th>
                <th className="px-3 py-3">Head Coach</th>
                <th className="px-3 py-3">Tenure</th>
                <th className="px-3 py-3">Off Coordinator</th>
                <th className="px-3 py-3">Def Coordinator</th>
                <th className="px-3 py-3">Off. Caller</th>
                <th className="px-3 py-3">Def. Caller</th>
                <th
                  className="px-3 py-3 text-right cursor-pointer hover:text-white"
                  onClick={() => {
                    if (sortField === 'fourth_down_aggression_index') setSortAsc(!sortAsc);
                    else {
                      setSortField('fourth_down_aggression_index');
                      setSortAsc(false);
                    }
                  }}
                >
                  4th Aggress %ile {sortField === 'fourth_down_aggression_index' && (sortAsc ? '↑' : '↓')}
                </th>
                <th
                  className="px-3 py-3 text-right cursor-pointer hover:text-white"
                  onClick={() => {
                    if (sortField === 'pass_rate_over_expected') setSortAsc(!sortAsc);
                    else {
                      setSortField('pass_rate_over_expected');
                      setSortAsc(false);
                    }
                  }}
                >
                  PROE % {sortField === 'pass_rate_over_expected' && (sortAsc ? '↑' : '↓')}
                </th>
                <th className="px-3 py-3 text-right">Pace (s)</th>
                <th className="px-3 py-3 text-center">Clock Grade</th>
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
                      isSelected ? 'bg-emerald-950/20 border-l-2 border-emerald-500' : ''
                    }`}
                  >
                    <td className="px-4 py-3">
                      <div className="flex items-center gap-2">
                        <TeamLogo team={c.team} size="xs" />
                        <span className="font-bold text-white">{c.team}</span>
                      </div>
                    </td>
                    <td className="px-3 py-3 font-sans font-semibold text-white">
                      {c.head_coach}
                    </td>
                    <td className="px-3 py-3 text-slate-400">
                      {c.tenure_years} yrs
                    </td>
                    <td className="px-3 py-3 font-sans text-slate-300">
                      {c.offensive_coordinator}
                    </td>
                    <td className="px-3 py-3 font-sans text-slate-300">
                      {c.defensive_coordinator}
                    </td>
                    <td className="px-3 py-3">
                      <span
                        className={`px-1.5 py-0.5 rounded text-[10px] font-sans font-medium ${
                          (c.offensive_play_caller || c.play_caller) === 'Head Coach'
                            ? 'bg-purple-950/80 border border-purple-800 text-purple-300'
                            : 'bg-emerald-950/80 border border-emerald-800 text-emerald-300'
                        }`}
                      >
                        {c.offensive_play_caller || c.play_caller}
                      </span>
                    </td>
                    <td className="px-3 py-3">
                      <span
                        className={`px-1.5 py-0.5 rounded text-[10px] font-sans font-medium ${
                          (c.defensive_play_caller || 'Defensive Coordinator') === 'Head Coach'
                            ? 'bg-purple-950/80 border border-purple-800 text-purple-300'
                            : 'bg-blue-950/80 border border-blue-800 text-blue-300'
                        }`}
                      >
                        {c.defensive_play_caller || 'Defensive Coordinator'}
                      </span>
                    </td>
                    <td className="px-3 py-3 text-right font-bold">
                      <span
                        className={
                          c.fourth_down_aggression_index >= 80
                            ? 'text-emerald-400'
                            : c.fourth_down_aggression_index < 60
                            ? 'text-rose-400'
                            : 'text-amber-400'
                        }
                      >
                        {c.fourth_down_aggression_index}th
                      </span>
                    </td>
                    <td className="px-3 py-3 text-right font-bold">
                      <span
                        className={
                          c.pass_rate_over_expected > 2.0
                            ? 'text-cyan-400'
                            : c.pass_rate_over_expected < -2.0
                            ? 'text-amber-400'
                            : 'text-slate-300'
                        }
                      >
                        {c.pass_rate_over_expected > 0 ? '+' : ''}
                        {c.pass_rate_over_expected.toFixed(1)}%
                      </span>
                    </td>
                    <td className="px-3 py-3 text-right text-slate-400">
                      {c.pace_seconds_per_play.toFixed(1)}s
                    </td>
                    <td className="px-3 py-3 text-center">
                      <span
                        className={`px-2 py-0.5 rounded text-[10px] font-bold ${
                          c.timeout_management_grade.startsWith('A')
                            ? 'bg-emerald-950 text-emerald-400 border border-emerald-800'
                            : c.timeout_management_grade.startsWith('B')
                            ? 'bg-blue-950 text-blue-400 border border-blue-800'
                            : 'bg-rose-950 text-rose-400 border border-rose-800'
                        }`}
                      >
                        {c.timeout_management_grade}
                      </span>
                    </td>
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

      {/* Selected Coach Deep-Dive Drawer */}
      {selectedCoach && (
        <div className="bg-slate-900/90 border border-emerald-500/50 rounded-xl p-5 shadow-2xl relative">
          <div className="flex flex-col sm:flex-row items-start sm:items-center justify-between pb-4 border-b border-slate-800 gap-4">
            <div className="flex items-center gap-4">
              <TeamLogo team={selectedCoach.team} size="xl" />
              <div>
                <h2 className="text-xl font-bold text-white flex items-center gap-2">
                  {selectedCoach.head_coach}
                  <span className="text-xs font-mono font-normal text-emerald-400 bg-emerald-950 px-2 py-0.5 rounded border border-emerald-800">
                    {selectedCoach.team} • Year {selectedCoach.tenure_years}
                  </span>
                </h2>
                <p className="text-xs text-slate-400 font-mono mt-0.5">
                  Career Record: {selectedCoach.career_record} • {selectedCoach.super_bowl_wins} Super Bowl Titles
                </p>
                <div className="flex items-center gap-2 mt-2">
                  <span className="text-[10px] font-mono px-2 py-0.5 rounded bg-slate-950 border border-slate-800 text-slate-300">
                    <strong className="text-slate-400">Offense Calls:</strong> {selectedCoach.offensive_play_caller || selectedCoach.play_caller} ({selectedCoach.offensive_play_caller === 'Head Coach' ? selectedCoach.head_coach : selectedCoach.offensive_coordinator})
                  </span>
                  <span className="text-[10px] font-mono px-2 py-0.5 rounded bg-slate-950 border border-slate-800 text-slate-300">
                    <strong className="text-slate-400">Defense Calls:</strong> {selectedCoach.defensive_play_caller || 'Defensive Coordinator'} ({selectedCoach.defensive_play_caller === 'Head Coach' ? selectedCoach.head_coach : selectedCoach.defensive_coordinator})
                  </span>
                </div>
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
            <div className="bg-slate-950/60 p-3 rounded-lg border border-slate-800">
              <span className="text-[10px] font-mono uppercase text-slate-500 block">Offensive Scheme</span>
              <span className="text-xs font-sans font-semibold text-white block mt-0.5">
                {selectedCoach.offensive_scheme}
              </span>
            </div>
            <div className="bg-slate-950/60 p-3 rounded-lg border border-slate-800">
              <span className="text-[10px] font-mono uppercase text-slate-500 block">Defensive Scheme</span>
              <span className="text-xs font-sans font-semibold text-white block mt-0.5">
                {selectedCoach.defensive_scheme}
              </span>
            </div>
            <div className="bg-slate-950/60 p-3 rounded-lg border border-slate-800">
              <span className="text-[10px] font-mono uppercase text-slate-500 block">Play-Action Rate</span>
              <span className="text-sm font-mono font-bold text-emerald-400 block mt-0.5">
                {selectedCoach.play_action_rate.toFixed(1)}%
              </span>
            </div>
            <div className="bg-slate-950/60 p-3 rounded-lg border border-slate-800">
              <span className="text-[10px] font-mono uppercase text-slate-500 block">Challenge Win %</span>
              <span className="text-sm font-mono font-bold text-cyan-400 block mt-0.5">
                {selectedCoach.challenge_win_pct.toFixed(1)}%
              </span>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
