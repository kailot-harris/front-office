import { getPlayersData } from '@/lib/data';
import { PlayersClient } from '@/components/PlayersClient';
import { SeasonSourceBadge } from '@/components/SeasonSourceBadge';
import { SEASON_SOURCES } from '@/lib/season';

export default function PlayersPage() {
  const players = getPlayersData();

  return (
    <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8 space-y-6">
      <div className="relative pb-6">
        <div className="flex flex-col md:flex-row md:items-center justify-between gap-4">
          <div>
            <h1 className="text-3xl font-black tracking-tight text-white flex items-center gap-3">
              <span><span className="text-orange-400">NBA</span> Player Projections & Outliers</span>
              <span className="text-sm font-semibold px-2.5 py-0.5 rounded-full bg-rose-500/10 text-rose-400 border border-rose-500/20">
                330 Active Rotation Players
              </span>
              <SeasonSourceBadge
                season={SEASON_SOURCES.playerProjections.season}
                kind="projection"
                label="Projected season"
                title={SEASON_SOURCES.playerProjections.note}
              />
            </h1>
            <p className="text-slate-400 text-sm mt-1">
              Projected 2026-2027 Games, MPG, Points, Rebounds, Assists, and Statistical Outlier Badges (|z| &gt; 2.0).
            </p>
          </div>
        </div>
        <div className="w-full h-[2px] bg-gradient-to-r from-orange-400 via-orange-500/40 to-transparent mt-4" />
      </div>

      <PlayersClient players={players} />
    </div>
  );
}
