'use client';

import React, { useState, useEffect, useMemo } from 'react';
import { PlayerCatalogEntry, PlayerShotData, ShotsMetadata } from '@/lib/shotTypes';
import { PlayerShotChart } from '@/components/PlayerShotChart';
import { TeamLogo } from '@/components/TeamLogo';
import { BASE_PATH } from '@/lib/basePath';
import { Search, Crosshair, Sparkles, Loader2, AlertCircle } from 'lucide-react';

interface ShotsExplorerClientProps {
  catalog: PlayerCatalogEntry[];
  metadata: ShotsMetadata;
  initialPlayerId?: string;
}

export const ShotsExplorerClient: React.FC<ShotsExplorerClientProps> = ({
  catalog,
  metadata,
  initialPlayerId,
}) => {
  // Default to A'ja Wilson (3149391) or Caitlin Clark (4432858) or first catalog entry
  const defaultPlayer = useMemo(() => {
    if (initialPlayerId) {
      const match = catalog.find((c) => c.player_id === initialPlayerId);
      if (match) return match;
    }
    const aja = catalog.find((c) => c.player_name.includes('Wilson'));
    if (aja) return aja;
    const clark = catalog.find((c) => c.player_name.includes('Clark'));
    return clark || catalog[0];
  }, [catalog, initialPlayerId]);

  const [selectedPlayer, setSelectedPlayer] = useState<PlayerCatalogEntry | null>(defaultPlayer || null);
  const [searchTerm, setSearchTerm] = useState<string>('');
  const [selectedTeam, setSelectedTeam] = useState<string>('All');
  const [loading, setLoading] = useState<boolean>(false);
  const [playerShotData, setPlayerShotData] = useState<PlayerShotData | null>(null);
  const [error, setError] = useState<string | null>(null);

  // Teams list for filtering
  const teams = useMemo(() => {
    const set = new Set(catalog.map((c) => c.team));
    return ['All', ...Array.from(set).sort()];
  }, [catalog]);

  // Featured WNBA marquee stars for quick-select pills
  const featuredStars = useMemo(() => {
    const starNames = [
      'Wilson',
      'Clark',
      'Stewart',
      'Ionescu',
      'Collier',
      'Plum',
      'Thomas',
      'Ogunbowale',
    ];
    return catalog.filter((c) =>
      starNames.some((star) => c.player_name.toLowerCase().includes(star.toLowerCase()))
    );
  }, [catalog]);

  // Filtered players in dropdown
  const filteredCatalog = useMemo(() => {
    return catalog.filter((p) => {
      if (selectedTeam !== 'All' && p.team !== selectedTeam) return false;
      if (searchTerm.trim() !== '') {
        const term = searchTerm.toLowerCase();
        return (
          p.player_name.toLowerCase().includes(term) ||
          p.team.toLowerCase().includes(term)
        );
      }
      return true;
    });
  }, [catalog, selectedTeam, searchTerm]);

  // Fetch shot data when selectedPlayer changes
  useEffect(() => {
    if (!selectedPlayer) return;

    let isMounted = true;
    setLoading(true);
    setError(null);

    fetch(`${BASE_PATH}/data/shots/${selectedPlayer.player_id}.json`)
      .then((res) => {
        if (!res.ok) throw new Error(`Could not load shot telemetry for ${selectedPlayer.player_name}`);
        return res.json();
      })
      .then((data: PlayerShotData) => {
        if (isMounted) {
          setPlayerShotData(data);
          setLoading(false);
        }
      })
      .catch((err) => {
        if (isMounted) {
          setError(err.message);
          setLoading(false);
        }
      });

    return () => {
      isMounted = false;
    };
  }, [selectedPlayer]);

  return (
    <div className="space-y-6">
      {/* Featured Marquee Stars Bar */}
      {featuredStars.length > 0 && (
        <div className="flex flex-wrap items-center gap-2">
          <div className="flex items-center gap-1.5 text-xs text-slate-400 font-semibold uppercase tracking-wider mr-1">
            <Sparkles className="w-3.5 h-3.5 text-amber-400" />
            <span>Featured Stars:</span>
          </div>
          {featuredStars.map((star) => {
            const isSelected = selectedPlayer?.player_id === star.player_id;
            return (
              <button
                key={star.player_id}
                onClick={() => setSelectedPlayer(star)}
                className={`flex items-center gap-1.5 px-3 py-1.5 rounded-full text-xs font-medium transition-all ${
                  isSelected
                    ? 'bg-accent-600 text-white font-bold shadow-md'
                    : 'bg-surface-raised border border-slate-800 text-slate-300 hover:text-white hover:border-slate-700'
                }`}
              >
                <TeamLogo team={star.team} size="xs" />
                <span>{star.player_name}</span>
                <span className="text-[10px] opacity-75 font-mono">({star.total_shots})</span>
              </button>
            );
          })}
        </div>
      )}

      {/* Search and Filters Bar */}
      <div className="grid grid-cols-1 md:grid-cols-12 gap-3 bg-surface-raised/60 p-3 rounded-xl border border-slate-800">
        <div className="md:col-span-6 relative">
          <Search className="w-4 h-4 absolute left-3 top-3 text-slate-500" />
          <input
            type="text"
            placeholder="Search rotation player by name or team..."
            value={searchTerm}
            onChange={(e) => setSearchTerm(e.target.value)}
            className="w-full bg-surface border border-slate-800 rounded-lg pl-9 pr-4 py-2 text-sm text-white placeholder-slate-500 focus:outline-none focus:border-indigo-500 transition-colors"
          />
        </div>

        <div className="md:col-span-3">
          <select
            value={selectedTeam}
            onChange={(e) => setSelectedTeam(e.target.value)}
            className="w-full bg-surface border border-slate-800 rounded-lg px-3 py-2 text-sm text-white focus:outline-none focus:border-indigo-500 transition-colors"
          >
            {teams.map((t) => (
              <option key={t} value={t}>
                {t === 'All' ? 'All Franchises' : t}
              </option>
            ))}
          </select>
        </div>

        <div className="md:col-span-3">
          <select
            value={selectedPlayer?.player_id || ''}
            onChange={(e) => {
              const match = catalog.find((p) => p.player_id === e.target.value);
              if (match) setSelectedPlayer(match);
            }}
            className="w-full bg-surface border border-slate-800 rounded-lg px-3 py-2 text-sm text-white font-semibold focus:outline-none focus:border-indigo-500 transition-colors"
          >
            {filteredCatalog.map((p) => (
              <option key={p.player_id} value={p.player_id}>
                {p.player_name} ({p.team}) — {p.total_shots} shots
              </option>
            ))}
          </select>
        </div>
      </div>

      {/* Active Player Card Header */}
      {selectedPlayer && (
        <div className="bg-surface-raised/90 border border-slate-800 rounded-2xl p-5 shadow-lg flex flex-col sm:flex-row sm:items-center justify-between gap-4">
          <div className="flex items-center gap-4">
            <TeamLogo team={selectedPlayer.team} size="lg" />
            <div>
              <div className="flex items-center gap-2">
                <h2 className="text-xl font-black text-white tracking-tight">
                  {selectedPlayer.player_name}
                </h2>
                <span className="text-xs font-mono px-2 py-0.5 rounded bg-slate-800 text-slate-300 font-bold">
                  {selectedPlayer.team}
                </span>
              </div>
              <p className="text-xs text-slate-400 mt-0.5 flex items-center gap-2">
                <span>WNBA Tracking Telemetry</span>
                <span>•</span>
                <span>Total Sampled FGA: <strong className="text-white font-mono">{selectedPlayer.total_shots}</strong></span>
              </p>
            </div>
          </div>

          <div className="flex items-center gap-3 self-end sm:self-center">
            <div className="text-right">
              <span className="text-[10px] font-mono uppercase tracking-wider text-slate-500 block font-bold">
                Telemetry Baseline
              </span>
              <span className="text-xs font-mono font-bold text-emerald-400">
                14-Zone Bayesian Prior
              </span>
            </div>
            <div className="p-2 rounded-lg bg-slate-800/80 border border-slate-700 text-indigo-400">
              <Crosshair className="w-5 h-5" />
            </div>
          </div>
        </div>
      )}

      {/* Loading & Error States */}
      {loading && (
        <div className="bg-surface-raised/40 border border-slate-800/80 rounded-2xl p-16 flex flex-col items-center justify-center space-y-3">
          <Loader2 className="w-8 h-8 text-indigo-500 animate-spin" />
          <p className="text-sm text-slate-400 font-mono">
            Loading spatial coordinates & Empirical Bayes priors...
          </p>
        </div>
      )}

      {error && !loading && (
        <div className="bg-rose-950/20 border border-rose-800/40 rounded-2xl p-8 flex items-center gap-4 text-rose-300">
          <AlertCircle className="w-6 h-6 text-rose-400 flex-shrink-0" />
          <div>
            <h4 className="font-bold text-sm">Failed to Load Shot Coordinates</h4>
            <p className="text-xs text-slate-400 mt-0.5">{error}</p>
          </div>
        </div>
      )}

      {/* Render Shot Chart Component */}
      {!loading && !error && playerShotData && (
        <PlayerShotChart
          playerData={playerShotData}
          metadata={metadata}
          initialN={100}
        />
      )}
    </div>
  );
};
