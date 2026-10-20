'use client';

import React, { useEffect, useState } from 'react';
import { PlayerShotData, ShotsMetadata } from '@/lib/shotTypes';
import { PlayerShotChart } from '@/components/PlayerShotChart';
import { TeamLogo } from '@/components/TeamLogo';
import { BASE_PATH } from '@/lib/basePath';
import { Crosshair, AlertCircle, Loader2, ChevronUp } from 'lucide-react';

interface InlinePlayerShotCardProps {
  playerId: string;
  playerName: string;
  playerTeam: string;
  onClose: () => void;
}

export const InlinePlayerShotCard: React.FC<InlinePlayerShotCardProps> = ({
  playerId,
  playerName,
  playerTeam,
  onClose,
}) => {
  const [loading, setLoading] = useState<boolean>(true);
  const [shotData, setShotData] = useState<PlayerShotData | null>(null);
  const [metadata, setMetadata] = useState<ShotsMetadata | null>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    let isMounted = true;
    setLoading(true);
    setError(null);

    const loadData = async () => {
      try {
        const [shotsRes, metaRes] = await Promise.all([
          fetch(`${BASE_PATH}/data/shots/${playerId}.json`),
          fetch(`${BASE_PATH}/data/shots_metadata.json`),
        ]);

        if (!shotsRes.ok) {
          throw new Error(`Shot telemetry not found for ${playerName} (ID: ${playerId})`);
        }
        if (!metaRes.ok) {
          throw new Error('League shot metadata unavailable');
        }

        const shotsJson: PlayerShotData = await shotsRes.json();
        const metaJson: ShotsMetadata = await metaRes.json();

        if (isMounted) {
          setShotData(shotsJson);
          setMetadata(metaJson);
          setLoading(false);
        }
      } catch (err: unknown) {
        if (isMounted) {
          const msg = err instanceof Error ? err.message : 'Failed to load shot data';
          setError(msg);
          setLoading(false);
        }
      }
    };

    loadData();

    return () => {
      isMounted = false;
    };
  }, [playerId, playerName]);

  return (
    <div className="rounded-2xl bg-surface-raised/95 border border-indigo-500/30 p-5 shadow-2xl space-y-5 animate-in fade-in slide-in-from-top-2 duration-200">
      {/* Inline Header */}
      <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-3 pb-4 border-b border-slate-800">
        <div className="flex items-center gap-3">
          <TeamLogo team={playerTeam} size="sm" />
          <div>
            <div className="flex items-center gap-2">
              <span className="text-lg font-bold text-white tracking-tight">{playerName}</span>
              <span className="text-xs font-mono font-bold px-2 py-0.5 rounded bg-amber-500/10 text-amber-400 border border-amber-500/20">
                {playerTeam}
              </span>
              <span className="text-xs font-mono text-slate-400">ID: {playerId}</span>
            </div>
            <p className="text-xs text-slate-400 flex items-center gap-1.5 mt-0.5">
              <Crosshair className="w-3.5 h-3.5 text-indigo-400" />
              <span>Spatial Shot Chart & Rolling Hot/Cold Zones</span>
            </p>
          </div>
        </div>

        <button
          onClick={onClose}
          className="inline-flex items-center gap-1 px-3 py-1.5 rounded-lg text-xs font-semibold text-slate-400 hover:text-white bg-slate-800/80 hover:bg-slate-700/80 border border-slate-700 transition-all self-start sm:self-auto"
        >
          <ChevronUp className="w-4 h-4" />
          <span>Collapse Shot Chart</span>
        </button>
      </div>

      {/* Body Content */}
      {loading && (
        <div className="h-64 flex flex-col items-center justify-center gap-3 text-slate-400">
          <Loader2 className="w-7 h-7 animate-spin text-indigo-500" />
          <p className="text-xs font-medium">Loading player shot coordinates & calculating zones...</p>
        </div>
      )}

      {error && (
        <div className="h-56 flex flex-col items-center justify-center gap-2 text-slate-400">
          <AlertCircle className="w-8 h-8 text-rose-500" />
          <div className="text-center">
            <p className="text-sm font-semibold text-white">{error}</p>
            <p className="text-xs text-slate-500 mt-0.5">
              No recent field goal attempts recorded in the sampled catalog.
            </p>
          </div>
        </div>
      )}

      {!loading && !error && shotData && metadata && (
        <PlayerShotChart playerData={shotData} metadata={metadata} initialN={100} />
      )}
    </div>
  );
};
