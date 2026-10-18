'use client';

import React, { useState } from 'react';
import Link from 'next/link';
import { usePathname } from 'next/navigation';
import { Trophy, BarChart3, Users, Activity, Sparkles, Menu, X, ShieldCheck, Layers } from 'lucide-react';

export const Sidebar: React.FC = () => {
  const pathname = usePathname();
  const [isOpen, setIsOpen] = useState(false);

  const navItems = [
    {
      href: '/',
      label: 'Season Standings',
      badge: '30 Teams',
      icon: Trophy,
      desc: 'Win distributions & title equity',
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
      href: '/diagnostics',
      label: 'Diagnostics',
      badge: 'Brier 0.198',
      icon: Activity,
      desc: 'Reliability & calibration curve',
    },
  ];

  const NavContent = () => (
    <div className="flex flex-col h-full justify-between p-4">
      <div className="space-y-6">
        {/* Brand Header */}
        <div className="flex items-center gap-3 px-2 pt-1 pb-2 border-b border-slate-800/80">
          <div className="w-10 h-10 rounded-xl bg-gradient-to-tr from-amber-500 via-orange-500 to-indigo-600 flex items-center justify-center shadow-lg shadow-amber-500/20 flex-shrink-0">
            <Sparkles className="w-5 h-5 text-white" />
          </div>
          <div className="min-w-0">
            <div className="flex items-center gap-2">
              <span className="font-extrabold text-base tracking-tight bg-gradient-to-r from-amber-400 via-orange-400 to-indigo-400 bg-clip-text text-transparent">
                NBA ANALYTICS
              </span>
            </div>
            <p className="text-[11px] text-slate-400 font-medium truncate">Season-Long Projections 2025-26</p>
          </div>
        </div>

        {/* Navigation Links */}
        <div className="space-y-1">
          <div className="px-2 text-[10px] font-bold uppercase tracking-wider text-slate-500 mb-2">
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
                <Icon className={`w-5 h-5 mt-0.5 flex-shrink-0 ${isActive ? 'text-white' : 'text-slate-400 group-hover:text-indigo-400'}`} />
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
                  <p className={`text-[11px] truncate ${isActive ? 'text-indigo-200' : 'text-slate-500'}`}>
                    {item.desc}
                  </p>
                </div>
              </Link>
            );
          })}
        </div>

        {/* Engine Metadata Card */}
        <div className="bg-slate-950/70 border border-slate-800/80 rounded-xl p-3.5 space-y-2.5">
          <div className="flex items-center gap-1.5 text-xs font-bold text-amber-400 uppercase tracking-wide">
            <Layers className="w-3.5 h-3.5" />
            <span>Simulation Spec</span>
          </div>
          <div className="grid grid-cols-2 gap-2 text-xs">
            <div className="bg-slate-900/80 p-2 rounded-lg border border-slate-800/50">
              <span className="text-[10px] text-slate-400 block">Monte Carlo</span>
              <span className="font-mono font-bold text-slate-200">1,000 Sims</span>
            </div>
            <div className="bg-slate-900/80 p-2 rounded-lg border border-slate-800/50">
              <span className="text-[10px] text-slate-400 block">Total Games</span>
              <span className="font-mono font-bold text-slate-200">1.23M</span>
            </div>
            <div className="bg-slate-900/80 p-2 rounded-lg border border-slate-800/50">
              <span className="text-[10px] text-slate-400 block">Margin σ</span>
              <span className="font-mono font-bold text-slate-200">11.8 pts</span>
            </div>
            <div className="bg-slate-900/80 p-2 rounded-lg border border-slate-800/50">
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
      </div>
    </div>
  );

  return (
    <>
      {/* Mobile Header Bar (shown only on small screens) */}
      <div className="md:hidden sticky top-0 z-40 bg-slate-900/95 backdrop-blur-md border-b border-slate-800 px-4 py-3 flex items-center justify-between">
        <div className="flex items-center gap-2.5">
          <div className="w-8 h-8 rounded-lg bg-gradient-to-tr from-amber-500 to-indigo-600 flex items-center justify-center shadow-md">
            <Sparkles className="w-4 h-4 text-white" />
          </div>
          <div>
            <span className="font-extrabold text-sm tracking-tight text-white">NBA PROJECTIONS</span>
            <span className="text-[10px] text-amber-400 font-mono ml-2">2025-26</span>
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

      {/* Desktop Persistent Sidebar */}
      <aside className="hidden md:flex w-64 lg:w-72 flex-col flex-shrink-0 h-screen sticky top-0 bg-slate-900/90 backdrop-blur-md border-r border-slate-800 z-30">
        <NavContent />
      </aside>
    </>
  );
};
