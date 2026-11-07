'use client';

import React, { useState, useMemo, useEffect } from 'react';
import Link from 'next/link';
import {
  Sparkles,
  CheckCircle2,
  Clock,
  Archive,
  Coins,
  FileText,
  Search,
  ExternalLink,
  Calendar,
  ArrowRight,
  ShieldAlert,
  Users,
  History,
  Info,
} from 'lucide-react';
import { BASE_PATH } from '@/lib/basePath';
import {
  OffseasonMonitorDataset,
  OffseasonEditionSummary,
} from '@/lib/offseasonTypes';

type EditionData = OffseasonMonitorDataset['editions'][number] & {
  totalConfirmedCount?: number;
};

interface Props {
  initialDataset: OffseasonMonitorDataset | null;
}

export const OffseasonMonitorClient: React.FC<Props> = ({ initialDataset }) => {
  const dataset = initialDataset;
  const [archivedEditions, setArchivedEditions] = useState<Record<number, EditionData>>({});
  const [isLoadingArchive, setIsLoadingArchive] = useState(false);

  // Pagination for Confirmed Transactions Ledger (bounds render volume)
  const CONFIRMED_PAGE_SIZE = 25;
  const [confirmedPage, setConfirmedPage] = useState<number>(1);

  const availableEditions: OffseasonEditionSummary[] = useMemo(() => {
    return dataset?.availableEditions || [];
  }, [dataset]);

  const latestWeekNumber = useMemo(() => {
    if (dataset?.currentWeekNumber) return dataset.currentWeekNumber;
    if (availableEditions.length > 0) return availableEditions[availableEditions.length - 1].weekNumber;
    return 1;
  }, [dataset, availableEditions]);

  const [selectedWeek, setSelectedWeek] = useState<number>(latestWeekNumber);

  // Drill-down tab selection
  const [activeTab, setActiveTab] = useState<
    'brief' | 'confirmed' | 'reported' | 'expired' | 'cbt' | 'labor'
  >('brief');

  // Filters for Confirmed Transactions Ledger
  const [confirmedSearch, setConfirmedSearch] = useState('');
  const [confirmedTeamFilter, setConfirmedTeamFilter] = useState('all');
  const [confirmedTypeFilter, setConfirmedTypeFilter] = useState('all');

  // Reset pagination to page 1 whenever filters or selected week change
  useEffect(() => {
    setConfirmedPage(1);
  }, [confirmedSearch, confirmedTeamFilter, confirmedTypeFilter, selectedWeek]);

  // Filters for Reported Radar
  const [reportedSearch, setReportedSearch] = useState('');
  const [reportedCatFilter, setReportedCatFilter] = useState('all');

  // Filters for Expired Claims
  const [expiredCatFilter, setExpiredCatFilter] = useState('all');

  // Lazy-load archived edition if selected
  useEffect(() => {
    const editionSummary = availableEditions.find((e) => e.weekNumber === selectedWeek);
    if (!editionSummary) return;

    const alreadyInEditions = dataset?.editions.some((e) => e.weekNumber === selectedWeek);
    const alreadyInArchived = Boolean(archivedEditions[selectedWeek]);

    if (editionSummary.isArchived && !alreadyInEditions && !alreadyInArchived) {
      setIsLoadingArchive(true);
      fetch(`${BASE_PATH}/data/archive/offseason_2026_editions.json`)
        .then((res) => {
          if (!res.ok) throw new Error('Archive not found');
          return res.json();
        })
        .then((data: { editions?: EditionData[] } | EditionData[]) => {
          const list = Array.isArray(data) ? data : data.editions || [];
          const map: Record<number, EditionData> = {};
          list.forEach((item) => {
            map[item.weekNumber] = item;
          });
          setArchivedEditions((prev) => ({ ...prev, ...map }));
        })
        .catch((err) => {
          console.error('Failed to load archived edition:', err);
        })
        .finally(() => {
          setIsLoadingArchive(false);
        });
    }
  }, [selectedWeek, availableEditions, dataset, archivedEditions]);

  // Resolve current active edition object
  const currentEdition: EditionData | null = useMemo(() => {
    if (!dataset) return null;
    const foundDirect = dataset.editions.find((ed) => ed.weekNumber === selectedWeek);
    if (foundDirect) return foundDirect;
    if (archivedEditions[selectedWeek]) return archivedEditions[selectedWeek];
    return dataset.editions[0] || null;
  }, [dataset, selectedWeek, archivedEditions]);

  // Unique teams & transaction types for confirmed filters, memoized with distribution counts
  const confirmedTeams = useMemo(() => {
    if (!currentEdition) return [];
    const set = new Set<string>();
    currentEdition.confirmedChanges.forEach((c) => {
      if (c.team) set.add(c.team);
    });
    return Array.from(set).sort();
  }, [currentEdition]);

  const confirmedTypes = useMemo(() => {
    if (!currentEdition) return [];
    const set = new Set<string>();
    currentEdition.confirmedChanges.forEach((c) => {
      if (c.transactionType) set.add(c.transactionType);
    });
    return Array.from(set).sort();
  }, [currentEdition]);

  const confirmedTypeCounts = useMemo(() => {
    if (!currentEdition) return {};
    const counts: Record<string, number> = {};
    currentEdition.confirmedChanges.forEach((c) => {
      if (c.transactionType) {
        counts[c.transactionType] = (counts[c.transactionType] || 0) + 1;
      }
    });
    return counts;
  }, [currentEdition]);

  const confirmedTeamCounts = useMemo(() => {
    if (!currentEdition) return {};
    const counts: Record<string, number> = {};
    currentEdition.confirmedChanges.forEach((c) => {
      if (c.team) {
        counts[c.team] = (counts[c.team] || 0) + 1;
      }
    });
    return counts;
  }, [currentEdition]);

  // Filtered confirmed changes
  const filteredConfirmed = useMemo(() => {
    if (!currentEdition) return [];
    return currentEdition.confirmedChanges.filter((item) => {
      const q = confirmedSearch.toLowerCase();
      const matchSearch =
        item.playerName.toLowerCase().includes(q) ||
        item.team.toLowerCase().includes(q) ||
        (item.contractTerms && item.contractTerms.toLowerCase().includes(q)) ||
        item.priorValue.toLowerCase().includes(q) ||
        item.newValue.toLowerCase().includes(q);
      const matchTeam = confirmedTeamFilter === 'all' || item.team === confirmedTeamFilter;
      const matchType = confirmedTypeFilter === 'all' || item.transactionType === confirmedTypeFilter;
      return matchSearch && matchTeam && matchType;
    });
  }, [currentEdition, confirmedSearch, confirmedTeamFilter, confirmedTypeFilter]);

  // Bounded pagination slicing for confirmed changes table (bounds render volume)
  const totalConfirmedPages = Math.max(1, Math.ceil(filteredConfirmed.length / CONFIRMED_PAGE_SIZE));
  const paginatedConfirmed = useMemo(() => {
    const start = (confirmedPage - 1) * CONFIRMED_PAGE_SIZE;
    return filteredConfirmed.slice(start, start + CONFIRMED_PAGE_SIZE);
  }, [filteredConfirmed, confirmedPage, CONFIRMED_PAGE_SIZE]);

  // Filtered reported claims
  const filteredReported = useMemo(() => {
    if (!currentEdition) return [];
    return currentEdition.reportedClaims.filter((claim) => {
      const q = reportedSearch.toLowerCase();
      const matchSearch =
        claim.team.toLowerCase().includes(q) || claim.claim.toLowerCase().includes(q);
      const matchCat = reportedCatFilter === 'all' || claim.sourceCategory === reportedCatFilter;
      return matchSearch && matchCat;
    });
  }, [currentEdition, reportedSearch, reportedCatFilter]);

  // Expired claims grouped by source category
  const groupedExpired = useMemo(() => {
    if (!currentEdition) return {};
    const groups: Record<string, typeof currentEdition.expiredClaims> = {};
    currentEdition.expiredClaims.forEach((item) => {
      if (expiredCatFilter !== 'all' && item.sourceCategory !== expiredCatFilter) return;
      const cat = item.sourceCategory || 'General Speculation';
      if (!groups[cat]) groups[cat] = [];
      groups[cat].push(item);
    });
    return groups;
  }, [currentEdition, expiredCatFilter]);

  if (!dataset || !currentEdition) {
    return (
      <div className="bg-surface-raised border border-slate-800 rounded-2xl p-8 text-center text-slate-400">
        <Sparkles className="w-10 h-10 text-sky-400 mx-auto mb-3 animate-pulse" />
        <h2 className="text-xl font-bold text-white mb-2">Off-Season Monitor Initializing</h2>
        <p className="text-sm max-w-md mx-auto">
          The 2026–2027 weekly state-diff engine is awaiting baseline initialization. Run the DAG pipeline to generate Week 1 intelligence.
        </p>
      </div>
    );
  }

  const isFrozen = currentEdition.isFrozenWeek || dataset.leagueOperatingStatus === 'TRANSACTION_FREEZE';
  const freezeDays = currentEdition.freezeDayCount ?? dataset.freezeDayCount ?? 0;
  const totalConfirmedCount = currentEdition.totalConfirmedCount ?? currentEdition.confirmedChanges.length;
  const isConfirmedBounded = Boolean(
    currentEdition.totalConfirmedCount &&
    currentEdition.totalConfirmedCount > currentEdition.confirmedChanges.length
  );

  return (
    <div className="space-y-6">
      {/* ------------------------------------------------------------- */}
      {/* HEADER BANNER & TIMELINE CONTROLS                             */}
      {/* ------------------------------------------------------------- */}
      <div className="relative pb-6 border-b border-slate-800">
        <div className="flex flex-col md:flex-row md:items-center justify-between gap-4">
          <div>
            <div className="flex items-center gap-2 mb-1.5 flex-wrap">
              <span className="text-xs font-bold uppercase tracking-wider px-2.5 py-0.5 rounded-full bg-sky-500/10 text-sky-400 border border-sky-500/20 font-mono flex items-center gap-1.5">
                <Sparkles className="w-3.5 h-3.5" />
                <span>2026–2027 Off-Season Dynamics Monitor</span>
              </span>
              <span className="text-xs text-slate-400 font-mono">
                Phase: <span className="text-slate-200 font-semibold">{dataset.activePhase}</span>
              </span>
            </div>

            <h1 className="text-3xl font-black tracking-tight text-white flex items-center gap-3">
              <span>
                <span className="text-sky-400">MLB</span> Off-Season Pulse — Week {currentEdition.weekNumber}
              </span>
            </h1>

            <p className="text-slate-400 text-sm mt-1 max-w-3xl">
              Deterministic weekly state diff tracking 40-man roster transactions, luxury tax payroll commitments,
              reported rumors with 28-day TTL decay, and 2027 Marcel baseline priors.
            </p>
          </div>

          {/* Quick Context Summary Chips */}
          <div className="flex items-center gap-2.5 text-xs font-mono flex-wrap">
            <div className="bg-surface-raised border border-slate-800 rounded-xl px-3 py-2 text-right">
              <span className="text-slate-500 block text-[10px] uppercase">Published</span>
              <span className="text-white font-bold">{currentEdition.publishDate}</span>
            </div>
            <div className="bg-surface-raised border border-slate-800 rounded-xl px-3 py-2 text-right">
              <span className="text-slate-500 block text-[10px] uppercase">Elapsed</span>
              <span className="text-sky-400 font-bold">{dataset.elapsedDaysSinceLastPublish}d Interval</span>
            </div>
            <div className="bg-surface-raised border border-slate-800 rounded-xl px-3 py-2 text-right">
              <span className="text-slate-500 block text-[10px] uppercase">CBT Payroll Leader</span>
              <span className="text-emerald-400 font-bold">{dataset.currentStateSummary.cbtPayrollLeader}</span>
            </div>
          </div>
        </div>

        {/* Operating Status & Quiet/Freeze Banners */}
        <div className="mt-4 flex items-center gap-3 flex-wrap">
          {isFrozen ? (
            <div className="flex items-center gap-2 px-3 py-1.5 rounded-lg bg-rose-950/60 border border-rose-800/60 text-rose-300 text-xs font-mono">
              <ShieldAlert className="w-4 h-4 text-rose-400 animate-pulse" />
              <span className="font-bold">TRANSACTION FREEZE ACTIVE</span>
              <span className="text-rose-200">· Day {freezeDays} of Major-League Lockout</span>
            </div>
          ) : currentEdition.isQuietWeek ? (
            <div className="flex items-center gap-2 px-3 py-1.5 rounded-lg bg-indigo-950/60 border border-indigo-800/60 text-indigo-300 text-xs font-mono">
              <Clock className="w-4 h-4 text-indigo-400" />
              <span className="font-bold">QUIET WEEK ASSERTED</span>
              <span className="text-indigo-200">· 0 confirmed 40-man state transitions (wire healthy)</span>
            </div>
          ) : (
            <div className="flex items-center gap-2 px-3 py-1.5 rounded-lg bg-emerald-950/60 border border-emerald-800/60 text-emerald-300 text-xs font-mono">
              <CheckCircle2 className="w-4 h-4 text-emerald-400" />
              <span className="font-bold">NORMAL LEAGUE MOVEMENT</span>
              <span className="text-emerald-200">
                · {totalConfirmedCount.toLocaleString()} confirmed transition{totalConfirmedCount === 1 ? '' : 's'} recorded
                {isConfirmedBounded && ` (${currentEdition.confirmedChanges.length} in view)`}
              </span>
            </div>
          )}
        </div>

        <div className="absolute bottom-0 left-0 right-0 h-[2px] bg-gradient-to-r from-sky-400 via-sky-500/40 to-transparent" />
      </div>

      {/* ------------------------------------------------------------- */}
      {/* TIMELINE EDITION SELECTOR                                     */}
      {/* ------------------------------------------------------------- */}
      <div className="bg-surface-raised border border-slate-800 rounded-xl p-4 space-y-3">
        <div className="flex items-center justify-between">
          <div className="flex items-center gap-2 text-xs font-mono font-bold uppercase tracking-wider text-slate-400">
            <History className="w-4 h-4 text-sky-400" />
            <span>Off-Season Edition Timeline</span>
          </div>
          {isLoadingArchive && (
            <span className="text-[11px] font-mono text-amber-400 animate-pulse">
              Fetching archived week...
            </span>
          )}
        </div>

        <div className="flex items-center gap-2 overflow-x-auto pb-1 pt-1 scrollbar-thin">
          {availableEditions.map((ed) => {
            const isSelected = ed.weekNumber === selectedWeek;
            return (
              <button
                key={ed.weekNumber}
                type="button"
                onClick={() => setSelectedWeek(ed.weekNumber)}
                className={`flex-shrink-0 px-3 py-2 rounded-lg text-xs font-mono transition-all flex flex-col items-start gap-1 border ${
                  isSelected
                    ? 'bg-sky-500/20 border-sky-400 text-white shadow-lg shadow-sky-500/10'
                    : 'bg-surface/80 border-slate-800 text-slate-400 hover:text-white hover:border-slate-700'
                }`}
              >
                <div className="flex items-center gap-1.5 w-full justify-between">
                  <span className="font-bold">Week {ed.weekNumber}</span>
                  {ed.isArchived && <Archive className="w-3 h-3 text-slate-500" />}
                </div>
                <span className="text-[10px] text-slate-500">{ed.publishDate}</span>
                <div className="flex items-center gap-1 mt-0.5">
                  {ed.isFrozenWeek ? (
                    <span className="text-[9px] px-1 py-0.2 rounded bg-rose-500/20 text-rose-300 border border-rose-500/30">
                      Freeze
                    </span>
                  ) : ed.isQuietWeek ? (
                    <span className="text-[9px] px-1 py-0.2 rounded bg-indigo-500/20 text-indigo-300 border border-indigo-500/30">
                      Quiet
                    </span>
                  ) : (
                    <span className="text-[9px] px-1 py-0.2 rounded bg-emerald-500/20 text-emerald-300 border border-emerald-500/30">
                      Active
                    </span>
                  )}
                </div>
              </button>
            );
          })}
        </div>
      </div>

      {/* State of Play Note */}
      <div className="bg-surface-raised border border-slate-800/80 rounded-xl p-4 flex items-start gap-3">
        <Info className="w-4 h-4 text-sky-400 flex-shrink-0 mt-0.5" />
        <div className="text-xs sm:text-sm text-slate-300 leading-relaxed font-sans">
          <strong className="text-white font-mono mr-1">State of Play:</strong>
          {currentEdition.stateOfPlay}
        </div>
      </div>

      {/* ------------------------------------------------------------- */}
      {/* TABS NAVIGATION                                               */}
      {/* ------------------------------------------------------------- */}
      <div className="flex items-center gap-2 border-b border-slate-800 pb-2 overflow-x-auto">
        <button
          type="button"
          onClick={() => setActiveTab('brief')}
          className={`px-3.5 py-2 rounded-lg text-xs font-semibold flex items-center gap-2 transition-all ${
            activeTab === 'brief'
              ? 'bg-sky-600 text-white shadow-md shadow-sky-600/20'
              : 'text-slate-400 hover:text-white hover:bg-slate-800/60'
          }`}
        >
          <FileText className="w-3.5 h-3.5" />
          <span>Executive Brief</span>
        </button>

        <button
          type="button"
          onClick={() => setActiveTab('confirmed')}
          className={`px-3.5 py-2 rounded-lg text-xs font-semibold flex items-center gap-2 transition-all ${
            activeTab === 'confirmed'
              ? 'bg-sky-600 text-white shadow-md shadow-sky-600/20'
              : 'text-slate-400 hover:text-white hover:bg-slate-800/60'
          }`}
        >
          <CheckCircle2 className="w-3.5 h-3.5" />
          <span>Confirmed Transactions</span>
          <span className="px-1.5 py-0.2 rounded bg-black/30 font-mono text-[10px]">
            {totalConfirmedCount.toLocaleString()}
          </span>
        </button>

        <button
          type="button"
          onClick={() => setActiveTab('reported')}
          className={`px-3.5 py-2 rounded-lg text-xs font-semibold flex items-center gap-2 transition-all ${
            activeTab === 'reported'
              ? 'bg-sky-600 text-white shadow-md shadow-sky-600/20'
              : 'text-slate-400 hover:text-white hover:bg-slate-800/60'
          }`}
        >
          <Clock className="w-3.5 h-3.5" />
          <span>Reported Radar</span>
          <span className="px-1.5 py-0.2 rounded bg-black/30 font-mono text-[10px]">
            {currentEdition.reportedClaims.length}
          </span>
        </button>

        <button
          type="button"
          onClick={() => setActiveTab('expired')}
          className={`px-3.5 py-2 rounded-lg text-xs font-semibold flex items-center gap-2 transition-all ${
            activeTab === 'expired'
              ? 'bg-sky-600 text-white shadow-md shadow-sky-600/20'
              : 'text-slate-400 hover:text-white hover:bg-slate-800/60'
          }`}
        >
          <Archive className="w-3.5 h-3.5" />
          <span>Expired Claims</span>
          <span className="px-1.5 py-0.2 rounded bg-black/30 font-mono text-[10px]">
            {currentEdition.expiredClaims.length}
          </span>
        </button>

        <button
          type="button"
          onClick={() => setActiveTab('cbt')}
          className={`px-3.5 py-2 rounded-lg text-xs font-semibold flex items-center gap-2 transition-all ${
            activeTab === 'cbt'
              ? 'bg-sky-600 text-white shadow-md shadow-sky-600/20'
              : 'text-slate-400 hover:text-white hover:bg-slate-800/60'
          }`}
        >
          <Coins className="w-3.5 h-3.5" />
          <span>CBT Payroll Matrix</span>
        </button>

        {isFrozen && (
          <button
            type="button"
            onClick={() => setActiveTab('labor')}
            className={`px-3.5 py-2 rounded-lg text-xs font-semibold flex items-center gap-2 transition-all ${
              activeTab === 'labor'
                ? 'bg-rose-600 text-white shadow-md shadow-rose-600/20'
                : 'text-rose-400 hover:text-rose-200 hover:bg-rose-950/40 border border-rose-900/40'
            }`}
          >
            <ShieldAlert className="w-3.5 h-3.5" />
            <span>Labor Negotiation Log</span>
            <span className="px-1.5 py-0.2 rounded bg-black/30 font-mono text-[10px]">
              {currentEdition.laborEvents?.length ?? 0}
            </span>
          </button>
        )}
      </div>

      {/* ------------------------------------------------------------- */}
      {/* TAB 1: EXECUTIVE BRIEF                                        */}
      {/* ------------------------------------------------------------- */}
      {activeTab === 'brief' && (
        <div className="space-y-6">
          <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
            {/* Model Prior Impact */}
            <div className="bg-surface-raised border border-slate-800 rounded-xl p-5 space-y-3">
              <div className="flex items-center gap-2 text-xs font-mono font-bold uppercase tracking-wider text-amber-400 border-b border-slate-800 pb-2">
                <Sparkles className="w-3.5 h-3.5" />
                <span>2027 Marcel / Pythagorean Prior Impact</span>
              </div>
              <p className="text-xs sm:text-sm text-slate-300 leading-relaxed">
                {currentEdition.modelPriorImpact?.summary || 'No change to 2027 baseline Marcel priors.'}
              </p>
              {currentEdition.modelPriorImpact?.adjustedTeams &&
                Object.keys(currentEdition.modelPriorImpact.adjustedTeams).length > 0 && (
                  <div className="pt-2 border-t border-slate-800 space-y-2">
                    {Object.entries(currentEdition.modelPriorImpact.adjustedTeams).map(([team, val]) => (
                      <div key={team} className="flex items-center justify-between text-xs font-mono">
                        <span className="font-bold text-white">{team}</span>
                        <span className={val.deltaWins >= 0 ? 'text-emerald-400' : 'text-rose-400'}>
                          {val.deltaWins >= 0 ? `+${val.deltaWins}` : val.deltaWins} Wins ({val.rationale})
                        </span>
                      </div>
                    ))}
                  </div>
                )}
            </div>

            {/* Upcoming Milestones */}
            <div className="bg-surface-raised border border-slate-800 rounded-xl p-5 space-y-3">
              <div className="flex items-center gap-2 text-xs font-mono font-bold uppercase tracking-wider text-sky-400 border-b border-slate-800 pb-2">
                <Calendar className="w-3.5 h-3.5" />
                <span>Next 30 Days (Milestones & Deadlines)</span>
              </div>
              <div className="space-y-2">
                {currentEdition.upcomingMilestones.length === 0 ? (
                  <p className="text-xs text-slate-500">No scheduled milestones in the immediate window.</p>
                ) : (
                  currentEdition.upcomingMilestones.map((m, idx) => (
                    <div key={idx} className="flex items-start justify-between gap-3 text-xs">
                      <div className="space-y-0.5">
                        <span className="font-semibold text-slate-200 block">{m.event}</span>
                        <span className="font-mono text-[10px] text-slate-500">{m.date ?? 'Unannounced'}</span>
                      </div>
                      <span
                        className={`text-[10px] font-mono px-2 py-0.5 rounded ${
                          m.status === 'Confirmed'
                            ? 'bg-emerald-500/10 text-emerald-400 border border-emerald-500/20'
                            : 'bg-amber-500/10 text-amber-400 border border-amber-500/20'
                        }`}
                      >
                        {m.status}
                      </span>
                    </div>
                  ))
                )}
              </div>
            </div>
          </div>

          {/* Winter Leagues & Rehab Notes */}
          <div className="bg-surface-raised border border-slate-800 rounded-xl p-5 space-y-3">
            <div className="flex items-center gap-2 text-xs font-mono font-bold uppercase tracking-wider text-emerald-400 border-b border-slate-800 pb-2">
              <Users className="w-3.5 h-3.5" />
              <span>Winter Leagues & Rehab Tracking (AFL / LIDOM / Post-Op)</span>
            </div>
            {currentEdition.winterLeagueNotes.length === 0 ? (
              <p className="text-xs text-slate-500">No winter league or rehab updates recorded this window.</p>
            ) : (
              <div className="grid grid-cols-1 sm:grid-cols-2 md:grid-cols-3 gap-3">
                {currentEdition.winterLeagueNotes.map((note, idx) => (
                  <div key={idx} className="bg-surface p-3 rounded-lg border border-slate-800 space-y-1">
                    <div className="flex items-center justify-between">
                      <span className="font-bold text-xs text-white">{note.playerName}</span>
                      <span className="text-[10px] font-mono px-1.5 py-0.2 rounded bg-slate-800 text-sky-400">
                        {note.mlbTeam} · {note.league}
                      </span>
                    </div>
                    <p className="text-xs text-slate-400 leading-relaxed">{note.notes}</p>
                  </div>
                ))}
              </div>
            )}
          </div>

          {/* Sources Visited */}
          <div className="bg-surface-raised border border-slate-800 rounded-xl p-4 text-xs font-mono text-slate-400 flex items-center justify-between flex-wrap gap-2">
            <span>Sources Verified: {currentEdition.sourcesVisited.join(' · ')}</span>
            <span className="text-slate-500">Confidence Tier 1 (Official / Filed)</span>
          </div>
        </div>
      )}

      {/* ------------------------------------------------------------- */}
      {/* TAB 2: CONFIRMED TRANSACTIONS LEDGER                          */}
      {/* ------------------------------------------------------------- */}
      {activeTab === 'confirmed' && (
        <div className="bg-surface-raised border border-slate-800 rounded-2xl p-5 sm:p-6 space-y-4">
          <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-3 border-b border-slate-800 pb-4">
            <div>
              <h2 className="text-lg font-bold text-white">Confirmed Transactions Ledger</h2>
              <p className="text-xs text-slate-400 mt-0.5">
                Mutated 40-man roster states, free agency contracts, options, and trades verified from official filings.
              </p>
            </div>

            {/* Filter controls */}
            <div className="flex items-center gap-2 flex-wrap">
              <div className="relative">
                <Search className="w-3.5 h-3.5 text-slate-500 absolute left-2.5 top-2.5" />
                <input
                  type="text"
                  placeholder="Filter player or terms..."
                  value={confirmedSearch}
                  onChange={(e) => setConfirmedSearch(e.target.value)}
                  className="bg-surface border border-slate-700 rounded-lg pl-8 pr-3 py-1.5 text-xs text-white placeholder-slate-500 focus:outline-none focus:border-sky-400 font-mono"
                />
              </div>

              <select
                value={confirmedTeamFilter}
                onChange={(e) => setConfirmedTeamFilter(e.target.value)}
                className="bg-surface border border-slate-700 rounded-lg px-2.5 py-1.5 text-xs text-slate-300 focus:outline-none focus:border-sky-400 font-mono"
              >
                <option value="all">All Clubs ({currentEdition.confirmedChanges.length})</option>
                {confirmedTeams.map((tm) => (
                  <option key={tm} value={tm}>
                    {tm} ({confirmedTeamCounts[tm] || 0})
                  </option>
                ))}
              </select>

              <select
                value={confirmedTypeFilter}
                onChange={(e) => setConfirmedTypeFilter(e.target.value)}
                className="bg-surface border border-slate-700 rounded-lg px-2.5 py-1.5 text-xs text-slate-300 focus:outline-none focus:border-sky-400 font-mono"
              >
                <option value="all">All Types</option>
                {confirmedTypes.map((t) => (
                  <option key={t} value={t}>
                    {t.replace(/_/g, ' ')} ({confirmedTypeCounts[t] || 0})
                  </option>
                ))}
              </select>
            </div>
          </div>

          {/* Non-silent Bounded Payload Notice */}
          {isConfirmedBounded && (
            <div className="flex items-center gap-2.5 px-3.5 py-2.5 rounded-xl bg-amber-500/10 border border-amber-500/25 text-amber-300 text-xs font-mono">
              <Info className="w-4 h-4 text-amber-400 flex-shrink-0" />
              <div>
                <strong className="font-semibold text-white">Bounded Artifact View:</strong> Displaying{' '}
                <span className="text-amber-200 font-bold">{currentEdition.confirmedChanges.length}</span> most recent inlined transitions of{' '}
                <span className="text-amber-200 font-bold">{totalConfirmedCount.toLocaleString()}</span> total verified wire events for initial load efficiency. Full historical ledger is archived.
              </div>
            </div>
          )}

          {filteredConfirmed.length === 0 ? (
            <div className="text-center py-10 text-slate-500 text-xs">
              No confirmed transactions match the active filter criteria.
            </div>
          ) : (
            <div className="space-y-3">
              <div className="overflow-x-auto">
                <table className="w-full text-left text-xs border-collapse">
                  <thead>
                    <tr className="border-b border-slate-800 text-[11px] font-mono text-slate-400 uppercase tracking-wider">
                      <th className="py-2.5 px-3">Date</th>
                      <th className="py-2.5 px-3">Club</th>
                      <th className="py-2.5 px-3">Player</th>
                      <th className="py-2.5 px-3">Tier</th>
                      <th className="py-2.5 px-3">Transaction</th>
                      <th className="py-2.5 px-3">Prior ($S_0$)</th>
                      <th className="py-2.5 px-3">New ($S_t$)</th>
                      <th className="py-2.5 px-3">Terms / AAV</th>
                      <th className="py-2.5 px-3 text-right">Source</th>
                    </tr>
                  </thead>
                  <tbody className="divide-y divide-slate-800/60 font-mono">
                    {paginatedConfirmed.map((tx, idx) => (
                      <tr key={idx} className="hover:bg-slate-800/30 transition-colors">
                        <td className="py-2 px-3 text-slate-400">{tx.date}</td>
                        <td className="py-2 px-3 font-bold text-white">{tx.team}</td>
                        <td className="py-2 px-3 text-slate-200 font-sans font-semibold">{tx.playerName}</td>
                        <td className="py-2 px-3 text-[10px]">
                          <span
                            className={`px-1.5 py-0.2 rounded ${
                              tx.rosterTier === 'MAJOR_40_MAN'
                                ? 'bg-sky-500/10 text-sky-400 border border-sky-500/20'
                                : 'bg-slate-800 text-slate-400'
                            }`}
                          >
                            {tx.rosterTier === 'MAJOR_40_MAN' ? '40-Man' : 'Minor'}
                          </span>
                        </td>
                        <td className="py-2 px-3 text-amber-300">{tx.transactionType.replace(/_/g, ' ')}</td>
                        <td className="py-2 px-3 text-slate-400">{tx.priorValue}</td>
                        <td className="py-2 px-3 text-emerald-400 font-semibold">{tx.newValue}</td>
                        <td className="py-2 px-3 text-slate-300 font-sans">{tx.contractTerms || '—'}</td>
                        <td className="py-2 px-3 text-right">
                          {tx.sourceUrl ? (
                            <a
                              href={tx.sourceUrl}
                              target="_blank"
                              rel="noopener noreferrer"
                              className="text-sky-400 hover:text-sky-300 inline-flex items-center gap-1"
                            >
                              <span>Wire</span>
                              <ExternalLink className="w-3 h-3" />
                            </a>
                          ) : (
                            <span className="text-slate-600">—</span>
                          )}
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>

              {/* Bounded Pagination Controls */}
              <div className="flex flex-col sm:flex-row items-center justify-between gap-3 pt-3 border-t border-slate-800 text-xs font-mono text-slate-400">
                <div>
                  Showing{' '}
                  <span className="text-white font-bold">
                    {(confirmedPage - 1) * CONFIRMED_PAGE_SIZE + 1}–{Math.min(confirmedPage * CONFIRMED_PAGE_SIZE, filteredConfirmed.length)}
                  </span>{' '}
                  of <span className="text-white font-bold">{filteredConfirmed.length}</span> matching
                  {filteredConfirmed.length !== currentEdition.confirmedChanges.length && (
                    <span> (filtered from {currentEdition.confirmedChanges.length} in view)</span>
                  )}
                  {isConfirmedBounded && (
                    <span className="text-amber-400/80"> · {totalConfirmedCount.toLocaleString()} total wire transactions</span>
                  )}
                </div>

                {totalConfirmedPages > 1 && (
                  <div className="flex items-center gap-1.5">
                    <button
                      type="button"
                      onClick={() => setConfirmedPage(1)}
                      disabled={confirmedPage === 1}
                      className="px-2 py-1 rounded bg-surface border border-slate-700 text-slate-300 hover:text-white disabled:opacity-30 disabled:cursor-not-allowed transition-all"
                    >
                      « First
                    </button>
                    <button
                      type="button"
                      onClick={() => setConfirmedPage((p) => Math.max(1, p - 1))}
                      disabled={confirmedPage === 1}
                      className="px-2.5 py-1 rounded bg-surface border border-slate-700 text-slate-300 hover:text-white disabled:opacity-30 disabled:cursor-not-allowed transition-all"
                    >
                      ‹ Prev
                    </button>
                    <span className="px-2.5 py-1 text-slate-300">
                      Page <strong className="text-white">{confirmedPage}</strong> of{' '}
                      <strong className="text-white">{totalConfirmedPages}</strong>
                    </span>
                    <button
                      type="button"
                      onClick={() => setConfirmedPage((p) => Math.min(totalConfirmedPages, p + 1))}
                      disabled={confirmedPage === totalConfirmedPages}
                      className="px-2.5 py-1 rounded bg-surface border border-slate-700 text-slate-300 hover:text-white disabled:opacity-30 disabled:cursor-not-allowed transition-all"
                    >
                      Next ›
                    </button>
                    <button
                      type="button"
                      onClick={() => setConfirmedPage(totalConfirmedPages)}
                      disabled={confirmedPage === totalConfirmedPages}
                      className="px-2 py-1 rounded bg-surface border border-slate-700 text-slate-300 hover:text-white disabled:opacity-30 disabled:cursor-not-allowed transition-all"
                    >
                      Last »
                    </button>
                  </div>
                )}
              </div>
            </div>
          )}
        </div>
      )}

      {/* ------------------------------------------------------------- */}
      {/* TAB 3: REPORTED & PENDING RADAR (28-DAY TTL)                  */}
      {/* ------------------------------------------------------------- */}
      {activeTab === 'reported' && (
        <div className="bg-surface-raised border border-slate-800 rounded-2xl p-5 sm:p-6 space-y-4">
          <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-3 border-b border-slate-800 pb-4">
            <div>
              <h2 className="text-lg font-bold text-white">Reported & Pending Radar</h2>
              <p className="text-xs text-slate-400 mt-0.5">
                Tier 2/3 beat reports and trade rumors decaying over a strict 28-day TTL queue before transitioning to the graveyard.
              </p>
            </div>

            <div className="flex items-center gap-2 flex-wrap">
              <div className="relative">
                <Search className="w-3.5 h-3.5 text-slate-500 absolute left-2.5 top-2.5" />
                <input
                  type="text"
                  placeholder="Filter rumor..."
                  value={reportedSearch}
                  onChange={(e) => setReportedSearch(e.target.value)}
                  className="bg-surface border border-slate-700 rounded-lg pl-8 pr-3 py-1.5 text-xs text-white placeholder-slate-500 focus:outline-none focus:border-sky-400 font-mono"
                />
              </div>

              <select
                value={reportedCatFilter}
                onChange={(e) => setReportedCatFilter(e.target.value)}
                className="bg-surface border border-slate-700 rounded-lg px-2.5 py-1.5 text-xs text-slate-300 focus:outline-none focus:border-sky-400 font-mono"
              >
                <option value="all">All Sources</option>
                <option value="National Beat">National Beat</option>
                <option value="Team Beat Wire">Team Beat Wire</option>
                <option value="Trade Speculation">Trade Speculation</option>
              </select>
            </div>
          </div>

          {filteredReported.length === 0 ? (
            <div className="text-center py-10 text-slate-500 text-xs">
              Radar clean. No unconfirmed claims pending verification.
            </div>
          ) : (
            <div className="space-y-3">
              {filteredReported.map((item) => {
                const ttlPct = Math.min(100, Math.round((item.daysPending / 28) * 100));
                return (
                  <div
                    key={item.id}
                    className="bg-surface border border-slate-800/90 rounded-xl p-4 flex flex-col sm:flex-row sm:items-center justify-between gap-3"
                  >
                    <div className="space-y-1">
                      <div className="flex items-center gap-2">
                        <span className="font-bold text-xs font-mono text-sky-400 px-2 py-0.5 rounded bg-sky-950/60 border border-sky-800/60">
                          {item.team}
                        </span>
                        <span className="text-[11px] font-mono text-slate-400">
                          {item.sourceCategory} · First Reported {item.firstReportedDate}
                        </span>
                      </div>
                      <p className="text-xs sm:text-sm text-slate-200 font-medium">{item.claim}</p>
                    </div>

                    <div className="sm:text-right min-w-[140px] space-y-1">
                      <div className="flex items-center justify-between sm:justify-end gap-2 text-[11px] font-mono">
                        <span className="text-slate-400">TTL Age:</span>
                        <span className="text-amber-400 font-bold">Day {item.daysPending} / 28</span>
                      </div>
                      <div className="w-full bg-slate-800 rounded-full h-1.5 overflow-hidden">
                        <div
                          className={`h-full ${ttlPct > 75 ? 'bg-rose-500' : 'bg-amber-400'}`}
                          style={{ width: `${ttlPct}%` }}
                        />
                      </div>
                    </div>
                  </div>
                );
              })}
            </div>
          )}
        </div>
      )}

      {/* ------------------------------------------------------------- */}
      {/* TAB 4: EXPIRED CLAIMS GRAVEYARD                               */}
      {/* ------------------------------------------------------------- */}
      {activeTab === 'expired' && (
        <div className="bg-surface-raised border border-slate-800 rounded-2xl p-5 sm:p-6 space-y-4">
          <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-3 border-b border-slate-800 pb-4">
            <div>
              <h2 className="text-lg font-bold text-white">Expired Claims Graveyard</h2>
              <p className="text-xs text-slate-400 mt-0.5">
                Claims aged past the 28-day window without official wire confirmation, archived by outlet category.
              </p>
            </div>

            <select
              value={expiredCatFilter}
              onChange={(e) => setExpiredCatFilter(e.target.value)}
              className="bg-surface border border-slate-700 rounded-lg px-2.5 py-1.5 text-xs text-slate-300 focus:outline-none focus:border-sky-400 font-mono"
            >
              <option value="all">All Categories</option>
              {Object.keys(groupedExpired).map((cat) => (
                <option key={cat} value={cat}>
                  {cat}
                </option>
              ))}
            </select>
          </div>

          {Object.keys(groupedExpired).length === 0 ? (
            <div className="text-center py-10 text-slate-500 text-xs">
              Graveyard is clean. No claims have aged out past the 28-day window yet.
            </div>
          ) : (
            <div className="space-y-4">
              {Object.entries(groupedExpired).map(([category, items]) => (
                <div key={category} className="bg-surface border border-slate-800/80 rounded-xl p-4 space-y-2">
                  <div className="flex items-center justify-between border-b border-slate-800 pb-2">
                    <span className="text-xs font-bold text-slate-200 uppercase tracking-wider font-mono">
                      {category}
                    </span>
                    <span className="text-[11px] font-mono text-slate-500">
                      {items.length} claim{items.length === 1 ? '' : 's'} expired
                    </span>
                  </div>
                  <div className="divide-y divide-slate-800/60">
                    {items.map((item, idx) => (
                      <div key={idx} className="py-2.5 flex flex-col sm:flex-row sm:items-center justify-between gap-2 text-xs">
                        <div>
                          <span className="font-bold text-sky-400 font-mono mr-2">[{item.team}]</span>
                          <span className="text-slate-300 font-medium">{item.claim}</span>
                        </div>
                        <div className="flex items-center gap-2 text-[11px] font-mono text-slate-500 flex-shrink-0">
                          <span>Reported: {item.firstReportedDate}</span>
                          <span>→</span>
                          <span className="text-rose-400">Expired: {item.expiredDate}</span>
                        </div>
                      </div>
                    ))}
                  </div>
                </div>
              ))}
            </div>
          )}
        </div>
      )}

      {/* ------------------------------------------------------------- */}
      {/* TAB 5: CBT PAYROLL MATRIX                                     */}
      {/* ------------------------------------------------------------- */}
      {activeTab === 'cbt' && (
        <div className="bg-surface-raised border border-slate-800 rounded-2xl p-6 sm:p-8 space-y-6">
          <div className="flex flex-col md:flex-row md:items-center justify-between gap-4 border-b border-slate-800 pb-5">
            <div>
              <span className="px-2.5 py-0.5 rounded-full text-[11px] font-bold uppercase tracking-wider bg-amber-500/20 text-amber-300 border border-amber-500/30 font-mono">
                2026–2027 Luxury Tax Matrix
              </span>
              <h2 className="text-2xl font-bold text-white mt-1">CBT Payroll &amp; Surcharge Thresholds</h2>
              <p className="text-xs sm:text-sm text-slate-400 max-w-2xl mt-1">
                40-man roster payroll commitments tracked against luxury tax surcharge thresholds ($244M base in 2026; 2027 base threshold unpopulated pending CBA).
              </p>
            </div>
            <Link
              href="/cap-sheet"
              className="inline-flex items-center gap-2 px-4 py-2.5 rounded-xl bg-sky-600 hover:bg-sky-500 text-white font-semibold text-xs transition-colors shadow-lg shadow-sky-600/30 self-start md:self-center font-mono"
            >
              <span>Explore Interactive CBT Sheet</span>
              <ArrowRight className="w-4 h-4" />
            </Link>
          </div>

          <div className="grid grid-cols-1 sm:grid-cols-3 gap-4">
            <div className="bg-surface p-4 rounded-xl border border-slate-800 space-y-1">
              <span className="text-xs text-slate-400">2026–27 Qualifying Offer</span>
              <div className="text-xl font-bold text-white font-mono">$23.15M</div>
              <div className="text-[11px] text-slate-500">Official top-125 salary average (confirmed)</div>
            </div>
            <div className="bg-surface p-4 rounded-xl border border-slate-800 space-y-1">
              <span className="text-xs text-slate-400">2027 CBT Base Threshold</span>
              <div className="text-xl font-bold text-amber-300 font-mono">Pending Ratification</div>
              <div className="text-[11px] text-slate-500">Unpopulated in $S_0$ baseline pending 2027 CBA</div>
            </div>
            <div className="bg-surface p-4 rounded-xl border border-slate-800 space-y-1">
              <span className="text-xs text-slate-400">Active CBT Payroll Leader</span>
              <div className="text-xl font-bold text-emerald-400 font-mono">
                {dataset.currentStateSummary.cbtPayrollLeader}
              </div>
              <div className="text-[11px] text-slate-500">Top Committed Payroll Post-World Series</div>
            </div>
          </div>
        </div>
      )}

      {/* ------------------------------------------------------------- */}
      {/* TAB 6: LABOR NEGOTIATION LOG (WHEN FROZEN)                    */}
      {/* ------------------------------------------------------------- */}
      {activeTab === 'labor' && isFrozen && (
        <div className="bg-surface-raised border border-rose-900/40 rounded-2xl p-5 sm:p-6 space-y-4">
          <div className="border-b border-rose-900/30 pb-4">
            <div className="flex items-center gap-2 text-rose-400 text-xs font-mono font-bold uppercase tracking-wider mb-1">
              <ShieldAlert className="w-4 h-4" />
              <span>Block 8 · Collective Bargaining Tracking</span>
            </div>
            <h2 className="text-lg font-bold text-white">Labor Negotiation Sessions &amp; Proposals</h2>
            <p className="text-xs text-slate-400 mt-0.5">
              Lockout day counter and verified bargaining sessions between MLB owners and MLBPA.
            </p>
          </div>

          {!currentEdition.laborEvents || currentEdition.laborEvents.length === 0 ? (
            <div className="text-center py-10 text-slate-500 text-xs">
              No bargaining sessions recorded for this window.
            </div>
          ) : (
            <div className="divide-y divide-slate-800/60 font-mono text-xs">
              {currentEdition.laborEvents.map((evt, idx) => (
                <div key={idx} className="py-3 flex flex-col sm:flex-row sm:items-center justify-between gap-2">
                  <div className="space-y-0.5">
                    <div className="flex items-center gap-2">
                      <span className="font-bold text-white">{evt.date}</span>
                      <span className="text-slate-400">· {evt.event}</span>
                    </div>
                    <div className="text-[11px] text-slate-500">
                      Parties: {evt.parties} | Category: {evt.sourceCategory}
                    </div>
                  </div>
                  <div className="flex items-center gap-3">
                    <span className="px-2 py-0.5 rounded bg-rose-500/10 text-rose-300 border border-rose-500/20 text-[11px]">
                      {evt.outcome}
                    </span>
                    {evt.sourceUrl && (
                      <a
                        href={evt.sourceUrl}
                        target="_blank"
                        rel="noopener noreferrer"
                        className="text-sky-400 hover:text-sky-300"
                      >
                        <ExternalLink className="w-3.5 h-3.5" />
                      </a>
                    )}
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
