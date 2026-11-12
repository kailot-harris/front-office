# ==============================================================================
# tools/viz_common.R
# Path: tools/viz_common.R
#
# Ported from the NBA Analytics repo's tools/viz_common.R (GitHub issue #144,
# part of #140's gallery-chart epic), WNBA-themed. This is PHASE 1 (plumbing)
# only -- it defines the shared building blocks that gallery chart scripts
# (phases 2-4, tools/gif_*.R, tracked separately) will source. No chart lives
# here.
#
# Common WNBA visualization foundation:
#   - Theme: theme_wnba_dark(), same dark-UI palette as the NBA original
#     (#0b1120 bg, #111a2e panel, #22304a grid) so charts from both sports read
#     as one visual family on the site.
#   - Palette: WNBA_COLORS, WNBA_TEAM_COLORS (built from config.R's WNBA_TEAMS,
#     never a hardcoded second copy of the team list).
#   - Team color / abbreviation resolver: get_wnba_team_color(), resolve_team_abbr()
#   - Logo helpers: get_wnba_logo_url(), get_wnba_logo_path(), read_wnba_logo_grob()
#   - Animation encoder: render_animated_artifact() (GIF + static PNG final
#     frame for prefers-reduced-motion) -- byte-for-byte the same contract as
#     the NBA version, since the gallery test harness (tests/test_gallery_viz.R)
#     and viz_gallery_helpers.R::viz_render_frames() both depend on its exact
#     signature.
#   - VIZ_NO_DATA_MARKER / viz_stop_no_data(): the zero-fallback contract. A
#     gallery chart with no real data stops with nothing rendered -- it does
#     NOT fall back to a "clearly labeled synthetic value" the way CLAUDE.md's
#     general house rule asks every other script to. That house rule is
#     deliberately NOT followed here: issue #140/#144 require zero-synthetic
#     gallery charts, matching this repo's existing zero-betting /
#     zero-synthetic-data policy (the #142 Shiny retirement, etc).
#
# WHAT DIFFERS FROM THE NBA VERSION, AND WHY:
#   - No WNBA_CONFERENCE_COLORS / WNBA_DIVISION_COLORS. The WNBA has run a
#     single combined standings table (no conferences or divisions) since
#     2022 -- there is nothing for those two palettes to key off of, so they
#     are simply omitted rather than ported as dead code.
#   - WNBA_TEAM_COLORS is keyed off config.R's WNBA_TEAMS (15 teams, 2026
#     season) rather than a second hardcoded 30-team list, per this repo's
#     "every structural constant has one definition site" rule. If WNBA_TEAMS
#     gains/loses a franchise, this file's resolver functions follow
#     automatically; only the color/logo-slug lookup tables below need a new
#     entry.
#   - Team abbreviations are NOT uniformly 3 letters (GS, LA, LV, NY are 2).
#     resolve_team_abbr()/the nickname map below are built FROM WNBA_TEAMS's
#     actual keys, so this is handled by construction, not a hardcoded case.
# ==============================================================================

suppressPackageStartupMessages({
  library(ggplot2)
})

# config.R defines WNBA_TEAMS (the single source of truth for the 15-team
# league). Every script in this repo sources config.R before anything else;
# this file is sourced BY those scripts (tools/ scripts setwd() to the
# project root first, per CLAUDE.md), so WNBA_TEAMS should already exist. The
# guard below only protects ad hoc interactive use of this file alone.
if (!exists("WNBA_TEAMS", envir = .GlobalEnv)) {
  if (file.exists("config.R")) {
    source("config.R")
  } else {
    stop("tools/viz_common.R: WNBA_TEAMS is not defined and config.R is not on the working directory. Source config.R first.")
  }
}

# ------------------------------------------------------------------------------
# 1. Dark Theme for WNBA Visualizations
# ------------------------------------------------------------------------------
# Identical palette to the NBA original, consistent with the Next.js dark UI:
#   bg:       #0b1120
#   panel:    #111a2e
#   grid:     #22304a
#   text:     #e7ecf5
#   subtext:  #9fb0c9
#   border:   #1f2937
# ------------------------------------------------------------------------------
WNBA_COLORS <- list(
  bg       = "#0b1120",
  panel    = "#111a2e",
  grid     = "#22304a",
  border   = "#1f2937",
  text     = "#e7ecf5",
  subtext  = "#9fb0c9",
  accent   = "#3fd0c9",
  negative = "#ff6b57"
)

