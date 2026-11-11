'use client';

import React, { useState, useMemo } from 'react';
import { WnbaCbaLeagueOverview } from '@/lib/cbaTypes';
import {
  Coins,
  Search,
  Users,
  AlertTriangle,
} from 'lucide-react';

interface CapSheetClientProps {
  initialData: WnbaCbaLeagueOverview;
}

// NOTE (2026-11-02, WNBA_analytics#128): this component used to render a
// per-player, multi-year contract book and a hard-cap/roster-crunch gauge
// (via the now-deleted WnbaFranchiseCapTable and HardCapCrunchMeter
// components) for every franchise. Every number in that view -- individual
// player salaries, contract types, team payroll totals, cap space, the
// 11-vs-12 roster "crunch" tier, and 2027/2028 projections -- came from
// unseeded runif() draws in build_cba_cap_dataset.R with no real WNBA
// contract data behind it. Per the cross-repo synthetic-data audit's
// decision rule, those fields were removed end-to-end rather than seeded or
// labeled "synthetic" (see build_cba_cap_dataset.R's provenance comment for
// what was checked and why no real source exists). This page keeps only the
// real content that survives that removal: the fixed CBA structural
// constants and each franchise's real roster count / core-player
// designation, with an explicit notice that per-player salary and payroll
// data is not available.
export const CapSheetClient: React.FC<CapSheetClientProps> = ({ initialData }) => {
  const [search, setSearch] = useState('');
  const [selectedConf, setSelectedConf] = useState('ALL');

  const filteredTeams = useMemo(() => {
    return initialData.teams
      .filter((t) => {
        if (selectedConf !== 'ALL' && t.conference !== selectedConf) return false;
        if (search.trim()) {
          const q = search.toLowerCase();
          const matchName = t.teamName.toLowerCase().includes(q);
          const matchAbbr = t.teamAbbr.toLowerCase().includes(q);
          const matchCore = t.corePlayer.toLowerCase().includes(q);
          if (!matchName && !matchAbbr && !matchCore) return false;
        }
        return true;
      })
      .sort((a, b) => a.teamName.localeCompare(b.teamName));
  }, [initialData.teams, selectedConf, search]);

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
              CBA Structural Cap Reference
            </h1>
            <p className="text-sm text-slate-300 max-w-2xl">
              The WNBA operates under a strict hard salary cap, 90% salary floor, supermax
              designations, and rookie wage ladders. The constants below are the league&apos;s
              structural cap figures. Per-player salaries, team payroll, and the 11-vs-12 roster
              crunch are <strong>not shown</strong> -- see the notice below.
            </p>
          </div>

          <div className="grid grid-cols-2 sm:grid-cols-4 gap-2.5">
            <div className="px-3 py-2.5 rounded-xl bg-surface/80 border border-slate-800 text-center">
              <div className="text-[11px] sm:text-[10px] text-slate-400 uppercase font-semibold">Hard Cap</div>
              <div className="text-base font-black text-white font-mono">
                ${(initialData.hardSalaryCap * 1_000_000).toLocaleString()}
              </div>
            </div>
            <div className="px-3 py-2.5 rounded-xl bg-surface/80 border border-slate-800 text-center">
              <div className="text-[11px] sm:text-[10px] text-slate-400 uppercase font-semibold">Salary Floor (90%)</div>
              <div className="text-base font-black text-amber-400 font-mono">
                ${(initialData.capFloor * 1_000_000).toLocaleString()}
              </div>
            </div>
            <div className="px-3 py-2.5 rounded-xl bg-surface/80 border border-slate-800 text-center">
              <div className="text-[11px] sm:text-[10px] text-slate-400 uppercase font-semibold">Supermax</div>
              <div className="text-base font-black text-rose-400 font-mono">
                ${(initialData.supermaxSalary * 1_000_000).toLocaleString()}
              </div>
            </div>
            <div className="px-3 py-2.5 rounded-xl bg-surface/80 border border-slate-800 text-center">
              <div className="text-[11px] sm:text-[10px] text-slate-400 uppercase font-semibold">Rookie Min</div>
              <div className="text-base font-black text-sky-400 font-mono">
                ${(initialData.rookieMinSalary * 1_000_000).toLocaleString()}
              </div>
            </div>
          </div>
        </div>
      </div>

      {/* Honest unavailability notice */}
      <div className="p-4 rounded-xl border border-amber-800/60 bg-amber-950/20 flex items-start gap-3 text-sm text-amber-200">
        <AlertTriangle className="w-4 h-4 text-amber-400 shrink-0 mt-0.5" />
        <div>
          <p className="font-bold text-amber-100">
            Per-player salaries, team payroll, and roster-crunch status are not available.
          </p>
          <p className="text-xs text-amber-200/80 mt-1">
            This repo has no real source of WNBA individual player contract or salary data
            (checked: wehoop&apos;s box score/roster/standings endpoints and ESPN&apos;s public
            WNBA JSON feeds -- neither carries contract data). Rather than fabricate those
            figures, they have been removed. Only the real structural cap constants and each
            franchise&apos;s real roster size / core-player designation are shown below.
          </p>
        </div>
      </div>

      {/* Franchise Roster Facts */}
      <div className="space-y-3">
        <div className="p-3.5 bg-surface-raised/60 rounded-xl border border-slate-800 space-y-3">
          <div className="flex items-center gap-2">
            <div className="relative flex-1">
              <Search className="w-3.5 h-3.5 absolute left-3 top-3 text-slate-400" />
              <input
                type="text"
                placeholder="Search franchise or core player..."
                value={search}
                onChange={(e) => setSearch(e.target.value)}
                className="w-full pl-8 pr-3 py-1.5 bg-surface border border-slate-800 rounded-lg text-xs text-slate-100 placeholder-slate-500 focus:outline-none focus:border-amber-500"
              />
            </div>

            <select
              value={selectedConf}
              onChange={(e) => setSelectedConf(e.target.value)}
              className="bg-surface border border-slate-800 text-slate-200 text-xs rounded-lg px-2 py-1.5 focus:outline-none focus:border-amber-500 font-mono"
            >
              <option value="ALL">All Conf</option>
              <option value="East">East</option>
              <option value="West">West</option>
            </select>
          </div>

          <div className="text-[11px] text-slate-500 font-mono flex justify-between items-center px-1">
            <span>Showing {filteredTeams.length} of {initialData.teams.length} Franchises</span>
          </div>
        </div>

        <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-2.5">
          {filteredTeams.map((t) => (
            <div
              key={t.teamAbbr}
              className="p-3.5 rounded-xl border border-slate-800/80 bg-surface-raised/60"
            >
              <div className="flex items-center justify-between">
                <div className="flex items-center gap-2.5">
                  <div className="w-8 h-8 rounded-lg bg-surface border border-slate-800 flex items-center justify-center font-black font-mono text-sm text-white">
                    {t.teamAbbr}
                  </div>
                  <div>
                    <div className="text-sm font-bold text-white flex items-center gap-2">
                      {t.teamName}
                      <span className="text-[11px] sm:text-[10px] font-mono text-slate-500 font-normal">
                        ({t.conference})
                      </span>
                    </div>
                    <div className="text-[11px] text-slate-400">
                      Core: <strong className="text-amber-400">{t.corePlayer}</strong>
                    </div>
                  </div>
                </div>
                <span className="text-slate-400 flex items-center gap-1 font-bold text-xs font-mono">
                  <Users className="w-3 h-3 text-slate-400" />
                  {t.rosterCount}
                </span>
              </div>
            </div>
          ))}
        </div>
      </div>
    </div>
  );
};
