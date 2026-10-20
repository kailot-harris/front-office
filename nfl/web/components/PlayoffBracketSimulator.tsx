'use client';

import React, { useState } from 'react';
import { PlayoffDataset, PlayoffSeed } from '@/lib/types';
import { TeamLogo } from '@/components/TeamLogo';
import { Trophy, Swords, RotateCcw, Sparkles } from 'lucide-react';

interface PlayoffBracketSimulatorProps {
  dataset: PlayoffDataset;
}

interface SimulatedGameResult {
  winner: PlayoffSeed;
  loser: PlayoffSeed;
  winnerScore: number;
  loserScore: number;
}

export const PlayoffBracketSimulator: React.FC<PlayoffBracketSimulatorProps> = ({ dataset }) => {
  const [isSimulated, setIsSimulated] = useState(false);
  const [champion, setChampion] = useState<PlayoffSeed | null>(null);
  const [superBowlMatchup, setSuperBowlMatchup] = useState<{ afc: PlayoffSeed; nfc: PlayoffSeed } | null>(null);

  // Helper to simulate a matchup between team A and team B based on power ratings + home field
  const simulateGame = (teamA: PlayoffSeed, teamB: PlayoffSeed, isNeutral = false): SimulatedGameResult => {
    // Higher seed is teamA (home unless neutral)
    const hca = isNeutral ? 0 : 1.93;
    const diff = teamA.power_rating - teamB.power_rating + hca;
    // Win prob using pnorm approximation (sigma = 14.6)
    const z = diff / 14.6;
    const winProbA = 0.5 * (1 + Math.sign(z) * Math.sqrt(1 - Math.exp(-2 * z * z / Math.PI)));

    const rand = Math.random();
    const aWins = rand < winProbA;
    const winner = aWins ? teamA : teamB;
    const loser = aWins ? teamB : teamA;

    // Generate realistic NFL scores
    const baseScore = 20 + Math.floor(Math.random() * 14);
    const margin = Math.max(1, Math.min(28, Math.floor(Math.abs(diff) + Math.random() * 10)));
    const winnerScore = baseScore + margin;
    const loserScore = baseScore;

    return { winner, loser, winnerScore, loserScore };
  };

  const handleSimulateBracket = () => {
    // AFC Wild Card: 2 vs 7, 3 vs 6, 4 vs 5 (1 has Bye)
    const afc1 = dataset.afc_seeds[0];
    const afcWc1 = simulateGame(dataset.afc_seeds[1], dataset.afc_seeds[6]).winner;
    const afcWc2 = simulateGame(dataset.afc_seeds[2], dataset.afc_seeds[5]).winner;
    const afcWc3 = simulateGame(dataset.afc_seeds[3], dataset.afc_seeds[4]).winner;

    // Reseed AFC Divisional: lowest remaining plays #1
    const afcDivTeams = [afcWc1, afcWc2, afcWc3].sort((a, b) => b.seed - a.seed); // lowest seed first
    const lowestAfc = afcDivTeams[0];
    const otherAfc1 = afcDivTeams[1];
    const otherAfc2 = afcDivTeams[2];

    const afcDivWinner1 = simulateGame(afc1, lowestAfc).winner;
    const afcDivWinner2 = simulateGame(
      otherAfc2.seed < otherAfc1.seed ? otherAfc2 : otherAfc1,
      otherAfc2.seed < otherAfc1.seed ? otherAfc1 : otherAfc2
    ).winner;

    // AFC Championship
    const afcChamp = simulateGame(
      afcDivWinner1.seed < afcDivWinner2.seed ? afcDivWinner1 : afcDivWinner2,
      afcDivWinner1.seed < afcDivWinner2.seed ? afcDivWinner2 : afcDivWinner1
    ).winner;

    // NFC Wild Card: 2 vs 7, 3 vs 6, 4 vs 5 (1 has Bye)
    const nfc1 = dataset.nfc_seeds[0];
    const nfcWc1 = simulateGame(dataset.nfc_seeds[1], dataset.nfc_seeds[6]).winner;
    const nfcWc2 = simulateGame(dataset.nfc_seeds[2], dataset.nfc_seeds[5]).winner;
    const nfcWc3 = simulateGame(dataset.nfc_seeds[3], dataset.nfc_seeds[4]).winner;

    // Reseed NFC Divisional
    const nfcDivTeams = [nfcWc1, nfcWc2, nfcWc3].sort((a, b) => b.seed - a.seed);
    const lowestNfc = nfcDivTeams[0];
    const otherNfc1 = nfcDivTeams[1];
    const otherNfc2 = nfcDivTeams[2];

    const nfcDivWinner1 = simulateGame(nfc1, lowestNfc).winner;
    const nfcDivWinner2 = simulateGame(
      otherNfc2.seed < otherNfc1.seed ? otherNfc2 : otherNfc1,
      otherNfc2.seed < otherNfc1.seed ? otherNfc1 : otherNfc2
    ).winner;

    // NFC Championship
    const nfcChamp = simulateGame(
      nfcDivWinner1.seed < nfcDivWinner2.seed ? nfcDivWinner1 : nfcDivWinner2,
      nfcDivWinner1.seed < nfcDivWinner2.seed ? nfcDivWinner2 : nfcDivWinner1
    ).winner;

    setSuperBowlMatchup({ afc: afcChamp, nfc: nfcChamp });

    // Super Bowl (Neutral Site)
    const sbResult = simulateGame(afcChamp, nfcChamp, true);
    setChampion(sbResult.winner);
    setIsSimulated(true);
  };

  const handleReset = () => {
    setIsSimulated(false);
    setChampion(null);
    setSuperBowlMatchup(null);
  };

  return (
    <div className="bg-surface-raised/80 border border-slate-800 rounded-xl overflow-hidden shadow-lg space-y-6 p-4 sm:p-6">
      {/* Simulator Control Header */}
      <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-4 border-b border-slate-800 pb-4">
        <div>
          <h2 className="text-base font-bold text-white flex items-center gap-2">
            <Swords className="w-5 h-5 text-emerald-400" />
            <span>Monte Carlo Playoff Bracket Simulator</span>
          </h2>
          <p className="text-xs text-slate-400 mt-0.5">
            14-Team Reseeding Format (Seeds 1–7) • Official NFL Bracket Logic with Wild Card, Divisional, Conf Champ & Super Bowl.
          </p>
        </div>

        <div className="flex items-center gap-2.5">
          <button
            onClick={handleSimulateBracket}
            className="cursor-pointer px-4 py-2 rounded-lg bg-emerald-600 hover:bg-emerald-500 text-white text-xs font-bold font-mono transition-all flex items-center gap-2 shadow-lg shadow-emerald-600/20 active:scale-95"
          >
            <Sparkles className="w-4 h-4" />
            <span>Simulate Bracket</span>
          </button>
          {isSimulated && (
            <button
              onClick={handleReset}
              className="cursor-pointer p-2 rounded-lg bg-slate-800 hover:bg-slate-700 text-slate-400 hover:text-white text-xs font-mono transition-colors"
              title="Reset to Model Probabilities"
            >
              <RotateCcw className="w-4 h-4" />
            </button>
          )}
        </div>
      </div>

      {/* Champion Banner Alert (if simulated) */}
      {isSimulated && champion && superBowlMatchup && (
        <div className="bg-gradient-to-r from-amber-600/20 via-emerald-600/20 to-indigo-600/20 border border-amber-500/40 rounded-xl p-4 flex flex-col sm:flex-row sm:items-center justify-between gap-4 animate-in fade-in zoom-in-95 duration-200">
          <div className="flex items-center gap-3.5">
            <div className="w-12 h-12 rounded-xl bg-surface/80 border border-amber-500/40 flex items-center justify-center p-1.5 shadow-lg shadow-amber-500/10">
              <TeamLogo team={champion.team} size="lg" />
            </div>
            <div>
              <span className="text-[10px] font-mono uppercase text-amber-400 font-bold flex items-center gap-1">
                <Trophy className="w-3.5 h-3.5" /> Simulated Super Bowl Champion
              </span>
              <h3 className="text-lg font-black text-white">{champion.team_name}</h3>
              <p className="text-xs text-slate-300 font-mono">
                Defeated {superBowlMatchup.afc.team === champion.team ? superBowlMatchup.nfc.team_name : superBowlMatchup.afc.team_name} in the Super Bowl!
              </p>
            </div>
          </div>

          <div className="text-right font-mono text-xs text-slate-400">
            <span className="block text-slate-500 text-[10px] uppercase">Model Probability</span>
            <span className="text-amber-400 font-bold text-sm">
              {(champion.super_bowl_win_prob * 100).toFixed(1)}% Super Bowl Equity
            </span>
          </div>
        </div>
      )}

      {/* Bracket Tree Layout (Wild Card -> Divisional -> Conf Champ -> Super Bowl) */}
      <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
        {/* AFC Bracket */}
        <div className="space-y-3">
          <div className="flex items-center justify-between border-b border-red-500/30 pb-2">
            <span className="text-xs font-mono uppercase tracking-wider text-red-400 font-bold flex items-center gap-1.5">
              <span className="w-2 h-2 rounded-full bg-red-500" />
              AFC Postseason Field (Seeds 1–7)
            </span>
            <span className="text-[10px] font-mono text-slate-500">10,000 MC Trials</span>
          </div>

          <div className="space-y-2">
            {dataset.afc_seeds.map((s) => (
              <div
                key={s.team}
                className={`p-2.5 rounded-lg border transition-all flex items-center justify-between ${
                  champion?.team === s.team
                    ? 'bg-amber-950/30 border-amber-500/50 shadow-md'
                    : 'bg-surface/50 border-slate-800 hover:border-slate-700'
                }`}
              >
                <div className="flex items-center gap-2.5 min-w-0">
                  <span
                    className={`w-6 h-6 rounded-md flex items-center justify-center font-mono text-xs font-bold ${
                      s.seed === 1
                        ? 'bg-amber-500/20 text-amber-400 border border-amber-500/30'
                        : 'bg-slate-800 text-slate-300'
                    }`}
                  >
                    {s.seed}
                  </span>
                  <TeamLogo team={s.team} size="sm" />
                  <div className="min-w-0">
                    <div className="flex items-center gap-1.5">
                      <span className="font-bold text-xs text-white truncate">{s.team_name}</span>
                      {s.seed === 1 && (
                        <span className="text-[9px] font-mono px-1 py-0.2 rounded bg-amber-500/20 text-amber-300 border border-amber-500/30 font-semibold">
                          1ST BYE
                        </span>
                      )}
                    </div>
                    <span className="text-[10px] font-mono text-slate-500">
                      {s.division} • Pwr: {s.power_rating > 0 ? `+${s.power_rating.toFixed(1)}` : s.power_rating.toFixed(1)}
                    </span>
                  </div>
                </div>

                {/* Advancement Probabilities */}
                <div className="flex items-center gap-3 text-right font-mono text-[11px] flex-shrink-0">
                  <div>
                    <span className="text-[9px] text-slate-500 block uppercase">Divisional</span>
                    <span className="font-semibold text-slate-300">
                      {(s.divisional_win_prob * 100).toFixed(0)}%
                    </span>
                  </div>
                  <div>
                    <span className="text-[9px] text-slate-500 block uppercase">Conf Champ</span>
                    <span className="font-semibold text-cyan-400">
                      {(s.conf_champ_win_prob * 100).toFixed(0)}%
                    </span>
                  </div>
                  <div className="min-w-[48px]">
                    <span className="text-[9px] text-slate-500 block uppercase">Super Bowl</span>
                    <span className="font-bold text-amber-400">
                      {(s.super_bowl_win_prob * 100).toFixed(1)}%
                    </span>
                  </div>
                </div>
              </div>
            ))}
          </div>
        </div>

        {/* NFC Bracket */}
        <div className="space-y-3">
          <div className="flex items-center justify-between border-b border-blue-500/30 pb-2">
            <span className="text-xs font-mono uppercase tracking-wider text-blue-400 font-bold flex items-center gap-1.5">
              <span className="w-2 h-2 rounded-full bg-blue-500" />
              NFC Postseason Field (Seeds 1–7)
            </span>
            <span className="text-[10px] font-mono text-slate-500">10,000 MC Trials</span>
          </div>

          <div className="space-y-2">
            {dataset.nfc_seeds.map((s) => (
              <div
                key={s.team}
                className={`p-2.5 rounded-lg border transition-all flex items-center justify-between ${
                  champion?.team === s.team
                    ? 'bg-amber-950/30 border-amber-500/50 shadow-md'
                    : 'bg-surface/50 border-slate-800 hover:border-slate-700'
                }`}
              >
                <div className="flex items-center gap-2.5 min-w-0">
                  <span
                    className={`w-6 h-6 rounded-md flex items-center justify-center font-mono text-xs font-bold ${
                      s.seed === 1
                        ? 'bg-amber-500/20 text-amber-400 border border-amber-500/30'
                        : 'bg-slate-800 text-slate-300'
                    }`}
                  >
                    {s.seed}
                  </span>
                  <TeamLogo team={s.team} size="sm" />
                  <div className="min-w-0">
                    <div className="flex items-center gap-1.5">
                      <span className="font-bold text-xs text-white truncate">{s.team_name}</span>
                      {s.seed === 1 && (
                        <span className="text-[9px] font-mono px-1 py-0.2 rounded bg-amber-500/20 text-amber-300 border border-amber-500/30 font-semibold">
                          1ST BYE
                        </span>
                      )}
                    </div>
                    <span className="text-[10px] font-mono text-slate-500">
                      {s.division} • Pwr: {s.power_rating > 0 ? `+${s.power_rating.toFixed(1)}` : s.power_rating.toFixed(1)}
                    </span>
                  </div>
                </div>

                {/* Advancement Probabilities */}
                <div className="flex items-center gap-3 text-right font-mono text-[11px] flex-shrink-0">
                  <div>
                    <span className="text-[9px] text-slate-500 block uppercase">Divisional</span>
                    <span className="font-semibold text-slate-300">
                      {(s.divisional_win_prob * 100).toFixed(0)}%
                    </span>
                  </div>
                  <div>
                    <span className="text-[9px] text-slate-500 block uppercase">Conf Champ</span>
                    <span className="font-semibold text-cyan-400">
                      {(s.conf_champ_win_prob * 100).toFixed(0)}%
                    </span>
                  </div>
                  <div className="min-w-[48px]">
                    <span className="text-[9px] text-slate-500 block uppercase">Super Bowl</span>
                    <span className="font-bold text-amber-400">
                      {(s.super_bowl_win_prob * 100).toFixed(1)}%
                    </span>
                  </div>
                </div>
              </div>
            ))}
          </div>
        </div>
      </div>
    </div>
  );
};
