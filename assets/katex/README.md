# KaTeX (self-hosted)

- Version: **0.16.11**
- Source: https://registry.npmjs.org/katex/-/katex-0.16.11.tgz (official npm tarball), files from `package/dist/`
- Copied: `katex.min.css`, `katex.min.js`, `contrib/auto-render.min.js`, `fonts/*.woff2`
- Only the woff2 fonts are kept. `katex.min.css` lists woff2 first in every `@font-face`, so
  browsers load it and never request the missing woff/ttf fallbacks.
- License: MIT (KaTeX). Used by `how-it-works/index.html` for the formula appendix (front-office#218).

Updating is a manual job: download the new tarball, replace these files, and update the version here.
