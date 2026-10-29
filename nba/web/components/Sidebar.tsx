'use client';

import React, { useState } from 'react';
import Link from 'next/link';
import { usePathname } from 'next/navigation';
import {
  Trophy,
  BarChart3,
  Users,
  Activity,
  Menu,
  X,
  ShieldCheck,
  Layers,
  HelpCircle,
  Calculator,
  Shuffle,
  Crosshair,
  Briefcase,
  Swords,
  Coins,
  Dna,
  Flame,
  CalendarDays,
} from 'lucide-react';
import { BASE_PATH } from '@/lib/basePath';

export interface SidebarProps {
  generatedAt?: string;
}

export const Sidebar: React.FC<SidebarProps> = ({ generatedAt }) => {
  const pathname = usePathname();
  const [isOpen, setIsOpen] = useState(false);
  const [showSigmaExplainer, setShowSigmaExplainer] = useState(false);

  const navItems = [
    {
      href: '/',
      label: 'Season Standings',
      badge: '30 Teams',
      icon: Trophy,
      desc: 'Win distributions & franchise table',
    },
    {
      href: '/offseason',
      label: 'Offseason Moves',
      badge: 'Trades • FA • Draft',
      icon: Shuffle,
      desc: 'Impact analysis & trade machine',
    },
    {
      href: '/cap-sheet',
      label: 'Cap & Aprons',
      badge: 'CBA 2026-2027',
      icon: Coins,
      desc: 'Apron handcuffs & tax brackets',
    },
    {
      href: '/variants',
      label: 'Model Variants',
      badge: '4 Engines',
      icon: BarChart3,
      desc: 'Divergence matrix & weights',
    },
    {
      href: '/players',
      label: 'Player Projections',
      badge: '330 Pool',
      icon: Users,
      desc: 'Outliers & rate distributions',
    },
    {
      href: '/player-dna',
      label: 'Player DNA & Twins',
      badge: '16-D Manifold',
      icon: Dna,
      desc: 'Archetypes & historical comps',
    },
    {
      href: '/defense',
      label: 'Defensive Versatility',
      badge: 'Switch Matrix',
      icon: ShieldCheck,
      desc: 'Positional entropy & rim deterrence',
    },
    {
      href: '/clutch',
      label: 'True Clutch Index',
      badge: 'Leverage LI',
      icon: Flame,
      desc: 'USCI, TS% resilience & c-dWPA',
    },
    {
      href: '/shots',
      label: 'Shot Charts',
      badge: 'Hot Zones',
      icon: Crosshair,
      desc: 'Empirical Bayes & binomial z',
    },
    {
      href: '/coaches',
      label: 'Coaching Staffs',
      badge: '30 Staffs',
      icon: Briefcase,
      desc: 'Tactics, ATO & CVA lift',
    },
    {
      href: '/matchups',
      label: 'Matchup Slates',
      badge: 'Weekly Grid',
      icon: CalendarDays,
      desc: 'Per-game picks, scores & grades',
    },
    {
      href: '/series',
      label: 'Playoff Simulator',
      badge: '10k Sims',
      icon: Swords,
      desc: '7-game Monte Carlo series',
    },
    {
      href: '/diagnostics',
      label: 'Diagnostics',
      badge: 'Brier 0.2282',
      icon: Activity,
      desc: 'Reliability & calibration curve',
    },
  ];

  const NavContent = () => (
    <div className="flex flex-col h-full justify-between p-4">
      <div className="space-y-6 flex-1 overflow-y-auto min-h-0">
        {/* Brand Header with Halloween Basketball Button Logo */}
        <div className="flex items-center gap-3 px-2 pt-1 pb-2 border-b border-slate-800/80">
          <div className="w-11 h-11 rounded-xl overflow-hidden border border-orange-500/30 shadow-lg shadow-orange-500/20 flex-shrink-0">
            {/* eslint-disable-next-line @next/next/no-img-element */}
            <img src={`${BASE_PATH}/sport-icons/nba.png`} alt="" width={44} height={44} className="w-full h-full object-cover" />
          </div>
          <div className="min-w-0">
            <div className="flex items-center gap-2">
              <span className="font-extrabold text-base tracking-tight bg-gradient-to-r from-orange-400 via-amber-400 to-indigo-400 bg-clip-text text-transparent">
                NBA ANALYTICS
              </span>
            </div>
            <p className="text-[11px] text-slate-400 font-medium truncate">Season Projections 2026-2027</p>
          </div>
        </div>

        {/* Navigation Links */}
        <div className="space-y-1">
          <div className="px-2 text-[10px] font-bold uppercase tracking-wider text-slate-500 mb-2 font-mono">
            Main Navigation
          </div>
          {navItems.map((item) => {
            const Icon = item.icon;
            const isActive = pathname === item.href;
            return (
              <Link
                key={item.href}
                href={item.href}
                onClick={() => setIsOpen(false)}
                className={`group flex items-start gap-3 px-3 py-2.5 rounded-xl text-sm font-medium transition-all ${
                  isActive
                    ? 'bg-accent-600 text-white shadow-lg shadow-accent-600/30'
                    : 'text-slate-300 hover:text-white hover:bg-slate-800/60'
                }`}
              >
                <Icon
                  className={`w-5 h-5 mt-0.5 flex-shrink-0 ${
                    isActive ? 'text-white' : 'text-slate-400 group-hover:text-emerald-400'
                  }`}
                />
                <div className="min-w-0 flex-1">
                  <div className="flex items-center justify-between">
                    <span className="font-semibold">{item.label}</span>
                    <span
                      className={`text-[10px] px-1.5 py-0.2 rounded font-mono font-medium ${
                        isActive ? 'bg-white/20 text-white' : 'bg-slate-800 text-slate-400'
                      }`}
                    >
                      {item.badge}
                    </span>
                  </div>
                  <p
                    className={`text-[11px] truncate ${
                      isActive ? 'text-emerald-200' : 'text-slate-500'
                    }`}
                  >
                    {item.desc}
                  </p>
                </div>
              </Link>
            );
          })}
        </div>

        {/* Engine Metadata Card */}
        <div className="bg-surface/70 border border-slate-800/80 rounded-xl p-3.5 space-y-2.5">
          <div className="flex items-center gap-1.5 text-xs font-bold text-amber-400 uppercase tracking-wide">
            <Layers className="w-3.5 h-3.5" />
            <span>Simulation Spec</span>
          </div>
          <div className="grid grid-cols-2 gap-2 text-xs">
            <div className="bg-surface-raised/80 p-2 rounded-lg border border-slate-800/50">
              <span className="text-[10px] text-slate-400 block">Monte Carlo</span>
              <span className="font-mono font-bold text-slate-200">1,000 Sims</span>
            </div>
            <div className="bg-surface-raised/80 p-2 rounded-lg border border-slate-800/50">
              <span className="text-[10px] text-slate-400 block">Total Games</span>
              <span className="font-mono font-bold text-slate-200">1.23M</span>
            </div>
            
            {/* Margin Sigma with ? Explainer Bubble & Compact Popover */}
            <div className="bg-surface-raised/80 p-2 rounded-lg border border-slate-800/50 relative">
              <div className="flex items-center justify-between">
                <span className="text-[10px] text-slate-400 block">Margin σ</span>
                <button
                  type="button"
                  onClick={() => setShowSigmaExplainer(!showSigmaExplainer)}
                  className="text-amber-400 hover:text-amber-300 p-0.5 rounded hover:bg-slate-800 transition-colors"
                  aria-label="What does margin sigma mean?"
                  title="What does margin sigma mean? Click for explainer."
                >
                  <HelpCircle className="w-3 h-3" />
                </button>
              </div>
              <span className="font-mono font-bold text-slate-200">11.8 pts</span>

              {/* Localized Compact Popover Card (Not Full Page) */}
              {showSigmaExplainer && (
                <>
                  <div
                    className="fixed inset-0 z-40 bg-transparent"
                    onClick={() => setShowSigmaExplainer(false)}
                  />
                  <div className="absolute left-0 md:left-full md:ml-3 bottom-full mb-2 md:bottom-auto md:-top-16 z-50 w-72 sm:w-80 bg-surface-raised border border-slate-700 rounded-xl p-3.5 shadow-2xl space-y-2.5 animate-in fade-in zoom-in-95 duration-150 text-slate-200">
                    <div className="flex items-center justify-between border-b border-slate-800 pb-2">
                      <div className="flex items-center gap-1.5 text-xs font-bold text-amber-400">
                        <Calculator className="w-3.5 h-3.5" />
                        <span>Margin σ = 11.8 pts</span>
                      </div>
                      <button
                        onClick={() => setShowSigmaExplainer(false)}
                        className="p-1 rounded text-slate-400 hover:text-white hover:bg-slate-800"
                      >
                        <X className="w-3 h-3" />
                      </button>
                    </div>

                    <p className="text-[11px] text-slate-300 leading-relaxed">
                      Standard deviation of single-game score differentials around expected margin. Converts point margins into game win probabilities:
                    </p>

                    <div className="bg-surface p-2 rounded border border-slate-800 font-mono text-[10.5px] text-emerald-400 font-semibold">
                      P(Win) = Φ( Expected_Margin / 11.8 )
                    </div>

                    <div className="space-y-1 font-mono text-[10.5px]">
                      <div className="flex justify-between text-slate-300">
                        <span>Pick&apos;em (0.0 pt):</span>
                        <span className="font-bold text-white">50.0%</span>
                      </div>
                      <div className="flex justify-between text-slate-300">
                        <span>+3.5 pt favorite:</span>
                        <span className="font-bold text-white">61.7%</span>
                      </div>
                      <div className="flex justify-between text-slate-300">
                        <span>+6.0 pt favorite:</span>
                        <span className="font-bold text-white">69.5%</span>
                      </div>
                      <div className="flex justify-between text-slate-300">
                        <span>+12.0 pt favorite:</span>
                        <span className="font-bold text-white">84.6%</span>
                      </div>
                    </div>
                  </div>
                </>
              )}
            </div>

            <div className="bg-surface-raised/80 p-2 rounded-lg border border-slate-800/50">
              <span className="text-[10px] text-slate-400 block">Variants</span>
              <span className="font-mono font-bold text-indigo-400">4 Blend</span>
            </div>
          </div>
        </div>
      </div>

      {/* Footer / System Status */}
      <div className="pt-4 border-t border-slate-800/80 space-y-2">
        <div className="flex items-center justify-between text-xs text-slate-400 px-1">
          <span className="flex items-center gap-1.5">
            <span className="w-2 h-2 rounded-full bg-emerald-400 animate-pulse" />
            <span>Pipeline Active</span>
          </span>
          <span className="font-mono text-[11px] text-slate-400">v1.2.0</span>
        </div>
        <div className="flex items-center gap-1.5 text-[11px] text-slate-400 px-1">
          <ShieldCheck className="w-3.5 h-3.5 text-indigo-400 flex-shrink-0" />
          <span className="truncate">ADR-I Frozen Reference Compliant</span>
        </div>
        {generatedAt && (
          <div className="flex items-center justify-between text-[10px] text-slate-500 font-mono px-1">
            <span>Updated</span>
            <time dateTime={generatedAt}>{generatedAt.slice(0, 16).replace('T', ' ')} UTC</time>
          </div>
        )}
      </div>
    </div>
  );

  return (
    <>
      {/* Mobile Header Bar (shown only on small screens) */}
      <div className="md:hidden sticky top-0 z-40 bg-surface-raised/95 backdrop-blur-md border-b border-slate-800 px-4 py-3 flex items-center justify-between">
        <div className="flex items-center gap-2.5">
          <div className="w-9 h-9 rounded-lg overflow-hidden border border-orange-500/30 shadow-md">
            {/* eslint-disable-next-line @next/next/no-img-element */}
            <img src={`${BASE_PATH}/sport-icons/nba.png`} alt="" width={36} height={36} className="w-full h-full object-cover" />
          </div>
          <div>
            <span className="font-extrabold text-sm tracking-tight text-white">NBA PROJECTIONS</span>
            <span className="text-[10px] text-amber-400 font-mono ml-2">2026-2027</span>
          </div>
        </div>
        <button
          onClick={() => setIsOpen(!isOpen)}
          aria-label="Toggle navigation menu"
          className="p-2 rounded-lg bg-slate-800 text-slate-300 hover:text-white hover:bg-slate-700 transition-colors"
        >
          {isOpen ? <X className="w-5 h-5" /> : <Menu className="w-5 h-5" />}
        </button>
      </div>

      {/* Mobile Drawer Overlay */}
      {isOpen && (
        <div className="md:hidden fixed inset-0 z-50 flex">
          <div
            className="fixed inset-0 bg-surface/80 backdrop-blur-sm transition-opacity"
            onClick={() => setIsOpen(false)}
          />
          <div className="relative w-72 max-w-[85vw] bg-surface-raised border-r border-slate-800 h-full z-10 flex flex-col shadow-2xl">
            <div className="absolute top-3 right-3">
              <button
                onClick={() => setIsOpen(false)}
                className="p-1.5 rounded-lg bg-slate-800 text-slate-400 hover:text-white"
              >
                <X className="w-4 h-4" />
              </button>
            </div>
            <NavContent />
          </div>
        </div>
      )}

      {/* Desktop Persistent Sidebar */}
      <aside className="hidden md:flex w-64 lg:w-72 flex-col flex-shrink-0 h-screen sticky top-0 bg-surface-raised/90 backdrop-blur-md border-r border-slate-800 z-30">
        <NavContent />
      </aside>
    </>
  );
};
