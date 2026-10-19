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
  Swords,
  Layers,
} from 'lucide-react';

// Phase 3 of docs/NEXTJS_WEB_APP_PLAN.md (shots, offseason, coaches, defense,
// player-dna, cap-sheet, clutch) needs net-new R engines before a route exists —
// listed here as a visible placeholder, not a Link, until each one ships.
const PLANNED_FEATURES = [
  'Shot Charts',
  'Offseason Moves',
  'Coaching Staffs',
  'Defensive Versatility',
  'Player DNA & Twins',
  'Cap & CBA Sheet',
  'True Clutch Index',
];

export const Sidebar: React.FC = () => {
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
      href: '/series',
      label: 'Playoff Simulator',
      badge: 'Bracket',
      icon: Swords,
      desc: 'Series Monte Carlo simulation',
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
      <div className="space-y-6">
        <div className="flex items-center gap-3 px-2 pt-1 pb-2 border-b border-slate-800/80">
          <div className="w-11 h-11 rounded-xl bg-gradient-to-tr from-indigo-600 via-violet-600 to-slate-900 border border-indigo-500/30 flex items-center justify-center shadow-lg shadow-indigo-500/20 flex-shrink-0">
            <Trophy className="w-6 h-6 text-white" />
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
                    ? 'bg-indigo-600 text-white shadow-lg shadow-indigo-600/30'
                    : 'text-slate-300 hover:text-white hover:bg-slate-800/60'
                }`}
              >
                <Icon
                  className={`w-5 h-5 mt-0.5 flex-shrink-0 ${
                    isActive ? 'text-white' : 'text-slate-400 group-hover:text-indigo-400'
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
                      isActive ? 'text-indigo-200' : 'text-slate-500'
                    }`}
                  >
                    {item.desc}
                  </p>
                </div>
              </Link>
            );
          })}
        </div>

        <div className="bg-slate-950/70 border border-slate-800/80 rounded-xl p-3.5 space-y-2">
          <div className="flex items-center gap-1.5 text-xs font-bold text-amber-400 uppercase tracking-wide">
            <Layers className="w-3.5 h-3.5" />
            <span>Planned (Phase 3)</span>
          </div>
          <ul className="space-y-1">
            {PLANNED_FEATURES.map((label) => (
              <li
                key={label}
                className="text-[11px] text-slate-500 px-2 py-1 rounded-lg bg-slate-900/60 border border-slate-800/50"
              >
                {label}
              </li>
            ))}
          </ul>
        </div>
      </div>

      <div className="pt-4 border-t border-slate-800/80 space-y-2">
        <div className="flex items-center justify-between text-xs text-slate-400 px-1">
          <span className="flex items-center gap-1.5">
            <span className="w-2 h-2 rounded-full bg-amber-400 animate-pulse" />
            <span>Scaffold — Phase 0</span>
          </span>
          <span className="font-mono text-[11px] text-slate-400">v0.1.0</span>
        </div>
      </div>
    </div>
  );

  return (
    <>
      <div className="md:hidden sticky top-0 z-40 bg-slate-900/95 backdrop-blur-md border-b border-slate-800 px-4 py-3 flex items-center justify-between">
        <div className="flex items-center gap-2.5">
          <div className="w-9 h-9 rounded-lg bg-gradient-to-tr from-indigo-600 via-violet-600 to-slate-900 border border-indigo-500/30 flex items-center justify-center shadow-md">
            <Trophy className="w-5 h-5 text-white" />
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
            className="fixed inset-0 bg-slate-950/80 backdrop-blur-sm transition-opacity"
            onClick={() => setIsOpen(false)}
          />
          <div className="relative w-72 max-w-[85vw] bg-slate-900 border-r border-slate-800 h-full z-10 flex flex-col shadow-2xl">
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

      <aside className="hidden md:flex w-64 lg:w-72 flex-col flex-shrink-0 h-screen sticky top-0 bg-slate-900/90 backdrop-blur-md border-r border-slate-800 z-30">
        <NavContent />
      </aside>
    </>
  );
};
