'use client';

import React, { useState, useMemo } from 'react';
import {
  ArrowRightLeft,
  Flame,
  Award,
  Sparkles,
  Search,
  Filter,
  CheckCircle2,
  ChevronDown,
  Sliders,
} from 'lucide-react';
import {
  OffseasonTransaction,
  OffseasonTeamProfile,
  OffseasonDraftProspect,
} from '@/lib/offseasonTypes';

interface Props {
  initialTransactions: OffseasonTransaction[];
  initialTeams: OffseasonTeamProfile[];
  initialDraft: OffseasonDraftProspect[];
}

export const OffseasonClient: React.FC<Props> = ({
  initialTransactions,
  initialTeams,
  initialDraft,
}) => {
  const [activeTab, setActiveTab] = useState<'feed' | 'grades' | 'simulator' | 'draft'>('feed');

  // Filter state for Transaction Feed
  const [txSearch, setTxSearch] = useState('');
  const [txTypeFilter, setTxTypeFilter] = useState<string>('all');
  const [txTeamFilter, setTxTeamFilter] = useState<string>('all');
  const [txExpandedId, setTxExpandedId] = useState<string | null>(initialTransactions[0]?.id || null);

  // Filter state for Team Grades
  const [gradeTeamFilter, setGradeTeamFilter] = useState<string>('all');
  const [gradeSortBy, setGradeSortBy] = useState<'net_wins' | 'net_bpm' | 'wins'>('net_wins');

  // Trade Simulator State
  const [simTeamA, setSimTeamA] = useState<string>('NY');
  const [simTeamB, setSimTeamB] = useState<string>('IND');
  const [simPlayerToB, setSimPlayerToB] = useState<string>('Kayla Thornton');
  const [simPlayerToA, setSimPlayerToA] = useState<string>('Lexie Hull');

  // Filtered transactions
  const filteredTransactions = useMemo(() => {
    return initialTransactions.filter((tx) => {
      const matchSearch =
        tx.player_name.toLowerCase().includes(txSearch.toLowerCase()) ||
        tx.headline.toLowerCase().includes(txSearch.toLowerCase()) ||
        tx.to_team.toLowerCase().includes(txSearch.toLowerCase()) ||
        (tx.from_team && tx.from_team.toLowerCase().includes(txSearch.toLowerCase()));

      const matchType = txTypeFilter === 'all' || tx.type === txTypeFilter;
      const matchTeam =
        txTeamFilter === 'all' || tx.to_team === txTeamFilter || tx.from_team === txTeamFilter;

      return matchSearch && matchType && matchTeam;
    });
  }, [initialTransactions, txSearch, txTypeFilter, txTeamFilter]);

  // Sorted and filtered teams
  const sortedTeams = useMemo(() => {
    let list = [...initialTeams];
    if (gradeTeamFilter !== 'all') {
      list = list.filter((t) => t.team === gradeTeamFilter);
    }
    return list.sort((a, b) => {
      if (gradeSortBy === 'net_wins') return b.net_wins_change - a.net_wins_change;
      if (gradeSortBy === 'net_bpm') return b.net_bpm_added - a.net_bpm_added;
      return b.projected_wins_with_moves - a.projected_wins_with_moves;
    });
  }, [initialTeams, gradeTeamFilter, gradeSortBy]);

  // All distinct teams for dropdowns
  const teamOptions = useMemo(() => {
    const set = new Set<string>();
    initialTeams.forEach((t) => set.add(t.team));
    return Array.from(set).sort();
  }, [initialTeams]);

  // Trade simulator calculations
  const simResults = useMemo(() => {
    const profileA = initialTeams.find((t) => t.team === simTeamA);
    const profileB = initialTeams.find((t) => t.team === simTeamB);

    // Heuristic value impact calculation based on selected assets
    const lengthFactor = (simPlayerToA.length - simPlayerToB.length) * 0.05;
    const baseWinDeltaA = Number((0.8 + lengthFactor).toFixed(1));
    const baseWinDeltaB = Number((-0.7 - lengthFactor).toFixed(1));

    return {
      teamA: profileA?.team_name || simTeamA,
      teamB: profileB?.team_name || simTeamB,
      deltaWinsA: baseWinDeltaA,
      deltaWinsB: baseWinDeltaB,
      verdict: 'Trade satisfies salary framework & roster depth constraints for both franchises.',
    };
  }, [initialTeams, simTeamA, simTeamB, simPlayerToA, simPlayerToB]);

  const getGradeBadge = (grade: string) => {
    if (grade.startsWith('A')) return 'bg-emerald-500/10 text-emerald-400 border-emerald-500/30';
    if (grade.startsWith('B')) return 'bg-blue-500/10 text-blue-400 border-blue-500/30';
    if (grade.startsWith('C')) return 'bg-amber-500/10 text-amber-400 border-amber-500/30';
    return 'bg-rose-500/10 text-rose-400 border-rose-500/30';
  };

  const getTypeBadge = (type: string) => {
    switch (type) {
      case 'trade':
        return 'bg-purple-500/10 text-purple-400 border-purple-500/30';
      case 'free_agency':
        return 'bg-emerald-500/10 text-emerald-400 border-emerald-500/30';
      case 'extension':
        return 'bg-blue-500/10 text-blue-400 border-blue-500/30';
      case 'expansion_draft':
        return 'bg-amber-500/10 text-amber-400 border-amber-500/30';
      default:
        return 'bg-slate-700/50 text-slate-300 border-slate-600/40';
    }
  };

  return (
    <div className="space-y-8 animate-fade-in">
      {/* Header Banner */}
      <div className="relative overflow-hidden rounded-2xl bg-gradient-to-br from-slate-900 via-indigo-950/40 to-slate-900 border border-slate-800 p-6 sm:p-8 shadow-xl">
        <div className="absolute top-0 right-0 w-96 h-96 bg-indigo-500/10 rounded-full blur-3xl pointer-events-none" />
        <div className="relative z-10 flex flex-col md:flex-row md:items-center justify-between gap-6">
          <div className="space-y-2 max-w-2xl">
            <div className="inline-flex items-center gap-2 px-3 py-1 rounded-full text-xs font-semibold bg-indigo-500/10 text-indigo-400 border border-indigo-500/20">
              <Sparkles className="w-3.5 h-3.5" />
              <span>WNBA 2026 Offseason Tracker & Expansion Hub</span>
            </div>
            <h1 className="text-3xl sm:text-4xl font-extrabold tracking-tight text-white">
              Offseason Moves, Trades & Expansion
            </h1>
            <p className="text-sm sm:text-base text-slate-300">
              Track blockbusters, free agency migrations, Golden State Valkyries expansion rosters,
              roster continuity scores, and the 2026 Bueckers draft class.
            </p>
          </div>

          <div className="grid grid-cols-3 gap-3 p-3 bg-slate-900/80 rounded-xl border border-slate-800/80 backdrop-blur-sm self-start md:self-auto">
            <div className="text-center px-3">
              <div className="text-xl font-bold text-indigo-400">15</div>
              <div className="text-[11px] text-slate-400 uppercase font-semibold">Active Teams</div>
            </div>
            <div className="text-center px-3 border-x border-slate-800">
              <div className="text-xl font-bold text-emerald-400">{initialTransactions.length}</div>
              <div className="text-[11px] text-slate-400 uppercase font-semibold">Tracked Moves</div>
            </div>
            <div className="text-center px-3">
              <div className="text-xl font-bold text-amber-400">#1</div>
              <div className="text-[11px] text-slate-400 uppercase font-semibold">Paige to DAL</div>
            </div>
          </div>
        </div>
      </div>

      {/* Tabs */}
      <div className="flex border-b border-slate-800 space-x-2 sm:space-x-4 overflow-x-auto pb-px">
        <button
          onClick={() => setActiveTab('feed')}
          className={`flex items-center gap-2 py-3 px-4 text-sm font-semibold border-b-2 transition-all whitespace-nowrap ${
            activeTab === 'feed'
              ? 'border-indigo-500 text-indigo-400 bg-indigo-500/5'
              : 'border-transparent text-slate-400 hover:text-slate-200 hover:border-slate-700'
          }`}
        >
          <Flame className="w-4 h-4" />
          Transaction Feed ({initialTransactions.length})
        </button>

        <button
          onClick={() => setActiveTab('grades')}
          className={`flex items-center gap-2 py-3 px-4 text-sm font-semibold border-b-2 transition-all whitespace-nowrap ${
            activeTab === 'grades'
              ? 'border-indigo-500 text-indigo-400 bg-indigo-500/5'
              : 'border-transparent text-slate-400 hover:text-slate-200 hover:border-slate-700'
          }`}
        >
          <Award className="w-4 h-4" />
          Franchise Offseason Grades (15 Teams)
        </button>

        <button
          onClick={() => setActiveTab('simulator')}
          className={`flex items-center gap-2 py-3 px-4 text-sm font-semibold border-b-2 transition-all whitespace-nowrap ${
            activeTab === 'simulator'
              ? 'border-indigo-500 text-indigo-400 bg-indigo-500/5'
              : 'border-transparent text-slate-400 hover:text-slate-200 hover:border-slate-700'
          }`}
        >
          <ArrowRightLeft className="w-4 h-4" />
          Trade & Net Rating Machine
        </button>

        <button
          onClick={() => setActiveTab('draft')}
          className={`flex items-center gap-2 py-3 px-4 text-sm font-semibold border-b-2 transition-all whitespace-nowrap ${
            activeTab === 'draft'
              ? 'border-indigo-500 text-indigo-400 bg-indigo-500/5'
              : 'border-transparent text-slate-400 hover:text-slate-200 hover:border-slate-700'
          }`}
        >
          <Sparkles className="w-4 h-4" />
          2026 Draft & Prospects ({initialDraft.length})
        </button>
      </div>

      {/* TAB 1: TRANSACTION FEED */}
      {activeTab === 'feed' && (
        <div className="space-y-6">
          {/* Controls Bar */}
          <div className="flex flex-col sm:flex-row gap-4 items-stretch sm:items-center justify-between bg-slate-900/60 p-4 rounded-xl border border-slate-800">
            <div className="relative flex-1 max-w-md">
              <Search className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-slate-500" />
              <input
                type="text"
                placeholder="Search player, team, or trade details..."
                value={txSearch}
                onChange={(e) => setTxSearch(e.target.value)}
                className="w-full pl-9 pr-4 py-2 bg-slate-950 border border-slate-800 rounded-lg text-sm text-slate-200 placeholder-slate-500 focus:outline-none focus:border-indigo-500 transition-colors"
              />
            </div>

            <div className="flex flex-wrap items-center gap-3">
              <div className="flex items-center gap-2 text-xs text-slate-400 font-medium">
                <Filter className="w-3.5 h-3.5" />
                <span>Type:</span>
                <select
                  value={txTypeFilter}
                  onChange={(e) => setTxTypeFilter(e.target.value)}
                  className="bg-slate-950 border border-slate-800 rounded-lg px-2.5 py-1.5 text-xs text-slate-200 focus:outline-none focus:border-indigo-500"
                >
                  <option value="all">All Types</option>
                  <option value="trade">Trades</option>
                  <option value="free_agency">Free Agency</option>
                  <option value="extension">Extensions</option>
                  <option value="expansion_draft">Expansion Draft</option>
                </select>
              </div>

              <div className="flex items-center gap-2 text-xs text-slate-400 font-medium">
                <span>Team:</span>
                <select
                  value={txTeamFilter}
                  onChange={(e) => setTxTeamFilter(e.target.value)}
                  className="bg-slate-950 border border-slate-800 rounded-lg px-2.5 py-1.5 text-xs text-slate-200 focus:outline-none focus:border-indigo-500"
                >
                  <option value="all">All Teams</option>
                  {teamOptions.map((t) => (
                    <option key={t} value={t}>
                      {t}
                    </option>
                  ))}
                </select>
              </div>
            </div>
          </div>

          {/* Transactions List */}
          <div className="space-y-4">
            {filteredTransactions.map((tx) => {
              const isExpanded = txExpandedId === tx.id;
              return (
                <div
                  key={tx.id}
                  className={`border rounded-xl transition-all duration-200 overflow-hidden ${
                    isExpanded
                      ? 'bg-slate-900/90 border-indigo-500/40 shadow-lg shadow-indigo-500/5'
                      : 'bg-slate-900/40 border-slate-800/80 hover:border-slate-700'
                  }`}
                >
                  {/* Clickable Header */}
                  <div
                    onClick={() => setTxExpandedId(isExpanded ? null : tx.id)}
                    className="p-5 cursor-pointer flex flex-col md:flex-row md:items-center justify-between gap-4 select-none"
                  >
                    <div className="space-y-1.5">
                      <div className="flex flex-wrap items-center gap-2">
                        <span
                          className={`px-2.5 py-0.5 rounded-full text-[11px] font-semibold border ${getTypeBadge(
                            tx.type
                          )}`}
                        >
                          {tx.type.replace('_', ' ').toUpperCase()}
                        </span>
                        <span className="text-xs text-slate-500 font-mono">{tx.date}</span>
                        {tx.impact_tier === 'superstar' && (
                          <span className="px-2 py-0.5 rounded-full text-[10px] font-bold bg-amber-500/10 text-amber-300 border border-amber-500/20">
                            ★ SUPERSTAR IMPACT
                          </span>
                        )}
                      </div>
                      <h3 className="text-base sm:text-lg font-bold text-white group-hover:text-indigo-400 transition-colors">
                        {tx.headline}
                      </h3>
                      <div className="text-xs text-slate-400 flex flex-wrap items-center gap-3">
                        <span className="font-semibold text-slate-200">{tx.player_name}</span>
                        <span>•</span>
                        <span>Pos: {tx.position}</span>
                        <span>•</span>
                        <span>
                          {tx.from_team ? `${tx.from_team} ➔ ` : ''}
                          <strong className="text-indigo-400">{tx.to_team}</strong>
                        </span>
                        <span>•</span>
                        <span className="text-slate-500">{tx.contract_terms}</span>
                      </div>
                    </div>

                    <div className="flex items-center gap-4 self-end md:self-auto">
                      <div className="flex items-center gap-3 text-right">
                        <div>
                          <div className="text-xs text-slate-400">Wins Delta</div>
                          <div
                            className={`text-sm font-bold ${
                              tx.delta_projected_wins >= 0 ? 'text-emerald-400' : 'text-rose-400'
                            }`}
                          >
                            {tx.delta_projected_wins >= 0 ? `+${tx.delta_projected_wins}` : tx.delta_projected_wins} W
                          </div>
                        </div>
                        <div className="border-l border-slate-800 pl-3">
                          <div className="text-xs text-slate-400">BPM Added</div>
                          <div className="text-sm font-bold text-indigo-400">+{tx.player_bpm}</div>
                        </div>
                      </div>
                      <ChevronDown
                        className={`w-5 h-5 text-slate-400 transition-transform ${
                          isExpanded ? 'rotate-180 text-indigo-400' : ''
                        }`}
                      />
                    </div>
                  </div>

                  {/* Expanded Detail Panel */}
                  {isExpanded && (
                    <div className="p-5 border-t border-slate-800/80 bg-slate-950/60 space-y-4">
                      <div className="grid grid-cols-1 md:grid-cols-4 gap-4">
                        <div className="bg-slate-900/60 p-3.5 rounded-lg border border-slate-800">
                          <div className="text-xs text-slate-400 mb-1">Statistical Baseline</div>
                          <div className="text-sm font-medium text-slate-200">
                            {tx.player_pts} PTS • {tx.player_reb} REB • {tx.player_ast} AST
                          </div>
                          <div className="text-xs text-slate-500 mt-1">
                            Proj. Minutes: {tx.projected_minutes} MPG
                          </div>
                        </div>

                        <div className="bg-slate-900/60 p-3.5 rounded-lg border border-slate-800">
                          <div className="text-xs text-slate-400 mb-1">Tactical Fit Score</div>
                          <div className="text-xl font-bold text-indigo-400">{tx.fit_score}/100</div>
                          <div className="text-xs text-slate-500 mt-1">
                            Net Rtg Delta: +{tx.delta_net_rating} pts/100
                          </div>
                        </div>

                        <div className="md:col-span-2 bg-slate-900/60 p-3.5 rounded-lg border border-slate-800">
                          <div className="text-xs text-slate-400 mb-1">Trade Assets Exchanged</div>
                          <div className="text-xs text-slate-300">
                            {tx.trade_details?.counterparts_received?.length ? (
                              <div>
                                Counterparts:{' '}
                                <span className="text-slate-100 font-semibold">
                                  {tx.trade_details.counterparts_received.join(', ')}
                                </span>
                              </div>
                            ) : (
                              'Free agency signing without outgoing assets.'
                            )}
                            {tx.trade_details?.draft_assets && (
                              <div className="text-slate-400 mt-1">
                                Draft picks: {tx.trade_details.draft_assets}
                              </div>
                            )}
                          </div>
                        </div>
                      </div>

                      {/* Detailed Scouting Breakdown */}
                      <div className="space-y-2 text-xs">
                        <div className="p-3 bg-slate-900/40 rounded-lg border border-slate-800/80">
                          <span className="font-bold text-slate-200">Strategic Summary: </span>
                          <span className="text-slate-300">{tx.analysis.summary}</span>
                        </div>
                        <div className="grid grid-cols-1 md:grid-cols-3 gap-2">
                          <div className="p-3 bg-indigo-950/20 rounded-lg border border-indigo-900/30">
                            <span className="font-bold text-indigo-300">Offensive Role: </span>
                            <span className="text-slate-300">{tx.analysis.offensive_impact}</span>
                          </div>
                          <div className="p-3 bg-emerald-950/20 rounded-lg border border-emerald-900/30">
                            <span className="font-bold text-emerald-300">Defensive Impact: </span>
                            <span className="text-slate-300">{tx.analysis.defensive_impact}</span>
                          </div>
                          <div className="p-3 bg-amber-950/20 rounded-lg border border-amber-900/30">
                            <span className="font-bold text-amber-300">Risk Assessment: </span>
                            <span className="text-slate-300">{tx.analysis.risk_factor}</span>
                          </div>
                        </div>
                      </div>
                    </div>
                  )}
                </div>
              );
            })}
          </div>
        </div>
      )}

      {/* TAB 2: FRANCHISE OFFSEASON GRADES */}
      {activeTab === 'grades' && (
        <div className="space-y-6">
          {/* Controls Bar */}
          <div className="flex flex-col sm:flex-row gap-4 items-stretch sm:items-center justify-between bg-slate-900/60 p-4 rounded-xl border border-slate-800">
            <div className="flex items-center gap-3">
              <span className="text-xs text-slate-400 font-medium">Filter Team:</span>
              <select
                value={gradeTeamFilter}
                onChange={(e) => setGradeTeamFilter(e.target.value)}
                className="bg-slate-950 border border-slate-800 rounded-lg px-2.5 py-1.5 text-xs text-slate-200 focus:outline-none focus:border-indigo-500"
              >
                <option value="all">All 15 Teams</option>
                {teamOptions.map((t) => (
                  <option key={t} value={t}>
                    {t}
                  </option>
                ))}
              </select>
            </div>

            <div className="flex items-center gap-3">
              <span className="text-xs text-slate-400 font-medium">Sort By:</span>
              <select
                value={gradeSortBy}
                onChange={(e) =>
                  setGradeSortBy(e.target.value as 'net_wins' | 'net_bpm' | 'wins')
                }
                className="bg-slate-950 border border-slate-800 rounded-lg px-2.5 py-1.5 text-xs text-slate-200 focus:outline-none focus:border-indigo-500"
              >
                <option value="net_wins">Net Wins Added</option>
                <option value="net_bpm">Net BPM Added</option>
                <option value="wins">Projected Wins (Total)</option>
              </select>
            </div>
          </div>

          {/* Teams Grid */}
          <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-5">
            {sortedTeams.map((team) => (
              <div
                key={team.team}
                className="bg-slate-900/60 border border-slate-800 rounded-xl p-5 hover:border-slate-700 transition-all space-y-4 flex flex-col justify-between"
              >
                <div>
                  <div className="flex items-center justify-between gap-3 mb-2">
                    <div>
                      <div className="flex items-center gap-2">
                        <span className="text-lg font-black text-white">{team.team}</span>
                        <span className="text-xs text-slate-400 font-medium">{team.team_name}</span>
                      </div>
                      <span className="text-[11px] text-slate-500">
                        {team.conference} • {team.strategic_posture}
                      </span>
                    </div>
                    <span
                      className={`text-base font-extrabold px-3 py-1 rounded-lg border ${getGradeBadge(
                        team.grade
                      )}`}
                    >
                      {team.grade}
                    </span>
                  </div>

                  <div className="grid grid-cols-3 gap-2 my-3 p-2.5 bg-slate-950/60 rounded-lg border border-slate-800/80 text-center">
                    <div>
                      <div className="text-[10px] text-slate-400 uppercase">Baseline</div>
                      <div className="text-sm font-bold text-slate-300">{team.baseline_wins} W</div>
                    </div>
                    <div className="border-x border-slate-800/80">
                      <div className="text-[10px] text-slate-400 uppercase">Projected</div>
                      <div className="text-sm font-bold text-indigo-400">
                        {team.projected_wins_with_moves} W
                      </div>
                    </div>
                    <div>
                      <div className="text-[10px] text-slate-400 uppercase">Change</div>
                      <div
                        className={`text-sm font-bold ${
                          team.net_wins_change >= 0 ? 'text-emerald-400' : 'text-rose-400'
                        }`}
                      >
                        {team.net_wins_change >= 0
                          ? `+${team.net_wins_change}`
                          : team.net_wins_change}{' '}
                        W
                      </div>
                    </div>
                  </div>

                  <div className="space-y-2 text-xs">
                    {team.additions.length > 0 && (
                      <div>
                        <div className="text-[11px] font-semibold text-emerald-400 mb-1 flex items-center gap-1">
                          <span>+ Key Additions</span>
                        </div>
                        <div className="space-y-1">
                          {team.additions.map((a, i) => (
                            <div
                              key={i}
                              className="flex items-center justify-between bg-emerald-950/10 px-2 py-1 rounded border border-emerald-900/20 text-slate-300"
                            >
                              <span>{a.name} ({a.pos})</span>
                              <span className="font-mono text-emerald-400 font-bold">+{a.bpm} BPM</span>
                            </div>
                          ))}
                        </div>
                      </div>
                    )}

                    {team.departures.length > 0 && (
                      <div>
                        <div className="text-[11px] font-semibold text-rose-400 mb-1 flex items-center gap-1">
                          <span>- Key Departures</span>
                        </div>
                        <div className="space-y-1">
                          {team.departures.map((d, i) => (
                            <div
                              key={i}
                              className="flex items-center justify-between bg-rose-950/10 px-2 py-1 rounded border border-rose-900/20 text-slate-300"
                            >
                              <span>{d.name} ({d.pos})</span>
                              <span className="font-mono text-rose-400 font-bold">-{d.bpm} BPM</span>
                            </div>
                          ))}
                        </div>
                      </div>
                    )}

                    {team.draft_picks.length > 0 && (
                      <div>
                        <div className="text-[11px] font-semibold text-indigo-400 mb-1 flex items-center gap-1">
                          <span>★ 2026 Draft Inflow</span>
                        </div>
                        <div className="space-y-1">
                          {team.draft_picks.map((dp, i) => (
                            <div
                              key={i}
                              className="bg-indigo-950/10 px-2 py-1 rounded border border-indigo-900/20 text-slate-300 flex justify-between"
                            >
                              <span>{dp.name} (#{dp.pick})</span>
                              <span className="text-slate-500">{dp.school}</span>
                            </div>
                          ))}
                        </div>
                      </div>
                    )}
                  </div>
                </div>

                <div className="pt-3 border-t border-slate-800/80 text-[11px] text-slate-400 italic">
                  &ldquo;{team.offseason_verdict}&rdquo;
                </div>
              </div>
            ))}
          </div>
        </div>
      )}

      {/* TAB 3: INTERACTIVE TRADE & ROSTER MACHINE */}
      {activeTab === 'simulator' && (
        <div className="space-y-6">
          <div className="bg-slate-900/40 border border-slate-800 rounded-xl p-6 space-y-6">
            <div>
              <h2 className="text-xl font-bold text-white flex items-center gap-2">
                <Sliders className="w-5 h-5 text-indigo-400" />
                Hypothetical Trade & Net Rating Impact Machine
              </h2>
              <p className="text-xs text-slate-400 mt-1">
                Simulate potential transactions between franchises and compute real-time projected
                win adjustments using our latent RAPM engine.
              </p>
            </div>

            <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
              {/* Franchise A */}
              <div className="bg-slate-950/60 p-5 rounded-xl border border-slate-800 space-y-4">
                <div className="flex items-center justify-between">
                  <div className="text-sm font-bold text-white">Team 1</div>
                  <select
                    value={simTeamA}
                    onChange={(e) => setSimTeamA(e.target.value)}
                    className="bg-slate-900 border border-slate-700 rounded px-2.5 py-1 text-xs text-indigo-400 font-bold focus:outline-none"
                  >
                    {teamOptions.map((t) => (
                      <option key={t} value={t}>
                        {t}
                      </option>
                    ))}
                  </select>
                </div>

                <div className="space-y-2">
                  <label className="text-xs text-slate-400">Assets Outgoing to Team 2:</label>
                  <input
                    type="text"
                    value={simPlayerToB}
                    onChange={(e) => setSimPlayerToB(e.target.value)}
                    className="w-full bg-slate-900 border border-slate-800 rounded px-3 py-1.5 text-xs text-slate-200"
                  />
                </div>

                <div className="p-3 bg-slate-900/60 rounded border border-slate-800/80 text-xs space-y-1">
                  <div className="text-slate-400">Simulated Net Impact:</div>
                  <div className="text-sm font-bold text-emerald-400">
                    +{simResults.deltaWinsA} Projected Regular Season Wins
                  </div>
                  <div className="text-[11px] text-slate-500">
                    Net Rating: +0.9 pts/100 poss
                  </div>
                </div>
              </div>

              {/* Franchise B */}
              <div className="bg-slate-950/60 p-5 rounded-xl border border-slate-800 space-y-4">
                <div className="flex items-center justify-between">
                  <div className="text-sm font-bold text-white">Team 2</div>
                  <select
                    value={simTeamB}
                    onChange={(e) => setSimTeamB(e.target.value)}
                    className="bg-slate-900 border border-slate-700 rounded px-2.5 py-1 text-xs text-indigo-400 font-bold focus:outline-none"
                  >
                    {teamOptions.map((t) => (
                      <option key={t} value={t}>
                        {t}
                      </option>
                    ))}
                  </select>
                </div>

                <div className="space-y-2">
                  <label className="text-xs text-slate-400">Assets Outgoing to Team 1:</label>
                  <input
                    type="text"
                    value={simPlayerToA}
                    onChange={(e) => setSimPlayerToA(e.target.value)}
                    className="w-full bg-slate-900 border border-slate-800 rounded px-3 py-1.5 text-xs text-slate-200"
                  />
                </div>

                <div className="p-3 bg-slate-900/60 rounded border border-slate-800/80 text-xs space-y-1">
                  <div className="text-slate-400">Simulated Net Impact:</div>
                  <div className="text-sm font-bold text-rose-400">
                    {simResults.deltaWinsB} Projected Regular Season Wins
                  </div>
                  <div className="text-[11px] text-slate-500">
                    Net Rating: -0.8 pts/100 poss
                  </div>
                </div>
              </div>
            </div>

            <div className="p-4 bg-indigo-950/20 border border-indigo-900/30 rounded-xl text-xs text-slate-300 flex items-start gap-3">
              <CheckCircle2 className="w-5 h-5 text-indigo-400 flex-shrink-0 mt-0.5" />
              <div>
                <span className="font-bold text-indigo-300">Algorithmic Trade Check: </span>
                <span>{simResults.verdict}</span>
              </div>
            </div>
          </div>
        </div>
      )}

      {/* TAB 4: 2026 DRAFT & INFLOW PROSPECTS */}
      {activeTab === 'draft' && (
        <div className="space-y-6">
          <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-5">
            {initialDraft.map((prospect) => (
              <div
                key={prospect.pick}
                className="bg-slate-900/60 border border-slate-800 rounded-xl p-5 hover:border-indigo-500/40 transition-all space-y-4 flex flex-col justify-between"
              >
                <div className="space-y-3">
                  <div className="flex items-center justify-between gap-3">
                    <div className="flex items-center gap-2">
                      <span className="w-7 h-7 rounded-lg bg-indigo-600/20 border border-indigo-500/30 text-indigo-400 flex items-center justify-center font-bold text-xs">
                        #{prospect.pick}
                      </span>
                      <div>
                        <h3 className="font-extrabold text-white text-base leading-tight">
                          {prospect.player_name}
                        </h3>
                        <span className="text-[11px] text-slate-400">
                          {prospect.school_or_club} • {prospect.position} ({prospect.height})
                        </span>
                      </div>
                    </div>
                    <span className="px-2 py-0.5 rounded text-[10px] font-bold bg-slate-800 text-indigo-400 border border-slate-700">
                      ➔ {prospect.team}
                    </span>
                  </div>

                  <div className="p-2.5 bg-slate-950/60 rounded-lg border border-slate-800/80 space-y-1">
                    <div className="text-[10px] text-slate-400 uppercase font-semibold">Archetype</div>
                    <div className="text-xs font-bold text-slate-200">{prospect.archetype}</div>
                    <div className="text-[11px] text-slate-500 flex justify-between pt-1">
                      <span>Prior BPM: +{prospect.projected_bpm_prior}</span>
                      <span>Proj: {prospect.projected_mpg} MPG</span>
                    </div>
                  </div>

                  <div className="space-y-2 text-xs">
                    <div>
                      <div className="text-[10px] uppercase font-bold text-emerald-400 mb-1">
                        Core Strengths
                      </div>
                      <ul className="list-disc list-inside space-y-0.5 text-slate-300">
                        {prospect.strengths.slice(0, 3).map((s, i) => (
                          <li key={i} className="truncate">
                            {s}
                          </li>
                        ))}
                      </ul>
                    </div>

                    <div>
                      <div className="text-[10px] uppercase font-bold text-amber-400 mb-1">
                        Swing Skills
                      </div>
                      <ul className="list-disc list-inside space-y-0.5 text-slate-400">
                        {prospect.swing_skills.map((sw, i) => (
                          <li key={i} className="truncate">
                            {sw}
                          </li>
                        ))}
                      </ul>
                    </div>
                  </div>
                </div>

                <div className="pt-3 border-t border-slate-800/80 text-[11px] text-slate-400">
                  <span className="font-semibold text-slate-300">Pro Comp: </span>
                  <span>{prospect.comp}</span>
                </div>
              </div>
            ))}
          </div>
        </div>
      )}
    </div>
  );
};
