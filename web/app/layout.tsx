import type { Metadata } from 'next';
import { GeistSans, GeistMono } from 'geist/font';
import './globals.css';
import { BASE_PATH } from '@/lib/basePath';
import { Sidebar } from '@/components/Sidebar';
import { SportSwitcher } from '@/components/SportSwitcher';
import { getDiagnostics, getMetadata } from '@/lib/data';

// Link previews (Discord, X, iMessage) need absolute URLs. metadataBase supplies
// the origin; BASE_PATH supplies /front-office/nba, because Next's basePath does
// not rewrite hand-written paths like the image below. No canonical or og:url is
// set here: this layout wraps every route, and both would point them all at home.
const SOCIAL_TITLE = 'NBA Analytics: Projections, Cap & Aprons, Playoff Simulator';
const SOCIAL_DESCRIPTION =
  'Season simulations for all 30 NBA teams and 330 rotation players, with cap and apron sheets, shot charts, a clutch index and a playoff series simulator.';
const SOCIAL_IMAGE = `${BASE_PATH}/social/og-card.png`;

export const metadata: Metadata = {
  metadataBase: new URL('https://kailot-harris.github.io'),
  title: {
    template: '%s | NBA Front Office',
    default: 'NBA Season-Long Projections | 1,000-Season Monte Carlo',
  },
  description:
    '1,000-season Monte Carlo simulation projections for all 30 NBA teams and 330 rotation players with multi-model variant analysis, divergence metrics, outlier flags, and empirical calibration diagnostics.',
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

export default function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  const { generated_at } = getMetadata();
  const { brierScore } = getDiagnostics();
  return (
    <html lang="en" className={`dark ${GeistSans.variable} ${GeistMono.variable}`}>
      <body
        className={`${GeistSans.className} font-sans bg-surface text-slate-100 min-h-screen flex flex-col md:flex-row antialiased selection:bg-accent-600 selection:text-white`}
      >
        <Sidebar generatedAt={generated_at} brierScore={brierScore} />
        <div className="flex-1 flex flex-col min-w-0 overflow-x-hidden">
          <SportSwitcher current="nba" />
          <main className="flex-1 pb-10">{children}</main>
          <footer className="border-t border-slate-800 bg-surface-raised/50 py-5 text-center text-xs text-slate-500 font-sans">
            <div className="max-w-7xl mx-auto px-4 flex flex-col sm:flex-row items-center justify-between gap-2">
              <span>NBA Season-Long Projections System • 1,000 Monte Carlo Simulations</span>
              <span>4 Model Variants (Bottom-Up, RAPM, Fatigue, Embeddings) + Ensemble</span>
            </div>
          </footer>
        </div>
      </body>
    </html>
  );
}
