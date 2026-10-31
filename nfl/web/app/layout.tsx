import type { Metadata } from 'next';
import { GeistSans, GeistMono } from 'geist/font';
import './globals.css';
import { Sidebar } from '@/components/Sidebar';
import { SportSwitcher } from '@/components/SportSwitcher';
import { getStandingsData } from '@/lib/data';

export const metadata: Metadata = {
  title: 'NFL Analytics & Season Projections | 1,000-Sim Monte Carlo',
  description:
    '1,000-season Monte Carlo simulation projections for all 32 NFL teams, weekly matchup spreads, EPA/play efficiency, 14-team playoff machine, and model diagnostics.',
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
        <Sidebar generatedAt={generated_at} />
        <div className="flex-1 flex flex-col min-w-0 overflow-x-hidden lg:pl-64">
          <SportSwitcher current="nfl" />
          <main className="flex-1 pb-10">{children}</main>
          <footer className="border-t border-slate-800 bg-surface-raised/50 py-5 text-center text-xs text-slate-500 font-sans">
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
