import fs from 'fs';
import path from 'path';
import {
  PlayoffBracketSeason,
  FinalsGamePredictionSet,
  FinalsSeriesBacktestSet,
} from '@/lib/playoffTypes';
import { PlayoffBracket2026Client } from '@/components/PlayoffBracket2026Client';
import { FinalsGamePredictions } from '@/components/FinalsGamePredictions';
import { FinalsSeriesBacktest } from '@/components/FinalsSeriesBacktest';
import { NetRatingTrajectory } from '@/components/NetRatingTrajectory';

export const metadata = {
  title: '2026 Playoff Bracket: Prediction vs Result | WNBA Analytics',
  description:
    "The 2026 WNBA postseason round by round, with the model's prediction for each series shown beside how that series actually resolved.",
};

/**
 * Fail-safe read, matching the convention every other route here follows: a
 * missing or unparseable artifact returns an empty `series` array rather than
 * throwing, and the client renders its empty state. `sourceNote` carries the
 * reason through to the page so a blank bracket is never unexplained.
 */
function getBracket(): PlayoffBracketSeason {
  const filePath = path.join(process.cwd(), 'public', 'data', 'playoff_bracket_2026.json');

  const empty = (note: string): PlayoffBracketSeason => ({
    generated_at: '',
    season: 2026,
    generatedAt: '',
    sourceNote: note,
    series: [],
  });

  if (!fs.existsSync(filePath)) {
    return empty('playoff_bracket_2026.json has not been generated yet.');
  }
  try {
    const content = fs.readFileSync(filePath, 'utf-8');
    const parsed = JSON.parse(content) as PlayoffBracketSeason;
    if (!parsed || !Array.isArray(parsed.series)) {
      return empty('playoff_bracket_2026.json is present but contains no series array.');
    }
    return parsed;
  } catch (err) {
    console.error('Failed to load playoff_bracket_2026.json:', err);
    return empty('playoff_bracket_2026.json could not be parsed.');
  }
}

/**
 * Finals per-game payload (issue #94), read with the same fail-safe contract as
 * the bracket above: a missing, unparseable or matchup-less artifact returns a
 * null `matchup` with an empty `games` array rather than throwing, and the
 * section renders its empty state. `sourceNote` carries the reason to the page so
 * an absent Finals section is never unexplained.
 */
function getFinalsGames(): FinalsGamePredictionSet {
  const filePath = path.join(
    process.cwd(),
    'public',
    'data',
    'finals_game_predictions_2026.json'
  );

  const empty = (note: string): FinalsGamePredictionSet => ({
    generated_at: '',
    season: 2026,
    generatedAt: '',
    sourceNote: note,
    formatKey: '',
    formatLabel: '',
    restApplied: false,
    restNote: '',
    matchup: null,
    lengthDistribution: [],
    games: [],
  });

  if (!fs.existsSync(filePath)) {
    return empty('finals_game_predictions_2026.json has not been generated yet.');
  }
  try {
    const content = fs.readFileSync(filePath, 'utf-8');
    const parsed = JSON.parse(content) as FinalsGamePredictionSet;
    if (!parsed || !Array.isArray(parsed.games)) {
      return empty('finals_game_predictions_2026.json is present but contains no games array.');
    }
    return parsed;
  } catch (err) {
    console.error('Failed to load finals_game_predictions_2026.json:', err);
    return empty('finals_game_predictions_2026.json could not be parsed.');
  }
}

/**
 * Walk-forward series backtest, read with the same fail-safe contract as the two
 * artifacts above: a missing or unparseable file returns an empty `infoSets` array
 * with a labeled `sourceNote`, and the section renders its empty state.
 *
 * This payload is a RECONSTRUCTION, not an archived forecast — see the header on
 * FinalsSeriesBacktestSet. It is rendered BELOW the per-game section and changes
 * nothing about the bracket tree, whose Finals row stays `available: false`.
 */
function getFinalsBacktest(): FinalsSeriesBacktestSet {
  const filePath = path.join(
    process.cwd(),
    'public',
    'data',
    'finals_series_backtest_2026.json'
  );

  const empty = (note: string): FinalsSeriesBacktestSet => ({
    generated_at: '',
    season: 2026,
    generatedAt: '',
    sourceNote: note,
    provenance: '',
    matchup: null,
    games: [],
    infoSets: [],
  });

  if (!fs.existsSync(filePath)) {
    return empty('The Finals series backtest has not been generated yet.');
  }
  try {
    const content = fs.readFileSync(filePath, 'utf-8');
    const parsed = JSON.parse(content) as FinalsSeriesBacktestSet;
    if (!parsed || !Array.isArray(parsed.infoSets)) {
      return empty('The Finals series backtest could not be read.');
    }
    return parsed;
  } catch (err) {
    console.error('Failed to load finals_series_backtest_2026.json:', err);
    return empty('The Finals series backtest could not be read.');
  }
}

/**
 * Net-rating trajectory media (issue #96), checked at build time rather than
 * assumed: this is a generated artifact like every JSON payload above, and it is
 * produced by a tools/ script that is not part of the daily pipeline, so a
 * checkout can legitimately be missing it. Both the animation and its
 * reduced-motion still must be present — the generator writes the pair or
 * neither, and rendering half of it would show a broken image to exactly the
 * readers who asked for less motion. Missing either one simply omits the chart;
 * the backtest table it illustrates stands on its own.
 */
function hasTrajectoryMedia(season: number): boolean {
  const dir = path.join(process.cwd(), 'public', 'media');
  return (
    fs.existsSync(path.join(dir, `net_rating_trajectory_${season}.gif`)) &&
    fs.existsSync(path.join(dir, `net_rating_trajectory_${season}.png`))
  );
}

export default function Bracket2026Page() {
  const bracket = getBracket();
  const finals = getFinalsGames();
  const backtest = getFinalsBacktest();
  const showTrajectory = hasTrajectoryMedia(backtest.season);

  /**
   * The page reads newest-round-first (#98): Finals, then Semifinals, then
   * Round 1. The Finals per-game table, the series backtest and the trajectory
   * figure are therefore handed to the bracket component as that round's own
   * content, so they render inside the Finals section instead of sitting below
   * every other round. They are built here, in the server component, because
   * they depend on the fail-safe artifact reads above.
   */
  const roundExtras = {
    Finals: (
      <div className="space-y-10 pt-2">
        {/* Finals-only, per-GAME section (#94). Sits beside the per-SERIES
            bracket row above and changes nothing about it. */}
        <div className="border-t border-slate-800 pt-8">
          <FinalsGamePredictions finals={finals} />
        </div>
        {/* Walk-forward reconstruction of the SERIES-level forecast. Kept after
            the per-game table: it is the weakest-provenance block on the page. */}
        <div className="border-t border-slate-800 pt-8">
          <FinalsSeriesBacktest data={backtest} />
          {/* The ratings that moved underneath the table above (#96). Rendered
              immediately after it, inside the same section, because it shares the
              table's reconstruction disclaimer and means nothing without it. */}
          {showTrajectory && <NetRatingTrajectory data={backtest} season={backtest.season} />}
        </div>
      </div>
    ),
  };

  return (
    <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8 space-y-10">
      <PlayoffBracket2026Client bracket={bracket} roundExtras={roundExtras} />
    </div>
  );
}
