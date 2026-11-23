import type { Metadata, Viewport } from 'next';
import { GeistSans, GeistMono } from 'geist/font';
import './design-tokens.css';
import './palette.css';
import './globals.css';
import { BASE_PATH } from '@/lib/basePath';
import { Sidebar } from '@/components/Sidebar';
import { SwitchArrivalNote } from '@/components/SportSwitcher';
import fs from 'fs';
import path from 'path';
import { getStandingsData } from '@/lib/data';

/**
 * `season_state` from the published landing digest (#221), read at build time.
 * Missing file or field -> undefined, so the sidebar uses the plain NAV_ORDER.
 */
function getSeasonState(): string | undefined {
  const filePath = path.join(process.cwd(), 'public', 'data', 'landing_digest.json');
  if (!fs.existsSync(filePath)) return undefined;
  try {
    const parsed = JSON.parse(fs.readFileSync(filePath, 'utf-8')) as { season_state?: unknown };
    return typeof parsed.season_state === 'string' ? parsed.season_state : undefined;
  } catch {
    return undefined;
  }
}

// Link previews (Discord, X, iMessage) need absolute URLs. metadataBase supplies
// the origin; BASE_PATH supplies /front-office/nfl, because Next's basePath does
// not rewrite hand-written paths like the image below. No canonical or og:url is
// set here: this layout wraps every route, and both would point them all at home.
const SOCIAL_TITLE = 'NFL Analytics: Season Projections & Playoff Simulator';
const SOCIAL_DESCRIPTION =
  '1,000-season Monte Carlo projections for all 32 NFL teams: weekly matchups, EPA efficiency, QB ratings, salary cap and a 14-team playoff machine.';
const SOCIAL_IMAGE = `${BASE_PATH}/social/og-card.png`;

export const metadata: Metadata = {
  metadataBase: new URL('https://kailot-harris.github.io'),
  title: {
    template: '%s | NFL Front Office',
    default: 'NFL Analytics & Season Projections | 1,000-Sim Monte Carlo',
  },
  description:
    '1,000-season Monte Carlo projections for all 32 NFL teams, weekly matchups, EPA/play efficiency, 14-team playoff machine, and model diagnostics.',
  openGraph: {
    type: 'website',
    siteName: 'Front Office',
    title: SOCIAL_TITLE,
    description: SOCIAL_DESCRIPTION,
    images: [{ url: SOCIAL_IMAGE, width: 1200, height: 630, alt: SOCIAL_TITLE }],
  },
  twitter: {
    card: 'summary_large_image',
    title: SOCIAL_TITLE,
    description: SOCIAL_DESCRIPTION,
    images: [SOCIAL_IMAGE],
  },
};

// #135: no theme-color was set, so mobile browser chrome (address bar, task switcher card)
// didn't match the app. tailwind.config.ts's `surface` token (#04140f) is this app's actual
// background color — reuse it rather than picking an arbitrary accent.
export const viewport: Viewport = {
  // Matches --fo-surface for data-site="nfl" in each scheme.
  colorScheme: 'light dark',
  themeColor: [
    { media: '(prefers-color-scheme: light)', color: '#f2f9f6' },
    { media: '(prefers-color-scheme: dark)', color: '#04140f' },
  ],
};

export default function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  const { generated_at } = getStandingsData();
  const seasonState = getSeasonState();
  return (
    <html lang="en" data-site="nfl" className={`${GeistSans.variable} ${GeistMono.variable}`}>
      <body
        className={`${GeistSans.className} font-sans bg-surface text-slate-100 min-h-screen flex flex-col md:flex-row antialiased selection:bg-fo-accent selection:text-on-accent`}
      >
        {/*
          #136: skip-to-content link. Visually hidden until focused (keyboard Tab from page
          load), then jumps straight past the sidebar/sport-switcher chrome to <main>. Every
          page's main content region is given id="main-content" below.
        */}
        <a
          href="#main-content"
          className="sr-only focus:not-sr-only focus:fixed focus:top-2 focus:left-2 focus:z-[100] focus:px-4 focus:py-2 focus:rounded-lg focus:bg-fo-accent focus:text-on-accent focus:text-sm focus:font-semibold focus:shadow-lg"
        >
          Skip to content
        </a>
        <Sidebar generatedAt={generated_at} seasonState={seasonState} />
        <div className="flex-1 flex flex-col min-w-0 overflow-x-hidden">
          <SwitchArrivalNote current="nfl" />
          <main id="main-content" className="flex-1 pb-10">{children}</main>
          <footer className="border-t border-slate-800 bg-surface-raised/50 py-5 text-center text-xs text-slate-400 font-sans">
            <div className="max-w-7xl mx-auto px-4 flex flex-col sm:flex-row items-center justify-between gap-2">
              <span>NFL Season Projections System • 1,000-Season Monte Carlo</span>
              <span>Ensemble Architecture (EPA-based Ridge Massey + Dynamic Elo)</span>
            </div>
          </footer>
        </div>
      </body>
    </html>
  );
}
