'use client';

import React, { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import {
  AlertCircle,
  ArrowDown,
  ArrowUp,
  ArrowUpDown,
  Calendar,
  CheckCircle2,
  Clock,
  Info,
  Loader2,
  Sparkles,
  X,
} from 'lucide-react';
import { BASE_PATH } from '@/lib/basePath';
import type {
  EfficiencyBaselineComparison,
  GameDetailEnvelope,
  GameExplainabilityPayload,
  InjuryDesignationRow,
  NflBoxCategory,
  NflEfficiencyFactorItem,
  NflGameDetailPayload,
  NflPlayerBoxRow,
  NflTeamComparisonItem,
  PointsWaterfallPayload,
  SecondaryModelSummary,
  WeeklyAttributionDataset,
} from '@/lib/gameDetailTypes';
import type { MatchupGame } from '@/lib/types';
import { TeamLogo } from '@/components/TeamLogo';
import { activateOnKey, ariaSort } from '@/lib/a11y';

export interface GameDetailModalProps {
  matchup: MatchupGame | null;
  onClose: () => void;
  returnFocusTo?: HTMLElement | null;
}

export type DetailTab = 'overview' | 'comparison' | 'box_score' | 'attribution';

type SortDirection = 'asc' | 'desc';

const FOCUSABLE_SELECTOR = [
  'a[href]',
  'button:not([disabled])',
  'input:not([disabled]):not([type="hidden"])',
  'select:not([disabled])',
  'textarea:not([disabled])',
  '[tabindex]:not([tabindex="-1"])',
].join(', ');

function getFocusableElements(container: HTMLElement): HTMLElement[] {
  const candidates = Array.from(container.querySelectorAll<HTMLElement>(FOCUSABLE_SELECTOR));
  return candidates.filter((el) => {
    if (el.hasAttribute('disabled')) return false;
    if (el.closest('[hidden], [inert]')) return false;
    const style = window.getComputedStyle(el);
    return style.display !== 'none' && style.visibility !== 'hidden';
  });
}

function isFiniteNum(value: unknown): value is number {
  return typeof value === 'number' && Number.isFinite(value);
}

function unwrapEnvelope(raw: unknown): NflGameDetailPayload | null {
  if (raw && typeof raw === 'object' && 'data' in raw) {
    const candidate = (raw as GameDetailEnvelope).data;
    if (candidate && typeof candidate === 'object' && 'game_id' in candidate) {
      return candidate;
    }
  }
  if (raw && typeof raw === 'object' && 'game_id' in raw) {
    return raw as NflGameDetailPayload;
  }
  return null;
}

function formatFactorValue(val: number | null | undefined, unit: NflEfficiencyFactorItem['unit']): string {
  if (!isFiniteNum(val)) return '—';
  if (unit === 'pct') return `${val.toFixed(1)}%`;
  if (unit === 'yards') return `${val.toFixed(1)} yds`;
  return `${val > 0 ? '+' : ''}${val.toFixed(2)}`;
}

function getFactorAdvantage(item: NflEfficiencyFactorItem): 'away' | 'home' | 'even' {
  if (!isFiniteNum(item.away_value) || !isFiniteNum(item.home_value)) return 'even';
  if (item.away_value === item.home_value) return 'even';
  const awayHigher = item.away_value > item.home_value;
  if (item.higher_is_better) {
    return awayHigher ? 'away' : 'home';
  }
  return awayHigher ? 'home' : 'away';
}

interface FactorRowProps {
  item: NflEfficiencyFactorItem;
  awayAbbr: string;
  homeAbbr: string;
}

const FactorRow: React.FC<FactorRowProps> = ({ item, awayAbbr, homeAbbr }) => {
  const advantage = getFactorAdvantage(item);
  const awayVal = isFiniteNum(item.away_value) ? Math.max(0, item.away_value) : 0;
  const homeVal = isFiniteNum(item.home_value) ? Math.max(0, item.home_value) : 0;
  const maxVal = Math.max(awayVal, homeVal);
  const scaleMax = maxVal > 0 ? maxVal * 1.15 : 1;
  const awayBarPct = isFiniteNum(item.away_value) ? Math.min(100, (awayVal / scaleMax) * 100) : 0;
  const homeBarPct = isFiniteNum(item.home_value) ? Math.min(100, (homeVal / scaleMax) * 100) : 0;

  return (
    <tr className="border-t border-slate-800/80 align-middle hover:bg-slate-800/20">
      <th scope="row" className="py-2.5 px-3 text-left font-normal">
        <div className="flex flex-wrap items-center gap-2">
          <span className="text-xs font-semibold text-white">{item.label}</span>
          <span className="text-[10px] font-mono text-slate-400 px-1.5 py-0.5 rounded bg-slate-800/80 border border-slate-700/60 uppercase">
            {item.unit}
          </span>
        </div>
        {item.description && (
          <p className="text-[11px] text-slate-400 mt-0.5 leading-snug">{item.description}</p>
        )}
      </th>
      <td
        className={`py-2.5 px-3 text-right font-mono text-xs tabular-nums whitespace-nowrap ${
          advantage === 'away' ? 'text-emerald-400 font-bold' : 'text-slate-300'
        }`}
      >
        {formatFactorValue(item.away_value, item.unit)}
      </td>
      <td className="py-2.5 px-3 min-w-[130px] sm:min-w-[180px]" aria-hidden="true">
        <div className="flex items-center gap-1 h-3 mt-0.5">
          <div className="w-1/2 h-2 bg-slate-800 rounded-l-full overflow-hidden flex justify-end border border-slate-700/50 border-r-0">
            <div
              className={`h-full rounded-l-full transition-all ${
                advantage === 'away' ? 'bg-emerald-400' : 'bg-slate-600'
              }`}
              style={{ width: `${awayBarPct}%` }}
            />
          </div>
          <div className="w-px h-3.5 bg-slate-600 flex-shrink-0" />
          <div className="w-1/2 h-2 bg-slate-800 rounded-r-full overflow-hidden flex justify-start border border-slate-700/50 border-l-0">
            <div
              className={`h-full rounded-r-full transition-all ${
                advantage === 'home' ? 'bg-emerald-400' : 'bg-slate-600'
              }`}
              style={{ width: `${homeBarPct}%` }}
            />
          </div>
        </div>
        <div className="flex justify-between text-[10px] font-mono text-slate-500 mt-0.5">
          <span>{awayAbbr}</span>
          <span>{homeAbbr}</span>
        </div>
      </td>
      <td
        className={`py-2.5 px-3 text-left font-mono text-xs tabular-nums whitespace-nowrap ${
          advantage === 'home' ? 'text-emerald-400 font-bold' : 'text-slate-300'
        }`}
      >
        {formatFactorValue(item.home_value, item.unit)}
      </td>
    </tr>
  );
};

interface TeamComparisonRowProps {
  item: NflTeamComparisonItem;
  awayAbbr: string;
  homeAbbr: string;
}

const TeamComparisonRow: React.FC<TeamComparisonRowProps> = ({ item, awayAbbr, homeAbbr }) => {
  const awayNum = isFiniteNum(item.away_value) ? item.away_value : null;
  const homeNum = isFiniteNum(item.home_value) ? item.home_value : null;
  const isNumeric = awayNum !== null && homeNum !== null;
  const awayAdvantage = isNumeric && awayNum! > homeNum!;
  const homeAdvantage = isNumeric && homeNum! > awayNum!;

  const sumVal = isNumeric ? Math.max(1, Math.abs(awayNum!) + Math.abs(homeNum!)) : 1;
  const awayWidthPct = isNumeric ? Math.min(100, Math.max(5, (Math.abs(awayNum!) / sumVal) * 100)) : 50;
  const homeWidthPct = isNumeric ? Math.min(100, Math.max(5, (Math.abs(homeNum!) / sumVal) * 100)) : 50;

  return (
    <div className="bg-slate-950/40 border border-slate-800 rounded-xl p-3.5 space-y-2.5">
      <div className="flex items-center justify-between">
        <span className="text-xs font-semibold text-slate-200">{item.label}</span>
      </div>
      <div className="flex items-baseline justify-between font-mono tabular-nums">
        <div className="flex items-baseline gap-1.5">
          <span className="text-[11px] text-slate-500">{awayAbbr}</span>
          <span className={`text-sm font-bold ${awayAdvantage ? 'text-emerald-400' : 'text-white'}`}>
            {item.away_value != null ? String(item.away_value) : '—'}
          </span>
        </div>
        <div className="flex items-baseline gap-1.5">
          <span className={`text-sm font-bold ${homeAdvantage ? 'text-emerald-400' : 'text-white'}`}>
            {item.home_value != null ? String(item.home_value) : '—'}
          </span>
          <span className="text-[11px] text-slate-500">{homeAbbr}</span>
        </div>
      </div>
      {isNumeric && (
        <div className="w-full h-1.5 rounded-full bg-slate-800 overflow-hidden flex" aria-hidden="true">
          <div
            className={`h-full ${awayAdvantage ? 'bg-emerald-400' : 'bg-slate-600'}`}
            style={{ width: `${awayWidthPct}%` }}
          />
          <div
            className={`h-full ${homeAdvantage ? 'bg-emerald-400' : 'bg-slate-700'}`}
            style={{ width: `${homeWidthPct}%` }}
          />
        </div>
      )}
    </div>
  );
};

export interface PointsWaterfallCardProps {
  waterfall: PointsWaterfallPayload;
  homeAbbr: string;
  awayAbbr: string;
  projectionBasis?: string | null;
}

export const PointsWaterfallCard: React.FC<PointsWaterfallCardProps> = ({
  waterfall,
  homeAbbr,
  awayAbbr,
  projectionBasis,
}) => {
  const steps = useMemo(() => {
    const list = [...(waterfall.steps ?? [])];
    const hasRounding = list.some(
      (s) => s.key === 'step_rounding' || s.label.toLowerCase() === 'rounding',
    );
    if (!hasRounding && typeof waterfall.rounding === 'number') {
      list.push({
        key: 'step_rounding',
        label: 'Rounding',
        points: waterfall.rounding,
        description: 'Decomposition residual',
      });
    }
    return list;
  }, [waterfall]);

  const maxStepPoints = useMemo(() => {
    const pts = steps.map((s) => Math.abs(s.points));
    return Math.max(1, ...pts);
  }, [steps]);

  const stepsSum = useMemo(() => {
    return steps.reduce((sum, s) => sum + s.points, 0);
  }, [steps]);

  const marginDiscrepancy = Math.abs(stepsSum - waterfall.projected_margin);

  return (
    <div
      className="bg-slate-950/60 border border-slate-800 rounded-xl p-4 sm:p-5 space-y-4"
      data-testid="points-waterfall-card"
    >
      <div className="flex flex-wrap items-center justify-between gap-2 border-b border-slate-800/80 pb-3">
        <div>
          <h3 className="text-xs font-mono font-bold uppercase tracking-wider text-slate-300">
            5-Step Points Waterfall
          </h3>
          <p className="text-[11px] text-slate-400 mt-0.5">
            Forecast decomposed into 5 additive factors plus residual rounding (points from home perspective).
          </p>
        </div>
        <div>
          {projectionBasis === 'logged_pregame' ? (
            <span className="px-2 py-0.5 rounded-full text-[10px] font-mono font-semibold bg-emerald-500/15 text-emerald-400 border border-emerald-500/30">
              Pre-Game Forecast
            </span>
          ) : projectionBasis === 'backtest_preweek' ? (
            <span className="px-2 py-0.5 rounded-full text-[10px] font-mono font-semibold bg-indigo-500/15 text-indigo-300 border border-indigo-500/30">
              Backtest (Pre-Week)
            </span>
          ) : (
            <span className="px-2 py-0.5 rounded-full text-[10px] font-mono font-semibold bg-slate-800 text-slate-300 border border-slate-700">
              Primary Ensemble
            </span>
          )}
        </div>
      </div>

      {/* Steps Table / Bars */}
      <div className="space-y-3">
        <div className="flex items-center justify-between text-[10px] font-mono text-slate-500 uppercase px-1">
          <span>Factor / Step</span>
          <div className="flex items-center gap-6">
            <span>{awayAbbr} &larr; Advantage &rarr; {homeAbbr}</span>
            <span className="w-16 text-right">Points</span>
          </div>
        </div>

        <div className="space-y-2">
          {steps.map((step) => {
            const isHomeAdv = step.points > 0.001;
            const isAwayAdv = step.points < -0.001;
            const barWidth = Math.min(100, (Math.abs(step.points) / maxStepPoints) * 100);

            return (
              <div
                key={step.key}
                className="bg-slate-900/60 border border-slate-800/80 rounded-lg p-2.5 flex flex-col sm:flex-row sm:items-center justify-between gap-2"
                data-testid={`waterfall-step-${step.key}`}
              >
                <div className="min-w-0 flex-1">
                  <div className="flex items-center gap-2">
                    <span className="text-xs font-semibold text-white">{step.label}</span>
                    {step.key === 'step_rounding' && (
                      <span className="text-[10px] font-mono text-slate-500 px-1 py-0.2 rounded bg-slate-800 border border-slate-700/60">
                        &le; 0.02
                      </span>
                    )}
                  </div>
                  {step.description && (
                    <p className="text-[11px] text-slate-400 mt-0.5 leading-tight">{step.description}</p>
                  )}
                </div>

                <div className="flex items-center gap-3 flex-shrink-0">
                  {/* Signed Relative Bar */}
                  <div className="w-32 sm:w-44 flex items-center gap-1 h-2.5" aria-hidden="true">
                    <div className="w-1/2 h-full bg-slate-800 rounded-l-full overflow-hidden flex justify-end">
                      <div
                        className={`h-full rounded-l-full transition-all ${
                          isAwayAdv ? 'bg-amber-400' : 'bg-transparent'
                        }`}
                        style={{ width: `${isAwayAdv ? barWidth : 0}%` }}
                      />
                    </div>
                    <div className="w-px h-3.5 bg-slate-600 flex-shrink-0" />
                    <div className="w-1/2 h-full bg-slate-800 rounded-r-full overflow-hidden flex justify-start">
                      <div
                        className={`h-full rounded-r-full transition-all ${
                          isHomeAdv ? 'bg-emerald-400' : 'bg-transparent'
                        }`}
                        style={{ width: `${isHomeAdv ? barWidth : 0}%` }}
                      />
                    </div>
                  </div>

                  {/* Points value */}
                  <div
                    className={`w-16 text-right font-mono text-xs tabular-nums font-bold ${
                      isHomeAdv ? 'text-emerald-400' : isAwayAdv ? 'text-amber-400' : 'text-slate-400'
                    }`}
                  >
                    {step.points > 0 ? `+${step.points.toFixed(2)}` : step.points.toFixed(2)}
                  </div>
                </div>
              </div>
            );
          })}
        </div>
      </div>

      {/* Waterfall Total Summary */}
      <div className="border-t border-slate-800/80 pt-3 flex flex-wrap items-center justify-between gap-3 text-xs font-mono">
        <div className="space-y-0.5">
          <div className="flex items-center gap-2">
            <span className="text-slate-400">Sum of Steps:</span>
            <span className="font-bold text-white tabular-nums">
              {stepsSum > 0 ? `+${stepsSum.toFixed(2)}` : stepsSum.toFixed(2)} pts
            </span>
            <span className="text-slate-500">•</span>
            <span className="text-slate-400">Projected Margin:</span>
            <span className="font-bold text-emerald-400 tabular-nums">
              {waterfall.projected_margin > 0
                ? `+${waterfall.projected_margin.toFixed(2)}`
                : waterfall.projected_margin.toFixed(2)}{' '}
              pts
            </span>
          </div>
          <div className="text-[11px] text-slate-500">
            Win probability: {(waterfall.home_win_prob * 100).toFixed(1)}% via Φ(margin /{' '}
            {waterfall.sigma?.toFixed(2) ?? '14.60'}).
            {marginDiscrepancy <= 0.02 && (
              <span className="text-emerald-500 ml-1">✓ Additivity verified (&le; 0.02)</span>
            )}
          </div>
        </div>
        <div className="text-right">
          <span className="text-[11px] text-slate-400 uppercase tracking-wider block">Home Win Prob</span>
          <span className="text-sm font-bold text-emerald-400 tabular-nums">
            {(waterfall.home_win_prob * 100).toFixed(1)}%
          </span>
        </div>
      </div>
    </div>
  );
};

export interface SecondaryShapCardProps {
  secondaryModel: SecondaryModelSummary;
  homeAbbr: string;
  awayAbbr: string;
}

export const SecondaryShapCard: React.FC<SecondaryShapCardProps> = ({
  secondaryModel,
  homeAbbr,
  awayAbbr,
}) => {
  const [showAllFactors, setShowAllFactors] = useState<boolean>(false);

  const sortedFactors = useMemo(() => {
    return [...(secondaryModel.factors ?? [])].sort(
      (a, b) => Math.abs(b.shap_value) - Math.abs(a.shap_value),
    );
  }, [secondaryModel.factors]);

  const displayedFactors = showAllFactors ? sortedFactors : sortedFactors.slice(0, 6);

  const maxShapAbs = useMemo(() => {
    const vals = sortedFactors.map((f) => Math.abs(f.shap_value));
    return Math.max(0.1, ...vals);
  }, [sortedFactors]);

  const shapSum = useMemo(() => {
    return sortedFactors.reduce((acc, f) => acc + f.shap_value, 0);
  }, [sortedFactors]);

  const agrees = secondaryModel.agreement === 'agree';

  return (
    <div
      className="bg-slate-950/60 border border-slate-800 rounded-xl p-4 sm:p-5 space-y-4"
      data-testid="secondary-shap-card"
    >
      <div className="flex flex-wrap items-center justify-between gap-2 border-b border-slate-800/80 pb-3">
        <div>
          <div className="flex items-center gap-2">
            <h3 className="text-xs font-mono font-bold uppercase tracking-wider text-slate-300">
              {secondaryModel.model_label || 'Secondary Model (TreeSHAP)'}
            </h3>
            <span
              className={`px-2 py-0.5 rounded-full text-[10px] font-mono font-semibold flex items-center gap-1 border ${
                agrees
                  ? 'bg-emerald-500/15 text-emerald-400 border-emerald-500/30'
                  : 'bg-amber-500/15 text-amber-400 border-amber-500/30'
              }`}
              data-testid="secondary-agreement-badge"
            >
              {agrees ? (
                <>
                  <CheckCircle2 className="w-3 h-3" /> Agrees with Primary Pick
                </>
              ) : (
                <>
                  <AlertCircle className="w-3 h-3" /> Differs from Primary Pick
                </>
              )}
            </span>
          </div>
          <p className="text-[11px] text-slate-400 mt-0.5">
            Deterministic XGBoost TreeSHAP model trained on strictly historical seasons with entering signals only.
          </p>
        </div>

        <div className="text-right">
          <span className="text-[10px] font-mono text-slate-400 uppercase tracking-wider block">Model Win Prob</span>
          <span className="text-sm font-mono font-bold text-white tabular-nums">
            {(secondaryModel.model_win_prob * 100).toFixed(1)}%
          </span>
        </div>
      </div>

      {/* Out-of-sample track record */}
      {secondaryModel.out_of_sample_record && (
        <div
          className="bg-slate-900/60 border border-slate-800/80 rounded-xl p-3 space-y-1.5"
          data-testid="secondary-track-record"
        >
          <div className="flex items-center justify-between text-[10px] font-mono text-slate-400 uppercase tracking-wider font-semibold">
            <span>Published Out-of-Sample Track Record</span>
            <span className="text-slate-500">Walk-forward validation</span>
          </div>
          <div className="grid grid-cols-4 gap-2 text-center font-mono">
            <div className="bg-slate-950/80 p-2 rounded-lg border border-slate-800/60">
              <span className="text-[10px] text-slate-500 block uppercase">Games</span>
              <span className="text-xs font-bold text-white">{secondaryModel.out_of_sample_record.n_games}</span>
            </div>
            <div className="bg-slate-950/80 p-2 rounded-lg border border-slate-800/60">
              <span className="text-[10px] text-slate-500 block uppercase">Accuracy</span>
              <span className="text-xs font-bold text-emerald-400">
                {secondaryModel.out_of_sample_record.accuracy.toFixed(1)}%
              </span>
            </div>
            <div className="bg-slate-950/80 p-2 rounded-lg border border-slate-800/60">
              <span className="text-[10px] text-slate-500 block uppercase">Brier</span>
              <span className="text-xs font-bold text-slate-200">
                {secondaryModel.out_of_sample_record.brier.toFixed(4)}
              </span>
            </div>
            <div className="bg-slate-950/80 p-2 rounded-lg border border-slate-800/60">
              <span className="text-[10px] text-slate-500 block uppercase">Log Loss</span>
              <span className="text-xs font-bold text-slate-200">
                {secondaryModel.out_of_sample_record.logloss.toFixed(4)}
              </span>
            </div>
          </div>
        </div>
      )}

      {/* TreeSHAP Feature Attribution Bars */}
      <div className="space-y-3">
        <div className="flex items-center justify-between text-[10px] font-mono text-slate-500 uppercase px-1">
          <span>Entering Signal</span>
          <div className="flex items-center gap-6">
            <span>{awayAbbr} &larr; Impact &rarr; {homeAbbr}</span>
            <span className="w-16 text-right">SHAP (Log-Odds)</span>
          </div>
        </div>

        <div className="space-y-2">
          {displayedFactors.map((factor) => {
            const isHomeAdv = factor.shap_value > 0.0001;
            const isAwayAdv = factor.shap_value < -0.0001;
            const barWidth = Math.min(100, (Math.abs(factor.shap_value) / maxShapAbs) * 100);

            return (
              <div
                key={factor.feature}
                className="bg-slate-900/60 border border-slate-800/80 rounded-lg p-2.5 flex flex-col sm:flex-row sm:items-center justify-between gap-2"
                data-testid={`shap-factor-${factor.feature}`}
              >
                <div className="min-w-0 flex-1">
                  <span className="text-xs font-semibold text-white block">{factor.label}</span>
                  <span className="text-[11px] font-mono text-slate-400">
                    Entering Value: {isFiniteNum(factor.value) ? factor.value.toFixed(2) : '—'}
                  </span>
                </div>

                <div className="flex items-center gap-3 flex-shrink-0">
                  {/* Centered signed bar */}
                  <div className="w-32 sm:w-44 flex items-center gap-1 h-2.5" aria-hidden="true">
                    <div className="w-1/2 h-full bg-slate-800 rounded-l-full overflow-hidden flex justify-end">
                      <div
                        className={`h-full rounded-l-full transition-all ${
                          isAwayAdv ? 'bg-amber-400' : 'bg-transparent'
                        }`}
                        style={{ width: `${isAwayAdv ? barWidth : 0}%` }}
                      />
                    </div>
                    <div className="w-px h-3.5 bg-slate-600 flex-shrink-0" />
                    <div className="w-1/2 h-full bg-slate-800 rounded-r-full overflow-hidden flex justify-start">
                      <div
                        className={`h-full rounded-r-full transition-all ${
                          isHomeAdv ? 'bg-emerald-400' : 'bg-transparent'
                        }`}
                        style={{ width: `${isHomeAdv ? barWidth : 0}%` }}
                      />
                    </div>
                  </div>

                  <div
                    className={`w-16 text-right font-mono text-xs tabular-nums font-bold ${
                      isHomeAdv ? 'text-emerald-400' : isAwayAdv ? 'text-amber-400' : 'text-slate-400'
                    }`}
                  >
                    {factor.shap_value > 0 ? `+${factor.shap_value.toFixed(4)}` : factor.shap_value.toFixed(4)}
                  </div>
                </div>
              </div>
            );
          })}
        </div>

        {sortedFactors.length > 6 && (
          <div className="pt-1 text-center">
            <button
              type="button"
              onClick={() => setShowAllFactors((prev) => !prev)}
              className="text-xs font-mono font-semibold text-emerald-400 hover:text-emerald-300 py-1 px-3 rounded-lg bg-slate-900 border border-slate-800 hover:border-slate-700 transition-colors"
            >
              {showAllFactors ? 'Show Top 6 Features' : `Show All ${sortedFactors.length} Features`}
            </button>
          </div>
        )}
      </div>

      {/* Additivity description note */}
      <div className="border-t border-slate-800/80 pt-3 text-[11px] font-mono text-slate-400 flex flex-wrap items-center justify-between gap-2">
        <div>
          TreeSHAP Additivity: Base Value ({secondaryModel.base_value.toFixed(3)}) + &sum; SHAP ({shapSum.toFixed(3)}) = Logit ({secondaryModel.logit.toFixed(3)}).
        </div>
        <div className="text-slate-500">
          &sigma;(Logit) = {(secondaryModel.model_win_prob * 100).toFixed(1)}% (&plusmn;1e-4)
        </div>
      </div>
    </div>
  );
};

export interface EnteringBaselinesCardProps {
  baselines: EfficiencyBaselineComparison[];
  divergenceNote: string | null;
  homeAbbr: string;
  awayAbbr: string;
  isCompleted: boolean;
}

export const EnteringBaselinesCard: React.FC<EnteringBaselinesCardProps> = ({
  baselines,
  divergenceNote,
  homeAbbr,
  awayAbbr,
  isCompleted,
}) => {
  const hasLowSample = useMemo(() => {
    return baselines.some((b) => b.is_low_sample);
  }, [baselines]);

  const formatBaselineValue = (val: number | null): string => {
    if (val === null || !isFiniteNum(val)) return '—';
    return val > 0 ? `+${val.toFixed(3)}` : val.toFixed(3);
  };

  return (
    <div
      className="bg-slate-950/60 border border-slate-800 rounded-xl p-4 sm:p-5 space-y-4"
      data-testid="entering-baselines-card"
    >
      <div className="border-b border-slate-800/80 pb-3 space-y-1">
        <div className="flex items-center justify-between">
          <h3 className="text-xs font-mono font-bold uppercase tracking-wider text-slate-300">
            Entering Efficiency Baselines
          </h3>
          <span className="text-[11px] font-mono text-slate-500">Strictly prior games</span>
        </div>
        <p className="text-[11px] text-slate-400 leading-snug">
          Season-to-date efficiency metrics entering the game, computed over strictly prior games (week &lt; current game week).
        </p>
      </div>

      {hasLowSample && (
        <div className="flex items-center gap-2 p-2.5 rounded-lg bg-amber-500/10 border border-amber-500/20 text-xs text-amber-300">
          <AlertCircle className="w-4 h-4 flex-shrink-0" />
          <span>Low sample alert: Fewer than 4 prior games recorded this season. Baselines carry higher uncertainty.</span>
        </div>
      )}

      {/* 10-row baseline comparison table */}
      <div className="border border-slate-800 rounded-xl overflow-hidden bg-slate-950/40">
        <div className="overflow-x-auto">
          <table className="w-full text-left text-xs">
            <thead className="bg-slate-900/80 font-mono text-[11px] text-slate-400 uppercase tracking-wider border-b border-slate-800">
              <tr>
                <th className="py-2.5 px-3">Team</th>
                <th className="py-2.5 px-3">Metric</th>
                <th className="py-2.5 px-3 text-center">Prior Games</th>
                <th className="py-2.5 px-3 text-right">Entering Baseline</th>
                <th className="py-2.5 px-3 text-right">Realized</th>
                <th className="py-2.5 px-3 text-right">Delta</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-slate-800/60 font-mono tabular-nums">
              {baselines.map((row, idx) => {
                const deltaNum = isFiniteNum(row.delta) ? row.delta : null;
                const deltaClass =
                  deltaNum === null
                    ? 'text-slate-400'
                    : deltaNum > 0
                    ? 'text-emerald-400 font-semibold'
                    : deltaNum < 0
                    ? 'text-rose-400 font-semibold'
                    : 'text-slate-300';

                return (
                  <tr key={`${row.team_abbr}-${row.metric_key}-${idx}`} className="hover:bg-slate-800/20">
                    <td className="py-2 px-3 font-bold text-white">
                      {row.team_abbr ?? (idx < 5 ? awayAbbr : homeAbbr)}
                    </td>
                    <td className="py-2 px-3 font-sans text-slate-200">{row.metric_label}</td>
                    <td className="py-2 px-3 text-center text-slate-400">{row.prior_games_n}</td>
                    <td className="py-2 px-3 text-right text-slate-300">
                      {formatBaselineValue(row.entering_baseline)}
                    </td>
                    <td className="py-2 px-3 text-right text-slate-300">
                      {formatBaselineValue(row.realized_value)}
                    </td>
                    <td className={`py-2 px-3 text-right ${deltaClass}`}>
                      {deltaNum !== null ? (deltaNum > 0 ? `+${deltaNum.toFixed(3)}` : deltaNum.toFixed(3)) : '—'}
                    </td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        </div>
      </div>

      {/* Divergence note callout */}
      {divergenceNote ? (
        <div
          className="bg-slate-900/60 border border-slate-800 rounded-xl p-3.5 space-y-1.5"
          data-testid="divergence-note-callout"
        >
          <div className="flex items-center gap-1.5 text-xs font-mono font-semibold text-emerald-400">
            <Sparkles className="w-4 h-4" />
            <span>Largest Baseline Divergence</span>
          </div>
          <p className="text-xs font-mono text-slate-200">{divergenceNote}</p>
          <p className="text-[11px] text-slate-500 italic">
            Descriptive indicator of largest divergence between entering baseline and realized game performance; makes no causal claim.
          </p>
        </div>
      ) : (
        <div className="bg-slate-900/30 border border-slate-800/60 rounded-xl p-3 text-xs text-slate-500 italic font-mono">
          {isCompleted
            ? 'No significant baseline divergence recorded for this game (or play-by-play data is pending ingest).'
            : 'Baseline divergence will be calculated after the game concludes and efficiency data is ingested.'}
        </div>
      )}
    </div>
  );
};

export const GameDetailModal: React.FC<GameDetailModalProps> = ({
  matchup,
  onClose,
  returnFocusTo,
}) => {
  const [detail, setDetail] = useState<NflGameDetailPayload | null>(null);
  const [loading, setLoading] = useState<boolean>(false);
  const [fetchError, setFetchError] = useState<string | null>(null);
  const [activeTab, setActiveTab] = useState<DetailTab>(
    matchup && !matchup.is_completed ? 'attribution' : 'overview',
  );
  const [boxCategory, setBoxCategory] = useState<NflBoxCategory>('passing');
  const [boxTeamFilter, setBoxTeamFilter] = useState<'both' | 'away' | 'home'>('both');
  const [sortKey, setSortKey] = useState<string | null>(null);
  const [sortDir, setSortDir] = useState<SortDirection>('desc');

  const dialogRef = useRef<HTMLDivElement | null>(null);
  const closeButtonRef = useRef<HTMLButtonElement | null>(null);
  const openerRef = useRef<HTMLElement | null>(null);
  const restoredFocusRef = useRef<boolean>(false);
  const prevOpenRef = useRef<boolean>(false);

  const isOpen = matchup !== null;
  const gameId = matchup?.game_id ?? null;

  const restoreOpenerFocus = useCallback(() => {
    if (restoredFocusRef.current) return;
    const target = returnFocusTo ?? openerRef.current;
    if (target && target.isConnected) {
      target.focus();
    }
    restoredFocusRef.current = true;
    openerRef.current = null;
  }, [returnFocusTo]);

  const handleClose = useCallback(() => {
    restoreOpenerFocus();
    onClose();
  }, [restoreOpenerFocus, onClose]);

  // Deep-link sync: sync ?game={game_id} in URL search params without page reload; remove on close.
  useEffect(() => {
    if (typeof window === 'undefined') return;
    const url = new URL(window.location.href);
    const existing = url.searchParams.get('game');

    if (gameId) {
      if (existing !== gameId) {
        url.searchParams.set('game', gameId);
        window.history.replaceState(null, '', url.toString());
      }
    } else if (existing !== null) {
      url.searchParams.delete('game');
      const searchStr = url.searchParams.toString();
      const nextPath = url.pathname + (searchStr ? `?${searchStr}` : '') + url.hash;
      window.history.replaceState(null, '', nextPath);
    }
  }, [gameId]);

  useEffect(() => {
    return () => {
      if (typeof window === 'undefined') return;
      const url = new URL(window.location.href);
      if (url.searchParams.has('game')) {
        url.searchParams.delete('game');
        const searchStr = url.searchParams.toString();
        const nextPath = url.pathname + (searchStr ? `?${searchStr}` : '') + url.hash;
        window.history.replaceState(null, '', nextPath);
      }
    };
  }, []);

  // Opener focus capture & initial focus
  useEffect(() => {
    const wasOpen = prevOpenRef.current;
    prevOpenRef.current = isOpen;

    if (isOpen && !wasOpen) {
      restoredFocusRef.current = false;
      const activeEl = document.activeElement;
      if (returnFocusTo) {
        openerRef.current = returnFocusTo;
      } else if (
        activeEl instanceof HTMLElement &&
        (!dialogRef.current || !dialogRef.current.contains(activeEl))
      ) {
        openerRef.current = activeEl;
      }

      if (dialogRef.current && !dialogRef.current.contains(document.activeElement)) {
        if (closeButtonRef.current) {
          closeButtonRef.current.focus();
        } else {
          dialogRef.current.focus();
        }
      }
    } else if (!isOpen && wasOpen) {
      restoreOpenerFocus();
    }
  }, [isOpen, returnFocusTo, restoreOpenerFocus]);

  // Trap Tab and Escape key inside modal
  useEffect(() => {
    if (!isOpen) return;

    const handleKeyDown = (e: KeyboardEvent) => {
      if (e.key === 'Escape') {
        e.preventDefault();
        e.stopPropagation();
        handleClose();
        return;
      }

      if (e.key === 'Tab') {
        const dialogEl = dialogRef.current;
        if (!dialogEl) return;

        const focusables = getFocusableElements(dialogEl);
        if (focusables.length === 0) {
          e.preventDefault();
          dialogEl.focus();
          return;
        }

        const first = focusables[0];
        const last = focusables[focusables.length - 1];
        const active = document.activeElement instanceof HTMLElement ? document.activeElement : null;

        if (e.shiftKey) {
          if (!active || !dialogEl.contains(active) || active === first || active === dialogEl) {
            e.preventDefault();
            last.focus();
          }
        } else if (!active || !dialogEl.contains(active) || active === last) {
          e.preventDefault();
          first.focus();
        }
      }
    };

    document.addEventListener('keydown', handleKeyDown);
    return () => {
      document.removeEventListener('keydown', handleKeyDown);
    };
  }, [isOpen, handleClose]);

  // Fetch game detail payload
  useEffect(() => {
    if (!gameId || !matchup) {
      setDetail(null);
      setLoading(false);
      setFetchError(null);
      return;
    }

    let cancelled = false;
    setLoading(true);
    setFetchError(null);

    const fetchDetail = async () => {
      try {
        if (matchup.is_completed) {
          const res = await fetch(`${BASE_PATH}/data/games/${gameId}.json`);
          if (!res.ok) {
            throw new Error(`HTTP ${res.status}`);
          }
          const raw = await res.json();
          const payload = unwrapEnvelope(raw);
          if (!cancelled) {
            setDetail(payload);
            setLoading(false);
          }
        } else {
          const season = matchup.season ?? 2026;
          const week = matchup.week;
          const res = await fetch(`${BASE_PATH}/data/week_attribution/${season}_${week}.json`);
          if (!res.ok) {
            throw new Error(`HTTP ${res.status}`);
          }
          const raw: WeeklyAttributionDataset = await res.json();
          const explainData: GameExplainabilityPayload | null =
            raw && Array.isArray(raw.games)
              ? raw.games.find((g: GameExplainabilityPayload) => g.game_id === gameId) ?? null
              : null;

          const synthesizedPayload: NflGameDetailPayload = {
            game_id: matchup.game_id,
            season: matchup.season,
            season_label: `${matchup.season}-${matchup.season + 1}`,
            week: matchup.week,
            week_label: `Week ${matchup.week}`,
            gameday: matchup.gameday,
            weekday: matchup.weekday,
            gametime: matchup.gametime,
            is_completed: false,
            has_box_score: false,
            away_team: {
              teamAbbr: matchup.away_team,
              teamName: matchup.away_team_name,
              score: null,
              is_winner: null,
            },
            home_team: {
              teamAbbr: matchup.home_team,
              teamName: matchup.home_team_name,
              score: null,
              is_winner: null,
            },
            forecast: {
              projected_margin: explainData?.predicted_margin ?? matchup.projected_margin ?? null,
              home_win_prob: explainData?.predicted_home_win_prob ?? matchup.home_win_prob ?? null,
              away_win_prob:
                explainData?.predicted_home_win_prob != null
                  ? 1 - explainData.predicted_home_win_prob
                  : matchup.away_win_prob ?? null,
              home_power_rating: matchup.home_power_rating ?? null,
              away_power_rating: matchup.away_power_rating ?? null,
              prediction_correct: null,
            },
            efficiency_factors: null,
            team_stats: null,
            leaders: null,
            box_score: null,
            injury_designations: null,
            explainability: explainData,
          };

          if (!cancelled) {
            setDetail(synthesizedPayload);
            setLoading(false);
          }
        }
      } catch (err: unknown) {
        if (!cancelled) {
          const msg = err instanceof Error ? err.message : 'Failed to load';
          setFetchError(msg);
          setDetail(null);
          setLoading(false);
        }
      }
    };

    fetchDetail();

    return () => {
      cancelled = true;
    };
  }, [gameId, matchup]);

  // Reset tab selection on game change
  useEffect(() => {
    setActiveTab(matchup && !matchup.is_completed ? 'attribution' : 'overview');
    setBoxCategory('passing');
    setBoxTeamFilter('both');
    setSortKey(null);
    setSortDir('desc');
  }, [gameId, matchup]);

  // Derived state
  const isCompleted = matchup?.is_completed ?? detail?.is_completed ?? false;
  const hasBoxScore = (matchup?.has_box_score !== false) && (detail?.has_box_score !== false) && !fetchError;
  const weekLabel = detail?.week_label ?? (matchup?.week ? `Week ${matchup.week}` : 'Matchup');

  // Forecast data from detail or matchup
  const forecast = detail?.forecast ?? null;
  const hasProjection =
    (matchup?.has_projection && matchup?.projected_margin != null) ||
    (forecast?.projected_margin != null);

  const homePowerRating = forecast?.home_power_rating ?? matchup?.home_power_rating ?? null;
  const awayPowerRating = forecast?.away_power_rating ?? matchup?.away_power_rating ?? null;
  const projMargin = forecast?.projected_margin ?? matchup?.projected_margin ?? null;

  // Efficiency factors
  const efficiencyFactors = detail?.efficiency_factors ?? null;
  const teamStats = detail?.team_stats ?? null;
  const leaders = detail?.leaders ?? null;

  // Box score players
  const awayPlayers = useMemo(() => detail?.box_score?.away_players ?? [], [detail]);
  const homePlayers = useMemo(() => detail?.box_score?.home_players ?? [], [detail]);

  const displayedPlayers = useMemo(() => {
    let pool: NflPlayerBoxRow[] = [];
    if (boxTeamFilter === 'both') {
      pool = [...awayPlayers, ...homePlayers];
    } else if (boxTeamFilter === 'away') {
      pool = awayPlayers;
    } else {
      pool = homePlayers;
    }

    // Filter by active category
    const filtered = pool.filter((p) => {
      if (p.categories && p.categories.includes(boxCategory)) return true;
      if (boxCategory === 'passing') return (p.attempts ?? 0) > 0 || (p.passing_yards ?? 0) > 0;
      if (boxCategory === 'rushing') return (p.carries ?? 0) > 0 || (p.rushing_yards ?? 0) > 0;
      if (boxCategory === 'receiving') return (p.targets ?? 0) > 0 || (p.receptions ?? 0) > 0;
      if (boxCategory === 'defense') {
        return (
          (p.def_tackles_solo ?? 0) > 0 ||
          (p.def_tackle_assists ?? 0) > 0 ||
          (p.def_sacks ?? 0) > 0 ||
          (p.def_interceptions ?? 0) > 0
        );
      }
      if (boxCategory === 'kicking') return (p.fg_att ?? 0) > 0 || (p.pat_att ?? 0) > 0;
      return false;
    });

    if (!sortKey) return filtered;

    return [...filtered].sort((a, b) => {
      const aVal = (a as unknown as Record<string, unknown>)[sortKey];
      const bVal = (b as unknown as Record<string, unknown>)[sortKey];
      const aNum = isFiniteNum(aVal) ? (aVal as number) : null;
      const bNum = isFiniteNum(bVal) ? (bVal as number) : null;

      if (aNum === null && bNum === null) return a.playerName.localeCompare(b.playerName);
      if (aNum === null) return 1;
      if (bNum === null) return -1;
      return sortDir === 'asc' ? aNum - bNum : bNum - aNum;
    });
  }, [awayPlayers, homePlayers, boxCategory, boxTeamFilter, sortKey, sortDir]);

  const injuryDesignations: InjuryDesignationRow[] = detail?.injury_designations ?? [];

  const handleSort = (key: string) => {
    if (sortKey === key) {
      setSortDir((prev) => (prev === 'asc' ? 'desc' : 'asc'));
    } else {
      setSortKey(key);
      setSortDir('desc');
    }
  };

  const renderSortIndicator = (key: string) => {
    if (sortKey !== key) {
      return <ArrowUpDown className="w-3 h-3 text-slate-500 inline ml-1" aria-hidden="true" />;
    }
    return sortDir === 'asc' ? (
      <ArrowUp className="w-3 h-3 text-emerald-400 inline ml-1" aria-hidden="true" />
    ) : (
      <ArrowDown className="w-3 h-3 text-emerald-400 inline ml-1" aria-hidden="true" />
    );
  };

  if (!isOpen || !matchup) return null;

  return (
    <div
      className="fixed inset-0 z-50 flex items-center justify-center p-2 sm:p-4 bg-slate-950/80 backdrop-blur-sm transition-opacity"
      onClick={handleClose}
      data-testid="game-detail-backdrop"
    >
      <div
        ref={dialogRef}
        role="dialog"
        aria-modal="true"
        aria-labelledby="game-detail-modal-title"
        className="bg-slate-900 border border-slate-800 rounded-2xl w-full max-w-4xl max-h-[92vh] flex flex-col shadow-2xl overflow-hidden focus:outline-none"
        tabIndex={-1}
        onClick={(e) => e.stopPropagation()}
      >
        {/* Modal Header */}
        <div className="p-4 sm:p-5 bg-slate-950/70 border-b border-slate-800 relative flex-shrink-0">
          <button
            ref={closeButtonRef}
            type="button"
            onClick={handleClose}
            aria-label="Close modal"
            className="absolute top-4 right-4 p-1.5 rounded-lg text-slate-400 hover:text-white hover:bg-slate-800 transition-colors focus:outline-none focus:ring-2 focus:ring-emerald-500/60"
          >
            <X className="w-5 h-5" />
          </button>

          {/* Subheader info: week, date, kickoff/final */}
          <div className="flex flex-wrap items-center gap-2 text-xs font-mono text-slate-400 mb-3 pr-8">
            <span className="px-2 py-0.5 rounded bg-slate-800 text-slate-300 font-semibold border border-slate-700/60">
              {weekLabel}
            </span>
            <span className="text-slate-600">•</span>
            <span className="flex items-center gap-1 text-slate-300">
              <Calendar className="w-3.5 h-3.5 text-slate-500" />
              {matchup.weekday ? `${matchup.weekday.slice(0, 3)}, ` : ''}
              {matchup.gameday}
            </span>
            <span className="text-slate-600">•</span>
            {isCompleted ? (
              <span className="px-1.5 py-0.5 rounded bg-slate-800 text-emerald-400 font-bold border border-slate-700 tracking-wide text-[11px]">
                FINAL
              </span>
            ) : (
              <span className="flex items-center gap-1 text-slate-300">
                <Clock className="w-3.5 h-3.5 text-emerald-400" />
                {matchup.gametime ? `${matchup.gametime} ET` : 'TBD'}
              </span>
            )}
          </div>

          {/* Teams Arena Banner */}
          <div className="grid grid-cols-5 items-center gap-2">
            {/* Away Team */}
            <div className="col-span-2 flex items-center gap-3">
              <TeamLogo team={matchup.away_team} size="lg" />
              <div className="min-w-0">
                <span className="text-[10px] font-mono text-slate-400 uppercase tracking-wider block">
                  Away
                </span>
                <span className="text-sm sm:text-base font-bold text-white block truncate leading-tight">
                  {matchup.away_team_name}
                </span>
                {awayPowerRating != null && (
                  <span className="text-[11px] font-mono text-slate-400">
                    Pwr:{' '}
                    <strong className={awayPowerRating > 0 ? 'text-emerald-400' : 'text-slate-300'}>
                      {awayPowerRating > 0 ? `+${awayPowerRating.toFixed(1)}` : awayPowerRating.toFixed(1)}
                    </strong>
                  </span>
                )}
              </div>
            </div>

            {/* Center Score / Proj Margin */}
            <div className="col-span-1 flex flex-col items-center justify-center text-center px-1">
              <h2 id="game-detail-modal-title" className="sr-only">
                {matchup.away_team_name} vs {matchup.home_team_name} Game Details
              </h2>
              {isCompleted ? (
                <>
                  <div className="bg-slate-950 px-3 py-1 rounded-md border border-slate-800 text-sm sm:text-base font-mono font-black text-white shadow-inner whitespace-nowrap">
                    <span
                      className={
                        matchup.away_score != null && matchup.home_score != null && matchup.away_score > matchup.home_score
                          ? 'text-emerald-400'
                          : 'text-slate-200'
                      }
                    >
                      {matchup.away_score ?? '—'}
                    </span>
                    <span className="text-slate-600 mx-1.5">-</span>
                    <span
                      className={
                        matchup.home_score != null && matchup.away_score != null && matchup.home_score > matchup.away_score
                          ? 'text-emerald-400'
                          : 'text-slate-200'
                      }
                    >
                      {matchup.home_score ?? '—'}
                    </span>
                  </div>
                  {hasProjection && projMargin != null && (
                    <span className="text-[10px] font-mono text-slate-400 mt-1 truncate">
                      Proj Margin: {projMargin > 0 ? `+${projMargin.toFixed(1)}` : projMargin.toFixed(1)}
                    </span>
                  )}
                </>
              ) : hasProjection && projMargin != null ? (
                <>
                  <span className="text-[10px] font-mono uppercase tracking-wider text-slate-500 font-semibold mb-0.5">
                    Proj Margin
                  </span>
                  <div className="bg-slate-950 px-2.5 py-1 rounded-md border border-slate-800 text-xs sm:text-sm font-mono font-black text-emerald-400 shadow-inner whitespace-nowrap">
                    {projMargin > 0 ? `+${projMargin.toFixed(1)}` : projMargin.toFixed(1)}
                  </div>
                </>
              ) : (
                <div className="flex flex-col items-center">
                  <span className="text-[10px] font-mono uppercase tracking-wider text-slate-500 font-semibold mb-0.5">
                    Matchup
                  </span>
                  <span className="text-[10px] font-mono text-slate-500 italic">No forecast recorded</span>
                </div>
              )}
            </div>

            {/* Home Team */}
            <div className="col-span-2 flex items-center justify-end gap-3 text-right">
              <div className="min-w-0">
                <span className="text-[10px] font-mono text-slate-400 uppercase tracking-wider block">
                  Home
                </span>
                <span className="text-sm sm:text-base font-bold text-white block truncate leading-tight">
                  {matchup.home_team_name}
                </span>
                {homePowerRating != null && (
                  <span className="text-[11px] font-mono text-slate-400">
                    Pwr:{' '}
                    <strong className={homePowerRating > 0 ? 'text-emerald-400' : 'text-slate-300'}>
                      {homePowerRating > 0 ? `+${homePowerRating.toFixed(1)}` : homePowerRating.toFixed(1)}
                    </strong>
                  </span>
                )}
              </div>
              <TeamLogo team={matchup.home_team} size="lg" />
            </div>
          </div>
        </div>

        {/* Tab Navigation */}
        <div className="border-b border-slate-800 bg-slate-950/40 px-4 sm:px-6 flex items-center gap-2 overflow-x-auto flex-shrink-0">
          <div role="tablist" aria-label="Game Detail Sections" className="flex gap-1 py-2">
            <button
              role="tab"
              id="tab-overview"
              aria-controls="panel-overview"
              aria-selected={activeTab === 'overview'}
              disabled={!isCompleted}
              aria-disabled={!isCompleted}
              onClick={() => isCompleted && setActiveTab('overview')}
              className={`px-3 py-1.5 rounded-lg text-xs font-medium transition-colors whitespace-nowrap focus:outline-none focus:ring-2 focus:ring-emerald-500/50 ${
                !isCompleted
                  ? 'opacity-40 cursor-not-allowed text-slate-500'
                  : activeTab === 'overview'
                  ? 'bg-slate-800 text-white font-semibold border border-slate-700/70 shadow-sm'
                  : 'text-slate-400 hover:text-slate-200 hover:bg-slate-800/40'
              }`}
            >
              Overview & Efficiency{' '}
              {!isCompleted && (
                <span className="text-[10px] ml-1 text-slate-500 font-mono">(Post-Game)</span>
              )}
            </button>
            <button
              role="tab"
              id="tab-comparison"
              aria-controls="panel-comparison"
              aria-selected={activeTab === 'comparison'}
              disabled={!isCompleted}
              aria-disabled={!isCompleted}
              onClick={() => isCompleted && setActiveTab('comparison')}
              className={`px-3 py-1.5 rounded-lg text-xs font-medium transition-colors whitespace-nowrap focus:outline-none focus:ring-2 focus:ring-emerald-500/50 ${
                !isCompleted
                  ? 'opacity-40 cursor-not-allowed text-slate-500'
                  : activeTab === 'comparison'
                  ? 'bg-slate-800 text-white font-semibold border border-slate-700/70 shadow-sm'
                  : 'text-slate-400 hover:text-slate-200 hover:bg-slate-800/40'
              }`}
            >
              Team Comparison{' '}
              {!isCompleted && (
                <span className="text-[10px] ml-1 text-slate-500 font-mono">(Post-Game)</span>
              )}
            </button>
            <button
              role="tab"
              id="tab-box-score"
              aria-controls="panel-box-score"
              aria-selected={activeTab === 'box_score'}
              disabled={!isCompleted}
              aria-disabled={!isCompleted}
              onClick={() => isCompleted && setActiveTab('box_score')}
              className={`px-3 py-1.5 rounded-lg text-xs font-medium transition-colors whitespace-nowrap focus:outline-none focus:ring-2 focus:ring-emerald-500/50 ${
                !isCompleted
                  ? 'opacity-40 cursor-not-allowed text-slate-500'
                  : activeTab === 'box_score'
                  ? 'bg-slate-800 text-white font-semibold border border-slate-700/70 shadow-sm'
                  : 'text-slate-400 hover:text-slate-200 hover:bg-slate-800/40'
              }`}
            >
              Player Box Score{' '}
              {!isCompleted && (
                <span className="text-[10px] ml-1 text-slate-500 font-mono">(Post-Game)</span>
              )}
            </button>
            <button
              role="tab"
              id="tab-attribution"
              aria-controls="panel-attribution"
              aria-selected={activeTab === 'attribution'}
              onClick={() => setActiveTab('attribution')}
              className={`px-3 py-1.5 rounded-lg text-xs font-medium transition-colors whitespace-nowrap focus:outline-none focus:ring-2 focus:ring-emerald-500/50 ${
                activeTab === 'attribution'
                  ? 'bg-slate-800 text-white font-semibold border border-slate-700/70 shadow-sm'
                  : 'text-slate-400 hover:text-slate-200 hover:bg-slate-800/40'
              }`}
            >
              Model Attribution
            </button>
          </div>
        </div>

        {/* Tab Content Panels */}
        <div className="overflow-y-auto p-4 sm:p-6 flex-1 space-y-6" aria-live="polite" aria-busy={loading}>
          {loading && (
            <div className="py-12 flex flex-col items-center justify-center text-slate-400 gap-3">
              <Loader2 className="w-6 h-6 animate-spin text-emerald-400" />
              <span className="text-xs font-mono">Loading game details...</span>
            </div>
          )}

          {!loading && (!detail || fetchError) && (
            <div className="py-12 px-4 rounded-xl bg-slate-950/40 border border-slate-800 text-center space-y-3">
              <AlertCircle className="w-8 h-8 text-amber-400 mx-auto" />
              <div className="space-y-1">
                <p className="text-sm font-semibold text-slate-200">
                  {isCompleted
                    ? 'Final. Box score is added on a later data refresh.'
                    : 'Game attribution is not yet available.'}
                </p>
                <p className="text-xs text-slate-400">
                  {isCompleted
                    ? 'Data from nflreadr will populate automatically once finalized and ingested.'
                    : 'Attribution data will populate once weekly forecasts are logged.'}
                </p>
              </div>
            </div>
          )}

          {!loading && detail && !fetchError && (
            <>
              {/* Post-game fallback when viewing Tabs 1-3 without box score */}
              {activeTab !== 'attribution' && (!hasBoxScore || !detail.box_score) && (
                <div className="py-12 px-4 rounded-xl bg-slate-950/40 border border-slate-800 text-center space-y-3">
                  <AlertCircle className="w-8 h-8 text-amber-400 mx-auto" />
                  <div className="space-y-1">
                    <p className="text-sm font-semibold text-slate-200">
                      {isCompleted
                        ? 'Final. Box score is added on a later data refresh.'
                        : 'Box score is added on a later data refresh.'}
                    </p>
                    <p className="text-xs text-slate-400">
                      Data from nflreadr will populate automatically once finalized and ingested.
                    </p>
                  </div>
                </div>
              )}
              {/* Tab 1: Overview & Efficiency */}
              {activeTab === 'overview' && hasBoxScore && (
                <div role="tabpanel" id="panel-overview" aria-labelledby="tab-overview" className="space-y-6">
                  {/* Category Leaders */}
                  {leaders && leaders.length > 0 && (
                    <div className="space-y-3">
                      <h3 className="text-xs font-mono font-bold uppercase tracking-wider text-slate-400">
                        Category Leaders
                      </h3>
                      <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-3">
                        {leaders.map((ldr, idx) => (
                          <div
                            key={`${ldr.teamAbbr}-${ldr.category}-${idx}`}
                            className="bg-slate-950/60 border border-slate-800 rounded-xl p-3 space-y-1.5"
                          >
                            <div className="flex items-center justify-between text-[11px] font-mono text-slate-400">
                              <span className="uppercase font-semibold text-emerald-400">
                                {ldr.category}
                              </span>
                              <span className="px-1.5 py-0.5 rounded bg-slate-800 border border-slate-700/60 text-slate-300">
                                {ldr.teamAbbr}
                              </span>
                            </div>
                            <div className="font-bold text-white text-sm truncate">{ldr.playerName}</div>
                            <div className="text-xs font-mono text-slate-300 truncate">{ldr.stat_line}</div>
                          </div>
                        ))}
                      </div>
                    </div>
                  )}

                  {/* Efficiency Factors Table */}
                  <div className="space-y-3">
                    <div className="flex items-center justify-between">
                      <h3 className="text-xs font-mono font-bold uppercase tracking-wider text-slate-400">
                        Efficiency Factors
                      </h3>
                      <span className="text-[11px] font-mono text-slate-500">nflreadr play-by-play metrics</span>
                    </div>

                    {efficiencyFactors && efficiencyFactors.length > 0 ? (
                      <div className="border border-slate-800 rounded-xl overflow-hidden bg-slate-950/40">
                        <table className="w-full text-left text-xs">
                          <thead className="bg-slate-950/80 text-[11px] font-mono text-slate-400 border-b border-slate-800">
                            <tr>
                              <th scope="col" className="py-2 px-3">
                                Factor
                              </th>
                              <th scope="col" className="py-2 px-3 text-right">
                                {matchup.away_team}
                              </th>
                              <th scope="col" className="py-2 px-3 text-center">
                                Comparison
                              </th>
                              <th scope="col" className="py-2 px-3 text-left">
                                {matchup.home_team}
                              </th>
                            </tr>
                          </thead>
                          <tbody>
                            {efficiencyFactors.map((item) => (
                              <FactorRow
                                key={item.key}
                                item={item}
                                awayAbbr={matchup.away_team}
                                homeAbbr={matchup.home_team}
                              />
                            ))}
                          </tbody>
                        </table>
                      </div>
                    ) : (
                      <div className="py-6 px-4 rounded-xl bg-slate-950/40 border border-slate-800 text-center text-xs text-slate-400">
                        Efficiency factors will appear once play-by-play calculations complete.
                      </div>
                    )}
                  </div>
                </div>
              )}

              {/* Tab 2: Team Comparison */}
              {activeTab === 'comparison' && hasBoxScore && (
                <div role="tabpanel" id="panel-comparison" aria-labelledby="tab-comparison" className="space-y-4">
                  <div className="flex items-center justify-between">
                    <h3 className="text-xs font-mono font-bold uppercase tracking-wider text-slate-400">
                      Team Statistics Comparison
                    </h3>
                    <span className="text-[11px] font-mono text-slate-500">
                      {matchup.away_team} vs {matchup.home_team}
                    </span>
                  </div>

                  {teamStats && teamStats.length > 0 ? (
                    <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
                      {teamStats.map((item) => (
                        <TeamComparisonRow
                          key={item.stat_key}
                          item={item}
                          awayAbbr={matchup.away_team}
                          homeAbbr={matchup.home_team}
                        />
                      ))}
                    </div>
                  ) : (
                    <div className="py-8 px-4 rounded-xl bg-slate-950/40 border border-slate-800 text-center text-xs text-slate-400">
                      Team statistics are added on a later data refresh.
                    </div>
                  )}
                </div>
              )}

              {/* Tab 3: Player Box Score */}
              {activeTab === 'box_score' && hasBoxScore && (
                <div role="tabpanel" id="panel-box-score" aria-labelledby="tab-box-score" className="space-y-6">
                  {/* Category & Team Filters */}
                  <div className="flex flex-wrap items-center justify-between gap-3">
                    {/* Category tabs */}
                    <div className="flex flex-wrap items-center gap-1 bg-slate-950/60 p-1 rounded-xl border border-slate-800">
                      {(['passing', 'rushing', 'receiving', 'defense', 'kicking'] as const).map((cat) => (
                        <button
                          key={cat}
                          type="button"
                          onClick={() => {
                            setBoxCategory(cat);
                            setSortKey(null);
                          }}
                          className={`px-2.5 py-1 rounded-lg text-xs font-medium capitalize transition-colors ${
                            boxCategory === cat
                              ? 'bg-slate-800 text-emerald-400 font-semibold border border-slate-700'
                              : 'text-slate-400 hover:text-slate-200'
                          }`}
                        >
                          {cat}
                        </button>
                      ))}
                    </div>

                    {/* Team Filter */}
                    <div className="flex items-center gap-1 bg-slate-950/60 p-1 rounded-xl border border-slate-800 text-xs font-mono">
                      <button
                        type="button"
                        onClick={() => setBoxTeamFilter('both')}
                        className={`px-2 py-1 rounded-lg transition-colors ${
                          boxTeamFilter === 'both' ? 'bg-slate-800 text-white font-bold' : 'text-slate-400'
                        }`}
                      >
                        All
                      </button>
                      <button
                        type="button"
                        onClick={() => setBoxTeamFilter('away')}
                        className={`px-2 py-1 rounded-lg transition-colors ${
                          boxTeamFilter === 'away' ? 'bg-slate-800 text-emerald-400 font-bold' : 'text-slate-400'
                        }`}
                      >
                        {matchup.away_team}
                      </button>
                      <button
                        type="button"
                        onClick={() => setBoxTeamFilter('home')}
                        className={`px-2 py-1 rounded-lg transition-colors ${
                          boxTeamFilter === 'home' ? 'bg-slate-800 text-emerald-400 font-bold' : 'text-slate-400'
                        }`}
                      >
                        {matchup.home_team}
                      </button>
                    </div>
                  </div>

                  {/* Players Table */}
                  <div className="border border-slate-800 rounded-xl overflow-x-auto bg-slate-950/40">
                    <table className="w-full text-left text-xs whitespace-nowrap">
                      <thead className="bg-slate-950/80 text-[11px] font-mono text-slate-400 border-b border-slate-800">
                        <tr>
                          <th scope="col" className="py-2 px-3">
                            Player
                          </th>
                          <th scope="col" className="py-2 px-2 text-center">
                            Pos
                          </th>
                          <th scope="col" className="py-2 px-2 text-center">
                            Tm
                          </th>
                          <th scope="col" className="py-2 px-2 text-right">
                            Snap%
                          </th>

                          {boxCategory === 'passing' && (
                            <>
                              <th scope="col" className="py-2 px-2 text-right">
                                C/ATT
                              </th>
                              <th
                                scope="col"
                                className="py-2 px-2 text-right cursor-pointer hover:text-white"
                                onClick={() => handleSort('passing_yards')}

                                tabIndex={0}

                                onKeyDown={activateOnKey}

                                aria-sort={ariaSort(sortKey === 'passing_yards', sortDir === 'asc')}
                              >
                                YDS{renderSortIndicator('passing_yards')}
                              </th>
                              <th
                                scope="col"
                                className="py-2 px-2 text-right cursor-pointer hover:text-white"
                                onClick={() => handleSort('passing_tds')}

                                tabIndex={0}

                                onKeyDown={activateOnKey}

                                aria-sort={ariaSort(sortKey === 'passing_tds', sortDir === 'asc')}
                              >
                                TD{renderSortIndicator('passing_tds')}
                              </th>
                              <th
                                scope="col"
                                className="py-2 px-2 text-right cursor-pointer hover:text-white"
                                onClick={() => handleSort('passing_interceptions')}

                                tabIndex={0}

                                onKeyDown={activateOnKey}

                                aria-sort={ariaSort(sortKey === 'passing_interceptions', sortDir === 'asc')}
                              >
                                INT{renderSortIndicator('passing_interceptions')}
                              </th>
                              <th scope="col" className="py-2 px-2 text-right">
                                SCK
                              </th>
                              <th
                                scope="col"
                                className="py-2 px-2 text-right cursor-pointer hover:text-white"
                                onClick={() => handleSort('passing_epa')}

                                tabIndex={0}

                                onKeyDown={activateOnKey}

                                aria-sort={ariaSort(sortKey === 'passing_epa', sortDir === 'asc')}
                              >
                                EPA (nflreadr){renderSortIndicator('passing_epa')}
                              </th>
                              <th scope="col" className="py-2 px-2 text-right">
                                CPOE
                              </th>
                            </>
                          )}

                          {boxCategory === 'rushing' && (
                            <>
                              <th
                                scope="col"
                                className="py-2 px-2 text-right cursor-pointer hover:text-white"
                                onClick={() => handleSort('carries')}

                                tabIndex={0}

                                onKeyDown={activateOnKey}

                                aria-sort={ariaSort(sortKey === 'carries', sortDir === 'asc')}
                              >
                                CAR{renderSortIndicator('carries')}
                              </th>
                              <th
                                scope="col"
                                className="py-2 px-2 text-right cursor-pointer hover:text-white"
                                onClick={() => handleSort('rushing_yards')}

                                tabIndex={0}

                                onKeyDown={activateOnKey}

                                aria-sort={ariaSort(sortKey === 'rushing_yards', sortDir === 'asc')}
                              >
                                YDS{renderSortIndicator('rushing_yards')}
                              </th>
                              <th
                                scope="col"
                                className="py-2 px-2 text-right cursor-pointer hover:text-white"
                                onClick={() => handleSort('rushing_tds')}

                                tabIndex={0}

                                onKeyDown={activateOnKey}

                                aria-sort={ariaSort(sortKey === 'rushing_tds', sortDir === 'asc')}
                              >
                                TD{renderSortIndicator('rushing_tds')}
                              </th>
                              <th scope="col" className="py-2 px-2 text-right">
                                1stD
                              </th>
                              <th scope="col" className="py-2 px-2 text-right">
                                FUM
                              </th>
                              <th
                                scope="col"
                                className="py-2 px-2 text-right cursor-pointer hover:text-white"
                                onClick={() => handleSort('rushing_epa')}

                                tabIndex={0}

                                onKeyDown={activateOnKey}

                                aria-sort={ariaSort(sortKey === 'rushing_epa', sortDir === 'asc')}
                              >
                                EPA (nflreadr){renderSortIndicator('rushing_epa')}
                              </th>
                            </>
                          )}

                          {boxCategory === 'receiving' && (
                            <>
                              <th
                                scope="col"
                                className="py-2 px-2 text-right cursor-pointer hover:text-white"
                                onClick={() => handleSort('receptions')}

                                tabIndex={0}

                                onKeyDown={activateOnKey}

                                aria-sort={ariaSort(sortKey === 'receptions', sortDir === 'asc')}
                              >
                                REC{renderSortIndicator('receptions')}
                              </th>
                              <th
                                scope="col"
                                className="py-2 px-2 text-right cursor-pointer hover:text-white"
                                onClick={() => handleSort('targets')}

                                tabIndex={0}

                                onKeyDown={activateOnKey}

                                aria-sort={ariaSort(sortKey === 'targets', sortDir === 'asc')}
                              >
                                TGTS{renderSortIndicator('targets')}
                              </th>
                              <th
                                scope="col"
                                className="py-2 px-2 text-right cursor-pointer hover:text-white"
                                onClick={() => handleSort('receiving_yards')}

                                tabIndex={0}

                                onKeyDown={activateOnKey}

                                aria-sort={ariaSort(sortKey === 'receiving_yards', sortDir === 'asc')}
                              >
                                YDS{renderSortIndicator('receiving_yards')}
                              </th>
                              <th
                                scope="col"
                                className="py-2 px-2 text-right cursor-pointer hover:text-white"
                                onClick={() => handleSort('receiving_tds')}

                                tabIndex={0}

                                onKeyDown={activateOnKey}

                                aria-sort={ariaSort(sortKey === 'receiving_tds', sortDir === 'asc')}
                              >
                                TD{renderSortIndicator('receiving_tds')}
                              </th>
                              <th scope="col" className="py-2 px-2 text-right">
                                1stD
                              </th>
                              <th scope="col" className="py-2 px-2 text-right">
                                FUM
                              </th>
                              <th
                                scope="col"
                                className="py-2 px-2 text-right cursor-pointer hover:text-white"
                                onClick={() => handleSort('receiving_epa')}

                                tabIndex={0}

                                onKeyDown={activateOnKey}

                                aria-sort={ariaSort(sortKey === 'receiving_epa', sortDir === 'asc')}
                              >
                                EPA (nflreadr){renderSortIndicator('receiving_epa')}
                              </th>
                            </>
                          )}

                          {boxCategory === 'defense' && (
                            <>
                              <th
                                scope="col"
                                className="py-2 px-2 text-right cursor-pointer hover:text-white"
                                onClick={() => handleSort('def_tackles_solo')}

                                tabIndex={0}

                                onKeyDown={activateOnKey}

                                aria-sort={ariaSort(sortKey === 'def_tackles_solo', sortDir === 'asc')}
                              >
                                SOLO{renderSortIndicator('def_tackles_solo')}
                              </th>
                              <th scope="col" className="py-2 px-2 text-right">
                                AST
                              </th>
                              <th
                                scope="col"
                                className="py-2 px-2 text-right cursor-pointer hover:text-white"
                                onClick={() => handleSort('def_sacks')}

                                tabIndex={0}

                                onKeyDown={activateOnKey}

                                aria-sort={ariaSort(sortKey === 'def_sacks', sortDir === 'asc')}
                              >
                                SCK{renderSortIndicator('def_sacks')}
                              </th>
                              <th scope="col" className="py-2 px-2 text-right">
                                TFL
                              </th>
                              <th scope="col" className="py-2 px-2 text-right">
                                QBH
                              </th>
                              <th
                                scope="col"
                                className="py-2 px-2 text-right cursor-pointer hover:text-white"
                                onClick={() => handleSort('def_interceptions')}

                                tabIndex={0}

                                onKeyDown={activateOnKey}

                                aria-sort={ariaSort(sortKey === 'def_interceptions', sortDir === 'asc')}
                              >
                                INT{renderSortIndicator('def_interceptions')}
                              </th>
                              <th scope="col" className="py-2 px-2 text-right">
                                PD
                              </th>
                              <th scope="col" className="py-2 px-2 text-right">
                                FF
                              </th>
                            </>
                          )}

                          {boxCategory === 'kicking' && (
                            <>
                              <th scope="col" className="py-2 px-2 text-right">
                                FG (M/ATT)
                              </th>
                              <th scope="col" className="py-2 px-2 text-right">
                                FG%
                              </th>
                              <th scope="col" className="py-2 px-2 text-right">
                                LONG
                              </th>
                              <th scope="col" className="py-2 px-2 text-right">
                                PAT (M/ATT)
                              </th>
                            </>
                          )}
                        </tr>
                      </thead>
                      <tbody className="divide-y divide-slate-800/80 font-mono">
                        {displayedPlayers.length > 0 ? (
                          displayedPlayers.map((p) => (
                            <tr key={p.playerId} className="hover:bg-slate-800/30">
                              <td className="py-2 px-3 font-sans font-medium text-white">{p.playerName}</td>
                              <td className="py-2 px-2 text-center text-slate-400">{p.position ?? '—'}</td>
                              <td className="py-2 px-2 text-center text-slate-400">{p.teamAbbr}</td>
                              <td className="py-2 px-2 text-right text-slate-400">
                                {p.snap_pct != null ? `${p.snap_pct}%` : '—'}
                              </td>

                              {boxCategory === 'passing' && (
                                <>
                                  <td className="py-2 px-2 text-right text-slate-300">
                                    {p.completions ?? 0}/{p.attempts ?? 0}
                                  </td>
                                  <td className="py-2 px-2 text-right font-bold text-white">
                                    {p.passing_yards ?? 0}
                                  </td>
                                  <td className="py-2 px-2 text-right text-emerald-400">{p.passing_tds ?? 0}</td>
                                  <td className="py-2 px-2 text-right text-amber-400">
                                    {p.passing_interceptions ?? 0}
                                  </td>
                                  <td className="py-2 px-2 text-right text-slate-400">
                                    {p.sacks_suffered ?? 0}
                                  </td>
                                  <td className="py-2 px-2 text-right text-slate-300">
                                    {isFiniteNum(p.passing_epa)
                                      ? `${p.passing_epa > 0 ? '+' : ''}${p.passing_epa.toFixed(2)}`
                                      : '—'}
                                  </td>
                                  <td className="py-2 px-2 text-right text-slate-300">
                                    {isFiniteNum(p.passing_cpoe) ? `${p.passing_cpoe.toFixed(1)}%` : '—'}
                                  </td>
                                </>
                              )}

                              {boxCategory === 'rushing' && (
                                <>
                                  <td className="py-2 px-2 text-right text-slate-300">{p.carries ?? 0}</td>
                                  <td className="py-2 px-2 text-right font-bold text-white">
                                    {p.rushing_yards ?? 0}
                                  </td>
                                  <td className="py-2 px-2 text-right text-emerald-400">{p.rushing_tds ?? 0}</td>
                                  <td className="py-2 px-2 text-right text-slate-400">
                                    {p.rushing_first_downs ?? 0}
                                  </td>
                                  <td className="py-2 px-2 text-right text-amber-400">
                                    {p.rushing_fumbles ?? 0}
                                  </td>
                                  <td className="py-2 px-2 text-right text-slate-300">
                                    {isFiniteNum(p.rushing_epa)
                                      ? `${p.rushing_epa > 0 ? '+' : ''}${p.rushing_epa.toFixed(2)}`
                                      : '—'}
                                  </td>
                                </>
                              )}

                              {boxCategory === 'receiving' && (
                                <>
                                  <td className="py-2 px-2 text-right font-bold text-white">
                                    {p.receptions ?? 0}
                                  </td>
                                  <td className="py-2 px-2 text-right text-slate-400">{p.targets ?? 0}</td>
                                  <td className="py-2 px-2 text-right font-bold text-white">
                                    {p.receiving_yards ?? 0}
                                  </td>
                                  <td className="py-2 px-2 text-right text-emerald-400">
                                    {p.receiving_tds ?? 0}
                                  </td>
                                  <td className="py-2 px-2 text-right text-slate-400">
                                    {p.receiving_first_downs ?? 0}
                                  </td>
                                  <td className="py-2 px-2 text-right text-amber-400">
                                    {p.receiving_fumbles ?? 0}
                                  </td>
                                  <td className="py-2 px-2 text-right text-slate-300">
                                    {isFiniteNum(p.receiving_epa)
                                      ? `${p.receiving_epa > 0 ? '+' : ''}${p.receiving_epa.toFixed(2)}`
                                      : '—'}
                                  </td>
                                </>
                              )}

                              {boxCategory === 'defense' && (
                                <>
                                  <td className="py-2 px-2 text-right font-bold text-white">
                                    {p.def_tackles_solo ?? 0}
                                  </td>
                                  <td className="py-2 px-2 text-right text-slate-400">
                                    {p.def_tackle_assists ?? 0}
                                  </td>
                                  <td className="py-2 px-2 text-right text-emerald-400">{p.def_sacks ?? 0}</td>
                                  <td className="py-2 px-2 text-right text-slate-300">
                                    {p.def_tackles_for_loss ?? 0}
                                  </td>
                                  <td className="py-2 px-2 text-right text-slate-400">{p.def_qb_hits ?? 0}</td>
                                  <td className="py-2 px-2 text-right text-amber-400">
                                    {p.def_interceptions ?? 0}
                                  </td>
                                  <td className="py-2 px-2 text-right text-slate-400">
                                    {p.def_pass_defended ?? 0}
                                  </td>
                                  <td className="py-2 px-2 text-right text-slate-400">
                                    {p.def_fumbles_forced ?? 0}
                                  </td>
                                </>
                              )}

                              {boxCategory === 'kicking' && (
                                <>
                                  <td className="py-2 px-2 text-right font-bold text-white">
                                    {p.fg_made ?? 0}/{p.fg_att ?? 0}
                                  </td>
                                  <td className="py-2 px-2 text-right text-slate-300">
                                    {p.fg_att && p.fg_att > 0
                                      ? `${(((p.fg_made ?? 0) / p.fg_att) * 100).toFixed(1)}%`
                                      : '—'}
                                  </td>
                                  <td className="py-2 px-2 text-right text-slate-400">
                                    {p.fg_long != null ? p.fg_long : '—'}
                                  </td>
                                  <td className="py-2 px-2 text-right text-slate-300">
                                    {p.pat_made ?? 0}/{p.pat_att ?? 0}
                                  </td>
                                </>
                              )}
                            </tr>
                          ))
                        ) : (
                          <tr>
                            <td colSpan={10} className="py-8 text-center text-slate-500 font-sans text-xs">
                              No {boxCategory} statistics recorded for this selection.
                            </td>
                          </tr>
                        )}
                      </tbody>
                    </table>
                  </div>

                  {/* Footnote on EPA estimate */}
                  <p className="text-[11px] text-slate-500 italic">
                    Note: EPA is a model estimate published by nflreadr.
                  </p>

                  {/* Injury Designations Table */}
                  <div className="space-y-3 pt-3 border-t border-slate-800">
                    <div className="flex items-center justify-between">
                      <h3 className="text-xs font-mono font-bold uppercase tracking-wider text-slate-400">
                        Injury report designations entering the game
                      </h3>
                      <span className="text-[11px] font-mono text-slate-500">Official pre-kickoff status</span>
                    </div>

                    {injuryDesignations.length > 0 ? (
                      <div className="border border-slate-800 rounded-xl overflow-hidden bg-slate-950/40">
                        <table className="w-full text-left text-xs whitespace-nowrap">
                          <thead className="bg-slate-950/80 text-[11px] font-mono text-slate-400 border-b border-slate-800">
                            <tr>
                              <th scope="col" className="py-2 px-3">
                                Player
                              </th>
                              <th scope="col" className="py-2 px-2 text-center">
                                Pos
                              </th>
                              <th scope="col" className="py-2 px-3 text-center">
                                Designation
                              </th>
                              <th scope="col" className="py-2 px-3">
                                Injury
                              </th>
                              <th scope="col" className="py-2 px-3 text-right">
                                Game Status
                              </th>
                            </tr>
                          </thead>
                          <tbody className="divide-y divide-slate-800/80 font-mono">
                            {injuryDesignations.map((inj, idx) => (
                              <tr key={`${inj.playerName}-${idx}`} className="hover:bg-slate-800/30">
                                <td className="py-2 px-3 font-sans font-medium text-white">{inj.playerName}</td>
                                <td className="py-2 px-2 text-center text-slate-400">{inj.position ?? '—'}</td>
                                <td className="py-2 px-3 text-center">
                                  <span
                                    className={`px-2 py-0.5 rounded text-[10px] font-semibold uppercase ${
                                      inj.designation === 'Out' || inj.designation === 'IR'
                                        ? 'bg-rose-500/10 text-rose-400 border border-rose-500/20'
                                        : inj.designation === 'Doubtful'
                                        ? 'bg-amber-500/10 text-amber-400 border border-amber-500/20'
                                        : 'bg-slate-800 text-slate-300 border border-slate-700'
                                    }`}
                                  >
                                    {inj.designation}
                                  </span>
                                </td>
                                <td className="py-2 px-3 text-slate-300 font-sans">{inj.body_part ?? '—'}</td>
                                <td className="py-2 px-3 text-right">
                                  {inj.played ? (
                                    <span className="inline-flex items-center gap-1 text-emerald-400 text-[11px] font-semibold">
                                      <CheckCircle2 className="w-3.5 h-3.5" /> Played
                                    </span>
                                  ) : (
                                    <span className="inline-flex items-center gap-1 text-slate-500 text-[11px]">
                                      Did Not Play
                                    </span>
                                  )}
                                </td>
                              </tr>
                            ))}
                          </tbody>
                        </table>
                      </div>
                    ) : (
                      <div className="py-6 px-4 rounded-xl bg-slate-950/40 border border-slate-800 text-center text-xs text-slate-500">
                        No injury designations recorded for this matchup.
                      </div>
                    )}
                  </div>
                </div>
              )}

              {/* Tab 4: Model Attribution */}
              {activeTab === 'attribution' && (
                <div
                  role="tabpanel"
                  id="panel-attribution"
                  aria-labelledby="tab-attribution"
                  className="space-y-6"
                >
                  {detail?.explainability ? (
                    <>
                      <PointsWaterfallCard
                        waterfall={detail.explainability.waterfall}
                        homeAbbr={matchup.home_team}
                        awayAbbr={matchup.away_team}
                        projectionBasis={detail.explainability.projection_basis}
                      />
                      {detail.explainability.secondary_model && (
                        <SecondaryShapCard
                          secondaryModel={detail.explainability.secondary_model}
                          homeAbbr={matchup.home_team}
                          awayAbbr={matchup.away_team}
                        />
                      )}
                      {detail.explainability.entering_baselines &&
                        detail.explainability.entering_baselines.length > 0 && (
                          <EnteringBaselinesCard
                            baselines={detail.explainability.entering_baselines}
                            divergenceNote={detail.explainability.divergence_note}
                            homeAbbr={matchup.home_team}
                            awayAbbr={matchup.away_team}
                            isCompleted={isCompleted}
                          />
                        )}
                    </>
                  ) : (
                    <div className="py-12 px-4 rounded-xl bg-slate-950/40 border border-slate-800 text-center space-y-2">
                      <Info className="w-8 h-8 text-slate-400 mx-auto" />
                      <p className="text-sm font-semibold text-slate-200">
                        No model attribution recorded
                      </p>
                      <p className="text-xs text-slate-400">
                        Attribution decomposition and secondary explanations will be generated once forecast ratings are logged.
                      </p>
                    </div>
                  )}
                </div>
              )}
            </>
          )}
        </div>
      </div>
    </div>
  );
};
