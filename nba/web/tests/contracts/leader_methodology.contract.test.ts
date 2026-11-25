/**
 * leader_methodology.json contract (consumed by /players/leaders/methodology).
 *
 * Written by tools/build_leader_methodology.R from
 * docs/research/leader_reliability_study_results.json and config.R.
 */
import crypto from 'crypto';
import fs from 'fs';
import path from 'path';
import { describe, it, expect } from 'vitest';
import { DATA_DIR } from '../helpers/datasets';
import type { LeaderMethodologyPayload } from '@/lib/leaderMethodologyTypes';

const FILE = path.join(DATA_DIR, 'leader_methodology.json');
const STUDY_FILE = path.resolve(DATA_DIR, '..', '..', '..', 'docs', 'research', 'leader_reliability_study_results.json');
const RAW = fs.readFileSync(FILE, 'utf-8');
const DATA = JSON.parse(RAW) as LeaderMethodologyPayload;
const FORBIDDEN_BETTING_RE =
  /\b(odds|spread|spreads|bet|bets|betting|wager|wagers|parlay|sportsbook|moneyline|over_under|vig|juice|handicap)\b/i;

describe('leader_methodology.json contract', () => {
  it('carries valid provenance matching the study JSON sha256', () => {
    expect(DATA.schema_version).toBe(1);
    expect(DATA.source_commit).toMatch(/^[0-9a-f]{40}$/);
    expect(DATA.study_run_date).toMatch(/^\d{4}-\d{2}-\d{2}$/);
    // CRLF normalised to LF, matching nba_lifecycle_sha256 in config.R, so the
    // check gives the same answer on a Windows checkout and in CI.
    const studyText = fs.readFileSync(STUDY_FILE, 'utf-8').replace(/\r\n/g, '\n');
    const sha = crypto.createHash('sha256').update(studyText, 'utf-8').digest('hex');
    expect(DATA.source_sha256).toBe(sha);
  });

  it('has all 21 leader minimums across counting, shooting, rates, and rapm', () => {
    expect(DATA.minimums).toHaveLength(21);
    const groups = new Set(DATA.minimums.map((m) => m.group));
    expect(groups).toEqual(new Set(['counting', 'shooting', 'rates', 'rapm']));
    const keys = new Set(DATA.minimums.map((m) => m.key));
    expect(keys.size).toBe(21);
  });

  it('every reliability field is either finite or null with a non-empty reason', () => {
    for (const m of DATA.minimums) {
      const r = m.reliability;
      expect(Number.isFinite(r.split_half_r)).toBe(true);
      expect(r.split_half_lo).toBeLessThanOrEqual(r.split_half_r);
      expect(r.split_half_r).toBeLessThanOrEqual(r.split_half_hi);

      if (r.spearman_brown_r === null) {
        expect(typeof r.spearman_brown_null_reason).toBe('string');
        expect(r.spearman_brown_null_reason!.length).toBeGreaterThan(0);
      } else {
        expect(Number.isFinite(r.spearman_brown_r)).toBe(true);
      }

      if (r.rest_of_season_r === null) {
        expect(typeof r.rest_of_season_null_reason).toBe('string');
        expect(r.rest_of_season_null_reason!.length).toBeGreaterThan(0);
      } else {
        expect(Number.isFinite(r.rest_of_season_r)).toBe(true);
      }
    }
  });

  it('carries no betting vocabulary', () => {
    expect(RAW).not.toMatch(FORBIDDEN_BETTING_RE);
  });
});
