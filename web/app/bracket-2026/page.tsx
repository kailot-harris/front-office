import fs from 'fs';
import path from 'path';
import { PlayoffBracketSeason } from '@/lib/playoffTypes';
import { PlayoffBracket2026Client } from '@/components/PlayoffBracket2026Client';

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

export default function Bracket2026Page() {
  const bracket = getBracket();

  return (
    <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
      <PlayoffBracket2026Client bracket={bracket} />
    </div>
  );
}
