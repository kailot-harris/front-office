'use client';

import React, { useState, useMemo, useEffect } from 'react';
import {
  PlayerDnaProfile,
  PlayerDnaCatalog,
  PlayerDnaSummary,
  DnaPlayerType,
  MULTI_TEAM_LABEL,
  summarizePlayerDna,
} from '@/lib/playerDnaTypes';
import { SkillFingerprintPolygon } from './SkillFingerprintPolygon';
import { PeerCompCard } from './PeerCompCard';
import { DnaManifoldScatter } from './DnaManifoldScatter';
import { DnaTeamBadge } from './DnaTeamBadge';
import { HowToRead } from '@/components/HowToRead';
import { BASE_PATH } from '@/lib/basePath';
import {
  Dna,
  Search,
  Sparkles,
  ChevronRight,
  Filter,
  Loader2,
} from 'lucide-react';

interface PlayerDnaClientProps {
  // The static HTML embeds only the first screen of profiles; the envelope fields
  // (season, throughDate, dimensions, categories) are complete.
  initialCatalog: PlayerDnaCatalog;
  // Whole-dataset counts and archetype lists, computed at build time from the full file.
  summary: PlayerDnaSummary;
}

const formatDate = (iso: string | null): string | null => {
  if (!iso) return null;
  const d = new Date(`${iso.slice(0, 10)}T12:00:00Z`);
  if (Number.isNaN(d.getTime())) return null;
  return d.toLocaleDateString('en-US', { month: 'short', day: 'numeric', year: 'numeric', timeZone: 'UTC' });
};

