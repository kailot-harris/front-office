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
import { BASE_PATH } from '@/lib/basePath';

/**
 * next.config.mjs sets `trailingSlash: true`, so usePathname() returns '/teams/'
 * while the navItems below are written as '/teams'. Comparing them directly meant
 * `isActive` was false on every page except the home page, and no nav item was
 * ever highlighted. Strip the trailing slash from both sides before comparing.
 */
const withoutTrailingSlash = (path: string) =>
  path.length > 1 && path.endsWith('/') ? path.slice(0, -1) : path;

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
    <div className="flex flex-col h-full justify-between p-4">
      <div className="space-y-6 flex-1 overflow-y-auto min-h-0">
        {/* Brand Header */}
        <div className="flex items-center gap-3 px-2 pt-1 pb-2 border-b border-slate-800/80">
          <div className="w-11 h-11 rounded-xl overflow-hidden border border-emerald-500/30 shadow-lg shadow-emerald-500/10 flex-shrink-0">
            {/* eslint-disable-next-line @next/next/no-img-element */}
            <img src={`${BASE_PATH}/sport-icons/nfl.png`} alt="" width={44} height={44} className="w-full h-full object-cover" />
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

        {/* Navigation Links */}
        <div className="space-y-1">
          <div className="px-2 text-[10px] font-bold uppercase tracking-wider text-slate-500 mb-2 font-mono">
            Main Navigation
          </div>
          {navItems.map((item) => {
            const Icon = item.icon;
            const isActive = withoutTrailingSlash(pathname ?? '/') === withoutTrailingSlash(item.href);
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

        {/* Model Spec & Sigma Footer */}
        <div className="bg-surface/70 border border-slate-800/80 rounded-xl p-3.5 space-y-2.5">
          <div className="flex items-center gap-1.5 text-xs font-bold text-amber-400 uppercase tracking-wide">
            <Layers className="w-3.5 h-3.5" />
            <span>Ensemble Spec</span>
          </div>
          <div className="grid grid-cols-2 gap-2 text-xs">
            <div className="bg-surface-raised/80 p-2 rounded-lg border border-slate-800/50">
              <span className="text-[10px] text-slate-400 block">Simulations</span>
              <span className="font-mono font-bold text-slate-200">1,000 Sims</span>
            </div>
            <div className="bg-surface-raised/80 p-2 rounded-lg border border-slate-800/50">
              <span className="text-[10px] text-slate-400 block">Blend Weights</span>
              <span className="font-mono font-bold text-slate-200">40/35/25</span>
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
              <span className="font-mono font-bold text-slate-200">14.6 pts</span>

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
                        <Zap className="w-3.5 h-3.5" />
                        <span>Margin σ = 14.6 pts</span>
                      </div>
                      <button
                        onClick={() => setShowSigmaExplainer(false)}
                        className="p-1 rounded text-slate-400 hover:text-white hover:bg-slate-800"
                      >
                        <X className="w-3 h-3" />
                      </button>
                    </div>

                    <p className="text-[11px] text-slate-300 leading-relaxed">
                      Standard deviation of single-game score differentials around expected margin. NFL outcomes carry higher variance than basketball, converting point margins into win probabilities:
                    </p>

                    <div className="bg-surface p-2 rounded border border-slate-800 font-mono text-[10.5px] text-emerald-400 font-semibold">
                      P(Win) = Φ( Expected_Margin / 14.6 )
                    </div>

                    <div className="space-y-1 font-mono text-[10.5px]">
                      <div className="flex justify-between text-slate-300">
                        <span>Pick&apos;em (0.0 pt):</span>
                        <span className="font-bold text-white">50.0%</span>
                      </div>
                      <div className="flex justify-between text-slate-300">
                        <span>+3.0 pt favorite:</span>
                        <span className="font-bold text-white">58.1%</span>
                      </div>
                      <div className="flex justify-between text-slate-300">
                        <span>+7.0 pt favorite:</span>
                        <span className="font-bold text-white">68.0%</span>
                      </div>
                      <div className="flex justify-between text-slate-300">
                        <span>+10.0 pt favorite:</span>
                        <span className="font-bold text-white">74.9%</span>
                      </div>
                    </div>
                  </div>
                </>
              )}
            </div>

            <div className="bg-surface-raised/80 p-2 rounded-lg border border-slate-800/50">
              <span className="text-[10px] text-slate-400 block">HFA</span>
              <span className="font-mono font-bold text-emerald-400">+1.93</span>
            </div>
          </div>
        </div>
      </div>

      {/* Footer / System Status */}
      <div className="pt-4 border-t border-slate-800/80 space-y-2">
        <div className="flex items-center justify-between text-xs text-slate-400 px-1">
          <span className="flex items-center gap-1.5">
            <span className="w-2 h-2 rounded-full bg-emerald-400 animate-pulse" />
            <span>Live Pipeline</span>
          </span>
          <span className="font-mono text-[11px] text-slate-400">NFL Season 2026</span>
        </div>
      </div>
    </div>
  );

  return (
    <>
      {/* Mobile Header Bar (shown only on small screens) */}
      <div className="md:hidden sticky top-0 z-40 bg-surface-raised/95 backdrop-blur-md border-b border-slate-800 px-4 py-3 flex items-center justify-between">
        <div className="flex items-center gap-2.5">
          <div className="w-9 h-9 rounded-lg overflow-hidden border border-emerald-500/30 shadow-md">
            {/* eslint-disable-next-line @next/next/no-img-element */}
            <img src={`${BASE_PATH}/sport-icons/nfl.png`} alt="" width={36} height={36} className="w-full h-full object-cover" />
          </div>
          <div>
            <span className="font-extrabold text-sm tracking-tight text-white">NFL PROJECTIONS</span>
            <span className="text-[10px] text-emerald-400 font-mono ml-2">2026</span>
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
