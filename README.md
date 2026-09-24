# WNBA_analytics
Analyzing WNBA games and players to deliver game-level predictions.

## Setup

1. **Clone and open the repo.** Clone this repository and open/run everything from inside the
   cloned folder (e.g. open the folder in RStudio, or start an R session with the repo as your
   working directory). `config.R` derives `PROJECT_DIR` automatically via `here::here()`, which
   locates the project root from the nearest `.git` directory — there is no path to edit
   manually, on any machine.
2. **Install R.** If you don't already have R installed, install it from
   [CRAN](https://cran.r-project.org/). R/`Rscript` may not be on your system `PATH`; rather than
   relying on a bare `R`/`Rscript` command, run scripts via RStudio's "Run"/"Knit" buttons, or
   invoke your R installation's `Rscript` executable directly (e.g.
   `"C:\Program Files\R\R-4.5.2\bin\Rscript.exe"` on Windows).

## Installing dependencies

This project pins its exact package versions with [`renv`](https://rstudio.github.io/renv/)
(`renv.lock`, `.Rprofile`). After cloning, open an R session in the project directory and run:

```r
renv::restore()
```

This bootstraps `renv` itself automatically on first R startup in the project (via `.Rprofile`),
then installs the exact package versions recorded in `renv.lock` — including `tidyverse`,
`tidymodels`, `wehoop`, `slider`, `xgboost`, and `ggridges`. No separate manual
`install.packages()` step is needed.

## Running the analysis

The main deliverable is `WNBA_Analysis_Project.Rmd`. Render it to PDF with:

```r
rmarkdown::render("WNBA_Analysis_Project.Rmd")
```

(or use RStudio's "Knit" button). PDF output requires a working TeX toolchain — if you don't
already have one installed, run `tinytex::install_tinytex()` first.

The Rmd expects a cached box-score data file at `data/box_scores_cache.rds` (referenced via
`CACHE_TEAM_BOX` in `config.R`). If that cache is present, it's loaded directly; if it's missing,
the Rmd automatically falls back to a live `wehoop::load_wnba_team_box()` pull from the WNBA
stats API and writes the cache for next time — so a missing cache isn't a hard blocker, but note
that a live pull will be slower and depends on the API being reachable.
