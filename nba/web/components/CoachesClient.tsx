'use client';

import React, { useState, useMemo } from 'react';
import { CoachingStaffMetric } from '@/lib/coachingTypes';
import { TeamLogo } from '@/components/TeamLogo';
import { CoachRadarProfile } from '@/components/CoachRadarProfile';
import { AtoEfficiencyScatter } from '@/components/AtoEfficiencyScatter';
import { CoachImpactProfile } from '@/components/CoachImpactProfile';
import { SeasonSourceBadge } from '@/components/SeasonSourceBadge';
import {
  Briefcase,
  Crosshair,
  Search,
  Award,
  Zap,
  TrendingUp,
  GitBranch,
  ChevronRight,
} from 'lucide-react';

interface CoachesClientProps {
  initialData: CoachingStaffMetric[];
}

export const CoachesClient: React.FC<CoachesClientProps> = ({ initialData }) => {
  const [activeTab, setActiveTab] = useState<'tierboard' | 'scatter' | 'profile' | 'genealogy'>('tierboard');
  const [searchTerm, setSearchTerm] = useState('');
  const [selectedTree, setSelectedTree] = useState<string>('All');
  const [selectedCoach, setSelectedCoach] = useState<CoachingStaffMetric>(initialData[0] || null);

  // The ATO and challenge figures on this page fall back to the last completed
  // season because the 2026-2027 play-by-play sample is too small. Taken from
  // whichever cards actually carry observed data; absent entirely when every card
  // is a synthetic coach band.
  const observedSeasons = useMemo(() => {
    const spans = new Set<string>();
    initialData.forEach((c) => {
      const s = c.provenance?.observedSeasons;
      if (s) s.split('+').forEach((p) => spans.add(p.trim()));
    });
    return spans.size > 0 ? Array.from(spans).sort().join(' + ') : null;
  }, [initialData]);

  // Distinct coaching trees
  const coachingTrees = useMemo(() => {
    const trees = new Set<string>();
    initialData.forEach((c) => {
      if (c.headCoach.coachingTree) trees.add(c.headCoach.coachingTree);
    });
    return ['All', ...Array.from(trees).sort()];
  }, [initialData]);

  // Filtered coaches
  const filteredCoaches = useMemo(() => {
    return initialData.filter((c) => {
      const matchesSearch =
        c.headCoach.name.toLowerCase().includes(searchTerm.toLowerCase()) ||
        c.teamAbbr.toLowerCase().includes(searchTerm.toLowerCase()) ||
        c.teamName.toLowerCase().includes(searchTerm.toLowerCase()) ||
        c.assistants.associateHC.toLowerCase().includes(searchTerm.toLowerCase()) ||
        c.assistants.offensiveCoord.toLowerCase().includes(searchTerm.toLowerCase());

      const matchesTree = selectedTree === 'All' || c.headCoach.coachingTree === selectedTree;
      return matchesSearch && matchesTree;
    }).sort((a, b) => b.metrics.coachImpactRating - a.metrics.coachImpactRating);
  }, [initialData, searchTerm, selectedTree]);

  // Top KPI metrics
  const topCirCoach = useMemo(() => {
    return [...initialData].sort((a, b) => b.metrics.coachImpactRating - a.metrics.coachImpactRating)[0];
  }, [initialData]);

  const topAtoCoach = useMemo(() => {
    return [...initialData].sort((a, b) => b.metrics.atoOffensivePpp - a.metrics.atoOffensivePpp)[0];
  }, [initialData]);

  const topDefAtoCoach = useMemo(() => {
    return [...initialData].sort((a, b) => a.metrics.atoDefensivePppAllowed - b.metrics.atoDefensivePppAllowed)[0];
  }, [initialData]);

  const topChallengeCoach = useMemo(() => {
    return [...initialData].sort((a, b) => b.metrics.challengeSuccessRate - a.metrics.challengeSuccessRate)[0];
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
          <div className="flex items-center gap-1.5 p-1 bg-surface/80 border border-slate-800 rounded-xl overflow-x-auto self-start md:self-auto">
            <button
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
            <button
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
            <button
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
            <button
              onClick={() => setActiveTab('genealogy')}
              className={`px-3 py-1.5 rounded-lg text-xs font-semibold transition-all whitespace-nowrap flex items-center gap-1.5 ${
                activeTab === 'genealogy'
                  ? 'bg-accent-600 text-white shadow-md shadow-accent-600/30'
                  : 'text-slate-400 hover:text-white hover:bg-slate-800/60'
              }`}
            >
              <GitBranch className="w-3.5 h-3.5" />
              Coaching Trees
            </button>
          </div>
        </div>
      </div>

      {/* Top 4 KPI Stat Badges */}
      <div className="grid grid-cols-2 lg:grid-cols-4 gap-3.5">
        <div className="p-3.5 rounded-xl bg-surface-raised/80 border border-slate-800 shadow-sm flex items-center gap-3">
          <div className="p-2.5 rounded-lg bg-emerald-500/10 text-emerald-400 flex-shrink-0">
            <Award className="w-5 h-5" />
          </div>
          <div className="min-w-0">
            <span className="text-[11px] text-slate-400 font-medium block truncate">#1 Coach Impact Rating</span>
            <div className="flex items-center gap-2 mt-0.5">
              <span className="font-bold text-white text-sm truncate">{topCirCoach?.headCoach.name}</span>
              <span className="text-xs font-mono font-bold text-emerald-400">{topCirCoach?.metrics.coachImpactRating} CIR</span>
            </div>
            <span className="text-[10px] text-slate-500 font-mono">{topCirCoach?.teamAbbr} • {topCirCoach?.headCoach.coachingTree}</span>
          </div>
        </div>

        <div className="p-3.5 rounded-xl bg-surface-raised/80 border border-slate-800 shadow-sm flex items-center gap-3">
          <div className="p-2.5 rounded-lg bg-indigo-500/10 text-indigo-400 flex-shrink-0">
            <Crosshair className="w-5 h-5" />
          </div>
          <div className="min-w-0">
            <span className="text-[11px] text-slate-400 font-medium block truncate">Top Offensive ATO</span>
            <div className="flex items-center gap-2 mt-0.5">
              <span className="font-bold text-white text-sm truncate">{topAtoCoach?.headCoach.name}</span>
              <span className="text-xs font-mono font-bold text-indigo-400">{topAtoCoach?.metrics.atoOffensivePpp} PPP</span>
            </div>
            <span className="text-[10px] text-slate-500 font-mono">{topAtoCoach?.teamAbbr}</span>
          </div>
        </div>

        <div className="p-3.5 rounded-xl bg-surface-raised/80 border border-slate-800 shadow-sm flex items-center gap-3">
          <div className="p-2.5 rounded-lg bg-sky-500/10 text-sky-400 flex-shrink-0">
            <Zap className="w-5 h-5" />
          </div>
          <div className="min-w-0">
            <span className="text-[11px] text-slate-400 font-medium block truncate">Top Defensive ATO Stopper</span>
            <div className="flex items-center gap-2 mt-0.5">
              <span className="font-bold text-white text-sm truncate">{topDefAtoCoach?.headCoach.name}</span>
              <span className="text-xs font-mono font-bold text-sky-400">{topDefAtoCoach?.metrics.atoDefensivePppAllowed} PPP</span>
            </div>
            <span className="text-[10px] text-slate-500 font-mono">{topDefAtoCoach?.teamAbbr}</span>
          </div>
        </div>

        <div className="p-3.5 rounded-xl bg-surface-raised/80 border border-slate-800 shadow-sm flex items-center gap-3">
          <div className="p-2.5 rounded-lg bg-amber-500/10 text-amber-400 flex-shrink-0">
            <TrendingUp className="w-5 h-5" />
          </div>
          <div className="min-w-0">
            <span className="text-[11px] text-slate-400 font-medium block truncate">Challenge Overturn Leader</span>
            <div className="flex items-center gap-2 mt-0.5">
              <span className="font-bold text-white text-sm truncate">{topChallengeCoach?.headCoach.name}</span>
              <span className="text-xs font-mono font-bold text-amber-400">
                {(topChallengeCoach?.metrics.challengeSuccessRate * 100).toFixed(1)}%
              </span>
            </div>
            <span className="text-[10px] text-slate-500 font-mono">{topChallengeCoach?.teamAbbr}</span>
          </div>
        </div>
      </div>

      {/* Main Content Area Based on Active Tab */}
      {activeTab === 'tierboard' && (
        <div className="grid grid-cols-1 lg:grid-cols-12 gap-6">
          {/* Left Column: List of Coaches (7 cols) */}
          <div className="lg:col-span-7 space-y-4">
            {/* Search & Filter Bar */}
            <div className="p-3 rounded-xl bg-surface-raised/80 border border-slate-800 flex flex-wrap items-center justify-between gap-3">
              <div className="relative flex-1 min-w-[200px]">
                <Search className="w-4 h-4 absolute left-3 top-1/2 -translate-y-1/2 text-slate-500" />
                <input
                  type="text"
                  placeholder="Filter by coach, assistant, or team..."
                  value={searchTerm}
                  onChange={(e) => setSearchTerm(e.target.value)}
                  className="w-full bg-surface border border-slate-800 rounded-lg pl-9 pr-3 py-1.5 text-xs text-white placeholder-slate-500 focus:outline-none focus:border-indigo-500"
                />
              </div>

              {/* Coaching Tree Selector */}
              <div className="flex items-center gap-1.5">
                <span className="text-[11px] text-slate-400">Tree:</span>
                <select
                  value={selectedTree}
                  onChange={(e) => setSelectedTree(e.target.value)}
                  className="bg-surface border border-slate-800 rounded-lg px-2.5 py-1.5 text-xs text-slate-300 focus:outline-none focus:border-indigo-500"
                >
                  {coachingTrees.map((tree) => (
                    <option key={tree} value={tree}>
                      {tree}
                    </option>
                  ))}
                </select>
              </div>
            </div>

            {/* Coach Cards List */}
            <div className="space-y-2.5 max-h-[680px] overflow-y-auto pr-1">
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
                            {c.headCoach.name}
                          </h4>
                          <span className="text-[10px] font-mono px-1.5 py-0.2 rounded bg-slate-800 text-slate-300 border border-slate-700">
                            {c.teamAbbr}
                          </span>
                        </div>
                        <div className="text-[11px] text-slate-400 truncate mt-0.5">
                          {c.headCoach.tacticalArchetype}
                        </div>
                      </div>
                    </div>

                    <div className="flex items-center gap-4 flex-shrink-0">
                      {/* Win Lift Badge */}
                      <div className="text-right hidden sm:block">
                        <span className="text-[10px] text-slate-400 block font-sans">Marginal Lift</span>
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
                        <span className="text-[10px] text-slate-400 block font-sans">CIR</span>
                        <span className="text-sm font-mono font-extrabold text-amber-400">
                          {cir.toFixed(1)}
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
                        {selectedCoach.headCoach.name}
                      </h3>
                      <div className="text-xs text-slate-400 mt-0.5">
                        {selectedCoach.teamName} • {selectedCoach.headCoach.tenureYears} yrs tenure • {selectedCoach.headCoach.careerGames} G
                      </div>
                    </div>
                  </div>

                  <div className="text-right">
                    <span className="text-[10px] text-slate-400 uppercase tracking-wider block font-bold">
                      Impact Rating
                    </span>
                    <span className="text-xl font-mono font-extrabold text-amber-400">
                      {selectedCoach.metrics.coachImpactRating}
                    </span>
                  </div>
                </div>

                {/* Tactical Archetype Badge */}
                <div className="p-2.5 rounded-lg bg-indigo-950/40 border border-indigo-500/20 text-xs text-indigo-300">
                  <span className="font-semibold text-white">System Identity: </span>
                  {selectedCoach.headCoach.tacticalArchetype}
                </div>

                {/* 5-Dimensional Radar Chart */}
                <div>
                  <div className="text-xs font-bold text-slate-300 mb-2 flex items-center justify-between">
                    <span>Tactical & Skill Percentiles</span>
                    <span className="text-[10px] font-mono text-slate-500">League Normalized</span>
                  </div>
                  <CoachRadarProfile
                    percentiles={selectedCoach.radarPercentiles}
                    coachName={selectedCoach.headCoach.name}
                    size={260}
                  />
                </div>

                {/* Coaching Bench & Assistants */}
                <div className="pt-3 border-t border-slate-800 space-y-2">
                  <span className="text-xs font-bold text-slate-300 block">
                    Bench & Assistant Staff
                  </span>
                  <div className="grid grid-cols-2 gap-2 text-xs">
                    <div className="p-2 bg-surface/60 rounded border border-slate-800">
                      <span className="text-[10px] text-slate-500 block">Associate HC</span>
                      <span className="text-slate-200 font-medium truncate block">
                        {selectedCoach.assistants.associateHC}
                      </span>
                    </div>
                    <div className="p-2 bg-surface/60 rounded border border-slate-800">
                      <span className="text-[10px] text-slate-500 block">Offensive Lead</span>
                      <span className="text-slate-200 font-medium truncate block">
                        {selectedCoach.assistants.offensiveCoord}
                      </span>
                    </div>
                    <div className="p-2 bg-surface/60 rounded border border-slate-800">
                      <span className="text-[10px] text-slate-500 block">Defensive Lead</span>
                      <span className="text-slate-200 font-medium truncate block">
                        {selectedCoach.assistants.defensiveCoord}
                      </span>
                    </div>
                    <div className="p-2 bg-surface/60 rounded border border-slate-800">
                      <span className="text-[10px] text-slate-500 block">Player Dev / Shooting</span>
                      <span className="text-slate-200 font-medium truncate block">
                        {selectedCoach.assistants.playerDevLead}
                      </span>
                    </div>
                  </div>
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
                  <span>{c.headCoach.name}</span>
                </button>
              ))}
            </div>
          </div>
        </div>
      )}

      {/* Coaching Tree Genealogy Tab */}
      {activeTab === 'genealogy' && (
        <div className="bg-surface-raised/80 border border-slate-800 rounded-xl p-5 shadow-lg space-y-6">
          <div className="flex items-center gap-2.5 pb-4 border-b border-slate-800">
            <div className="p-2 rounded-lg bg-indigo-500/10 text-indigo-400">
              <GitBranch className="w-5 h-5" />
            </div>
            <div>
              <h3 className="text-base font-bold text-white tracking-tight">
                Coaching Tree Lineages & Pedagogical Ancestry
              </h3>
              <p className="text-xs text-slate-400">
                Tracking how strategic philosophies and motion schemes propagate across modern NBA franchises.
              </p>
            </div>
          </div>

          <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
            {coachingTrees.filter((t) => t !== 'All').map((treeName) => {
              const treeMembers = initialData.filter((c) => c.headCoach.coachingTree === treeName);
              const avgCir = +(treeMembers.reduce((sum, c) => sum + c.metrics.coachImpactRating, 0) / treeMembers.length).toFixed(1);

              return (
                <div
                  key={treeName}
                  className="p-4 rounded-xl bg-surface/70 border border-slate-800 hover:border-slate-700 transition-all space-y-3"
                >
                  <div className="flex items-center justify-between pb-2 border-b border-slate-800/80">
                    <div>
                      <h4 className="text-sm font-bold text-white">{treeName} Tree</h4>
                      <span className="text-[10px] text-slate-400">{treeMembers.length} Active Head Coaches</span>
                    </div>
                    <div className="text-right">
                      <span className="text-[9px] text-slate-500 uppercase block">Avg CIR</span>
                      <span className="text-xs font-mono font-bold text-amber-400">{avgCir}</span>
                    </div>
                  </div>

                  <div className="space-y-2">
                    {treeMembers.map((member) => (
                      <div
                        key={member.teamAbbr}
                        onClick={() => {
                          setSelectedCoach(member);
                          setActiveTab('tierboard');
                        }}
                        className="p-2 rounded-lg bg-surface-raised/60 border border-slate-800/80 hover:bg-slate-850 hover:border-amber-500/40 cursor-pointer flex items-center justify-between transition-all"
                      >
                        <div className="flex items-center gap-2 min-w-0">
                          <TeamLogo team={member.teamAbbr} size="xs" />
                          <div className="min-w-0">
                            <span className="text-xs font-semibold text-slate-200 block truncate">
                              {member.headCoach.name}
                            </span>
                            <span className="text-[10px] text-slate-400 truncate block">
                              {member.teamName}
                            </span>
                          </div>
                        </div>
                        <span className="text-xs font-mono font-bold text-amber-400">
                          {member.metrics.coachImpactRating}
                        </span>
                      </div>
                    ))}
                  </div>
                </div>
              );
            })}
          </div>
        </div>
      )}
    </div>
  );
};
