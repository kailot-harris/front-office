'use client';

import React, { useState } from 'react';
import { ClutchProfile, CLUTCH_MIN_FGA, CLUTCH_DATA_SEASON_NOTE } from '@/lib/clutchTypes';
import { ClutchShotBreakdownCard } from './ClutchShotBreakdownCard';
import { PressureResiliencePlot } from './PressureResiliencePlot';
import { Flame, Search, ChevronRight, Activity, Crosshair, ArrowUpDown, Shield } from 'lucide-react';
import { SeasonSourceBadge } from '@/components/SeasonSourceBadge';
import { SEASON_SOURCES } from '@/lib/season';
import { HowToReadDisclosure } from '@/components/HowToReadDisclosure';
import { GlossaryTerm } from '@/components/GlossaryTerm';

interface ClutchClientProps {
  initialProfiles: ClutchProfile[];
}

/**
 * True when a profile meets the clutch sample minimum (NBA#90). Checked on the
 * attempt count as well as the published flag, so a stale file can never let an
 * under-threshold player be ranked or labelled.
 */
const isQualified = (p: ClutchProfile) => p.qualified === true && p.clutchFga >= CLUTCH_MIN_FGA;

/** Lowest and highest USCI among qualified players, or null when none qualify. */
export function qualifiedUsciRange(
  profiles: ClutchProfile[]
): { min: number; max: number; above100: number } | null {
  const values = profiles
    .filter(isQualified)
    .map((p) => p.usciScore)
    .filter((v): v is number => v != null && Number.isFinite(v));
  if (values.length === 0) return null;
  return {
    min: Math.min(...values),
    max: Math.max(...values),
    above100: values.filter((v) => v > 100).length,
  };
}

