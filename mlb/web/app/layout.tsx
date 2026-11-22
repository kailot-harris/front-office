import fs from 'fs';
import path from 'path';
import type { Metadata, Viewport } from 'next';
import { GeistSans, GeistMono } from 'geist/font';
import './globals.css';
import { BASE_PATH } from '@/lib/basePath';
import { Sidebar } from '@/components/Sidebar';
import { SportSwitcher } from '@/components/SportSwitcher';
import { getMetadata } from '@/lib/data';

// Link previews (Discord, X, iMessage) need absolute URLs. metadataBase supplies
// the origin; BASE_PATH supplies /front-office/mlb, because Next's basePath does
// not rewrite hand-written paths like the image below. No canonical or og:url is
// set here: this layout wraps every route, and both would point them all at home.
const SOCIAL_TITLE = 'MLB Analytics: Sabermetric Projections & Postseason Simulator';
const SOCIAL_DESCRIPTION =
  '162-game projections for all 30 MLB clubs, 1,279 player forecasts, luxury tax sheets, spatial analytics and a 10,000-run postseason simulator.';
const SOCIAL_IMAGE = `${BASE_PATH}/social/og-card.png`;

export const metadata: Metadata = {
  metadataBase: new URL('https://kailot-harris.github.io'),
  title: {
    template: '%s | MLB Front Office',
    default: 'MLB Sabermetric Projections | 162-Game & 10,000-Sim Postseason Engine',
  },
  description:
    'Explore MLB projections for 30 teams, 630 batters, and 649 pitchers using pitcher Elo, empirical Bayes, Pythagenpat, and a 10,000-run postseason simulator.',
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

export const viewport: Viewport = {
  // Matches --fo-surface for data-site="mlb" in each colour scheme.
  themeColor: [
    { media: '(prefers-color-scheme: light)', color: '#f2f7fc' },
    { media: '(prefers-color-scheme: dark)', color: '#040a1a' },
  ],
  colorScheme: 'light dark',
};

/** season_state from the published landing digest; undefined if absent (#221). */
function readSeasonState(): string | undefined {
  try {
    const raw = fs.readFileSync(path.join(process.cwd(), 'public', 'data', 'landing_digest.json'), 'utf-8');
    const state = (JSON.parse(raw) as { season_state?: unknown }).season_state;
    return typeof state === 'string' ? state : undefined;
  } catch {
    return undefined;
  }
}

export default function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  const { generated_at } = getMetadata();
  return (
    <html lang="en" data-site="mlb" className={`${GeistSans.variable} ${GeistMono.variable}`}>
      <body
        className={`${GeistSans.className} font-sans bg-surface text-slate-100 min-h-screen flex flex-col md:flex-row antialiased selection:bg-accent-600 selection:text-fo-on-accent`}
      >
        <a
          href="#main-content"
          className="sr-only focus:not-sr-only focus:absolute focus:left-3 focus:top-3 focus:z-[100] focus:rounded-lg focus:bg-accent-600 focus:px-4 focus:py-2 focus:text-sm focus:font-bold focus:text-fo-on-accent focus:shadow-xl"
        >
          Skip to content
        </a>
        <Sidebar generatedAt={generated_at} seasonState={readSeasonState()} />
        <div className="flex-1 flex flex-col min-w-0 overflow-x-hidden">
          <SportSwitcher current="mlb" />
          <main id="main-content" className="flex-1 pb-10">{children}</main>
          <footer className="border-t border-slate-800 bg-surface-raised/50 py-5 text-center text-xs text-slate-400 font-sans">
            <div className="max-w-7xl mx-auto px-4 flex flex-col sm:flex-row items-center justify-between gap-2">
              <span>MLB Quantitative Sabermetric Engine • 162-Game & 10,000-Sim Postseason Monte Carlo</span>
              <span>4 Model Variants (Pitcher Elo, Empirical Bayes, Pythagenpat, Marcel/Bullpen) + Ensemble</span>
            </div>
          </footer>
        </div>
      </body>
    </html>
  );
}
