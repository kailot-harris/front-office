'use client';

import React, { useEffect, useState } from 'react';
import { PlayerShotData, ShotsMetadata } from '@/lib/shotTypes';
import { PlayerShotChart } from '@/components/PlayerShotChart';
import { TeamLogo } from '@/components/TeamLogo';
import { BASE_PATH } from '@/lib/basePath';
import { X, Crosshair, AlertCircle, Loader2 } from 'lucide-react';

interface ShotChartModalProps {
  playerId: string | null;
  playerName?: string;
  playerTeam?: string;
  onClose: () => void;
}

export const ShotChartModal: React.FC<ShotChartModalProps> = ({
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
    if (!playerId) return;

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
          throw new Error(`Shot telemetry not found for player (ID: ${playerId})`);
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
  }, [playerId]);

  if (!playerId) return null;

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center p-3 sm:p-6 bg-surface/80 backdrop-blur-md animate-in fade-in duration-200">
      <div className="relative w-full max-w-5xl max-h-[92vh] bg-surface-raised border border-slate-800 rounded-2xl shadow-2xl overflow-hidden flex flex-col">
        {/* Modal Header */}
        <div className="relative flex items-center justify-between px-6 py-4 bg-surface/60">
          <div className="flex items-center gap-3">
            {playerTeam && <TeamLogo team={playerTeam} size="sm" />}
            <div>
              <div className="flex items-center gap-2">
                <span className="w-1.5 h-1.5 rounded-full bg-orange-400 shadow-[0_0_8px_#fb923c]" />
                <h2 className="text-xl font-bold text-white tracking-tight">
                  {shotData?.player_name || playerName || 'Player'}
                </h2>
                <span className="text-xs font-mono font-semibold px-2 py-0.5 rounded bg-orange-500/10 text-orange-400 border border-orange-500/20">
                  {shotData?.team || playerTeam}
                </span>
                <span className="text-xs text-slate-400 font-mono">
                  ID: {playerId}
                </span>
              </div>
              <p className="text-xs text-slate-400 mt-0.5 flex items-center gap-1.5">
                <Crosshair className="w-3.5 h-3.5 text-orange-400" />
                <span>Spatial Shot Chart & Rolling Hot/Cold Zones</span>
              </p>
            </div>
          </div>

          <button
            onClick={onClose}
            className="p-2 text-slate-400 hover:text-white hover:bg-slate-800 rounded-xl transition-colors"
          >
            <X className="w-5 h-5" />
          </button>
          <div className="absolute bottom-0 left-0 right-0 h-[2px] bg-gradient-to-r from-orange-400 via-orange-500/40 to-transparent" />
        </div>

        {/* Modal Body */}
        <div className="flex-1 overflow-y-auto p-6">
          {loading && (
            <div className="h-96 flex flex-col items-center justify-center gap-3 text-slate-400">
              <Loader2 className="w-8 h-8 animate-spin text-indigo-500" />
              <p className="text-sm font-medium">Fetching telemetry & computing rolling zones...</p>
            </div>
          )}

          {error && (
            <div className="h-96 flex flex-col items-center justify-center gap-3 text-slate-400">
              <AlertCircle className="w-10 h-10 text-rose-500" />
              <div className="text-center">
                <p className="text-white font-semibold">{error}</p>
                <p className="text-xs text-slate-500 mt-1">
                  This player may not have sufficient field goal attempts recorded in the sampled catalog.
                </p>
              </div>
            </div>
          )}

          {!loading && !error && shotData && metadata && (
            <PlayerShotChart playerData={shotData} metadata={metadata} initialN={100} />
          )}
        </div>
      </div>
    </div>
  );
};
