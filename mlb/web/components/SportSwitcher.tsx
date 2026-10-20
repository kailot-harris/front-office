const repoBase = process.env.PAGES_BASE_PATH ?? '';

const SPORTS = [
  { slug: 'nfl', label: 'NFL' },
  { slug: 'nba', label: 'NBA' },
  { slug: 'mlb', label: 'MLB' },
  { slug: 'wnba', label: 'WNBA' },
] as const;

export const SportSwitcher: React.FC<{ current: (typeof SPORTS)[number]['slug'] }> = ({ current }) => (
  <nav
    aria-label="Switch sport"
    className="md:sticky md:top-0 z-20 bg-slate-900/95 backdrop-blur-md border-b border-slate-800 px-4 py-2 py-2 flex items-center justify-end gap-2"
  >
    <span className="hidden sm:inline text-[10px] font-bold uppercase tracking-wider text-slate-500 font-mono mr-1">
      Sports
    </span>
    {SPORTS.map(({ slug, label }) => {
      const isCurrent = slug === current;
      return (
        <a
          key={slug}
          href={`${repoBase}/${slug}/`}
          aria-current={isCurrent ? 'page' : undefined}
          title={isCurrent ? `${label} Analytics (current)` : `Open ${label} Analytics`}
          className={`flex items-center gap-2 px-2.5 py-1.5 rounded-lg text-xs font-semibold transition-all ${
            isCurrent
              ? 'bg-emerald-600 text-white shadow-md shadow-emerald-600/30'
              : 'text-slate-300 hover:text-white hover:bg-slate-800/60'
          }`}
        >
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img src={`${repoBase}/${current}/sport-icons/${slug}.svg`} alt="" width={20} height={20} className="w-5 h-5 rounded" />
          <span>{label}</span>
        </a>
      );
    })}
  </nav>
);
