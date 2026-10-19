'use client';

import React, { useState, useMemo } from 'react';
import { CoachingStaffMetric } from '@/lib/coachingTypes';
import { TeamLogo } from '@/components/TeamLogo';
import { CoachRadarProfile } from '@/components/CoachRadarProfile';
import { AtoEfficiencyScatter } from '@/components/AtoEfficiencyScatter';
import { CoachImpactWaterfall } from '@/components/CoachImpactWaterfall';
import {
  Briefcase,
  Crosshair,
  Search,
  Award,
  TrendingUp,
  GitBranch,
  ChevronRight,
} from 'lucide-react';

interface CoachesClientProps {
  initialData: CoachingStaffMetric[];
}

export const CoachesClient: React.FC<CoachesClientProps> = ({ initialData }) => {
  const [activeTab, setActiveTab] = useState<'tierboard' | 'scatter' | 'waterfall' | 'genealogy'>('tierboard');
  const [searchTerm, setSearchTerm] = useState('');
  const [selectedTree, setSelectedTree] = useState<string>('All');
  const [selectedCoach, setSelectedCoach] = useState<CoachingStaffMetric>(initialData[0] || null);

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
    return initialData
      .filter((c) => {
        const matchesSearch =
          c.headCoach.name.toLowerCase().includes(searchTerm.toLowerCase()) ||
          c.teamAbbr.toLowerCase().includes(searchTerm.toLowerCase()) ||
          c.teamName.toLowerCase().includes(searchTerm.toLowerCase()) ||
          c.assistants.associateHC.toLowerCase().includes(searchTerm.toLowerCase()) ||
          c.assistants.offensiveCoord.toLowerCase().includes(searchTerm.toLowerCase());

        const matchesTree = selectedTree === 'All' || c.headCoach.coachingTree === selectedTree;
        return matchesSearch && matchesTree;
      })
      .sort((a, b) => b.metrics.coachImpactRating - a.metrics.coachImpactRating);
  }, [initialData, searchTerm, selectedTree]);

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
            <div className="inline-flex items-center gap-2 px-3 py-1 rounded-full text-xs font-semibold bg-indigo-500/10 text-indigo-400 border border-indigo-500/20">
              <Briefcase className="w-3.5 h-3.5" />
              <span>WNBA Tactical Staffs & System Impact</span>
            </div>
            <h1 className="text-3xl sm:text-4xl font-extrabold tracking-tight text-white">
              Coaching Staffs & Tactical Impact
            </h1>
            <p className="text-sm sm:text-base text-slate-300">
              Evaluate all 15 WNBA head coaches and coaching trees across After-Timeout (ATO)
              efficiency, challenge leverage WPA, rotational staggering, and marginal win lift.
            </p>
          </div>

          <div className="grid grid-cols-3 gap-3 p-3 bg-slate-900/80 rounded-xl border border-slate-800/80 backdrop-blur-sm self-start md:self-auto">
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
              ? 'border-indigo-500 text-indigo-400 bg-indigo-500/5'
              : 'border-transparent text-slate-400 hover:text-slate-200 hover:border-slate-700'
          }`}
        >
          <Award className="w-4 h-4" />
          Coaching Tierboard (15 Staffs)
        </button>

        <button
          onClick={() => setActiveTab('scatter')}
          className={`flex items-center gap-2 py-3 px-4 text-sm font-semibold border-b-2 transition-all whitespace-nowrap ${
            activeTab === 'scatter'
              ? 'border-indigo-500 text-indigo-400 bg-indigo-500/5'
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
              ? 'border-indigo-500 text-indigo-400 bg-indigo-500/5'
              : 'border-transparent text-slate-400 hover:text-slate-200 hover:border-slate-700'
          }`}
        >
          <TrendingUp className="w-4 h-4" />
          Talent-to-Wins Bridge
        </button>

        <button
          onClick={() => setActiveTab('genealogy')}
          className={`flex items-center gap-2 py-3 px-4 text-sm font-semibold border-b-2 transition-all whitespace-nowrap ${
            activeTab === 'genealogy'
              ? 'border-indigo-500 text-indigo-400 bg-indigo-500/5'
              : 'border-transparent text-slate-400 hover:text-slate-200 hover:border-slate-700'
          }`}
        >
          <GitBranch className="w-4 h-4" />
          Coaching Tree Genealogy
        </button>
      </div>

      {/* TAB 1: TIERBOARD & PROFILES */}
      {activeTab === 'tierboard' && (
        <div className="space-y-6">
          {/* Controls Bar */}
          <div className="flex flex-col sm:flex-row gap-4 items-stretch sm:items-center justify-between bg-slate-900/60 p-4 rounded-xl border border-slate-800">
            <div className="relative flex-1 max-w-md">
              <Search className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-slate-500" />
              <input
                type="text"
                placeholder="Search coach, assistant, or franchise..."
                value={searchTerm}
                onChange={(e) => setSearchTerm(e.target.value)}
                className="w-full pl-9 pr-4 py-2 bg-slate-950 border border-slate-800 rounded-lg text-sm text-slate-200 placeholder-slate-500 focus:outline-none focus:border-indigo-500 transition-colors"
              />
            </div>

            <div className="flex items-center gap-2 text-xs text-slate-400 font-medium">
              <span>Coaching Tree:</span>
              <select
                value={selectedTree}
                onChange={(e) => setSelectedTree(e.target.value)}
                className="bg-slate-950 border border-slate-800 rounded-lg px-2.5 py-1.5 text-xs text-slate-200 focus:outline-none focus:border-indigo-500"
              >
                {coachingTrees.map((tree) => (
                  <option key={tree} value={tree}>
                    {tree}
                  </option>
                ))}
              </select>
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
                        ? 'bg-slate-900/90 border-indigo-500/50 shadow-lg shadow-indigo-500/10'
                        : 'bg-slate-900/40 border-slate-800/80 hover:border-slate-700'
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
                            {c.headCoach.tacticalArchetype}
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
                            isSelected ? 'text-indigo-400 translate-x-0.5' : ''
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
              <div className="bg-slate-900/60 border border-slate-800 rounded-xl p-5 space-y-6">
                <div className="flex items-center justify-between border-b border-slate-800 pb-4">
                  <div className="flex items-center gap-3">
                    <TeamLogo team={selectedCoach.teamAbbr} size="lg" />
                    <div>
                      <h2 className="text-lg font-extrabold text-white">
                        {selectedCoach.headCoach.name}
                      </h2>
                      <p className="text-xs text-slate-400">
                        {selectedCoach.teamName} • {selectedCoach.headCoach.tenureYears} yrs tenure
                      </p>
                    </div>
                  </div>
                  <div className="text-right">
                    <span className="text-xs text-slate-400">Tree:</span>
                    <div className="text-xs font-bold text-indigo-400">
                      {selectedCoach.headCoach.coachingTree}
                    </div>
                  </div>
                </div>

                {/* Radar Profile */}
                <CoachRadarProfile
                  percentiles={selectedCoach.radarPercentiles}
                  coachName={selectedCoach.headCoach.name}
                  size={260}
                />

                {/* Assistants Staff Box */}
                <div className="p-3.5 bg-slate-950/60 rounded-lg border border-slate-800/80 space-y-2 text-xs">
                  <span className="text-[10px] uppercase font-bold text-slate-400 block">
                    Bench Staff & Tactical Coordinators
                  </span>
                  <div className="grid grid-cols-2 gap-2 text-slate-300">
                    <div>
                      <span className="text-slate-500 block text-[10px]">Associate HC</span>
                      <span className="font-semibold">{selectedCoach.assistants.associateHC}</span>
                    </div>
                    <div>
                      <span className="text-slate-500 block text-[10px]">Offensive Coord</span>
                      <span className="font-semibold">{selectedCoach.assistants.offensiveCoord}</span>
                    </div>
                    <div>
                      <span className="text-slate-500 block text-[10px]">Defensive Coord</span>
                      <span className="font-semibold">{selectedCoach.assistants.defensiveCoord}</span>
                    </div>
                    <div>
                      <span className="text-slate-500 block text-[10px]">Player Dev Lead</span>
                      <span className="font-semibold">{selectedCoach.assistants.playerDevLead}</span>
                    </div>
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
          <div className="flex flex-wrap items-center gap-2 p-4 bg-slate-900/40 rounded-xl border border-slate-800">
            <span className="text-xs text-slate-400 font-semibold mr-2">Select Staff:</span>
            {initialData.map((c) => (
              <button
                key={c.teamAbbr}
                onClick={() => setSelectedCoach(c)}
                className={`flex items-center gap-1.5 px-3 py-1.5 rounded-lg text-xs font-bold transition-all ${
                  selectedCoach.teamAbbr === c.teamAbbr
                    ? 'bg-indigo-600 text-white shadow-md shadow-indigo-600/30'
                    : 'bg-slate-950 text-slate-300 border border-slate-800 hover:border-slate-700'
                }`}
              >
                <span>{c.teamAbbr}</span>
                <span className="text-[10px] opacity-75">({c.headCoach.name.split(' ')[1]})</span>
              </button>
            ))}
          </div>
        </div>
      )}

      {/* TAB 4: GENEALOGY */}
      {activeTab === 'genealogy' && (
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-5">
          {coachingTrees
            .filter((t) => t !== 'All')
            .map((tree) => {
              const disciples = initialData.filter((c) => c.headCoach.coachingTree === tree);
              return (
                <div
                  key={tree}
                  className="bg-slate-900/60 border border-slate-800 rounded-xl p-5 space-y-4 hover:border-slate-700 transition-all"
                >
                  <div className="flex items-center gap-2 border-b border-slate-800 pb-3">
                    <GitBranch className="w-4 h-4 text-indigo-400" />
                    <h3 className="font-bold text-white text-base">{tree} Tree</h3>
                  </div>

                  <div className="space-y-2">
                    {disciples.map((disciple) => (
                      <div
                        key={disciple.teamAbbr}
                        onClick={() => {
                          setSelectedCoach(disciple);
                          setActiveTab('tierboard');
                        }}
                        className="p-3 bg-slate-950/60 rounded-lg border border-slate-800/80 hover:border-indigo-500/40 cursor-pointer transition-all flex items-center justify-between"
                      >
                        <div className="flex items-center gap-2.5">
                          <TeamLogo team={disciple.teamAbbr} size="sm" />
                          <div>
                            <div className="text-xs font-bold text-white">
                              {disciple.headCoach.name}
                            </div>
                            <div className="text-[10px] text-slate-400">
                              {disciple.teamName} ({disciple.headCoach.tenureYears} yrs)
                            </div>
                          </div>
                        </div>

                        <div className="text-right">
                          <span className="text-[10px] text-slate-400 block">CIR</span>
                          <span className="text-xs font-bold text-indigo-400">
                            {disciple.metrics.coachImpactRating}
                          </span>
                        </div>
                      </div>
                    ))}
                  </div>
                </div>
              );
            })}
        </div>
      )}
    </div>
  );
};
