'use client';

import React, { useState } from 'react';
import Link from 'next/link';
import { usePathname } from 'next/navigation';
import { BASE_PATH } from '@/lib/basePath';
import {
  Trophy,
  BarChart3,
  Users,
  Activity,
  Menu,
  X,
  Swords,
  Crosshair,
  ArrowRightLeft,
  Briefcase,
  Shield,
  Dna,
  Flame,
  Coins,
  CheckCircle2,
  CalendarDays,
} from 'lucide-react';


export interface SidebarProps {
  generatedAt?: string;
}

export const Sidebar: React.FC<SidebarProps> = ({ generatedAt }) => {
  const pathname = usePathname();
  const [isOpen, setIsOpen] = useState(false);

  const navItems = [
    {
      href: '/',
      label: 'Season Standings',
      badge: '15 Teams',
      icon: Trophy,
      desc: 'Win distributions & franchise table',
    },
    {
      href: '/matchups',
      label: 'Matchups',
      badge: 'By Week',
      icon: CalendarDays,
      desc: 'Week slate, scores & graded picks',
    },
    {
      href: '/variants',
      label: 'Model Variants',
      badge: 'RAPM',
      icon: BarChart3,
      desc: 'Divergence matrix & weights',
    },
    {
      href: '/players',
      label: 'Player Projections',
      badge: 'Props',
      icon: Users,
      desc: 'Rate distributions & outliers',
    },
    {
      href: '/player-dna',
      label: 'Player DNA & Twins',
      badge: '16-D',
      icon: Dna,
      desc: 'Fingerprints & historical comps',
    },
    {
      href: '/clutch',
      label: 'True Clutch Index',
      badge: 'Leverage',
      icon: Flame,
      desc: 'Shot creation & pressure fragility',
    },
    {
      href: '/cap-sheet',
      label: 'CBA Cap Sheet',
      badge: 'Hard Cap',
      icon: Coins,
      desc: '11-vs-12 crunch & contract book',
    },
    {
      href: '/shots',
      label: 'Shot Charts',
      badge: '14 Zones',
      icon: Crosshair,
      desc: 'Half-court spatial heatmaps',
    },
    {
      href: '/defense',
      label: 'Defensive Matrix',
      badge: 'Versatility',
      icon: Shield,
      desc: 'Entropy & rim suppression',
    },
    {
      href: '/coaches',
      label: 'Coaching Staffs',
      badge: 'ATO',
      icon: Briefcase,
      desc: 'Tactical impact & system lift',
    },
    {
      href: '/offseason',
      label: 'Offseason & Moves',
      badge: 'Trades',
      icon: ArrowRightLeft,
      desc: 'Trades, expansion & draft',
    },
    {
      href: '/series',
      label: 'Playoff Simulator',
      badge: 'Bracket',
      icon: Swords,
      desc: 'Series Monte Carlo simulation',
    },
    {
      href: '/bracket-2026',
      label: '2026 Bracket',
      badge: 'Postseason',
      icon: Trophy,
      desc: 'Prediction beside result, per round',
    },
    {
      href: '/diagnostics',
      label: 'Diagnostics',
      badge: 'Calibration',
      icon: Activity,
      desc: 'Reliability & calibration curve',
    },
  ];

  const NavContent = () => (
    <div className="flex flex-col h-full justify-between p-4">
      <div className="space-y-6 flex-1 overflow-y-auto min-h-0">
        <div className="flex items-center gap-3 px-2 pt-1 pb-2 border-b border-slate-800/80">
          <div className="w-11 h-11 rounded-xl overflow-hidden border border-indigo-500/30 shadow-lg shadow-indigo-500/20 flex-shrink-0">
            {/* eslint-disable-next-line @next/next/no-img-element */}
            <img src={`${BASE_PATH}/sport-icons/wnba.png`} alt="" width={44} height={44} className="w-full h-full object-cover" />
          </div>
          <div className="min-w-0">
            <span className="font-extrabold text-base tracking-tight bg-gradient-to-r from-indigo-400 via-violet-400 to-amber-400 bg-clip-text text-transparent">
              WNBA ANALYTICS
            </span>
            <p className="text-[11px] text-slate-400 font-medium truncate">Season Projections</p>
          </div>
        </div>

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

        <div className="bg-surface/50 border border-emerald-900/30 rounded-xl p-3 space-y-1">
          <div className="flex items-center gap-1.5 text-xs font-bold text-emerald-400">
            <CheckCircle2 className="w-3.5 h-3.5 text-emerald-400" />
            <span>Full Analytics Suite Live</span>
          </div>
          <p className="text-[11px] text-slate-500">
            All 12 analytics engines & routes operational.
          </p>
        </div>
      </div>

      <div className="pt-4 border-t border-slate-800/80 space-y-2">
        <div className="flex items-center justify-between text-xs text-slate-400 px-1">
          <span className="flex items-center gap-1.5">
            <span className="w-2 h-2 rounded-full bg-emerald-400 animate-pulse" />
            <span>Live Analytics System</span>
          </span>
          <span className="font-mono text-[11px] text-slate-400">v1.0.0</span>
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
      <div className="md:hidden sticky top-0 z-40 bg-surface-raised/95 backdrop-blur-md border-b border-slate-800 px-4 py-3 flex items-center justify-between">
        <div className="flex items-center gap-2.5">
          <div className="w-9 h-9 rounded-lg overflow-hidden border border-indigo-500/30 shadow-md">
            {/* eslint-disable-next-line @next/next/no-img-element */}
            <img src={`${BASE_PATH}/sport-icons/wnba.png`} alt="" width={36} height={36} className="w-full h-full object-cover" />
          </div>
          <span className="font-extrabold text-sm tracking-tight text-white">WNBA ANALYTICS</span>
        </div>
        <button
          onClick={() => setIsOpen(!isOpen)}
          aria-label="Toggle navigation menu"
          className="p-2 rounded-lg bg-slate-800 text-slate-300 hover:text-white hover:bg-slate-700 transition-colors"
        >
          {isOpen ? <X className="w-5 h-5" /> : <Menu className="w-5 h-5" />}
        </button>
      </div>

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

      <aside className="hidden md:flex w-64 lg:w-72 flex-col flex-shrink-0 h-screen sticky top-0 bg-surface-raised/90 backdrop-blur-md border-r border-slate-800 z-30">
        <NavContent />
      </aside>
    </>
  );
};
