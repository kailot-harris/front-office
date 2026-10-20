'use client';

import React, { useState, useMemo } from 'react';
import {
  Coins,
  Building2,
} from 'lucide-react';
import { CbtLeagueOverview } from '@/lib/cbtTypes';
import { CbtThermometer } from '@/components/CbtThermometer';
import { FranchisePayrollTable } from '@/components/FranchisePayrollTable';
import { SurplusValueCalculator } from '@/components/SurplusValueCalculator';

interface CapSheetClientProps {
  overview: CbtLeagueOverview;
}

export const CapSheetClient: React.FC<CapSheetClientProps> = ({ overview }) => {
  const [selectedTeamAbbr, setSelectedTeamAbbr] = useState<string>('LAD');
  const [selectedTierFilter, setSelectedTierFilter] = useState<string>('ALL');
  const [leagueFilter, setLeagueFilter] = useState<'ALL' | 'AL' | 'NL'>('ALL');

  const selectedTeam = useMemo(() => {
    return (
      overview.teams.find((t) => t.teamAbbr === selectedTeamAbbr) ||
      overview.teams[0]
    );
  }, [overview.teams, selectedTeamAbbr]);

  // Aggregate stats
  const totalTaxPayingTeams = useMemo(() => {
    return overview.teams.filter((t) => t.payroll2026 > overview.baseThreshold).length;
  }, [overview.teams, overview.baseThreshold]);

  const filteredTeams = useMemo(() => {
    return overview.teams.filter((t) => {
      const matchesLeague = leagueFilter === 'ALL' || t.league === leagueFilter;
      const matchesTier =
        selectedTierFilter === 'ALL' ||
        (selectedTierFilter === 'OVER_CBT' && t.payroll2026 > overview.baseThreshold) ||
        (selectedTierFilter === 'UNDER_CBT' && t.payroll2026 <= overview.baseThreshold) ||
        (selectedTierFilter === 'REPEATER' && t.isRepeater);
      return matchesLeague && matchesTier;
    });
  }, [overview.teams, leagueFilter, selectedTierFilter, overview.baseThreshold]);

  return (
    <div className="space-y-6 max-w-7xl mx-auto pb-12">
      {/* Hero Header */}
      <div className="relative overflow-hidden rounded-2xl bg-gradient-to-br from-slate-900 via-slate-900 to-indigo-950/40 border border-slate-800 p-6 md:p-8 shadow-2xl">
        <div className="relative z-10 flex flex-col md:flex-row md:items-center justify-between gap-6">
          <div className="space-y-2">
            <div className="inline-flex items-center gap-2 px-3 py-1 rounded-full bg-amber-500/10 border border-amber-500/20 text-amber-400 text-xs font-semibold">
              <Coins className="w-3.5 h-3.5" />
              <span>MLB Competitive Balance Tax (CBT) & Salary Cap Architect</span>
            </div>
            <h1 className="text-2xl md:text-3xl font-extrabold text-white tracking-tight">
              Franchise Payrolls & Luxury Tax Surcharges
            </h1>
            <p className="text-slate-400 text-sm max-w-3xl leading-relaxed">
              Explore 2026–2028 multi-year payroll obligations across all 30 MLB clubs. Assess luxury tax liabilities, repeater surcharges, draft pick drop penalties, and contract surplus ROI under the 2022–2026 CBA thresholds ($244M base).
            </p>
          </div>

          {/* League Macro Metrics */}
          <div className="grid grid-cols-2 sm:grid-cols-3 gap-3 md:min-w-[340px]">
            <div className="bg-slate-950/70 border border-slate-800 rounded-xl p-3">
              <span className="text-[10px] text-slate-400 uppercase tracking-wider block">Base CBT Line</span>
              <span className="font-mono font-bold text-base text-white">${overview.baseThreshold}M</span>
              <span className="text-[10px] text-emerald-400 block mt-0.5">2026 Benchmark</span>
            </div>
            <div className="bg-slate-950/70 border border-slate-800 rounded-xl p-3">
              <span className="text-[10px] text-slate-400 uppercase tracking-wider block">Tax Payers</span>
              <span className="font-mono font-bold text-base text-amber-400">{totalTaxPayingTeams} / 30</span>
              <span className="text-[10px] text-slate-400 block mt-0.5">Clubs Above Base</span>
            </div>
            <div className="bg-slate-950/70 border border-slate-800 rounded-xl p-3 col-span-2 sm:col-span-1">
              <span className="text-[10px] text-slate-400 uppercase tracking-wider block">Total Tax Pool</span>
              <span className="font-mono font-bold text-base text-rose-400">${overview.totalLuxuryTaxCollected.toFixed(1)}M</span>
              <span className="text-[10px] text-slate-400 block mt-0.5">Est. Revenue Share</span>
            </div>
          </div>
        </div>
      </div>

      {/* Main Interactive Grid */}
      <div className="grid grid-cols-1 lg:grid-cols-12 gap-6">
        {/* Left Column: 30-Team Leaderboard Selector (5 Cols) */}
        <div className="lg:col-span-5 space-y-4">
          <div className="bg-slate-900/90 border border-slate-800 rounded-xl p-4 shadow-xl">
            {/* Filter Bar */}
            <div className="flex flex-col gap-3 pb-3 border-b border-slate-800">
              <div className="flex items-center justify-between">
                <span className="text-xs font-bold text-white uppercase tracking-wider flex items-center gap-1.5">
                  <Building2 className="w-3.5 h-3.5 text-sky-400" />
                  30-Team Payroll Ledger
                </span>
                <span className="text-xs font-mono text-slate-400">
                  {filteredTeams.length} Clubs
                </span>
              </div>

              {/* League & Tier Chips */}
              <div className="flex flex-wrap items-center gap-1.5">
                {(['ALL', 'AL', 'NL'] as const).map((lg) => (
                  <button
                    key={lg}
                    onClick={() => setLeagueFilter(lg)}
                    className={`px-2.5 py-1 text-xs font-semibold rounded-lg transition-colors ${
                      leagueFilter === lg
                        ? 'bg-emerald-600 text-white'
                        : 'bg-slate-950 text-slate-400 hover:text-white border border-slate-800'
                    }`}
                  >
                    {lg}
                  </button>
                ))}

                <div className="h-4 w-px bg-slate-800 mx-1" />

                {[
                  { id: 'ALL', label: 'All' },
                  { id: 'OVER_CBT', label: 'Tax Payers' },
                  { id: 'UNDER_CBT', label: 'Under Line' },
                  { id: 'REPEATER', label: 'Repeaters' },
                ].map((tier) => (
                  <button
                    key={tier.id}
                    onClick={() => setSelectedTierFilter(tier.id)}
                    className={`px-2 py-1 text-[11px] font-medium rounded-lg transition-colors ${
                      selectedTierFilter === tier.id
                        ? 'bg-amber-500/20 text-amber-300 border border-amber-500/40'
                        : 'bg-slate-950 text-slate-400 hover:text-white border border-slate-800'
                    }`}
                  >
                    {tier.label}
                  </button>
                ))}
              </div>
            </div>

            {/* Team Scroll List */}
            <div className="divide-y divide-slate-850 max-h-[640px] overflow-y-auto mt-2 pr-1 space-y-1">
              {filteredTeams.map((team, idx) => {
                const isSelected = team.teamAbbr === selectedTeam.teamAbbr;
                const isOver = team.payroll2026 > overview.baseThreshold;
                return (
                  <button
                    key={team.teamAbbr}
                    onClick={() => setSelectedTeamAbbr(team.teamAbbr)}
                    className={`w-full text-left p-3 rounded-lg transition-all flex items-center justify-between gap-3 ${
                      isSelected
                        ? 'bg-sky-950/60 border border-sky-500/40 shadow-md shadow-sky-500/10'
                        : 'hover:bg-slate-800/40 border border-transparent'
                    }`}
                  >
                    <div className="flex items-center gap-3 min-w-0">
                      <span className="font-mono text-xs text-slate-400 w-5 flex-shrink-0">
                        #{idx + 1}
                      </span>
                      <div className="min-w-0">
                        <div className="flex items-center gap-2">
                          <span className="font-bold text-white text-sm truncate">
                            {team.fullName}
                          </span>
                          <span className="font-mono text-[10.5px] px-1.5 py-0.2 rounded bg-slate-800 text-slate-300">
                            {team.teamAbbr}
                          </span>
                        </div>
                        <div className="flex items-center gap-2 text-[11px] text-slate-400 mt-0.5">
                          <span>{team.division}</span>
                          {team.isRepeater && (
                            <span className="text-[10px] text-amber-400 font-semibold">• Repeater</span>
                          )}
                        </div>
                      </div>
                    </div>

                    <div className="text-right flex-shrink-0">
                      <div className="font-mono font-bold text-sm text-white">
                        ${team.payroll2026.toFixed(1)}M
                      </div>
                      <div className="text-[11px] font-mono">
                        {isOver ? (
                          <span className="text-rose-400 font-semibold">
                            +${team.cbtTaxBill.toFixed(1)}M tax
                          </span>
                        ) : (
                          <span className="text-emerald-400 font-medium">
                            ${team.cbtSpace2026.toFixed(1)}M space
                          </span>
                        )}
                      </div>
                    </div>
                  </button>
                );
              })}
            </div>
          </div>
        </div>

        {/* Right Column: Selected Team Deep Dive & Tooling (7 Cols) */}
        <div className="lg:col-span-7 space-y-6">
          {/* Selected Team CBT Thermometer */}
          <CbtThermometer team={selectedTeam} />

          {/* Contract Architecture Table */}
          <FranchisePayrollTable
            contracts={selectedTeam.contracts}
            teamName={selectedTeam.fullName}
          />

          {/* Interactive Trade / Surplus Value Simulator */}
          <SurplusValueCalculator />
        </div>
      </div>
    </div>
  );
};