theme_wnba_dark <- function(base_size = 11, base_family = "") {
  theme_minimal(base_size = base_size, base_family = base_family) +
    theme(
      plot.background   = element_rect(fill = WNBA_COLORS$bg, color = NA),
      panel.background  = element_rect(fill = WNBA_COLORS$panel, color = NA),
      panel.border      = element_rect(color = WNBA_COLORS$border, fill = NA, linewidth = 0.5),
      panel.grid.major  = element_line(color = WNBA_COLORS$grid, linewidth = 0.35),
      panel.grid.minor  = element_blank(),
      legend.background = element_rect(fill = WNBA_COLORS$bg, color = NA),
      legend.key        = element_rect(fill = "transparent", color = NA),
      legend.text       = element_text(color = WNBA_COLORS$subtext, size = rel(0.85)),
      legend.title      = element_text(color = WNBA_COLORS$text, face = "bold", size = rel(0.9)),
      text              = element_text(color = WNBA_COLORS$text),
      plot.title        = element_text(color = WNBA_COLORS$text, face = "bold", size = rel(1.3), margin = margin(b = 5)),
      plot.subtitle     = element_text(color = WNBA_COLORS$subtext, size = rel(0.95), margin = margin(b = 10)),
      plot.caption      = element_text(color = WNBA_COLORS$subtext, size = rel(0.75), margin = margin(t = 10), hjust = 1),
      axis.title        = element_text(color = WNBA_COLORS$subtext, size = rel(0.9)),
      axis.title.x      = element_text(margin = margin(t = 8)),
      axis.title.y      = element_text(margin = margin(r = 8)),
      axis.text         = element_text(color = WNBA_COLORS$subtext, size = rel(0.85)),
      axis.ticks        = element_line(color = WNBA_COLORS$grid, linewidth = 0.35),
      strip.background  = element_rect(fill = WNBA_COLORS$panel, color = WNBA_COLORS$border),
      strip.text        = element_text(color = WNBA_COLORS$text, face = "bold", size = rel(0.9), margin = margin(t = 4, b = 4)),
      plot.margin       = margin(16, 20, 14, 16)
    )
}

# ------------------------------------------------------------------------------
# 2. Canonical WNBA Team Palette (Primary, Secondary, Accent)
# ------------------------------------------------------------------------------
# PROVENANCE: compiled from public WNBA franchise brand references (team
# style guides / team-color reference sites such as teamcolorcodes.com,
# cross-checked against each team's current wordmark/jersey assets) as of
# this repo's Nov 2026 knowledge horizon. This is the first time this repo has
# needed a WNBA team color palette -- there was no prior WNBA_TEAM_COLORS to
# inherit (unlike the NBA port, which lifted NBA_TEAM_COLORS from
# web/lib/teams.ts).
#
# CONFIDENCE FLAG: 13 of 15 franchises have been stable, well-documented
# brands for years. Two are 2026-season expansion franchises with much less
# public brand history to draw on -- POR (Portland Fire) and TOR (Toronto
# Tempo). Their entries below are a best-effort approximation of their
# announced primary hues, NOT verified against an official brand guide PDF,
# and should be re-checked against web/lib (if/when a Next.js teams.ts
# equivalent exists for this repo) or an official franchise asset before any
# chart ships these two colors in a way readers might screenshot and compare
# to the real jersey.
#
# Keyed off config.R's WNBA_TEAMS -- adding or removing a franchise from
# WNBA_TEAMS without updating this list makes resolve_team_abbr() fall through
# to the neutral accent color for the unmapped team (see get_wnba_team_color()
# below) rather than erroring, so a future expansion team is visually obvious
# (flat teal) instead of silently crashing every gallery chart.
WNBA_TEAM_COLORS <- list(
  ATL = list(primary = "#E31937", secondary = "#000000", accent = "#B29B6E"),  # Atlanta Dream
  CHI = list(primary = "#418FDE", secondary = "#FFD520", accent = "#13165E"),  # Chicago Sky
  CON = list(primary = "#E2231A", secondary = "#0A2240", accent = "#FFC72C"),  # Connecticut Sun
  DAL = list(primary = "#002A5C", secondary = "#C4122F", accent = "#8A8D8F"),  # Dallas Wings
  GS  = list(primary = "#4A2E83", secondary = "#9F85C9", accent = "#FDB927"),  # Golden State Valkyries
  IND = list(primary = "#E03A3E", secondary = "#FFC633", accent = "#002D62"),  # Indiana Fever
  LV  = list(primary = "#C8102E", secondary = "#101820", accent = "#A4925A"),  # Las Vegas Aces
  LA  = list(primary = "#552583", secondary = "#FDB927", accent = "#000000"),  # Los Angeles Sparks
  MIN = list(primary = "#236192", secondary = "#78BE20", accent = "#9EA2A2"),  # Minnesota Lynx
  NY  = list(primary = "#6ECEB2", secondary = "#000000", accent = "#9EA2A2"),  # New York Liberty
  PHX = list(primary = "#201747", secondary = "#E56020", accent = "#CB6079"),  # Phoenix Mercury
  POR = list(primary = "#E03A3E", secondary = "#000000", accent = "#C89B3C"),  # Portland Fire (2026 expansion; LOW CONFIDENCE, see note above)
  SEA = list(primary = "#2C5234", secondary = "#FEE11A", accent = "#9EA2A2"),  # Seattle Storm
  TOR = list(primary = "#CE0E2D", secondary = "#1D1160", accent = "#C4CED4"),  # Toronto Tempo (2026 expansion; LOW CONFIDENCE, see note above)
  WSH = list(primary = "#0A2240", secondary = "#E31837", accent = "#C4CED4")   # Washington Mystics
)

