const repoBase = process.env.PAGES_BASE_PATH ?? '';

const SPORTS = [
  { slug: 'nfl', label: 'NFL' },
  { slug: 'nba', label: 'NBA' },
  { slug: 'mlb', label: 'MLB' },
  { slug: 'wnba', label: 'WNBA' },
] as const;

const PIP_COLORS: Record<(typeof SPORTS)[number]['slug'], string> = {
  nba: '#fb923c',
  nfl: '#34d399',
  mlb: '#38bdf8',
  wnba: '#a78bfa',
};

export const SportSwitcher: React.FC<{ current: (typeof SPORTS)[number]['slug'] }> = ({ current }) => (
  <nav
    aria-label="Switch sport"
    className="relative md:sticky md:top-0 z-20 bg-surface-raised/95 backdrop-blur-md border-b border-slate-800 px-4 py-2 flex items-center justify-end gap-2"
  >
    <span className="hidden sm:inline text-[10px] font-bold uppercase tracking-wider text-slate-500 font-mono mr-1">
      Sports
    </span>
    {SPORTS.map(({ slug, label }) => {
      const isCurrent = slug === current;
      const pipHex = PIP_COLORS[slug];
      return (
        <a
          key={slug}
          href={`${repoBase}/${slug}/`}
          aria-current={isCurrent ? 'page' : undefined}
          title={isCurrent ? `${label} Analytics (current)` : `Open ${label} Analytics`}
          className={`flex items-center gap-2 px-2.5 py-1.5 rounded-lg text-xs font-semibold transition-all ${
            isCurrent
              ? 'bg-accent-600 text-white shadow-md shadow-accent-600/30'
              : 'text-slate-300 hover:text-white hover:bg-slate-800/60'
          }`}
        >
          {isCurrent && (
            <span
              className="w-1.5 h-1.5 rounded-full"
              style={{ backgroundColor: pipHex, boxShadow: `0 0 8px ${pipHex}` }}
            />
          )}
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img src={`${repoBase}/${current}/sport-icons/${slug}.png`} alt="" width={20} height={20} className="w-5 h-5 rounded" />
          <span>{label}</span>
        </a>
      );
    })}
    <div className="absolute bottom-0 left-0 right-0 h-[2px] bg-gradient-to-r from-accent-400 via-accent-500/40 to-transparent" />
  </nav>
);
