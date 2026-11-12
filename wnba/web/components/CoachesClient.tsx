'use client';

import React, { useState, useMemo } from 'react';
import { CoachingStaffMetric } from '@/lib/coachingTypes';
import { TeamLogo } from '@/components/TeamLogo';
import { CoachRadarProfile } from '@/components/CoachRadarProfile';
import { AtoEfficiencyScatter } from '@/components/AtoEfficiencyScatter';
import { CoachImpactWaterfall } from '@/components/CoachImpactWaterfall';
import { HowToRead } from '@/components/HowToRead';
import {
  Briefcase,
  Crosshair,
  Search,
  Award,
  TrendingUp,
  ChevronRight,
  ShieldCheck,
} from 'lucide-react';

interface CoachesClientProps {
  initialData: CoachingStaffMetric[];
}

export const CoachesClient: React.FC<CoachesClientProps> = ({ initialData }) => {
  const [activeTab, setActiveTab] = useState<'tierboard' | 'scatter' | 'waterfall'>('tierboard');
  const [searchTerm, setSearchTerm] = useState('');
  const [selectedCoach, setSelectedCoach] = useState<CoachingStaffMetric>(initialData[0] || null);

  // Filtered coaches
  const filteredCoaches = useMemo(() => {
    return initialData
      .filter((c) => {
        const matchesSearch =
          c.headCoach.name.toLowerCase().includes(searchTerm.toLowerCase()) ||
          c.teamAbbr.toLowerCase().includes(searchTerm.toLowerCase()) ||
          c.teamName.toLowerCase().includes(searchTerm.toLowerCase());

        return matchesSearch;
      })
      .sort((a, b) => b.metrics.coachImpactRating - a.metrics.coachImpactRating);
  }, [initialData, searchTerm]);

  // Top KPI metrics
  const topCirCoach = useMemo(() => {
    return [...initialData].sort((a, b) => b.metrics.coachImpactRating - a.metrics.coachImpactRating)[0];
  }, [initialData]);

  const topAtoCoach = useMemo(() => {
    return [...initialData].sort((a, b) => b.metrics.atoOffensivePpp - a.metrics.atoOffensivePpp)[0];
  }, [initialData]);

  const topWinsAddedCoach = useMemo(() => {
    return [...initialData].sort((a, b) => b.metrics.coachingWinsAdded - a.metrics.coachingWinsAdded)[0];
  }, [initialData]);

  return (
    <div className="space-y-8 animate-fade-in">
      {/* Hero Header */}
      <div className="relative overflow-hidden rounded-2xl bg-gradient-to-br from-slate-900 via-indigo-950/40 to-slate-900 border border-slate-800 p-6 sm:p-8 shadow-xl">
        <div className="absolute top-0 right-0 w-96 h-96 bg-indigo-500/10 rounded-full blur-3xl pointer-events-none" />
        <div className="relative z-10 flex flex-col md:flex-row md:items-center justify-between gap-6">
          <div className="space-y-2 max-w-2xl">
            <div className="inline-flex items-center gap-2">
              <span className="inline-flex items-center gap-2 px-3 py-1 rounded-full text-xs font-semibold bg-indigo-500/10 text-indigo-400 border border-indigo-500/20">
                <Briefcase className="w-3.5 h-3.5" />
                <span>WNBA Head Coaches & Tactical Impact</span>
              </span>
              <span className="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-bold bg-amber-500/10 text-amber-400 border border-amber-500/20">
                2026 Season
              </span>
            </div>
            <h1 className="text-3xl sm:text-4xl font-extrabold tracking-tight text-white">
              Head Coaches & Tactical Impact
            </h1>
            <p className="text-sm sm:text-base text-slate-300">
              Evaluate all 15 WNBA head coaches across After-Timeout (ATO) play-by-play
              efficiency, coach&apos;s challenge overturn rates, and marginal system win lift.
            </p>
            <div className="mt-2">
              <HowToRead pageKey="coaches">
                CIR (Coach Impact Rating) is a 0-100 composite score summarizing a coach&apos;s
                tactical value across ATO efficiency, timeout usage, and challenge success. Coaching
                Wins Added is that same impact translated into a marginal regular-season win total —
                how many more or fewer wins the system estimates this coach is worth versus a
                replacement-level staff. ATO Off/Def Poss is the offense&apos;s and defense&apos;s
                points per possession specifically on possessions immediately following a timeout.
              </HowToRead>
            </div>
          </div>

          <div className="grid grid-cols-3 gap-3 p-3 bg-surface-raised/80 rounded-xl border border-slate-800/80 backdrop-blur-sm self-start md:self-auto">
            <div className="text-center px-3">
              <div className="text-xl font-bold text-indigo-400">
                {topCirCoach?.metrics.coachImpactRating}
              </div>
              <div className="text-[11px] text-slate-400 uppercase font-semibold">Top CIR</div>
            </div>
            <div className="text-center px-3 border-x border-slate-800">
              <div className="text-xl font-bold text-emerald-400">
                +{topWinsAddedCoach?.metrics.coachingWinsAdded} W
              </div>
              <div className="text-[11px] text-slate-400 uppercase font-semibold">Max Lift</div>
            </div>
            <div className="text-center px-3">
              <div className="text-xl font-bold text-amber-400">
                {topAtoCoach?.metrics.atoOffensivePpp}
              </div>
              <div className="text-[11px] text-slate-400 uppercase font-semibold">Best ATO</div>
            </div>
          </div>
        </div>
      </div>

      {/* Tabs */}
      <div className="flex border-b border-slate-800 space-x-2 sm:space-x-4 overflow-x-auto pb-px">
        <button
          onClick={() => setActiveTab('tierboard')}
          className={`flex items-center gap-2 py-3 px-4 text-sm font-semibold border-b-2 transition-all whitespace-nowrap ${
            activeTab === 'tierboard'
              ? 'border-accent-600 bg-accent-600 text-white shadow-sm'
              : 'border-transparent text-slate-400 hover:text-slate-200 hover:border-slate-700'
          }`}
        >
          <Award className="w-4 h-4" />
          Coaching Tierboard (15 Head Coaches)
        </button>

        <button
          onClick={() => setActiveTab('scatter')}
          className={`flex items-center gap-2 py-3 px-4 text-sm font-semibold border-b-2 transition-all whitespace-nowrap ${
            activeTab === 'scatter'
              ? 'border-accent-600 bg-accent-600 text-white shadow-sm'
              : 'border-transparent text-slate-400 hover:text-slate-200 hover:border-slate-700'
          }`}
        >
          <Crosshair className="w-4 h-4" />
          ATO Tactical Scatter
        </button>

        <button
          onClick={() => setActiveTab('waterfall')}
          className={`flex items-center gap-2 py-3 px-4 text-sm font-semibold border-b-2 transition-all whitespace-nowrap ${
            activeTab === 'waterfall'
              ? 'border-accent-600 bg-accent-600 text-white shadow-sm'
              : 'border-transparent text-slate-400 hover:text-slate-200 hover:border-slate-700'
          }`}
        >
          <TrendingUp className="w-4 h-4" />
          Talent-to-Wins Bridge
        </button>
      </div>

      {/* TAB 1: TIERBOARD & PROFILES */}
      {activeTab === 'tierboard' && (
        <div className="space-y-6">
          {/* Controls Bar */}
          <div className="flex flex-col sm:flex-row gap-4 items-stretch sm:items-center justify-between bg-surface-raised/60 p-4 rounded-xl border border-slate-800">
            <div className="relative flex-1 max-w-md">
              <Search className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-slate-500" />
              <input
                type="text"
                placeholder="Search head coach or franchise..."
                value={searchTerm}
                onChange={(e) => setSearchTerm(e.target.value)}
                className="w-full pl-9 pr-4 py-2 bg-surface border border-slate-800 rounded-lg text-sm text-slate-200 placeholder-slate-500 focus:outline-none focus:border-indigo-500 transition-colors"
              />
            </div>

            <div className="flex items-center gap-2 text-xs text-slate-400 font-medium">
              <ShieldCheck className="w-4 h-4 text-emerald-400" />
              <span>PBP-Verified ATO & Challenge Metrics</span>
            </div>
          </div>

          <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
            {/* Coach List */}
            <div className="lg:col-span-2 space-y-3">
              {filteredCoaches.map((c) => {
                const isSelected = selectedCoach?.teamAbbr === c.teamAbbr;
                return (
                  <div
                    key={c.teamAbbr}
                    onClick={() => setSelectedCoach(c)}
                    className={`cursor-pointer border rounded-xl p-4 transition-all duration-200 ${
                      isSelected
                        ? 'bg-surface-raised/90 border-accent-500/50 shadow-lg shadow-accent-500/10'
                        : 'bg-surface-raised/40 border-slate-800/80 hover:border-slate-700'
                    }`}
                  >
                    <div className="flex items-center justify-between gap-4">
                      <div className="flex items-center gap-3">
                        <TeamLogo team={c.teamAbbr} size="md" />
                        <div>
                          <div className="flex items-center gap-2">
                            <h3 className="font-bold text-white text-base">{c.headCoach.name}</h3>
                            <span className="text-xs text-slate-400 font-mono font-bold">
                              {c.teamAbbr}
                            </span>
                          </div>
                          <p className="text-xs text-slate-400 truncate max-w-sm">
                            Since {c.headCoach.tenureStart} ({c.headCoach.tenureYears} yr
                            {c.headCoach.tenureYears === 1 ? '' : 's'}) • ATO Off:{' '}
                            {c.metrics.atoOffensivePpp.toFixed(3)} PPP (n=
                            {c.metrics.atoOffPossessions})
                          </p>
                        </div>
                      </div>

                      <div className="flex items-center gap-4 text-right">
                        <div>
                          <div className="text-[11px] text-slate-400">CIR Score</div>
                          <div className="text-base font-extrabold text-indigo-400">
                            {c.metrics.coachImpactRating}
                          </div>
                        </div>
                        <div className="border-l border-slate-800 pl-3">
                          <div className="text-[11px] text-slate-400">Wins Lift</div>
                          <div
                            className={`text-sm font-bold ${
                              c.metrics.coachingWinsAdded >= 0
                                ? 'text-emerald-400'
                                : 'text-rose-400'
                            }`}
                          >
                            {c.metrics.coachingWinsAdded >= 0
                              ? `+${c.metrics.coachingWinsAdded}`
                              : c.metrics.coachingWinsAdded}{' '}
                            W
                          </div>
                        </div>
                        <ChevronRight
                          className={`w-4 h-4 text-slate-500 transition-transform ${
                            isSelected ? 'text-accent-400 translate-x-0.5' : ''
                          }`}
                        />
                      </div>
                    </div>
                  </div>
                );
              })}
            </div>

            {/* Selected Coach Detailed Dossier */}
            {selectedCoach && (
              <div className="bg-surface-raised/60 border border-slate-800 rounded-xl p-5 space-y-6">
                <div className="flex items-center justify-between border-b border-slate-800 pb-4">
                  <div className="flex items-center gap-3">
                    <TeamLogo team={selectedCoach.teamAbbr} size="lg" />
                    <div>
                      <h2 className="text-lg font-extrabold text-white">
                        {selectedCoach.headCoach.name}
                      </h2>
                      <p className="text-xs text-slate-400">
                        {selectedCoach.teamName} • Appointed {selectedCoach.headCoach.tenureStart} (
                        {selectedCoach.headCoach.tenureYears} yrs)
                      </p>
                    </div>
                  </div>
                  <div className="text-right">
                    <span className="text-xs text-slate-400">Season:</span>
                    <div className="text-xs font-bold text-indigo-400">
                      {selectedCoach.headCoach.registrySeason}
                    </div>
                  </div>
                </div>

                {/* Radar Profile */}
                <CoachRadarProfile
                  percentiles={selectedCoach.radarPercentiles}
                  coachName={selectedCoach.headCoach.name}
                  size={260}
                />

                {/* PBP Sample & Registry Provenance Box */}
                <div className="p-3.5 bg-surface/60 rounded-lg border border-slate-800/80 space-y-2 text-xs">
                  <span className="text-[11px] sm:text-[10px] uppercase font-bold text-slate-400 block">
                    PBP Sample & Registry Provenance
                  </span>
                  <div className="grid grid-cols-2 gap-2 text-slate-300">
                    <div>
                      <span className="text-slate-500 block text-[11px] sm:text-[10px]">ATO Off / Def Poss</span>
                      <span className="font-semibold font-mono">
                        {selectedCoach.metrics.atoOffPossessions} /{' '}
                        {selectedCoach.metrics.atoDefPossessions}
                      </span>
                    </div>
                    <div>
                      <span className="text-slate-500 block text-[11px] sm:text-[10px]">Challenge Overturn</span>
                      <span className="font-semibold font-mono">
                        {(selectedCoach.metrics.challengeSuccessRate * 100).toFixed(1)}% (n=
                        {selectedCoach.metrics.challengeAttempts})
                      </span>
                    </div>
                  </div>
                  <div className="pt-1 border-t border-slate-800/60 text-[11px] sm:text-[10px] text-slate-400">
                    <div>Source: {selectedCoach.headCoach.sourceCitation}</div>
                    <div>Verified: {selectedCoach.headCoach.sourceVerifiedDate}</div>
                  </div>
                </div>
              </div>
            )}
          </div>
        </div>
      )}

      {/* TAB 2: ATO SCATTER */}
      {activeTab === 'scatter' && (
        <AtoEfficiencyScatter
          coaches={filteredCoaches}
          selectedCoach={selectedCoach}
          onSelectCoach={(c) => setSelectedCoach(c)}
        />
      )}

      {/* TAB 3: WATERFALL DECOMPOSITION */}
      {activeTab === 'waterfall' && selectedCoach && (
        <div className="space-y-6">
          <CoachImpactWaterfall coach={selectedCoach} />

          {/* Quick Selector Pills */}
          <div className="flex flex-wrap items-center gap-2 p-4 bg-surface-raised/40 rounded-xl border border-slate-800">
            <span className="text-xs text-slate-400 font-semibold mr-2">Select Head Coach:</span>
            {initialData.map((c) => (
              <button
                key={c.teamAbbr}
                onClick={() => setSelectedCoach(c)}
                className={`flex items-center gap-1.5 px-3 py-1.5 rounded-lg text-xs font-bold transition-all ${
                  selectedCoach.teamAbbr === c.teamAbbr
                    ? 'bg-accent-600 text-white shadow-md shadow-accent-600/30'
                    : 'bg-surface text-slate-300 border border-slate-800 hover:border-slate-700'
                }`}
              >
                <span>{c.teamAbbr}</span>
                <span className="text-[11px] sm:text-[10px] opacity-75">({c.headCoach.name.split(' ')[1]})</span>
              </button>
            ))}
          </div>
        </div>
      )}
    </div>
  );
};