# Fail loudly (at source() time, not mid-chart) if WNBA_TEAMS and
# WNBA_TEAM_COLORS ever disagree on membership -- the comment above tolerates
# a missing color (falls back to the neutral accent) but an outright name
# mismatch is almost certainly a typo, not a real new/retired franchise.
.missing_colors <- setdiff(names(WNBA_TEAMS), names(WNBA_TEAM_COLORS))
if (length(.missing_colors) > 0) {
  warning(sprintf(
    "tools/viz_common.R: WNBA_TEAMS has team(s) with no WNBA_TEAM_COLORS entry: %s. Charts for %s will fall back to the neutral accent color.",
    paste(.missing_colors, collapse = ", "), paste(.missing_colors, collapse = ", ")
  ))
}
rm(.missing_colors)

# ------------------------------------------------------------------------------
# 3. Team Nickname / Abbreviation Normalization
# ------------------------------------------------------------------------------
# Built FROM WNBA_TEAMS's full names (e.g. "Atlanta Dream" -> "Dream") rather
# than a second hardcoded nickname list, so a roster change in config.R's
# WNBA_TEAMS propagates here automatically.
.wnba_nickname_from_fullname <- function(full_name) {
  words <- strsplit(trimws(full_name), "\\s+")[[1]]
  words[length(words)]
}
.NICKNAME_TO_ABBR <- setNames(
  names(WNBA_TEAMS),
  vapply(WNBA_TEAMS, .wnba_nickname_from_fullname, character(1))
)

# Alternate / historical abbreviations seen in raw wehoop feeds or other
# sources, mapped to this repo's canonical WNBA_TEAMS keys. CLAUDE.md already
# documents the CONN -> CON quirk (wehoop uses "CONN" for seasons 2019-2023);
# the rest are other spellings a chart script might plausibly be handed.
.ALT_ABBR_TO_STANDARD <- c(
  "CONN" = "CON", "NYL" = "NY", "LVA" = "LV", "GSV" = "GS",
  "WAS" = "WSH", "PHO" = "PHX"
)

resolve_team_abbr <- function(team_str) {
  if (is.null(team_str) || length(team_str) == 0) return(character(0))
  vapply(team_str, function(tm) {
    if (is.na(tm) || tm == "") return(NA_character_)
    s <- trimws(as.character(tm))
    u <- toupper(s)

    if (u %in% names(WNBA_TEAM_COLORS)) return(u)
    if (u %in% names(.ALT_ABBR_TO_STANDARD)) return(.ALT_ABBR_TO_STANDARD[[u]])
    if (s %in% names(.NICKNAME_TO_ABBR)) return(.NICKNAME_TO_ABBR[[s]])

    # Try resolving via team_name_resolver if present
    if (exists("resolve_team_name", mode = "function")) {
      resolved_nick <- resolve_team_name(s)
      if (resolved_nick %in% names(.NICKNAME_TO_ABBR)) {
        return(.NICKNAME_TO_ABBR[[resolved_nick]])
      }
    }

    # Best-effort match against nickname substrings
    for (nick in names(.NICKNAME_TO_ABBR)) {
      if (grepl(nick, s, ignore.case = TRUE)) {
        return(.NICKNAME_TO_ABBR[[nick]])
      }
    }

    u
  }, FUN.VALUE = character(1), USE.NAMES = FALSE)
}

