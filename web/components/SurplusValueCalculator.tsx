'use client';

import React, { useState } from 'react';
import { Calculator, Sparkles, TrendingUp, TrendingDown, DollarSign } from 'lucide-react';

export const SurplusValueCalculator: React.FC = () => {
  const [salary, setSalary] = useState<number>(25.0);
  const [projectedWar, setProjectedWar] = useState<number>(4.2);
  const [marketRate, setMarketRate] = useState<number>(8.5); // $8.5M / WAR

  const fairMarketValue = projectedWar * marketRate;
  const surplus = fairMarketValue - salary;
  const isPositive = surplus >= 0;
  const roiMultiplier = salary > 0 ? (fairMarketValue / salary) : 1;

  return (
    <div className="bg-surface-raised/90 border border-slate-800 rounded-xl p-5 shadow-xl">
      <div className="flex items-center gap-2 mb-3">
        <div className="p-1.5 rounded-lg bg-sky-500/10 border border-sky-500/20 text-sky-400">
          <Calculator className="w-4 h-4" />
        </div>
        <div>
          <h3 className="font-bold text-white text-base">Contract ROI & Trade Surplus Calculator</h3>
          <p className="text-xs text-slate-400">
            Interactive valuation simulator comparing real salary against projected win equity
          </p>
        </div>
      </div>

      <div className="grid grid-cols-1 md:grid-cols-3 gap-4 my-4">
        {/* Slider 1: Annual Salary */}
        <div className="bg-surface/70 p-3.5 rounded-lg border border-slate-800">
          <div className="flex justify-between items-center text-xs mb-2">
            <span className="text-slate-400 font-medium">Annual Salary (AAV)</span>
            <span className="font-mono font-bold text-white">${salary.toFixed(1)}M</span>
          </div>
          <input
            type="range"
            min={0.8}
            max={55.0}
            step={0.5}
            value={salary}
            onChange={(e) => setSalary(parseFloat(e.target.value))}
            className="w-full accent-sky-500 h-1.5 bg-slate-800 rounded-lg cursor-pointer"
          />
          <div className="flex justify-between text-[10px] text-slate-400 mt-1">
            <span>$0.8M (Min)</span>
            <span>$25M</span>
            <span>$55M (Max)</span>
          </div>
        </div>

        {/* Slider 2: Projected WAR */}
        <div className="bg-surface/70 p-3.5 rounded-lg border border-slate-800">
          <div className="flex justify-between items-center text-xs mb-2">
            <span className="text-slate-400 font-medium">Projected WAR</span>
            <span className="font-mono font-bold text-sky-400">{projectedWar.toFixed(1)} WAR</span>
          </div>
          <input
            type="range"
            min={-0.5}
            max={10.0}
            step={0.1}
            value={projectedWar}
            onChange={(e) => setProjectedWar(parseFloat(e.target.value))}
            className="w-full accent-sky-500 h-1.5 bg-slate-800 rounded-lg cursor-pointer"
          />
          <div className="flex justify-between text-[10px] text-slate-400 mt-1">
            <span>0.0</span>
            <span>4.0 (All-Star)</span>
            <span>8.0+ (MVP)</span>
          </div>
        </div>

        {/* Slider 3: Cost per WAR Market Rate */}
        <div className="bg-surface/70 p-3.5 rounded-lg border border-slate-800">
          <div className="flex justify-between items-center text-xs mb-2">
            <span className="text-slate-400 font-medium">Market Cost / Win</span>
            <span className="font-mono font-bold text-amber-400">${marketRate.toFixed(1)}M / WAR</span>
          </div>
          <input
            type="range"
            min={7.0}
            max={11.0}
            step={0.25}
            value={marketRate}
            onChange={(e) => setMarketRate(parseFloat(e.target.value))}
            className="w-full accent-amber-500 h-1.5 bg-slate-800 rounded-lg cursor-pointer"
          />
          <div className="flex justify-between text-[10px] text-slate-400 mt-1">
            <span>$7.0M (2020)</span>
            <span>$8.5M (2026)</span>
            <span>$11.0M (Top FA)</span>
          </div>
        </div>
      </div>

      {/* Output Metric Cards */}
      <div className="grid grid-cols-1 sm:grid-cols-3 gap-3 pt-2">
        <div className="p-3 rounded-lg bg-surface/60 border border-slate-800">
          <div className="text-[11px] text-slate-400 flex items-center gap-1.5">
            <DollarSign className="w-3.5 h-3.5 text-slate-400" />
            <span>Fair Market Production Value</span>
          </div>
          <div className="text-lg font-mono font-bold text-white mt-1">
            ${fairMarketValue.toFixed(2)}M
          </div>
          <p className="text-[10.5px] text-slate-400 mt-0.5">
            {projectedWar.toFixed(1)} WAR × ${marketRate.toFixed(1)}M/win
          </p>
        </div>

        <div className={`p-3 rounded-lg border ${
          isPositive
            ? 'bg-emerald-500/10 border-emerald-500/30'
            : 'bg-rose-500/10 border-rose-500/30'
        }`}>
          <div className="text-[11px] text-slate-400 flex items-center gap-1.5">
            {isPositive ? (
              <TrendingUp className="w-3.5 h-3.5 text-emerald-400" />
            ) : (
              <TrendingDown className="w-3.5 h-3.5 text-rose-400" />
            )}
            <span>Net Contract Surplus ROI</span>
          </div>
          <div className={`text-lg font-mono font-extrabold mt-1 ${isPositive ? 'text-emerald-400' : 'text-rose-400'}`}>
            {isPositive ? '+' : ''}${surplus.toFixed(2)}M
          </div>
          <p className="text-[10.5px] text-slate-400 mt-0.5">
            {isPositive ? 'Team friendly contract excess' : 'Underwater commitment'}
          </p>
        </div>

        <div className="p-3 rounded-lg bg-surface/60 border border-slate-800">
          <div className="text-[11px] text-slate-400 flex items-center gap-1.5">
            <Sparkles className="w-3.5 h-3.5 text-sky-400" />
            <span>Contract Efficiency Multiple</span>
          </div>
          <div className="text-lg font-mono font-bold text-sky-400 mt-1">
            {roiMultiplier.toFixed(2)}x
          </div>
          <p className="text-[10.5px] text-slate-400 mt-0.5">
            Value delivered per dollar spent
          </p>
        </div>
      </div>
    </div>
  );
};
