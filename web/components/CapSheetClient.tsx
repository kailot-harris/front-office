'use client';

import React, { useState, useMemo } from 'react';
import { WnbaCbaLeagueOverview } from '@/lib/cbaTypes';
import { HardCapCrunchMeter } from '@/components/HardCapCrunchMeter';
import { WnbaFranchiseCapTable } from '@/components/WnbaFranchiseCapTable';
import {
  Coins,
  Search,
  Users,
} from 'lucide-react';

interface CapSheetClientProps {
  initialData: WnbaCbaLeagueOverview;
}

export const CapSheetClient: React.FC<CapSheetClientProps> = ({ initialData }) => {
  const [search, setSearch] = useState('');
  const [selectedConf, setSelectedConf] = useState('ALL');
  const [selectedTier, setSelectedTier] = useState('ALL');
  const [selectedTeamAbbr, setSelectedTeamAbbr] = useState<string>(() => {
    return initialData.teams[0]?.teamAbbr || 'LV';
  });

  const filteredTeams = useMemo(() => {
    return initialData.teams
      .filter((t) => {
        if (selectedConf !== 'ALL' && t.conference !== selectedConf) return false;
        if (selectedTier !== 'ALL' && t.cbaTier !== selectedTier) return false;
        if (search.trim()) {
          const q = search.toLowerCase();
          const matchName = t.teamName.toLowerCase().includes(q);
          const matchAbbr = t.teamAbbr.toLowerCase().includes(q);
          const matchCore = t.corePlayer.toLowerCase().includes(q);
          if (!matchName && !matchAbbr && !matchCore) return false;
        }
        return true;
      })
      .sort((a, b) => b.totalPayroll2026 - a.totalPayroll2026);
  }, [initialData.teams, selectedConf, selectedTier, search]);

  const selectedTeam = useMemo(() => {
    return (
      initialData.teams.find((t) => t.teamAbbr === selectedTeamAbbr) ||
      filteredTeams[0] ||
      null
    );
  }, [initialData.teams, filteredTeams, selectedTeamAbbr]);

  const getTierBadge = (tier: string) => {
    switch (tier) {
      case 'Hard Cap Squeeze (11 Roster)':
        return 'bg-rose-500/10 text-rose-400 border-rose-500/30';
      case 'Cap Compliant (12 Roster)':
        return 'bg-emerald-500/10 text-emerald-400 border-emerald-500/30';
      case 'Flexible Cap Room':
        return 'bg-amber-500/10 text-amber-400 border-amber-500/30';
      default:
        return 'bg-sky-500/10 text-sky-400 border-sky-500/30';
    }
  };

  return (
    <div className="space-y-6">
      {/* Overview Banner */}
      <div className="p-6 rounded-2xl bg-gradient-to-r from-amber-950/40 via-slate-900 to-indigo-950/40 border border-amber-900/40 shadow-xl">
        <div className="flex flex-col md:flex-row items-start md:items-center justify-between gap-4">
          <div className="space-y-1.5">
            <div className="inline-flex items-center gap-2 px-3 py-1 rounded-full bg-amber-500/10 border border-amber-500/20 text-amber-400 text-xs font-semibold">
              <Coins className="w-3.5 h-3.5 text-amber-400" />
              WNBA CBA & Hard Salary Cap Sheet
            </div>
            <h1 className="text-2xl sm:text-3xl font-extrabold tracking-tight text-white">
              Hard Cap Architect & 11-vs-12 Roster Squeeze
            </h1>
            <p className="text-sm text-slate-300 max-w-2xl">
              Unlike the NBA&apos;s soft cap with luxury taxes and exceptions, the WNBA operates under a strict,
              unforgiving Hard Salary Cap ($1.520M). Franchises must navigate supermax designations, rookie wage ladders,
              and the agonizing choice between carrying an 11-woman or 12-woman roster.
            </p>
          </div>

          <div className="grid grid-cols-2 sm:grid-cols-4 gap-2.5">
            <div className="px-3 py-2.5 rounded-xl bg-surface/80 border border-slate-800 text-center">
              <div className="text-[10px] text-slate-400 uppercase font-semibold">Hard Cap</div>
              <div className="text-base font-black text-white font-mono">$1,520,000</div>
            </div>
            <div className="px-3 py-2.5 rounded-xl bg-surface/80 border border-slate-800 text-center">
              <div className="text-[10px] text-slate-400 uppercase font-semibold">Salary Floor (90%)</div>
              <div className="text-base font-black text-amber-400 font-mono">$1,368,000</div>
            </div>
            <div className="px-3 py-2.5 rounded-xl bg-surface/80 border border-slate-800 text-center">
              <div className="text-[10px] text-slate-400 uppercase font-semibold">Supermax Max</div>
              <div className="text-base font-black text-rose-400 font-mono">$249,244</div>
            </div>
            <div className="px-3 py-2.5 rounded-xl bg-surface/80 border border-slate-800 text-center">
              <div className="text-[10px] text-slate-400 uppercase font-semibold">11-Roster Squeeze</div>
              <div className="text-base font-black text-rose-400 font-mono">
                {initialData.hardCapSqueezeTeamCount} / 15
              </div>
            </div>
          </div>
        </div>
      </div>

      {/* Main Section: 15-Team Ledger (Left) & Inspector (Right) */}
      <div className="grid grid-cols-1 lg:grid-cols-12 gap-6">
        {/* Left Team Ledger (5 cols) */}
        <div className="lg:col-span-5 space-y-3">
          <div className="p-3.5 bg-surface-raised/60 rounded-xl border border-slate-800 space-y-3">
            <div className="flex items-center gap-2">
              <div className="relative flex-1">
                <Search className="w-3.5 h-3.5 absolute left-3 top-3 text-slate-400" />
                <input
                  type="text"
                  placeholder="Search franchise or core star..."
                  value={search}
                  onChange={(e) => setSearch(e.target.value)}
                  className="w-full pl-8 pr-3 py-1.5 bg-surface border border-slate-800 rounded-lg text-xs text-slate-100 placeholder-slate-500 focus:outline-none focus:border-amber-500"
                />
              </div>

              {/* Conference Filter */}
              <select
                value={selectedConf}
                onChange={(e) => setSelectedConf(e.target.value)}
                className="bg-surface border border-slate-800 text-slate-200 text-xs rounded-lg px-2 py-1.5 focus:outline-none focus:border-amber-500 font-mono"
              >
                <option value="ALL">All Conf</option>
                <option value="East">East</option>
                <option value="West">West</option>
              </select>

              {/* Tier Filter */}
              <select
                value={selectedTier}
                onChange={(e) => setSelectedTier(e.target.value)}
                className="bg-surface border border-slate-800 text-slate-200 text-xs rounded-lg px-2 py-1.5 focus:outline-none focus:border-amber-500 font-mono"
              >
                <option value="ALL">All Tiers</option>
                <option value="Hard Cap Squeeze (11 Roster)">11 Roster Squeeze</option>
                <option value="Cap Compliant (12 Roster)">12 Roster Compliant</option>
                <option value="Flexible Cap Room">Flexible Room</option>
                <option value="Maximum Cap Space">Max Cap Space</option>
              </select>
            </div>

            <div className="text-[11px] text-slate-500 font-mono flex justify-between items-center px-1">
              <span>Showing {filteredTeams.length} of 15 Franchises</span>
              <span>Sorted by Total Payroll</span>
            </div>
          </div>

          {/* Franchise Cards List */}
          <div className="space-y-2 max-h-[750px] overflow-y-auto pr-1">
            {filteredTeams.map((t) => {
              const isSelected = t.teamAbbr === selectedTeam?.teamAbbr;
              return (
                <div
                  key={t.teamAbbr}
                  onClick={() => setSelectedTeamAbbr(t.teamAbbr)}
                  className={`p-3.5 rounded-xl border transition-all cursor-pointer ${
                    isSelected
                      ? 'bg-amber-950/20 border-amber-500/50 shadow-md ring-1 ring-amber-500/30'
                      : 'bg-surface-raised/60 border-slate-800/80 hover:bg-slate-800/50'
                  }`}
                >
                  <div className="flex items-center justify-between">
                    <div className="flex items-center gap-2.5">
                      <div className="w-8 h-8 rounded-lg bg-surface border border-slate-800 flex items-center justify-center font-black font-mono text-sm text-white">
                        {t.teamAbbr}
                      </div>
                      <div>
                        <div className="text-sm font-bold text-white flex items-center gap-2">
                          {t.teamName}
                          <span className="text-[10px] font-mono text-slate-500 font-normal">
                            ({t.conference})
                          </span>
                        </div>
                        <div className="text-[11px] text-slate-400">
                          Core: <strong className="text-amber-400">{t.corePlayer}</strong>
                        </div>
                      </div>
                    </div>

                    <div className="text-right font-mono">
                      <div className="text-xs font-bold text-slate-100">
                        ${(t.totalPayroll2026 * 1000).toFixed(0)}k
                      </div>
                      <div className="text-[10px] text-indigo-400">
                        +${(t.capSpace2026 * 1000).toFixed(0)}k Room
                      </div>
                    </div>
                  </div>

                  <div className="flex items-center justify-between pt-2.5 mt-2 border-t border-slate-800/60 text-[10px] font-mono">
                    <span
                      className={`px-2 py-0.5 rounded-full font-bold border ${getTierBadge(
                        t.cbaTier
                      )}`}
                    >
                      {t.cbaTier}
                    </span>
                    <span className="text-slate-400 flex items-center gap-1 font-bold">
                      <Users className="w-3 h-3 text-slate-400" />
                      {t.rosterCount} Players
                    </span>
                  </div>
                </div>
              );
            })}
          </div>
        </div>

        {/* Right Inspector & Breakdown (7 cols) */}
        <div className="lg:col-span-7 space-y-4">
          {selectedTeam ? (
            <>
              {/* Franchise Title Banner */}
              <div className="p-4 rounded-xl bg-surface-raised/80 border border-slate-800 flex items-center justify-between">
                <div>
                  <div className="flex items-center gap-2">
                    <span className="text-xs font-mono font-bold px-2 py-0.5 rounded bg-slate-800 text-amber-400 border border-slate-700">
                      {selectedTeam.teamAbbr}
                    </span>
                    <h2 className="text-lg font-extrabold text-white">
                      {selectedTeam.teamName} Cap Architecture
                    </h2>
                  </div>
                  <p className="text-xs text-slate-400 mt-0.5">
                    2026 Hard Salary Cap ledger and 3-year financial allocations
                  </p>
                </div>

                <div className="text-right font-mono">
                  <div className="text-[10px] uppercase font-bold text-slate-400">Cap Space</div>
                  <div className="text-xl font-black text-indigo-400">
                    ${(selectedTeam.capSpace2026 * 1000).toFixed(0)}k
                  </div>
                </div>
              </div>

              {/* Hard Cap Gauge & Crunch Meter */}
              <HardCapCrunchMeter profile={selectedTeam} />

              {/* Multi-Year Contract Book */}
              <WnbaFranchiseCapTable profile={selectedTeam} />
            </>
          ) : (
            <div className="p-12 text-center text-slate-500 bg-surface-raised/40 rounded-xl border border-slate-800">
              Select a team to inspect its CBA cap sheet
            </div>
          )}
        </div>
      </div>
    </div>
  );
};
