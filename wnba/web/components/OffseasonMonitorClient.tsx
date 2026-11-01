'use client';

import React, { useState, useMemo } from 'react';
import Link from 'next/link';
import ReactMarkdown from 'react-markdown';
import remarkGfm from 'remark-gfm';
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
  Globe,
  Radio,
  History,
} from 'lucide-react';
import {
  OffseasonMonitorDataset,
  OffseasonEdition,
} from '@/lib/offseasonTypes';

interface Props {
  initialDataset: OffseasonMonitorDataset | null;
}

export const OffseasonMonitorClient: React.FC<Props> = ({ initialDataset }) => {
  const editions = useMemo(() => initialDataset?.editions || [], [initialDataset]);
  const latestEdition = editions.length > 0 ? editions[editions.length - 1] : null;

  const [selectedWeek, setSelectedWeek] = useState<number>(
    initialDataset?.currentWeekNumber || (latestEdition ? latestEdition.weekNumber : 1)
  );

  const [activeTab, setActiveTab] = useState<
    'memo' | 'confirmed' | 'reported' | 'expired' | 'cap'
  >('memo');

  // Confirmed Changes filter state
  const [confirmedSearch, setConfirmedSearch] = useState('');
  const [confirmedFieldFilter, setConfirmedFieldFilter] = useState('all');

  // Reported Claims search filter
  const [reportedSearch, setReportedSearch] = useState('');
  const [reportedCatFilter, setReportedCatFilter] = useState('all');

  // Expired Claims filter
  const [expiredCatFilter, setExpiredCatFilter] = useState('all');

  const currentEdition: OffseasonEdition | null = useMemo(() => {
    return editions.find((ed) => ed.weekNumber === selectedWeek) || latestEdition;
  }, [editions, selectedWeek, latestEdition]);

  // Unique fields for confirmed filter
  const confirmedFields = useMemo(() => {
    if (!currentEdition) return [];
    const fields = new Set<string>();
    currentEdition.confirmedChanges.forEach((c) => {
      if (c.field) fields.add(c.field);
    });
    return Array.from(fields);
  }, [currentEdition]);

  // Filtered confirmed changes
  const filteredConfirmed = useMemo(() => {
    if (!currentEdition) return [];
    return currentEdition.confirmedChanges.filter((item) => {
      const matchSearch =
        item.entityName.toLowerCase().includes(confirmedSearch.toLowerCase()) ||
        item.newValue.toLowerCase().includes(confirmedSearch.toLowerCase()) ||
        item.priorValue.toLowerCase().includes(confirmedSearch.toLowerCase()) ||
        item.field.toLowerCase().includes(confirmedSearch.toLowerCase());
      const matchField =
        confirmedFieldFilter === 'all' || item.field === confirmedFieldFilter;
      return matchSearch && matchField;
    });
  }, [currentEdition, confirmedSearch, confirmedFieldFilter]);

  // Filtered reported claims
  const filteredReported = useMemo(() => {
    if (!currentEdition) return [];
    return currentEdition.reportedClaims.filter((claim) => {
      const matchSearch =
        claim.entityName.toLowerCase().includes(reportedSearch.toLowerCase()) ||
        claim.claim.toLowerCase().includes(reportedSearch.toLowerCase());
      const matchCat =
        reportedCatFilter === 'all' || claim.sourceCategory === reportedCatFilter;
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

  if (!initialDataset || !currentEdition) {
    return (
      <div className="bg-surface-raised border border-slate-800 rounded-2xl p-8 text-center text-slate-400">
        <Sparkles className="w-10 h-10 text-violet-400 mx-auto mb-3 animate-pulse" />
        <h2 className="text-xl font-bold text-white mb-2">Off-Season Monitor Initializing</h2>
        <p className="text-sm max-w-md mx-auto">
          The 2026-2027 weekly state-diff engine is awaiting baseline initialization. Run the DAG pipeline to generate Week 1 intelligence.
        </p>
      </div>
    );
  }

  return (
    <div className="space-y-6">
      {/* ------------------------------------------------------------- */}
      {/* 1. TOP HEADER & EDITION SELECTOR                             */}
      {/* ------------------------------------------------------------- */}
      <div className="bg-surface-raised border border-slate-800/80 rounded-2xl p-5 sm:p-6 shadow-xl relative overflow-hidden">
        <div className="absolute top-0 left-0 right-0 h-1 bg-gradient-to-r from-violet-500 via-indigo-500 to-purple-500" />
        <div className="flex flex-col lg:flex-row lg:items-center justify-between gap-4">
          <div className="space-y-1">
            <div className="flex items-center gap-2">
              <span className="px-2.5 py-0.5 rounded-full text-[11px] font-bold uppercase tracking-wider bg-violet-500/20 text-violet-400 border border-violet-500/30">
                Weekly Pulse
              </span>
              <span className="text-xs text-slate-400 font-mono">
                Phase: <strong className="text-slate-200">{initialDataset.activePhase}</strong>
              </span>
              <span className="text-slate-600">â€¢</span>
              <span className="text-xs text-slate-400 font-mono">
                Baseline: {initialDataset.baselineAsOfDate}
              </span>
            </div>
            <h1 className="text-2xl sm:text-3xl font-extrabold text-white tracking-tight flex items-center gap-2.5">
              <span>2026-2027 Off-Season Dynamics Monitor</span>
              <Radio className="w-5 h-5 text-violet-400 animate-pulse" />
            </h1>
            <p className="text-sm text-slate-400 max-w-2xl">
              Deterministic state-diff intelligence engine tracking official roster mutations, reported beat linkage, CBA hard cap pressure, and baseline Bayesian priors.
            </p>
          </div>

          {/* Timeline Edition Selector */}
          <div className="flex items-center gap-2 self-start lg:self-center bg-surface border border-slate-700/60 rounded-xl p-1.5 shadow-inner">
            <History className="w-4 h-4 text-violet-400 ml-2 mr-1 flex-shrink-0" />
            <span className="text-xs font-semibold text-slate-400 mr-2">Edition:</span>
            <div className="flex items-center gap-1 overflow-x-auto max-w-xs sm:max-w-md">
              {editions.map((ed) => {
                const isSelected = ed.weekNumber === selectedWeek;
                return (
                  <button
                    key={ed.weekNumber}
                    onClick={() => setSelectedWeek(ed.weekNumber)}
                    className={`px-3 py-1.5 rounded-lg text-xs font-bold transition-all whitespace-nowrap ${
                      isSelected
                        ? 'bg-violet-600 text-white shadow-md shadow-violet-600/30'
                        : 'text-slate-400 hover:text-white hover:bg-slate-800'
                    }`}
                  >
                    Week {ed.weekNumber}
                    {ed.isQuietWeek && (
                      <span className="ml-1 text-[10px] text-slate-400 opacity-70">
                        (Quiet)
                      </span>
                    )}
                  </button>
                );
              })}
            </div>
          </div>
        </div>

        {/* ------------------------------------------------------------- */}
        {/* State of Play Banner                                          */}
        {/* ------------------------------------------------------------- */}
        <div className="mt-5 pt-4 border-t border-slate-800/80 flex flex-col sm:flex-row sm:items-center justify-between gap-3">
          <div className="flex items-center gap-3">
            {currentEdition.isQuietWeek ? (
              <span className="px-3 py-1 rounded-lg text-xs font-bold bg-amber-500/10 text-amber-300 border border-amber-500/30 flex items-center gap-1.5">
                <Clock className="w-3.5 h-3.5 text-amber-400" />
                Quiet Week
              </span>
            ) : (
              <span className="px-3 py-1 rounded-lg text-xs font-bold bg-emerald-500/10 text-emerald-300 border border-emerald-500/30 flex items-center gap-1.5">
                <CheckCircle2 className="w-3.5 h-3.5 text-emerald-400" />
                {currentEdition.confirmedChanges.length} Confirmed Mutation{currentEdition.confirmedChanges.length === 1 ? '' : 's'}
              </span>
            )}
            <p className="text-xs sm:text-sm text-slate-300 font-medium">
              {currentEdition.stateOfPlay}
            </p>
          </div>
          <div className="text-xs text-slate-500 font-mono self-end sm:self-center">
            Published: {currentEdition.publishDate}
          </div>
        </div>
      </div>

      {/* ------------------------------------------------------------- */}
      {/* 2. STATS OVERVIEW CARDS                                       */}
      {/* ------------------------------------------------------------- */}
      <div className="grid grid-cols-2 lg:grid-cols-4 gap-3 sm:gap-4">
        <div className="bg-surface-raised border border-slate-800/80 rounded-xl p-4">
          <div className="flex items-center justify-between text-slate-400 text-xs mb-1">
            <span>Confirmed Transitions</span>
            <CheckCircle2 className="w-4 h-4 text-emerald-400" />
          </div>
          <div className="text-2xl font-extrabold text-white">
            {currentEdition.confirmedChanges.length}
          </div>
          <div className="text-[11px] text-slate-500 mt-1">Tier 1 baseline mutations</div>
        </div>

        <div className="bg-surface-raised border border-slate-800/80 rounded-xl p-4">
          <div className="flex items-center justify-between text-slate-400 text-xs mb-1">
            <span>Reported Radar</span>
            <Radio className="w-4 h-4 text-violet-400" />
          </div>
          <div className="text-2xl font-extrabold text-white">
            {currentEdition.reportedClaims.length}
          </div>
          <div className="text-[11px] text-slate-500 mt-1">Active rumors (28-day TTL)</div>
        </div>

        <div className="bg-surface-raised border border-slate-800/80 rounded-xl p-4">
          <div className="flex items-center justify-between text-slate-400 text-xs mb-1">
            <span>Expired Graveyard</span>
            <Archive className="w-4 h-4 text-slate-400" />
          </div>
          <div className="text-2xl font-extrabold text-white">
            {currentEdition.expiredClaims.length}
          </div>
          <div className="text-[11px] text-slate-500 mt-1">Aged out &gt; 28 days unverified</div>
        </div>

        <div className="bg-surface-raised border border-slate-800/80 rounded-xl p-4">
          <div className="flex items-center justify-between text-slate-400 text-xs mb-1">
            <span>CBA Cap Climate</span>
            <Coins className="w-4 h-4 text-amber-400" />
          </div>
          <div className="text-xs font-bold text-amber-300 truncate" title={initialDataset.currentStateSummary.cbaLaborStatus}>
            $1.520M Hard Cap
          </div>
          <div className="text-[11px] text-slate-500 mt-1">11-vs-12 player roster crunch</div>
        </div>
      </div>

      {/* ------------------------------------------------------------- */}
      {/* 3. FIVE TABBED VIEWS                                          */}
      {/* ------------------------------------------------------------- */}
      <div className="flex items-center gap-1 sm:gap-2 border-b border-slate-800 overflow-x-auto pb-px">
        <button
          onClick={() => setActiveTab('memo')}
          className={`flex items-center gap-2 px-4 py-2.5 rounded-t-xl text-xs sm:text-sm font-semibold transition-colors border-b-2 whitespace-nowrap ${
            activeTab === 'memo'
              ? 'border-violet-500 text-white bg-surface-raised'
              : 'border-transparent text-slate-400 hover:text-white hover:bg-slate-800/40'
          }`}
        >
          <FileText className="w-4 h-4 text-violet-400" />
          <span>Executive Brief</span>
        </button>

        <button
          onClick={() => setActiveTab('confirmed')}
          className={`flex items-center gap-2 px-4 py-2.5 rounded-t-xl text-xs sm:text-sm font-semibold transition-colors border-b-2 whitespace-nowrap ${
            activeTab === 'confirmed'
              ? 'border-violet-500 text-white bg-surface-raised'
              : 'border-transparent text-slate-400 hover:text-white hover:bg-slate-800/40'
          }`}
        >
          <CheckCircle2 className="w-4 h-4 text-emerald-400" />
          <span>Confirmed Transactions</span>
          <span className="px-1.5 py-0.5 rounded-full text-[10px] bg-slate-800 text-slate-300 font-mono">
            {currentEdition.confirmedChanges.length}
          </span>
        </button>

        <button
          onClick={() => setActiveTab('reported')}
          className={`flex items-center gap-2 px-4 py-2.5 rounded-t-xl text-xs sm:text-sm font-semibold transition-colors border-b-2 whitespace-nowrap ${
            activeTab === 'reported'
              ? 'border-violet-500 text-white bg-surface-raised'
              : 'border-transparent text-slate-400 hover:text-white hover:bg-slate-800/40'
          }`}
        >
          <Radio className="w-4 h-4 text-violet-400" />
          <span>Reported & Pending Radar</span>
          <span className="px-1.5 py-0.5 rounded-full text-[10px] bg-slate-800 text-slate-300 font-mono">
            {currentEdition.reportedClaims.length}
          </span>
        </button>

        <button
          onClick={() => setActiveTab('expired')}
          className={`flex items-center gap-2 px-4 py-2.5 rounded-t-xl text-xs sm:text-sm font-semibold transition-colors border-b-2 whitespace-nowrap ${
            activeTab === 'expired'
              ? 'border-violet-500 text-white bg-surface-raised'
              : 'border-transparent text-slate-400 hover:text-white hover:bg-slate-800/40'
          }`}
        >
          <Archive className="w-4 h-4 text-slate-400" />
          <span>Expired Claims Graveyard</span>
          <span className="px-1.5 py-0.5 rounded-full text-[10px] bg-slate-800 text-slate-300 font-mono">
            {currentEdition.expiredClaims.length}
          </span>
        </button>

        <button
          onClick={() => setActiveTab('cap')}
          className={`flex items-center gap-2 px-4 py-2.5 rounded-t-xl text-xs sm:text-sm font-semibold transition-colors border-b-2 whitespace-nowrap ${
            activeTab === 'cap'
              ? 'border-violet-500 text-white bg-surface-raised'
              : 'border-transparent text-slate-400 hover:text-white hover:bg-slate-800/40'
          }`}
        >
          <Coins className="w-4 h-4 text-amber-400" />
          <span>CBA Cap Matrix</span>
        </button>
      </div>

      {/* ------------------------------------------------------------- */}
      {/* TAB 1: EXECUTIVE BRIEF (7-BLOCK MEMO)                         */}
      {/* ------------------------------------------------------------- */}
      {activeTab === 'memo' && (
        <div className="space-y-6">
          <div className="bg-surface-raised border border-slate-800/80 rounded-2xl p-6 sm:p-8 shadow-xl">
            <div className="prose prose-invert max-w-none prose-headings:text-white prose-a:text-violet-400 hover:prose-a:underline prose-table:border-collapse prose-th:border prose-th:border-slate-800 prose-th:bg-surface prose-th:p-2 prose-td:border prose-td:border-slate-800 prose-td:p-2">
              <ReactMarkdown remarkPlugins={[remarkGfm]}>
                {currentEdition.memoMarkdown}
              </ReactMarkdown>
            </div>
          </div>

          {/* Quick Cards for Milestones and Model Prior Impact */}
          <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
            {/* Upcoming Milestones */}
            <div className="bg-surface-raised border border-slate-800/80 rounded-xl p-5">
              <h3 className="text-base font-bold text-white flex items-center gap-2 mb-3">
                <Calendar className="w-4 h-4 text-violet-400" />
                <span>Next 30 Days Milestones</span>
              </h3>
              {currentEdition.upcomingMilestones.length === 0 ? (
                <p className="text-xs text-slate-500">No scheduled calendar events in next 30 days.</p>
              ) : (
                <div className="space-y-2">
                  {currentEdition.upcomingMilestones.map((m, idx) => (
                    <div
                      key={idx}
                      className="p-3 rounded-lg bg-surface border border-slate-800/60 flex items-start justify-between gap-3 text-xs"
                    >
                      <div>
                        <span className="font-mono text-violet-400 font-semibold block">{m.date || 'TBD'}</span>
                        <span className="text-slate-200 mt-0.5 block">{m.event}</span>
                      </div>
                      <span className={`px-2 py-0.5 rounded text-[10px] font-semibold flex-shrink-0 ${
                        m.status === 'Confirmed'
                          ? 'bg-emerald-500/20 text-emerald-300 border border-emerald-500/30'
                          : 'bg-slate-700/50 text-slate-300 border border-slate-600'
                      }`}>
                        {m.status}
                      </span>
                    </div>
                  ))}
                </div>
              )}
            </div>

            {/* Winter League & Overseas */}
            <div className="bg-surface-raised border border-slate-800/80 rounded-xl p-5">
              <h3 className="text-base font-bold text-white flex items-center gap-2 mb-3">
                <Globe className="w-4 h-4 text-sky-400" />
                <span>Winter League & Alternative Play</span>
              </h3>
              {currentEdition.winterLeagueNotes.length === 0 ? (
                <p className="text-xs text-slate-500">No active winter league notes this week.</p>
              ) : (
                <div className="space-y-2">
                  {currentEdition.winterLeagueNotes.map((note, idx) => (
                    <div
                      key={idx}
                      className="p-3 rounded-lg bg-surface border border-slate-800/60 flex items-start justify-between gap-3 text-xs"
                    >
                      <div>
                        <span className="font-bold text-slate-100">{note.playerName}</span>
                        {note.wnbaTeam && <span className="text-slate-400 ml-1">({note.wnbaTeam})</span>}
                        <div className="text-slate-400 text-[11px] mt-0.5">{note.healthStatus}</div>
                      </div>
                      <span className="px-2 py-0.5 rounded text-[10px] font-semibold bg-sky-500/20 text-sky-300 border border-sky-500/30 flex-shrink-0">
                        {note.league}
                      </span>
                    </div>
                  ))}
                </div>
              )}
            </div>
          </div>
        </div>
      )}

      {/* ------------------------------------------------------------- */}
      {/* TAB 2: CONFIRMED TRANSACTIONS LEDGER                         */}
      {/* ------------------------------------------------------------- */}
      {activeTab === 'confirmed' && (
        <div className="space-y-4">
          {/* Filters */}
          <div className="flex flex-col sm:flex-row gap-3 items-stretch sm:items-center justify-between bg-surface-raised p-4 rounded-xl border border-slate-800/80">
            <div className="relative flex-1">
              <Search className="w-4 h-4 text-slate-400 absolute left-3 top-1/2 -translate-y-1/2" />
              <input
                type="text"
                value={confirmedSearch}
                onChange={(e) => setConfirmedSearch(e.target.value)}
                placeholder="Search transactions by player, team, value..."
                className="w-full bg-surface border border-slate-700/60 rounded-lg pl-9 pr-3 py-1.5 text-xs text-white placeholder-slate-500 focus:outline-none focus:border-violet-500"
              />
            </div>
            <div className="flex items-center gap-2">
              <span className="text-xs text-slate-400 flex-shrink-0">Field:</span>
              <select
                value={confirmedFieldFilter}
                onChange={(e) => setConfirmedFieldFilter(e.target.value)}
                className="bg-surface border border-slate-700/60 rounded-lg px-2.5 py-1.5 text-xs text-slate-200 focus:outline-none focus:border-violet-500"
              >
                <option value="all">All Fields</option>
                {confirmedFields.map((f) => (
                  <option key={f} value={f}>{f}</option>
                ))}
              </select>
            </div>
          </div>

          {/* Table */}
          <div className="bg-surface-raised border border-slate-800/80 rounded-xl overflow-hidden shadow-lg">
            <div className="overflow-x-auto">
              <table className="w-full text-left text-xs">
                <thead>
                  <tr className="bg-surface border-b border-slate-800 text-slate-400 font-semibold uppercase tracking-wider text-[10px]">
                    <th className="py-3 px-4">Date</th>
                    <th className="py-3 px-4">Entity</th>
                    <th className="py-3 px-4">Field</th>
                    <th className="py-3 px-4">Prior State (S_last)</th>
                    <th className="py-3 px-4">New State (S_t)</th>
                    <th className="py-3 px-4">Source</th>
                  </tr>
                </thead>
                <tbody className="divide-y divide-slate-800/60">
                  {filteredConfirmed.length === 0 ? (
                    <tr>
                      <td colSpan={6} className="py-8 text-center text-slate-500">
                        No confirmed transactions match the current filter.
                      </td>
                    </tr>
                  ) : (
                    filteredConfirmed.map((item, idx) => (
                      <tr key={idx} className="hover:bg-slate-800/30 transition-colors">
                        <td className="py-3 px-4 font-mono text-slate-400 whitespace-nowrap">
                          {item.date || 'â€”'}
                        </td>
                        <td className="py-3 px-4 font-bold text-white whitespace-nowrap">
                          {item.entityName || item.entityId}
                        </td>
                        <td className="py-3 px-4 text-violet-400 font-mono">
                          {item.field}
                        </td>
                        <td className="py-3 px-4 text-slate-400">
                          <span className="px-2 py-0.5 rounded bg-slate-800 font-mono">
                            {item.priorValue}
                          </span>
                        </td>
                        <td className="py-3 px-4 text-emerald-400 font-semibold">
                          <span className="px-2 py-0.5 rounded bg-emerald-500/10 border border-emerald-500/20 font-mono">
                            {item.newValue}
                          </span>
                        </td>
                        <td className="py-3 px-4 text-slate-400 whitespace-nowrap">
                          {item.sourceUrl ? (
                            <a
                              href={item.sourceUrl}
                              target="_blank"
                              rel="noreferrer"
                              className="text-violet-400 hover:text-violet-300 inline-flex items-center gap-1"
                            >
                              <span>Wire</span>
                              <ExternalLink className="w-3 h-3" />
                            </a>
                          ) : (
                            'Official Wire'
                          )}
                        </td>
                      </tr>
                    ))
                  )}
                </tbody>
              </table>
            </div>
          </div>
        </div>
      )}

      {/* ------------------------------------------------------------- */}
      {/* TAB 3: REPORTED & PENDING RADAR (28-DAY TTL)                  */}
      {/* ------------------------------------------------------------- */}
      {activeTab === 'reported' && (
        <div className="space-y-4">
          <div className="flex flex-col sm:flex-row gap-3 items-stretch sm:items-center justify-between bg-surface-raised p-4 rounded-xl border border-slate-800/80">
            <div className="relative flex-1">
              <Search className="w-4 h-4 text-slate-400 absolute left-3 top-1/2 -translate-y-1/2" />
              <input
                type="text"
                value={reportedSearch}
                onChange={(e) => setReportedSearch(e.target.value)}
                placeholder="Search rumors by entity or claim..."
                className="w-full bg-surface border border-slate-700/60 rounded-lg pl-9 pr-3 py-1.5 text-xs text-white placeholder-slate-500 focus:outline-none focus:border-violet-500"
              />
            </div>
            <div className="flex items-center gap-2">
              <span className="text-xs text-slate-400 flex-shrink-0">Category:</span>
              <select
                value={reportedCatFilter}
                onChange={(e) => setReportedCatFilter(e.target.value)}
                className="bg-surface border border-slate-700/60 rounded-lg px-2.5 py-1.5 text-xs text-slate-200 focus:outline-none focus:border-violet-500"
              >
                <option value="all">All Categories</option>
                <option value="National Beat">National Beat</option>
                <option value="Team Beat Wire">Team Beat Wire</option>
                <option value="Trade Speculation">Trade Speculation</option>
              </select>
            </div>
          </div>

          {filteredReported.length === 0 ? (
            <div className="bg-surface-raised border border-slate-800/80 rounded-xl p-8 text-center text-slate-400">
              <Radio className="w-8 h-8 text-violet-400 mx-auto mb-2 opacity-60" />
              <p className="text-sm font-semibold text-slate-300">No active rumors currently pending.</p>
              <p className="text-xs text-slate-500 mt-1">Pending items are aged out after a 28-day TTL if unconfirmed.</p>
            </div>
          ) : (
            <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
              {filteredReported.map((claim) => {
                const ttlPct = Math.min(100, Math.round((claim.daysPending / 28) * 100));
                const daysRemaining = Math.max(0, 28 - claim.daysPending);
                return (
                  <div
                    key={claim.id}
                    className="bg-surface-raised border border-slate-800/80 rounded-xl p-5 space-y-3 relative overflow-hidden shadow-lg"
                  >
                    <div className="flex items-start justify-between gap-3">
                      <div>
                        <span className="px-2 py-0.5 rounded text-[10px] font-semibold bg-violet-500/20 text-violet-300 border border-violet-500/30">
                          {claim.sourceCategory}
                        </span>
                        <h4 className="text-base font-bold text-white mt-1.5">{claim.entityName}</h4>
                      </div>
                      <span className="text-[11px] font-mono text-slate-400">
                        First reported: {claim.firstReportedDate}
                      </span>
                    </div>

                    <p className="text-xs sm:text-sm text-slate-200 bg-surface p-3 rounded-lg border border-slate-800/60">
                      &ldquo;{claim.claim}&rdquo;
                    </p>

                    {/* 28-day TTL progress bar */}
                    <div className="space-y-1">
                      <div className="flex items-center justify-between text-[11px] text-slate-400">
                        <span>Aging Window (28-day TTL)</span>
                        <span className="font-mono text-amber-400">
                          Day {claim.daysPending} / 28 ({daysRemaining}d left)
                        </span>
                      </div>
                      <div className="w-full bg-slate-800 rounded-full h-1.5 overflow-hidden">
                        <div
                          className={`h-full transition-all rounded-full ${
                            ttlPct > 75 ? 'bg-rose-500' : ttlPct > 45 ? 'bg-amber-500' : 'bg-violet-500'
                          }`}
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
        <div className="space-y-4">
          <div className="flex flex-col sm:flex-row gap-3 items-stretch sm:items-center justify-between bg-surface-raised p-4 rounded-xl border border-slate-800/80">
            <div>
              <h3 className="text-sm font-bold text-white flex items-center gap-2">
                <Archive className="w-4 h-4 text-slate-400" />
                <span>Aged-Out Rumors Archive</span>
              </h3>
              <p className="text-xs text-slate-400">
                Editorial restraint: Unverified claims are categorized by beat tier rather than naming journalists.
              </p>
            </div>
            <div className="flex items-center gap-2">
              <span className="text-xs text-slate-400 flex-shrink-0">Category:</span>
              <select
                value={expiredCatFilter}
                onChange={(e) => setExpiredCatFilter(e.target.value)}
                className="bg-surface border border-slate-700/60 rounded-lg px-2.5 py-1.5 text-xs text-slate-200 focus:outline-none focus:border-violet-500"
              >
                <option value="all">All Categories</option>
                <option value="National Beat">National Beat</option>
                <option value="Team Beat Wire">Team Beat Wire</option>
                <option value="Trade Speculation">Trade Speculation</option>
              </select>
            </div>
          </div>

          {Object.keys(groupedExpired).length === 0 ? (
            <div className="bg-surface-raised border border-slate-800/80 rounded-xl p-8 text-center text-slate-400">
              <Archive className="w-8 h-8 text-slate-500 mx-auto mb-2" />
              <p className="text-sm font-semibold text-slate-300">Graveyard is clean.</p>
              <p className="text-xs text-slate-500 mt-1">No claims have aged out past the 28-day window yet.</p>
            </div>
          ) : (
            <div className="space-y-4">
              {Object.entries(groupedExpired).map(([category, items]) => (
                <div key={category} className="bg-surface-raised border border-slate-800/80 rounded-xl p-5 space-y-3">
                  <div className="flex items-center justify-between border-b border-slate-800 pb-2">
                    <span className="text-xs font-bold text-slate-200 uppercase tracking-wider">
                      {category}
                    </span>
                    <span className="text-[11px] font-mono text-slate-500">
                      {items.length} claim{items.length === 1 ? '' : 's'}
                    </span>
                  </div>
                  <div className="divide-y divide-slate-800/60">
                    {items.map((item, idx) => (
                      <div key={idx} className="py-2.5 flex flex-col sm:flex-row sm:items-center justify-between gap-2 text-xs">
                        <div className="space-y-0.5">
                          <span className="font-bold text-white mr-2">{item.entityName}:</span>
                          <span className="text-slate-300">&ldquo;{item.claim}&rdquo;</span>
                        </div>
                        <div className="flex items-center gap-2 text-[11px] font-mono text-slate-500 flex-shrink-0">
                          <span>Reported: {item.firstReportedDate}</span>
                          <span>â†’</span>
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
      {/* TAB 5: CBA CAP MATRIX                                         */}
      {/* ------------------------------------------------------------- */}
      {activeTab === 'cap' && (
        <div className="bg-surface-raised border border-slate-800/80 rounded-2xl p-6 sm:p-8 space-y-6">
          <div className="flex flex-col md:flex-row md:items-center justify-between gap-4 border-b border-slate-800 pb-5">
            <div>
              <span className="px-2.5 py-0.5 rounded-full text-[11px] font-bold uppercase tracking-wider bg-amber-500/20 text-amber-300 border border-amber-500/30">
                2027 CBA Salary Cap Matrix
              </span>
              <h3 className="text-2xl font-bold text-white mt-1">11-vs-12 Player Roster Crunch</h3>
              <p className="text-xs sm:text-sm text-slate-400 max-w-2xl mt-1">
                Under the WNBA hard salary cap ($1,520,000 for 2027), franchises carrying two or more maximum veteran contracts cannot roster a 12th player without exceeding the cap ceiling.
              </p>
            </div>
            <Link
              href="/cap-sheet"
              className="inline-flex items-center gap-2 px-4 py-2.5 rounded-xl bg-violet-600 hover:bg-violet-500 text-white font-semibold text-xs transition-colors shadow-lg shadow-violet-600/30 self-start md:self-center"
            >
              <span>Explore Interactive Cap Sheet</span>
              <ArrowRight className="w-4 h-4" />
            </Link>
          </div>

          <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
            <div className="bg-surface p-4 rounded-xl border border-slate-800 space-y-1">
              <span className="text-xs text-slate-400">2027 Salary Cap Ceiling</span>
              <div className="text-xl font-bold text-white">$1,520,000</div>
              <div className="text-[11px] text-slate-500">Rigid hard cap ceiling (no luxury tax exceptions)</div>
            </div>
            <div className="bg-surface p-4 rounded-xl border border-slate-800 space-y-1">
              <span className="text-xs text-slate-400">Supermax Veteran Level</span>
              <div className="text-xl font-bold text-amber-300">~$242,000</div>
              <div className="text-[11px] text-slate-500">Max allowable salary for cored / veteran franchise players</div>
            </div>
            <div className="bg-surface p-4 rounded-xl border border-slate-800 space-y-1">
              <span className="text-xs text-slate-400">Rookie Minimum Scale</span>
              <div className="text-xl font-bold text-emerald-400">~$68,000</div>
              <div className="text-[11px] text-slate-500">Mandated minimum cap charge for rookie picks 1-12</div>
            </div>
          </div>
        </div>
      )}
    </div>
  );
};
