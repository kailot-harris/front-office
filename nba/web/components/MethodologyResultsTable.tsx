'use client';

import React, { useId, useMemo, useState } from 'react';
import { ArrowDown, ArrowUp } from 'lucide-react';
import type {
  MomentumVerdict,
  SingleFeatureResult,
  StudyMeasure,
  StudySeries,
  StudyTarget,
} from '@/lib/momentumMethodologyTypes';
import { IntervalBar, VerdictBadge, fmtInterval, fmtSigned, intervalDomain } from '@/components/MethodologyCharts';

type SortKey = 'series' | 'measure' | 'target' | 'r2_gain' | 'ci_lo' | 'fdr_q_value' | 'n' | 'verdict';

const ALL = '__all__';
const VERDICTS: MomentumVerdict[] = ['kept', 'inconclusive', 'discarded'];

interface Props {
  rows: SingleFeatureResult[];
  targets: StudyTarget[];
  measures: StudyMeasure[];
  series: StudySeries[];
}

const selectClass =
  'min-h-8 rounded-md border border-slate-700 bg-surface-raised px-2 py-1 text-xs text-slate-100 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-accent';

interface ThProps {
  k: SortKey;
  active: SortKey;
  desc: boolean;
  onSort: (k: SortKey) => void;
  children: React.ReactNode;
  className?: string;
}

const Th: React.FC<ThProps> = ({ k, active, desc, onSort, children, className = '' }) => (
  <th scope="col" aria-sort={active === k ? (desc ? 'descending' : 'ascending') : 'none'} className={`px-2 py-2 font-semibold ${className}`}>
    <button
      type="button"
      onClick={() => onSort(k)}
      className="inline-flex items-center gap-1 rounded text-left hover:text-slate-100 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-accent"
    >
      {children}
      {active === k && (desc ? <ArrowDown className="h-3 w-3" aria-hidden="true" /> : <ArrowUp className="h-3 w-3" aria-hidden="true" />)}
    </button>
  </th>
);

/**
 * Every series x measure x target row of the study, filterable and sortable.
 * Defaults to the study's primary target.
 */
