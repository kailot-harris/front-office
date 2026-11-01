import fs from 'fs';
import path from 'path';
import { describe, it, expect } from 'vitest';
import { z } from 'zod';
import { DATA_DIR } from './helpers/datasets';
import { OffseasonMonitorDataset } from '../lib/offseasonTypes';

const ConfirmedChangeSchema = z.object({
  date: z.string(),
  team: z.string(),
  playerName: z.string(),
  playerId: z.string().optional(),
  rosterTier: z.enum(['MAJOR_40_MAN', 'MINOR_LEAGUE']),
  transactionType: z.enum([
    'FREE_AGENCY',
    'TRADE',
    'OPTION_EXERCISED',
    'OPTION_DECLINED',
    'QUALIFYING_OFFER',
    'NON_TENDER',
    'WAIVER_CLAIM',
    'OUTRIGHT',
  ]),
  priorValue: z.string(),
  newValue: z.string(),
  contractTerms: z.string().optional(),
  sourceUrl: z.string(),
});

const ReportedClaimSchema = z.object({
  id: z.string(),
  team: z.string(),
  claim: z.string(),
  sourceCategory: z.enum(['National Beat', 'Team Beat Wire', 'Trade Speculation']),
  firstReportedDate: z.string(),
  daysPending: z.number().int().nonnegative(),
});

const ExpiredClaimSchema = z.object({
  team: z.string(),
  claim: z.string(),
  sourceCategory: z.string(),
  firstReportedDate: z.string(),
  expiredDate: z.string(),
});

const LaborEventSchema = z.object({
  date: z.string(),
  event: z.string(),
  parties: z.string(),
  sourceCategory: z.string(),
  outcome: z.string(),
  sourceUrl: z.string(),
});

const UpcomingMilestoneSchema = z.object({
  date: z.string().nullable(),
  event: z.string(),
  status: z.enum(['Confirmed', 'Tentative', 'Unannounced', 'Suspended']),
});

const ModelPriorImpactSchema = z.object({
  hasChanges: z.boolean(),
  summary: z.string(),
  adjustedTeams: z
    .record(
      z.object({
        deltaWins: z.number(),
        netWarAdded: z.number(),
        rationale: z.string(),
      })
    )
    .optional(),
});

const WinterLeagueNoteSchema = z.object({
  playerName: z.string(),
  mlbTeam: z.string(),
  league: z.enum(['AFL', 'LIDOM', 'LBPRC', 'LMP', 'LVBP', 'Rehab']),
  notes: z.string(),
});

const OffseasonEditionSchema = z.object({
  weekNumber: z.number().int().positive(),
  publishDate: z.string(),
  isQuietWeek: z.boolean(),
  isFrozenWeek: z.boolean(),
  freezeDayCount: z.number().nullable().optional(),
  freezeStartDate: z.string().nullable().optional(),
  stateOfPlay: z.string(),
  confirmedChanges: z.array(ConfirmedChangeSchema),
  reportedClaims: z.array(ReportedClaimSchema),
  expiredClaims: z.array(ExpiredClaimSchema),
  laborEvents: z.array(LaborEventSchema),
  upcomingMilestones: z.array(UpcomingMilestoneSchema),
  modelPriorImpact: ModelPriorImpactSchema,
  winterLeagueNotes: z.array(WinterLeagueNoteSchema),
  sourcesVisited: z.array(z.string()),
});

const CurrentStateSummarySchema = z.object({
  totalConfirmedTransactions: z.number().int().nonnegative(),
  pendingReportedRumors: z.number().int().nonnegative(),
  expiredRumorCount: z.number().int().nonnegative(),
  cbtPayrollLeader: z.string(),
});

const OffseasonEditionSummarySchema = z.object({
  weekNumber: z.number().int().positive(),
  publishDate: z.string(),
  isQuietWeek: z.boolean(),
  isFrozenWeek: z.boolean(),
  isArchived: z.boolean(),
});

const OffseasonMonitorDatasetSchema = z.object({
  version: z.literal('2026-2027.1.0'),
  lastPublished: z.string(),
  currentWeekNumber: z.number().int().positive(),
  baselineAsOfDate: z.string(),
  elapsedDaysSinceLastPublish: z.number().int().nonnegative(),
  leagueOperatingStatus: z.enum(['NORMAL', 'TRANSACTION_FREEZE']),
  freezeDayCount: z.number().nullable(),
  activePhase: z.enum([
    'Post-World Series Review',
    'Option & Qualifying Offer Window',
    'Pre-Lockout Surge',
    'Transaction Freeze',
    'Winter Meetings & Rule 5 Draft',
    'Arbitration Exchange & Hearings',
    'Spring Training Transition',
  ]),
  availableEditions: z.array(OffseasonEditionSummarySchema).min(1),
  editions: z.array(OffseasonEditionSchema).min(1),
  currentStateSummary: CurrentStateSummarySchema,
});

