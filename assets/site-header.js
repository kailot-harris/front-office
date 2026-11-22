/*
 * Shared site header behaviour (front-office#218).
 *
 * Sharing approach: the header MARKUP is copied by hand into index.html, guide/index.html and
 * how-it-works/index.html (so it works and is crawlable without JavaScript), and
 * tools/check_site_header_drift.mjs fails CI if the three copies differ in anything other than
 * which link carries aria-current="page". This script only adds the narrow-screen Menu
 * disclosure: aria-expanded, focus into the list on open and back to the button on close,
 * Esc to close. Without JavaScript the full list simply stays visible.
 */
(function () {
  'use strict';
  var header = document.querySelector('[data-site-header]');
  if (!header) return;
  var btn = header.querySelector('.site-header__toggle');
  var list = header.querySelector('.site-header__list');
  if (!btn || !list) return;
  header.classList.add('js-menu');
  btn.hidden = false;

  function setOpen(open, returnFocus) {
    header.classList.toggle('is-open', open);
    btn.setAttribute('aria-expanded', open ? 'true' : 'false');
    if (open) {
      var first = list.querySelector('a');
      if (first) first.focus();
    } else if (returnFocus) {
      btn.focus();
    }
  }

  btn.addEventListener('click', function () {
    setOpen(btn.getAttribute('aria-expanded') !== 'true', true);
  });
  header.addEventListener('keydown', function (e) {
    if ((e.key === 'Escape' || e.key === 'Esc') && btn.getAttribute('aria-expanded') === 'true') {
      e.preventDefault();
      setOpen(false, true);
    }
  });
  // Close (without stealing focus) when focus leaves the header.
  header.addEventListener('focusout', function (e) {
    if (btn.getAttribute('aria-expanded') === 'true' && e.relatedTarget && !header.contains(e.relatedTarget)) {
      setOpen(false, false);
    }
  });
})();
