'use client';

import React, { useState, useMemo } from 'react';
import {
  OffseasonTransaction,
  TeamOffseasonProfile,
  RookieDraftProfile,
  TransactionType,
} from '@/lib/offseasonTypes';
import { PlayerProjection } from '@/lib/types';
import { SeasonSourceBadge } from '@/components/SeasonSourceBadge';
import { SEASON_SOURCES } from '@/lib/season';
import { TeamLogo } from '@/components/TeamLogo';
import {
  ArrowRight,
  TrendingUp,
  Sparkles,
  Search,
  CheckCircle2,
  AlertTriangle,
  Shuffle,
  DollarSign,
  GraduationCap,
  ShieldAlert,
  Trophy,
  Layers,
  ChevronDown,
  ChevronUp,
  Zap,
  Scale,
  Download,
} from 'lucide-react';
import { exportToCsv } from '@/lib/exportToCsv';

interface OffseasonClientProps {
  transactions: OffseasonTransaction[];
  teams: TeamOffseasonProfile[];
  draftProspects: RookieDraftProfile[];
  allPlayers?: PlayerProjection[];
}

export const OffseasonClient: React.FC<OffseasonClientProps> = ({
  transactions,
  teams,
  draftProspects,
  allPlayers = [],
}) => {
  // Navigation tabs
  const [activeTab, setActiveTab] = useState<'feed' | 'teams' | 'machine' | 'draft'>('feed');

  // Transaction Feed Filters
  const [searchQuery, setSearchQuery] = useState('');
  const [typeFilter, setTypeFilter] = useState<'all' | TransactionType>('all');
  const [teamFilter, setTeamFilter] = useState<string>('all');
  const [tierFilter, setTierFilter] = useState<string>('all');
  const [sortBy, setSortBy] = useState<'wins' | 'nrtg' | 'bpm' | 'date'>('wins');
  const [expandedTransId, setExpandedTransId] = useState<string | null>(transactions[0]?.id || null);

  // Teams Leaderboard Filters
  const [confFilter, setConfFilter] = useState<'all' | 'East' | 'West'>('all');
  const [selectedTeamProfile, setSelectedTeamProfile] = useState<string | null>('PHI');

  // Trade / Move Machine Sandbox State (2026-2027 Blockbuster Default: Giannis to Miami)
  const [sandboxTeamA, setSandboxTeamA] = useState<string>('MIA');
  const [sandboxTeamB, setSandboxTeamB] = useState<string>('MIL');
  const [sandboxOutgoingA, setSandboxOutgoingA] = useState<string[]>(['Tyler Herro', 'Jaime Jaquez Jr.', 'Bobby Portis']);
  const [sandboxIncomingA, setSandboxIncomingA] = useState<string[]>(['Giannis Antetokounmpo']);

  // Draft Class Filters
  const [draftSearch, setDraftSearch] = useState('');
  const [draftRoundFilter, setDraftRoundFilter] = useState<'all' | 1 | 2>('all');
  const [draftPosFilter, setDraftPosFilter] = useState<'all' | 'G' | 'F' | 'C'>('all');
  const [draftTierFilter, setDraftTierFilter] = useState<string>('all');

  // Extract unique NBA teams from transactions & teams list
  const availableTeams = useMemo(() => {
    return Array.from(new Set(teams.map((t) => t.team))).sort();
  }, [teams]);

  // Filtered & Sorted Transactions
  const filteredTransactions = useMemo(() => {
    return transactions
      .filter((t) => {
        if (typeFilter !== 'all' && t.type !== typeFilter) return false;
        if (teamFilter !== 'all' && t.to_team !== teamFilter && t.from_team !== teamFilter) return false;
        if (tierFilter !== 'all' && t.impact_tier !== tierFilter) return false;
        if (searchQuery.trim()) {
          const q = searchQuery.toLowerCase();
          const matchPlayer = t.player_name.toLowerCase().includes(q);
          const matchTo = t.to_team.toLowerCase().includes(q);
          const matchFrom = (t.from_team || '').toLowerCase().includes(q);
          const matchHeadline = t.headline.toLowerCase().includes(q);
          if (!matchPlayer && !matchTo && !matchFrom && !matchHeadline) return false;
        }
        return true;
      })
      .sort((a, b) => {
        if (sortBy === 'wins') return b.delta_projected_wins - a.delta_projected_wins;
        if (sortBy === 'nrtg') return b.delta_net_rating - a.delta_net_rating;
        if (sortBy === 'bpm') return b.player_bpm - a.player_bpm;
        if (sortBy === 'date') return new Date(b.date).getTime() - new Date(a.date).getTime();
        return 0;
      });
  }, [transactions, typeFilter, teamFilter, tierFilter, searchQuery, sortBy]);

  // Filtered Teams Leaderboard
  const filteredTeams = useMemo(() => {
    return teams.filter((t) => {
      if (confFilter !== 'all' && t.conference !== confFilter) return false;
      return true;
    });
  }, [teams, confFilter]);

  const handleExportTeamsCsv = () => {
    exportToCsv(
      filteredTeams as unknown as Record<string, unknown>[],
      [
        { key: 'team', label: 'Franchise' },
        { key: 'grade', label: 'Grade' },
        { key: 'roster_continuity_pct', label: 'Continuity' },
        { key: 'net_bpm_added', label: 'Net BPM' },
        { key: 'net_wins_change', label: 'Net Win Delta' },
        { key: 'projected_wins_with_moves', label: 'Proj Wins' },
      ],
      'offseason-franchise-rankings'
    );
  };

  // Filtered Draft Prospects
  const filteredDraftProspects = useMemo(() => {
    return draftProspects.filter((p) => {
      const pRound = p.round || (p.pick <= 30 ? 1 : 2);
      if (draftRoundFilter !== 'all' && pRound !== draftRoundFilter) return false;
      if (draftPosFilter !== 'all' && !p.position.toUpperCase().includes(draftPosFilter)) return false;
      if (draftTierFilter !== 'all' && p.upside_tier !== draftTierFilter) return false;
      if (draftSearch.trim()) {
        const q = draftSearch.toLowerCase();
        const mName = p.player_name.toLowerCase().includes(q);
        const mSchool = p.school_or_club.toLowerCase().includes(q);
        const mTeam = p.team.toLowerCase().includes(q);
        const mArch = p.archetype.toLowerCase().includes(q);
        if (!mName && !mSchool && !mTeam && !mArch) return false;
      }
      return true;
    });
  }, [draftProspects, draftRoundFilter, draftPosFilter, draftTierFilter, draftSearch]);

  // Summary KPIs
  const totalTrades = useMemo(() => transactions.filter((t) => t.type === 'trade').length, [transactions]);
  const totalFreeAgents = useMemo(() => transactions.filter((t) => t.type === 'free_agency').length, [transactions]);
  const totalDraftPicks = useMemo(() => transactions.filter((t) => t.type === 'draft').length, [transactions]);
  const topGainTeam = teams[0] || null;

  // Selected team profile object for deep-dive
  const activeTeamDetail = useMemo(() => {
    return teams.find((t) => t.team === selectedTeamProfile) || teams[0] || null;
  }, [teams, selectedTeamProfile]);

  // Active Roster for Sandbox Team A (players projected on Team A)
  const rosterTeamA = useMemo(() => {
    return allPlayers
      .filter((p) => p.team === sandboxTeamA)
      .sort((a, b) => b.proj_mpg - a.proj_mpg);
  }, [allPlayers, sandboxTeamA]);

  // Active Roster for Sandbox Team B (players projected on Team B)
  const rosterTeamB = useMemo(() => {
    return allPlayers
      .filter((p) => p.team === sandboxTeamB)
      .sort((a, b) => b.proj_mpg - a.proj_mpg);
  }, [allPlayers, sandboxTeamB]);

  // ----------------------------------------------------------------------------
  // Interactive Trade / Sandbox Engine Calculation
  // ----------------------------------------------------------------------------
  const sandboxCalculation = useMemo(() => {
    const teamAProfile = teams.find((t) => t.team === sandboxTeamA);
    const teamBProfile = teams.find((t) => t.team === sandboxTeamB);

    const baseWinsA = teamAProfile ? teamAProfile.baseline_wins : 45.0;
    const baseWinsB = teamBProfile ? teamBProfile.baseline_wins : 42.0;

    // Approximate BPM lookups
    const getBpm = (name: string): number => {
      const transMatch = transactions.find((t) => t.player_name.toLowerCase().includes(name.toLowerCase()));
      if (transMatch) return transMatch.player_bpm;
      const playerMatch = allPlayers.find((p) => p.player_name.toLowerCase().includes(name.toLowerCase()));
      if (playerMatch) {
        // Estimated BPM from PRA zscore
        return Math.round((playerMatch.pra_zscore * 1.8) * 10) / 10;
      }
      return 0.5;
    };

    const outBpmSumA = sandboxOutgoingA.reduce((sum, name) => sum + getBpm(name), 0);
    const inBpmSumA = sandboxIncomingA.reduce((sum, name) => sum + getBpm(name), 0);

    const netBpmDeltaA = inBpmSumA - outBpmSumA;
    // Rotation minute normalization factor (~0.65 net rating per BPM point for high minute pieces)
    const netRatingShiftA = Math.round(netBpmDeltaA * 0.62 * 10) / 10;

    // Margin sigma 11.8 win probability shift: Delta Wins = (Delta Nrtg / 11.8) * ~18 wins
    const deltaWinsA = Math.round((netRatingShiftA / 11.8) * 18.2 * 10) / 10;
    const newWinsA = Math.max(15, Math.min(68, Math.round((baseWinsA + deltaWinsA) * 10) / 10));

    // Team B mirrored impact
    const netRatingShiftB = -netRatingShiftA;
    const deltaWinsB = -deltaWinsA;
    const newWinsB = Math.max(15, Math.min(68, Math.round((baseWinsB + deltaWinsB) * 10) / 10));

    return {
      teamA: {
        team: sandboxTeamA,
        baseWins: baseWinsA,
        newWins: newWinsA,
        deltaWins: deltaWinsA,
        netRatingShift: netRatingShiftA,
        outBpm: outBpmSumA,
        inBpm: inBpmSumA,
      },
      teamB: {
        team: sandboxTeamB,
        baseWins: baseWinsB,
        newWins: newWinsB,
        deltaWins: deltaWinsB,
        netRatingShift: netRatingShiftB,
        outBpm: inBpmSumA,
        inBpm: outBpmSumA,
      },
    };
  }, [sandboxTeamA, sandboxTeamB, sandboxOutgoingA, sandboxIncomingA, teams, transactions, allPlayers]);

  return (
    <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8 space-y-8">
      {/* Hero Header */}
      <div className="flex flex-col md:flex-row md:items-center justify-between gap-4 border-b border-slate-800 pb-6">
        <div>
          <div className="flex items-center gap-2.5 mb-1.5">
            <span className="p-1.5 rounded-lg bg-orange-500/10 text-orange-400 border border-orange-500/20">
              <Shuffle className="w-5 h-5" />
            </span>
            <h1 className="text-3xl font-black tracking-tight text-white">
              Offseason Moves & Transaction Analytics
            </h1>
            <span className="text-xs font-semibold px-2.5 py-0.5 rounded-full bg-indigo-500/10 text-indigo-400 border border-indigo-500/20 font-mono">
              Trades • Free Agency • Draft
            </span>
          </div>
          <div className="mt-2">
            <SeasonSourceBadge
              season={SEASON_SOURCES.offseason.season}
              kind="projection"
              label="Offseason"
              title={SEASON_SOURCES.offseason.note}
            />
          </div>
          <p className="text-slate-400 text-sm max-w-3xl">
            Quantitative transaction space analyzing roster turnover, returning minute continuity, bottom-up net rating swings,
            and 82-game win trajectories across all 30 NBA franchises.
          </p>
        </div>

        {/* Global KPI Pills */}
        <div className="flex items-center gap-3">
          <div className="bg-surface-raised/90 border border-slate-800 rounded-xl px-3.5 py-2">
            <span className="text-[10px] uppercase font-bold text-slate-400 block tracking-wider font-mono">
              Top Gainer
            </span>
            <div className="flex items-center gap-1.5">
              {topGainTeam && <TeamLogo team={topGainTeam.team} size="xs" />}
              <span className="font-bold text-emerald-400 text-sm">
                {topGainTeam ? `${topGainTeam.team} (+${topGainTeam.net_wins_change}W)` : 'OKC (+6.3W)'}
              </span>
            </div>
          </div>
          <div className="bg-surface-raised/90 border border-slate-800 rounded-xl px-3.5 py-2">
            <span className="text-[10px] uppercase font-bold text-slate-400 block tracking-wider font-mono">
              Tracked Moves
            </span>
            <span className="font-bold text-white text-sm font-mono">{transactions.length} Major Moves</span>
          </div>
        </div>
      </div>

      {/* Primary Tab Navigation */}
      <div className="flex flex-wrap items-center justify-between gap-3 bg-surface-raised/70 p-1.5 rounded-2xl border border-slate-800/80">
        <div className="flex items-center gap-1.5 overflow-x-auto">
          <button
            onClick={() => setActiveTab('feed')}
            className={`flex items-center gap-2 px-4 py-2.5 rounded-xl text-sm font-semibold transition-all ${
              activeTab === 'feed'
                ? 'bg-accent-600 text-white shadow-lg shadow-accent-600/30'
                : 'text-slate-400 hover:text-white hover:bg-slate-800/60'
            }`}
          >
            <Layers className="w-4 h-4" />
            <span>Transaction Ledger & Impact Feed</span>
            <span
              className={`text-[10px] px-1.5 py-0.5 rounded-full font-mono ${
                activeTab === 'feed' ? 'bg-accent-700 text-indigo-100' : 'bg-slate-800 text-slate-400'
              }`}
            >
              {transactions.length}
            </span>
          </button>

          <button
            onClick={() => setActiveTab('teams')}
            className={`flex items-center gap-2 px-4 py-2.5 rounded-xl text-sm font-semibold transition-all ${
              activeTab === 'teams'
                ? 'bg-accent-600 text-white shadow-lg shadow-accent-600/30'
                : 'text-slate-400 hover:text-white hover:bg-slate-800/60'
            }`}
          >
            <Trophy className="w-4 h-4" />
            <span>Franchise Winners & Losers (30 Teams)</span>
            <span
              className={`text-[10px] px-1.5 py-0.5 rounded-full font-mono ${
                activeTab === 'teams' ? 'bg-accent-700 text-indigo-100' : 'bg-slate-800 text-slate-400'
              }`}
            >
              Rankings
            </span>
          </button>

          <button
            onClick={() => setActiveTab('machine')}
            className={`flex items-center gap-2 px-4 py-2.5 rounded-xl text-sm font-semibold transition-all ${
              activeTab === 'machine'
                ? 'bg-accent-600 text-white shadow-lg shadow-accent-600/30'
                : 'text-slate-400 hover:text-white hover:bg-slate-800/60'
            }`}
          >
            <Scale className="w-4 h-4 text-amber-400" />
            <span>Interactive Trade Machine (What-If)</span>
            <span className="text-[10px] px-1.5 py-0.5 rounded-full font-mono bg-amber-500/20 text-amber-300 border border-amber-500/30">
              Live Calc
            </span>
          </button>

          <button
            onClick={() => setActiveTab('draft')}
            className={`flex items-center gap-2 px-4 py-2.5 rounded-xl text-sm font-semibold transition-all ${
              activeTab === 'draft'
                ? 'bg-accent-600 text-white shadow-lg shadow-accent-600/30'
                : 'text-slate-400 hover:text-white hover:bg-slate-800/60'
            }`}
          >
            <GraduationCap className="w-4 h-4 text-emerald-400" />
            <span>Draft Class & Rookie Projections</span>
            <span
              className={`text-[10px] px-1.5 py-0.5 rounded-full font-mono ${
                activeTab === 'draft' ? 'bg-accent-700 text-indigo-100' : 'bg-slate-800 text-slate-400'
              }`}
            >
              {draftProspects.length}
            </span>
          </button>
        </div>
      </div>

      {/* ========================================================================
          TAB 1: TRANSACTION LEDGER & IMPACT FEED
          ======================================================================== */}
      {activeTab === 'feed' && (
        <div className="space-y-6">
          {/* Quick Metrics Banner */}
          <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4">
            <div className="bg-surface-raised/80 border border-slate-800/80 rounded-2xl p-4 flex items-center justify-between">
              <div>
                <span className="text-xs text-slate-400 uppercase tracking-wider font-mono">Blockbuster Trades</span>
                <div className="text-2xl font-black text-white mt-0.5">{totalTrades} Verified</div>
                <span className="text-[11px] text-slate-400 mt-1 block">Giannis, Brown, Kawhi, AD, Herro</span>
              </div>
              <div className="w-12 h-12 rounded-xl bg-indigo-500/10 border border-indigo-500/20 flex items-center justify-center text-indigo-400">
                <Shuffle className="w-6 h-6" />
              </div>
            </div>

            <div className="bg-surface-raised/80 border border-slate-800/80 rounded-2xl p-4 flex items-center justify-between">
              <div>
                <span className="text-xs text-slate-400 uppercase tracking-wider font-mono">Free Agent Signings</span>
                <div className="text-2xl font-black text-amber-400 mt-0.5">{totalFreeAgents} Signings</div>
                <span className="text-[11px] text-slate-400 mt-1 block">LeBron, DeRozan, Naz Reid, Bridges</span>
              </div>
              <div className="w-12 h-12 rounded-xl bg-amber-500/10 border border-amber-500/20 flex items-center justify-center text-amber-400">
                <DollarSign className="w-6 h-6" />
              </div>
            </div>

            <div className="bg-surface-raised/80 border border-slate-800/80 rounded-2xl p-4 flex items-center justify-between">
              <div>
                <span className="text-xs text-slate-400 uppercase tracking-wider font-mono">Draft Class Signings</span>
                <div className="text-2xl font-black text-emerald-400 mt-0.5">{totalDraftPicks} Rookies</div>
                <span className="text-[11px] text-slate-400 mt-1 block">Cenac Jr., Mikel Brown, Meleek, Wilson</span>
              </div>
              <div className="w-12 h-12 rounded-xl bg-emerald-500/10 border border-emerald-500/20 flex items-center justify-center text-emerald-400">
                <GraduationCap className="w-6 h-6" />
              </div>
            </div>

            <div className="bg-surface-raised/80 border border-slate-800/80 rounded-2xl p-4 flex items-center justify-between">
              <div>
                <span className="text-xs text-slate-400 uppercase tracking-wider font-mono">Avg Net Rating Delta</span>
                <div className="text-2xl font-black text-indigo-300 mt-0.5">+1.84 pts</div>
                <span className="text-[11px] text-slate-400 mt-1 block">Per 100 poss on acquiring teams</span>
              </div>
              <div className="w-12 h-12 rounded-xl bg-indigo-500/10 border border-indigo-500/20 flex items-center justify-center text-indigo-400">
                <TrendingUp className="w-6 h-6" />
              </div>
            </div>
          </div>

          {/* Interactive Filters Bar */}
          <div className="bg-surface-raised/90 border border-slate-800 rounded-2xl p-4 space-y-4">
            <div className="flex flex-col md:flex-row items-stretch md:items-center justify-between gap-4">
              {/* Search */}
              <div className="relative flex-1 max-w-md">
                <Search className="w-4 h-4 text-slate-400 absolute left-3.5 top-1/2 -translate-y-1/2" />
                <input
                  type="text"
                  placeholder="Search player, team, trade package..."
                  value={searchQuery}
                  onChange={(e) => setSearchQuery(e.target.value)}
                  className="w-full bg-surface border border-slate-800 rounded-xl pl-10 pr-4 py-2 text-sm text-white placeholder-slate-500 focus:outline-none focus:border-indigo-500 transition-colors"
                />
              </div>

              {/* Type Category Pills */}
              <div className="flex items-center gap-1.5 overflow-x-auto pb-1 md:pb-0">
                <button
                  onClick={() => setTypeFilter('all')}
                  className={`px-3 py-1.5 rounded-lg text-xs font-semibold transition-all ${
                    typeFilter === 'all'
                      ? 'bg-slate-800 text-white border border-slate-700'
                      : 'text-slate-400 hover:text-white'
                  }`}
                >
                  All Types ({transactions.length})
                </button>
                <button
                  onClick={() => setTypeFilter('trade')}
                  className={`px-3 py-1.5 rounded-lg text-xs font-semibold transition-all ${
                    typeFilter === 'trade'
                      ? 'bg-accent-600 text-white shadow-sm'
                      : 'text-slate-400 hover:text-white'
                  }`}
                >
                  Trades ({totalTrades})
                </button>
                <button
                  onClick={() => setTypeFilter('free_agency')}
                  className={`px-3 py-1.5 rounded-lg text-xs font-semibold transition-all ${
                    typeFilter === 'free_agency'
                      ? 'bg-accent-600 text-white shadow-sm'
                      : 'text-slate-400 hover:text-white'
                  }`}
                >
                  Free Agency ({totalFreeAgents})
                </button>
                <button
                  onClick={() => setTypeFilter('draft')}
                  className={`px-3 py-1.5 rounded-lg text-xs font-semibold transition-all ${
                    typeFilter === 'draft'
                      ? 'bg-accent-600 text-white shadow-sm'
                      : 'text-slate-400 hover:text-white'
                  }`}
                >
                  Draft Class ({totalDraftPicks})
                </button>
              </div>

              {/* Team Dropdown & Sort */}
              <div className="flex items-center gap-2">
                <select
                  value={teamFilter}
                  onChange={(e) => setTeamFilter(e.target.value)}
                  className="bg-surface border border-slate-800 rounded-xl px-3 py-2 text-xs text-slate-300 focus:outline-none focus:border-indigo-500"
                >
                  <option value="all">All Franchises (30)</option>
                  {availableTeams.map((tm) => (
                    <option key={tm} value={tm}>
                      {tm}
                    </option>
                  ))}
                </select>

                <select
                  value={sortBy}
                  onChange={(e) => setSortBy(e.target.value as 'wins' | 'nrtg' | 'bpm' | 'date')}
                  className="bg-surface border border-slate-800 rounded-xl px-3 py-2 text-xs text-slate-300 focus:outline-none focus:border-indigo-500"
                >
                  <option value="wins">Sort: Proj Wins (Highest)</option>
                  <option value="nrtg">Sort: Net Rating Impact</option>
                  <option value="bpm">Sort: Player BPM</option>
                  <option value="date">Sort: Date (Recent)</option>
                </select>
              </div>
            </div>
          </div>

          {/* Transaction Cards List */}
          <div className="space-y-4">
            {filteredTransactions.length === 0 ? (
              <div className="text-center py-12 bg-surface-raised/50 rounded-2xl border border-slate-800">
                <AlertTriangle className="w-8 h-8 text-amber-400 mx-auto mb-2 opacity-60" />
                <p className="text-slate-300 font-medium">No transactions matched your filter criteria.</p>
                <button
                  onClick={() => {
                    setSearchQuery('');
                    setTypeFilter('all');
                    setTeamFilter('all');
                    setTierFilter('all');
                  }}
                  className="mt-3 text-xs text-indigo-400 hover:underline"
                >
                  Reset all filters
                </button>
              </div>
            ) : (
              filteredTransactions.map((t) => {
                const isExpanded = expandedTransId === t.id;
                const isTrade = t.type === 'trade';
                const isFA = t.type === 'free_agency';

                return (
                  <div
                    key={t.id}
                    className={`bg-surface-raised/90 border rounded-2xl transition-all overflow-hidden ${
                      isExpanded
                        ? 'border-accent-500/50 shadow-xl shadow-accent-950/20'
                        : 'border-slate-800 hover:border-slate-700'
                    }`}
                  >
                    {/* Header Row */}
                    <div
                      onClick={() => setExpandedTransId(isExpanded ? null : t.id)}
                      className="p-4 sm:p-5 flex flex-col md:flex-row items-start md:items-center justify-between gap-4 cursor-pointer select-none"
                    >
                      {/* Left: Player info & Teams transfer */}
                      <div className="flex items-center gap-3.5 min-w-0">
                        {/* Transaction Type Badge */}
                        <div
                          className={`w-10 h-10 rounded-xl flex items-center justify-center flex-shrink-0 border ${
                            isTrade
                              ? 'bg-indigo-500/10 border-indigo-500/30 text-indigo-400'
                              : isFA
                              ? 'bg-amber-500/10 border-amber-500/30 text-amber-400'
                              : 'bg-emerald-500/10 border-emerald-500/30 text-emerald-400'
                          }`}
                        >
                          {isTrade ? (
                            <Shuffle className="w-5 h-5" />
                          ) : isFA ? (
                            <DollarSign className="w-5 h-5" />
                          ) : (
                            <GraduationCap className="w-5 h-5" />
                          )}
                        </div>

                        {/* Player name & headline */}
                        <div className="min-w-0">
                          <div className="flex items-center gap-2 flex-wrap">
                            <h3 className="font-bold text-base text-white hover:text-indigo-300 transition-colors">
                              {t.player_name}
                            </h3>
                            <span className="text-xs px-2 py-0.5 rounded-md bg-slate-800 text-slate-300 font-mono font-medium">
                              {t.position} • Age {t.age}
                            </span>
                            <span
                              className={`text-[10px] uppercase font-bold px-2 py-0.5 rounded-full font-mono ${
                                isTrade
                                  ? 'bg-indigo-500/20 text-indigo-300 border border-indigo-500/30'
                                  : isFA
                                  ? 'bg-amber-500/20 text-amber-300 border border-amber-500/30'
                                  : 'bg-emerald-500/20 text-emerald-300 border border-emerald-500/30'
                              }`}
                            >
                              {isTrade ? 'Trade' : isFA ? 'Free Agent' : 'Draft Pick'}
                            </span>
                          </div>
                          <p className="text-xs text-slate-400 truncate mt-0.5 max-w-xl">{t.headline}</p>
                        </div>
                      </div>

                      {/* Middle: Movement Pathway (From -> To) */}
                      <div className="flex items-center gap-2.5 bg-surface/70 border border-slate-800/80 px-3.5 py-1.5 rounded-xl flex-shrink-0">
                        {t.from_team ? (
                          <div className="flex items-center gap-1.5">
                            {availableTeams.includes(t.from_team) ? (
                              <TeamLogo team={t.from_team} size="xs" />
                            ) : (
                              <span className="text-[10px] text-slate-400 font-mono">FA / Draft</span>
                            )}
                            <span className="text-xs font-bold text-slate-300">{t.from_team}</span>
                          </div>
                        ) : (
                          <span className="text-[10px] text-slate-400 font-mono">Free Agent</span>
                        )}

                        <ArrowRight className="w-3.5 h-3.5 text-slate-500" />

                        <div className="flex items-center gap-1.5">
                          <TeamLogo team={t.to_team} size="xs" />
                          <span className="text-xs font-bold text-white">{t.to_team}</span>
                        </div>
                      </div>

                      {/* Right: Analytical KPIs */}
                      <div className="flex items-center gap-4 sm:gap-6 self-end md:self-center">
                        <div className="text-right">
                          <span className="text-[10px] uppercase font-mono text-slate-400 block">Win Impact</span>
                          <span className="font-mono font-black text-emerald-400 text-sm flex items-center gap-0.5 justify-end">
                            <TrendingUp className="w-3.5 h-3.5" />
                            +{t.delta_projected_wins}W
                          </span>
                        </div>

                        <div className="text-right">
                          <span className="text-[10px] uppercase font-mono text-slate-400 block">Net Rtg Delta</span>
                          <span className="font-mono font-bold text-indigo-300 text-sm">
                            +{t.delta_net_rating} pts
                          </span>
                        </div>

                        <div className="text-right hidden sm:block">
                          <span className="text-[10px] uppercase font-mono text-slate-400 block">Player BPM</span>
                          <span
                            className={`font-mono font-bold text-sm ${
                              t.player_bpm >= 2.0
                                ? 'text-emerald-400'
                                : t.player_bpm >= 0
                                ? 'text-indigo-300'
                                : 'text-amber-400'
                            }`}
                          >
                            {t.player_bpm >= 0 ? `+${t.player_bpm}` : t.player_bpm}
                          </span>
                        </div>

                        <div className="p-1 rounded-lg bg-slate-800 text-slate-400">
                          {isExpanded ? <ChevronUp className="w-4 h-4" /> : <ChevronDown className="w-4 h-4" />}
                        </div>
                      </div>
                    </div>

                    {/* Expandable Analytical Breakdown Drawer */}
                    {isExpanded && (
                      <div className="border-t border-slate-800/80 bg-surface/60 p-5 space-y-5">
                        {/* Summary & Contract Specs */}
                        <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
                          <div className="md:col-span-2 space-y-2">
                            <span className="text-[11px] font-bold uppercase tracking-wider text-indigo-400 font-mono">
                              Tactical Fit & Analytical Rationale
                            </span>
                            <p className="text-sm text-slate-200 leading-relaxed">{t.analysis.summary}</p>
                          </div>

                          <div className="bg-surface-raised/90 border border-slate-800/80 rounded-xl p-3.5 space-y-2 text-xs">
                            <div className="text-[10px] font-bold uppercase text-slate-400 font-mono">
                              Terms & Asset Details
                            </div>
                            <div className="font-mono font-medium text-amber-300">
                              {t.contract_terms || 'Standard Agreement'}
                            </div>

                            {t.trade_details && t.trade_details.counterparts_received && (
                              <div className="pt-2 border-t border-slate-800">
                                <span className="text-[10px] text-slate-400 block mb-1">Exchange Outgoing:</span>
                                <ul className="space-y-0.5 text-[11px] text-slate-300 font-mono">
                                  {t.trade_details.counterparts_received.map((c, idx) => (
                                    <li key={idx}>• {c}</li>
                                  ))}
                                </ul>
                              </div>
                            )}

                            {t.draft_pick && (
                              <div className="pt-2 border-t border-slate-800">
                                <span className="text-[10px] text-slate-400 block">Draft Pedigree:</span>
                                <span className="font-mono text-emerald-400">
                                  Round {t.draft_pick.round}, Pick #{t.draft_pick.pick} ({t.draft_pick.school_or_club})
                                </span>
                              </div>
                            )}
                          </div>
                        </div>

                        {/* Three Pillars: Offensive Impact, Defensive Impact, Risk Assessment */}
                        <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
                          {/* Offensive Impact */}
                          <div className="bg-surface-raised/60 border border-slate-800/80 rounded-xl p-3.5 space-y-1.5">
                            <div className="flex items-center gap-1.5 text-emerald-400 font-bold text-xs">
                              <TrendingUp className="w-3.5 h-3.5" />
                              <span>Offensive Spacing & Creation</span>
                            </div>
                            <p className="text-xs text-slate-300 leading-relaxed">{t.analysis.offensive_impact}</p>
                          </div>

                          {/* Defensive Impact */}
                          <div className="bg-surface-raised/60 border border-slate-800/80 rounded-xl p-3.5 space-y-1.5">
                            <div className="flex items-center gap-1.5 text-indigo-400 font-bold text-xs">
                              <CheckCircle2 className="w-3.5 h-3.5" />
                              <span>Defensive & Scheme Utility</span>
                            </div>
                            <p className="text-xs text-slate-300 leading-relaxed">{t.analysis.defensive_impact}</p>
                          </div>

                          {/* Risk Assessment */}
                          <div className="bg-surface-raised/60 border border-slate-800/80 rounded-xl p-3.5 space-y-1.5">
                            <div className="flex items-center gap-1.5 text-amber-400 font-bold text-xs">
                              <ShieldAlert className="w-3.5 h-3.5" />
                              <span>Risk & Exposure Profile</span>
                            </div>
                            <p className="text-xs text-slate-300 leading-relaxed">{t.analysis.risk_factor}</p>
                          </div>
                        </div>

                        {/* Quantitative Rotation Breakdown Strip */}
                        <div className="flex flex-wrap items-center justify-between gap-4 pt-3 border-t border-slate-800/60 text-xs">
                          <div className="flex items-center gap-4 text-slate-400 font-mono">
                            <span>
                              Proj MPG: <strong className="text-white">{t.projected_minutes} mpg</strong>
                            </span>
                            <span>
                              Base Pts: <strong className="text-white">{t.player_pts}</strong>
                            </span>
                            <span>
                              Reb: <strong className="text-white">{t.player_reb}</strong>
                            </span>
                            <span>
                              Ast: <strong className="text-white">{t.player_ast}</strong>
                            </span>
                          </div>

                          <div className="flex items-center gap-2">
                            <span className="text-[11px] text-slate-400 font-mono">Tactical Spacing Fit Score:</span>
                            <div className="flex items-center gap-1.5 bg-surface-raised px-2.5 py-1 rounded-md border border-slate-800">
                              <Zap className="w-3 h-3 text-amber-400" />
                              <span className="font-mono font-bold text-white text-xs">{t.fit_score}/100</span>
                            </div>
                          </div>
                        </div>
                      </div>
                    )}
                  </div>
                );
              })
            )}
          </div>
        </div>
      )}

      {/* ========================================================================
          TAB 2: FRANCHISE WINNERS & LOSERS (30 TEAMS RANKINGS)
          ======================================================================== */}
      {activeTab === 'teams' && (
        <div className="space-y-6">
          {/* Header & Conference Filter */}
          <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-4 bg-surface-raised/90 border border-slate-800 rounded-2xl p-4">
            <div>
              <h2 className="text-lg font-bold text-white flex items-center gap-2">
                <span>Franchise Net Talent Impact & Continuity Rankings</span>
                <span className="text-xs font-mono px-2 py-0.5 rounded-full bg-indigo-500/10 text-indigo-400 border border-indigo-500/20">
                  82-Game Zero-Sum Shift
                </span>
              </h2>
              <p className="text-xs text-slate-400 mt-0.5">
                Evaluates aggregate talent acquired minus departed, returning minute continuity (roster_dynamics.R), and
                net win trajectory adjustments.
              </p>
            </div>

            <div className="flex items-center gap-1.5 self-start sm:self-auto">
              <button
                onClick={() => setConfFilter('all')}
                className={`px-3 py-1.5 rounded-lg text-xs font-semibold transition-all ${
                  confFilter === 'all'
                    ? 'bg-slate-800 text-white border border-slate-700'
                    : 'text-slate-400 hover:text-white'
                }`}
              >
                All 30 Teams
              </button>
              <button
                onClick={() => setConfFilter('East')}
                className={`px-3 py-1.5 rounded-lg text-xs font-semibold transition-all ${
                  confFilter === 'East'
                    ? 'bg-accent-600 text-white shadow-sm'
                    : 'text-slate-400 hover:text-white'
                }`}
              >
                Eastern Conference
              </button>
              <button
                onClick={() => setConfFilter('West')}
                className={`px-3 py-1.5 rounded-lg text-xs font-semibold transition-all ${
                  confFilter === 'West'
                    ? 'bg-accent-600 text-white shadow-sm'
                    : 'text-slate-400 hover:text-white'
                }`}
              >
                Western Conference
              </button>
              <button
                type="button"
                onClick={handleExportTeamsCsv}
                title="Export CSV"
                aria-label="Export franchise rankings table as CSV"
                className="p-1.5 rounded-lg border border-slate-800 text-slate-400 hover:text-white hover:border-slate-600 transition-colors"
              >
                <Download className="w-3.5 h-3.5" />
              </button>
            </div>
          </div>

          {/* Grid Layout: Left 30-team rankings table, Right active team deep-dive */}
          <div className="grid grid-cols-1 lg:grid-cols-12 gap-6">
            {/* 30-Team Table (7 cols on lg) */}
            <div className="lg:col-span-7 bg-surface-raised/90 border border-slate-800 rounded-2xl overflow-hidden">
              <div className="overflow-x-auto">
                <table className="w-full text-left text-xs">
                  <thead className="bg-surface/80 border-b border-slate-800 text-slate-400 uppercase font-mono text-[10px]">
                    <tr>
                      <th className="py-3 px-3">Franchise</th>
                      <th className="py-3 px-2 text-center">Grade</th>
                      <th className="py-3 px-2 text-right">Continuity</th>
                      <th className="py-3 px-2 text-right">Net BPM</th>
                      <th className="py-3 px-3 text-right">Net Win Delta</th>
                      <th className="py-3 px-3 text-right">Proj Wins</th>
                    </tr>
                  </thead>
                  <tbody className="divide-y divide-slate-800/60 font-mono">
                    {filteredTeams.map((tm, idx) => {
                      const isSelected = selectedTeamProfile === tm.team;
                      const isPositive = tm.net_wins_change > 0;
                      const isNeutral = tm.net_wins_change === 0;

                      return (
                        <tr
                          key={tm.team}
                          onClick={() => setSelectedTeamProfile(tm.team)}
                          className={`cursor-pointer transition-colors ${
                            isSelected
                              ? 'bg-accent-950/40 border-l-4 border-accent-500'
                              : 'hover:bg-slate-800/40'
                          }`}
                        >
                          <td className="py-2.5 px-3">
                            <div className="flex items-center gap-2">
                              <span className="text-slate-500 text-[10px] w-4">{idx + 1}</span>
                              <TeamLogo team={tm.team} size="xs" />
                              <span className="font-bold text-white font-sans">{tm.team}</span>
                              <span className="text-[11px] text-slate-400 hidden sm:inline font-sans truncate">
                                {tm.team_name}
                              </span>
                            </div>
                          </td>

                          <td className="py-2.5 px-2 text-center">
                            <span
                              className={`px-2 py-0.5 rounded text-[10px] font-bold ${
                                tm.grade.startsWith('A')
                                  ? 'bg-emerald-500/20 text-emerald-300 border border-emerald-500/30'
                                  : tm.grade.startsWith('B')
                                  ? 'bg-indigo-500/20 text-indigo-300 border border-indigo-500/30'
                                  : 'bg-amber-500/20 text-amber-300 border border-amber-500/30'
                              }`}
                            >
                              {tm.grade}
                            </span>
                          </td>

                          <td className="py-2.5 px-2 text-right text-slate-300">
                            {Math.round(tm.roster_continuity_pct * 100)}%
                          </td>

                          <td className="py-2.5 px-2 text-right">
                            <span className={tm.net_bpm_added >= 0 ? 'text-emerald-400' : 'text-rose-400'}>
                              {tm.net_bpm_added >= 0 ? `+${tm.net_bpm_added}` : tm.net_bpm_added}
                            </span>
                          </td>

                          <td className="py-2.5 px-3 text-right">
                            <span
                              className={`font-bold inline-flex items-center gap-0.5 ${
                                isPositive ? 'text-emerald-400' : isNeutral ? 'text-slate-400' : 'text-rose-400'
                              }`}
                            >
                              {isPositive ? `+${tm.net_wins_change}W` : `${tm.net_wins_change}W`}
                            </span>
                          </td>

                          <td className="py-2.5 px-3 text-right font-bold text-white">
                            {tm.projected_wins_with_moves}
                          </td>
                        </tr>
                      );
                    })}
                  </tbody>
                </table>
              </div>
            </div>

            {/* Selected Franchise Detail Card (5 cols on lg) */}
            <div className="lg:col-span-5 space-y-4">
              {activeTeamDetail && (
                <div className="bg-surface-raised/90 border border-slate-800 rounded-2xl p-5 space-y-5 sticky top-20">
                  {/* Franchise Header */}
                  <div className="flex items-center justify-between border-b border-slate-800 pb-4">
                    <div className="flex items-center gap-3">
                      <TeamLogo team={activeTeamDetail.team} size="lg" />
                      <div>
                        <div className="flex items-center gap-2">
                          <h3 className="text-xl font-black text-white">{activeTeamDetail.team_name}</h3>
                          <span className="text-xs font-mono font-bold px-2 py-0.5 rounded bg-indigo-500/20 text-indigo-300 border border-indigo-500/30">
                            Grade: {activeTeamDetail.grade}
                          </span>
                        </div>
                        <p className="text-xs text-slate-400 font-mono">
                          {activeTeamDetail.conference} • {activeTeamDetail.division} •{' '}
                          <span className="text-amber-400">{activeTeamDetail.strategic_posture}</span>
                        </p>
                      </div>
                    </div>
                  </div>

                  {/* Stat Metrics Grid */}
                  <div className="grid grid-cols-3 gap-2 text-center text-xs">
                    <div className="bg-surface p-2.5 rounded-xl border border-slate-800/80">
                      <span className="text-[10px] text-slate-400 block font-mono">Baseline Wins</span>
                      <span className="font-mono font-bold text-slate-300 text-sm">
                        {activeTeamDetail.baseline_wins}
                      </span>
                    </div>

                    <div className="bg-surface p-2.5 rounded-xl border border-slate-800/80">
                      <span className="text-[10px] text-slate-400 block font-mono">Net Win Delta</span>
                      <span
                        className={`font-mono font-bold text-sm ${
                          activeTeamDetail.net_wins_change >= 0 ? 'text-emerald-400' : 'text-rose-400'
                        }`}
                      >
                        {activeTeamDetail.net_wins_change >= 0
                          ? `+${activeTeamDetail.net_wins_change}W`
                          : `${activeTeamDetail.net_wins_change}W`}
                      </span>
                    </div>

                    <div className="bg-surface p-2.5 rounded-xl border border-slate-800/80">
                      <span className="text-[10px] text-slate-400 block font-mono">Continuity</span>
                      <span className="font-mono font-bold text-indigo-300 text-sm">
                        {Math.round(activeTeamDetail.roster_continuity_pct * 100)}%
                      </span>
                    </div>
                  </div>

                  {/* Offseason Verdict */}
                  <div className="bg-surface/70 border border-slate-800/80 rounded-xl p-3.5 space-y-1.5">
                    <div className="text-[10px] font-bold uppercase tracking-wider text-slate-400 font-mono">
                      Analytical Verdict
                    </div>
                    <p className="text-xs text-slate-200 leading-relaxed font-sans">
                      {activeTeamDetail.offseason_verdict}
                    </p>
                  </div>

                  {/* Incoming Additions */}
                  <div className="space-y-2">
                    <div className="text-[10px] font-bold uppercase tracking-wider text-emerald-400 font-mono flex items-center justify-between">
                      <span>Additions ({activeTeamDetail.additions.length})</span>
                      <span className="text-slate-500">BPM</span>
                    </div>
                    {activeTeamDetail.additions.length === 0 ? (
                      <p className="text-xs text-slate-500 italic">No major recorded additions.</p>
                    ) : (
                      <div className="space-y-1.5">
                        {activeTeamDetail.additions.map((a, idx) => (
                          <div
                            key={idx}
                            className="flex items-center justify-between p-2 rounded-lg bg-surface/60 border border-slate-800/60 text-xs font-mono"
                          >
                            <span className="font-medium text-white">{a.name} ({a.pos})</span>
                            <span className="text-emerald-400 font-bold">+{a.bpm}</span>
                          </div>
                        ))}
                      </div>
                    )}
                  </div>

                  {/* Departures */}
                  <div className="space-y-2">
                    <div className="text-[10px] font-bold uppercase tracking-wider text-rose-400 font-mono flex items-center justify-between">
                      <span>Departures ({activeTeamDetail.departures.length})</span>
                      <span className="text-slate-500">BPM</span>
                    </div>
                    {activeTeamDetail.departures.length === 0 ? (
                      <p className="text-xs text-slate-500 italic">No major departures recorded.</p>
                    ) : (
                      <div className="space-y-1.5">
                        {activeTeamDetail.departures.map((d, idx) => (
                          <div
                            key={idx}
                            className="flex items-center justify-between p-2 rounded-lg bg-surface/60 border border-slate-800/60 text-xs font-mono"
                          >
                            <span className="font-medium text-slate-300">{d.name} ({d.pos})</span>
                            <span className="text-rose-400 font-bold">+{d.bpm}</span>
                          </div>
                        ))}
                      </div>
                    )}
                  </div>

                  {/* Draft Picks */}
                  {activeTeamDetail.draft_picks.length > 0 && (
                    <div className="space-y-2 pt-2 border-t border-slate-800">
                      <div className="text-[10px] font-bold uppercase tracking-wider text-indigo-400 font-mono">
                        Draft Capital Added
                      </div>
                      <div className="space-y-1.5">
                        {activeTeamDetail.draft_picks.map((dp, idx) => (
                          <div
                            key={idx}
                            className="flex items-center justify-between p-2 rounded-lg bg-indigo-950/20 border border-indigo-500/20 text-xs font-mono"
                          >
                            <span className="font-medium text-white">
                              #{dp.pick} {dp.name}
                            </span>
                            <span className="text-[11px] text-indigo-300 font-sans">{dp.school}</span>
                          </div>
                        ))}
                      </div>
                    </div>
                  )}
                </div>
              )}
            </div>
          </div>
        </div>
      )}

      {/* ========================================================================
          TAB 3: INTERACTIVE TRADE & SIGNING MACHINE (WHAT-IF SANDBOX)
          ======================================================================== */}
      {activeTab === 'machine' && (
        <div className="space-y-6">
          {/* Machine Header */}
          <div className="bg-surface-raised/90 border border-slate-800 rounded-2xl p-5 space-y-2">
            <div className="flex items-center gap-2">
              <span className="p-1.5 rounded-lg bg-amber-500/10 text-amber-400 border border-amber-500/20">
                <Scale className="w-5 h-5" />
              </span>
              <h2 className="text-xl font-black text-white">Bottom-Up Trade & Roster Reallocation Machine</h2>
            </div>
            <p className="text-sm text-slate-300 max-w-3xl">
              Dynamically evaluate what-if off-season trade scenarios. The engine recalculates the 240-minute top-9
              rotation, weights player BPM contributions, and propagates net margin shifts through the calibrated{' '}
              <span className="font-mono text-amber-400">MARGIN_SIGMA = 11.8</span> model.
            </p>
          </div>

          {/* Trade Setup Controls Grid */}
          <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
            {/* Team A Sandbox Box */}
            <div className="bg-surface-raised/90 border border-slate-800 rounded-2xl p-5 space-y-4">
              <div className="flex items-center justify-between border-b border-slate-800 pb-3">
                <div className="flex items-center gap-2.5">
                  <TeamLogo team={sandboxTeamA} size="md" />
                  <div>
                    <span className="text-xs text-slate-400 font-mono block">Primary Franchise (Team A)</span>
                    <select
                      value={sandboxTeamA}
                      onChange={(e) => setSandboxTeamA(e.target.value)}
                      className="bg-surface border border-slate-800 rounded-lg px-2.5 py-1 text-sm font-bold text-white focus:outline-none focus:border-indigo-500"
                    >
                      {availableTeams.map((t) => (
                        <option key={t} value={t}>
                          {t}
                        </option>
                      ))}
                    </select>
                  </div>
                </div>

                <div className="text-right">
                  <span className="text-[10px] text-slate-400 font-mono block">Baseline Proj</span>
                  <span className="font-mono font-bold text-white text-sm">
                    {sandboxCalculation.teamA.baseWins} Wins
                  </span>
                </div>
              </div>

              {/* Outgoing Players Selector */}
              <div className="space-y-2">
                <label className="text-xs font-bold uppercase tracking-wider text-rose-400 font-mono block">
                  Outgoing Assets from {sandboxTeamA}:
                </label>
                <div className="flex flex-wrap gap-1.5 min-h-[30px] items-center">
                  {sandboxOutgoingA.length > 0 ? (
                    sandboxOutgoingA.map((p, idx) => (
                      <span
                        key={idx}
                        className="inline-flex items-center gap-1.5 px-3 py-1 rounded-lg bg-rose-500/10 text-rose-300 border border-rose-500/20 text-xs font-mono"
                      >
                        <span>{p}</span>
                        <button
                          onClick={() => setSandboxOutgoingA(sandboxOutgoingA.filter((_, i) => i !== idx))}
                          className="text-rose-400 hover:text-white"
                        >
                          ×
                        </button>
                      </span>
                    ))
                  ) : (
                    <span className="text-slate-500 text-xs italic">No outgoing players selected</span>
                  )}
                </div>
                {/* Team A Roster Dropdown */}
                <div className="flex items-center gap-2 pt-1">
                  <select
                    id="select-out-a"
                    defaultValue=""
                    onChange={(e) => {
                      const val = e.target.value;
                      if (val && !sandboxOutgoingA.includes(val)) {
                        setSandboxOutgoingA([...sandboxOutgoingA, val]);
                        e.target.value = '';
                      }
                    }}
                    className="flex-1 bg-surface border border-slate-800 rounded-lg px-3 py-1.5 text-xs text-white focus:outline-none focus:border-rose-500"
                  >
                    <option value="" disabled>
                      Select player from {sandboxTeamA} active roster...
                    </option>
                    {rosterTeamA
                      .filter((p) => !sandboxOutgoingA.includes(p.player_name))
                      .map((p) => (
                        <option key={p.player_name} value={p.player_name}>
                          {p.player_name} ({p.position} • {p.proj_mpg} mpg • {p.proj_pts} ppg)
                        </option>
                      ))}
                  </select>
                </div>
              </div>

              {/* Incoming Players Selector (from Trade Partner B) */}
              <div className="space-y-2">
                <label className="text-xs font-bold uppercase tracking-wider text-emerald-400 font-mono block">
                  Incoming Acquisitions to {sandboxTeamA} (from {sandboxTeamB}):
                </label>
                <div className="flex flex-wrap gap-1.5 min-h-[30px] items-center">
                  {sandboxIncomingA.length > 0 ? (
                    sandboxIncomingA.map((p, idx) => (
                      <span
                        key={idx}
                        className="inline-flex items-center gap-1.5 px-3 py-1 rounded-lg bg-emerald-500/10 text-emerald-300 border border-emerald-500/20 text-xs font-mono"
                      >
                        <span>{p}</span>
                        <button
                          onClick={() => setSandboxIncomingA(sandboxIncomingA.filter((_, i) => i !== idx))}
                          className="text-emerald-400 hover:text-white"
                        >
                          ×
                        </button>
                      </span>
                    ))
                  ) : (
                    <span className="text-slate-500 text-xs italic">No incoming players selected</span>
                  )}
                </div>
                {/* Team B Active Roster Dropdown */}
                <div className="flex items-center gap-2 pt-1">
                  <select
                    id="select-in-b"
                    defaultValue=""
                    onChange={(e) => {
                      const val = e.target.value;
                      if (val && !sandboxIncomingA.includes(val)) {
                        setSandboxIncomingA([...sandboxIncomingA, val]);
                        e.target.value = '';
                      }
                    }}
                    className="flex-1 bg-surface border border-slate-800 rounded-lg px-3 py-1.5 text-xs text-white focus:outline-none focus:border-emerald-500"
                  >
                    <option value="" disabled>
                      Select player from {sandboxTeamB} active roster...
                    </option>
                    {rosterTeamB
                      .filter((p) => !sandboxIncomingA.includes(p.player_name))
                      .map((p) => (
                        <option key={p.player_name} value={p.player_name}>
                          {p.player_name} ({p.position} • {p.proj_mpg} mpg • {p.proj_pts} ppg)
                        </option>
                      ))}
                  </select>
                </div>
              </div>
            </div>

            {/* Team B Sandbox Box */}
            <div className="bg-surface-raised/90 border border-slate-800 rounded-2xl p-5 space-y-4">
              <div className="flex items-center justify-between border-b border-slate-800 pb-3">
                <div className="flex items-center gap-2.5">
                  <TeamLogo team={sandboxTeamB} size="md" />
                  <div>
                    <span className="text-xs text-slate-400 font-mono block">Trade Partner (Team B)</span>
                    <select
                      value={sandboxTeamB}
                      onChange={(e) => setSandboxTeamB(e.target.value)}
                      className="bg-surface border border-slate-800 rounded-lg px-2.5 py-1 text-sm font-bold text-white focus:outline-none focus:border-indigo-500"
                    >
                      {availableTeams.map((t) => (
                        <option key={t} value={t}>
                          {t}
                        </option>
                      ))}
                    </select>
                  </div>
                </div>

                <div className="text-right">
                  <span className="text-[10px] text-slate-400 font-mono block">Baseline Proj</span>
                  <span className="font-mono font-bold text-white text-sm">
                    {sandboxCalculation.teamB.baseWins} Wins
                  </span>
                </div>
              </div>

              {/* Team B Exchange Summary */}
              <div className="space-y-3 pt-2">
                <div className="p-3 rounded-xl bg-surface/70 border border-slate-800/80 space-y-1.5">
                  <span className="text-[11px] font-bold uppercase tracking-wider text-slate-400 font-mono">
                    Assets Received by {sandboxTeamB}:
                  </span>
                  <div className="flex flex-wrap gap-1 font-mono text-xs text-emerald-300">
                    {sandboxOutgoingA.length > 0 ? (
                      sandboxOutgoingA.map((p, i) => (
                        <span key={i} className="px-2 py-0.5 rounded bg-emerald-500/10 border border-emerald-500/20">
                          {p}
                        </span>
                      ))
                    ) : (
                      <span className="text-slate-500 italic">None selected</span>
                    )}
                  </div>
                </div>

                <div className="p-3 rounded-xl bg-surface/70 border border-slate-800/80 space-y-1.5">
                  <span className="text-[11px] font-bold uppercase tracking-wider text-slate-400 font-mono">
                    Assets Relinquished by {sandboxTeamB}:
                  </span>
                  <div className="flex flex-wrap gap-1 font-mono text-xs text-rose-300">
                    {sandboxIncomingA.length > 0 ? (
                      sandboxIncomingA.map((p, i) => (
                        <span key={i} className="px-2 py-0.5 rounded bg-rose-500/10 border border-rose-500/20">
                          {p}
                        </span>
                      ))
                    ) : (
                      <span className="text-slate-500 italic">None selected</span>
                    )}
                  </div>
                </div>
              </div>
            </div>
          </div>

          {/* Real-Time Mathematical Simulation Result Card */}
          <div className="bg-gradient-to-r from-slate-900 via-indigo-950/30 to-slate-900 border border-indigo-500/40 rounded-2xl p-6 space-y-5 shadow-2xl">
            <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-3 border-b border-slate-800/80 pb-4">
              <div className="flex items-center gap-2">
                <Sparkles className="w-5 h-5 text-indigo-400" />
                <h3 className="text-lg font-black text-white">Calculated Post-Trade Win Trajectory</h3>
              </div>
              <span className="text-xs font-mono text-slate-400">
                Formula: Δ Wins = Φ( Δ Nrtg / 11.8 ) × 82 Games
              </span>
            </div>

            <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
              {/* Team A Simulation Result */}
              <div className="bg-surface/80 border border-slate-800/90 rounded-xl p-4 space-y-3">
                <div className="flex items-center justify-between">
                  <div className="flex items-center gap-2">
                    <TeamLogo team={sandboxCalculation.teamA.team} size="sm" />
                    <span className="font-bold text-white text-base">{sandboxCalculation.teamA.team} Impact</span>
                  </div>
                  <span
                    className={`font-mono font-black text-base ${
                      sandboxCalculation.teamA.deltaWins >= 0 ? 'text-emerald-400' : 'text-rose-400'
                    }`}
                  >
                    {sandboxCalculation.teamA.deltaWins >= 0
                      ? `+${sandboxCalculation.teamA.deltaWins}W`
                      : `${sandboxCalculation.teamA.deltaWins}W`}
                  </span>
                </div>

                <div className="grid grid-cols-2 gap-2 text-xs font-mono">
                  <div className="bg-surface-raised p-2 rounded-lg">
                    <span className="text-[10px] text-slate-400 block">Post-Trade Wins</span>
                    <span className="font-bold text-white text-sm">
                      {sandboxCalculation.teamA.newWins} Wins
                    </span>
                  </div>
                  <div className="bg-surface-raised p-2 rounded-lg">
                    <span className="text-[10px] text-slate-400 block">Net Rating Shift</span>
                    <span
                      className={`font-bold text-sm ${
                        sandboxCalculation.teamA.netRatingShift >= 0 ? 'text-emerald-400' : 'text-rose-400'
                      }`}
                    >
                      {sandboxCalculation.teamA.netRatingShift >= 0
                        ? `+${sandboxCalculation.teamA.netRatingShift}`
                        : sandboxCalculation.teamA.netRatingShift}{' '}
                      pts/100
                    </span>
                  </div>
                </div>
              </div>

              {/* Team B Simulation Result */}
              <div className="bg-surface/80 border border-slate-800/90 rounded-xl p-4 space-y-3">
                <div className="flex items-center justify-between">
                  <div className="flex items-center gap-2">
                    <TeamLogo team={sandboxCalculation.teamB.team} size="sm" />
                    <span className="font-bold text-white text-base">{sandboxCalculation.teamB.team} Impact</span>
                  </div>
                  <span
                    className={`font-mono font-black text-base ${
                      sandboxCalculation.teamB.deltaWins >= 0 ? 'text-emerald-400' : 'text-rose-400'
                    }`}
                  >
                    {sandboxCalculation.teamB.deltaWins >= 0
                      ? `+${sandboxCalculation.teamB.deltaWins}W`
                      : `${sandboxCalculation.teamB.deltaWins}W`}
                  </span>
                </div>

                <div className="grid grid-cols-2 gap-2 text-xs font-mono">
                  <div className="bg-surface-raised p-2 rounded-lg">
                    <span className="text-[10px] text-slate-400 block">Post-Trade Wins</span>
                    <span className="font-bold text-white text-sm">
                      {sandboxCalculation.teamB.newWins} Wins
                    </span>
                  </div>
                  <div className="bg-surface-raised p-2 rounded-lg">
                    <span className="text-[10px] text-slate-400 block">Net Rating Shift</span>
                    <span
                      className={`font-bold text-sm ${
                        sandboxCalculation.teamB.netRatingShift >= 0 ? 'text-emerald-400' : 'text-rose-400'
                      }`}
                    >
                      {sandboxCalculation.teamB.netRatingShift >= 0
                        ? `+${sandboxCalculation.teamB.netRatingShift}`
                        : sandboxCalculation.teamB.netRatingShift}{' '}
                      pts/100
                    </span>
                  </div>
                </div>
              </div>
            </div>
          </div>
        </div>
      )}

      {/* ========================================================================
          TAB 4: DRAFT CLASS & ROOKIE PROJECTIONS DEEP DIVE
          ======================================================================== */}
      {activeTab === 'draft' && (
        <div className="space-y-6">
          {/* Header */}
          <div className="bg-surface-raised/90 border border-slate-800 rounded-2xl p-5 flex flex-col sm:flex-row sm:items-center justify-between gap-4">
            <div>
              <div className="flex items-center gap-2">
                <GraduationCap className="w-5 h-5 text-emerald-400" />
                <h2 className="text-xl font-black text-white">2026-2027 Rookie Class Projections & Empirical Priors</h2>
              </div>
              <p className="text-xs text-slate-400 mt-0.5">
                Full 60-player two-round draft class initialized at the canonical <span className="font-mono text-emerald-400">-2.0 BPM</span>{' '}
                replacement floor with Empirical Bayes lottery scale adjustments from prep/collegiate box production and physical archetypes.
              </p>
            </div>

            <div className="flex items-center gap-2 text-xs font-mono bg-surface px-3 py-1.5 rounded-xl border border-slate-800">
              <span className="text-slate-400">Class Size:</span>
              <span className="font-bold text-white">{draftProspects.length} Total Rookies</span>
              <span className="text-slate-500">|</span>
              <span className="text-emerald-400">Showing {filteredDraftProspects.length}</span>
            </div>
          </div>

          {/* Draft Filters & Search Bar */}
          <div className="bg-surface-raised/90 border border-slate-800 rounded-2xl p-4 flex flex-col md:flex-row items-stretch md:items-center justify-between gap-4">
            {/* Search */}
            <div className="relative flex-1 max-w-md">
              <Search className="w-4 h-4 text-slate-400 absolute left-3.5 top-1/2 -translate-y-1/2" />
              <input
                type="text"
                placeholder="Search rookie, team, college/club, or archetype..."
                value={draftSearch}
                onChange={(e) => setDraftSearch(e.target.value)}
                className="w-full bg-surface border border-slate-800 rounded-xl pl-10 pr-4 py-2 text-sm text-white placeholder-slate-500 focus:outline-none focus:border-indigo-500 transition-colors"
              />
            </div>

            {/* Round 1 / Round 2 Toggle Pills */}
            <div className="flex items-center gap-1.5 bg-surface p-1 rounded-xl border border-slate-800">
              <button
                onClick={() => setDraftRoundFilter('all')}
                className={`px-3 py-1 rounded-lg text-xs font-semibold transition-all ${
                  draftRoundFilter === 'all'
                    ? 'bg-slate-800 text-white shadow-sm'
                    : 'text-slate-400 hover:text-white'
                }`}
              >
                All Rounds (60)
              </button>
              <button
                onClick={() => setDraftRoundFilter(1)}
                className={`px-3 py-1 rounded-lg text-xs font-semibold transition-all ${
                  draftRoundFilter === 1
                    ? 'bg-accent-600 text-white shadow-sm'
                    : 'text-slate-400 hover:text-white'
                }`}
              >
                Round 1 (Picks 1–30)
              </button>
              <button
                onClick={() => setDraftRoundFilter(2)}
                className={`px-3 py-1 rounded-lg text-xs font-semibold transition-all ${
                  draftRoundFilter === 2
                    ? 'bg-accent-600 text-white shadow-sm'
                    : 'text-slate-400 hover:text-white'
                }`}
              >
                Round 2 (Picks 31–60)
              </button>
            </div>

            {/* Position Filter Pills */}
            <div className="flex items-center gap-1.5 overflow-x-auto pb-1 md:pb-0">
              <button
                onClick={() => setDraftPosFilter('all')}
                className={`px-3 py-1.5 rounded-lg text-xs font-semibold transition-all ${
                  draftPosFilter === 'all'
                    ? 'bg-slate-800 text-white border border-slate-700'
                    : 'text-slate-400 hover:text-white'
                }`}
              >
                All Pos
              </button>
              <button
                onClick={() => setDraftPosFilter('G')}
                className={`px-3 py-1.5 rounded-lg text-xs font-semibold transition-all ${
                  draftPosFilter === 'G'
                    ? 'bg-accent-600 text-white shadow-sm'
                    : 'text-slate-400 hover:text-white'
                }`}
              >
                Guards
              </button>
              <button
                onClick={() => setDraftPosFilter('F')}
                className={`px-3 py-1.5 rounded-lg text-xs font-semibold transition-all ${
                  draftPosFilter === 'F'
                    ? 'bg-accent-600 text-white shadow-sm'
                    : 'text-slate-400 hover:text-white'
                }`}
              >
                Forwards
              </button>
              <button
                onClick={() => setDraftPosFilter('C')}
                className={`px-3 py-1.5 rounded-lg text-xs font-semibold transition-all ${
                  draftPosFilter === 'C'
                    ? 'bg-accent-600 text-white shadow-sm'
                    : 'text-slate-400 hover:text-white'
                }`}
              >
                Centers
              </button>
            </div>

            {/* Tier Filter Dropdown */}
            <div className="flex items-center gap-2">
              <select
                value={draftTierFilter}
                onChange={(e) => setDraftTierFilter(e.target.value)}
                className="bg-surface border border-slate-800 rounded-xl px-3 py-2 text-xs text-slate-300 focus:outline-none focus:border-indigo-500"
              >
                <option value="all">All Upside Tiers</option>
                <option value="Franchise Pillar">Franchise Pillar</option>
                <option value="Core Starter">Core Starter</option>
                <option value="Specialist">Specialist</option>
                <option value="Developmental">Developmental</option>
              </select>
            </div>
          </div>

          {/* Draft Prospect Cards Grid */}
          {filteredDraftProspects.length === 0 ? (
            <div className="text-center py-12 bg-surface-raised/50 rounded-2xl border border-slate-800">
              <AlertTriangle className="w-8 h-8 text-amber-400 mx-auto mb-2 opacity-60" />
              <p className="text-slate-300 font-medium">No rookies matched your filter criteria.</p>
              <button
                onClick={() => {
                  setDraftSearch('');
                  setDraftPosFilter('all');
                  setDraftTierFilter('all');
                }}
                className="mt-3 text-xs text-indigo-400 hover:underline"
              >
                Reset rookie filters
              </button>
            </div>
          ) : (
            <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-5">
              {filteredDraftProspects.map((prospect) => (
              <div
                key={prospect.pick}
                className="bg-surface-raised/90 border border-slate-800 rounded-2xl p-5 space-y-4 hover:border-slate-700 transition-all flex flex-col justify-between"
              >
                <div className="space-y-3">
                  {/* Pick Badge & Team */}
                  <div className="flex items-center justify-between">
                    <div className="flex items-center gap-2">
                      <span className={`px-2.5 py-1 rounded-lg border font-mono font-black text-xs ${
                        (prospect.round || (prospect.pick <= 30 ? 1 : 2)) === 1
                          ? 'bg-emerald-500/10 text-emerald-400 border-emerald-500/20'
                          : 'bg-amber-500/10 text-amber-400 border-amber-500/20'
                      }`}>
                        R{prospect.round || (prospect.pick <= 30 ? 1 : 2)} • PICK #{prospect.pick}
                      </span>
                      {prospect.trade_note && (
                        <span className="px-2 py-0.5 rounded-md bg-indigo-500/10 text-indigo-300 border border-indigo-500/20 font-mono text-[10px] font-semibold flex items-center gap-1">
                          <span>⇄</span>
                          <span className="truncate max-w-[160px]">{prospect.trade_note}</span>
                        </span>
                      )}
                    </div>
                    <div className="flex items-center gap-1.5">
                      <TeamLogo team={prospect.team} size="xs" />
                      <span className="font-bold text-white text-xs">{prospect.team}</span>
                    </div>
                  </div>

                  {/* Player Name & Pedigree */}
                  <div>
                    <h3 className="font-black text-lg text-white">{prospect.player_name}</h3>
                    <div className="flex items-center gap-2 text-xs text-slate-400 font-mono mt-0.5">
                      <span>{prospect.position}</span>
                      <span>•</span>
                      <span>{prospect.height}</span>
                      <span>•</span>
                      <span className="text-indigo-300 truncate">{prospect.school_or_club}</span>
                    </div>
                  </div>

                  {/* Archetype & Upside Tier */}
                  <div className="space-y-1 bg-surface/70 p-2.5 rounded-xl border border-slate-800/80">
                    <span className="text-[10px] uppercase font-bold text-slate-400 font-mono block">
                      Role Archetype
                    </span>
                    <span className="font-bold text-amber-300 text-xs">{prospect.archetype}</span>
                  </div>

                  {/* Metrics Strip: Prior BPM & Proj MPG */}
                  <div className="grid grid-cols-2 gap-2 text-xs font-mono">
                    <div className="bg-surface p-2 rounded-lg border border-slate-800/60">
                      <span className="text-[10px] text-slate-400 block">Rookie BPM Prior</span>
                      <span className="font-bold text-emerald-400">{prospect.projected_bpm_prior}</span>
                    </div>
                    <div className="bg-surface p-2 rounded-lg border border-slate-800/60">
                      <span className="text-[10px] text-slate-400 block">Proj Minutes</span>
                      <span className="font-bold text-indigo-300">{prospect.projected_mpg} mpg</span>
                    </div>
                  </div>

                  {/* Strengths */}
                  <div className="space-y-1">
                    <span className="text-[10px] font-bold uppercase tracking-wider text-emerald-400 font-mono block">
                      Core Strengths:
                    </span>
                    <ul className="text-xs text-slate-300 space-y-0.5 font-sans">
                      {prospect.strengths.map((s, idx) => (
                        <li key={idx} className="flex items-start gap-1.5">
                          <span className="text-emerald-400 text-[10px] mt-0.5">✓</span>
                          <span>{s}</span>
                        </li>
                      ))}
                    </ul>
                  </div>

                  {/* Swing Skills */}
                  <div className="space-y-1">
                    <span className="text-[10px] font-bold uppercase tracking-wider text-amber-400 font-mono block">
                      Swing Skill / Risk:
                    </span>
                    <ul className="text-xs text-slate-400 space-y-0.5 font-sans">
                      {prospect.swing_skills.map((sw, idx) => (
                        <li key={idx} className="flex items-start gap-1.5">
                          <span className="text-amber-400 text-[10px] mt-0.5">⚠</span>
                          <span>{sw}</span>
                        </li>
                      ))}
                    </ul>
                  </div>
                </div>

                {/* NBA Player Comp Footnote */}
                <div className="pt-3 border-t border-slate-800 text-xs font-mono text-slate-400">
                  <span className="text-slate-500 block text-[10px] uppercase">Style Comp:</span>
                  <span className="text-indigo-300 font-medium">{prospect.comp}</span>
                </div>
              </div>
            ))}
          </div>
          )}
        </div>
      )}
    </div>
  );
};