export const ClutchClient: React.FC<ClutchClientProps> = ({ initialProfiles }) => {
  const [searchQuery, setSearchQuery] = useState('');
  const [sortKey, setSortKey] = useState<'usciScore' | 'clutchTsPct' | 'cDwpa' | 'clutchUsgPct'>('usciScore');
  const [sampleView, setSampleView] = useState<'QUALIFIED' | 'ALL'>('QUALIFIED');
  const [selectedArchetypeFilter, setSelectedArchetypeFilter] = useState<string>('ALL');

  const qualifiedCount = initialProfiles.filter(isQualified).length;
  const usciRange = qualifiedUsciRange(initialProfiles);
  const usciScaleText =
    'USCI is not a 0-100 scale: it is the unassisted share of clutch makes times clutch points per shot attempt, times 100, capped at 0-150.';
  const usciRangeText = usciRange
    ? `${usciScaleText} Among the ${qualifiedCount} qualified players it runs from ${usciRange.min} to ${usciRange.max}; ${usciRange.above100} ${usciRange.above100 === 1 ? 'is' : 'are'} above 100.`
    : `${usciScaleText} No player meets the sample minimum yet.`;

  // Default selection is a qualified player, never an unranked one.
  const topQualified = [...initialProfiles]
    .filter(isQualified)
    .sort((a, b) => (a.clutchRank ?? Infinity) - (b.clutchRank ?? Infinity))[0];
  const [selectedProfile, setSelectedProfile] = useState<ClutchProfile>(
    initialProfiles.find((p) => p.playerName === 'Luka Doncic' && isQualified(p)) ||
      topQualified ||
      initialProfiles[0]
  );

  const filteredProfiles = initialProfiles
    .filter((p) => {
      const q = searchQuery.toLowerCase();
      const matchesSearch =
        p.playerName.toLowerCase().includes(q) ||
        p.team.toLowerCase().includes(q) ||
        (p.clutchArchetype ?? '').toLowerCase().includes(q);
      const matchesPos =
        selectedArchetypeFilter === 'ALL' ||
        (selectedArchetypeFilter === 'G' && p.position === 'G') ||
        (selectedArchetypeFilter === 'F' && p.position === 'F') ||
        (selectedArchetypeFilter === 'C' && p.position === 'C');
      const matchesSample = sampleView === 'ALL' || isQualified(p);
      return matchesSearch && matchesPos && matchesSample;
    })
    // Qualified players always sort ahead of unranked ones, whatever the metric;
    // unranked players follow, ordered by attempt count.
    .sort((a, b) => {
      const qa = isQualified(a) ? 1 : 0;
      const qb = isQualified(b) ? 1 : 0;
      if (qa !== qb) return qb - qa;
      if (!qa) return b.clutchFga - a.clutchFga;
      return ((b[sortKey] ?? -Infinity) as number) - ((a[sortKey] ?? -Infinity) as number);
    });

  return (
    <div className="space-y-6">
      {/* Header Banner */}
      <div className="flex flex-col md:flex-row md:items-center justify-between gap-4 p-5 rounded-2xl bg-gradient-to-r from-zinc-900 via-rose-950/20 to-zinc-900 border border-rose-900/30">
        <div>
          <div className="flex items-center gap-2 mb-1">
            <span className="px-2.5 py-0.5 rounded-full text-[11px] font-semibold bg-rose-500/10 text-rose-400 border border-rose-500/20 flex items-center gap-1">
              <Flame className="w-3.5 h-3.5" /> True Clutch & Leverage Creation Index
            </span>
            <span className="text-xs text-zinc-500 font-mono">Leverage Index (LI ≤ 5 pts, ≤ 5:00 4Q)</span>
            <SeasonSourceBadge
              season={SEASON_SOURCES.clutch.season}
              kind="projection"
              label="Projected season"
              title={SEASON_SOURCES.clutch.note}
            />
          </div>
          <h1 className="text-2xl font-bold tracking-tight text-zinc-100">
            Late-Game Shot Creation, Efficiency & Defensive Stops
          </h1>
          <p className="text-sm text-zinc-400 max-w-2xl mt-1">
            Filtering non-competitive garbage time to evaluate unassisted isolation scoring (USCI), pressure True Shooting % deltas,
            turnover fragility under late-game blitzes, and clutch defensive stops (c-dWPA).
          </p>
        </div>
      </div>

      <HowToReadDisclosure pageKey="clutch">
        Only possessions in the final 5 minutes of the 4th quarter (or overtime) with the score
        within 5 points count as clutch. <GlossaryTerm term="USCI" /> credits a player for shots
        they created themselves rather than ones a teammate set up, <GlossaryTerm term="c-dWPA" />{' '}
        does the same on the defensive end, and clutch <GlossaryTerm term="TS%" /> shows whether scoring
        efficiency holds up or falls off once the game tightens.
      </HowToReadDisclosure>

      {/* Methodology note (NBA#90): sample minimum, season and USCI range */}
      <div
        data-testid="clutch-methodology"
        className="p-4 rounded-xl bg-zinc-900/50 border border-zinc-800 text-xs text-zinc-400 leading-relaxed space-y-1"
      >
        <div className="font-semibold text-zinc-300">Methodology</div>
        <p>
          Season: {CLUTCH_DATA_SEASON_NOTE} Clutch means the 4th quarter or overtime, 5:00 or less on the
          clock, with the score within 5 points.
        </p>
        <p>
          Sample minimum: a player needs at least {CLUTCH_MIN_FGA} clutch field-goal attempts to get clutch
          rates, a rank and an archetype. {qualifiedCount} of {initialProfiles.length} players qualify.
          Players under the minimum are listed only in the &quot;All players&quot; view, unranked, with their
          attempt count.
        </p>
        <p>{usciRangeText}</p>
      </div>

      {/* Main Grid: Left Roster / Right Focus View */}
      <div className="grid grid-cols-1 lg:grid-cols-12 gap-6">
        {/* Left Column: Search & Leaderboard (4 cols) */}
        <div className="lg:col-span-4 space-y-4">
          <div className="p-4 rounded-xl bg-zinc-900/50 border border-zinc-800 space-y-3">
            <div className="relative">
              <Search className="w-4 h-4 absolute left-3 top-3 text-zinc-400" />
              <input
                type="text"
                placeholder="Search closer, team, archetype..."
                value={searchQuery}
                onChange={(e) => setSearchQuery(e.target.value)}
                className="w-full pl-9 pr-3 py-2 text-sm bg-zinc-950 border border-zinc-800 rounded-lg text-zinc-200 placeholder-zinc-500 focus:outline-none focus:border-rose-500 transition-colors"
              />
            </div>

            {/* Sample View Toggle */}
            <div className="flex items-center gap-1.5">
              {[
                { label: `Qualified (${CLUTCH_MIN_FGA}+ FGA)`, val: 'QUALIFIED' as const },
                { label: 'All players', val: 'ALL' as const },
              ].map((tab) => (
                <button
                  key={tab.val}
                  onClick={() => setSampleView(tab.val)}
                  className={`flex-1 py-1 text-xs font-semibold rounded-md transition-colors ${
                    sampleView === tab.val
                      ? 'bg-accent-600 text-white shadow-sm'
                      : 'bg-zinc-800/80 text-zinc-400 hover:text-zinc-200 hover:bg-zinc-800'
                  }`}
                >
                  {tab.label}
                </button>
              ))}
            </div>

            {/* Position Filter Buttons */}
            <div className="flex items-center gap-1.5">
              {[
                { label: 'All Roles', val: 'ALL' },
                { label: 'Guards (G)', val: 'G' },
                { label: 'Wings (F)', val: 'F' },
                { label: 'Bigs (C)', val: 'C' },
              ].map((tab) => (
                <button
                  key={tab.val}
                  onClick={() => setSelectedArchetypeFilter(tab.val)}
                  className={`flex-1 py-1 text-xs font-semibold rounded-md transition-colors ${
                    selectedArchetypeFilter === tab.val
                      ? 'bg-accent-600 text-white shadow-sm'
                      : 'bg-zinc-800/80 text-zinc-400 hover:text-zinc-200 hover:bg-zinc-800'
                  }`}
                >
                  {tab.label}
                </button>
              ))}
            </div>

            {/* Sort Metric Selector */}
            <div className="flex items-center justify-between text-xs text-zinc-400 pt-1">
              <span className="flex items-center gap-1">
                <ArrowUpDown className="w-3 h-3 text-rose-400" /> Sort metric:
              </span>
              <div className="flex gap-2">
                <button
                  onClick={() => setSortKey('usciScore')}
                  title={usciRangeText}
                  className={`underline-offset-2 ${sortKey === 'usciScore' ? 'text-rose-400 underline font-semibold' : 'hover:text-zinc-200'}`}
                >
                  USCI
                </button>
                <button
                  onClick={() => setSortKey('clutchTsPct')}
                  className={`underline-offset-2 ${sortKey === 'clutchTsPct' ? 'text-rose-400 underline font-semibold' : 'hover:text-zinc-200'}`}
                >
                  Clutch TS%
                </button>
                <button
                  onClick={() => setSortKey('cDwpa')}
                  className={`underline-offset-2 ${sortKey === 'cDwpa' ? 'text-rose-400 underline font-semibold' : 'hover:text-zinc-200'}`}
                >
                  c-dWPA
                </button>
              </div>
            </div>
          </div>

          {/* Player Scroll List */}
          <div className="rounded-xl border border-zinc-800 bg-zinc-900/30 overflow-hidden divide-y divide-zinc-800/60 max-h-[620px] overflow-y-auto">
            {filteredProfiles.slice(0, 50).map((profile) => {
              const isSelected = profile.playerId === selectedProfile.playerId;
              return (
                <button
                  key={profile.playerId}
                  onClick={() => setSelectedProfile(profile)}
                  className={`w-full text-left p-3 flex items-center justify-between transition-colors ${
                    isSelected
                      ? 'bg-rose-950/40 border-l-4 border-l-rose-500 text-zinc-100'
                      : 'hover:bg-zinc-800/40 text-zinc-300'
                  }`}
                >
                  <div>
                    <div className="flex items-center gap-2">
                      <span className="text-[11px] font-mono text-zinc-500 w-7">
                        {isQualified(profile) && profile.clutchRank != null ? `#${profile.clutchRank}` : '–'}
                      </span>
                      <span className="font-semibold text-sm">{profile.playerName}</span>
                      <span className="text-[11px] sm:text-[10px] font-mono px-1.5 py-0.5 rounded bg-zinc-800 text-zinc-400">
                        {profile.team} · {profile.position}
                      </span>
                    </div>
                    <div className="text-xs text-zinc-400 truncate max-w-[210px] mt-0.5">
                      {isQualified(profile)
                        ? `${profile.clutchArchetype ?? ''} · ${profile.clutchFga} FGA`
                        : `Unranked · ${profile.clutchFga} of ${CLUTCH_MIN_FGA} clutch FGA`}
                    </div>
                  </div>
                  <div className="flex items-center gap-2">
                    <div className="text-right">
                      <div className="text-xs font-bold text-rose-400">
                        {sortKey === 'usciScore'
                          ? (profile.usciScore != null ? `${profile.usciScore}` : 'N/A')
                          : sortKey === 'clutchTsPct'
                          ? (profile.clutchTsPct != null ? `${profile.clutchTsPct}%` : 'N/A')
                          : (profile.cDwpa != null ? `+${profile.cDwpa}%` : 'N/A')}
                      </div>
                      <div className="text-[11px] sm:text-[9px] text-zinc-500 uppercase">
                        {sortKey === 'usciScore' ? 'USCI' : sortKey === 'clutchTsPct' ? 'TS%' : 'c-dWPA'}
                      </div>
                    </div>
                    <ChevronRight className="w-4 h-4 text-zinc-500" />
                  </div>
                </button>
              );
            })}
          </div>
        </div>

        {/* Right Column: In-Depth Closer Focus Dashboard (8 cols) */}
        <div className="lg:col-span-8 space-y-5">
          {/* Active Profile Header Card */}
          <div className="p-5 rounded-2xl bg-zinc-900/70 border border-zinc-800/90 relative overflow-hidden">
            <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-4">
              <div>
                <div className="flex items-center gap-2 mb-1">
                  <span className="text-xs font-mono px-2 py-0.5 rounded bg-zinc-800 text-rose-400 border border-zinc-700">
                    {selectedProfile.team} · {selectedProfile.position}
                  </span>
                  <span className="text-xs font-medium text-zinc-400">
                    {selectedProfile.clutchMpg != null ? `${selectedProfile.clutchMpg} Clutch MPG` : 'N/A'} · {selectedProfile.clutchUsgPct != null ? `${selectedProfile.clutchUsgPct}% USG` : 'N/A'}
                  </span>
                </div>
                <h2 className="text-2xl font-bold text-zinc-100 tracking-tight">
                  {selectedProfile.playerName}
                </h2>
                <p className="text-sm font-semibold text-rose-400 mt-0.5 flex items-center gap-1.5">
                  <Flame className="w-4 h-4" />
                  {isQualified(selectedProfile)
                    ? `${selectedProfile.clutchRank != null ? `#${selectedProfile.clutchRank} USCI · ` : ''}${selectedProfile.clutchArchetype ?? ''}`
                    : `Unranked: ${selectedProfile.clutchFga} of the ${CLUTCH_MIN_FGA} clutch FGA needed`}
                </p>
              </div>

              {/* Core Clutch Badges, with the sample size beside them */}
              <div className="flex items-center gap-2.5">
                <div
                  className="px-3 py-2 rounded-xl bg-zinc-950/80 border border-zinc-800 text-center"
                  data-testid="clutch-fga-badge"
                >
                  <div className="text-[11px] text-zinc-400 font-medium">CLUTCH FGA</div>
                  <div className="text-base font-bold text-zinc-100">{selectedProfile.clutchFga}</div>
                </div>
                <div className="px-3 py-2 rounded-xl bg-zinc-950/80 border border-zinc-800 text-center">
                  <div className="text-[11px] text-zinc-400 font-medium" title={usciRangeText}>USCI</div>
                  <div className="text-base font-bold text-rose-400">{selectedProfile.usciScore != null ? selectedProfile.usciScore : 'N/A'}</div>
                </div>
                <div className="px-3 py-2 rounded-xl bg-zinc-950/80 border border-zinc-800 text-center">
                  <div className="text-[11px] text-zinc-400 font-medium">CLUTCH TS%</div>
                  <div className="text-base font-bold text-zinc-100">{selectedProfile.clutchTsPct != null ? `${selectedProfile.clutchTsPct}%` : 'N/A'}</div>
                </div>
                <div className="px-3 py-2 rounded-xl bg-zinc-950/80 border border-zinc-800 text-center">
                  <div className="text-[11px] text-zinc-400 font-medium">TS DELTA</div>
                  <div className={`text-base font-bold ${selectedProfile.tsDelta != null && selectedProfile.tsDelta >= 0 ? 'text-emerald-400' : 'text-rose-400'}`}>
                    {selectedProfile.tsDelta != null ? (selectedProfile.tsDelta >= 0 ? `+${selectedProfile.tsDelta}%` : `${selectedProfile.tsDelta}%`) : 'N/A'}
                  </div>
                </div>
                <div className="px-3 py-2 rounded-xl bg-rose-950/60 border border-rose-800/80 text-center">
                  <div className="text-[11px] text-rose-400 font-medium">c-dWPA</div>
                  <div className="text-base font-bold text-rose-200">{selectedProfile.cDwpa != null ? `+${selectedProfile.cDwpa}%` : 'N/A'}</div>
                </div>
              </div>
            </div>
          </div>

          {/* Spatial Clutch Shot Generation Breakdown */}
          <ClutchShotBreakdownCard
            breakdown={selectedProfile.shotBreakdown}
          />

          {/* Pressure Resilience Scatter (TS% vs Turnover Fragility) */}
          <PressureResiliencePlot
            profiles={initialProfiles}
            selectedProfile={selectedProfile}
            onSelectProfile={(p) => setSelectedProfile(p)}
          />

          {/* Explanatory Metric Callout Cards */}
          <div className="grid grid-cols-1 md:grid-cols-3 gap-3">
            <div className="p-3.5 rounded-xl bg-zinc-950/60 border border-zinc-800/80">
              <div className="text-xs font-semibold text-zinc-300 flex items-center gap-1.5 mb-1">
                <Crosshair className="w-3.5 h-3.5 text-rose-400" />
                Unassisted FGM%: {selectedProfile.unassistedFgmPct != null ? `${selectedProfile.unassistedFgmPct}%` : 'N/A'}
              </div>
              <p className="text-[11px] text-zinc-400 leading-relaxed">
                Percentage of clutch baskets scored without a teammate assist, measuring pure late-game isolation engine capacity.
              </p>
            </div>
            <div className="p-3.5 rounded-xl bg-zinc-950/60 border border-zinc-800/80">
              <div className="text-xs font-semibold text-zinc-300 flex items-center gap-1.5 mb-1">
                <Activity className="w-3.5 h-3.5 text-sky-400" />
                Turnover Fragility: {selectedProfile.tovFragility != null ? (selectedProfile.tovFragility > 0 ? `+${selectedProfile.tovFragility}%` : `${selectedProfile.tovFragility}%`) : 'N/A'}
              </div>
              <p className="text-[11px] text-zinc-400 leading-relaxed">
                Shift in turnover rate in 4th-quarter clutch moments. Negative values indicate elite, ice-cold ball security.
              </p>
            </div>
            <div className="p-3.5 rounded-xl bg-zinc-950/60 border border-zinc-800/80">
              <div className="text-xs font-semibold text-zinc-300 flex items-center gap-1.5 mb-1">
                <Shield className="w-3.5 h-3.5 text-emerald-400" />
                Clutch dWPA: {selectedProfile.cDwpa != null ? `+${selectedProfile.cDwpa}%` : 'N/A'}
              </div>
              <p className="text-[11px] text-zinc-400 leading-relaxed">
                Net team win probability added exclusively through late-game defensive stops, contests, deflections, and rebounds.
              </p>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
};
