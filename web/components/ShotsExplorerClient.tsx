'use client';

import React, { useState, useEffect, useMemo } from 'react';
import { PlayerCatalogEntry, PlayerShotData, ShotsMetadata } from '@/lib/shotTypes';
import { PlayerShotChart } from '@/components/PlayerShotChart';
import { TeamLogo } from '@/components/TeamLogo';
import { NBA_TEAMS_METADATA } from '@/lib/teams';
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
  // Default to Luka Doncic (3945274) or first catalog entry
  const defaultPlayer = useMemo(() => {
    if (initialPlayerId) {
      const match = catalog.find((c) => c.player_id === initialPlayerId);
      if (match) return match;
    }
    const luka = catalog.find((c) => c.player_name.includes('Doncic'));
    return luka || catalog[0];
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

  // Featured marquee stars for quick-select pills
  const featuredStars = useMemo(() => {
    const starNames = [
      'Luka Doncic',
      'Shai Gilgeous-Alexander',
      'Nikola Jokic',
      'Giannis Antetokounmpo',
      'Anthony Edwards',
      'Jaylen Brown',
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
        if (!res.ok) throw new Error(`Could not load shots for ${selectedPlayer.player_name}`);
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
      {/* Player Selection Header */}
      <div className="bg-surface-raised/80 border border-slate-800 rounded-2xl p-6 shadow-xl space-y-4">
        <div className="flex flex-col lg:flex-row lg:items-center justify-between gap-4">
          <div>
            <h2 className="text-xl font-bold text-white flex items-center gap-2">
              <Crosshair className="w-5 h-5 text-indigo-400" />
              <span>Select Player Telemetry</span>
            </h2>
            <p className="text-xs text-slate-400 mt-0.5">
              Explore spatial shot distributions, prior-N momentum, and Empirical Bayes hot/cold zones.
            </p>
          </div>

          {/* Quick-Select Featured Star Pills */}
          <div className="flex flex-wrap items-center gap-2">
            <span className="text-xs text-slate-400 font-semibold uppercase tracking-wider flex items-center gap-1">
              <Sparkles className="w-3.5 h-3.5 text-amber-400" />
              <span>Marquee:</span>
            </span>
            {featuredStars.map((star) => {
              const isSelected = selectedPlayer?.player_id === star.player_id;
              return (
                <button
                  key={star.player_id}
                  onClick={() => setSelectedPlayer(star)}
                  className={`px-3 py-1 rounded-full text-xs font-semibold transition-all flex items-center gap-1.5 ${
                    isSelected
                      ? 'bg-accent-600 text-white font-bold shadow-md shadow-accent-600/20'
                      : 'bg-surface text-slate-300 border border-slate-800 hover:border-slate-700 hover:text-white'
                  }`}
                >
                  <TeamLogo team={star.team} size="xs" />
                  <span>{star.player_name.split(' ').pop()}</span>
                </button>
              );
            })}
          </div>
        </div>

        {/* Search & Team Filter Controls */}
        <div className="grid grid-cols-1 sm:grid-cols-12 gap-3 pt-2 border-t border-slate-800/80">
          <div className="sm:col-span-6 relative">
            <Search className="w-4 h-4 text-slate-400 absolute left-3 top-1/2 -translate-y-1/2" />
            <input
              type="text"
              value={searchTerm}
              onChange={(e) => setSearchTerm(e.target.value)}
              placeholder="Search by player name or team..."
              className="w-full pl-9 pr-4 py-2 bg-surface border border-slate-800 rounded-xl text-sm text-white placeholder-slate-500 focus:outline-none focus:border-indigo-500"
            />
          </div>

          <div className="sm:col-span-3">
            <select
              value={selectedTeam}
              onChange={(e) => {
                const newTeam = e.target.value;
                setSelectedTeam(newTeam);
                // Auto-select first player from newly selected team
                const pool = catalog.filter((p) => newTeam === 'All' || p.team === newTeam);
                if (pool.length > 0 && (!selectedPlayer || (newTeam !== 'All' && selectedPlayer.team !== newTeam))) {
                  setSelectedPlayer(pool[0]);
                }
              }}
              className="w-full px-3 py-2 bg-surface border border-slate-800 rounded-xl text-sm text-white focus:outline-none focus:border-indigo-500"
            >
              {teams.map((tm) => {
                const meta = NBA_TEAMS_METADATA[tm];
                const label = tm === 'All' ? 'All Teams (30 Teams)' : `${tm} - ${meta?.fullName || meta?.name || tm}`;
                return (
                  <option key={tm} value={tm}>
                    {label}
                  </option>
                );
              })}
            </select>
          </div>

          <div className="sm:col-span-3">
            <select
              value={selectedPlayer?.player_id || ''}
              onChange={(e) => {
                const found = catalog.find((c) => c.player_id === e.target.value);
                if (found) setSelectedPlayer(found);
              }}
              className="w-full px-3 py-2 bg-surface border border-slate-800 rounded-xl text-sm text-white focus:outline-none focus:border-indigo-500"
            >
              {filteredCatalog.map((p) => (
                <option key={p.player_id} value={p.player_id}>
                  {p.player_name} ({p.team}) - {p.total_shots} shots
                </option>
              ))}
            </select>
          </div>
        </div>
      </div>

      {/* Main Shot Chart Container */}
      <div className="bg-surface-raised/60 border border-slate-800 rounded-2xl p-6 shadow-2xl">
        {loading && (
          <div className="h-96 flex flex-col items-center justify-center gap-3 text-slate-400">
            <Loader2 className="w-8 h-8 animate-spin text-indigo-500" />
            <p className="text-sm font-medium">Fetching player shot telemetry & mapping rolling zones...</p>
          </div>
        )}

        {error && (
          <div className="h-96 flex flex-col items-center justify-center gap-3 text-slate-400">
            <AlertCircle className="w-10 h-10 text-rose-500" />
            <div className="text-center">
              <p className="text-white font-semibold">{error}</p>
              <p className="text-xs text-slate-500 mt-1">Please select another player.</p>
            </div>
          </div>
        )}

        {!loading && !error && playerShotData && (
          <PlayerShotChart playerData={playerShotData} metadata={metadata} initialN={100} />
        )}
      </div>
    </div>
  );
};
