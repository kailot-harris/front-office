import { getPlayersData } from '@/lib/data';
import { PlayersClient } from '@/components/PlayersClient';

export default function PlayersPage() {
  const players = getPlayersData();

  return (
    <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8 space-y-6">
      <div className="flex flex-col md:flex-row md:items-center justify-between gap-4 border-b border-slate-800 pb-6">
        <div>
          <h1 className="text-3xl font-black tracking-tight text-white flex items-center gap-3">
            <span>Player Projections & Outliers</span>
            <span className="text-sm font-semibold px-2.5 py-0.5 rounded-full bg-rose-500/10 text-rose-400 border border-rose-500/20">
              330 Active Rotation Players
            </span>
          </h1>
          <p className="text-slate-400 text-sm mt-1">
            Projected Games, MPG, Points, Rebounds, Assists, and Statistical Outlier Badges (|z| &gt; 2.0).
          </p>
        </div>
      </div>

      <PlayersClient players={players} />
    </div>
  );
}
