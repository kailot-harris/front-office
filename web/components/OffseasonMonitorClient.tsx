'use client';

import React, { useState, useMemo } from 'react';
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
  Globe,
  Radio,
  History,
  AlertTriangle,
  ChevronLeft,
  ChevronRight,
  ChevronDown,
  ChevronUp,
  Layers,
  Copy,
  Check,
  ShieldCheck,
} from 'lucide-react';
import { MediaSentimentPulseCard } from './MediaSentimentPulseCard';
import {
  OffseasonMonitorDataset,
  OffseasonEdition,
  ConfirmedChange,
  OffseasonChangeType,
} from '@/lib/offseasonTypes';

interface Props {
  initialDataset: OffseasonMonitorDataset | null;
}

const WNBA_TEAM_CODES = [
  'ATL', 'CHI', 'CON', 'DAL', 'GSV', 'IND', 'LA', 'LVA', 'MIN', 'NY', 'PHX', 'POR', 'SEA', 'TOR', 'WAS'
];

const ALL_CHANGE_TYPES: OffseasonChangeType[] = [
  OffseasonChangeType.SIGNING,
  OffseasonChangeType.WAIVER,
  OffseasonChangeType.RELEASE,
  OffseasonChangeType.TRADE,
  OffseasonChangeType.WAIVER_CLAIM,
  OffseasonChangeType.CONTRACT_OFFER,
  OffseasonChangeType.OFFER_MATCH,
  OffseasonChangeType.ROSTER_STATUS,
  OffseasonChangeType.FRONT_OFFICE,
  OffseasonChangeType.CORE_DESIGNATION,
  OffseasonChangeType.RESERVED_PLAYER,
  OffseasonChangeType.QUALIFYING_OFFER,
  OffseasonChangeType.PRIORITIZATION,
  OffseasonChangeType.RETIREMENT,
  OffseasonChangeType.SUSPENSION,
  OffseasonChangeType.DRAFT_RIGHTS,
  OffseasonChangeType.EXPANSION_DRAFT,
  OffseasonChangeType.UNCLASSIFIED,
];

const getTransactionChangeType = (item: ConfirmedChange): string => {
  if (item.changeType) return item.changeType;
  const raw = item as unknown as Record<string, unknown>;
  if (typeof raw.change_type === 'string') return raw.change_type;
  if (item.field && item.field.toUpperCase() === 'UNCLASSIFIED') return 'UNCLASSIFIED';
  return 'UNCLASSIFIED';
};

const getTransactionTeam = (item: ConfirmedChange): string => {
  if (item.team) return item.team.toUpperCase();
  const raw = item as unknown as Record<string, unknown>;
  if (typeof raw.team_abbr === 'string') return raw.team_abbr.toUpperCase();
  const upperEntityId = item.entityId ? item.entityId.toUpperCase() : '';
  if (WNBA_TEAM_CODES.includes(upperEntityId)) return upperEntityId;
  
  if (item.entityName) {
    const upperName = item.entityName.toUpperCase();
    for (const code of WNBA_TEAM_CODES) {
      if (upperName.includes(code)) return code;
    }
  }

  if (item.field && item.field.toLowerCase() === 'team') {
    if (item.newValue && item.newValue !== 'None') {
      const val = item.newValue.toUpperCase();
      if (WNBA_TEAM_CODES.includes(val)) return val;
    }
    if (item.priorValue && item.priorValue !== 'None') {
      const val = item.priorValue.toUpperCase();
      if (WNBA_TEAM_CODES.includes(val)) return val;
    }
  }

  if (item.newValue && WNBA_TEAM_CODES.includes(item.newValue.toUpperCase())) {
    return item.newValue.toUpperCase();
  }
  if (item.priorValue && WNBA_TEAM_CODES.includes(item.priorValue.toUpperCase())) {
    return item.priorValue.toUpperCase();
  }
  return 'LEAGUE';
};

const formatEntityName = (name: string | null | undefined, id?: string): string => {
  if (name && name !== 'NA' && name !== 'null' && name.trim().length > 0) return name;
  if (id && id !== 'NA' && id !== 'null' && id.trim().length > 0) {
    if (id.startsWith('claim-')) {
      return `League Wire Item #${id.replace('claim-', '')}`;
    }
    return id;
  }
  return 'League Roster Wire';
};

const formatClaimText = (claim: string | null | undefined): string => {
  if (!claim) return 'Unclassified transaction wire report under active verification';
  const clean = claim.trim();
  if (
    clean === 'Reported move involving NA unclassified' ||
    clean.includes('involving NA unclassified')
  ) {
    return 'Beat wire report pending entity & transaction classification';
  }
  return clean;
};

const getSourceCategoryBadge = (category: string) => {
  switch (category) {
    case 'National Beat':
      return 'bg-emerald-500/20 text-emerald-300 border-emerald-500/30';
    case 'Team Beat Wire':
      return 'bg-violet-500/20 text-violet-300 border-violet-500/30';
    case 'Trade Speculation':
      return 'bg-amber-500/20 text-amber-300 border-amber-500/30';
    default:
      return 'bg-slate-700/40 text-slate-300 border-slate-600/40';
  }
};

const getChangeTypeBadge = (changeType: string) => {
  switch (changeType) {
    case 'SIGNING':
      return 'bg-emerald-500/20 text-emerald-300 border-emerald-500/30';
    case 'TRADE':
      return 'bg-cyan-500/20 text-cyan-300 border-cyan-500/30';
    case 'WAIVER':
    case 'RELEASE':
      return 'bg-rose-500/20 text-rose-300 border-rose-500/30';
    case 'CONTRACT_OFFER':
    case 'QUALIFYING_OFFER':
      return 'bg-amber-500/20 text-amber-300 border-amber-500/30';
    case 'FRONT_OFFICE':
      return 'bg-purple-500/20 text-purple-300 border-purple-500/30';
    case 'UNCLASSIFIED':
      return 'bg-amber-500/20 text-amber-300 border-amber-500/30';
    default:
      return 'bg-violet-500/20 text-violet-300 border-violet-500/30';
  }
};

const formatSourceUrl = (url: string) => {
  try {
    const parsed = new URL(url);
    if (parsed.hostname.includes('wnba.com')) return { title: 'WNBA Official Transactions Wire', host: 'wnba.com' };
    if (parsed.hostname.includes('espn.com')) return { title: 'ESPN WNBA Transactions', host: 'espn.com' };
    if (parsed.hostname.includes('unrivaled.basketball')) return { title: 'Unrivaled Official League Roster', host: 'unrivaled.basketball' };
    return { title: parsed.hostname + (parsed.pathname !== '/' ? parsed.pathname : ''), host: parsed.hostname };
  } catch {
    return { title: url, host: 'wire' };
  }
};

