import type { Metadata } from 'next';
import { GeistSans, GeistMono } from 'geist/font';
import './globals.css';
import { Sidebar } from '@/components/Sidebar';

export const metadata: Metadata = {
  title: 'MLB Sabermetric Projections | 162-Game & 10,000-Sim Postseason Engine',
  description:
    'Quantitative MLB projections across all 30 franchises, 630 batters, and 649 pitchers featuring 4-Factor Starting-Pitcher Elo, Hierarchical Empirical Bayes Partial Pooling, Pythagenpat Run-Expectation, Marcel 3-Year Projections, Bullpen Fatigue Diagnostics, and 12-Team Postseason Monte Carlo Simulations.',
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
          <main className="flex-1 pb-10">{children}</main>
          <footer className="border-t border-slate-800 bg-slate-900/50 py-5 text-center text-xs text-slate-500 font-sans">
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
