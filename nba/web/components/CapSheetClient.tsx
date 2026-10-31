'use client';

import React, { useState, useMemo } from 'react';
import { CbaLeagueOverview, FranchiseCbaProfile } from '@/lib/cbaTypes';
import { SeasonSourceBadge } from '@/components/SeasonSourceBadge';
import { SEASON_SOURCES } from '@/lib/season';
import { TeamLogo } from '@/components/TeamLogo';
import { ApronThermometer } from '@/components/ApronThermometer';
import { TradeCbaValidator } from '@/components/TradeCbaValidator';
import { FranchiseCapTable } from '@/components/FranchiseCapTable';
import {
  Coins,
  ShieldAlert,
  Search,
  CheckCircle2,
  Lock,
  DollarSign,
  ChevronRight,
  Flame,
} from 'lucide-react';

interface CapSheetClientProps {
  initialData: CbaLeagueOverview;
}

export const CapSheetClient: React.FC<CapSheetClientProps> = ({ initialData }) => {
  const [searchTerm, setSearchTerm] = useState('');
  const [selectedTier, setSelectedTier] = useState<string>('All');
  const [selectedTeam, setSelectedTeam] = useState<FranchiseCbaProfile>(initialData.teams[0] || null);
  const [viewMode, setViewMode] = useState<'roster' | 'multiyear'>('roster');

  const tiers = [
    'All',
    'Second Apron Restricted',
    'First Apron Team',
    'Taxpayer (Below Apron 1)',
    'Over Cap (Non-Taxpayer)',
    'Under Cap Room',
  ];

  const filteredTeams = useMemo(() => {
    return initialData.teams
      .filter((t) => {
        const matchesSearch =
          t.teamName.toLowerCase().includes(searchTerm.toLowerCase()) ||
          t.teamAbbr.toLowerCase().includes(searchTerm.toLowerCase());
        const matchesTier = selectedTier === 'All' || t.cbaTier === selectedTier;
        return matchesSearch && matchesTier;
      })
      .sort((a, b) => b.totalPayroll2026 - a.totalPayroll2026);
  }, [initialData.teams, searchTerm, selectedTier]);

  const topTaxTeam = useMemo(() => {
    return [...initialData.teams].sort((a, b) => b.luxuryTaxBill - a.luxuryTaxBill)[0];
  }, [initialData.teams]);

  const getTierBadge = (tier: string) => {
    switch (tier) {
      case 'Second Apron Restricted':
        return 'bg-rose-500/10 text-rose-400 border-rose-500/30';
      case 'First Apron Team':
        return 'bg-orange-500/10 text-orange-400 border-orange-500/30';
      case 'Taxpayer (Below Apron 1)':
        return 'bg-amber-500/10 text-amber-400 border-amber-500/30';
      case 'Over Cap (Non-Taxpayer)':
        return 'bg-indigo-500/10 text-indigo-400 border-indigo-500/30';
      default:
        return 'bg-emerald-500/10 text-emerald-400 border-emerald-500/30';
    }
  };

  return (
    <div className="space-y-6">
      {/* Top Banner */}
      <div className="bg-surface-raised border border-slate-800 rounded-2xl p-6 shadow-xl relative overflow-hidden">
        <div className="flex flex-col md:flex-row md:items-center justify-between gap-4 relative z-10">
          <div>
            <div className="flex items-center gap-2.5">
              <div className="p-2.5 rounded-xl bg-orange-500/10 text-orange-400 border border-orange-500/20 shadow-sm">
                <Coins className="w-6 h-6" />
              </div>
              <div>
                <div className="flex items-center gap-2">
                  <h1 className="text-xl sm:text-2xl font-extrabold text-white tracking-tight">
                    <span className="text-orange-400">NBA</span> CBA Salary Cap, Apron & Luxury Tax Architect
                  </h1>
                  <SeasonSourceBadge
                    season={initialData.season}
                    kind="projection"
                    label="League year"
                    title={SEASON_SOURCES.capSheet.note}
                  />
                </div>
                <p className="text-xs sm:text-sm text-slate-400 mt-0.5">
                  Regulatory modeling of the {initialData.season} NBA salary cap (${initialData.salaryCap}M), luxury tax brackets, repeater surcharges, and second apron trade handcuffs.
                </p>
              </div>
            </div>
          </div>

          <div className="flex items-center gap-2 text-xs font-mono">
            <span className="px-3 py-1.5 rounded-lg bg-surface/80 border border-slate-800 text-slate-300">
              Cap: ${initialData.salaryCap}M • Tax: ${initialData.luxuryTaxThreshold}M
            </span>
            <span className="px-3 py-1.5 rounded-lg bg-rose-500/10 border border-rose-500/30 text-rose-400 font-bold">
              2nd Apron: ${initialData.secondApron}M
            </span>
          </div>
        </div>
        <div className="w-full h-[2px] bg-gradient-to-r from-orange-400 via-orange-500/40 to-transparent mt-4" />
      </div>

      {/* KPI Cards */}
      <div className="grid grid-cols-2 lg:grid-cols-4 gap-3.5">
        <div className="p-3.5 rounded-xl bg-surface-raised/80 border border-slate-800 shadow-sm flex items-center gap-3">
          <div className="p-2.5 rounded-lg bg-amber-500/10 text-amber-400 flex-shrink-0">
            <DollarSign className="w-5 h-5" />
          </div>
          <div className="min-w-0">
            <span className="text-[11px] text-slate-400 font-medium block truncate">Total League Tax Revenue</span>
            <div className="flex items-baseline gap-1.5 mt-0.5">
              <span className="font-mono text-base font-bold text-white">${initialData.totalLeagueTaxRevenue}M</span>
              <span className="text-[10px] text-slate-500 font-mono">({initialData.taxTeamCount} teams)</span>
            </div>
            <span className="text-[10px] text-slate-500 font-mono">Avg Payroll: ${initialData.averagePayroll}M</span>
          </div>
        </div>

        <div className="p-3.5 rounded-xl bg-surface-raised/80 border border-slate-800 shadow-sm flex items-center gap-3">
          <div className="p-2.5 rounded-lg bg-rose-500/10 text-rose-400 flex-shrink-0">
            <ShieldAlert className="w-5 h-5" />
          </div>
          <div className="min-w-0">
            <span className="text-[11px] text-slate-400 font-medium block truncate">Second Apron Handcuffs</span>
            <div className="flex items-baseline gap-1.5 mt-0.5">
              <span className="font-mono text-base font-bold text-rose-400">{initialData.secondApronTeamCount} Franchises</span>
            </div>
            <span className="text-[10px] text-slate-500 font-mono">Frozen 7-yr picks & no aggregation</span>
          </div>
        </div>

        <div className="p-3.5 rounded-xl bg-surface-raised/80 border border-slate-800 shadow-sm flex items-center gap-3">
          <div className="p-2.5 rounded-lg bg-emerald-500/10 text-emerald-400 flex-shrink-0">
            <CheckCircle2 className="w-5 h-5" />
          </div>
          <div className="min-w-0">
            <span className="text-[11px] text-slate-400 font-medium block truncate">Cap Room Teams</span>
            <div className="flex items-baseline gap-1.5 mt-0.5">
              <span className="font-mono text-base font-bold text-emerald-400">{initialData.capRoomTeamCount} Franchises</span>
            </div>
            <span className="text-[10px] text-slate-500 font-mono">Sub-${initialData.salaryCap}M flexible payrolls</span>
          </div>
        </div>

        <div className="p-3.5 rounded-xl bg-surface-raised/80 border border-slate-800 shadow-sm flex items-center gap-3">
          <div className="p-2.5 rounded-lg bg-amber-500/10 text-amber-400 flex-shrink-0">
            <Flame className="w-5 h-5" />
          </div>
          <div className="min-w-0">
            <span className="text-[11px] text-slate-400 font-medium block truncate">Top Tax Bill: {topTaxTeam?.teamAbbr}</span>
            <div className="flex items-baseline gap-1.5 mt-0.5">
              <span className="font-mono text-base font-bold text-amber-400">${topTaxTeam?.luxuryTaxBill}M</span>
              <span className="text-[10px] text-slate-500 font-mono">Tax</span>
            </div>
            <span className="text-[10px] text-slate-500 font-mono">Total: ${topTaxTeam?.totalFinancialCommitment}M</span>
          </div>
        </div>
      </div>

      {/* Main Content Layout */}
      <div className="grid grid-cols-1 lg:grid-cols-12 gap-6">
        {/* Left Column: 30 Teams Ranking Table (6 cols) */}
        <div className="lg:col-span-6 space-y-3">
          {/* Search & Filter Toolbar */}
          <div className="p-3 rounded-xl bg-surface-raised/80 border border-slate-800 flex flex-wrap items-center justify-between gap-2">
            <div className="relative flex-1 min-w-[160px]">
              <Search className="w-4 h-4 absolute left-3 top-1/2 -translate-y-1/2 text-slate-500" />
              <input
                type="text"
                placeholder="Search team..."
                value={searchTerm}
                onChange={(e) => setSearchTerm(e.target.value)}
                className="w-full bg-surface border border-slate-800 rounded-lg pl-9 pr-3 py-1.5 text-xs text-white placeholder-slate-500 focus:outline-none focus:border-amber-500"
              />
            </div>

            <select
              value={selectedTier}
              onChange={(e) => setSelectedTier(e.target.value)}
              className="bg-surface border border-slate-800 rounded-lg px-2.5 py-1.5 text-xs text-slate-300 focus:outline-none focus:border-amber-500"
            >
              {tiers.map((t) => (
                <option key={t} value={t}>
                  {t}
                </option>
              ))}
            </select>
          </div>

          {/* Teams Table */}
          <div className="space-y-2 max-h-[720px] overflow-y-auto pr-1">
            {filteredTeams.map((t, idx) => {
              const isSelected = selectedTeam?.teamAbbr === t.teamAbbr;

              return (
                <div
                  key={t.teamAbbr}
                  onClick={() => setSelectedTeam(t)}
                  className={`p-3 rounded-xl border transition-all cursor-pointer flex items-center justify-between gap-3 ${
                    isSelected
                      ? 'bg-slate-850 border-amber-500/60 shadow-lg shadow-amber-500/10'
                      : 'bg-surface-raised/70 border-slate-800/80 hover:bg-slate-850 hover:border-slate-700'
                  }`}
                >
                  <div className="flex items-center gap-3 min-w-0">
                    <span className="font-mono text-xs font-bold text-slate-500 w-5 text-right">
                      #{idx + 1}
                    </span>
                    <TeamLogo team={t.teamAbbr} size="sm" />
                    <div className="min-w-0">
                      <div className="flex items-center gap-2">
                        <span className="font-bold text-white text-xs truncate">
                          {t.teamName}
                        </span>
                        <span className="font-mono text-[10px] text-slate-400">
                          {t.teamAbbr}
                        </span>
                      </div>
                      <span
                        className={`text-[9px] font-mono px-1.5 py-0.2 rounded border font-semibold inline-block mt-0.5 ${getTierBadge(
                          t.cbaTier
                        )}`}
                      >
                        {t.cbaTier}
                      </span>
                    </div>
                  </div>

                  <div className="flex items-center gap-4 flex-shrink-0 text-right font-mono">
                    <div>
                      <span className="text-[10px] text-slate-400 block font-sans">Payroll</span>
                      <span className="text-xs font-bold text-white">
                        ${t.totalPayroll2026.toFixed(1)}M
                      </span>
                    </div>

                    <div className="min-w-[60px]">
                      <span className="text-[10px] text-slate-400 block font-sans">Tax Bill</span>
                      <span
                        className={`text-xs font-bold ${
                          t.luxuryTaxBill > 0 ? 'text-amber-400' : 'text-slate-600'
                        }`}
                      >
                        {t.luxuryTaxBill > 0 ? `$${t.luxuryTaxBill.toFixed(1)}M` : '$0.0M'}
                      </span>
                    </div>

                    <ChevronRight
                      className={`w-4 h-4 transition-transform ${
                        isSelected ? 'text-amber-400 translate-x-0.5' : 'text-slate-600'
                      }`}
                    />
                  </div>
                </div>
              );
            })}
          </div>
        </div>

        {/* Right Column: Selected Franchise Deep Dive (6 cols) */}
        <div className="lg:col-span-6 space-y-4">
          {selectedTeam && (
            <div className="space-y-4 sticky top-20">
              {/* Franchise Dossier Header */}
              <div className="p-4 rounded-xl bg-surface-raised/90 border border-slate-800 shadow-xl flex items-center justify-between gap-3">
                <div className="flex items-center gap-3">
                  <TeamLogo team={selectedTeam.teamAbbr} size="lg" />
                  <div>
                    <h3 className="text-base font-extrabold text-white tracking-tight flex items-center gap-2">
                      <span>{selectedTeam.teamName} Financial Dossier</span>
                      {selectedTeam.isRepeaterTax && (
                        <span className="text-[9px] font-mono px-1.5 py-0.2 rounded bg-amber-500/20 text-amber-300 border border-amber-500/40 font-bold">
                          REPEATER
                        </span>
                      )}
                    </h3>
                    <div className="text-xs text-slate-400 mt-0.5">
                      Total Commitment: <span className="font-mono text-amber-400 font-bold">${selectedTeam.totalFinancialCommitment.toFixed(1)}M</span> (Payroll + Tax)
                    </div>
                  </div>
                </div>

                <div className="flex items-center gap-1.5 bg-surface p-1 rounded-lg border border-slate-800 text-xs">
                  <button
                    onClick={() => setViewMode('roster')}
                    className={`px-2.5 py-1 rounded font-medium transition-all ${
                      viewMode === 'roster'
                        ? 'bg-accent-600 text-white font-bold'
                        : 'text-slate-400 hover:text-white'
                    }`}
                  >
                    Roster
                  </button>
                  <button
                    onClick={() => setViewMode('multiyear')}
                    className={`px-2.5 py-1 rounded font-medium transition-all ${
                      viewMode === 'multiyear'
                        ? 'bg-accent-600 text-white font-bold'
                        : 'text-slate-400 hover:text-white'
                    }`}
                  >
                    Trade Machine
                  </button>
                </div>
              </div>

              {/* Apron Thermometer Gauge */}
              <ApronThermometer profile={selectedTeam} />

              {/* Active CBA Handcuffs Checklist */}
              <div className="p-4 rounded-xl bg-surface/70 border border-slate-800 space-y-2.5">
                <span className="text-xs font-bold text-white block">
                  CBA Regulatory Restrictions & Handcuffs:
                </span>
                <div className="grid grid-cols-2 gap-2 text-xs">
                  <div className="flex items-center gap-2 p-2 rounded bg-surface-raised/60 border border-slate-800/80">
                    <Lock
                      className={`w-3.5 h-3.5 ${
                        selectedTeam.handcuffs.frozenPick7Years ? 'text-rose-400' : 'text-slate-600'
                      }`}
                    />
                    <span
                      className={
                        selectedTeam.handcuffs.frozenPick7Years ? 'text-rose-300 font-medium' : 'text-slate-500'
                      }
                    >
                      Frozen 7-Yr Pick
                    </span>
                  </div>

                  <div className="flex items-center gap-2 p-2 rounded bg-surface-raised/60 border border-slate-800/80">
                    <Lock
                      className={`w-3.5 h-3.5 ${
                        selectedTeam.handcuffs.noSalaryAggregation ? 'text-rose-400' : 'text-slate-600'
                      }`}
                    />
                    <span
                      className={
                        selectedTeam.handcuffs.noSalaryAggregation ? 'text-rose-300 font-medium' : 'text-slate-500'
                      }
                    >
                      No Trade Aggregation
                    </span>
                  </div>

                  <div className="flex items-center gap-2 p-2 rounded bg-surface-raised/60 border border-slate-800/80">
                    <Lock
                      className={`w-3.5 h-3.5 ${
                        selectedTeam.handcuffs.noCashInTrades ? 'text-rose-400' : 'text-slate-600'
                      }`}
                    />
                    <span
                      className={
                        selectedTeam.handcuffs.noCashInTrades ? 'text-rose-300 font-medium' : 'text-slate-500'
                      }
                    >
                      No Cash in Trades
                    </span>
                  </div>

                  <div className="flex items-center gap-2 p-2 rounded bg-surface-raised/60 border border-slate-800/80">
                    <Lock
                      className={`w-3.5 h-3.5 ${
                        selectedTeam.handcuffs.noTpmle ? 'text-rose-400' : 'text-slate-600'
                      }`}
                    />
                    <span
                      className={
                        selectedTeam.handcuffs.noTpmle ? 'text-rose-300 font-medium' : 'text-slate-500'
                      }
                    >
                      Loss of Taxpayer MLE
                    </span>
                  </div>
                </div>
              </div>

              {/* View Mode: Roster Contracts vs Trade Validator */}
              {viewMode === 'roster' ? (
                <FranchiseCapTable profile={selectedTeam} />
              ) : (
                <TradeCbaValidator profile={selectedTeam} />
              )}
            </div>
          )}
        </div>
      </div>
    </div>
  );
};