export const MethodologyResultsTable: React.FC<Props> = ({ rows, targets, measures, series }) => {
  const id = useId();
  const primary = targets.find((t) => t.primary)?.id ?? ALL;
  const [target, setTarget] = useState<string>(primary);
  const [verdict, setVerdict] = useState<string>(ALL);
  const [seriesId, setSeriesId] = useState<string>(ALL);
  const [measureId, setMeasureId] = useState<string>(ALL);
  const [sortKey, setSortKey] = useState<SortKey>('r2_gain');
  const [desc, setDesc] = useState(true);

  const seriesName = useMemo(() => Object.fromEntries(series.map((s) => [s.id, s.name])), [series]);
  const measureName = useMemo(() => Object.fromEntries(measures.map((m) => [m.id, m.name])), [measures]);

  const visible = useMemo(() => {
    const out = rows.filter(
      (r) =>
        (target === ALL || r.target === target) &&
        (verdict === ALL || r.verdict === verdict) &&
        (seriesId === ALL || r.series === seriesId) &&
        (measureId === ALL || r.measure === measureId),
    );
    const val = (r: SingleFeatureResult): number | string => {
      switch (sortKey) {
        case 'series':
          return seriesName[r.series] ?? r.series;
        case 'measure':
          return measureName[r.measure] ?? r.measure;
        case 'target':
          return r.target;
        case 'ci_lo':
          return r.ci_95[0];
        case 'verdict':
          return VERDICTS.indexOf(r.verdict);
        default:
          return r[sortKey];
      }
    };
    return [...out].sort((a, b) => {
      const va = val(a);
      const vb = val(b);
      const c = typeof va === 'number' && typeof vb === 'number' ? va - vb : String(va).localeCompare(String(vb));
      return desc ? -c : c;
    });
  }, [rows, target, verdict, seriesId, measureId, sortKey, desc, seriesName, measureName]);

  const domain = useMemo(() => intervalDomain(visible.map((r) => ({ lo: r.ci_95[0], hi: r.ci_95[1] }))), [visible]);
  const counts = useMemo(() => {
    const c: Record<MomentumVerdict, number> = { kept: 0, inconclusive: 0, discarded: 0 };
    for (const r of visible) c[r.verdict] += 1;
    return c;
  }, [visible]);

  const sortBy = (k: SortKey) => {
    if (k === sortKey) setDesc((d) => !d);
    else {
      setSortKey(k);
      setDesc(k === 'r2_gain' || k === 'ci_lo' || k === 'n');
    }
  };

  const showTarget = target === ALL;
  const metricNote = Array.from(new Set(visible.map((r) => r.gain_metric)));

  return (
    <div className="space-y-3">
      <div className="flex flex-wrap items-end gap-3">
        <div>
          <label htmlFor={`${id}-target`} className="mb-1 block text-xs font-semibold text-slate-300">
            What it tries to predict
          </label>
          <select id={`${id}-target`} value={target} onChange={(e) => setTarget(e.target.value)} className={selectClass}>
            {targets.map((t) => (
              <option key={t.id} value={t.id}>
                {t.id}
                {t.primary ? ' (main target)' : ''}
              </option>
            ))}
            <option value={ALL}>All targets</option>
          </select>
        </div>
        <div>
          <label htmlFor={`${id}-verdict`} className="mb-1 block text-xs font-semibold text-slate-300">
            Verdict
          </label>
          <select id={`${id}-verdict`} value={verdict} onChange={(e) => setVerdict(e.target.value)} className={selectClass}>
            <option value={ALL}>All verdicts</option>
            {VERDICTS.map((v) => (
              <option key={v} value={v}>
                {v}
              </option>
            ))}
          </select>
        </div>
        <div>
          <label htmlFor={`${id}-series`} className="mb-1 block text-xs font-semibold text-slate-300">
            Stat
          </label>
          <select id={`${id}-series`} value={seriesId} onChange={(e) => setSeriesId(e.target.value)} className={selectClass}>
            <option value={ALL}>All stats</option>
            {series.map((s) => (
              <option key={s.id} value={s.id}>
                {s.name}
              </option>
            ))}
          </select>
        </div>
        <div>
          <label htmlFor={`${id}-measure`} className="mb-1 block text-xs font-semibold text-slate-300">
            Measure
          </label>
          <select id={`${id}-measure`} value={measureId} onChange={(e) => setMeasureId(e.target.value)} className={selectClass}>
            <option value={ALL}>All measures</option>
            {measures.map((m) => (
              <option key={m.id} value={m.id}>
                {m.name}
              </option>
            ))}
          </select>
        </div>
      </div>

      <p className="text-xs text-slate-400" aria-live="polite" data-testid="tried-count">
        Showing {visible.length} of {rows.length} rows: {counts.kept} kept, {counts.inconclusive} inconclusive,{' '}
        {counts.discarded} discarded. Score: {metricNote.join('; ') || 'none'}.
      </p>

      <div className="overflow-x-auto rounded-lg border border-slate-800" tabIndex={0} role="region" aria-label="Every momentum method tried">
        <table className="w-full min-w-[56rem] text-left text-xs">
          <caption className="sr-only">
            Every stat and measure tried, with its gain over team strength on unseen seasons, the 95% interval, the
            false discovery rate q-value, the verdict and the reason.
          </caption>
          <thead className="bg-surface-raised/60 text-slate-300">
            <tr>
              <Th active={sortKey} desc={desc} onSort={sortBy} k="series">Stat</Th>
              <Th active={sortKey} desc={desc} onSort={sortBy} k="measure">Measure</Th>
              {showTarget && <Th active={sortKey} desc={desc} onSort={sortBy} k="target">Target</Th>}
              <Th active={sortKey} desc={desc} onSort={sortBy} k="r2_gain" className="text-right">Gain</Th>
              <Th active={sortKey} desc={desc} onSort={sortBy} k="ci_lo">95% interval</Th>
              <Th active={sortKey} desc={desc} onSort={sortBy} k="fdr_q_value" className="text-right">q</Th>
              <Th active={sortKey} desc={desc} onSort={sortBy} k="n" className="text-right">Rows</Th>
              <Th active={sortKey} desc={desc} onSort={sortBy} k="verdict">Verdict</Th>
              <th scope="col" className="px-2 py-2 font-semibold">
                Reason
              </th>
            </tr>
          </thead>
          <tbody>
            {visible.map((r) => (
              <tr key={`${r.feature}|${r.target}`} data-testid="tried-row" className="border-t border-slate-800 align-top">
                <td className="px-2 py-1.5 text-slate-200">{seriesName[r.series] ?? r.series}</td>
                <td className="px-2 py-1.5 text-slate-200">{measureName[r.measure] ?? r.measure}</td>
                {showTarget && <td className="px-2 py-1.5 font-mono text-slate-300">{r.target}</td>}
                <td className="px-2 py-1.5 text-right font-mono tabular-nums text-slate-100">{fmtSigned(r.r2_gain)}</td>
                <td className="px-2 py-1.5">
                  <div className="flex items-center gap-2">
                    <IntervalBar lo={r.ci_95[0]} hi={r.ci_95[1]} point={r.r2_gain} domain={domain} />
                    <span className="whitespace-nowrap font-mono tabular-nums text-slate-300">{fmtInterval(r.ci_95[0], r.ci_95[1])}</span>
                  </div>
                </td>
                <td className="px-2 py-1.5 text-right font-mono tabular-nums text-slate-300">{r.fdr_q_value.toFixed(4)}</td>
                <td className="px-2 py-1.5 text-right font-mono tabular-nums text-slate-300">
                  {r.n}
                  <span className="block text-[10px] text-slate-400">{r.missing_count} missing</span>
                </td>
                <td className="px-2 py-1.5">
                  <VerdictBadge verdict={r.verdict} />
                </td>
                <td className="px-2 py-1.5 text-slate-300">{r.reason}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </div>
  );
};
