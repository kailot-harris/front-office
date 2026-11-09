'use client';

import React from 'react';
import { Activity, ExternalLink } from 'lucide-react';
import { MediaSentimentHeadline, MediaSentimentPulse } from '@/lib/offseasonTypes';

interface Props {
  /** `undefined` for any edition published before #156 added the pulse. */
  pulse?: MediaSentimentPulse;
  /**
   * Reserved right-hand header slot for a week-over-week trend element. Left
   * empty on purpose: the dataset holds a single edition, so a sparkline would
   * plot one point. Wiring it later is a prop, not a rewrite of this card.
   */
  trendSlot?: React.ReactNode;
}

const CARD_CLASS =
  'bg-surface-raised border border-slate-800/80 rounded-2xl p-5 sm:p-6 shadow-xl space-y-4';

/** Signed, 4-decimal score, matching render_memo.R's `%+.4f`. */
function formatSigned(value: number): string {
  return `${value >= 0 ? '+' : '-'}${Math.abs(value).toFixed(4)}`;
}

/**
 * Sign-dependent label for the minimum-scoring story, mirroring
 * `tools/offseason/render_memo.R:333`. The `>= 0` boundary is inclusive and
 * deliberate: when every scored article is positive, the minimum is not a
 * negative story, and calling a +0.0043 retrospective the week's "most
 * negative" story reads as a damning headline it is not.
 *
 * ACCEPTED CONSTRAINT (#169): this rule now lives in both R and TypeScript.
 * Any edit to `render_block_media_sentiment()`'s label logic must be mirrored
 * here, and vice versa.
 */
export function negativeExtremeLabel(score: number): 'Least positive' | 'Most negative' {
  return score >= 0 ? 'Least positive' : 'Most negative';
}

function CardShell({
  children,
  trendSlot,
  subtitle,
}: {
  children: React.ReactNode;
  trendSlot?: React.ReactNode;
  subtitle: string;
}) {
  return (
    <div className={CARD_CLASS} data-testid="media-sentiment-pulse-card">
      <div className="flex items-center justify-between gap-3 pb-3 border-b border-slate-800/80">
        <div className="flex items-center gap-2.5">
          <div className="p-2 rounded-xl bg-fuchsia-500/10 border border-fuchsia-500/20 text-fuchsia-400">
            <Activity className="w-4 h-4" />
          </div>
          <div>
            <h3 className="text-base font-bold text-white">Media Sentiment Pulse</h3>
            <p className="text-xs text-slate-400">{subtitle}</p>
          </div>
        </div>
        {/* Reserved trend slot — see `trendSlot` prop. */}
        <div className="flex-shrink-0" data-testid="media-sentiment-trend-slot">
          {trendSlot}
        </div>
      </div>
      {children}
    </div>
  );
}

function ExtremeRow({
  label,
  item,
}: {
  label: string;
  item: MediaSentimentHeadline;
}) {
  const hasUrl = typeof item.url === 'string' && item.url.length > 0;
  return (
    <div className="p-3.5 rounded-xl bg-surface border border-slate-800/70 space-y-1.5">
      <div className="flex items-center justify-between gap-3">
        <span className="text-[10px] font-bold uppercase tracking-wider text-slate-400">
          {label}
        </span>
        <span className="px-2 py-0.5 rounded text-[11px] font-mono font-bold bg-slate-800 text-slate-200 border border-slate-700">
          {formatSigned(item.score)}
        </span>
      </div>
      {hasUrl ? (
        <a
          href={item.url as string}
          target="_blank"
          rel="noreferrer"
          className="text-sm font-semibold text-slate-100 hover:text-white inline-flex items-start gap-1.5 group"
        >
          <span>{item.headline}</span>
          <ExternalLink className="w-3 h-3 mt-1 flex-shrink-0 text-violet-400 group-hover:text-violet-300" />
        </a>
      ) : (
        <span className="text-sm font-semibold text-slate-100 block">{item.headline}</span>
      )}
      {item.sourceId && (
        <span className="font-mono text-[11px] text-slate-500 block">{item.sourceId}</span>
      )}
    </div>
  );
}

function WordChips({
  title,
  words,
  tone,
}: {
  title: string;
  words: { word: string; n: number }[];
  tone: 'positive' | 'negative';
}) {
  const chip =
    tone === 'positive'
      ? 'bg-emerald-500/10 text-emerald-300 border-emerald-500/30'
      : 'bg-rose-500/10 text-rose-300 border-rose-500/30';
  return (
    <div className="space-y-2">
      <span className="text-[10px] font-bold uppercase tracking-wider text-slate-400">
        {title}
      </span>
      <div className="flex flex-wrap gap-1.5">
        {words.length === 0 ? (
          <span className="text-xs text-slate-500">none matched</span>
        ) : (
          words.map((w) => (
            <span
              key={w.word}
              className={`px-2 py-0.5 rounded text-[11px] font-medium border ${chip}`}
            >
              {w.word} <span className="font-mono opacity-70">{w.n}</span>
            </span>
          ))
        )}
      </div>
    </div>
  );
}

