/*
 * Landing-page "This week's visuals" slideshow (front-office#210).
 * Reads each sport's landing_digest.json (season_state) and visual_media_index.json, published at
 * /front-office/<sport>/data/. Shows GIFs built in the last 7 days for sports not in the off-season,
 * in random order. A sport whose files are missing contributes nothing; with no slides the section
 * stays hidden. URLs are relative and resolve against document.baseURI.
 * Pure helpers are exported on window.FOGifs (and module.exports) for tests.
 */
(function (root) {
  'use strict';

  var SPORTS = ['nfl', 'nba', 'wnba', 'mlb'];
  var LABEL = { nfl: 'NFL', nba: 'NBA', wnba: 'WNBA', mlb: 'MLB' };
  var WEEK_MS = 7 * 86400000;
  var DEFAULT_DELAY = 10000;

  // ---- pure helpers -------------------------------------------------------
  // Same rule the daily digest uses for an active sport.
  function isActive(digest) {
    return !!digest && digest.season_state !== 'offseason';
  }

  // generated_at ("%Y-%m-%dT%H:%M:%SZ") is within the last 7 days and not in the future.
  function isFresh(generatedAt, now) {
    if (typeof generatedAt !== 'string') return false;
    var t = Date.parse(generatedAt);
    if (isNaN(t)) return false;
    var age = (now || new Date()).getTime() - t;
    return age >= 0 && age <= WEEK_MS;
  }

  function mediaUrl(sport, filename) {
    return sport + '/' + (sport === 'nfl' ? 'animations' : 'media') + '/' + filename;
  }

  function stillFor(sport, item, index) {
    if (item.previewPng) return mediaUrl(sport, item.previewPng);
    var png = String(item.filename).replace(/\.gif$/i, '.png');
    for (var i = 0; i < index.length; i++) {
      if (index[i] && index[i].filename === png) return mediaUrl(sport, png);
    }
    return null;
  }

  function selectSlides(digests, indexes, now) {
    var out = [];
    SPORTS.forEach(function (sport) {
      var index = indexes && indexes[sport];
      if (!isActive(digests && digests[sport]) || !Array.isArray(index)) return;
      index.forEach(function (item) {
        if (!item || item.type !== 'gif' || !item.filename || !isFresh(item.generated_at, now)) return;
        out.push({
          sport: sport,
          src: mediaUrl(sport, item.filename),
          still: stillFor(sport, item, index),
          href: sport + '/gallery/',
          title: item.title || item.filename,
          date: item.generated_at,
          durationMs: item.duration_ms
        });
      });
    });
    return out;
  }

  // Fisher-Yates on a copy.
  function shuffle(slides, rand) {
    var a = slides.slice();
    for (var i = a.length - 1; i > 0; i--) {
      var j = Math.floor(rand() * (i + 1));
      var t = a[i]; a[i] = a[j]; a[j] = t;
    }
    return a;
  }

  function slideDelay(slide) {
    var d = slide && slide.durationMs;
    return typeof d === 'number' && d > 0 && isFinite(d) ? d : DEFAULT_DELAY;
  }

  function formatDate(iso) {
    var d = new Date(iso);
    if (isNaN(d)) return '';
    return d.toLocaleDateString('en-US', { month: 'short', day: 'numeric', timeZone: 'UTC' });
  }

  function caption(slide) {
    return LABEL[slide.sport] + ' · ' + slide.title + ' · ' + formatDate(slide.date);
  }

  var api = {
    SPORTS: SPORTS, isActive: isActive, isFresh: isFresh, mediaUrl: mediaUrl,
    selectSlides: selectSlides, shuffle: shuffle, slideDelay: slideDelay, caption: caption
  };
  root.FOGifs = api;
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
  if (typeof document === 'undefined') return;

  // ---- DOM ------------------------------------------------------------------
  function abs(rel) { return new URL(rel, document.baseURI).href; }

  function getJson(u) {
    return fetch(u, { cache: 'no-cache' }).then(function (r) {
      if (!r.ok) throw new Error(r.status);
      return r.json();
    }).catch(function () { return undefined; });
  }

  function el(tag, attrs) {
    var n = document.createElement(tag);
    Object.keys(attrs || {}).forEach(function (k) {
      if (k === 'text') n.textContent = attrs[k];
      else if (k === 'className') n.className = attrs[k];
      else n.setAttribute(k, attrs[k]);
    });
    return n;
  }

  function init() {
    var section = document.getElementById('gifs');
    if (!section) return;
    var files = [];
    SPORTS.forEach(function (s) {
      files.push(getJson(abs(s + '/data/landing_digest.json')));
      files.push(getJson(abs(s + '/data/visual_media_index.json')));
    });
    Promise.all(files).then(function (res) {
      var digests = {}, indexes = {};
      SPORTS.forEach(function (s, i) { digests[s] = res[2 * i]; indexes[s] = res[2 * i + 1]; });
      var slides = shuffle(selectSlides(digests, indexes, new Date()), Math.random);
      if (slides.length) start(section, slides);
    });
  }

  function start(section, slides) {
    var reduced = window.matchMedia && window.matchMedia('(prefers-reduced-motion: reduce)').matches;
    var state = { i: 0, playing: !reduced, timer: null };

    var link = section.querySelector('.gf-link');
    var frame = section.querySelector('.gf-frame');
    var cap = section.querySelector('.gf-caption');
    var pauseBtn = section.querySelector('.gf-pause');
    var nextBtn = section.querySelector('.gf-next');
    var live = section.querySelector('.gf-live');

    function hide() {
      clearTimeout(state.timer);
      section.hidden = true;
    }

    function schedule() {
      clearTimeout(state.timer);
      if (state.playing && slides.length > 1) state.timer = setTimeout(function () { go(1, false); }, slideDelay(slides[state.i]));
    }

    function preloadNext() {
      if (!state.playing || slides.length < 2) return;
      new Image().src = abs(slides[(state.i + 1) % slides.length].src);
    }

    function render() {
      var s = slides[state.i];
      link.href = abs(s.href);
      link.setAttribute('data-sport', s.sport);
      cap.textContent = caption(s);
      frame.textContent = '';
      var src = state.playing ? s.src : s.still;
      if (src) {
        var img = el('img', { className: 'gf-img', alt: s.title, src: abs(src), decoding: 'async' });
        img.onerror = function () {
          if (slides[state.i] !== s) return;
          if (src === s.still) { s.still = null; render(); return; }
          slides.splice(state.i, 1);
          if (!slides.length) return hide();
          state.i = state.i % slides.length;
          render();
        };
        frame.appendChild(img);
      } else {
        frame.appendChild(el('p', { className: 'gf-card', text: caption(s) }));
      }
      nextBtn.disabled = slides.length < 2;
      schedule();
      preloadNext();
    }

    function go(step, announce) {
      state.i = (state.i + step) % slides.length;
      render();
      live.textContent = announce ? 'Slide ' + (state.i + 1) + ' of ' + slides.length + ': ' + caption(slides[state.i]) : '';
    }

    function setPlaying(p) {
      state.playing = p;
      pauseBtn.textContent = p ? 'Pause' : 'Play';
      pauseBtn.setAttribute('aria-label', p ? 'Pause slideshow' : 'Play slideshow');
      render();
    }

    pauseBtn.addEventListener('click', function () { setPlaying(!state.playing); });
    nextBtn.addEventListener('click', function () { go(1, true); });

    section.hidden = false;
    setPlaying(state.playing);
  }

  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', init);
  else init();
})(typeof window !== 'undefined' ? window : this);
