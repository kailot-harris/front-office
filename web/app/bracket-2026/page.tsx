import fs from 'fs';
import path from 'path';
import { PlayoffBracketSeason, FinalsGamePredictionSet } from '@/lib/playoffTypes';
import { PlayoffBracket2026Client } from '@/components/PlayoffBracket2026Client';
import { FinalsGamePredictions } from '@/components/FinalsGamePredictions';

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

export default function Bracket2026Page() {
  const bracket = getBracket();
  const finals = getFinalsGames();

  return (
    <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8 space-y-10">
      <PlayoffBracket2026Client bracket={bracket} />
      {/* Finals-only, per-GAME section (#94). Sits beside the per-SERIES bracket
          tree above and changes nothing about it. */}
      <div className="border-t border-slate-800 pt-8">
        <FinalsGamePredictions finals={finals} />
      </div>
    </div>
  );
}
