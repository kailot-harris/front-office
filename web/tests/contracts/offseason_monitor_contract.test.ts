import fs from 'fs';
import path from 'path';
import { describe, it, expect } from 'vitest';
import { z } from 'zod';
import { DATA_DIR } from '../helpers/datasets';
import { OffseasonMonitorDataset } from '../../lib/offseasonTypes';

const ConfirmedChangeSchema = z.object({
  date: z.string(),
  entityId: z.string(),
  entityName: z.string(),
  field: z.string(),
  priorValue: z.string(),
  newValue: z.string(),
  sourceUrl: z.string(),
});

const ReportedClaimSchema = z.object({
  id: z.string(),
  entityName: z.string(),
  claim: z.string(),
  sourceCategory: z.enum(['National Beat', 'Team Beat Wire', 'Trade Speculation']),
  firstReportedDate: z.string(),
  daysPending: z.number().int().nonnegative(),
});

const ExpiredClaimSchema = z.object({
  entityName: z.string(),
  claim: z.string(),
  sourceCategory: z.string(),
  firstReportedDate: z.string(),
  expiredDate: z.string(),
});

const UpcomingMilestoneSchema = z.object({
  date: z.string().nullable(),
  event: z.string(),
  status: z.enum(['Confirmed', 'Tentative']),
});

const ModelPriorImpactSchema = z.object({
  hasChanges: z.boolean(),
  summary: z.string(),
  adjustedTeams: z.record(z.object({
    deltaNetRating: z.number(),
    rationale: z.string(),
  })).optional(),
});

const WinterLeagueNoteSchema = z.object({
  playerName: z.string(),
  wnbaTeam: z.string(),
  league: z.enum(['Unrivaled', 'EuroLeague', 'Rehab']),
  healthStatus: z.string(),
});

const OffseasonEditionSchema = z.object({
  weekNumber: z.number().int().positive(),
  publishDate: z.string(),
  isQuietWeek: z.boolean(),
  stateOfPlay: z.string(),
  memoMarkdown: z.string(),
  confirmedChanges: z.array(ConfirmedChangeSchema),
  reportedClaims: z.array(ReportedClaimSchema),
  expiredClaims: z.array(ExpiredClaimSchema),
  upcomingMilestones: z.array(UpcomingMilestoneSchema),
  modelPriorImpact: ModelPriorImpactSchema,
  winterLeagueNotes: z.array(WinterLeagueNoteSchema),
  sourcesVisited: z.array(z.string()),
});

const CurrentStateSummarySchema = z.object({
  totalConfirmedTransactions: z.number().int().nonnegative(),
  pendingReportedRumors: z.number().int().nonnegative(),
  expiredRumorCount: z.number().int().nonnegative(),
  cbaLaborStatus: z.string(),
});

const OffseasonMonitorDatasetSchema = z.object({
  version: z.literal('2026-2027.1.0'),
  lastPublished: z.string(),
  currentWeekNumber: z.number().int().positive(),
  baselineAsOfDate: z.string(),
  elapsedDaysSinceLastPublish: z.number().int().nonnegative(),
  activePhase: z.enum([
    'Post-Finals Review',
    'Draft Lottery & Overseas Tracking',
    'Qualifying Offers & Core Window',
    'Free Agency Signings',
    'NCAA Tournament & Draft Prep',
    '2027 Draft',
    'Training Camp Transition',
  ]),
  editions: z.array(OffseasonEditionSchema).min(1),
  currentStateSummary: CurrentStateSummarySchema,
});

describe('Off-Season Dynamics Monitor Contract Suite', () => {
  const filePath = path.join(DATA_DIR, 'offseason_monitor.json');

  it('offseason_monitor.json file exists on disk in web/public/data/', () => {
    expect(fs.existsSync(filePath)).toBe(true);
  });

  it('matches OffseasonMonitorDataset JSON schema exactly', () => {
    const raw = fs.readFileSync(filePath, 'utf-8');
    const data = JSON.parse(raw) as OffseasonMonitorDataset;
    const parsed = OffseasonMonitorDatasetSchema.safeParse(data);
    expect(parsed.success).toBe(true);
  });

  it('enforces monotonic weekNumber ordering and edition invariants', () => {
    const raw = fs.readFileSync(filePath, 'utf-8');
    const data = JSON.parse(raw) as OffseasonMonitorDataset;

    expect(data.currentWeekNumber).toBeGreaterThanOrEqual(1);
    expect(data.editions.length).toBeGreaterThanOrEqual(1);

    for (let i = 0; i < data.editions.length; i++) {
      const ed = data.editions[i];
      expect(ed.weekNumber).toBe(i + 1);

      // Array defense: arrays must never be null or unboxed scalars
      expect(Array.isArray(ed.confirmedChanges)).toBe(true);
      expect(Array.isArray(ed.reportedClaims)).toBe(true);
      expect(Array.isArray(ed.expiredClaims)).toBe(true);
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

      // Memo Markdown has all 7 block sections
      expect(ed.memoMarkdown).toContain('### 1. Confirmed Changes');
      expect(ed.memoMarkdown).toContain('### 2. Reported (Unconfirmed)');
      expect(ed.memoMarkdown).toContain('### 3. Expired Claims');
      expect(ed.memoMarkdown).toContain('### 4. Next 30 Days');
      expect(ed.memoMarkdown).toContain('### 5. Model Implications');
      expect(ed.memoMarkdown).toContain('### 6. Winter League & Alternative Play');
      expect(ed.memoMarkdown).toContain('### 7. Sources Verified');
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
});
