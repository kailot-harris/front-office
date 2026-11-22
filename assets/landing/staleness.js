/*
 * The one staleness definition for the landing page and the guide pages (front-office#218).
 * Reads a sport's data_manifest.json (published at /front-office/<sport>/data/). A dataset is:
 *   'static'  - marked static in the manifest; never stale.
 *   'undated' - no game-dated through_date (through_date_source 'not_game_dated' or missing);
 *               the landing freshness strip counts these but does not flag them.
 *   'stale'   - its through_date trails the manifest's schedule_through_date by more than
 *               its max_lag_days; the landing strip flags these.
 *   'fresh'   - anything else that is dated.
 *   'missing' - not listed in the manifest (or no manifest at all).
 * datasets may be an object keyed by file name or an array of { file, ... } rows.
 * Loaded before assets/landing/digest.js and assets/guide/examples.js; exported on
 * window.FOStaleness (and module.exports) for tests.
 */
(function (root) {
  'use strict';

  function daysBetween(a, b) {
    return Math.round((Date.parse(a + 'T00:00:00Z') - Date.parse(b + 'T00:00:00Z')) / 86400000);
  }

  function classify(d, sched) {
    if (d.through_date_source === 'not_game_dated' || !d.through_date) return d.static ? 'static' : 'undated';
    if (!d.static && sched && typeof d.max_lag_days === 'number' &&
        daysBetween(sched, d.through_date) > d.max_lag_days) return 'stale';
    return d.static ? 'static' : 'fresh';
  }

  function findDataset(manifest, file) {
    if (!manifest || !manifest.datasets) return null;
    var ds = manifest.datasets;
    if (Array.isArray(ds)) {
      for (var i = 0; i < ds.length; i++) if (ds[i] && ds[i].file === file) return ds[i];
      return null;
    }
    return Object.prototype.hasOwnProperty.call(ds, file) ? ds[file] : null;
  }

  function datasetStatus(manifest, file) {
    var d = findDataset(manifest, file);
    return d ? classify(d, manifest.schedule_through_date) : 'missing';
  }

  // Freshness summary for the landing strip: latest through_date, stale and undated counts.
  function freshness(manifest) {
    if (!manifest || !manifest.datasets) return null;
    var through = null, stale = 0, undated = 0;
    var sched = manifest.schedule_through_date;
    Object.keys(manifest.datasets).forEach(function (name) {
      var d = manifest.datasets[name];
      var s = classify(d, sched);
      if (s === 'undated') { undated++; return; }
      if (d.through_date_source === 'not_game_dated' || !d.through_date) return;
      if (!through || d.through_date > through) through = d.through_date;
      if (s === 'stale') stale++;
    });
    return { through: through, stale: stale, undated: undated };
  }

  // True when the landing page would not flag this dataset (fresh, undated or static).
  function usable(manifest, file) {
    var s = datasetStatus(manifest, file);
    return s === 'fresh' || s === 'undated' || s === 'static';
  }

  var api = { daysBetween: daysBetween, datasetStatus: datasetStatus, freshness: freshness, usable: usable };
  root.FOStaleness = api;
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
})(typeof window !== 'undefined' ? window : globalThis);