# ------------------------------------------------------------------------------
# 4. Team Color Resolver
# ------------------------------------------------------------------------------
get_wnba_team_color <- function(team, type = c("primary", "secondary", "accent")) {
  type <- match.arg(type)
  if (is.null(team) || length(team) == 0) return(character(0))

  abbrs <- resolve_team_abbr(team)
  vapply(abbrs, function(ab) {
    if (is.na(ab) || !ab %in% names(WNBA_TEAM_COLORS)) {
      # Fallback neutral color (also WNBA_COLORS$accent, kept as a literal
      # here so this function has no load-bearing dependency on WNBA_COLORS's
      # internal shape).
      return("#3fd0c9")
    }
    WNBA_TEAM_COLORS[[ab]][[type]]
  }, FUN.VALUE = character(1), USE.NAMES = FALSE)
}

# ------------------------------------------------------------------------------
# 5. Team Logo Resolution Helpers
# ------------------------------------------------------------------------------
# ESPN WNBA team logo slugs. Default is tolower(abbr); only the entries below
# (where ESPN's own slug differs from this repo's WNBA_TEAMS abbreviation)
# need an override. CONFIDENCE FLAG: POR and TOR are 2026 expansion
# franchises -- their ESPN CDN slugs below are a best guess (lowercase
# abbreviation) and have not been verified against a live ESPN asset fetch;
# viz_logo_map()/get_wnba_logo_path() will surface a download failure (via
# viz_stop_no_data(), since this file's contract is zero-fallback) if a slug
# is wrong, rather than silently drawing a chart with a missing logo.
.ESPN_SLUG_MAP <- c(
  ATL = "atl", CHI = "chi", CON = "conn", DAL = "dal", GS = "gs",
  IND = "ind", LV = "lv", LA = "la", MIN = "min", NY = "ny",
  PHX = "phx", POR = "por", SEA = "sea", TOR = "tor", WSH = "wsh"
)

get_wnba_logo_url <- function(team) {
  if (is.null(team) || length(team) == 0) return(character(0))
  abbrs <- resolve_team_abbr(team)
  vapply(abbrs, function(ab) {
    if (is.na(ab)) return(NA_character_)
    slug <- if (ab %in% names(.ESPN_SLUG_MAP)) .ESPN_SLUG_MAP[[ab]] else tolower(ab)
    sprintf("https://a.espncdn.com/i/teamlogos/wnba/500/%s.png", slug)
  }, FUN.VALUE = character(1), USE.NAMES = FALSE)
}

get_wnba_logo_path <- function(team, dest_dir = NULL) {
  if (is.null(team) || length(team) == 0) return(character(0))
  abbrs <- resolve_team_abbr(team)

  if (is.null(dest_dir)) {
    # Check if config.R exists and defines CACHE_DIR
    if (exists("CACHE_DIR", envir = .GlobalEnv)) {
      dest_dir <- file.path(get("CACHE_DIR", envir = .GlobalEnv), "logos")
    } else {
      dest_dir <- file.path("cache", "logos")
    }
  }

  if (!dir.exists(dest_dir)) {
    dir.create(dest_dir, recursive = TRUE, showWarnings = FALSE)
  }

  vapply(abbrs, function(ab) {
    if (is.na(ab)) return(NA_character_)
    local_file <- file.path(dest_dir, sprintf("%s.png", ab))
    if (file.exists(local_file) && file.info(local_file)$size > 200) {
      return(normalizePath(local_file, winslash = "/"))
    }

    url <- get_wnba_logo_url(ab)
    download_ok <- tryCatch({
      utils::download.file(url, destfile = local_file, mode = "wb", quiet = TRUE)
      file.exists(local_file) && file.info(local_file)$size > 200
    }, error = function(e) {
      FALSE
    })

    if (download_ok) {
      normalizePath(local_file, winslash = "/")
    } else {
      NA_character_
    }
  }, FUN.VALUE = character(1), USE.NAMES = FALSE)
}

read_wnba_logo_grob <- function(team, dest_dir = NULL) {
  if (!requireNamespace("grid", quietly = TRUE) || !requireNamespace("png", quietly = TRUE)) {
    warning("Packages 'grid' and 'png' are required to construct logo grobs.")
    return(NULL)
  }
  p <- get_wnba_logo_path(team, dest_dir = dest_dir)
  if (is.na(p) || !file.exists(p)) return(NULL)

  img <- tryCatch(png::readPNG(p), error = function(e) NULL)
  if (is.null(img)) return(NULL)
  grid::rasterGrob(img, interpolate = TRUE)
}

