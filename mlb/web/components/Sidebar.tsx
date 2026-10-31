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
  Flame,
  Compass,
  Swords,
  Dna,
  Award,
  Coins,
  CalendarDays,
  Sparkles,
  Film,
} from 'lucide-react';
import { BASE_PATH } from '@/lib/basePath';

/**
 * next.config.mjs sets `trailingSlash: true`, so usePathname() returns '/variants/'
 * while the navItems below are written as '/variants'. Comparing them directly meant
 * `isActive` was false on every page except the home page, and no nav item was
 * ever highlighted. Strip the trailing slash from both sides before comparing.
 */
const withoutTrailingSlash = (path: string) =>
  path.length > 1 && path.endsWith('/') ? path.slice(0, -1) : path;

export interface SidebarProps {
  generatedAt?: string;
}

export const Sidebar: React.FC<SidebarProps> = ({ generatedAt }) => {
  const pathname = usePathname();
  const [isOpen, setIsOpen] = useState(false);
  const [showEloExplainer, setShowEloExplainer] = useState(false);

  const navItems = [
    {
      href: '/',
      label: 'Season Standings',
      badge: '30 Clubs',
      icon: Trophy,
      desc: '162-game win distributions & WS%',
    },
    {
      href: '/gallery',
      label: 'Visual Media Gallery',
      badge: '20 GIFs',
      icon: Film,
      desc: 'Year-end animated races, brackets & scatters',
    },
    {
      href: '/retrospective',
      label: '2026 Retrospective',
      badge: 'WS Debrief',
      icon: Sparkles,
      desc: 'Postseason audit, champions and model postmortem',
    },
    {
      href: '/postseason',
      label: 'Postseason & Bullpen',
      badge: '12-Team Ops',
      icon: Award,
      desc: '12-team bracket, bullpen & +EV bets',
    },
    {
      href: '/matchups',
      label: 'Weekly Matchups',
      badge: 'Slate Grades',
      icon: CalendarDays,
      desc: 'Every game by week, graded vs pre-game Elo',
    },
    {
      href: '/players',
      label: 'Player Projections',
      badge: '1,279 Pool',
      icon: Users,
      desc: 'Batters (630) & Pitchers (649) toggle',
    },
    {
      href: '/player-dna',
      label: 'Player DNA & Twins',
      badge: '16-D Manifold',
      icon: Dna,
      desc: 'Archetypes & historical comps (1980+)',
    },
    {
      href: '/clutch',
      label: 'True Clutch Index',
      badge: 'Leverage LI',
      icon: Flame,
      desc: 'Tango LI, RISP resilience & Firemen',
    },
    {
      href: '/spatial',
      label: 'Spatial Analytics',
      badge: 'Statcast',
      icon: Compass,
      desc: 'Spray, Strike Zone, IVB & Shift',
    },
    {
      href: '/cap-sheet',
      label: 'Cap & Luxury Tax',
      badge: 'CBT $244M',
      icon: Coins,
      desc: 'CBT thresholds, payroll & contract surplus',
    },
    {
      href: '/series',
      label: 'Playoff Simulator',
      badge: '10K Sims',
      icon: Swords,
      desc: '3/5/7-game rotation series match-ups',
    },
    {
      href: '/variants',
      label: 'Model Variants',
      badge: '4 Engines',
      icon: BarChart3,
      desc: 'Elo, Bayes, Pythagenpat & Marcel',
    },
    {
      href: '/diagnostics',
      label: 'Diagnostics',
      badge: 'Brier 0.2449',
      icon: Activity,
      desc: 'Reliability curve & walk-forward drift',
    },
  ];

  const NavContent = () => (
    <div className="flex flex-col h-full justify-between p-4">
      <div className="space-y-6 flex-1 overflow-y-auto min-h-0">
        {/* Brand Header */}
        <div className="flex items-center gap-3 px-2 pt-1 pb-2 border-b border-slate-800/80">
          <div className="w-11 h-11 rounded-xl overflow-hidden border border-sky-500/30 shadow-lg shadow-sky-500/20 flex-shrink-0">
            {/* eslint-disable-next-line @next/next/no-img-element */}
            <img src={`${BASE_PATH}/sport-icons/mlb.png`} alt="" width={44} height={44} className="w-full h-full object-cover" />
          </div>
          <div className="min-w-0">
            <div className="flex items-center gap-1.5">
              <span className="w-1.5 h-1.5 rounded-full bg-sky-400 shadow-[0_0_8px_#38bdf8]" />
              <span className="font-space font-bold text-base text-white tracking-wide">
                <span className="text-sky-400">MLB</span> ANALYTICS
              </span>
            </div>
            <div className="w-full h-[2px] bg-gradient-to-r from-sky-400 via-sky-500/40 to-transparent rounded-full mt-1 mb-1" />
            <p className="text-[10px] text-slate-400 font-mono tracking-tight">Sabermetric Engine • 162-Game</p>
          </div>
        </div>

        {/* Navigation Links */}
        <div className="space-y-1">
          <div className="px-2 text-[10px] font-bold uppercase tracking-wider text-slate-500 mb-2 font-mono">
            Main Navigation
          </div>
          {navItems.map((item) => {
            const Icon = item.icon;
            const isActive =
              withoutTrailingSlash(pathname ?? '/') === withoutTrailingSlash(item.href) ||
              (item.href === '/' && withoutTrailingSlash(pathname ?? '/') === '/teams');
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
                    isActive ? 'text-white' : 'text-slate-400 group-hover:text-accent-400'
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
                      isActive ? 'text-accent-50' : 'text-slate-500'
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
              <span className="text-[10px] text-slate-400 block">Bracket / Season</span>
              <span className="font-mono font-bold text-slate-200">10K / 1K Sims</span>
            </div>
            <div className="bg-surface-raised/80 p-2 rounded-lg border border-slate-800/50">
              <span className="text-[10px] text-slate-400 block">Schedule</span>
              <span className="font-mono font-bold text-slate-200">2,430 Games</span>
            </div>

            {/* Pitcher rGS & Pythagenpat Explainer Popover */}
            <div className="bg-surface-raised/80 p-2 rounded-lg border border-slate-800/50 relative">
              <div className="flex items-center justify-between">
                <span className="text-[10px] text-slate-400 block">Starter rGS</span>
                <button
                  type="button"
                  onClick={() => setShowEloExplainer(!showEloExplainer)}
                  className="text-amber-400 hover:text-amber-300 p-0.5 rounded hover:bg-slate-800 transition-colors"
                  aria-label="How does Starter rGS & Pythagenpat work?"
                  title="How does Starter rGS & Pythagenpat work? Click for math explainer."
                >
                  <HelpCircle className="w-3 h-3" />
                </button>
              </div>
              <span className="font-mono font-bold text-slate-200">4.7× ΔrGS</span>

              {showEloExplainer && (
                <>
                  <div
                    className="fixed inset-0 z-40 bg-transparent"
                    onClick={() => setShowEloExplainer(false)}
                  />
                  <div className="absolute left-0 md:left-full md:ml-3 bottom-full mb-2 md:bottom-auto md:-top-24 z-50 w-72 sm:w-80 bg-surface-raised border border-slate-700 rounded-xl p-3.5 shadow-2xl space-y-2.5 animate-in fade-in zoom-in-95 duration-150 text-slate-200">
                    <div className="flex items-center justify-between border-b border-slate-800 pb-2">
                      <div className="flex items-center gap-1.5 text-xs font-bold text-amber-400">
                        <Calculator className="w-3.5 h-3.5" />
                        <span>4-Factor Pitcher Elo & Pythagenpat</span>
                      </div>
                      <button
                        onClick={() => setShowEloExplainer(false)}
                        className="p-1 rounded text-slate-400 hover:text-white hover:bg-slate-800"
                      >
                        <X className="w-3 h-3" />
                      </button>
                    </div>

                    <p className="text-[11px] text-slate-300 leading-relaxed">
                      Adjusts pre-game team Elo using Tangotiger rolling Starter Game Score (rGS), HFA (+14.9 Elo), and Smyth&apos;s Pythagenpat exponent:
                    </p>

                    <div className="bg-surface p-2 rounded border border-slate-800 font-mono text-[10.5px] text-emerald-400 font-semibold space-y-1">
                      <div>Elo_adj = Elo + 14.9 + 4.7 × (rGS_sp - rGS_tm)</div>
                      <div>γ = ((RS + RA) / G)^0.287 ≈ 1.79</div>
                    </div>

                    <div className="space-y-1 font-mono text-[10.5px]">
                      <div className="flex justify-between text-slate-300">
                        <span>Neutral Pick&apos;em (0 Elo):</span>
                        <span className="font-bold text-white">50.0%</span>
                      </div>
                      <div className="flex justify-between text-slate-300">
                        <span>Home Field (+14.9 Elo):</span>
                        <span className="font-bold text-white">52.1%</span>
                      </div>
                      <div className="flex justify-between text-slate-300">
                        <span>Ace Starter (+10 rGS / +47 Elo):</span>
                        <span className="font-bold text-white">56.7%</span>
                      </div>
                      <div className="flex justify-between text-slate-300">
                        <span>Elite Contender (+100 Elo):</span>
                        <span className="font-bold text-white">64.0%</span>
                      </div>
                    </div>
                  </div>
                </>
              )}
            </div>

            <div className="bg-surface-raised/80 p-2 rounded-lg border border-slate-800/50">
              <span className="text-[10px] text-slate-400 block">Pythagenpat</span>
              <span className="font-mono font-bold text-indigo-400">γ = 1.79</span>
            </div>
          </div>
        </div>
      </div>

      {/* Footer / System Status */}
      <div className="pt-4 border-t border-slate-800/80 space-y-2">
        <div className="flex items-center justify-between text-xs text-slate-400 px-1">
          <span className="flex items-center gap-1.5">
            <span className="w-2 h-2 rounded-full bg-emerald-400 animate-pulse" />
            <span>18-Stage DAG Active</span>
          </span>
          <span className="font-mono text-[11px] text-slate-400">v1.8.0</span>
        </div>
        <div className="flex items-center gap-1.5 text-[11px] text-slate-400 px-1">
          <ShieldCheck className="w-3.5 h-3.5 text-indigo-400 flex-shrink-0" />
          <span className="truncate">Empirical Bayes & Walk-Forward Verified</span>
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
      {/* Mobile Header Bar */}
      <div className="relative md:hidden sticky top-0 z-40 bg-surface-raised/95 backdrop-blur-md border-b border-slate-800 px-4 py-3 flex items-center justify-between">
        <div className="absolute bottom-0 left-0 right-0 h-[2px] bg-gradient-to-r from-sky-400 via-sky-500/40 to-transparent" />
        <div className="flex items-center gap-2.5">
          <div className="w-9 h-9 rounded-lg overflow-hidden border border-sky-500/30 shadow-md flex-shrink-0">
            {/* eslint-disable-next-line @next/next/no-img-element */}
            <img src={`${BASE_PATH}/sport-icons/mlb.png`} alt="" width={36} height={36} className="w-full h-full object-cover" />
          </div>
          <div className="flex items-center gap-1.5">
            <span className="w-1.5 h-1.5 rounded-full bg-sky-400 shadow-[0_0_8px_#38bdf8] flex-shrink-0" />
            <span className="font-bold text-sm tracking-tight text-white">
              <span className="text-sky-400">MLB</span> ANALYTICS
            </span>
            <span className="text-[10px] text-slate-400 font-mono ml-2">162-GAME</span>
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
