import type { Metadata, Viewport } from 'next';
import { GeistSans, GeistMono } from 'geist/font';
import './globals.css';
import { BASE_PATH } from '@/lib/basePath';
import { Sidebar } from '@/components/Sidebar';
import { SportSwitcher } from '@/components/SportSwitcher';
import { getMetadata } from '@/lib/data';

// Link previews (Discord, X, iMessage) need absolute URLs. metadataBase supplies
// the origin; BASE_PATH supplies /front-office/wnba, because Next's basePath does
// not rewrite hand-written paths like the image below. No canonical or og:url is
// set here: this layout wraps every route, and both would point them all at home.
const SOCIAL_TITLE = 'WNBA Analytics: Projections, Player DNA & 2026 Bracket';
const SOCIAL_DESCRIPTION =
  'Season projections for all 15 WNBA teams with RAPM-based player models, shot charts, coaching impact, the 2026 bracket and a weekly off-season monitor.';
const SOCIAL_IMAGE = `${BASE_PATH}/social/og-card.png`;

export const metadata: Metadata = {
  metadataBase: new URL('https://kailot-harris.github.io'),
  // Issue #122: a route-level `export const metadata` without its own
  // `title` falls back to this template rather than silently inheriting the
  // bare default string, so every route's <title> stays distinct in browser
  // tabs, search results, and link previews.
  title: {
    template: '%s | WNBA Front Office',
    default: 'WNBA Season-Long Projections',
  },
  // Issue #135: trimmed from 205 characters (measured in this worktree) to
  // stay under the ~155-160 char search-snippet limit, while still leading
  // with what a visitor can do here and preserving the original's meaning.
  description:
    'Explore WNBA season projections for all 15 teams: RAPM player ratings, Player DNA fingerprints, bracket simulations, and calibration diagnostics.',
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

// Issue #135: no `viewport.themeColor` meant mobile browser chrome (the
// address bar / status bar tint on Android Chrome, PWA splash background)
// didn't match the app at all. This is the real `surface` token from
// tailwind.config.ts (#100a22), not an invented color.
export const viewport: Viewport = {
  themeColor: '#100a22',
};

export default function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  const { generated_at } = getMetadata();
  return (
    <html lang="en" className={`dark ${GeistSans.variable} ${GeistMono.variable}`}>
      <body
        className={`${GeistSans.className} font-sans bg-surface text-slate-100 min-h-screen flex flex-col md:flex-row antialiased selection:bg-accent-600 selection:text-white`}
      >
        {/* Issue #136: keyboard/screen-reader users had no way to bypass the
            sidebar nav on every single page. Visually hidden until focused
            (first Tab press), then jumps straight to <main>. */}
        <a
          href="#main-content"
          className="sr-only focus:not-sr-only focus:fixed focus:top-2 focus:left-2 focus:z-[100] focus:px-4 focus:py-2 focus:rounded-lg focus:bg-accent-600 focus:text-white focus:text-sm focus:font-semibold focus:shadow-xl"
        >
          Skip to main content
        </a>
        <Sidebar generatedAt={generated_at} />
        <div className="flex-1 flex flex-col min-w-0 overflow-x-hidden">
          <SportSwitcher current="wnba" />
          <main id="main-content" tabIndex={-1} className="flex-1 pb-10">{children}</main>
          <footer className="border-t border-slate-800 bg-surface-raised/50 py-5 text-center text-xs text-slate-500 font-sans">
            <div className="max-w-7xl mx-auto px-4 flex flex-col sm:flex-row items-center justify-between gap-2">
              <span>WNBA Analytics — pipeline-driven season projections</span>
              <span>Standings &bull; RAPM &bull; Player DNA & Projections &bull; Playoff Bracket</span>
            </div>
          </footer>
        </div>
      </body>
    </html>
  );
}
