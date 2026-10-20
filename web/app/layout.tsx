import type { Metadata } from 'next';
import { GeistSans, GeistMono } from 'geist/font';
import './globals.css';
import { Sidebar } from '@/components/Sidebar';
import { SportSwitcher } from '@/components/SportSwitcher';

export const metadata: Metadata = {
  title: 'WNBA Season-Long Projections',
  description:
    'Season-long simulation projections for all 15 WNBA teams and rotation players, with RAPM/variant model analysis, player props, playoff bracket simulation, and empirical calibration diagnostics.',
};

export default function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <html lang="en" className={`dark ${GeistSans.variable} ${GeistMono.variable}`}>
      <body
        className={`${GeistSans.className} font-sans bg-slate-950 text-slate-100 min-h-screen flex flex-col md:flex-row antialiased selection:bg-indigo-600 selection:text-white`}
      >
        <Sidebar />
        <div className="flex-1 flex flex-col min-w-0 overflow-x-hidden">
          <SportSwitcher current="wnba" />
          <main className="flex-1 pb-10">{children}</main>
          <footer className="border-t border-slate-800 bg-slate-900/50 py-5 text-center text-xs text-slate-500 font-sans">
            <div className="max-w-7xl mx-auto px-4 flex flex-col sm:flex-row items-center justify-between gap-2">
              <span>WNBA Analytics — pipeline-driven season projections</span>
              <span>Standings &bull; RAPM &bull; Player Props &bull; Playoff Bracket</span>
            </div>
          </footer>
        </div>
      </body>
    </html>
  );
}