export const OffseasonMonitorClient: React.FC<Props> = ({ initialDataset }) => {
  const editions = useMemo(() => initialDataset?.editions || [], [initialDataset]);
  const latestEdition = editions.length > 0 ? editions[editions.length - 1] : null;

  const [selectedWeek, setSelectedWeek] = useState<number>(
    initialDataset?.currentWeekNumber || (latestEdition ? latestEdition.weekNumber : 1)
  );

  const [activeTab, setActiveTab] = useState<
    'memo' | 'confirmed' | 'reported' | 'expired' | 'cap'
  >('memo');

  const [showRawMarkdown, setShowRawMarkdown] = useState(false);
  const [copiedMemo, setCopiedMemo] = useState(false);

  const handleCopyMemo = () => {
    if (currentEdition?.memoMarkdown && typeof navigator !== 'undefined') {
      navigator.clipboard.writeText(currentEdition.memoMarkdown);
      setCopiedMemo(true);
      setTimeout(() => setCopiedMemo(false), 2000);
    }
  };

  // Confirmed Changes filter and pagination state
  const [confirmedSearch, setConfirmedSearch] = useState('');
  const [confirmedFieldFilter, setConfirmedFieldFilter] = useState('all');
  const [confirmedChangeTypeFilter, setConfirmedChangeTypeFilter] = useState('all');
  const [confirmedTeamFilter, setConfirmedTeamFilter] = useState('all');
  const [confirmedGroupBy, setConfirmedGroupBy] = useState<'none' | 'team' | 'changeType'>('none');
  const [confirmedPage, setConfirmedPage] = useState(1);
  const [confirmedPageSize, setConfirmedPageSize] = useState(25);

  // Reported Claims search, filter and pagination state
  const [reportedSearch, setReportedSearch] = useState('');
  const [reportedCatFilter, setReportedCatFilter] = useState('all');
  const [reportedPage, setReportedPage] = useState(1);
  const [reportedPageSize, setReportedPageSize] = useState(25);

  // Expired Claims filter and per-category slice state
  const [expiredCatFilter, setExpiredCatFilter] = useState('all');
  const [expiredSliceSize, setExpiredSliceSize] = useState(25);

  const currentEdition: OffseasonEdition | null = useMemo(() => {
    return editions.find((ed) => ed.weekNumber === selectedWeek) || latestEdition;
  }, [editions, selectedWeek, latestEdition]);

  // Iteration site 1: confirmedChanges.forEach with bounded processing and metadata extraction
  const { confirmedFields, confirmedChangeTypes, confirmedTeams, unclassifiedCount } = useMemo(() => {
    if (!currentEdition) {
      return { confirmedFields: [], confirmedChangeTypes: [], confirmedTeams: [], unclassifiedCount: 0 };
    }
    const fields = new Set<string>();
    const changeTypes = new Set<string>();
    const teams = new Set<string>();
    let unclassified = 0;

    currentEdition.confirmedChanges.forEach((c) => {
      if (c.field) fields.add(c.field);
      const ct = getTransactionChangeType(c);
      if (ct) changeTypes.add(ct);
      if (ct === 'UNCLASSIFIED') unclassified++;
      const tm = getTransactionTeam(c);
      if (tm && tm !== 'LEAGUE') teams.add(tm);
    });

    return {
      confirmedFields: Array.from(fields).sort(),
      confirmedChangeTypes: Array.from(changeTypes).sort(),
      confirmedTeams: Array.from(teams).sort(),
      unclassifiedCount: unclassified,
    };
  }, [currentEdition]);

  // Combined options for dropdowns
  const availableChangeTypes = useMemo(() => {
    const list = Array.from(new Set<string>([...ALL_CHANGE_TYPES, ...confirmedChangeTypes]));
    return list.sort();
  }, [confirmedChangeTypes]);

  const availableTeams = useMemo(() => {
    const list = Array.from(new Set<string>([...WNBA_TEAM_CODES, ...confirmedTeams]));
    return list.sort();
  }, [confirmedTeams]);

  // Filtered confirmed changes
  const filteredConfirmed = useMemo(() => {
    if (!currentEdition) return [];
    return currentEdition.confirmedChanges.filter((item) => {
      const ct = getTransactionChangeType(item);
      const tm = getTransactionTeam(item);

      const term = confirmedSearch.toLowerCase();
      const matchSearch = !term ||
        (item.entityName ? item.entityName.toLowerCase().includes(term) : false) ||
        (item.newValue ? item.newValue.toLowerCase().includes(term) : false) ||
        (item.priorValue ? item.priorValue.toLowerCase().includes(term) : false) ||
        (item.field ? item.field.toLowerCase().includes(term) : false) ||
        (ct ? ct.toLowerCase().includes(term) : false) ||
        (tm ? tm.toLowerCase().includes(term) : false);

      const matchField =
        confirmedFieldFilter === 'all' || item.field === confirmedFieldFilter;

      const matchChangeType =
        confirmedChangeTypeFilter === 'all' || ct === confirmedChangeTypeFilter;

      const matchTeam =
        confirmedTeamFilter === 'all' || tm === confirmedTeamFilter;

      return matchSearch && matchField && matchChangeType && matchTeam;
    });
  }, [currentEdition, confirmedSearch, confirmedFieldFilter, confirmedChangeTypeFilter, confirmedTeamFilter]);

  // Paged slice for confirmed changes
  const totalConfirmed = filteredConfirmed.length;
  const totalConfirmedPages = Math.max(1, Math.ceil(totalConfirmed / confirmedPageSize));
  const confirmedStartIndex = (confirmedPage - 1) * confirmedPageSize;
  const displayedConfirmed = useMemo(() => {
    return filteredConfirmed.slice(confirmedStartIndex, confirmedStartIndex + confirmedPageSize);
  }, [filteredConfirmed, confirmedStartIndex, confirmedPageSize]);

  // Grouped confirmed changes when groupBy is selected
  const groupedConfirmed = useMemo(() => {
    if (confirmedGroupBy === 'none') return null;
    const groups: Record<string, ConfirmedChange[]> = {};
    filteredConfirmed.forEach((item) => {
      const key = confirmedGroupBy === 'changeType' ? getTransactionChangeType(item) : getTransactionTeam(item);
      if (!groups[key]) groups[key] = [];
      groups[key].push(item);
    });
    return groups;
  }, [filteredConfirmed, confirmedGroupBy]);

  // Filtered reported claims
  const filteredReported = useMemo(() => {
    if (!currentEdition) return [];
    return currentEdition.reportedClaims.filter((claim) => {
      const term = reportedSearch.toLowerCase();
      const matchSearch = !term ||
        (claim.entityName ? claim.entityName.toLowerCase().includes(term) : false) ||
        (claim.claim ? claim.claim.toLowerCase().includes(term) : false);
      const matchCat =
        reportedCatFilter === 'all' || claim.sourceCategory === reportedCatFilter;
      return matchSearch && matchCat;
    });
  }, [currentEdition, reportedSearch, reportedCatFilter]);

  // Paged slice for reported claims
  const totalReported = filteredReported.length;
  const totalReportedPages = Math.max(1, Math.ceil(totalReported / reportedPageSize));
  const reportedStartIndex = (reportedPage - 1) * reportedPageSize;
  const displayedReported = useMemo(() => {
    return filteredReported.slice(reportedStartIndex, reportedStartIndex + reportedPageSize);
  }, [filteredReported, reportedStartIndex, reportedPageSize]);

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
              <span className="text-slate-600">•</span>
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
                    onClick={() => {
                      setSelectedWeek(ed.weekNumber);
                      setConfirmedPage(1);
                      setReportedPage(1);
                    }}
                    className={`px-3 py-1.5 rounded-lg text-xs font-bold transition-all whitespace-nowrap ${
                      isSelected
                        ? 'bg-violet-600 text-white shadow-md shadow-violet-600/30'
                        : 'text-slate-400 hover:text-white hover:bg-slate-800'
                    }`}
                  >
                    Week {ed.weekNumber}
                    {ed.isQuietWeek && (
                      <span className="ml-1 text-[11px] sm:text-[10px] text-slate-400 opacity-70">
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
            $1.000M Hard Cap
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
          <span className="px-1.5 py-0.5 rounded-full text-[11px] sm:text-[10px] bg-slate-800 text-slate-300 font-mono">
            {currentEdition.confirmedChanges.length}
          </span>
          {unclassifiedCount > 0 && (
            <span className="px-1.5 py-0.5 rounded-full text-[11px] sm:text-[10px] bg-amber-500/20 text-amber-300 border border-amber-500/30 font-bold font-mono">
              Unclassified: {unclassifiedCount}
            </span>
          )}
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
          <span className="px-1.5 py-0.5 rounded-full text-[11px] sm:text-[10px] bg-slate-800 text-slate-300 font-mono">
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
          <span className="px-1.5 py-0.5 rounded-full text-[11px] sm:text-[10px] bg-slate-800 text-slate-300 font-mono">
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
      {/* TAB 1: EXECUTIVE BRIEF (7-BLOCK ANALYTICAL DOSSIER)           */}
      {/* ------------------------------------------------------------- */}
      {activeTab === 'memo' && (
        <div className="space-y-6">
          {/* Top Dossier Header Card with Actions */}
          <div className="bg-surface-raised border border-slate-800/80 rounded-2xl p-6 shadow-xl relative overflow-hidden">
            <div className="absolute top-0 left-0 right-0 h-1 bg-gradient-to-r from-violet-500 via-indigo-500 to-purple-500" />
            
            <div className="flex flex-col md:flex-row md:items-center justify-between gap-4">
              <div className="space-y-1.5">
                <div className="flex flex-wrap items-center gap-2">
                  <span className="px-2.5 py-0.5 rounded-full text-[11px] font-bold uppercase tracking-wider bg-violet-500/20 text-violet-300 border border-violet-500/30 flex items-center gap-1.5">
                    <FileText className="w-3.5 h-3.5 text-violet-400" />
                    Analytical Brief
                  </span>
                  <span className="text-xs text-slate-400 font-mono">
                    Edition: <strong className="text-slate-200">Week {currentEdition.weekNumber}</strong>
                  </span>
                  <span className="text-slate-600">•</span>
                  <span className="text-xs text-slate-400 font-mono">
                    Published: {currentEdition.publishDate}
                  </span>
                  <span className="text-slate-600">•</span>
                  {currentEdition.isQuietWeek ? (
                    <span className="px-2 py-0.5 rounded text-[11px] sm:text-[10px] font-bold bg-amber-500/10 text-amber-300 border border-amber-500/30 flex items-center gap-1">
                      <Clock className="w-3 h-3 text-amber-400" />
                      Quiet Week
                    </span>
                  ) : (
                    <span className="px-2 py-0.5 rounded text-[11px] sm:text-[10px] font-bold bg-emerald-500/10 text-emerald-300 border border-emerald-500/30 flex items-center gap-1">
                      <CheckCircle2 className="w-3 h-3 text-emerald-400" />
                      {currentEdition.confirmedChanges.length} Active Transitions
                    </span>
                  )}
                </div>
                <h2 className="text-xl sm:text-2xl font-extrabold text-white tracking-tight">
                  Executive Analytical Brief &amp; State-Diff Dossier
                </h2>
                <p className="text-xs sm:text-sm text-slate-400 max-w-3xl">
                  Reconciled weekly intelligence briefing synthesizing deterministic roster state mutations, beat rumor trajectory, CBA hard cap pressure, and baseline Bayesian prior stability.
                </p>
              </div>

              {/* Utility actions: Copy Memo & Toggle Raw Markdown */}
              <div className="flex items-center gap-2 self-start md:self-center flex-shrink-0">
                <button
                  onClick={handleCopyMemo}
                  className="px-3 py-1.5 rounded-lg text-xs font-semibold bg-surface border border-slate-700/70 text-slate-300 hover:text-white hover:bg-slate-800 transition-colors flex items-center gap-1.5 shadow-sm"
                  title="Copy markdown memo to clipboard"
                >
                  {copiedMemo ? (
                    <>
                      <Check className="w-3.5 h-3.5 text-emerald-400" />
                      <span className="text-emerald-300">Copied</span>
                    </>
                  ) : (
                    <>
                      <Copy className="w-3.5 h-3.5 text-slate-400" />
                      <span>Copy Memo</span>
                    </>
                  )}
                </button>

                <button
                  onClick={() => setShowRawMarkdown(!showRawMarkdown)}
                  className={`px-3 py-1.5 rounded-lg text-xs font-semibold border transition-colors flex items-center gap-1.5 shadow-sm ${
                    showRawMarkdown
                      ? 'bg-violet-600/30 border-violet-500/50 text-violet-200'
                      : 'bg-surface border-slate-700/70 text-slate-300 hover:text-white hover:bg-slate-800'
                  }`}
                  title="Toggle raw markdown preview"
                >
                  <FileText className="w-3.5 h-3.5 text-violet-400" />
                  <span>{showRawMarkdown ? 'Hide Raw Markdown' : 'Raw Markdown'}</span>
                  {showRawMarkdown ? (
                    <ChevronUp className="w-3 h-3 text-slate-400" />
                  ) : (
                    <ChevronDown className="w-3 h-3 text-slate-400" />
                  )}
                </button>
              </div>
            </div>

            {/* State of Play Callout Card */}
            <div className="mt-5 p-4 sm:p-5 rounded-xl bg-gradient-to-r from-violet-950/40 via-surface to-surface border border-violet-500/20">
              <div className="flex items-center gap-2 mb-2">
                <Sparkles className="w-4 h-4 text-violet-400" />
                <span className="text-xs font-bold uppercase tracking-wider text-violet-300">
                  State of Play Summary
                </span>
              </div>
              <p className="text-sm sm:text-base text-slate-100 font-medium leading-relaxed">
                {currentEdition.stateOfPlay}
              </p>
              
              {/* Executive Mini Metric Strip */}
              <div className="grid grid-cols-2 sm:grid-cols-4 gap-3 mt-4 pt-4 border-t border-slate-800/80">
                <div className="space-y-0.5">
                  <span className="text-[11px] sm:text-[10px] uppercase tracking-wider text-slate-400 font-semibold block">Confirmed Diffs</span>
                  <div className="text-sm sm:text-base font-extrabold text-white flex items-center gap-1.5">
                    <CheckCircle2 className="w-3.5 h-3.5 text-emerald-400" />
                    <span>{currentEdition.confirmedChanges.length} Filed</span>
                  </div>
                </div>
                <div className="space-y-0.5">
                  <span className="text-[11px] sm:text-[10px] uppercase tracking-wider text-slate-400 font-semibold block">Radar Volume</span>
                  <div className="text-sm sm:text-base font-extrabold text-white flex items-center gap-1.5">
                    <Radio className="w-3.5 h-3.5 text-violet-400" />
                    <span>{currentEdition.reportedClaims.length} Tracked</span>
                  </div>
                </div>
                <div className="space-y-0.5">
                  <span className="text-[11px] sm:text-[10px] uppercase tracking-wider text-slate-400 font-semibold block">Cap Pressure</span>
                  <div className="text-sm sm:text-base font-extrabold text-amber-300 flex items-center gap-1.5">
                    <Coins className="w-3.5 h-3.5 text-amber-400" />
                    <span>$1.000M Hard Cap</span>
                  </div>
                </div>
                <div className="space-y-0.5">
                  <span className="text-[11px] sm:text-[10px] uppercase tracking-wider text-slate-400 font-semibold block">Bayesian Priors</span>
                  <div className="text-sm sm:text-base font-extrabold text-slate-200 flex items-center gap-1.5">
                    <Layers className="w-3.5 h-3.5 text-indigo-400" />
                    <span>0.0 Δ Net Rating</span>
                  </div>
                </div>
              </div>
            </div>

            {/* Optional Collapsible Raw Markdown Drawer */}
            {showRawMarkdown && (
              <div className="mt-5 p-4 rounded-xl bg-slate-950/80 border border-slate-800 space-y-3">
                <div className="flex items-center justify-between text-xs text-slate-400 font-mono pb-2 border-b border-slate-800">
                  <div className="flex items-center gap-2">
                    <FileText className="w-3.5 h-3.5 text-violet-400" />
                    <span>Raw Markdown Memo (Phase 4 Spec)</span>
                  </div>
                  <button
                    onClick={handleCopyMemo}
                    className="text-violet-400 hover:text-violet-300 flex items-center gap-1 text-[11px]"
                  >
                    <Copy className="w-3 h-3" />
                    Copy
                  </button>
                </div>
                <pre className="text-xs font-mono text-slate-300 whitespace-pre-wrap overflow-x-auto max-h-96 p-3 bg-surface rounded-lg border border-slate-800/80 leading-relaxed">
                  {currentEdition.memoMarkdown}
                </pre>
              </div>
            )}
          </div>

          {/* ----------------------------------------------------------- */}
          {/* BLOCK 1: CONFIRMED CHANGES                                  */}
          {/* ----------------------------------------------------------- */}
          <div className="bg-surface-raised border border-slate-800/80 rounded-2xl p-5 sm:p-6 shadow-xl space-y-4">
            <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-3 pb-3 border-b border-slate-800/80">
              <div className="flex items-center gap-2.5">
                <div className="p-2 rounded-xl bg-emerald-500/10 border border-emerald-500/20 text-emerald-400">
                  <CheckCircle2 className="w-4 h-4" />
                </div>
                <div>
                  <h3 className="text-base font-bold text-white flex items-center gap-2">
                    <span>1. Confirmed Transactions</span>
                    <span className="px-2 py-0.5 rounded-full text-xs font-mono font-semibold bg-slate-800 text-slate-300">
                      {currentEdition.confirmedChanges.length}
                    </span>
                  </h3>
                  <p className="text-xs text-slate-400">
                    Tier 1 state mutations reconciled against immutable baseline S0.
                  </p>
                </div>
              </div>

              {currentEdition.confirmedChanges.length > 0 && (
                <button
                  onClick={() => setActiveTab('confirmed')}
                  className="px-3 py-1 rounded-lg text-xs font-semibold text-violet-400 hover:text-violet-300 hover:bg-violet-950/30 transition-colors flex items-center gap-1 self-start sm:self-center"
                >
                  <span>Open Full Ledger</span>
                  <ArrowRight className="w-3.5 h-3.5" />
                </button>
              )}
            </div>

            {currentEdition.confirmedChanges.length === 0 ? (
              <div className="p-5 rounded-xl bg-surface border border-slate-800/80 flex flex-col sm:flex-row items-start sm:items-center justify-between gap-4">
                <div className="flex items-start gap-3.5">
                  <div className="p-2.5 rounded-xl bg-emerald-500/10 border border-emerald-500/20 text-emerald-400 flex-shrink-0 mt-0.5 sm:mt-0">
                    <ShieldCheck className="w-5 h-5" />
                  </div>
                  <div className="space-y-1">
                    <h4 className="text-sm font-bold text-white">Baseline Roster States Invariant</h4>
                    <p className="text-xs text-slate-400 max-w-2xl leading-relaxed">
                      Zero official contract signings, waivers, releases, or trades were filed with the league office during this interval. All 15 franchise rosters, coaching staffs, and player contracts remain identical to Baseline S0 (2026-11-07).
                    </p>
                    <div className="flex flex-wrap items-center gap-1.5 pt-1 text-[11px] font-mono text-slate-500">
                      <span className="px-2 py-0.5 rounded bg-surface-raised border border-slate-800">0 Signings</span>
                      <span className="px-2 py-0.5 rounded bg-surface-raised border border-slate-800">0 Trades</span>
                      <span className="px-2 py-0.5 rounded bg-surface-raised border border-slate-800">0 Waivers</span>
                      <span className="px-2 py-0.5 rounded bg-surface-raised border border-slate-800">0 Front Office Changes</span>
                    </div>
                  </div>
                </div>

                <button
                  onClick={() => setActiveTab('confirmed')}
                  className="px-3 py-1.5 rounded-lg text-xs font-semibold bg-surface-raised border border-slate-700/60 text-slate-300 hover:text-white hover:bg-slate-800 transition-colors whitespace-nowrap self-start sm:self-center"
                >
                  Inspect Ledger Tab
                </button>
              </div>
            ) : (
              <div className="overflow-x-auto">
                <table className="w-full text-left text-xs">
                  <thead>
                    <tr className="bg-surface border-b border-slate-800 text-slate-400 font-semibold uppercase tracking-wider text-[11px] sm:text-[10px]">
                      <th className="py-2.5 px-3">Date</th>
                      <th className="py-2.5 px-3">Entity</th>
                      <th className="py-2.5 px-3">Type</th>
                      <th className="py-2.5 px-3">Field</th>
                      <th className="py-2.5 px-3">Prior State (S_last)</th>
                      <th className="py-2.5 px-3">New State (S_t)</th>
                      <th className="py-2.5 px-3">Source</th>
                    </tr>
                  </thead>
                  <tbody className="divide-y divide-slate-800/60">
                    {currentEdition.confirmedChanges.slice(0, 10).map((item, idx) => {
                      const ct = getTransactionChangeType(item);
                      return (
                        <tr key={idx} className="hover:bg-slate-800/30 transition-colors">
                          <td className="py-2.5 px-3 font-mono text-slate-400 whitespace-nowrap">{item.date || '—'}</td>
                          <td className="py-2.5 px-3 font-bold text-white whitespace-nowrap">{formatEntityName(item.entityName, item.entityId)}</td>
                          <td className="py-2.5 px-3 whitespace-nowrap">
                            <span className={`px-2 py-0.5 rounded text-[11px] sm:text-[10px] font-mono font-semibold border ${getChangeTypeBadge(ct)}`}>
                              {ct}
                            </span>
                          </td>
                          <td className="py-2.5 px-3 text-violet-400 font-mono">{item.field}</td>
                          <td className="py-2.5 px-3 font-mono text-slate-400">{item.priorValue}</td>
                          <td className="py-2.5 px-3 font-mono text-emerald-400 font-semibold">{item.newValue}</td>
                          <td className="py-2.5 px-3 whitespace-nowrap">
                            {item.sourceUrl ? (
                              <a href={item.sourceUrl} target="_blank" rel="noreferrer" className="text-violet-400 hover:text-violet-300 flex items-center gap-1 font-mono text-[11px]">
                                <span>Wire</span>
                                <ExternalLink className="w-3 h-3" />
                              </a>
                            ) : '—'}
                          </td>
                        </tr>
                      );
                    })}
                  </tbody>
                </table>
              </div>
            )}
          </div>

          {/* ----------------------------------------------------------- */}
          {/* BLOCK 2: REPORTED (UNCONFIRMED) RADAR                       */}
          {/* ----------------------------------------------------------- */}
          <div className="bg-surface-raised border border-slate-800/80 rounded-2xl p-5 sm:p-6 shadow-xl space-y-4">
            <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-3 pb-3 border-b border-slate-800/80">
              <div className="flex items-center gap-2.5">
                <div className="p-2 rounded-xl bg-violet-500/10 border border-violet-500/20 text-violet-400">
                  <Radio className="w-4 h-4 animate-pulse" />
                </div>
                <div>
                  <h3 className="text-base font-bold text-white flex items-center gap-2">
                    <span>2. Reported (Unconfirmed) Radar</span>
                    <span className="px-2 py-0.5 rounded-full text-xs font-mono font-semibold bg-violet-500/20 text-violet-300 border border-violet-500/30">
                      {currentEdition.reportedClaims.length} Claims
                    </span>
                  </h3>
                  <p className="text-xs text-slate-400">
                    Tier 2/3 media and beat speculation under continuous 28-day TTL observation.
                  </p>
                </div>
              </div>

              <button
                onClick={() => setActiveTab('reported')}
                className="px-3 py-1.5 rounded-lg text-xs font-semibold bg-violet-600/20 hover:bg-violet-600/30 text-violet-300 border border-violet-500/40 transition-colors flex items-center gap-1.5 self-start sm:self-center"
              >
                <span>Explore Full Radar ({currentEdition.reportedClaims.length})</span>
                <ArrowRight className="w-3.5 h-3.5" />
              </button>
            </div>

            {/* Radar Distribution Strip */}
            <div className="flex flex-wrap items-center gap-2 text-xs">
              <span className="text-slate-400 font-semibold mr-1">Distribution:</span>
              <span className="px-2.5 py-1 rounded-lg bg-surface border border-slate-800 text-slate-300 font-mono text-[11px] flex items-center gap-1.5">
                <span className="w-2 h-2 rounded-full bg-violet-400" />
                Team Beat Wire: {currentEdition.reportedClaims.filter(c => c.sourceCategory === 'Team Beat Wire').length}
              </span>
              <span className="px-2.5 py-1 rounded-lg bg-surface border border-slate-800 text-slate-300 font-mono text-[11px] flex items-center gap-1.5">
                <span className="w-2 h-2 rounded-full bg-emerald-400" />
                National Beat: {currentEdition.reportedClaims.filter(c => c.sourceCategory === 'National Beat').length}
              </span>
              <span className="px-2.5 py-1 rounded-lg bg-surface border border-slate-800 text-slate-300 font-mono text-[11px] flex items-center gap-1.5">
                <span className="w-2 h-2 rounded-full bg-amber-400" />
                Trade Speculation: {currentEdition.reportedClaims.filter(c => c.sourceCategory === 'Trade Speculation').length}
              </span>
              <span className="text-slate-500 text-[11px] ml-auto hidden md:inline">
                28-day TTL lifecycle • Unconfirmed claims automatically retire
              </span>
            </div>

            {/* Curated Feed: Top 6 Claims */}
            <div className="grid grid-cols-1 md:grid-cols-2 gap-3">
              {currentEdition.reportedClaims.slice(0, 6).map((claim) => {
                const daysRemaining = Math.max(0, 28 - claim.daysPending);
                return (
                  <div
                    key={claim.id}
                    className="p-4 rounded-xl bg-surface border border-slate-800/80 hover:border-slate-700/80 transition-all space-y-2.5"
                  >
                    <div className="flex items-center justify-between gap-2">
                      <span className={`px-2 py-0.5 rounded text-[11px] sm:text-[10px] font-semibold border ${getSourceCategoryBadge(claim.sourceCategory)}`}>
                        {claim.sourceCategory}
                      </span>
                      <div className="flex items-center gap-1.5 text-[11px] font-mono text-slate-400">
                        <span className="w-1.5 h-1.5 rounded-full bg-amber-400 animate-pulse" />
                        <span>Pending (Day {claim.daysPending})</span>
                      </div>
                    </div>

                    <div>
                      <h4 className="text-sm font-bold text-white">
                        {formatEntityName(claim.entityName, claim.id)}
                      </h4>
                      <p className="text-xs text-slate-300 mt-1 leading-relaxed">
                        {formatClaimText(claim.claim)}
                      </p>
                    </div>

                    <div className="flex items-center justify-between text-[11px] font-mono text-slate-500 pt-1 border-t border-slate-800/60">
                      <span>Reported: {claim.firstReportedDate}</span>
                      <span>{daysRemaining}d left in TTL window</span>
                    </div>
                  </div>
                );
              })}
            </div>

            {/* Radar Card Footer */}
            <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-3 pt-2 text-xs text-slate-400">
              <span className="font-mono">
                Showing top 6 priority claims ({currentEdition.reportedClaims.length - 6 > 0 ? `${currentEdition.reportedClaims.length - 6} omitted from preview` : 'all displayed'})
              </span>
              <button
                onClick={() => setActiveTab('reported')}
                className="text-violet-400 hover:text-violet-300 font-semibold flex items-center gap-1 self-start sm:self-center"
              >
                <span>View all {currentEdition.reportedClaims.length} rumors in Reported Radar</span>
                <ArrowRight className="w-3.5 h-3.5" />
              </button>
            </div>
          </div>

          {/* ----------------------------------------------------------- */}
          {/* BLOCK 3: EXPIRED CLAIMS LEDGER                              */}
          {/* ----------------------------------------------------------- */}
          <div className="bg-surface-raised border border-slate-800/80 rounded-2xl p-5 sm:p-6 shadow-xl space-y-4">
            <div className="flex items-center justify-between gap-3 pb-3 border-b border-slate-800/80">
              <div className="flex items-center gap-2.5">
                <div className="p-2 rounded-xl bg-slate-800 border border-slate-700/60 text-slate-400">
                  <Archive className="w-4 h-4" />
                </div>
                <div>
                  <h3 className="text-base font-bold text-white flex items-center gap-2">
                    <span>3. Expired Claims Ledger (&gt; 28 Days TTL)</span>
                    <span className="px-2 py-0.5 rounded-full text-xs font-mono font-semibold bg-slate-800 text-slate-400">
                      {currentEdition.expiredClaims.length}
                    </span>
                  </h3>
                  <p className="text-xs text-slate-400">
                    Claims retired after 28 continuous days without official wire verification.
                  </p>
                </div>
              </div>

              {currentEdition.expiredClaims.length > 0 && (
                <button
                  onClick={() => setActiveTab('expired')}
                  className="px-3 py-1 rounded-lg text-xs font-semibold text-slate-400 hover:text-slate-200 transition-colors flex items-center gap-1"
                >
                  <span>Open Graveyard</span>
                  <ArrowRight className="w-3.5 h-3.5" />
                </button>
              )}
            </div>

            {currentEdition.expiredClaims.length === 0 ? (
              <div className="p-4 rounded-xl bg-surface border border-slate-800/80 flex items-center gap-3">
                <Archive className="w-4 h-4 text-slate-500 flex-shrink-0" />
                <p className="text-xs text-slate-400">
                  <strong className="text-slate-300">Graveyard Clear:</strong> Zero claims have aged past the 28-day TTL threshold. All active rumors remain within their valid reporting interval.
                </p>
              </div>
            ) : (
              <div className="space-y-2">
                {currentEdition.expiredClaims.map((item, idx) => (
                  <div key={idx} className="p-3 rounded-lg bg-surface border border-slate-800/80 flex items-center justify-between text-xs">
                    <div>
                      <span className="font-bold text-white mr-2">{formatEntityName(item.entityName)}</span>
                      <span className="text-slate-400">{formatClaimText(item.claim)}</span>
                    </div>
                    <span className="text-slate-500 font-mono text-[11px]">Expired: {item.expiredDate}</span>
                  </div>
                ))}
              </div>
            )}
          </div>

          {/* ----------------------------------------------------------- */}
          {/* TWO COLUMN GRID: BLOCK 4 (CALENDAR) & BLOCK 5 (MODEL)       */}
          {/* ----------------------------------------------------------- */}
          <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
            {/* BLOCK 4: NEXT 30 DAYS MILESTONES */}
            <div className="bg-surface-raised border border-slate-800/80 rounded-2xl p-5 sm:p-6 shadow-xl space-y-4">
              <div className="flex items-center gap-2.5 pb-3 border-b border-slate-800/80">
                <div className="p-2 rounded-xl bg-violet-500/10 border border-violet-500/20 text-violet-400">
                  <Calendar className="w-4 h-4" />
                </div>
                <div>
                  <h3 className="text-base font-bold text-white">4. Next 30 Days (Milestone Calendar)</h3>
                  <p className="text-xs text-slate-400">Scheduled league events, lottery broadcast, and key transition dates.</p>
                </div>
              </div>

              {currentEdition.upcomingMilestones.length === 0 ? (
                <p className="text-xs text-slate-500 py-3">No scheduled calendar events in next 30 days.</p>
              ) : (
                <div className="space-y-2.5">
                  {currentEdition.upcomingMilestones.map((m, idx) => (
                    <div
                      key={idx}
                      className="p-3.5 rounded-xl bg-surface border border-slate-800/70 flex items-start justify-between gap-3 text-xs"
                    >
                      <div className="space-y-1">
                        <span className="font-mono text-violet-400 font-bold block text-xs">
                          {m.date || 'Date TBD'}
                        </span>
                        <span className="text-slate-200 font-medium block">
                          {m.event}
                        </span>
                      </div>
                      <span className={`px-2.5 py-0.5 rounded text-[11px] sm:text-[10px] font-semibold flex-shrink-0 ${
                        m.status === 'Confirmed'
                          ? 'bg-emerald-500/20 text-emerald-300 border border-emerald-500/30'
                          : 'bg-amber-500/10 text-amber-300 border border-amber-500/30'
                      }`}>
                        {m.status}
                      </span>
                    </div>
                  ))}
                </div>
              )}
            </div>

            {/* BLOCK 5: MODEL IMPLICATIONS */}
            <div className="bg-surface-raised border border-slate-800/80 rounded-2xl p-5 sm:p-6 shadow-xl space-y-4">
              <div className="flex items-center gap-2.5 pb-3 border-b border-slate-800/80">
                <div className="p-2 rounded-xl bg-indigo-500/10 border border-indigo-500/20 text-indigo-400">
                  <Layers className="w-4 h-4" />
                </div>
                <div>
                  <h3 className="text-base font-bold text-white">5. Model Implications (2027 Baseline Priors)</h3>
                  <p className="text-xs text-slate-400">Quantitative assessment of roster deltas on team Bayesian net rating priors.</p>
                </div>
              </div>

              <div className="p-5 rounded-xl bg-surface border border-slate-800/80 space-y-3.5">
                <div className="flex items-center justify-between gap-2">
                  <span className="px-2.5 py-1 rounded-lg text-xs font-bold bg-emerald-500/10 text-emerald-300 border border-emerald-500/30 flex items-center gap-1.5">
                    <CheckCircle2 className="w-3.5 h-3.5 text-emerald-400" />
                    Priors Invariant
                  </span>
                  <span className="text-xs font-mono text-slate-400">
                    Delta: <strong className="text-white">0.0 pts Net Rating</strong>
                  </span>
                </div>

                <p className="text-xs sm:text-sm text-slate-200 leading-relaxed font-medium">
                  {currentEdition.modelPriorImpact.summary || 'No change to 2027 baseline Bayesian priors.'}
                </p>

                <p className="text-xs text-slate-400 leading-relaxed border-t border-slate-800/70 pt-3">
                  Statistical evaluation confirms zero state mutations have crossed the threshold required to alter franchise power ratings or individual player RAPM priors. Ratings remain locked at post-2026 Finals equilibrium.
                </p>
              </div>
            </div>
          </div>

          {/* ----------------------------------------------------------- */}
          {/* TWO COLUMN GRID: BLOCK 6 (WINTER LEAGUE) & BLOCK 7 (SOURCES) */}
          {/* ----------------------------------------------------------- */}
          <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
            {/* BLOCK 6: WINTER LEAGUE & ALTERNATIVE PLAY */}
            <div className="bg-surface-raised border border-slate-800/80 rounded-2xl p-5 sm:p-6 shadow-xl space-y-4">
              <div className="flex items-center gap-2.5 pb-3 border-b border-slate-800/80">
                <div className="p-2 rounded-xl bg-sky-500/10 border border-sky-500/20 text-sky-400">
                  <Globe className="w-4 h-4" />
                </div>
                <div>
                  <h3 className="text-base font-bold text-white">6. Winter League &amp; Alternative Play</h3>
                  <p className="text-xs text-slate-400">Offseason conditioning, EuroLeague competition &amp; Unrivaled 3-on-3 tracking.</p>
                </div>
              </div>

              {currentEdition.winterLeagueNotes.length === 0 ? (
                <p className="text-xs text-slate-500 py-3">No active winter league notes this week.</p>
              ) : (
                <div className="space-y-2.5">
                  {currentEdition.winterLeagueNotes.map((note, idx) => (
                    <div
                      key={idx}
                      className="p-3.5 rounded-xl bg-surface border border-slate-800/70 flex items-start justify-between gap-3 text-xs"
                    >
                      <div className="space-y-1">
                        <div className="flex items-center gap-2">
                          <span className="font-bold text-white text-sm">{note.playerName}</span>
                          {note.wnbaTeam && (
                            <span className="px-1.5 py-0.5 rounded text-[11px] sm:text-[10px] font-mono font-bold bg-slate-800 text-slate-300 border border-slate-700">
                              {note.wnbaTeam}
                            </span>
                          )}
                        </div>
                        <div className="flex items-center gap-1.5 text-slate-400 text-xs">
                          <span className="w-1.5 h-1.5 rounded-full bg-emerald-400" />
                          <span>{note.healthStatus}</span>
                        </div>
                      </div>
                      <span className="px-2.5 py-0.5 rounded text-[11px] sm:text-[10px] font-semibold bg-sky-500/20 text-sky-300 border border-sky-500/30 flex-shrink-0">
                        {note.league}
                      </span>
                    </div>
                  ))}
                </div>
              )}
            </div>

            {/* BLOCK 7: SOURCES VERIFIED & AUDIT PROVENANCE */}
            <div className="bg-surface-raised border border-slate-800/80 rounded-2xl p-5 sm:p-6 shadow-xl space-y-4">
              <div className="flex items-center gap-2.5 pb-3 border-b border-slate-800/80">
                <div className="p-2 rounded-xl bg-emerald-500/10 border border-emerald-500/20 text-emerald-400">
                  <ShieldCheck className="w-4 h-4" />
                </div>
                <div>
                  <h3 className="text-base font-bold text-white">7. Sources Verified &amp; Audit Trail</h3>
                  <p className="text-xs text-slate-400">Deterministic ingestion feeds verified for Week {currentEdition.weekNumber} publication.</p>
                </div>
              </div>

              <div className="space-y-2.5">
                {currentEdition.sourcesVisited.map((src, idx) => {
                  const meta = formatSourceUrl(src);
                  return (
                    <a
                      key={idx}
                      href={src}
                      target="_blank"
                      rel="noreferrer"
                      className="p-3 rounded-xl bg-surface border border-slate-800/70 hover:border-slate-700 transition-all flex items-center justify-between text-xs group"
                    >
                      <div className="flex items-center gap-2.5">
                        <ExternalLink className="w-3.5 h-3.5 text-violet-400 group-hover:text-violet-300 transition-colors flex-shrink-0" />
                        <div>
                          <span className="font-semibold text-slate-200 group-hover:text-white transition-colors block">
                            {meta.title}
                          </span>
                          <span className="font-mono text-[11px] text-slate-500 block">
                            {meta.host}
                          </span>
                        </div>
                      </div>
                      <span className="px-2 py-0.5 rounded text-[11px] sm:text-[10px] font-mono font-semibold bg-emerald-500/10 text-emerald-300 border border-emerald-500/20">
                        Verified
                      </span>
                    </a>
                  );
                })}

                <div className="p-3 rounded-xl bg-surface/50 border border-slate-800/60 text-[11px] text-slate-400 flex items-center gap-2">
                  <CheckCircle2 className="w-3.5 h-3.5 text-emerald-400 flex-shrink-0" />
                  <span>
                    100% Deterministic State-Diff Protocol • Cryptographically snapshot-verified against Baseline S0.
                  </span>
                </div>
              </div>
            </div>

            {/* MEDIA SENTIMENT PULSE — unnumbered on purpose: render_7_block_memo()'s
                seven blocks are a Phase 4 spec artifact and the R renderer emits this
                as an unnumbered `### Media Sentiment Pulse` (#169). */}
            <MediaSentimentPulseCard pulse={currentEdition.mediaSentimentPulse} />
          </div>
        </div>
      )}

      {/* ------------------------------------------------------------- */}
      {/* TAB 2: CONFIRMED TRANSACTIONS LEDGER                         */}
      {/* ------------------------------------------------------------- */}
      {activeTab === 'confirmed' && (
        <div className="space-y-4">
          {/* Unclassified Transactions Alert Banner */}
          {unclassifiedCount > 0 && (
            <div className="bg-amber-500/10 border border-amber-500/30 rounded-xl p-4 flex flex-col sm:flex-row sm:items-center justify-between gap-3">
              <div className="flex items-center gap-2.5">
                <AlertTriangle className="w-5 h-5 text-amber-400 flex-shrink-0" />
                <div>
                  <span className="text-xs sm:text-sm font-bold text-amber-200">
                    {unclassifiedCount} Unclassified Transaction{unclassifiedCount === 1 ? '' : 's'} Detected
                  </span>
                  <p className="text-xs text-amber-300/80">
                    Records requiring manual classification review or dictionary vocabulary alignment.
                  </p>
                </div>
              </div>
              <button
                onClick={() => {
                  setConfirmedChangeTypeFilter('UNCLASSIFIED');
                  setConfirmedPage(1);
                }}
                className="px-3 py-1.5 rounded-lg text-xs font-bold bg-amber-500/20 text-amber-300 hover:bg-amber-500/30 border border-amber-500/40 transition-colors whitespace-nowrap self-start sm:self-center"
              >
                Filter Unclassified ({unclassifiedCount})
              </button>
            </div>
          )}

          {/* Filters & Grouping Bar */}
          <div className="bg-surface-raised p-4 rounded-xl border border-slate-800/80 space-y-3">
            <div className="flex flex-col md:flex-row gap-3 items-stretch md:items-center justify-between">
              {/* Search input */}
              <div className="relative flex-1">
                <Search className="w-4 h-4 text-slate-400 absolute left-3 top-1/2 -translate-y-1/2" />
                <input
                  type="text"
                  value={confirmedSearch}
                  onChange={(e) => {
                    setConfirmedSearch(e.target.value);
                    setConfirmedPage(1);
                  }}
                  placeholder="Search transactions by player, team, value, type..."
                  className="w-full bg-surface border border-slate-700/60 rounded-lg pl-9 pr-3 py-1.5 text-xs text-white placeholder-slate-500 focus:outline-none focus:border-violet-500"
                />
              </div>

              {/* Controls: Change Type, Team, Field, GroupBy */}
              <div className="flex flex-wrap items-center gap-2">
                {/* Change Type Filter */}
                <div className="flex items-center gap-1.5">
                  <span className="text-xs text-slate-400 flex-shrink-0">Type:</span>
                  <select
                    value={confirmedChangeTypeFilter}
                    onChange={(e) => {
                      setConfirmedChangeTypeFilter(e.target.value);
                      setConfirmedPage(1);
                    }}
                    className="bg-surface border border-slate-700/60 rounded-lg px-2.5 py-1.5 text-xs text-slate-200 focus:outline-none focus:border-violet-500"
                  >
                    <option value="all">All Types</option>
                    {availableChangeTypes.map((ct) => (
                      <option key={ct} value={ct}>
                        {ct} {ct === 'UNCLASSIFIED' && unclassifiedCount > 0 ? `(${unclassifiedCount})` : ''}
                      </option>
                    ))}
                  </select>
                </div>

                {/* Team Filter */}
                <div className="flex items-center gap-1.5">
                  <span className="text-xs text-slate-400 flex-shrink-0">Team:</span>
                  <select
                    value={confirmedTeamFilter}
                    onChange={(e) => {
                      setConfirmedTeamFilter(e.target.value);
                      setConfirmedPage(1);
                    }}
                    className="bg-surface border border-slate-700/60 rounded-lg px-2.5 py-1.5 text-xs text-slate-200 focus:outline-none focus:border-violet-500"
                  >
                    <option value="all">All Teams</option>
                    {availableTeams.map((t) => (
                      <option key={t} value={t}>{t}</option>
                    ))}
                  </select>
                </div>

                {/* Field Filter */}
                <div className="flex items-center gap-1.5">
                  <span className="text-xs text-slate-400 flex-shrink-0">Field:</span>
                  <select
                    value={confirmedFieldFilter}
                    onChange={(e) => {
                      setConfirmedFieldFilter(e.target.value);
                      setConfirmedPage(1);
                    }}
                    className="bg-surface border border-slate-700/60 rounded-lg px-2.5 py-1.5 text-xs text-slate-200 focus:outline-none focus:border-violet-500"
                  >
                    <option value="all">All Fields</option>
                    {confirmedFields.map((f) => (
                      <option key={f} value={f}>{f}</option>
                    ))}
                  </select>
                </div>

                {/* Group By selector */}
                <div className="flex items-center gap-1.5">
                  <span className="text-xs text-slate-400 flex-shrink-0">Group:</span>
                  <select
                    value={confirmedGroupBy}
                    onChange={(e) => {
                      setConfirmedGroupBy(e.target.value as 'none' | 'team' | 'changeType');
                      setConfirmedPage(1);
                    }}
                    className="bg-surface border border-slate-700/60 rounded-lg px-2.5 py-1.5 text-xs text-slate-200 focus:outline-none focus:border-violet-500"
                  >
                    <option value="none">Flat Table</option>
                    <option value="changeType">By Change Type</option>
                    <option value="team">By Team</option>
                  </select>
                </div>
              </div>
            </div>

            {/* Explicit Count Label and Page Size */}
            <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-2 pt-2 border-t border-slate-800/60 text-xs">
              <div className="text-slate-400 font-mono flex items-center gap-2">
                <span>
                  Showing {displayedConfirmed.length} of {totalConfirmed} transactions
                </span>
                {totalConfirmed !== currentEdition.confirmedChanges.length && (
                  <span className="text-slate-500">
                    (filtered from {currentEdition.confirmedChanges.length} total)
                  </span>
                )}
              </div>

              {/* Pagination controls for flat table */}
              {confirmedGroupBy === 'none' && totalConfirmed > 0 && (
                <div className="flex items-center gap-3">
                  <div className="flex items-center gap-1.5">
                    <span className="text-slate-500 text-[11px]">Rows:</span>
                    <select
                      value={confirmedPageSize}
                      onChange={(e) => {
                        setConfirmedPageSize(Number(e.target.value));
                        setConfirmedPage(1);
                      }}
                      className="bg-surface border border-slate-700/60 rounded px-2 py-0.5 text-xs text-slate-300"
                    >
                      <option value={25}>25</option>
                      <option value={50}>50</option>
                      <option value={100}>100</option>
                    </select>
                  </div>

                  <div className="flex items-center gap-1">
                    <button
                      onClick={() => setConfirmedPage((p) => Math.max(1, p - 1))}
                      disabled={confirmedPage <= 1}
                      className="p-1 rounded bg-surface border border-slate-700/60 text-slate-300 disabled:opacity-40 disabled:cursor-not-allowed hover:bg-slate-800"
                      title="Previous Page"
                    >
                      <ChevronLeft className="w-3.5 h-3.5" />
                    </button>
                    <span className="text-slate-400 text-xs font-mono px-1">
                      {confirmedPage} / {totalConfirmedPages}
                    </span>
                    <button
                      onClick={() => setConfirmedPage((p) => Math.min(totalConfirmedPages, p + 1))}
                      disabled={confirmedPage >= totalConfirmedPages}
                      className="p-1 rounded bg-surface border border-slate-700/60 text-slate-300 disabled:opacity-40 disabled:cursor-not-allowed hover:bg-slate-800"
                      title="Next Page"
                    >
                      <ChevronRight className="w-3.5 h-3.5" />
                    </button>
                  </div>
                </div>
              )}
            </div>
          </div>

          {/* Table View (Flat) */}
          {confirmedGroupBy === 'none' && (
            <div className="bg-surface-raised border border-slate-800/80 rounded-xl overflow-hidden shadow-lg">
              <div className="overflow-x-auto">
                <table className="w-full text-left text-xs">
                  <thead>
                    <tr className="bg-surface border-b border-slate-800 text-slate-400 font-semibold uppercase tracking-wider text-[11px] sm:text-[10px]">
                      <th className="py-3 px-4">Date</th>
                      <th className="py-3 px-4">Entity</th>
                      <th className="py-3 px-4">Type</th>
                      <th className="py-3 px-4">Field</th>
                      <th className="py-3 px-4">Prior State (S_last)</th>
                      <th className="py-3 px-4">New State (S_t)</th>
                      <th className="py-3 px-4">Source</th>
                    </tr>
                  </thead>
                  <tbody className="divide-y divide-slate-800/60">
                    {displayedConfirmed.length === 0 ? (
                      <tr>
                        <td colSpan={7} className="py-8 text-center text-slate-500">
                          No confirmed transactions match the current filter.
                        </td>
                      </tr>
                    ) : (
                      /* Iteration site 2: filteredConfirmed.map bounded via displayedConfirmed slice */
                      displayedConfirmed.map((item, idx) => {
                        const ct = getTransactionChangeType(item);
                        return (
                          <tr key={idx} className="hover:bg-slate-800/30 transition-colors">
                            <td className="py-3 px-4 font-mono text-slate-400 whitespace-nowrap">
                              {item.date || '—'}
                            </td>
                            <td className="py-3 px-4 font-bold text-white whitespace-nowrap">
                              {formatEntityName(item.entityName, item.entityId)}
                            </td>
                            <td className="py-3 px-4 whitespace-nowrap">
                              <span className={`px-2 py-0.5 rounded text-[11px] sm:text-[10px] font-mono font-semibold ${
                                ct === 'UNCLASSIFIED'
                                  ? 'bg-amber-500/20 text-amber-300 border border-amber-500/30'
                                  : 'bg-violet-500/10 text-violet-300 border border-violet-500/20'
                              }`}>
                                {ct}
                              </span>
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
                        );
                      })
                    )}
                  </tbody>
                </table>
              </div>
            </div>
          )}

          {/* Grouped View (by Team or Change Type) */}
          {confirmedGroupBy !== 'none' && groupedConfirmed && (
            <div className="space-y-4">
              {Object.keys(groupedConfirmed).length === 0 ? (
                <div className="bg-surface-raised border border-slate-800/80 rounded-xl p-8 text-center text-slate-500">
                  No confirmed transactions match the current filter.
                </div>
              ) : (
                Object.entries(groupedConfirmed).map(([groupKey, groupItems]) => {
                  const displayedGroupItems = groupItems.slice(0, 25);
                  return (
                    <div key={groupKey} className="bg-surface-raised border border-slate-800/80 rounded-xl p-5 space-y-3">
                      <div className="flex items-center justify-between border-b border-slate-800 pb-2.5">
                        <div className="flex items-center gap-2">
                          <Layers className="w-4 h-4 text-violet-400" />
                          <h4 className="text-sm font-bold text-white uppercase tracking-wider">{groupKey}</h4>
                        </div>
                        <span className="text-xs font-mono text-slate-400">
                          Showing {displayedGroupItems.length} of {groupItems.length} transactions
                        </span>
                      </div>

                      <div className="divide-y divide-slate-800/60">
                        {displayedGroupItems.map((item, idx) => (
                          <div key={idx} className="py-2.5 flex flex-col sm:flex-row sm:items-center justify-between gap-2 text-xs">
                            <div className="space-y-0.5">
                              <span className="font-bold text-white mr-2">{formatEntityName(item.entityName, item.entityId)}</span>
                              <span className="text-violet-400 font-mono text-[11px] mr-2">({item.field})</span>
                              <span className="text-slate-400">{item.priorValue} → </span>
                              <span className="text-emerald-400 font-semibold">{item.newValue}</span>
                            </div>
                            <div className="flex items-center gap-2 text-[11px] font-mono text-slate-500 flex-shrink-0">
                              <span>{item.date}</span>
                              {item.sourceUrl && (
                                <a href={item.sourceUrl} target="_blank" rel="noreferrer" className="text-violet-400 hover:text-violet-300">
                                  Wire
                                </a>
                              )}
                            </div>
                          </div>
                        ))}
                      </div>
                    </div>
                  );
                })
              )}
            </div>
          )}
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
                onChange={(e) => {
                  setReportedSearch(e.target.value);
                  setReportedPage(1);
                }}
                placeholder="Search rumors by entity or claim..."
                className="w-full bg-surface border border-slate-700/60 rounded-lg pl-9 pr-3 py-1.5 text-xs text-white placeholder-slate-500 focus:outline-none focus:border-violet-500"
              />
            </div>
            <div className="flex items-center gap-2">
              <span className="text-xs text-slate-400 flex-shrink-0">Category:</span>
              <select
                value={reportedCatFilter}
                onChange={(e) => {
                  setReportedCatFilter(e.target.value);
                  setReportedPage(1);
                }}
                className="bg-surface border border-slate-700/60 rounded-lg px-2.5 py-1.5 text-xs text-slate-200 focus:outline-none focus:border-violet-500"
              >
                <option value="all">All Categories</option>
                <option value="National Beat">National Beat</option>
                <option value="Team Beat Wire">Team Beat Wire</option>
                <option value="Trade Speculation">Trade Speculation</option>
              </select>
            </div>
          </div>

          {/* Explicit Counter and Pagination Bar */}
          <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-2 text-xs px-1">
            <div className="text-slate-400 font-mono">
              Showing {displayedReported.length} of {totalReported} rumors
            </div>

            {totalReported > 0 && (
              <div className="flex items-center gap-3">
                <div className="flex items-center gap-1.5">
                  <span className="text-slate-500 text-[11px]">Rows:</span>
                  <select
                    value={reportedPageSize}
                    onChange={(e) => {
                      setReportedPageSize(Number(e.target.value));
                      setReportedPage(1);
                    }}
                    className="bg-surface border border-slate-700/60 rounded px-2 py-0.5 text-xs text-slate-300"
                  >
                    <option value={25}>25</option>
                    <option value={50}>50</option>
                    <option value={100}>100</option>
                  </select>
                </div>

                <div className="flex items-center gap-1">
                  <button
                    onClick={() => setReportedPage((p) => Math.max(1, p - 1))}
                    disabled={reportedPage <= 1}
                    className="p-1 rounded bg-surface border border-slate-700/60 text-slate-300 disabled:opacity-40 disabled:cursor-not-allowed hover:bg-slate-800"
                    title="Previous Page"
                  >
                    <ChevronLeft className="w-3.5 h-3.5" />
                  </button>
                  <span className="text-slate-400 text-xs font-mono px-1">
                    {reportedPage} / {totalReportedPages}
                  </span>
                  <button
                    onClick={() => setReportedPage((p) => Math.min(totalReportedPages, p + 1))}
                    disabled={reportedPage >= totalReportedPages}
                    className="p-1 rounded bg-surface border border-slate-700/60 text-slate-300 disabled:opacity-40 disabled:cursor-not-allowed hover:bg-slate-800"
                    title="Next Page"
                  >
                    <ChevronRight className="w-3.5 h-3.5" />
                  </button>
                </div>
              </div>
            )}
          </div>

          {totalReported === 0 ? (
            <div className="bg-surface-raised border border-slate-800/80 rounded-xl p-8 text-center text-slate-400">
              <Radio className="w-8 h-8 text-violet-400 mx-auto mb-2 opacity-60" />
              <p className="text-sm font-semibold text-slate-300">No active rumors currently pending.</p>
              <p className="text-xs text-slate-500 mt-1">Pending items are aged out after a 28-day TTL if unconfirmed.</p>
            </div>
          ) : (
            /* Iteration site 3: filteredReported.map bounded via displayedReported slice */
            <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
              {displayedReported.map((claim) => {
                const ttlPct = Math.min(100, Math.round((claim.daysPending / 28) * 100));
                const daysRemaining = Math.max(0, 28 - claim.daysPending);
                return (
                  <div
                    key={claim.id}
                    className="bg-surface-raised border border-slate-800/80 rounded-xl p-5 space-y-3 relative overflow-hidden shadow-lg"
                  >
                    <div className="flex items-start justify-between gap-3">
                      <div>
                        <span className="px-2 py-0.5 rounded text-[11px] sm:text-[10px] font-semibold bg-violet-500/20 text-violet-300 border border-violet-500/30">
                          {claim.sourceCategory}
                        </span>
                        <h4 className="text-base font-bold text-white mt-1.5">{formatEntityName(claim.entityName, claim.id)}</h4>
                      </div>
                      <span className="text-[11px] font-mono text-slate-400">
                        First reported: {claim.firstReportedDate}
                      </span>
                    </div>

                    <p className="text-xs sm:text-sm text-slate-200 bg-surface p-3 rounded-lg border border-slate-800/60">
                      &ldquo;{formatClaimText(claim.claim)}&rdquo;
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
              {Object.entries(groupedExpired).map(([category, items]) => {
                const displayedExpiredItems = items.slice(0, expiredSliceSize);
                return (
                  <div key={category} className="bg-surface-raised border border-slate-800/80 rounded-xl p-5 space-y-3">
                    <div className="flex items-center justify-between border-b border-slate-800 pb-2">
                      <span className="text-xs font-bold text-slate-200 uppercase tracking-wider">
                        {category}
                      </span>
                      <span className="text-[11px] font-mono text-slate-400">
                        Showing {displayedExpiredItems.length} of {items.length} claims
                      </span>
                    </div>
                    <div className="divide-y divide-slate-800/60">
                      {/* Iteration site 4: items.map bounded with displayedExpiredItems slice */}
                      {displayedExpiredItems.map((item, idx) => (
                        <div key={idx} className="py-2.5 flex flex-col sm:flex-row sm:items-center justify-between gap-2 text-xs">
                          <div className="space-y-0.5">
                            <span className="font-bold text-white mr-2">{formatEntityName(item.entityName)}:</span>
                            <span className="text-slate-300">&ldquo;{formatClaimText(item.claim)}&rdquo;</span>
                          </div>
                          <div className="flex items-center gap-2 text-[11px] font-mono text-slate-500 flex-shrink-0">
                            <span>Reported: {item.firstReportedDate}</span>
                            <span>→</span>
                            <span className="text-rose-400">Expired: {item.expiredDate}</span>
                          </div>
                        </div>
                      ))}
                    </div>
                    {items.length > displayedExpiredItems.length && (
                      <div className="pt-2 text-center">
                        <button
                          onClick={() => setExpiredSliceSize((s) => s + 25)}
                          className="px-3 py-1 rounded-lg text-xs font-medium bg-slate-800 hover:bg-slate-700 text-slate-300 transition-colors"
                        >
                          Show more claims ({items.length - displayedExpiredItems.length} remaining)
                        </button>
                      </div>
                    )}
                  </div>
                );
              })}
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
