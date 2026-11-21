/**
 * Player DNA invariants (player_dna_profiles.json, written by mlb_player_dna_engine.R).
 *
 * Recomputes the peer comps from the published skill vectors and checks the rules stated in
 * the engine header: same type only, top 5, cosine on 50-centred vectors over shared non-null
 * dimensions (at least 4), similarityPct = max(cos, 0) * 100, ties on playerId, and players
 * with too few measured dimensions get a null rating / archetype, no peers, and are nobody's peer.
 */
import fs from 'fs';
import path from 'path';
import { describe, it, expect } from 'vitest';
import { loadAllDatasets } from '../helpers/datasets';
import type { PlayerDnaProfile } from '@/lib/playerDnaTypes';

// Mirrors mlb_player_dna_engine.R
const MIN_DIMS = 8;
const MIN_SHARED_DIMS = 4;
const PEER_COUNT = 5;
const EXPECTED_DIMS = { Batter: 16, Pitcher: 15 } as const;

type Vec = Record<string, number | null>;
const vecOf = (p: PlayerDnaProfile) => p.skillVector as unknown as Vec;
const present = (p: PlayerDnaProfile) => Object.values(vecOf(p)).filter((v) => v !== null).length;

/** max(cos, 0) * 100 over shared non-null dims of 50-centred vectors; null below the minimum. */
export function centredCosinePct(a: Vec, b: Vec): number | null {
  let dot = 0;
  let na = 0;
  let nb = 0;
  let shared = 0;
  for (const k of Object.keys(a)) {
    const x = a[k];
    const y = b[k];
    if (x === null || y === null || x === undefined || y === undefined) continue;
    shared++;
    dot += (x - 50) * (y - 50);
    na += (x - 50) ** 2;
    nb += (y - 50) ** 2;
  }
  if (shared < MIN_SHARED_DIMS || na === 0 || nb === 0) return null;
  return Math.max(dot / Math.sqrt(na * nb), 0) * 100;
}

