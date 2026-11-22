/*
 * Landing-page daily digest (front-office#202-#204, epic #200).
 * Reads each sport's web/public/data/landing_digest.json and data_manifest.json, published at
 * /front-office/<sport>/data/. URLs resolve against document.baseURI so they keep the
 * /front-office/ base path in production; there are no root-relative paths.
 * Pure helpers are exported on window.FODigest (and module.exports) for tests.
 */
(function (root) {
  'use strict';

  var SPORTS = ['nfl', 'nba', 'wnba', 'mlb'];
  var LABEL = { nfl: 'NFL', nba: 'NBA', wnba: 'WNBA', mlb: 'MLB' };
  var STATE_LABEL = {
    regular: 'In-Season',
    postseason: 'Postseason',
    preseason: 'Preseason',
    offseason: 'Off-Season'
  };
  var WINDOWS = ['1', '7', '21'];

  // ---- pure helpers -------------------------------------------------------
  function easternDate(now) {
    // en-CA formats as YYYY-MM-DD.
    return new Intl.DateTimeFormat('en-CA', { timeZone: 'America/New_York' }).format(now || new Date());
  }

  function isStale(digest, now) {
    return !!digest && digest.slate_date !== easternDate(now);
  }

  function formatDate(iso) {
    if (!iso) return '';
    var d = new Date(iso + 'T12:00:00Z');
    return d.toLocaleDateString('en-US', { month: 'short', day: 'numeric', timeZone: 'UTC' });
  }

  function formatStart(utc) {
    if (!utc) return 'Time TBD';
    var d = new Date(utc);
    if (isNaN(d)) return 'Time TBD';
    return d.toLocaleTimeString([], { hour: 'numeric', minute: '2-digit', timeZoneName: 'short' });
  }

  function pct(p) {
    return Math.round(p * 100) + '%';
  }

  // The favored side and its probability, or null when there is no prediction.
  function favorite(game) {
    var h = game.home_win_prob, a = game.away_win_prob;
    if (typeof h !== 'number' || typeof a !== 'number') return null;
    return h >= a ? { team: game.home, p: h } : { team: game.away, p: a };
  }

  function predictionText(game) {
    var fav = favorite(game);
    if (fav) return fav.team + ' ' + pct(fav.p);
    if (game.prediction_status === 'no_model') return 'No model prediction';
    return 'Prediction pending';
  }

  function hitText(game) {
    if (game.hit === true) return 'Hit';
    if (game.hit === false) return 'Miss';
    var s = String(game.status || '').toLowerCase();
    if (s.indexOf('postpon') !== -1) return 'Postponed';
    if (s.indexOf('cancel') !== -1) return 'Cancelled';
    if (!game.final) return 'Not final';
    return 'Not graded';
  }

  function recordText(record) {
    if (!record || !record.season || !record.season.games) return '';
    var s = record.season, l = record.last_7 || { hits: 0, games: 0, excluded: 0 };
    var parts = ['Model: ' + s.hits + '–' + (s.games - s.hits) + ' season'];
    if (l.games) parts.push(l.hits + '–' + (l.games - l.hits) + ' last 7 days');
    var ex = (s.excluded || 0);
    if (ex) parts.push(ex + ' excluded');
    return parts.join(' · ');
  }

  // First sport (in page order) that is not in the off-season; else the first sport loaded.
  function defaultSport(digests) {
    var loaded = SPORTS.filter(function (s) { return digests[s]; });
    for (var i = 0; i < loaded.length; i++) {
      if (digests[loaded[i]].season_state !== 'offseason') return loaded[i];
    }
    return loaded[0] || null;
  }

  // Freshness summary from a sport's data_manifest.json. The staleness rule itself lives in
  // assets/landing/staleness.js, shared with the guide pages' live examples (front-office#218).
  var Staleness = root.FOStaleness ||
    (typeof require === 'function' ? require('./staleness.js') : null);
  function freshness(manifest) {
    return Staleness.freshness(manifest);
  }

  var api = {
    SPORTS: SPORTS, easternDate: easternDate, isStale: isStale, formatStart: formatStart,
    favorite: favorite, predictionText: predictionText, hitText: hitText, recordText: recordText,
    defaultSport: defaultSport, freshness: freshness
  };
  root.FODigest = api;
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
  if (typeof document === 'undefined') return;

  // ---- DOM ------------------------------------------------------------------
  function el(tag, attrs, children) {
    var n = document.createElement(tag);
    Object.keys(attrs || {}).forEach(function (k) {
      if (k === 'text') n.textContent = attrs[k];
      else if (k === 'className') n.className = attrs[k];
      else n.setAttribute(k, attrs[k]);
    });
    (children || []).forEach(function (c) { if (c) n.appendChild(c); });
    return n;
  }

  function url(sport, file) {
    return new URL(sport + '/data/' + file, document.baseURI).href;
  }

  function getJson(u) {
    return fetch(u, { cache: 'no-cache' }).then(function (r) {
      if (!r.ok) throw new Error(r.status);
      return r.json();
    });
  }

  var state = { digests: {}, manifests: {}, failed: {}, sport: null, window: '7' };

  function sportHeading(sport, digest, level) {
    var h = el(level, { className: 'dg-sport', 'data-sport': sport }, [
      el('span', { className: 'sport-pip', 'aria-hidden': 'true' }),
      el('span', { text: LABEL[sport] })
    ]);
    if (digest && isStale(digest)) {
      h.appendChild(el('span', { className: 'dg-stale', text: 'Data as of ' + formatDate(digest.slate_date) }));
    }
    return h;
  }

  function gameRow(primary, secondary, right, rightClass) {
    return el('li', { className: 'dg-row' }, [
      el('span', { className: 'dg-game' }, [
        el('span', { text: primary }),
        el('span', { className: 'dg-sub', text: secondary })
      ]),
      el('span', { className: 'dg-right ' + (rightClass || ''), text: right })
    ]);
  }

  function renderToday() {
    var box = document.getElementById('dg-today-body');
    box.textContent = '';
    SPORTS.forEach(function (s) {
      var d = state.digests[s];
      if (!d) { if (state.failed[s]) box.appendChild(failedNote(s)); return; }
      var group = el('div', { className: 'dg-group' }, [sportHeading(s, d, 'h4')]);
      if (d.today && d.today.length) {
        var ul = el('ul', { className: 'dg-list' });
        d.today.forEach(function (g) {
          ul.appendChild(gameRow(g.away + ' at ' + g.home, formatStart(g.start_time_utc), predictionText(g),
            favorite(g) ? '' : 'dg-muted'));
        });
        group.appendChild(ul);
      } else {
        var line = d.season_state === 'offseason' ? 'Off-season' : 'No games today';
        if (d.next_milestone && d.next_milestone.label) {
          line += '. Next: ' + d.next_milestone.label +
            (d.next_milestone.date ? ' ' + formatDate(d.next_milestone.date) : '');
        }
        group.appendChild(el('p', { className: 'dg-muted dg-line', text: line }));
      }
      box.appendChild(group);
    });
  }

  function renderYesterday() {
    var box = document.getElementById('dg-yesterday-body');
    box.textContent = '';
    SPORTS.forEach(function (s) {
      var d = state.digests[s];
      if (!d) return;
      var games = d.yesterday || [];
      var rec = recordText(d.record);
      if (!games.length && !rec) return;
      var group = el('div', { className: 'dg-group' }, [sportHeading(s, d, 'h4')]);
      if (games.length) {
        var ul = el('ul', { className: 'dg-list' });
        games.forEach(function (g) {
          var score = typeof g.home_score === 'number'
            ? g.away + ' ' + g.away_score + ', ' + g.home + ' ' + g.home_score
            : g.away + ' at ' + g.home;
          var fav = favorite(g);
          var sub = fav ? 'Model: ' + fav.team + ' ' + pct(fav.p) : predictionText(g);
          var h = hitText(g);
          ul.appendChild(gameRow(score, sub, h, g.hit === true ? 'dg-hit' : g.hit === false ? 'dg-miss' : 'dg-muted'));
        });
        group.appendChild(ul);
      } else {
        group.appendChild(el('p', { className: 'dg-muted dg-line', text: 'No games yesterday' }));
      }
      if (rec) group.appendChild(el('p', { className: 'dg-record', text: rec }));
      box.appendChild(group);
    });
    if (!box.childNodes.length) box.appendChild(el('p', { className: 'dg-muted', text: 'No results yesterday.' }));
  }

  function failedNote(s) {
    return el('p', { className: 'dg-muted dg-line', text: LABEL[s] + ': today’s data couldn’t be loaded.' });
  }

  function renderFreshness() {
    var ul = document.getElementById('dg-fresh');
    ul.textContent = '';
    SPORTS.forEach(function (s) {
      var f = freshness(state.manifests[s]);
      var text, cls = 'dg-chip';
      if (state.failed[s] && !f) { text = LABEL[s] + ' data unavailable'; cls += ' dg-chip-warn'; }
      else if (!f) return;
      else {
        text = LABEL[s] + (f.through ? ' data through ' + formatDate(f.through) : ' no dated data');
        if (f.stale) { text += ' · ' + f.stale + ' stale'; cls += ' dg-chip-warn'; }
        if (f.undated) text += ' · ' + f.undated + ' undated';
      }
      ul.appendChild(el('li', { className: cls, 'data-sport': s, text: text }));
    });
  }

  function renderBadges() {
    SPORTS.forEach(function (s) {
      var badge = document.querySelector('.card[data-sport="' + s + '"] .card-badge');
      var d = state.digests[s];
      if (!badge) return;
      badge.textContent = d && STATE_LABEL[d.season_state] ? STATE_LABEL[d.season_state] : 'Season status unavailable';
    });
  }

  function tabs(container, items, selected, onSelect, label) {
    container.textContent = '';
    container.setAttribute('role', 'tablist');
    container.setAttribute('aria-label', label);
    var buttons = items.map(function (it) {
      var b = el('button', {
        type: 'button', role: 'tab', id: container.id + '-' + it.value,
        'aria-selected': it.value === selected ? 'true' : 'false',
        'aria-controls': container.getAttribute('data-controls'),
        className: 'dg-tab', text: it.label
      });
      if (it.value !== selected) b.setAttribute('tabindex', '-1');
      b.addEventListener('click', function () { onSelect(it.value, false); });
      container.appendChild(b);
      return b;
    });
    container.onkeydown = function (e) {
      var i = buttons.indexOf(document.activeElement);
      if (i === -1) return;
      var step = { ArrowRight: 1, ArrowDown: 1, ArrowLeft: -1, ArrowUp: -1 }[e.key];
      var next = step ? (i + step + buttons.length) % buttons.length
        : e.key === 'Home' ? 0 : e.key === 'End' ? buttons.length - 1 : -1;
      if (next === -1) return;
      e.preventDefault();
      onSelect(items[next].value, true);
    };
  }

  function renderInsights(focusId) {
    var avail = SPORTS.filter(function (s) { return state.digests[s]; });
    var picker = document.getElementById('dg-picker');
    if (!avail.length) { document.getElementById('dg-insights').hidden = true; return; }
    tabs(picker, avail.map(function (s) { return { value: s, label: LABEL[s] }; }), state.sport,
      function (v, focus) { state.sport = v; renderInsights(focus ? picker.id + '-' + v : null); }, 'Choose a league');
    var panel = document.getElementById('dg-insights-panel');
    panel.setAttribute('aria-labelledby', picker.id + '-' + state.sport);
    renderCalibration(state.digests[state.sport]);
    renderMovers(state.digests[state.sport], focusId);
    if (focusId) document.getElementById(focusId).focus();
  }

  function renderCalibration(d) {
    var box = document.getElementById('dg-cal');
    box.textContent = '';
    var buckets = (d.calibration || []).filter(function (b) { return b && typeof b.lo === 'number'; });
    var rec = recordText(d.record);
    if (rec) box.appendChild(el('p', { className: 'dg-record', text: rec }));
    if (!buckets.length) { box.appendChild(el('p', { className: 'dg-muted', text: 'No graded predictions yet.' })); return; }
    var chart = el('div', { className: 'dg-cal', 'aria-hidden': 'true' });
    var table = el('table', { className: 'fo-sr-only' }, [
      el('caption', { text: LABEL[state.sport] + ' model calibration: predicted versus actual win rate by confidence bucket' }),
      el('thead', {}, [el('tr', {}, ['Model said', 'Predicted', 'Actual', 'Games'].map(function (h) {
        return el('th', { scope: 'col', text: h });
      }))])
    ]);
    var tbody = el('tbody');
    buckets.forEach(function (b) {
      var name = Math.round(b.lo * (b.lo <= 1 ? 100 : 1)) + '–' + Math.round(b.hi * (b.hi <= 1 ? 100 : 1)) + '%';
      var enough = b.games >= 20 && typeof b.actual_rate === 'number';
      var row = el('div', { className: 'dg-cal-row' }, [
        el('span', { className: 'dg-cal-label', text: name }),
        el('span', { className: 'dg-cal-track' }, enough ? [
          el('span', { className: 'dg-cal-bar', style: 'width:' + Math.round(b.actual_rate * 100) + '%' }),
          typeof b.predicted_mean === 'number'
            ? el('span', { className: 'dg-cal-tick', style: 'left:' + Math.round(b.predicted_mean * 100) + '%' }) : null
        ] : []),
        el('span', { className: 'dg-cal-val', text: enough ? pct(b.actual_rate) + ' · ' + b.games : 'Not enough games yet' })
      ]);
      chart.appendChild(row);
      tbody.appendChild(el('tr', {}, [
        el('th', { scope: 'row', text: name }),
        el('td', { text: typeof b.predicted_mean === 'number' ? pct(b.predicted_mean) : 'n/a' }),
        el('td', { text: enough ? pct(b.actual_rate) : 'not enough games' }),
        el('td', { text: String(b.games || 0) })
      ]));
    });
    table.appendChild(tbody);
    box.appendChild(chart);
    box.appendChild(el('p', { className: 'dg-note', 'aria-hidden': 'true', text: 'Bar: actual win rate. Tick: what the model said.' }));
    box.appendChild(table);
  }

  function renderMovers(d, focusId) {
    var wbar = document.getElementById('dg-window');
    tabs(wbar, WINDOWS.map(function (w) { return { value: w, label: w + 'd' }; }), state.window,
      function (v, focus) { state.window = v; renderMovers(state.digests[state.sport], focus ? wbar.id + '-' + v : null); },
      'Rating change window');
    if (focusId && focusId.indexOf(wbar.id) === 0) document.getElementById(focusId).focus();
    var box = document.getElementById('dg-movers');
    box.textContent = '';
    var mv = d.movers || {};
    var w = (mv.windows || {})[state.window] || {};
    var metric = mv.metric ? String(mv.metric).replace(/_/g, ' ') : 'rating';
    document.getElementById('dg-movers-metric').textContent = LABEL[state.sport] + ' · ' + metric;
    var items = w.items || [];
    if (!items.length) {
      box.appendChild(el('p', { className: 'dg-muted', text: w.compared_to
        ? 'No rating changes since ' + formatDate(w.compared_to) + '.'
        : 'Not enough rating history yet.' }));
      return;
    }
    var ul = el('ul', { className: 'dg-list' });
    items.forEach(function (it) {
      var delta = Number(it.delta);
      ul.appendChild(el('li', { className: 'dg-row' }, [
        el('span', { text: it.team }),
        el('span', { className: 'dg-right ' + (delta > 0 ? 'dg-hit' : delta < 0 ? 'dg-miss' : ''),
          text: (delta > 0 ? '+' : delta < 0 ? '−' : '') + Math.abs(delta).toFixed(1) })
      ]));
    });
    box.appendChild(ul);
    if (w.compared_to) box.appendChild(el('p', { className: 'dg-note', text: 'vs ' + formatDate(w.compared_to) }));
  }

  function renderAll() {
    renderFreshness();
    renderBadges();
    renderToday();
    renderYesterday();
    if (!state.sport) state.sport = defaultSport(state.digests);
    renderInsights(null);
  }

  function load() {
    var status = document.getElementById('dg-status');
    var jobs = [];
    SPORTS.forEach(function (s) {
      jobs.push(getJson(url(s, 'landing_digest.json'))
        .then(function (j) { state.digests[s] = j; })
        .catch(function () { state.failed[s] = true; }));
      jobs.push(getJson(url(s, 'data_manifest.json'))
        .then(function (j) { state.manifests[s] = j; })
        .catch(function () {}));
    });
    Promise.all(jobs).then(function () {
      document.getElementById('digest').removeAttribute('aria-busy');
      renderAll();
      var n = Object.keys(state.digests).length;
      status.textContent = n
        ? 'Daily digest loaded for ' + n + ' of 4 leagues.'
        : 'The daily digest couldn’t be loaded. Try again later.';
    });
  }

  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', load);
  else load();
})(typeof window !== 'undefined' ? window : globalThis);
