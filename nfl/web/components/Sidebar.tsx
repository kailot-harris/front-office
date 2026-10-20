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
  Swords,
  Award,
  Film,
  Zap,
  Briefcase,
  DollarSign,
} from 'lucide-react';
import { FootballIcon } from '@/components/FootballIcon';

export const Sidebar: React.FC = () => {
  const pathname = usePathname();
  const [isOpen, setIsOpen] = useState(false);
  const [showSigmaExplainer, setShowSigmaExplainer] = useState(false);

  const navItems = [
    {
      href: '/',
      label: 'Season Standings',
      badge: '32 Teams',
      icon: Trophy,
      desc: 'Win distributions & division races',
    },
    {
      href: '/matchups',
      label: 'Weekly Matchups',
      badge: 'Projections',
      icon: Swords,
      desc: 'Projected margins, totals & fatigue',
    },
    {
      href: '/teams',
      label: 'Team Ratings & EPA',
      badge: 'Ridge + Elo',
      icon: ShieldCheck,
      desc: 'Power ranks & EPA quadrants',
    },
    {
      href: '/coaching',
      label: 'Coaching Analysis',
      badge: 'Staff & Decisions',
      icon: Briefcase,
      desc: 'Decision profiles, aggressive index & tenure',
    },
    {
      href: '/salary-cap',
      label: 'Salary Cap & OTC',
      badge: '$301.2M Cap',
      icon: DollarSign,
      desc: 'Positional allocations & top contracts',
    },
    {
      href: '/playoffs',
      label: 'Playoff Machine',
      badge: '14-Team Field',
      icon: Award,
      desc: 'Tiebreaker logic & bracket sim',
    },
    {
      href: '/players',
      label: 'QB & Player Ratings',
      badge: 'EPA & CPOE',
      icon: Users,
      desc: 'QB composite & rookie snap ramp',
    },
    {
      href: '/variants',
      label: 'Model Variants',
      badge: '3 Engines',
      icon: BarChart3,
      desc: 'Ridge vs Elo vs Market weights',
    },
    {
      href: '/diagnostics',
      label: 'Diagnostics',
      badge: 'Calibration',
      icon: Activity,
      desc: 'Reliability & calibration curve',
    },
    {
      href: '/gallery',
      label: 'Visual Gallery',
      badge: '17 Animations',
      icon: Film,
      desc: 'Animated races & simulation GIFs',
    },
  ];

  const NavContent = () => (
    <div className="flex flex-col h-full justify-between p-4 overflow-y-auto">
      <div className="space-y-6">
        {/* Brand Header */}
        <div className="flex items-center gap-3 px-2 pt-1 pb-3 border-b border-slate-800/80">
          <div className="w-11 h-11 rounded-xl bg-gradient-to-tr from-emerald-800 via-teal-900 to-slate-900 border border-emerald-500/30 flex items-center justify-center shadow-lg shadow-emerald-500/10 flex-shrink-0">
            <FootballIcon className="w-7 h-7" size={28} />
          </div>
          <div className="min-w-0">
            <div className="flex items-center gap-2">
              <span className="font-extrabold text-base tracking-tight bg-gradient-to-r from-emerald-400 via-teal-300 to-cyan-400 bg-clip-text text-transparent">
                NFL ANALYTICS
              </span>
            </div>
            <p className="text-[11px] text-slate-400 font-medium truncate">Season Projections 2026</p>
          </div>
        </div>

        {/* Navigation Items */}
        <nav className="space-y-1.5">
          <p className="px-3 text-[10px] font-mono uppercase tracking-wider text-slate-400 font-semibold mb-2">
            Platform Navigation
          </p>
          {navItems.map((item) => {
            const Icon = item.icon;
            const isActive = pathname === item.href;
            return (
              <Link
                key={item.href}
                href={item.href}
                onClick={() => setIsOpen(false)}
                className={`group flex items-center justify-between px-3 py-2.5 rounded-xl text-xs font-medium transition-all ${
                  isActive
                    ? 'bg-gradient-to-r from-accent-600/90 to-teal-700/80 text-white shadow-lg shadow-accent-950 border border-accent-400/30'
                    : 'text-slate-300 hover:text-white hover:bg-surface-raised/80 border border-transparent hover:border-slate-800'
                }`}
              >
                <div className="flex items-center gap-3 min-w-0">
                  <div
                    className={`p-1.5 rounded-lg transition-colors ${
                      isActive
                        ? 'bg-white/10 text-white'
                        : 'bg-surface text-slate-400 group-hover:text-accent-400 group-hover:bg-surface-raised border border-slate-800'
                    }`}
                  >
                    <Icon className="w-4 h-4 flex-shrink-0" />
                  </div>
                  <div className="truncate">
                    <div className="font-semibold truncate">{item.label}</div>
                    <div className="text-[10px] text-slate-400 group-hover:text-slate-300 font-normal truncate">
                      {item.desc}
                    </div>
                  </div>
                </div>
                {item.badge && (
                  <span
                    className={`ml-2 px-1.5 py-0.5 text-[9px] font-mono rounded flex-shrink-0 border ${
                      isActive
                        ? 'bg-accent-950/80 text-emerald-300 border-accent-400/40'
                        : 'bg-surface text-slate-400 border-slate-800 group-hover:border-slate-700'
                    }`}
                  >
                    {item.badge}
                  </span>
                )}
              </Link>
            );
          })}
        </nav>
      </div>

      {/* Model Spec & Sigma Footer */}
      <div className="pt-4 border-t border-slate-800/80 space-y-3">
        <div className="bg-surface/70 rounded-xl p-3 border border-slate-800 text-xs font-mono space-y-2">
          <div className="flex items-center justify-between text-slate-400 text-[11px]">
            <span className="flex items-center gap-1.5">
              <Layers className="w-3.5 h-3.5 text-emerald-400" />
              <span>Ensemble Spec</span>
            </span>
            <span className="text-emerald-400 font-semibold">1,000 Sims</span>
          </div>

          <div className="grid grid-cols-2 gap-1.5 text-[10px] pt-1 border-t border-slate-900 text-slate-300">
            <div>
              <span className="text-slate-400">Ridge:</span> <span className="text-white font-bold">40%</span>
            </div>
            <div>
              <span className="text-slate-400">Elo:</span> <span className="text-white font-bold">35%</span>
            </div>
            <div>
              <span className="text-slate-400">Market:</span> <span className="text-white font-bold">25%</span>
            </div>
            <div>
              <span className="text-slate-400">HFA:</span> <span className="text-emerald-400 font-bold">+1.93</span>
            </div>
          </div>

          {/* Interactive Margin Sigma Popover Trigger */}
          <div className="pt-1.5 border-t border-slate-900 flex items-center justify-between">
            <button
              onClick={() => setShowSigmaExplainer(!showSigmaExplainer)}
              className="flex items-center gap-1 text-[11px] text-cyan-400 hover:text-cyan-300 transition-colors cursor-pointer"
            >
              <Zap className="w-3 h-3" />
              <span>σ = 14.6 Margin</span>
              <HelpCircle className="w-3 h-3 text-slate-400" />
            </button>
            <span className="text-[10px] text-slate-400">NFL Tail</span>
          </div>

          {/* Popover Explainer Card */}
          {showSigmaExplainer && (
            <div className="mt-2 p-2.5 rounded-lg bg-surface-raised border border-cyan-800/60 text-[10px] text-slate-300 space-y-1.5 animate-in fade-in slide-in-from-bottom-1 duration-150">
              <div className="font-bold text-cyan-300 flex items-center gap-1">
                <span>NFL Margin Sigma (σ = 14.6)</span>
              </div>
              <p className="leading-relaxed text-slate-400">
                NFL outcomes follow a normal distribution with higher variance than basketball (σ = 14.6)
                calibrates win probability: P(win) = Φ(margin / 14.6). Key scoring margins occur at 3, 7, 6, 10, and 4.
              </p>
              <div className="text-right">
                <button
                  onClick={() => setShowSigmaExplainer(false)}
                  className="text-cyan-400 hover:underline font-semibold"
                >
                  Dismiss
                </button>
              </div>
            </div>
          )}
        </div>

        <div className="flex items-center justify-between text-[10px] font-mono text-slate-400 px-1">
          <span>NFL Season 2026</span>
          <span className="flex items-center gap-1">
            <span className="w-1.5 h-1.5 rounded-full bg-emerald-400 animate-pulse"></span>
            Live Pipeline
          </span>
        </div>
      </div>
    </div>
  );

  return (
    <>
      {/* Mobile Menu Button */}
      <button
        onClick={() => setIsOpen(!isOpen)}
        className="lg:hidden fixed top-4 left-4 z-[60] p-2 rounded-xl bg-surface-raised border border-slate-800 text-slate-300 hover:text-white shadow-xl"
        aria-label="Toggle navigation"
      >
        {isOpen ? <X className="w-5 h-5" /> : <Menu className="w-5 h-5" />}
      </button>

      {/* Backdrop for mobile */}
      {isOpen && (
        <div
          onClick={() => setIsOpen(false)}
          className="lg:hidden fixed inset-0 z-40 bg-surface/80 backdrop-blur-sm"
        />
      )}

      {/* Desktop Persistent Sidebar */}
      <aside className="hidden lg:flex fixed top-0 left-0 h-screen w-64 bg-surface border-r border-slate-800/80 z-30 flex-col">
        <NavContent />
      </aside>

      {/* Mobile Drawer */}
      <aside
        className={`lg:hidden fixed top-0 left-0 h-screen w-72 bg-surface border-r border-slate-800 z-50 transform transition-transform duration-200 ease-in-out ${
          isOpen ? 'translate-x-0' : '-translate-x-full'
        }`}
      >
        <NavContent />
      </aside>
    </>
  );
};
