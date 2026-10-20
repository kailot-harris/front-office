'use client';

import React from 'react';
import Link from 'next/link';
import { usePathname } from 'next/navigation';
import { Trophy, BarChart3, Users, Activity, Sparkles, Crosshair, Shuffle, Briefcase, Swords, Coins, Dna, Shield, Flame } from 'lucide-react';

export const Navbar: React.FC = () => {
  const pathname = usePathname();

  const navItems = [
    { href: '/', label: 'Season Standings', icon: Trophy },
    { href: '/offseason', label: 'Offseason Moves', icon: Shuffle },
    { href: '/cap-sheet', label: 'Cap & Aprons', icon: Coins },
    { href: '/variants', label: 'Model Variants', icon: BarChart3 },
    { href: '/players', label: 'Player Projections', icon: Users },
    { href: '/player-dna', label: 'Player DNA', icon: Dna },
    { href: '/defense', label: 'Defense', icon: Shield },
    { href: '/clutch', label: 'Clutch', icon: Flame },
    { href: '/shots', label: 'Shot Charts', icon: Crosshair },
    { href: '/coaches', label: 'Coaches', icon: Briefcase },
    { href: '/series', label: 'Playoffs', icon: Swords },
    { href: '/diagnostics', label: 'Diagnostics & Calibration', icon: Activity },
  ];

  return (
    <header className="sticky top-0 z-50 bg-surface-raised/90 backdrop-blur-md border-b border-slate-800 text-white">
      <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
        <div className="flex items-center justify-between h-16">
          <div className="flex items-center gap-3">
            <div className="w-10 h-10 rounded-xl bg-gradient-to-tr from-amber-500 to-indigo-600 flex items-center justify-center shadow-lg shadow-amber-500/20">
              <Sparkles className="w-5 h-5 text-white" />
            </div>
            <div>
              <div className="flex items-center gap-2">
                <span className="font-extrabold text-lg tracking-tight bg-gradient-to-r from-amber-400 via-orange-400 to-indigo-400 bg-clip-text text-transparent">
                  NBA PROJECTIONS
                </span>
                <span className="px-2 py-0.5 text-xs font-semibold uppercase tracking-wider rounded-full bg-indigo-500/20 text-indigo-300 border border-indigo-500/30">
                  1,000-Sim Monte Carlo
                </span>
              </div>
              <p className="text-xs text-slate-400">Season-Long Probabilistic Simulation Engine (2025-26)</p>
            </div>
          </div>

          <nav className="flex items-center gap-1 sm:gap-2">
            {navItems.map((item) => {
              const Icon = item.icon;
              const isActive = pathname === item.href;
              return (
                <Link
                  key={item.href}
                  href={item.href}
                  className={`flex items-center gap-2 px-3 py-2 rounded-lg text-sm font-medium transition-all ${
                    isActive
                      ? 'bg-accent-600 text-white shadow-md shadow-accent-600/30'
                      : 'text-slate-300 hover:text-white hover:bg-slate-800/60'
                  }`}
                >
                  <Icon className="w-4 h-4" />
                  <span className="hidden md:inline">{item.label}</span>
                </Link>
              );
            })}
          </nav>
        </div>
      </div>
    </header>
  );
};
