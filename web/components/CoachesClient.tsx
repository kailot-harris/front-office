'use client';

import React, { useState, useMemo } from 'react';
import { CoachingStaffMetric } from '@/lib/coachingTypes';
import { TeamLogo } from '@/components/TeamLogo';
import { CoachRadarProfile } from '@/components/CoachRadarProfile';
import { AtoEfficiencyScatter } from '@/components/AtoEfficiencyScatter';
import { CoachImpactProfile } from '@/components/CoachImpactProfile';
import { SeasonSourceBadge } from '@/components/SeasonSourceBadge';
import { HowToReadDisclosure } from '@/components/HowToReadDisclosure';
import {
  Briefcase,
  Crosshair,
  Search,
  Award,
  Zap,
  TrendingUp,
  ChevronRight,
} from 'lucide-react';

interface CoachesClientProps {
  initialData: CoachingStaffMetric[];
}

export const CoachesClient: React.FC<CoachesClientProps> = ({ initialData }) => {
  const [activeTab, setActiveTab] = useState<'tierboard' | 'scatter' | 'profile'>('tierboard');
  const [searchTerm, setSearchTerm] = useState('');
  const [selectedCoach, setSelectedCoach] = useState<CoachingStaffMetric>(initialData[0] || null);

  // The ATO and challenge figures on this page fall back to the last completed
  // season because the 2026-2027 play-by-play sample is too small. Taken from
  // whichever cards actually carry observed data; absent entirely when unobserved.
  const observedSeasons = useMemo(() => {
    const spans = new Set<string>();
    initialData.forEach((c) => {
      const s = c.provenance?.observedSeasons;
      if (s) s.split('+').forEach((p) => spans.add(p.trim()));
    });
    return spans.size > 0 ? Array.from(spans).sort().join(' + ') : null;
  }, [initialData]);

  // Filtered teams
  const filteredCoaches = useMemo(() => {
    return initialData.filter((c) => {
      const q = searchTerm.toLowerCase();
      return (
        c.teamAbbr.toLowerCase().includes(q) ||
        c.teamName.toLowerCase().includes(q)
      );
    }).sort((a, b) => (b.metrics.coachImpactRating ?? -Infinity) - (a.metrics.coachImpactRating ?? -Infinity));
  }, [initialData, searchTerm]);

  // Top KPI metrics
  const topCirCoach = useMemo(() => {
    return [...initialData]
      .filter((c) => c.metrics.coachImpactRating !== null)
      .sort((a, b) => (b.metrics.coachImpactRating ?? -Infinity) - (a.metrics.coachImpactRating ?? -Infinity))[0];
  }, [initialData]);

  const topAtoCoach = useMemo(() => {
    return [...initialData]
      .filter((c) => c.metrics.atoOffensivePpp !== null)
      .sort((a, b) => (b.metrics.atoOffensivePpp ?? -Infinity) - (a.metrics.atoOffensivePpp ?? -Infinity))[0];
  }, [initialData]);

  const topDefAtoCoach = useMemo(() => {
    return [...initialData]
      .filter((c) => c.metrics.atoDefensivePppAllowed !== null)
      .sort((a, b) => (a.metrics.atoDefensivePppAllowed ?? Infinity) - (b.metrics.atoDefensivePppAllowed ?? Infinity))[0];
  }, [initialData]);

  const topChallengeCoach = useMemo(() => {
    return [...initialData]
      .filter((c) => c.metrics.challengeSuccessRate !== null)
      .sort((a, b) => (b.metrics.challengeSuccessRate ?? -Infinity) - (a.metrics.challengeSuccessRate ?? -Infinity))[0];
  }, [initialData]);

  return (
    <div className="space-y-6">
      {/* Top Header Banner */}
      <div className="bg-gradient-to-r from-slate-900 via-slate-900 to-indigo-950/70 border border-slate-800 rounded-2xl p-6 shadow-xl relative overflow-hidden">
        <div className="absolute right-0 top-0 bottom-0 w-96 bg-[radial-gradient(ellipse_at_top_right,_var(--tw-gradient-stops))] from-amber-500/10 via-indigo-500/5 to-transparent pointer-events-none" />
        
        <div className="flex flex-col md:flex-row md:items-center justify-between gap-4 relative z-10">
          <div>
            <div className="flex items-center gap-2.5">
              <div className="p-2.5 rounded-xl bg-gradient-to-tr from-amber-500 to-orange-600 text-white shadow-lg shadow-orange-500/20">
                <Briefcase className="w-6 h-6" />
              </div>
              <div>
                <div className="flex flex-wrap items-center gap-2">
                  <h1 className="text-xl sm:text-2xl font-extrabold text-white tracking-tight">
                    Coaching Staffs & Tactical Impact Panel
                  </h1>
                  <span className="px-2.5 py-0.5 rounded-full text-xs font-mono font-bold bg-amber-500/20 text-amber-300 border border-amber-500/30">
                    2026-2027 Projected Season
                  </span>
                  <SeasonSourceBadge
                    season={observedSeasons}
                    kind="fallback"
                    label="Fallback: ATO & challenges observed"
                    title={`After-timeout possessions and coach's challenges are counted from observed ${observedSeasons} play-by-play. The 2026-2027 sample is too small, so the page falls back to the last completed season.`}
                  />
                </div>
                <p className="text-xs sm:text-sm text-slate-400 mt-0.5">
                  Comparing ensemble and roster-talent win projections alongside independent tactical indicators. The gap between the two projections is a model residual, not a measured coaching effect.
                </p>
              </div>
            </div>
          </div>

          {/* Sub-tab Navigation */}
          <div role="tablist" aria-label="Active tab" className="flex items-center gap-1.5 p-1 bg-surface/80 border border-slate-800 rounded-xl overflow-x-auto self-start md:self-auto">
            <button role="tab" aria-selected={activeTab === 'tierboard'}
              onClick={() => setActiveTab('tierboard')}
              className={`px-3 py-1.5 rounded-lg text-xs font-semibold transition-all whitespace-nowrap flex items-center gap-1.5 ${
                activeTab === 'tierboard'
                  ? 'bg-accent-600 text-white shadow-md shadow-accent-600/30'
                  : 'text-slate-400 hover:text-white hover:bg-slate-800/60'
              }`}
            >
              <Award className="w-3.5 h-3.5" />
              Tier Board & Dossiers
            </button>
            <button role="tab" aria-selected={activeTab === 'scatter'}
              onClick={() => setActiveTab('scatter')}
              className={`px-3 py-1.5 rounded-lg text-xs font-semibold transition-all whitespace-nowrap flex items-center gap-1.5 ${
                activeTab === 'scatter'
                  ? 'bg-accent-600 text-white shadow-md shadow-accent-600/30'
                  : 'text-slate-400 hover:text-white hover:bg-slate-800/60'
              }`}
            >
              <Crosshair className="w-3.5 h-3.5" />
              ATO Tactical Matrix
            </button>
            <button role="tab" aria-selected={activeTab === 'profile'}
              onClick={() => setActiveTab('profile')}
              className={`px-3 py-1.5 rounded-lg text-xs font-semibold transition-all whitespace-nowrap flex items-center gap-1.5 ${
                activeTab === 'profile'
                  ? 'bg-accent-600 text-white shadow-md shadow-accent-600/30'
                  : 'text-slate-400 hover:text-white hover:bg-slate-800/60'
              }`}
            >
              <TrendingUp className="w-3.5 h-3.5" />
              Impact Profile
            </button>
          </div>
        </div>
      </div>

      <HowToReadDisclosure pageKey="coaches">
        The Coach Impact Rating compares a team&rsquo;s actual win total against a roster-talent
        baseline — the gap is a model residual attributed to coaching, not a directly measured
        effect. ATO (after-timeout) offensive and defensive marks show points per possession on
        plays drawn up out of a stoppage, alongside observed coach&rsquo;s challenge overturn rates.
      </HowToReadDisclosure>

      {/* Top 4 KPI Stat Badges */}
      <div className="grid grid-cols-2 lg:grid-cols-4 gap-3.5">
        <div className="p-3.5 rounded-xl bg-surface-raised/80 border border-slate-800 shadow-sm flex items-center gap-3">
          <div className="p-2.5 rounded-lg bg-emerald-500/10 text-emerald-400 flex-shrink-0">
            <Award className="w-5 h-5" />
          </div>
          <div className="min-w-0">
            <span className="text-[11px] text-slate-400 font-medium block truncate">#1 Coach Impact Rating</span>
            <div className="flex items-center gap-2 mt-0.5">
              <span className="font-bold text-white text-sm truncate">{topCirCoach?.teamName ?? '—'}</span>
              <span className="text-xs font-mono font-bold text-emerald-400">
                {topCirCoach?.metrics.coachImpactRating != null ? `${topCirCoach.metrics.coachImpactRating} CIR` : '—'}
              </span>
            </div>
            <span className="text-[11px] sm:text-[10px] text-slate-500 font-mono">{topCirCoach?.teamAbbr}</span>
          </div>
        </div>

        <div className="p-3.5 rounded-xl bg-surface-raised/80 border border-slate-800 shadow-sm flex items-center gap-3">
          <div className="p-2.5 rounded-lg bg-indigo-500/10 text-indigo-400 flex-shrink-0">
            <Crosshair className="w-5 h-5" />
          </div>
          <div className="min-w-0">
            <span className="text-[11px] text-slate-400 font-medium block truncate">Top Offensive ATO</span>
            <div className="flex items-center gap-2 mt-0.5">
              <span className="font-bold text-white text-sm truncate">{topAtoCoach?.teamName ?? '—'}</span>
              <span className="text-xs font-mono font-bold text-indigo-400">{topAtoCoach?.metrics.atoOffensivePpp} PPP</span>
            </div>
            <span className="text-[11px] sm:text-[10px] text-slate-500 font-mono">{topAtoCoach?.teamAbbr}</span>
          </div>
        </div>

        <div className="p-3.5 rounded-xl bg-surface-raised/80 border border-slate-800 shadow-sm flex items-center gap-3">
          <div className="p-2.5 rounded-lg bg-sky-500/10 text-sky-400 flex-shrink-0">
            <Zap className="w-5 h-5" />
          </div>
          <div className="min-w-0">
            <span className="text-[11px] text-slate-400 font-medium block truncate">Top Defensive ATO Stopper</span>
            <div className="flex items-center gap-2 mt-0.5">
              <span className="font-bold text-white text-sm truncate">{topDefAtoCoach?.teamName ?? '—'}</span>
              <span className="text-xs font-mono font-bold text-sky-400">{topDefAtoCoach?.metrics.atoDefensivePppAllowed} PPP</span>
            </div>
            <span className="text-[11px] sm:text-[10px] text-slate-500 font-mono">{topDefAtoCoach?.teamAbbr}</span>
          </div>
        </div>

        <div className="p-3.5 rounded-xl bg-surface-raised/80 border border-slate-800 shadow-sm flex items-center gap-3">
          <div className="p-2.5 rounded-lg bg-amber-500/10 text-amber-400 flex-shrink-0">
            <TrendingUp className="w-5 h-5" />
          </div>
          <div className="min-w-0">
            <span className="text-[11px] text-slate-400 font-medium block truncate">Challenge Overturn Leader</span>
            <div className="flex items-center gap-2 mt-0.5">
              <span className="font-bold text-white text-sm truncate">{topChallengeCoach?.teamName ?? '—'}</span>
              <span className="text-xs font-mono font-bold text-amber-400">
                {topChallengeCoach?.metrics.challengeSuccessRate != null
                  ? `${(topChallengeCoach.metrics.challengeSuccessRate * 100).toFixed(1)}%`
                  : '—'}
              </span>
            </div>
            <span className="text-[11px] sm:text-[10px] text-slate-500 font-mono">{topChallengeCoach?.teamAbbr}</span>
          </div>
        </div>
      </div>

      {/* Main Content Area Based on Active Tab */}
      {activeTab === 'tierboard' && (
        <div className="grid grid-cols-1 lg:grid-cols-12 gap-6">
          {/* Left Column: List of Teams (7 cols) */}
          <div className="lg:col-span-7 space-y-4">
            {/* Search Bar */}
            <div className="p-3 rounded-xl bg-surface-raised/80 border border-slate-800 flex flex-wrap items-center justify-between gap-3">
              <div className="relative flex-1 min-w-[200px]">
                <Search className="w-4 h-4 absolute left-3 top-1/2 -translate-y-1/2 text-slate-500" />
                <input
                  type="text"
                  placeholder="Filter by team..."
                  value={searchTerm}
                  onChange={(e) => setSearchTerm(e.target.value)}
                  className="w-full bg-surface border border-slate-800 rounded-lg pl-9 pr-3 py-1.5 text-xs text-white placeholder-slate-500 focus:outline-none focus:border-indigo-500"
                />
              </div>
            </div>

            {/* Coach Cards List */}
            <div className="space-y-2.5 max-h-[680px] overflow-y-auto pr-1" tabIndex={0} role="region" aria-label="Coach list">
              {filteredCoaches.map((c, idx) => {
                const isSelected = selectedCoach?.teamAbbr === c.teamAbbr;
                const cir = c.metrics.coachImpactRating;
                const netLift = c.metrics.coachingWinsAdded;

                return (
                  <div
                    key={c.teamAbbr}
                    onClick={() => setSelectedCoach(c)}
                    className={`p-3.5 rounded-xl border transition-all cursor-pointer flex items-center justify-between gap-3 ${
                      isSelected
                        ? 'bg-slate-850 border-amber-500/60 shadow-lg shadow-amber-500/10'
                        : 'bg-surface-raised/70 border-slate-800/80 hover:bg-slate-850 hover:border-slate-700'
                    }`}
                  >
                    <div className="flex items-center gap-3 min-w-0">
                      <span className="font-mono text-xs font-bold text-slate-500 w-5 text-right">
                        #{idx + 1}
                      </span>
                      <TeamLogo team={c.teamAbbr} size="sm" />
                      <div className="min-w-0">
                        <div className="flex items-center gap-2">
                          <h4 className="text-sm font-bold text-white tracking-tight truncate">
                            {c.teamName}
                          </h4>
                          <span className="text-[11px] sm:text-[10px] font-mono px-1.5 py-0.2 rounded bg-slate-800 text-slate-300 border border-slate-700">
                            {c.teamAbbr}
                          </span>
                        </div>
                      </div>
                    </div>

                    <div className="flex items-center gap-4 flex-shrink-0">
                      {/* Win Lift Badge */}
                      <div className="text-right hidden sm:block">
                        <span className="text-[11px] sm:text-[10px] text-slate-400 block font-sans">Marginal Lift</span>
                        <span
                          className={`text-xs font-mono font-bold ${
                            netLift >= 0 ? 'text-emerald-400' : 'text-rose-400'
                          }`}
                        >
                          {netLift >= 0 ? `+${netLift}` : netLift} W
                        </span>
                      </div>

                      {/* CIR Score Pill */}
                      <div className="text-right">
                        <span className="text-[11px] sm:text-[10px] text-slate-400 block font-sans">CIR</span>
                        <span className="text-sm font-mono font-extrabold text-amber-400">
                          {cir !== null ? cir.toFixed(1) : '—'}
                        </span>
                      </div>

                      <ChevronRight
                        className={`w-4 h-4 transition-transform ${
                          isSelected ? 'text-amber-400 translate-x-0.5' : 'text-slate-500'
                        }`}
                      />
                    </div>
                  </div>
                );
              })}
            </div>
          </div>

          {/* Right Column: Detailed Coach Dossier (5 cols) */}
          <div className="lg:col-span-5">
            {selectedCoach && (
              <div className="bg-surface-raised/90 border border-slate-800 rounded-xl p-5 shadow-xl space-y-5 sticky top-20">
                {/* Dossier Header */}
                <div className="flex items-center justify-between pb-4 border-b border-slate-800">
                  <div className="flex items-center gap-3">
                    <TeamLogo team={selectedCoach.teamAbbr} size="lg" />
                    <div>
                      <h3 className="text-base font-extrabold text-white tracking-tight">
                        {selectedCoach.teamName}
                      </h3>
                      <div className="text-xs text-slate-400 mt-0.5 font-mono">
                        {selectedCoach.teamAbbr}
                      </div>
                    </div>
                  </div>

                  <div className="text-right">
                    <span className="text-[11px] sm:text-[10px] text-slate-400 uppercase tracking-wider block font-bold">
                      Impact Rating
                    </span>
                    <span className="text-xl font-mono font-extrabold text-amber-400">
                      {selectedCoach.metrics.coachImpactRating ?? '—'}
                    </span>
                  </div>
                </div>

                {/* 5-Dimensional Radar Chart */}
                <div>
                  <div className="text-xs font-bold text-slate-300 mb-2 flex items-center justify-between">
                    <span>Tactical & Skill Percentiles</span>
                    <span className="text-[11px] sm:text-[10px] font-mono text-slate-500">League Normalized</span>
                  </div>
                  <CoachRadarProfile
                    percentiles={selectedCoach.radarPercentiles}
                    coachName={selectedCoach.teamName}
                    size={260}
                  />
                </div>
              </div>
            )}
          </div>
        </div>
      )}

      {/* ATO Scatter Plot Tab */}
      {activeTab === 'scatter' && (
        <AtoEfficiencyScatter
          coaches={initialData}
          selectedCoach={selectedCoach}
          onSelectCoach={(c) => setSelectedCoach(c)}
        />
      )}

      {/* Coaching Impact Profile Tab */}
      {activeTab === 'profile' && selectedCoach && (
        <div className="space-y-4">
          <CoachImpactProfile coach={selectedCoach} />

          {/* Quick switcher to other top coaches */}
          <div className="p-4 rounded-xl bg-surface-raised/60 border border-slate-800">
            <span className="text-xs font-bold text-slate-300 block mb-2">
              Inspect Impact Profile for Other Coaches:
            </span>
            <div className="flex flex-wrap gap-2">
              {initialData.slice(0, 10).map((c) => (
                <button
                  key={c.teamAbbr}
                  onClick={() => setSelectedCoach(c)}
                  className={`px-2.5 py-1 rounded-lg text-xs font-medium border flex items-center gap-1.5 transition-all ${
                    selectedCoach.teamAbbr === c.teamAbbr
                      ? 'bg-amber-500/20 text-amber-300 border-amber-500/40'
                      : 'bg-surface text-slate-400 border-slate-800 hover:text-white'
                  }`}
                >
                  <TeamLogo team={c.teamAbbr} size="xs" />
                  <span>{c.teamName}</span>
                </button>
              ))}
            </div>
          </div>
        </div>
      )}
    </div>
  );
};
