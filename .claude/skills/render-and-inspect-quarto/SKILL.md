---
name: render-and-inspect-quarto
description: Renders a .qmd/.Rmd file and visually inspects the actual output pages (not just the exit code) for rendering defects like unevaluated inline expressions, broken citations, or mis-numbered sections. Use after creating or editing any .qmd/.Rmd file, before reporting the document as finished.
---

# Render and Inspect Quarto/R Markdown Output

## Why this exists

`docs/WNBA_Pipeline_Manuscript.qmd` rendered successfully (exit 0, valid PDF, correct TOC,
correctly resolved citations) but still had a real defect: the title page showed literal text
"Invalid Date" instead of a date, because `` date: "`r Sys.Date()`" `` only evaluates under a
knitr/R engine, and that document had no R code chunks to trigger one. Pandoc passed the string
through unevaluated and the PDF title-block template choked on it. A successful render exit code
says nothing about this class of defect — only actually looking at the rendered pages does.

## When to use

- After creating or substantively editing any `.qmd` or `.Rmd` file.
- Before telling the user a document is "done" or "ready" — rendering without inspection is not
  sufficient evidence of that claim.
- After changing a document's YAML frontmatter (date, bibliography, format options), since that's
  exactly where this class of bug tends to hide.

## Environment note

`quarto` is **not on PATH** on this machine — there is no bare `quarto` executable resolvable from
a shell. The real binary is bundled with RStudio at
`C:\Program Files\RStudio\resources\app\bin\quarto\bin\quarto.exe`. Invoke it via its full path
(quote it, since the path contains spaces), the same way CLAUDE.md documents doing for
`Rscript.exe`. Do not assume a bare `quarto render ...` command will resolve.

## Procedure

1. Determine the render command:
   - If a `_quarto.yml` project file exists, or the target is a bare `.qmd`, use
     `"C:\Program Files\RStudio\resources\app\bin\quarto\bin\quarto.exe" render <path>`.
   - If it's an `.Rmd` with no adjacent `.qmd` tooling, use
     `Rscript.exe -e` is disallowed on this machine (segfaults on inline multi-line `-e`; per
     CLAUDE.md, write any render call to a temp `.R` file first) —
     e.g. write `rmarkdown::render("path/to/file.Rmd")` to a temp `.R` file and run it with
     `C:\Program Files\R\R-4.5.2\bin\Rscript.exe`.
2. Check the exit code, but treat exit 0 as necessary, not sufficient.
3. If the output is a PDF, use the `Read` tool's PDF page-range support to actually view:
   - Page 1 (title block): confirm the title, author, and date all rendered as real values, not
     literal unevaluated template syntax (`` `r ...` ``, `Invalid Date`, `NA`, empty fields).
   - The table of contents page: confirm section numbers are sequential and match the headers
     that follow.
   - Any page containing a citation (`[@key]` in source): confirm it rendered as
     `(Author Year)`-style text, not a literal `?@key` or `[@key]` fallback, which indicates an
     unresolved bibliography key.
   - The references/bibliography page (if present): confirm entries appear at all — an empty
     references section with citations present in the body indicates a missing or misconfigured
     `bibliography:` field.
   - Skim remaining pages for obviously broken layout (truncated tables, overlapping text,
     empty figure placeholders) rather than reading every page in full.
4. If the output is HTML, the equivalent check is loading it (e.g. via a headless browser per
   CLAUDE.md's `shinytest2`/`chromote` pattern, or simply reading the rendered HTML source for the
   same failure signatures) rather than only checking that a `.html` file exists.
5. Report specifically what was inspected and what was found — "rendered clean, verified title
   block/TOC/citations across N pages" or "found X on page Y, fixed by Z, re-rendered and
   reverified."

## Known failure signatures to check for specifically

- `` `r ... ` `` or other unevaluated inline-code syntax appearing literally in output text.
- `Invalid Date`, `NA`, or an empty string where a date/author field should be.
- `?@key` or a raw `[@key]` where a citation should be.
- A `References`/`Bibliography` heading with no entries below it.
- Section numbers in the TOC that don't match the numbers on the actual section headers (usually
  indicates a `number-sections` / heading-level mismatch, not a fatal error but worth flagging).

## Limitations to disclose

- This is a manual visual-inspection loop, not an automated regression check — it doesn't scale
  to very long documents beyond skimming key pages, and it must be re-run after every substantive
  edit rather than once per document's lifetime.
- It cannot catch semantic/factual errors in the prose (e.g. a wrong number carried over from a
  source report) — pair with independent fact-checking of any figures, per the caveats already
  attached to `deep-review-to-manuscript` output.
