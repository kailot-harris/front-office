/*
 * Live examples for /how-it-works/ (front-office#218).
 *
 * Each example belongs to one section of the page and declares, per league, the published data
 * file it reads (/front-office/<sport>/data/<file>) and the fields it uses. On page load the
 * browser tries the example's leagues in order and fills the example's slot from the first
 * league that qualifies:
 *   - its landing_digest.json loads and its season_state is not 'offseason';
 *   - its data_manifest.json loads and the landing page would not flag the file
 *     (FOStaleness.usable, the one staleness rule shared with the landing digest);
 *   - the file loads and the example finds a real value in it.
 * If no league qualifies the slot stays hidden: no placeholder, stand-in or fallback number is
 * ever shown, and the surrounding text reads correctly without it.
 *
 * Pure parts are exported on window.FOExamples (and module.exports) for
 * tools/test_guide_examples.mjs.
 */
(function (root) {
  'use strict';

  var LABEL = { nfl: 'NFL', nba: 'NBA', wnba: 'WNBA', mlb: 'MLB' };
  var Staleness = root.FOStaleness ||
    (typeof require === 'function' ? require('../landing/staleness.js') : null);

  function num(v) { return typeof v === 'number' && isFinite(v); }
  function str(v) { return typeof v === 'string' && v.trim() !== ''; }
  function pct(p) { return Math.round(p * 100) + '%'; }
  function fixed(v, d) { return v.toFixed(d); }
  function arr(v) { return Array.isArray(v) ? v : []; }
  function maxBy(rows, key) {
    var best = null;
    rows.forEach(function (r) { if (num(r[key]) && (!best || r[key] > best[key])) best = r; });
    return best;
  }
  function last(a) { return Array.isArray(a) && a.length ? a[a.length - 1] : a; }

  // Next game that has a forecast, earliest date first.
  function nextGame(rows, dateKey, probKey) {
    var open = rows.filter(function (g) {
      return g && g.is_completed === false && num(g[probKey]) && str(g.home_team_name) && str(g.away_team_name) && str(g[dateKey]);
    });
    open.sort(function (a, b) { return a[dateKey] < b[dateKey] ? -1 : a[dateKey] > b[dateKey] ? 1 : 0; });
    return open[0] || null;
  }

  function winProbNext(data, L, dateKey, probKey) {
    var g = nextGame(arr(data && data.matchups), dateKey, probKey);
    if (!g) return null;
    return 'For the next ' + L + ' game on the schedule, ' + g.away_team_name + ' at ' + g.home_team_name +
      ', the model gives ' + g.home_team_name + ' a win probability of ' + pct(g[probKey]) + '.';
  }

  function closestToEven(rows, probKey) {
    var best = null;
    rows.forEach(function (r) {
      if (!r || !num(r[probKey]) || !str(r.team_name)) return;
      if (!best || Math.abs(r[probKey] - 0.5) < Math.abs(best[probKey] - 0.5)) best = r;
    });
    return best;
  }
  function simsText(t, probKey, L) {
    return t ? t.team_name + ' reached the playoffs in ' + pct(t[probKey]) + ' of the current ' + L + ' simulations.' : null;
  }

  function basketballClutch(data, L) {
    var rows = arr(data && data.profiles).filter(function (p) {
      return p && p.qualified === true && str(p.playerName) && num(p.clutchFga) && num(p.clutchTsPct) && num(p.baseTsPct);
    });
    var p = maxBy(rows, 'clutchFga');
    if (!p) return null;
    return p.playerName + ' has taken ' + p.clutchFga + ' clutch shots this ' + L + ' season, with a true shooting percentage of ' +
      fixed(p.clutchTsPct, 1) + '% in those moments against ' + fixed(p.baseTsPct, 1) + '% overall.';
  }

  function dna(data, L) {
    var rows = arr(data && data.profiles).filter(function (p) {
      return p && str(p.playerName) && num(p.overallRating) && arr(p.peerComps).length &&
        str(p.peerComps[0].compName) && num(p.peerComps[0].similarityPct);
    });
    var p = maxBy(rows, 'overallRating');
    if (!p) return null;
    var c = p.peerComps[0];
    return 'In the current ' + L + ' profiles, the closest match for ' + p.playerName + ' is ' + c.compName +
      ', at ' + fixed(c.similarityPct, 1) + '% similarity.';
  }

  function diagnostics(n, brier, L) {
    if (!num(n) || n <= 0 || !num(brier)) return null;
    return 'Across ' + n.toLocaleString('en-US') + ' graded ' + L + ' games, the forecasts have a Brier score of ' + fixed(brier, 3) + '.';
  }

  var BB_TEAMS = { file: 'projections_season_teams.json', fields: ['[].team_name', '[].ensemble_playoff_prob'],
    extract: function (d, L) { return simsText(closestToEven(arr(d), 'ensemble_playoff_prob'), 'ensemble_playoff_prob', L); } };
  var BB_SLATES = { file: 'matchups_slates.json',
    fields: ['matchups[].is_completed', 'matchups[].game_date', 'matchups[].home_team_name', 'matchups[].away_team_name', 'matchups[].predicted_home_win_prob'],
    extract: function (d, L) { return winProbNext(d, L, 'game_date', 'predicted_home_win_prob'); } };
  var NFL_WEEK_FIELDS = ['matchups[].is_completed', 'matchups[].gameday', 'matchups[].home_team_name', 'matchups[].away_team_name', 'matchups[].home_win_prob'];
  var BB_PLAYERS = { file: 'projections_season_players.json', fields: ['[].player_name', '[].proj_pts'],
    extract: function (d, L) {
      var p = maxBy(arr(d).filter(function (r) { return r && str(r.player_name); }), 'proj_pts');
      return p ? p.player_name + ' leads the current ' + L + ' projections at ' + fixed(p.proj_pts, 1) + ' points per game.' : null;
    } };
  var DNA = { file: 'player_dna_profiles.json',
    fields: ['profiles[].playerName', 'profiles[].overallRating', 'profiles[].peerComps[].compName', 'profiles[].peerComps[].similarityPct'],
    extract: dna };
  var BB_CLUTCH = { file: 'clutch_leverage_metrics.json',
    fields: ['profiles[].playerName', 'profiles[].qualified', 'profiles[].clutchFga', 'profiles[].clutchTsPct', 'profiles[].baseTsPct'],
    extract: basketballClutch };
  var BB_DEF = { file: 'defensive_metrics.json', fields: ['profiles[].playerName', 'profiles[].versatilityScore'],
    extract: function (d, L) {
      var p = maxBy(arr(d && d.profiles).filter(function (r) { return r && str(r.playerName); }), 'versatilityScore');
      return p ? 'In the current ' + L + ' data, ' + p.playerName + ' has the highest versatility score, ' + fixed(p.versatilityScore, 1) + '.' : null;
    } };
  var BB_DIAG = { file: 'projections_diagnostics.json', fields: ['totalResolvedGames', 'brierScore'],
    extract: function (d, L) { return d ? diagnostics(d.totalResolvedGames, d.brierScore, L) : null; } };

  // WNBA publishes the same ideas with flatter shapes (top-level arrays, different field names).
  var WNBA_SLATES = { file: 'matchups_slates.json',
    fields: ['matchups[].is_completed', 'matchups[].game_date', 'matchups[].home_team_name', 'matchups[].away_team_name', 'matchups[].home_win_prob'],
    extract: function (d, L) { return winProbNext(d, L, 'game_date', 'home_win_prob'); } };
  var WNBA_DNA = { file: 'player_dna_profiles.json',
    fields: ['[].playerName', '[].overallRating', '[].similarPlayers[].playerName', '[].similarPlayers[].similarityPct'],
    extract: function (d, L) {
      return dna({ profiles: arr(d).map(function (p) {
        return p && { playerName: p.playerName, overallRating: p.overallRating,
          peerComps: arr(p.similarPlayers).map(function (c) { return { compName: c && c.playerName, similarityPct: c && c.similarityPct }; }) };
      }) }, L);
    } };
  var WNBA_CLUTCH = { file: 'clutch_leverage_metrics.json',
    fields: ['[].playerName', '[].clutchFga', '[].clutchPoints', '[].clutchFgPct'],
    extract: function (d, L) {
      var p = maxBy(arr(d).filter(function (r) { return r && str(r.playerName) && num(r.clutchPoints) && num(r.clutchFgPct); }), 'clutchFga');
      return p ? p.playerName + ' has taken ' + p.clutchFga + ' clutch shots this ' + L + ' season, scoring ' + p.clutchPoints +
        ' points and making ' + fixed(p.clutchFgPct, 1) + '% of them.' : null;
    } };
  var WNBA_DEF = { file: 'defensive_metrics.json', fields: ['[].playerName', '[].versatilityScore'],
    extract: function (d, L) { return BB_DEF.extract({ profiles: arr(d) }, L); } };

  var EXAMPLES = [
    { id: 'win-probability', section: 'team-ratings-and-win-probabilities', sources: {
      nfl: { file: 'matchups_current_week.json', fields: NFL_WEEK_FIELDS,
        extract: function (d, L) { return winProbNext(d, L, 'gameday', 'home_win_prob'); } },
      nba: BB_SLATES, wnba: WNBA_SLATES } },
    { id: 'playoff-odds', section: 'season-and-playoff-simulations', sources: {
      nfl: { file: 'standings_projections.json', fields: ['teams[].team_name', 'teams[].playoff_prob'],
        extract: function (d, L) { return simsText(closestToEven(arr(d && d.teams), 'playoff_prob'), 'playoff_prob', L); } },
      nba: BB_TEAMS, wnba: BB_TEAMS, mlb: BB_TEAMS } },
    { id: 'player-projection', section: 'player-projections', sources: { nba: BB_PLAYERS, wnba: BB_PLAYERS } },
    { id: 'similar-players', section: 'player-dna-and-similar-players', sources: { nfl: DNA, nba: DNA, wnba: WNBA_DNA, mlb: DNA } },
    { id: 'clutch', section: 'clutch', sources: {
      nfl: { file: 'clutch_leverage_metrics.json',
        fields: ['[].playerName', '[].clutchAttempts', '[].minClutchAttempts', '[].clutchSuccessRate', '[].baselineSuccessRate'],
        extract: function (d, L) {
          var p = maxBy(arr(d).filter(function (r) {
            return r && str(r.playerName) && num(r.clutchAttempts) && num(r.minClutchAttempts) && r.clutchAttempts >= r.minClutchAttempts &&
              num(r.clutchSuccessRate) && num(r.baselineSuccessRate);
          }), 'clutchAttempts');
          return p ? p.playerName + ' has ' + p.clutchAttempts + ' clutch attempts this ' + L + ' season, with a success rate of ' +
            fixed(p.clutchSuccessRate, 1) + '% in those moments against ' + fixed(p.baselineSuccessRate, 1) + '% overall.' : null;
        } },
      nba: BB_CLUTCH, wnba: WNBA_CLUTCH } },
    { id: 'versatility', section: 'defense-and-versatility-nba-wnba', sources: { nba: BB_DEF, wnba: WNBA_DEF } },
    { id: 'accuracy', section: 'how-accuracy-is-measured', sources: {
      nfl: { file: 'model_diagnostics.json', fields: ['n_games_graded', 'overall_brier'],
        extract: function (d, L) { return d ? diagnostics(last(d.n_games_graded), last(d.overall_brier), L) : null; } },
      nba: BB_DIAG, wnba: BB_DIAG, mlb: BB_DIAG } },
    { id: 'nfl-win-probability-method', section: 'appendix-formulas', sources: {
      nfl: { file: 'matchups_current_week.json', fields: NFL_WEEK_FIELDS.concat(['matchups[].projected_margin']),
        extract: function (d, L) {
          var g = nextGame(arr(d && d.matchups).filter(function (m) { return m && num(m.projected_margin); }), 'gameday', 'home_win_prob');
          return g ? 'For ' + g.away_team_name + ' at ' + g.home_team_name + ', the next ' + L + ' game on the schedule, a projected home margin of ' +
            fixed(g.projected_margin, 1) + ' points becomes a home win probability of ' + pct(g.home_win_prob) + '.' : null;
        } } } }
  ];

  var ORDER = ['nfl', 'nba', 'wnba', 'mlb'];

  // Does a league qualify for this source? bundle = { digest, manifest, data } (any may be missing).
  function qualifies(src, bundle) {
    if (!bundle || !bundle.digest || !bundle.manifest) return false;
    if (bundle.digest.season_state === 'offseason') return false;
    return Staleness.usable(bundle.manifest, src.file);
  }

  // First league whose data qualifies and yields text: { league, text } or null.
  // bundles[league] = { digest, manifest, data: { <file>: payload } }.
  function pick(example, bundles) {
    for (var i = 0; i < ORDER.length; i++) {
      var lg = ORDER[i], src = example.sources[lg], b = bundles[lg];
      if (!src || !qualifies(src, b)) continue;
      var payload = b.data ? b.data[src.file] : undefined;
      if (payload === undefined || payload === null) continue;
      var text = null;
      try { text = src.extract(payload, LABEL[lg]); } catch (e) { text = null; }
      if (str(text)) return { league: lg, text: text };
    }
    return null;
  }

  // Does a field path ('a[].b', '[].c', 'd') resolve to at least one present, non-null value?
  function hasField(obj, path) {
    var parts = path.split('.');
    var cur = [obj];
    for (var i = 0; i < parts.length; i++) {
      var part = parts[i], isArr = /\[\]$/.test(part), key = part.replace(/\[\]$/, '');
      var next = [];
      cur.forEach(function (o) {
        var v = key ? (o && typeof o === 'object' ? o[key] : undefined) : o;
        if (isArr) { if (Array.isArray(v)) next = next.concat(v); }
        else if (v !== undefined && v !== null) next.push(v);
      });
      cur = next;
      if (!cur.length) return false;
    }
    return true;
  }

  var api = { EXAMPLES: EXAMPLES, ORDER: ORDER, LABEL: LABEL, pick: pick, qualifies: qualifies, hasField: hasField };
  root.FOExamples = api;
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
  if (typeof document === 'undefined') return;

  // ---- DOM ------------------------------------------------------------------
  function getJson(sport, file) {
    var u = new URL('../' + sport + '/data/' + file, document.baseURI).href;
    return fetch(u, { cache: 'no-cache' }).then(function (r) {
      if (!r.ok) throw new Error(r.status);
      return r.json();
    }).catch(function () { return null; });
  }

  function load() {
    var bundles = {};
    var jobs = ORDER.map(function (lg) {
      var files = {};
      EXAMPLES.forEach(function (ex) { if (ex.sources[lg]) files[ex.sources[lg].file] = true; });
      return Promise.all([getJson(lg, 'landing_digest.json'), getJson(lg, 'data_manifest.json')]).then(function (dm) {
        var b = { digest: dm[0], manifest: dm[1], data: {} };
        bundles[lg] = b;
        // Only fetch payloads a qualifying league could use.
        var wanted = Object.keys(files).filter(function (f) {
          return EXAMPLES.some(function (ex) { var s = ex.sources[lg]; return s && s.file === f && qualifies(s, b); });
        });
        return Promise.all(wanted.map(function (f) {
          return getJson(lg, f).then(function (j) { b.data[f] = j; });
        }));
      });
    });
    return Promise.all(jobs).then(function () { return bundles; });
  }

  function render(bundles) {
    EXAMPLES.forEach(function (ex) {
      var slot = document.querySelector('[data-example="' + ex.id + '"]');
      if (!slot) return;
      var hit = pick(ex, bundles);
      if (!hit) { slot.hidden = true; slot.textContent = ''; return; }
      slot.textContent = '';
      var label = document.createElement('span');
      label.className = 'fo-example__label';
      label.textContent = 'Live example · ' + LABEL[hit.league];
      var body = document.createElement('span');
      body.className = 'fo-example__text';
      body.textContent = hit.text;
      slot.appendChild(label);
      slot.appendChild(document.createTextNode(' '));
      slot.appendChild(body);
      slot.setAttribute('data-league', hit.league);
      slot.hidden = false;
    });
  }

  load().then(render);
})(typeof window !== 'undefined' ? window : globalThis);