# ------------------------------------------------------------------------------
# 6. Standardized Animated Artifact Renderer (GIF + Static Reduced-Motion PNG)
# ------------------------------------------------------------------------------
# Dual artifacts:
#   1. gif_path: Animated sequence encoded with gifski
#   2. png_path: Static final frame for prefers-reduced-motion compliance
# ------------------------------------------------------------------------------
# Marker a chart script emits when its real input data is unavailable. Per
# issue #140/#144, gallery chart scripts do NOT fall back to invented data
# (hand-typed ratings, simulated shots, etc.) the way CLAUDE.md's general
# house rule asks most of this repo's other scripts to -- they stop instead:
# no data, no chart. This mirrors the NBA original's rationale and this
# repo's own zero-betting / zero-synthetic-data policy.
#
# stop() rather than quit(): these scripts may also be source()d by pipeline
# stages, where quit() would end the whole session. Run through Rscript this
# is a non-zero exit, and tests/test_gallery_viz.R recognises the marker and
# reports a skip rather than a failure.
VIZ_NO_DATA_MARKER <- "[SKIP-NO-DATA]"

viz_stop_no_data <- function(script, reason) {
  stop(sprintf("%s %s: %s Nothing was rendered.", VIZ_NO_DATA_MARKER, script, reason),
       call. = FALSE)
}

render_animated_artifact <- function(frame_paths, gif_path, png_path = NULL,
                                     fps = 2, hold_last_frames = 6,
                                     width = 1000, height = 600) {
  if (length(frame_paths) == 0) {
    stop("render_animated_artifact: 'frame_paths' is empty.")
  }

  missing_frames <- frame_paths[!file.exists(frame_paths)]
  if (length(missing_frames) > 0) {
    stop(sprintf("render_animated_artifact: %d frame file(s) do not exist (e.g. %s)",
                 length(missing_frames), missing_frames[1]))
  }

  # Ensure destination directories exist
  for (out_f in c(gif_path, png_path)) {
    if (!is.null(out_f)) {
      d <- dirname(out_f)
      if (nzchar(d) && !dir.exists(d)) {
        dir.create(d, recursive = TRUE, showWarnings = FALSE)
      }
    }
  }

  # Expand frame sequence with hold_last_frames if requested
  last_frame <- frame_paths[length(frame_paths)]
  expanded_frames <- if (hold_last_frames > 0) {
    c(frame_paths, rep(last_frame, as.integer(hold_last_frames)))
  } else {
    frame_paths
  }

  # Write reduced-motion static PNG (copy of final frame, ensuring 100% agreement)
  if (!is.null(png_path) && nzchar(png_path)) {
    cp_ok <- file.copy(last_frame, png_path, overwrite = TRUE)
    if (!cp_ok) {
      warning(sprintf("render_animated_artifact: Failed to copy last frame to static PNG %s", png_path))
    }
  }

  # Encode GIF with gifski
  if (!requireNamespace("gifski", quietly = TRUE)) {
    stop("Package 'gifski' is required for render_animated_artifact().")
  }

  gifski::gifski(
    png_files = expanded_frames,
    gif_file  = gif_path,
    width     = width,
    height    = height,
    delay     = 1 / fps,
    progress  = FALSE
  )

  invisible(list(
    gif = gif_path,
    png = png_path,
    frames = length(expanded_frames),
    fps = fps
  ))
}

# ------------------------------------------------------------------------------
# 7. Logo lookup for charts
# ------------------------------------------------------------------------------
# Named vector (by team abbreviation) of local logo files for all 15 WNBA
# teams, downloaded once into <cache>/logos. Charts identify teams by logo,
# not by abbreviation. Stops when any logo is unavailable rather than drawing
# a chart with teams missing (zero-fallback contract, see VIZ_NO_DATA_MARKER
# above).
viz_logo_map <- function(cache_dir = Sys.getenv("WNBA_VIZ_CACHE_DIR", "cache"), script = "chart") {
  teams <- sort(names(WNBA_TEAM_COLORS))
  paths <- get_wnba_logo_path(teams, dest_dir = file.path(cache_dir, "logos"))
  if (anyNA(paths)) {
    viz_stop_no_data(script, sprintf("team logos unavailable for %s.", paste(teams[is.na(paths)], collapse = ", ")))
  }
  setNames(paths, teams)
}