export const PlayerDnaClient: React.FC<PlayerDnaClientProps> = ({ initialCatalog, summary: initialSummary }) => {
  // `catalog.profiles` starts as the embedded first screen and is swapped for the
  // full dataset once it has been fetched (the WNBA /player-dna pattern).
  const [catalog, setCatalog] = useState<PlayerDnaCatalog>(initialCatalog);
  const [summary, setSummary] = useState<PlayerDnaSummary>(initialSummary);
  const [isLoadingFull, setIsLoadingFull] = useState(
    initialSummary.totalProfiles > initialCatalog.profiles.length,
  );

  useEffect(() => {
    if (initialSummary.totalProfiles <= initialCatalog.profiles.length) return;
    let cancelled = false;
    fetch(`${BASE_PATH}/data/player_dna_profiles.json`)
      .then((res) => (res.ok ? res.json() : Promise.reject(new Error(`HTTP ${res.status}`))))
      .then((full: PlayerDnaCatalog) => {
        if (!cancelled && full && Array.isArray(full.profiles) && full.profiles.length > 0) {
          setCatalog(full);
          setSummary(summarizePlayerDna(full.profiles));
        }
      })
      .catch((err) => console.error('Failed to fetch full player DNA dataset:', err))
      .finally(() => {
        if (!cancelled) setIsLoadingFull(false);
      });
    return () => {
      cancelled = true;
    };
    // Fetch once after hydration; the embedded first screen never changes.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  const [playerType, setPlayerType] = useState<DnaPlayerType>('Batter');
  const [searchQuery, setSearchQuery] = useState('');
  const [selectedArchetype, setSelectedArchetype] = useState<string>('ALL');

  // Filter profiles by player type
  const typeProfiles = useMemo(() => {
    return catalog.profiles.filter((p) => p.playerType === playerType);
  }, [catalog.profiles, playerType]);

  const batterCount = summary.counts.Batter;
  const pitcherCount = summary.counts.Pitcher;
  const seasonLabel = catalog.season !== null ? `${catalog.season} season` : 'Season unavailable';
  const throughLabel = formatDate(catalog.throughDate);
  const batterDims = catalog.dimensions.Batter.length;
  const pitcherDims = catalog.dimensions.Pitcher.length;
  const dimensionMeta = catalog.dimensions[playerType];
  const categoryMeta = catalog.categories[playerType];

  // Selected player state
  const [selectedPlayer, setSelectedPlayer] = useState<PlayerDnaProfile>(
    typeProfiles[0] || catalog.profiles[0]
  );

  // Once the full dataset has loaded, keep the selected player's record in sync.
  useEffect(() => {
    const refreshed = catalog.profiles.find((p) => p.playerId === selectedPlayer.playerId);
    if (refreshed && refreshed !== selectedPlayer) {
      setSelectedPlayer(refreshed);
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [catalog.profiles]);

  // When switching playerType, reset selected player to first in that pool
  const handleTypeSwitch = (type: DnaPlayerType) => {
    setPlayerType(type);
    setSelectedArchetype('ALL');
    const firstInPool = catalog.profiles.find((p) => p.playerType === type);
    if (firstInPool) setSelectedPlayer(firstInPool);
  };

  // Distinct archetypes in the whole pool of this type (known before the full fetch)
  const availableArchetypes = useMemo(
    () => ['ALL', ...summary.archetypes[playerType]],
    [summary, playerType],
  );

  // Filtered player directory
  const filteredPlayers = useMemo(() => {
    return typeProfiles.filter((p) => {
      const q = searchQuery.toLowerCase();
      const matchesSearch =
        p.playerName.toLowerCase().includes(q) ||
        (p.team ?? MULTI_TEAM_LABEL).toLowerCase().includes(q) ||
        (p.archetype ?? '').toLowerCase().includes(q);
      const matchesArch = selectedArchetype === 'ALL' || p.archetype === selectedArchetype;
      return matchesSearch && matchesArch;
    });
  }, [typeProfiles, searchQuery, selectedArchetype]);

  // Skill rows in the published dimension order with the published labels;
  // null = input missing for this player
  const skillEntries = useMemo(() => {
    if (!selectedPlayer?.skillVector) return [];
    const vec = selectedPlayer.skillVector as unknown as Record<string, number | null>;
    const meta = catalog.dimensions[selectedPlayer.playerType];
    return meta.map((d) => ({ key: d.key, label: d.label, val: vec[d.key] ?? null }));
  }, [selectedPlayer, catalog.dimensions]);
  const dimCount = skillEntries.length;

  return (
    <div className="space-y-6">
      {/* Header Banner */}
      <div className="bg-gradient-to-r from-slate-900 via-sky-950/30 to-slate-900 border border-sky-900/30 rounded-2xl p-6 shadow-xl relative overflow-hidden">
        <div className="absolute right-0 top-0 bottom-0 w-96 bg-[radial-gradient(ellipse_at_top_right,_var(--tw-gradient-stops))] from-sky-500/10 via-indigo-500/5 to-transparent pointer-events-none" />

        <div className="flex flex-col lg:flex-row lg:items-center justify-between gap-6 relative z-10">
          <div>
            <div className="flex items-center gap-2 mb-1.5">
              <span className="px-2.5 py-0.5 rounded-full text-[11px] font-semibold bg-sky-500/10 text-sky-400 border border-sky-500/20 flex items-center gap-1 font-mono">
                <Dna className="w-3.5 h-3.5" /> Player DNA
              </span>
              <span className="text-xs text-slate-400 font-mono" data-testid="dna-season-label">
                {seasonLabel}
                {throughLabel ? ` · through ${throughLabel}` : ''}
              </span>
            </div>
            <h1 className="text-2xl sm:text-3xl font-extrabold tracking-tight text-white">
              Player DNA & Nearest Peer Comps
            </h1>
            <p className="text-sm text-slate-300 max-w-2xl mt-1">
              Skill fingerprints for qualified MLB batters ({batterDims} skill percentiles each) and pitchers
              ({pitcherDims} each), built from FanGraphs leaderboard data for the {seasonLabel}. Each player is
              compared with the other qualified players of the same type in that same season.
            </p>
            <div className="max-w-xl mt-2">
              <HowToRead pageKey="player-dna">
                Every batter gets {batterDims} and every pitcher {pitcherDims} skill percentiles, each ranked within that season&apos;s
                qualified batters or pitchers (a missing input is shown as &quot;—&quot;, never filled in). The radar
                groups them into {categoryMeta.length} category averages. A player who played for more than one club
                that season is shown as &quot;{MULTI_TEAM_LABEL}&quot;. The
                &quot;Peer Comps&quot; panel lists the five players of the same type whose percentile profiles point
                in the most similar direction (cosine similarity around the 50th percentile), so a 100% match means an
                (almost) identical skill mix, not an identical outcome.
              </HowToRead>
            </div>
          </div>

          {/* Batter / Pitcher Toggle */}
          <div className="flex items-center gap-2 bg-surface/80 p-1.5 rounded-xl border border-slate-800 self-start lg:self-auto font-mono text-xs">
            <button
              type="button"
              onClick={() => handleTypeSwitch('Batter')}
              data-testid="dna-type-batter"
              className={`px-4 py-2 rounded-lg font-bold transition-all ${
                playerType === 'Batter'
                  ? 'bg-accent-600 text-fo-on-accent shadow-md shadow-accent-600/30'
                  : 'text-slate-400 hover:text-white'
              }`}
            >
              Batters ({batterCount})
            </button>
            <button
              type="button"
              onClick={() => handleTypeSwitch('Pitcher')}
              data-testid="dna-type-pitcher"
              className={`px-4 py-2 rounded-lg font-bold transition-all ${
                playerType === 'Pitcher'
                  ? 'bg-accent-600 text-fo-on-accent shadow-md shadow-accent-600/30'
                  : 'text-slate-400 hover:text-white'
              }`}
            >
              Pitchers ({pitcherCount})
            </button>
          </div>
        </div>
      </div>

      {/* Main 12-Column Analysis Grid */}
      <div className="grid grid-cols-1 lg:grid-cols-12 gap-6">
        {/* Left Column: Search & Directory Roster (4 cols) */}
        <div className="lg:col-span-4 space-y-4">
          <div className="p-4 rounded-2xl bg-surface-raised/90 border border-slate-800 shadow-xl space-y-3">
            <div className="relative">
              <Search className="w-4 h-4 absolute left-3 top-3.5 text-slate-400" />
              <input
                type="text"
                placeholder={`Search ${playerType} by name, team, or archetype...`}
                value={searchQuery}
                onChange={(e) => setSearchQuery(e.target.value)}
                className="w-full pl-9 pr-4 py-2.5 bg-surface rounded-xl border border-slate-800 text-sm text-white placeholder-slate-500 focus:outline-none focus:border-sky-500 font-mono"
              />
            </div>

            {/* Archetype Filter Dropdown */}
            <div className="flex items-center gap-2">
              <Filter className="w-3.5 h-3.5 text-slate-400 flex-shrink-0" />
              <select aria-label="Filter by archetype"
                value={selectedArchetype}
                onChange={(e) => setSelectedArchetype(e.target.value)}
                className="w-full bg-surface border border-slate-800 rounded-lg px-2.5 py-1.5 text-xs text-slate-200 focus:outline-none focus:border-sky-500 font-mono cursor-pointer truncate"
              >
                {availableArchetypes.map((arch) => (
                  <option key={arch} value={arch}>
                    {arch === 'ALL' ? `All Archetypes (${summary.counts[playerType]})` : arch}
                  </option>
                ))}
              </select>
            </div>

            <div role="status" aria-live="polite" data-testid="dna-load-status" data-state={isLoadingFull ? 'loading' : 'complete'}>
              {isLoadingFull && (
                <div className="flex items-center gap-1.5 text-[11px] sm:text-[10px] text-slate-400 font-mono">
                  <Loader2 className="w-3 h-3 animate-spin" />
                  <span>
                    Loading all players ({catalog.profiles.length} of {summary.totalProfiles} shown)...
                  </span>
                </div>
              )}
            </div>

            {/* Player Roster List */}
            <div tabIndex={0} role="region" aria-label="Player list" className="space-y-1.5 max-h-[580px] overflow-y-auto pr-1">
              {filteredPlayers.map((p) => {
                const isSelected = p.playerId === selectedPlayer?.playerId;
                return (
                  <div
                    key={p.playerId}
                    data-testid="dna-roster-item"
                    onClick={() => setSelectedPlayer(p)}
                    className={`flex items-center justify-between p-2.5 rounded-xl border cursor-pointer transition-all ${
                      isSelected
                        ? 'bg-sky-950/40 border-sky-500/60 shadow-lg shadow-sky-500/10'
                        : 'bg-surface/60 border-slate-800/80 hover:bg-slate-800/50 hover:border-slate-700'
                    }`}
                  >
                    <div className="flex items-center gap-2.5 min-w-0">
                      <DnaTeamBadge team={p.team} size="sm" />
                      <div className="min-w-0">
                        <div className="flex items-center gap-1.5">
                          <span className="font-bold text-xs text-white truncate">{p.playerName}</span>
                          <span className="text-[11px] sm:text-[10px] font-mono px-1.5 py-0.2 rounded bg-slate-800 text-slate-400">
                            {p.position}
                          </span>
                        </div>
                        <p className="text-[10.5px] text-slate-400 font-mono truncate">{p.archetype ?? 'Insufficient data'}</p>
                      </div>
                    </div>

                    <div className="flex items-center gap-2 flex-shrink-0">
                      <div className="text-right font-mono">
                        <span className="text-xs font-bold text-sky-400 block">{p.overallRating ?? '—'} OVR</span>
                      </div>
                      <ChevronRight className={`w-4 h-4 ${isSelected ? 'text-sky-400' : 'text-slate-600'}`} />
                    </div>
                  </div>
                );
              })}
            </div>
          </div>
        </div>

        {/* Middle Column: Player Focus Profile & Skill Vector Breakdown (4 cols) */}
        <div className="lg:col-span-4 space-y-4">
          {/* Headline Card */}
          <div className="p-5 rounded-2xl bg-surface-raised/90 border border-slate-800 shadow-xl space-y-4">
            <div className="flex items-center justify-between border-b border-slate-800/80 pb-3">
              <div className="flex items-center gap-3">
                <DnaTeamBadge team={selectedPlayer.team} size="lg" />
                <div>
                  <h2 className="text-xl font-extrabold text-white" data-testid="dna-selected-name">{selectedPlayer.playerName}</h2>
                  <div className="flex items-center gap-2 text-xs font-mono text-slate-400 mt-0.5">
                    <span data-testid="dna-team">{selectedPlayer.team ?? MULTI_TEAM_LABEL}</span>
                    <span>•</span>
                    <span>{selectedPlayer.position ?? '—'}</span>
                    <span>•</span>
                    <span>Age {selectedPlayer.age ?? '—'}</span>
                  </div>
                </div>
              </div>

              <div className="text-right font-mono">
                <span className="text-2xl font-black text-white">{selectedPlayer.overallRating ?? '—'}</span>
                <span className="text-[11px] sm:text-[10px] text-sky-400 block font-bold">DNA SCORE</span>
              </div>
            </div>

            {/* Archetype Badge */}
            <div className="p-3 bg-surface/80 rounded-xl border border-sky-500/30 flex items-center justify-between">
              <div>
                <span className="text-[11px] sm:text-[10px] uppercase font-mono font-bold text-slate-400 block">Classified Archetype</span>
                <span className="text-sm font-bold text-sky-300 font-mono">{selectedPlayer.archetype ?? 'Insufficient data'}</span>
              </div>
              <Sparkles className="w-5 h-5 text-amber-400 flex-shrink-0" />
            </div>

            {/* Headline Key Stats Grid */}
            <div className="grid grid-cols-4 gap-2 text-center font-mono text-xs">
              <div className="bg-surface p-2 rounded-lg border border-slate-800">
                <span className="text-[11px] sm:text-[10px] text-slate-400 block">{selectedPlayer.headlineStats.stat1Label}</span>
                <span className="font-bold text-white text-xs">{selectedPlayer.headlineStats.stat1Val ?? '—'}</span>
              </div>
              <div className="bg-surface p-2 rounded-lg border border-slate-800">
                <span className="text-[11px] sm:text-[10px] text-slate-400 block">{selectedPlayer.headlineStats.stat2Label}</span>
                <span className="font-bold text-white text-xs">{selectedPlayer.headlineStats.stat2Val ?? '—'}</span>
              </div>
              <div className="bg-surface p-2 rounded-lg border border-slate-800">
                <span className="text-[11px] sm:text-[10px] text-slate-400 block">{selectedPlayer.headlineStats.stat3Label}</span>
                <span className="font-bold text-white text-xs">{selectedPlayer.headlineStats.stat3Val ?? '—'}</span>
              </div>
              <div className="bg-surface p-2 rounded-lg border border-slate-800">
                <span className="text-[11px] sm:text-[10px] text-slate-400 block">{selectedPlayer.headlineStats.countLabel}</span>
                <span className="font-bold text-amber-400 text-xs">{selectedPlayer.headlineStats.countVal ?? '—'}</span>
              </div>
            </div>

            {/* Radar Polygon */}
            <SkillFingerprintPolygon
              playerType={playerType}
              categoryScores={selectedPlayer.categoryScores}
              categories={categoryMeta}
              dimensions={dimensionMeta}
            />

            {/* Individual Vector Progress Bars */}
            <div className="space-y-2 pt-2 border-t border-slate-800/80">
              <span className="text-[10.5px] uppercase font-mono font-bold text-slate-400 tracking-wider block">
                {dimCount}-Dimension Skill Percentiles ({seasonLabel})
              </span>
              <div className="grid grid-cols-2 gap-2 text-xs font-mono">
                {skillEntries.map((item) => (
                  <div key={item.key} data-testid="dna-skill-row" className="bg-surface/60 p-2 rounded-lg border border-slate-800/50 space-y-1">
                    <div className="flex justify-between text-[10.5px]">
                      <span className="text-slate-400 truncate">{item.label}</span>
                      <span className="font-bold text-white">{item.val ?? '—'}</span>
                    </div>
                    <div className="w-full bg-surface-raised h-1.5 rounded-full overflow-hidden">
                      <div
                        className={`h-full rounded-full ${playerType === 'Batter' ? 'bg-sky-500' : 'bg-amber-500'}`}
                        style={{ width: `${item.val ?? 0}%` }}
                      />
                    </div>
                  </div>
                ))}
              </div>
            </div>
          </div>
        </div>

        {/* Right Column: Peer Comps & Style Map (4 cols) */}
        <div className="lg:col-span-4 space-y-6">
          {/* Peer Comps List */}
          <div className="p-5 rounded-2xl bg-surface-raised/90 border border-slate-800 shadow-xl space-y-3.5">
            <div className="flex items-center justify-between border-b border-slate-800/80 pb-3">
              <div>
                <h3 className="text-sm font-bold text-white uppercase tracking-wider font-mono">
                  Top 5 Peer Comps
                </h3>
                <p className="text-xs text-slate-400">Same-type players, {seasonLabel}</p>
              </div>
              <span className="text-[11px] sm:text-[10px] font-mono px-2 py-0.5 rounded-full bg-emerald-500/10 text-emerald-400 border border-emerald-500/20 font-bold">
                Cosine Comps
              </span>
            </div>

            <div className="space-y-2.5">
              {selectedPlayer.peerComps.length === 0 ? (
                <p className="text-xs text-slate-400">Insufficient data: too few measured skill dimensions to compare.</p>
              ) : (
                selectedPlayer.peerComps.map((comp, idx) => (
                  <PeerCompCard key={comp.playerId} comp={comp} rank={idx + 1} />
                ))
              )}
            </div>
          </div>

          {/* Style map: fixed blend of category scores */}
          <DnaManifoldScatter
            players={typeProfiles}
            selectedPlayer={selectedPlayer}
            onSelectPlayer={setSelectedPlayer}
            playerType={playerType}
            categories={categoryMeta}
            totalPlotted={summary.plotted[playerType]}
          />
        </div>
      </div>
    </div>
  );
};
