'use client';

import React from 'react';
import Link from 'next/link';
import { usePathname } from 'next/navigation';
import { Trophy, Swords, ShieldCheck, Award, Users, BarChart3, Activity, Briefcase, DollarSign, Film } from 'lucide-react';
import { FootballIcon } from '@/components/FootballIcon';

export const Navbar: React.FC = () => {
  const pathname = usePathname();

  const navItems = [
    { href: '/', label: 'Standings', icon: Trophy },
    { href: '/matchups', label: 'Matchups', icon: Swords },
    { href: '/teams', label: 'Teams & EPA', icon: ShieldCheck },
    { href: '/coaching', label: 'Coaching', icon: Briefcase },
    { href: '/salary-cap', label: 'Cap & OTC', icon: DollarSign },
    { href: '/playoffs', label: 'Playoffs', icon: Award },
    { href: '/players', label: 'Players', icon: Users },
    { href: '/variants', label: 'Variants', icon: BarChart3 },
    { href: '/diagnostics', label: 'Diagnostics', icon: Activity },
    { href: '/gallery', label: 'Gallery', icon: Film },
  ];

  return (
    <header className="sticky top-0 z-40 bg-surface-raised/90 backdrop-blur-md border-b border-slate-800 text-white">
      <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
        <div className="flex items-center justify-between h-16">
          <div className="flex items-center gap-3">
            <div className="w-10 h-10 rounded-xl bg-gradient-to-tr from-emerald-700 to-teal-900 border border-emerald-500/30 flex items-center justify-center shadow-lg shadow-emerald-600/20">
              <FootballIcon className="w-6 h-6" size={24} />
            </div>
            <div>
              <div className="flex items-center gap-2">
                <div className="flex items-center gap-1.5">
                  <span className="w-1.5 h-1.5 rounded-full bg-emerald-400 shadow-[0_0_8px_#34d399]" />
                  <span className="font-space font-bold text-lg text-white tracking-wide">
                    <span className="text-emerald-400">NFL</span> ANALYTICS
                  </span>
                </div>
                <span className="px-2 py-0.5 text-xs font-semibold uppercase tracking-wider rounded-full bg-emerald-500/20 text-emerald-300 border border-emerald-500/30">
                  1,000-Sim Monte Carlo
                </span>
              </div>
              <p className="text-xs text-slate-400">Probabilistic Ridge + Elo Projections Engine (2026)</p>
            </div>
          </div>

          <nav className="hidden lg:flex items-center gap-1">
            {navItems.map((item) => {
              const Icon = item.icon;
              const isActive = pathname === item.href;
              return (
                <Link
                  key={item.href}
                  href={item.href}
                  className={`flex items-center gap-1.5 px-3 py-1.5 rounded-lg text-xs font-medium transition-all ${
                    isActive
                      ? 'bg-accent-600 text-white shadow-md shadow-accent-600/30'
                      : 'text-slate-300 hover:text-white hover:bg-slate-800/60'
                  }`}
                >
                  <Icon className="w-3.5 h-3.5" />
                  <span>{item.label}</span>
                </Link>
              );
            })}
          </nav>
        </div>
      </div>
    </header>
  );
};
