'use client';

import React, { useState, useMemo } from 'react';
import Link from 'next/link';
import { PostseasonOpsData, WorldSeriesData } from '@/lib/types';
import {
  Trophy,
  Flame,
  ShieldCheck,
  AlertTriangle,
  Activity,
  Award,
  Download,
  Swords,
} from 'lucide-react';
import { TeamLogo } from '@/components/TeamLogo';
import { exportToCsv } from '@/lib/exportToCsv';

interface PostseasonOpsClientProps {
  data: PostseasonOpsData;
  worldSeries?: WorldSeriesData | null;
}

/** "Oct 23" — the banner never needs the year, every game is in-season. */
const formatSeriesDate = (iso: string): string =>
  new Date(`${iso}T12:00:00Z`).toLocaleDateString('en-US', {
    month: 'short',
    day: 'numeric',
    timeZone: 'UTC',
  });

export const PostseasonOpsClient: React.FC<PostseasonOpsClientProps> = ({ data, worldSeries }) => {
  const ws = worldSeries ?? null;
  const [activeTab, setActiveTab] = useState<'bracket' | 'bullpen' | 'tactical'>('bracket');
  const [bullpenLeague, setBullpenLeague] = useState<'All' | 'AL' | 'NL'>('All');

  const alSeeds = useMemo(
    () => data.bracket.filter((t) => t.league === 'AL').sort((a, b) => a.seed - b.seed),
    [data.bracket]
  );
  const nlSeeds = useMemo(
    () => data.bracket.filter((t) => t.league === 'NL').sort((a, b) => a.seed - b.seed),
    [data.bracket]
  );

  const filteredBullpen = useMemo(() => {
    return data.bullpen_status.filter((b) =>
      bullpenLeague === 'All' ? true : b.league === bullpenLeague
    );
  }, [data.bullpen_status, bullpenLeague]);

  const wsLeader = useMemo(() => {
    return [...data.bracket].sort((a, b) => b.pct_ws - a.pct_ws)[0];
  }, [data.bracket]);

  const wsSummaryLine = useMemo(() => {
    if (!ws) return '';
    const { home_field: hfa, challenger: chal } = ws;
    const hostLine = `Games 1, 2, 6, and 7 at ${ws.games[0]?.venue_name} (${hfa.team} HCA), Games 3, 4, and 5 at ${
      ws.games.find((g) => g.home_team === chal.team)?.venue_name ?? 'the challenger’s park'
    }.`;

    if (ws.status === 'scheduled') {
      return `${chal.team_name} face ${hfa.team_name} in the ${ws.format.toLowerCase()} Fall Classic. ${hostLine}`;
    }

    const champ = ws.champion === hfa.team ? hfa : ws.champion === chal.team ? chal : null;
    if (champ) {
      const runnerUp = champ.team === hfa.team ? chal : hfa;
      return `${champ.team_name} win the ${ws.title} ${champ.wins}–${runnerUp.wins} over the ${runnerUp.team_name}.`;
    }

    const leader = hfa.wins === chal.wins ? null : hfa.wins > chal.wins ? hfa : chal;
    const state = leader
      ? `${leader.team_name} lead ${Math.max(hfa.wins, chal.wins)}–${Math.min(hfa.wins, chal.wins)}`
      : `Series tied ${hfa.wins}–${chal.wins}`;
    return `${state} after ${ws.games_played} of up to ${ws.games_scheduled} games. ${hostLine}`;
  }, [ws]);

  const bracketColumns = [
    { key: 'seed', label: 'Seed' },
    { key: 'team_name', label: 'Club' },
    { key: 'division', label: 'Division' },
    { key: 'elo_rating', label: 'Elo' },
    { key: 'pct_ds', label: 'Make DS %' },
    { key: 'pct_lcs', label: 'Make LCS %' },
    { key: 'pct_pennant', label: 'Pennant %' },
    { key: 'pct_ws', label: 'Win WS %' },
  ];

  const handleExportAlBracket = () => {
    exportToCsv(alSeeds as unknown as Record<string, unknown>[], bracketColumns, 'al-postseason-bracket');
  };

  const handleExportNlBracket = () => {
    exportToCsv(nlSeeds as unknown as Record<string, unknown>[], bracketColumns, 'nl-postseason-bracket');
  };

  const handleExportBullpen = () => {
    exportToCsv(
      filteredBullpen as unknown as Record<string, unknown>[],
      [
        { key: 'full_name', label: 'Club' },
        { key: 'division', label: 'Division' },
        { key: 'proj_wins', label: 'Proj Wins' },
        { key: 'active_relievers', label: 'High-Lev Arms' },
        { key: 'relievers_fatigued', label: 'Fatigued Relievers' },
        { key: 'b2b_relievers_count', label: 'Back-to-Back Arms' },
        { key: 'avg_bullpen_fatigue', label: 'Avg Fatigue Index' },
        { key: 'bullpen_vulnerability', label: 'Vulnerability Score' },
        { key: 'vulnerability_grade', label: 'Workload Status' },
      ],
      'bullpen-workload-fatigue'
    );
  };

  // Tactical Matchup Advantage & Upset Vulnerability derived from bracket and bullpen status
  const tacticalTeams = useMemo(() => {
    const bpMap = new Map(data.bullpen_status.map((b) => [b.team, b]));
    return data.bracket.map((team) => {
      const bp = bpMap.get(team.team);
      const fatigue = bp?.avg_bullpen_fatigue ?? 25;
      const vuln = bp?.bullpen_vulnerability ?? 20;
      const elo = team.elo_rating;
      // Normal win prob vs average league opponent (Elo 1500)
      const winProbVsAvg = 1 / (1 + Math.pow(10, (1500 - elo) / 400));
      // Game Quality / Excitement Index
      const qualityIndex = Math.max(10, Math.min(99, Math.round((elo / 1500) * (1 - 2 * Math.abs(winProbVsAvg - 0.5)) * 100)));
      // Upset Vulnerability Score: based on high elo coupled with bullpen fatigue
      const upsetVulnerability = Math.max(5, Math.min(95, Math.round(((elo - 1450) / 100) * 0.4 * vuln + (fatigue * 0.6))));
      const riskTier = upsetVulnerability > 60 ? 'HIGH' : upsetVulnerability > 40 ? 'MODERATE' : 'STABLE';

      return {
        ...team,
        avg_fatigue: fatigue,
        bullpen_vuln: vuln,
        workload_grade: bp?.vulnerability_grade ?? 'Well Rested',
        win_prob_vs_avg: winProbVsAvg,
        quality_index: qualityIndex,
        upset_vulnerability: upsetVulnerability,
        risk_tier: riskTier,
        high_lev_arms: bp?.active_relievers ?? 0,
        fatigued_arms: bp?.relievers_fatigued ?? 0,
      };
    }).sort((a, b) => b.upset_vulnerability - a.upset_vulnerability);
  }, [data.bracket, data.bullpen_status]);

  const handleExportTactical = () => {
    exportToCsv(
      tacticalTeams as unknown as Record<string, unknown>[],
      [
        { key: 'team_name', label: 'Club' },
        { key: 'seed', label: 'Seed' },
        { key: 'league', label: 'League' },
        { key: 'elo_rating', label: 'Elo Rating' },
        { key: 'quality_index', label: 'Excitement Index' },
        { key: 'upset_vulnerability', label: 'Upset Vulnerability' },
        { key: 'risk_tier', label: 'Vulnerability Tier' },
        { key: 'avg_fatigue', label: 'Bullpen Fatigue' },
        { key: 'workload_grade', label: 'Workload Status' },
      ],
      'tactical-matchup-vulnerability'
    );
  };

  const highRiskCount = tacticalTeams.filter((t) => t.risk_tier === 'HIGH').length;
  const avgPostseasonElo = Math.round(data.bracket.reduce((acc, t) => acc + t.elo_rating, 0) / data.bracket.length);
  const avgFatigue = (tacticalTeams.reduce((acc, t) => acc + t.avg_fatigue, 0) / tacticalTeams.length).toFixed(1);

  return (
    <div className="space-y-6">
      {/* Top Sub-Navigation Tabs */}
      <div className="flex flex-wrap items-center gap-2 bg-surface-raised/90 border border-slate-800 rounded-xl p-2 shadow-lg">
        <button
          type="button"
          onClick={() => setActiveTab('bracket')}
          className={`flex items-center gap-2 px-4 py-2.5 rounded-lg text-sm font-bold transition-all ${
            activeTab === 'bracket'
              ? 'bg-accent-600 text-white shadow-lg shadow-accent-600/30'
              : 'text-slate-400 hover:text-white hover:bg-slate-800/60'
          }`}
        >
          <Trophy className="w-4 h-4" />
          <span>12-Team Postseason Bracket</span>
          <span
            className={`text-xs font-mono px-2 py-0.5 rounded-full ${
              activeTab === 'bracket' ? 'bg-white/20 text-white' : 'bg-slate-800 text-slate-400'
            }`}
          >
            10,000 Sims
          </span>
        </button>

        <button
          type="button"
          onClick={() => setActiveTab('bullpen')}
          className={`flex items-center gap-2 px-4 py-2.5 rounded-lg text-sm font-bold transition-all ${
            activeTab === 'bullpen'
              ? 'bg-accent-600 text-white shadow-lg shadow-accent-600/30'
              : 'text-slate-400 hover:text-white hover:bg-slate-800/60'
          }`}
        >
          <Flame className="w-4 h-4" />
          <span>Bullpen Workload & Fatigue</span>
          <span
            className={`text-xs font-mono px-2 py-0.5 rounded-full ${
              activeTab === 'bullpen' ? 'bg-white/20 text-white' : 'bg-slate-800 text-slate-400'
            }`}
          >
            30 Bullpens
          </span>
        </button>

        <button
          type="button"
          onClick={() => setActiveTab('tactical')}
          className={`flex items-center gap-2 px-4 py-2.5 rounded-lg text-sm font-bold transition-all ${
            activeTab === 'tactical'
              ? 'bg-accent-600 text-white shadow-lg shadow-accent-600/30'
              : 'text-slate-400 hover:text-white hover:bg-slate-800/60'
          }`}
        >
          <Swords className="w-4 h-4" />
          <span>Tactical Matchups & Upset Vulnerability</span>
          <span
            className={`text-xs font-mono px-2 py-0.5 rounded-full ${
              activeTab === 'tactical' ? 'bg-white/20 text-white' : 'bg-slate-800 text-slate-400'
            }`}
          >
            {highRiskCount} Elevated
          </span>
        </button>
      </div>

      {/* TAB 1: 12-Team Postseason Bracket */}
      {activeTab === 'bracket' && (
        <div className="space-y-6">
          {/* Postseason Format Banner */}
          <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4">
            <div className="bg-surface-raised/60 border border-slate-800 rounded-xl p-4 flex items-center gap-3.5">
              <TeamLogo team={wsLeader?.team} size="lg" />
              <div>
                <div className="text-xs text-slate-400 uppercase font-semibold">
                  Bracket Title Favorite
                </div>
                <div className="text-lg font-bold text-white">{wsLeader?.team_name}</div>
                <div className="text-xs text-amber-400 font-mono font-bold">
                  {wsLeader?.pct_ws.toFixed(1)}% World Series • {wsLeader?.pct_pennant.toFixed(1)}% Pennant
                </div>
              </div>
            </div>

            <div className="bg-surface-raised/60 border border-slate-800 rounded-xl p-4">
              <div className="text-xs text-slate-400 uppercase font-semibold">Wild Card Series</div>
              <div className="text-lg font-bold text-white mt-0.5">Best-of-3 (3-0 Home)</div>
              <div className="text-xs text-slate-400 mt-0.5">
                Seeds 1 & 2 earn DS Byes; #3 hosts #6, #4 hosts #5
              </div>
            </div>

            <div className="bg-surface-raised/60 border border-slate-800 rounded-xl p-4">
              <div className="text-xs text-slate-400 uppercase font-semibold">
                Division & League Series
              </div>
              <div className="text-lg font-bold text-white mt-0.5">DS (Bo5) • LCS (Bo7)</div>
              <div className="text-xs text-slate-400 mt-0.5">
                DS uses 2-2-1 home format; LCS & WS use 2-3-2 format
              </div>
            </div>

            <div className="bg-surface-raised/60 border border-slate-800 rounded-xl p-4">
              <div className="text-xs text-slate-400 uppercase font-semibold">
                Extra-Innings Rule
              </div>
              <div className="text-lg font-bold text-emerald-400 mt-0.5">Traditional Rules</div>
              <div className="text-xs text-slate-400 mt-0.5">
                No automatic ghost runner on 2nd in postseason play
              </div>
            </div>
          </div>

          {/* World Series Spotlight Banner — live series state from world_series.json */}
          {ws && (
            <div className="relative overflow-hidden rounded-2xl border border-amber-500/30 bg-gradient-to-r from-amber-500/10 via-surface-raised to-accent-500/10 p-6 shadow-2xl">
              <div className="flex flex-col xl:flex-row xl:items-center justify-between gap-6">
                <div className="flex items-center gap-4">
                  <div className="p-3 rounded-2xl bg-amber-500/20 text-amber-400 border border-amber-500/30">
                    <Trophy className="w-8 h-8" />
                  </div>
                  <div>
                    <div className="flex flex-wrap items-center gap-2">
                      <span className="text-[10px] font-extrabold uppercase tracking-widest px-2 py-0.5 rounded-full bg-amber-500/20 text-amber-300 border border-amber-500/30 font-mono">
                        Official {ws.season} Fall Classic
                      </span>
                      <span className={`text-[10px] font-extrabold uppercase tracking-widest px-2 py-0.5 rounded-full border font-mono ${
                        ws.status === 'complete'
                          ? 'bg-emerald-500/20 text-emerald-300 border-emerald-500/30'
                          : ws.status === 'in_progress'
                            ? 'bg-rose-500/20 text-rose-300 border-rose-500/30'
                            : 'bg-slate-700/40 text-slate-300 border-slate-600/40'
                      }`}>
                        {ws.status === 'complete' ? 'Final' : ws.status === 'in_progress' ? 'Series Underway' : 'Upcoming'}
                      </span>
                      <span className="text-xs text-slate-400 font-mono">
                        {ws.format} · {formatSeriesDate(ws.start_date)} – {formatSeriesDate(ws.end_date)}
                      </span>
                    </div>
                    <h2 className="text-2xl font-black text-white mt-1">
                      {ws.title}: {ws.challenger.team_name} vs. {ws.home_field.team_name}
                    </h2>
                    <p className="text-xs text-slate-300 mt-1 max-w-2xl">{wsSummaryLine}</p>
                  </div>
                </div>

                <div className="flex items-center gap-4 flex-shrink-0">
                  <div className="flex items-center gap-3 bg-surface/80 border border-slate-800 rounded-xl px-4 py-3">
                    {[ws.challenger, ws.home_field].map((side, i) => (
                      <React.Fragment key={side.team}>
                        {i === 1 && <div className="text-xs font-black text-amber-400 px-1 font-mono">VS</div>}
                        <div className="flex items-center gap-2">
                          <TeamLogo team={side.team} size="md" />
                          <div className="text-left">
                            <div className="text-xs font-bold text-white">{side.team}</div>
                            <div className={`text-lg font-black font-mono leading-none ${
                              ws.champion === side.team ? 'text-amber-400' : 'text-slate-200'
                            }`}>
                              {side.wins}
                            </div>
                          </div>
                        </div>
                      </React.Fragment>
                    ))}
                  </div>

                  <Link
                    href="/series"
                    className="flex items-center gap-2 px-4 py-3 rounded-xl bg-gradient-to-r from-amber-500 to-amber-600 hover:from-amber-400 hover:to-amber-500 text-slate-950 font-bold text-xs uppercase tracking-wider transition-all shadow-lg shadow-amber-500/20 whitespace-nowrap"
                  >
                    <Swords className="w-4 h-4" />
                    <span>Simulate Series</span>
                  </Link>
                </div>
              </div>

              {/* Game-by-game strip: resolved games show the final line, the rest stay dimmed */}
              <div className="grid grid-cols-2 sm:grid-cols-4 xl:grid-cols-7 gap-2 mt-5">
                {ws.games.map((g) => {
                  const resolved = g.is_completed && g.home_score !== null && g.away_score !== null;
                  const winScore = resolved ? Math.max(g.home_score!, g.away_score!) : null;
                  const loseScore = resolved ? Math.min(g.home_score!, g.away_score!) : null;
                  const loser = resolved ? (g.winner === g.home_team ? g.away_team : g.home_team) : null;
                  return (
                    <div
                      key={g.game_pk}
                      className={`rounded-xl border px-3 py-2 ${
                        resolved
                          ? 'border-amber-500/30 bg-surface/80'
                          : 'border-slate-800 bg-surface/40 opacity-70'
                      }`}
                    >
                      <div className="flex items-center justify-between">
                        <span className="text-[10px] font-extrabold uppercase tracking-widest text-slate-400 font-mono">
                          Gm {g.game_number}
                        </span>
                        <span className="text-[10px] text-slate-500 font-mono">{formatSeriesDate(g.game_date)}</span>
                      </div>
                      {resolved ? (
                        <>
                          <div className="mt-1 text-sm font-black text-white font-mono">
                            <span className="text-amber-400">{g.winner}</span> {winScore}
                            <span className="text-slate-500"> – </span>
                            {loseScore} <span className="text-slate-400">{loser}</span>
                          </div>
                          <div className="text-[10px] text-slate-500 mt-0.5">Final · {g.venue_name}</div>
                        </>
                      ) : (
                        <>
                          <div className="mt-1 text-sm font-bold text-slate-300 font-mono">
                            {g.away_team} @ {g.home_team}
                          </div>
                          <div className="text-[10px] text-slate-500 mt-0.5">
                            {g.status_detail} · {(g.home_win_prob * 100).toFixed(0)}% {g.home_team}
                          </div>
                        </>
                      )}
                    </div>
                  );
                })}
              </div>
            </div>
          )}

          {/* AL & NL Bracket Matchup Cards */}
          <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
            {[
              { title: 'American League (AL) Postseason Field', seeds: alSeeds, badge: 'AL' },
              { title: 'National League (NL) Postseason Field', seeds: nlSeeds, badge: 'NL' },
            ].map((lg) => (
              <div
                key={lg.badge}
                className="bg-surface-raised/80 border border-slate-800 rounded-xl overflow-hidden shadow-xl"
              >
                <div className="p-4 bg-surface/80 border-b border-slate-800 flex items-center justify-between">
                  <h3 className="text-sm font-bold text-white flex items-center gap-2">
                    <Award className="w-4 h-4 text-amber-400" />
                    <span>{lg.title}</span>
                  </h3>
                  <div className="flex items-center gap-2">
                    <span className="text-xs font-mono px-2 py-0.5 rounded bg-indigo-500/15 text-indigo-300 border border-indigo-500/30">
                      Seeds 1–6
                    </span>
                    <button
                      type="button"
                      onClick={lg.badge === 'AL' ? handleExportAlBracket : handleExportNlBracket}
                      title="Export CSV"
                      aria-label="Export table as CSV"
                      data-export-exclude
                      className="p-1.5 rounded-lg border border-slate-800 text-slate-400 hover:text-white hover:border-slate-600 transition-colors"
                    >
                      <Download className="w-3.5 h-3.5" />
                    </button>
                  </div>
                </div>

                <div className="overflow-x-auto">
                  <table className="w-full text-left border-collapse">
                    <thead>
                      <tr className="border-b border-slate-800 bg-surface/50 text-[10px] font-bold uppercase tracking-wider text-slate-400">
                        <th className="py-2.5 px-3">Seed</th>
                        <th className="py-2.5 px-3">Club</th>
                        <th className="py-2.5 px-2 text-right">Elo</th>
                        <th className="py-2.5 px-2 text-right">Make DS</th>
                        <th className="py-2.5 px-2 text-right">Make LCS</th>
                        <th className="py-2.5 px-2 text-right">Pennant</th>
                        <th className="py-2.5 px-3 text-right text-amber-400">Win WS</th>
                      </tr>
                    </thead>
                    <tbody className="divide-y divide-slate-800/60 text-xs">
                      {lg.seeds.map((t) => (
                        <tr key={t.team_id} className="hover:bg-slate-800/40">
                          <td className="py-3 px-3 font-mono">
                            <span
                              className={`px-1.5 py-0.5 rounded font-bold ${
                                t.seed <= 2
                                  ? 'bg-emerald-500/20 text-emerald-300 border border-emerald-500/30'
                                  : 'bg-slate-800 text-slate-300'
                              }`}
                            >
                              #{t.seed} {t.seed <= 2 ? 'BYE' : 'WC'}
                            </span>
                          </td>
                          <td className="py-3 px-3">
                            <div className="flex items-center gap-2">
                              <TeamLogo team={t.team} size="sm" />
                              <div>
                                <div className="font-bold text-white">{t.team_name}</div>
                                <div className="text-[10px] text-slate-400 font-mono">
                                  {t.wins.toFixed(1)} Proj W • {t.division}
                                </div>
                              </div>
                            </div>
                          </td>
                          <td className="py-3 px-2 text-right font-mono text-slate-300">
                            {t.elo_rating.toFixed(0)}
                          </td>
                          <td className="py-3 px-2 text-right font-mono text-slate-200">
                            {t.pct_ds.toFixed(1)}%
                          </td>
                          <td className="py-3 px-2 text-right font-mono text-slate-200">
                            {t.pct_lcs.toFixed(1)}%
                          </td>
                          <td className="py-3 px-2 text-right font-mono font-semibold text-indigo-300">
                            {t.pct_pennant.toFixed(1)}%
                          </td>
                          <td className="py-3 px-3 text-right font-mono font-bold text-amber-400">
                            {t.pct_ws.toFixed(1)}%
                          </td>
                        </tr>
                      ))}
                    </tbody>
                  </table>
                </div>
              </div>
            ))}
          </div>
        </div>
      )}

      {/* TAB 2: Bullpen Workload & Fatigue Monitor */}
      {activeTab === 'bullpen' && (
        <div className="space-y-4">
          <div className="bg-surface-raised/80 border border-slate-800 rounded-xl p-4 flex flex-wrap items-center justify-between gap-4">
            <div>
              <h3 className="text-base font-bold text-white flex items-center gap-2">
                <Flame className="w-5 h-5 text-amber-400" />
                <span>30-Club Relief Pitcher Workload & Bullpen Vulnerability</span>
              </h3>
              <p className="text-xs text-slate-400 mt-0.5">
                Tracks cumulative 3-day pitch counts, back-to-back appearances, and high-leverage reliever exhaustion penalties.
              </p>
            </div>

            <button
              type="button"
              onClick={handleExportBullpen}
              title="Export CSV"
              aria-label="Export table as CSV"
              data-export-exclude
              className="p-1.5 rounded-lg border border-slate-800 text-slate-400 hover:text-white hover:border-slate-600 transition-colors"
            >
              <Download className="w-3.5 h-3.5" />
            </button>
            <div className="inline-flex rounded-lg bg-surface p-1 border border-slate-800">
              {(['All', 'AL', 'NL'] as const).map((lg) => (
                <button
                  key={lg}
                  onClick={() => setBullpenLeague(lg)}
                  className={`px-3 py-1 text-xs font-semibold rounded-md transition-all ${
                    bullpenLeague === lg
                      ? 'bg-accent-600 text-white shadow-sm'
                      : 'text-slate-400 hover:text-white'
                  }`}
                >
                  {lg === 'All' ? 'All 30 Bullpens' : `${lg} League`}
                </button>
              ))}
            </div>
          </div>

          <div className="bg-surface-raised/80 border border-slate-800 rounded-xl overflow-hidden shadow-xl">
            <div className="overflow-x-auto">
              <table className="w-full text-left border-collapse">
                <thead>
                  <tr className="border-b border-slate-800 bg-surface/90 text-[11px] font-bold uppercase tracking-wider text-slate-400">
                    <th className="py-3.5 px-4">Club</th>
                    <th className="py-3.5 px-3">Division</th>
                    <th className="py-3.5 px-3 text-right">High-Lev Arms</th>
                    <th className="py-3.5 px-3 text-right">Back-to-Back (B2B)</th>
                    <th className="py-3.5 px-3 text-right">Avg Fatigue Index</th>
                    <th className="py-3.5 px-3 text-right">Vulnerability Score</th>
                    <th className="py-3.5 px-4 text-right">Workload Status</th>
                  </tr>
                </thead>
                <tbody className="divide-y divide-slate-800/60 text-sm">
                  {filteredBullpen.map((bp) => (
                    <tr key={bp.team} className="hover:bg-slate-800/40 transition-colors">
                      <td className="py-3 px-4">
                        <div className="flex items-center gap-2.5">
                          <TeamLogo team={bp.team} size="sm" />
                          <div>
                            <span className="font-bold text-white">{bp.full_name}</span>
                            <span className="text-[10px] font-mono text-slate-400 ml-1.5">
                              ({bp.proj_wins.toFixed(1)}W)
                            </span>
                          </div>
                        </div>
                      </td>
                      <td className="py-3 px-3 font-mono text-xs text-slate-400">
                        {bp.division}
                      </td>
                      <td className="py-3 px-3 text-right font-mono text-slate-200">
                        {bp.active_relievers} Tracked ({bp.relievers_fatigued} Fatigued)
                      </td>
                      <td className="py-3 px-3 text-right font-mono text-slate-200">
                        {bp.b2b_relievers_count} Arms
                      </td>
                      <td className="py-3 px-3 text-right font-mono text-amber-300">
                        {bp.avg_bullpen_fatigue.toFixed(1)} / 100
                      </td>
                      <td className="py-3 px-3 text-right font-mono font-bold text-white">
                        {bp.bullpen_vulnerability.toFixed(1)}
                      </td>
                      <td className="py-3 px-4 text-right">
                        <span
                          className={`text-xs font-mono font-bold px-2.5 py-0.5 rounded-full border ${
                            bp.vulnerability_grade === 'High Vulnerability'
                              ? 'bg-rose-500/15 text-rose-300 border-rose-500/30'
                              : bp.vulnerability_grade === 'Elevated Workload'
                              ? 'bg-amber-500/15 text-amber-300 border-amber-500/30'
                              : 'bg-emerald-500/15 text-emerald-300 border-emerald-500/30'
                          }`}
                        >
                          {bp.vulnerability_grade}
                        </span>
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          </div>
        </div>
      )}

      {/* TAB 3: Tactical Matchup Advantage & Upset Vulnerability Index */}
      {activeTab === 'tactical' && (
        <div className="space-y-6">
          {/* Tactical KPI Cards */}
          <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4">
            <div className="bg-surface-raised/60 border border-slate-800 rounded-xl p-4">
              <div className="flex items-center justify-between text-xs text-slate-400 uppercase font-semibold">
                <span>Elevated Upset Risk Clubs</span>
                <AlertTriangle className="w-4 h-4 text-red-400" />
              </div>
              <div className="text-2xl font-extrabold text-red-400 mt-1 font-mono">
                {highRiskCount} Teams
              </div>
              <div className="text-xs text-slate-400 mt-1">
                High fatigue & high leverage strain
              </div>
            </div>

            <div className="bg-surface-raised/60 border border-slate-800 rounded-xl p-4">
              <div className="flex items-center justify-between text-xs text-slate-400 uppercase font-semibold">
                <span>Mean Field Elo Rating</span>
                <Activity className="w-4 h-4 text-indigo-400" />
              </div>
              <div className="text-2xl font-extrabold text-white mt-1 font-mono">
                {avgPostseasonElo}
              </div>
              <div className="text-xs text-slate-400 mt-1">
                Postseason field baseline
              </div>
            </div>

            <div className="bg-surface-raised/60 border border-slate-800 rounded-xl p-4">
              <div className="flex items-center justify-between text-xs text-slate-400 uppercase font-semibold">
                <span>Avg Bullpen Fatigue</span>
                <Flame className="w-4 h-4 text-amber-400" />
              </div>
              <div className="text-2xl font-extrabold text-amber-400 mt-1 font-mono">
                {avgFatigue} / 100
              </div>
              <div className="text-xs text-slate-400 mt-1">
                Weighted reliever workload index
              </div>
            </div>

            <div className="bg-surface-raised/60 border border-slate-800 rounded-xl p-4">
              <div className="flex items-center justify-between text-xs text-slate-400 uppercase font-semibold">
                <span>Tactical Governance Status</span>
                <ShieldCheck className="w-4 h-4 text-emerald-400" />
              </div>
              <div className="text-2xl font-extrabold text-emerald-400 mt-1">
                ACTIVE
              </div>
              <div className="text-xs text-slate-400 mt-1 truncate">
                100% Endogenous Matchup Analytics
              </div>
            </div>
          </div>

          {/* Tactical Matchups & Vulnerability Table */}
          <div className="bg-surface-raised/80 border border-slate-800 rounded-xl overflow-hidden shadow-xl">
            <div className="p-4 bg-surface/80 border-b border-slate-800 flex items-center justify-between">
              <div>
                <h3 className="text-base font-bold text-white">
                  Tactical Matchup Advantage & Upset Vulnerability Index
                </h3>
                <p className="text-xs text-slate-400 mt-0.5">
                  Evaluates team quality, projected win probability curves, and bullpen exhaustion risks for postseason contenders.
                </p>
              </div>
              <button
                type="button"
                onClick={handleExportTactical}
                title="Export CSV"
                aria-label="Export tactical metrics as CSV"
                data-export-exclude
                className="p-1.5 rounded-lg border border-slate-800 text-slate-400 hover:text-white hover:border-slate-600 transition-colors flex-shrink-0"
              >
                <Download className="w-3.5 h-3.5" />
              </button>
            </div>

            <div className="overflow-x-auto">
              <table className="w-full text-left border-collapse">
                <thead>
                  <tr className="border-b border-slate-800 bg-surface/90 text-[11px] font-bold uppercase tracking-wider text-slate-400">
                    <th className="py-3.5 px-4">Club</th>
                    <th className="py-3.5 px-3">Seed</th>
                    <th className="py-3.5 px-3 text-right">Elo Rating</th>
                    <th className="py-3.5 px-3 text-right">Win Prob vs Avg</th>
                    <th className="py-3.5 px-3 text-right">Excitement Index</th>
                    <th className="py-3.5 px-3 text-right">Bullpen Fatigue</th>
                    <th className="py-3.5 px-3 text-right">Upset Vulnerability</th>
                    <th className="py-3.5 px-4 text-right">Vulnerability Tier</th>
                  </tr>
                </thead>
                <tbody className="divide-y divide-slate-800/60 text-sm">
                  {tacticalTeams.map((team) => (
                    <tr key={team.team} className="hover:bg-slate-800/40">
                      <td className="py-3.5 px-4">
                        <div className="flex items-center gap-2">
                          <TeamLogo team={team.team} size="sm" />
                          <div>
                            <div className="font-bold text-white">{team.team_name}</div>
                            <div className="text-[11px] text-slate-400">{team.division} &bull; {team.wins} Wins</div>
                          </div>
                        </div>
                      </td>
                      <td className="py-3.5 px-3 font-mono text-slate-300">
                        {team.league} #{team.seed}
                      </td>
                      <td className="py-3.5 px-3 text-right font-mono text-slate-200">
                        {team.elo_rating.toFixed(0)}
                      </td>
                      <td className="py-3.5 px-3 text-right font-mono text-indigo-300 font-semibold">
                        {(team.win_prob_vs_avg * 100).toFixed(1)}%
                      </td>
                      <td className="py-3.5 px-3 text-right font-mono text-emerald-400 font-bold">
                        {team.quality_index}/100
                      </td>
                      <td className="py-3.5 px-3 text-right font-mono text-slate-300">
                        {team.avg_fatigue.toFixed(1)}
                        <span className="text-[10px] text-slate-500 ml-1">({team.workload_grade})</span>
                      </td>
                      <td className="py-3.5 px-3 text-right font-mono font-bold text-amber-300">
                        {team.upset_vulnerability}/100
                      </td>
                      <td className="py-3.5 px-4 text-right">
                        <span
                          className={`px-2 py-0.5 rounded text-xs font-bold ${
                            team.risk_tier === 'HIGH'
                              ? 'bg-red-500/20 text-red-300 border border-red-500/30'
                              : team.risk_tier === 'MODERATE'
                              ? 'bg-amber-500/20 text-amber-300 border border-amber-500/30'
                              : 'bg-emerald-500/20 text-emerald-300 border border-emerald-500/30'
                          }`}
                        >
                          {team.risk_tier}
                        </span>
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          </div>
        </div>
      )}
    </div>
  );
};