describe('player DNA - window, null and peer-comp invariants', () => {
  const { playerDna: d } = loadAllDatasets();
  const byId = new Map(d.profiles.map((p) => [p.playerId, p]));

  it('publishes one season window with provenance', () => {
    expect(d.season).toBeGreaterThanOrEqual(2020);
    expect(d.generatedAt).toBe(d.generated_at);
    expect(Number.isNaN(Date.parse(d.generatedAt))).toBe(false);
    if (d.throughDate !== null) {
      expect(d.throughDate.slice(0, 4)).toBe(String(d.season));
    }
  });

  it('player ids are unique and every type has the documented dimension count', () => {
    expect(byId.size).toBe(d.profiles.length);
    for (const type of ['Batter', 'Pitcher'] as const) {
      const ps = d.profiles.filter((p) => p.playerType === type);
      expect(ps.length).toBeGreaterThan(MIN_DIMS);
      const keys = Object.keys(vecOf(ps[0])).sort();
      expect(keys).toHaveLength(EXPECTED_DIMS[type]);
      for (const p of ps) expect(Object.keys(vecOf(p)).sort()).toEqual(keys);
    }
  });

  it('missing dimensions publish null and the rating is the mean of measured dimensions', () => {
    for (const p of d.profiles) {
      const vals = Object.values(vecOf(p)).filter((v): v is number => v !== null);
      if (vals.length < MIN_DIMS) {
        expect(p.overallRating, `${p.playerName} rating needs >= ${MIN_DIMS} dims`).toBeNull();
        expect(p.archetype).toBeNull();
        expect(p.peerComps).toEqual([]);
      } else {
        const mean = vals.reduce((a, b) => a + b, 0) / vals.length;
        expect(p.overallRating).not.toBeNull();
        expect(Math.abs((p.overallRating as number) - mean)).toBeLessThanOrEqual(0.5 + 1e-9);
        expect(p.archetype).not.toBeNull();
      }
    }
  });

  it('every peer comp is another eligible player of the same type, listed once', () => {
    for (const p of d.profiles) {
      expect(p.peerComps.length).toBeLessThanOrEqual(PEER_COUNT);
      const ids = p.peerComps.map((c) => c.playerId);
      expect(new Set(ids).size, `${p.playerName} repeats a peer`).toBe(ids.length);
      for (const c of p.peerComps) {
        expect(c.playerId, `${p.playerName} is compared with themself`).not.toBe(p.playerId);
        const peer = byId.get(c.playerId);
        expect(peer, `${c.compName} is not in the dataset`).toBeDefined();
        expect(peer?.playerType, `${p.playerName} -> ${c.compName} crosses types`).toBe(p.playerType);
        expect(c.compName).toBe(peer?.playerName);
        expect(c.team).toBe(peer?.team);
        expect(c.archetype).toBe(peer?.archetype);
        expect(present(peer as PlayerDnaProfile), `${c.compName} leaked as a peer`).toBeGreaterThanOrEqual(MIN_DIMS);
      }
    }
  });

  it('similarityPct is the recomputed centred cosine, sorted best first with ties on playerId', () => {
    for (const p of d.profiles) {
      p.peerComps.forEach((c, i) => {
        const peer = byId.get(c.playerId) as PlayerDnaProfile;
        const sim = centredCosinePct(vecOf(p), vecOf(peer));
        expect(sim, `${p.playerName} -> ${c.compName} shares < ${MIN_SHARED_DIMS} dims`).not.toBeNull();
        expect(Math.abs(c.similarityPct - (sim as number))).toBeLessThanOrEqual(0.051);
        if (i > 0) {
          const prev = p.peerComps[i - 1];
          expect(prev.similarityPct).toBeGreaterThanOrEqual(c.similarityPct);
          if (prev.similarityPct === c.similarityPct) expect(prev.playerId < c.playerId).toBe(true);
        }
      });
    }
  });

  it('the listed peers are the top 5 of all eligible same-type candidates', () => {
    for (const p of d.profiles) {
      if (present(p) < MIN_DIMS) continue;
      const listed = new Set(p.peerComps.map((c) => c.playerId));
      const others = d.profiles
        .filter((q) => q.playerType === p.playerType && q.playerId !== p.playerId && present(q) >= MIN_DIMS)
        .map((q) => ({ id: q.playerId, sim: centredCosinePct(vecOf(p), vecOf(q)) }))
        .filter((x): x is { id: string; sim: number } => x.sim !== null);
      expect(p.peerComps.length).toBe(Math.min(PEER_COUNT, others.length));
      const worstListed = Math.min(...p.peerComps.map((c) => c.similarityPct));
      const bestUnlisted = Math.max(-1, ...others.filter((x) => !listed.has(x.id)).map((x) => x.sim));
      expect(worstListed, `${p.playerName} skipped a closer peer`).toBeGreaterThanOrEqual(bestUnlisted - 0.1);
    }
  });

  it('publishes the dimension and category metadata the page reads, matching every profile', () => {
    for (const type of ['Batter', 'Pitcher'] as const) {
      const dims = d.dimensions[type];
      const cats = d.categories[type];
      expect(dims).toHaveLength(EXPECTED_DIMS[type]);
      const catKeys = cats.map((c) => c.key);
      for (const dim of dims) expect(catKeys, `${dim.key} has an unknown category`).toContain(dim.category);
      for (const c of cats) expect(dims.some((dim) => dim.category === c.key), `${c.key} has no dimensions`).toBe(true);
      for (const p of d.profiles.filter((q) => q.playerType === type)) {
        expect(Object.keys(vecOf(p))).toEqual(dims.map((dim) => dim.key));
        expect(Object.keys(p.categoryScores)).toEqual(catKeys);
      }
    }
  });
});

// FanGraphs reports "- - -" for a player who played for 2+ clubs. That must publish as a
// null team, never as a made-up code such as "MLB" that readers would take for a team.
describe('player DNA - no made-up "MLB" team', () => {
  const { playerDna: d } = loadAllDatasets();

  it('no profile or peer comp has team "MLB"; multi-club players are null', () => {
    const bad: string[] = [];
    for (const p of d.profiles) {
      if ((p.team as string | null) === 'MLB') bad.push(p.playerName);
      for (const c of p.peerComps) if ((c.team as string | null) === 'MLB') bad.push(`${p.playerName} -> ${c.compName}`);
    }
    expect(bad, 'team "MLB" published').toEqual([]);
    const raw = fs.readFileSync(path.join(__dirname, '..', '..', 'public', 'data', 'player_dna_profiles.json'), 'utf-8');
    expect(raw).not.toMatch(/"team"\s*:\s*"MLB"/);
  });

  it('the engine maps no FanGraphs code to "MLB"', () => {
    const engine = fs.readFileSync(path.join(__dirname, '..', '..', '..', 'mlb_player_dna_engine.R'), 'utf-8');
    expect(engine).not.toMatch(/=\s*"MLB"/);
  });
});