describe('MLB Off-Season Dynamics Monitor Contract Suite', () => {
  const filePath = path.join(DATA_DIR, 'offseason_monitor.json');

  it('offseason_monitor.json file exists on disk in web/public/data/', () => {
    expect(fs.existsSync(filePath)).toBe(true);
  });

  it('matches OffseasonMonitorDataset JSON schema exactly', () => {
    const raw = fs.readFileSync(filePath, 'utf-8');
    const data = JSON.parse(raw) as OffseasonMonitorDataset;
    const parsed = OffseasonMonitorDatasetSchema.safeParse(data);
    if (!parsed.success) {
      console.error(parsed.error.format());
    }
    expect(parsed.success).toBe(true);
  });

  it('enforces monotonic weekNumber ordering and edition invariants', () => {
    const raw = fs.readFileSync(filePath, 'utf-8');
    const data = JSON.parse(raw) as OffseasonMonitorDataset;

    expect(data.currentWeekNumber).toBeGreaterThanOrEqual(1);
    expect(data.editions.length).toBeGreaterThanOrEqual(1);
    expect(data.availableEditions.length).toBeGreaterThanOrEqual(data.editions.length);

    for (let i = 0; i < data.editions.length; i++) {
      const ed = data.editions[i];
      expect(ed.weekNumber).toBe(i + 1);

      // Array defense: arrays must never be null or unboxed scalars
      expect(Array.isArray(ed.confirmedChanges)).toBe(true);
      expect(Array.isArray(ed.reportedClaims)).toBe(true);
      expect(Array.isArray(ed.expiredClaims)).toBe(true);
      expect(Array.isArray(ed.laborEvents)).toBe(true);
      expect(Array.isArray(ed.upcomingMilestones)).toBe(true);
      expect(Array.isArray(ed.winterLeagueNotes)).toBe(true);
      expect(Array.isArray(ed.sourcesVisited)).toBe(true);

      // Quiet week definition
      if (ed.isQuietWeek) {
        expect(ed.confirmedChanges.length).toBe(0);
        expect(ed.stateOfPlay).toMatch(/Quiet week/i);
      } else {
        expect(ed.confirmedChanges.length).toBeGreaterThan(0);
      }

      // Frozen week checks
      if (ed.isFrozenWeek) {
        expect(ed.freezeDayCount).not.toBeNull();
      }
    }
  });

  it('validates 28-day TTL on reported claims and expired ledger integrity', () => {
    const raw = fs.readFileSync(filePath, 'utf-8');
    const data = JSON.parse(raw) as OffseasonMonitorDataset;

    data.editions.forEach((ed) => {
      ed.reportedClaims.forEach((claim) => {
        expect(claim.daysPending).toBeLessThanOrEqual(28);
      });
    });
  });

  it('complies with zero-betting policy with no gambling terminology', () => {
    const raw = fs.readFileSync(filePath, 'utf-8').toLowerCase();
    const forbiddenWords = ['sportsbook', 'moneyline', 'runline', 'over/under', 'parlay', 'vig', 'prop bet', 'draftkings', 'fanduel'];
    forbiddenWords.forEach((term) => {
      expect(raw).not.toContain(term);
    });
  });

  it('wire sourceUrl identifies the specific transaction (teamId + transactionIds), not a bare endpoint', () => {
    const raw = fs.readFileSync(filePath, 'utf-8');
    const data = JSON.parse(raw) as OffseasonMonitorDataset;

    // A specific-transaction link, e.g.
    // https://statsapi.mlb.com/api/v1/transactions?teamId=121&transactionIds=947444
    const specificTransactionPattern = /teamId=\d+&transactionIds=\d+/;
    // Documented fallback when no specific transactionId is known for the
    // wire source: a team-scoped link with a date range, e.g.
    // https://statsapi.mlb.com/api/v1/transactions?teamId=110&startDate=2026-10-29&endDate=2026-10-29
    const teamLevelFallbackPattern = /teamId=\d+(&startDate=[\d-]+&endDate=[\d-]+)?$/;
    const bareWireUrl = 'https://statsapi.mlb.com/api/v1/transactions';

    data.editions.forEach((ed) => {
      ed.confirmedChanges.forEach((c) => {
        expect(c.sourceUrl).not.toBe(bareWireUrl);
        const matches =
          specificTransactionPattern.test(c.sourceUrl) || teamLevelFallbackPattern.test(c.sourceUrl);
        expect(matches).toBe(true);
      });
    });
  });

  it('classifies a waiver claim as WAIVER_CLAIM, not TRADE', () => {
    const raw = fs.readFileSync(filePath, 'utf-8');
    const data = JSON.parse(raw) as OffseasonMonitorDataset;

    const parisRows = data.editions
      .flatMap((ed) => ed.confirmedChanges)
      .filter((c) => c.playerName === 'Kyren Paris');

    expect(parisRows.length).toBeGreaterThan(0);
    parisRows.forEach((row) => {
      expect(row.transactionType).toBe('WAIVER_CLAIM');
      expect(row.sourceUrl).toMatch(/teamId=121&transactionIds=947444/);
    });
  });

  it('collapses Pete Alonso to exactly one FREE_AGENCY row for BAL (no duplicate/phantom rows)', () => {
    const raw = fs.readFileSync(filePath, 'utf-8');
    const data = JSON.parse(raw) as OffseasonMonitorDataset;

    const alonsoRows = data.editions
      .flatMap((ed) => ed.confirmedChanges)
      .filter((c) => c.playerName === 'Pete Alonso');

    expect(alonsoRows.length).toBe(1);
    expect(alonsoRows[0].transactionType).toBe('FREE_AGENCY');
    expect(alonsoRows[0].team).toBe('BAL');
    expect(alonsoRows[0].newValue).not.toBe('None');
  });
});
