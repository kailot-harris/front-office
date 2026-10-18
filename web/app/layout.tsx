import type { Metadata } from 'next';
import { Inter } from 'next/font/google';
import './globals.css';
import { Sidebar } from '@/components/Sidebar';

const inter = Inter({ subsets: ['latin'] });

export const metadata: Metadata = {
  title: 'NBA Season-Long Projections | 1,000-Season Monte Carlo',
  description:
    '1,000-season Monte Carlo simulation projections for all 30 NBA teams and 330 rotation players with multi-model variant analysis, divergence metrics, outlier flags, and empirical calibration diagnostics.',
};

export default function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <html lang="en" className="dark">
      <body
        className={`${inter.className} bg-slate-950 text-slate-100 min-h-screen flex flex-col md:flex-row antialiased selection:bg-indigo-600 selection:text-white`}
      >
        <Sidebar />
        <div className="flex-1 flex flex-col min-w-0 overflow-x-hidden">
          <main className="flex-1 pb-10">{children}</main>
          <footer className="border-t border-slate-800 bg-slate-900/50 py-5 text-center text-xs text-slate-500">
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