export function MediaSentimentPulseCard({ pulse, trendSlot }: Props) {
  // State 1 — absent. A pre-#156 edition carries no pulse at all. The wording
  // stays generic because the code cannot know more than "older edition".
  if (!pulse) {
    return (
      <CardShell subtitle="Weekly beat-coverage tone." trendSlot={trendSlot}>
        <p className="text-sm text-slate-400">
          Not computed for this edition — the Media Sentiment Pulse was added after this memo
          was published, so no tone measurement exists for this week.
        </p>
      </CardShell>
    );
  }

  // State 2 — present but unavailable. Show the reason verbatim and no number:
  // a placeholder value here would be a publishing defect (#129/#133-#135, #138).
  if (!pulse.available) {
    return (
      <CardShell subtitle="Weekly beat-coverage tone." trendSlot={trendSlot}>
        <p className="text-sm text-slate-400">{pulse.reason || 'Sentiment scoring unavailable this week.'}</p>
      </CardShell>
    );
  }

  const mean = typeof pulse.meanSentiment === 'number' ? pulse.meanSentiment : null;
  const offTopic = pulse.offTopicExcluded ?? 0;
  const seen = pulse.beatItemsSeen ?? pulse.articleCount;
  const wb = pulse.wordBreakdown;

  return (
    <CardShell
      subtitle={`Tone of ${pulse.articleCount} WNBA beat article${pulse.articleCount === 1 ? '' : 's'}, word-count normalized.`}
      trendSlot={trendSlot}
    >
      {/* Tier 1 — headline mean. */}
      <div className="p-4 rounded-xl bg-surface border border-slate-800/70 flex items-baseline gap-3">
        {mean === null ? (
          <span className="text-sm text-slate-400">Mean sentiment not reported.</span>
        ) : (
          <>
            <span
              className="text-3xl font-black font-mono text-white"
              data-testid="media-sentiment-mean"
            >
              {formatSigned(mean)}
            </span>
            <span className="text-xs text-slate-400">per word</span>
          </>
        )}
      </div>

      {/* Tier 2 — extremes. */}
      <div className="grid gap-2.5 sm:grid-cols-2">
        {pulse.mostPositive && <ExtremeRow label="Most positive" item={pulse.mostPositive} />}
        {pulse.mostNegative && (
          <ExtremeRow
            label={negativeExtremeLabel(pulse.mostNegative.score)}
            item={pulse.mostNegative}
          />
        )}
      </div>

      {/* Tier 2 — word breakdown. */}
      {wb && (
        <div className="p-3.5 rounded-xl bg-surface border border-slate-800/70">
          {wb.available ? (
            <div className="grid gap-3 sm:grid-cols-2">
              <WordChips title="Top positive words (bing)" words={wb.positive} tone="positive" />
              <WordChips title="Top negative words (bing)" words={wb.negative} tone="negative" />
            </div>
          ) : (
            <p className="text-xs text-slate-400">
              Word breakdown unavailable ({wb.reason || 'unavailable'}).
            </p>
          )}
        </div>
      )}

      {/* Tier 3 — provenance / methodology. */}
      <div className="pt-3 border-t border-slate-800/80 space-y-1 text-[11px] text-slate-400">
        <p>
          {pulse.articleCount} article{pulse.articleCount === 1 ? '' : 's'} scored —{' '}
          {pulse.scrapedCount} full-text, {pulse.fallbackCount} from RSS summary.
        </p>
        {offTopic > 0 && (
          <p data-testid="media-sentiment-offtopic">
            {offTopic} of {seen} ingested beat item{seen === 1 ? '' : 's'} excluded as off-topic
            (the beat feeds also carry non-WNBA women&apos;s sports).
          </p>
        )}
        {typeof pulse.extremesMinWords === 'number' &&
          (pulse.extremesFloorApplied ? (
            <p>
              Extremes drawn from the {pulse.extremesEligibleCount ?? 0} article
              {pulse.extremesEligibleCount === 1 ? '' : 's'} of at least {pulse.extremesMinWords}{' '}
              words; all {pulse.articleCount} count toward the mean.
            </p>
          ) : (
            <p>
              No article reached the {pulse.extremesMinWords}-word floor this week, so the extremes
              come from all {pulse.articleCount} scored items and are noise-prone.
            </p>
          ))}
        <p>
          {pulse.teamNamesMasked
            ? 'Franchise names masked before scoring'
            : 'Franchise names NOT masked before scoring'}
          {pulse.jargonMasked === undefined
            ? ''
            : pulse.jargonMasked
              ? ' • basketball jargon masked before scoring'
              : ' • basketball jargon NOT masked before scoring'}
          {pulse.posDisambiguated
            ? ' • word senses resolved by POS tagging'
            : ''}
          {pulse.lexicon ? ` • lexicon: ${pulse.lexicon}` : ''}
          {pulse.method ? ` • method: ${pulse.method}` : ''}
          {pulse.modelVersion ? ` • model: ${pulse.modelVersion}` : ''}
        </p>
      </div>
    </CardShell>
  );
}
