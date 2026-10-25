import { BASE_PATH } from '@/lib/basePath';
import { FinalsSeriesBacktestSet } from '@/lib/playoffTypes';

/**
 * The animated net-rating trajectory that sits beside the series backtest table
 * (issue #96).
 *
 * WHAT IT SHOWS, AND WHY IT IS HERE. The backtest table says what the model
 * would have said at each point in the Finals; this chart shows the thing that
 * moved underneath it — the two teams' adjusted net ratings, recomputed at every
 * playoff game date from only the games played up to that date. They are the
 * same numbers: the animation is rendered from the same ratings the table's rows
 * are built on, so the two can never disagree.
 *
 * REDUCED MOTION. A looping GIF has no pause control, so this is a <picture>
 * whose `prefers-reduced-motion: reduce` source is a still of the animation's
 * FINAL frame. The browser fetches exactly one of the two — the <img> is the
 * fallback, not a second download — and a reader who asked for less motion gets
 * the end state rather than nothing. Both files are written by the same render
 * pass, so the still always matches the last frame of the animation.
 *
 * ALT TEXT is composed from the real first/last adjusted net ratings in the
 * payload, not written as a fixed sentence and not a filename: a screen-reader
 * user gets the chart's actual conclusion (who rose, who fell, by how much), and
 * it stays correct for a different matchup or a re-run.
 *
 * PROVENANCE. These are reconstructions from box scores, not forecasts that were
 * published at the time. The caption under the chart repeats that in the reader's
 * own terms, so the disclaimer travels with the image if it is screenshotted away
 * from the table's warning banner.
 *
 * FAIL-SAFE: the page only renders this when the media files are actually on
 * disk, and it renders nothing at all without a matchup — never a broken image.
 */
export function NetRatingTrajectory({
  data,
  season,
}: {
  data: FinalsSeriesBacktestSet;
  season: number;
}) {
  const { matchup, infoSets } = data;
  if (!matchup || infoSets.length === 0) return null;

  const first = infoSets[0];
  const last = infoSets[infoSets.length - 1];

  const fmt = (n: number) => `${n >= 0 ? '+' : ''}${n.toFixed(2)}`;
  /** 'falls from +8.63 to +7.53', or 'holds at +8.63' when it did not move. */
  const describe = (from: number, to: number) => {
    if (fmt(from) === fmt(to)) return `holds at ${fmt(from)}`;
    return `${to > from ? 'rises' : 'falls'} from ${fmt(from)} to ${fmt(to)}`;
  };

  const altText =
    `Animated line chart of adjusted net rating through the ${season} playoffs. ` +
    `Across the Finals, ${matchup.teamHigh} ${describe(first.netAdjHigh, last.netAdjHigh)} ` +
    `while ${matchup.teamLow} ${describe(first.netAdjLow, last.netAdjLow)}. ` +
    `One point per playoff game date, each using only the games played up to that date.`;

  const gif = `${BASE_PATH}/media/net_rating_trajectory_${season}.gif`;
  const png = `${BASE_PATH}/media/net_rating_trajectory_${season}.png`;

  return (
    <figure className="mt-6">
      <div className="overflow-hidden rounded-lg border border-slate-800 bg-slate-900/60">
        <picture>
          <source media="(prefers-reduced-motion: reduce)" srcSet={png} />
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img
            src={gif}
            alt={altText}
            width={1000}
            height={600}
            className="block h-auto w-full"
          />
        </picture>
      </div>
      <figcaption className="mt-2 text-[12px] leading-relaxed text-slate-500">
        The ratings behind the forecasts above, recomputed at every playoff game
        date. Like the table, this is a reconstruction from box scores — not a
        forecast that was published at the time.
      </figcaption>
    </figure>
  );
}
