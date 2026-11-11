import type { Metadata, Viewport } from 'next';
import { GeistSans, GeistMono } from 'geist/font';
import './globals.css';
import { BASE_PATH } from '@/lib/basePath';
import { Sidebar } from '@/components/Sidebar';
import { SportSwitcher } from '@/components/SportSwitcher';
import { getStandingsData } from '@/lib/data';

// Link previews (Discord, X, iMessage) need absolute URLs. metadataBase supplies
// the origin; BASE_PATH supplies /front-office/nfl, because Next's basePath does
// not rewrite hand-written paths like the image below. No canonical or og:url is
// set here: this layout wraps every route, and both would point them all at home.
const SOCIAL_TITLE = 'NFL Analytics: Season Projections & Playoff Machine';
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
  themeColor: '#04140f',
};

export default function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  const { generated_at } = getStandingsData();
  return (
    <html lang="en" className={`dark ${GeistSans.variable} ${GeistMono.variable}`}>
      <body
        className={`${GeistSans.className} font-sans bg-surface text-slate-100 min-h-screen flex flex-col md:flex-row antialiased selection:bg-accent-600 selection:text-white`}
      >
        {/*
          #136: skip-to-content link. Visually hidden until focused (keyboard Tab from page
          load), then jumps straight past the sidebar/sport-switcher chrome to <main>. Every
          page's main content region is given id="main-content" below.
        */}
        <a
          href="#main-content"
          className="sr-only focus:not-sr-only focus:fixed focus:top-2 focus:left-2 focus:z-[100] focus:px-4 focus:py-2 focus:rounded-lg focus:bg-accent-600 focus:text-white focus:text-sm focus:font-semibold focus:shadow-lg"
        >
          Skip to content
        </a>
        <Sidebar generatedAt={generated_at} />
        <div className="flex-1 flex flex-col min-w-0 overflow-x-hidden">
          <SportSwitcher current="nfl" />
          <main id="main-content" className="flex-1 pb-10">{children}</main>
          <footer className="border-t border-slate-800 bg-surface-raised/50 py-5 text-center text-xs text-slate-400 font-sans">
            <div className="max-w-7xl mx-auto px-4 flex flex-col sm:flex-row items-center justify-between gap-2">
              <span>NFL Season Projections System • 1,000-Season Monte Carlo</span>
              <span>Ensemble Architecture (Ridge Massey + Elo + EPA Situational + Market Blend)</span>
            </div>
          </footer>
        </div>
      </body>
    </html>
  );
}
