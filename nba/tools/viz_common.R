# ==============================================================================
# tools/viz_common.R
# Path: tools/viz_common.R
#
# Common NBA visualization foundation:
#   - Theme: theme_nba_dark() consistent with Next.js dark UI (#0b1120 bg, #111a2e panel, #22304a grid)
#   - Palettes: NBA_COLORS, NBA_CONFERENCE_COLORS, NBA_DIVISION_COLORS, NBA_TEAM_COLORS
#   - Team color / abbreviation resolver: get_nba_team_color(), resolve_team_abbr()
#   - Logo helpers: get_nba_logo_url(), get_nba_logo_path(), read_nba_logo_grob()
#   - Animation encoder: render_animated_artifact() (GIF + static PNG final frame for prefers-reduced-motion)
# ==============================================================================

suppressPackageStartupMessages({
  library(ggplot2)
})

# ------------------------------------------------------------------------------
# 1. Dark Theme for NBA Visualizations
# ------------------------------------------------------------------------------
# Consistent with Next.js dark UI:
#   bg:       #0b1120
#   panel:    #111a2e
#   grid:     #22304a
#   text:     #e7ecf5
#   subtext:  #9fb0c9
#   border:   #1f2937
# ------------------------------------------------------------------------------
NBA_COLORS <- list(
  bg         = "#0b1120",
  panel      = "#111a2e",
  grid       = "#22304a",
  border     = "#1f2937",
  text       = "#e7ecf5",
  subtext    = "#9fb0c9",
  accent     = "#3fd0c9",
  negative   = "#ff6b57",
  east       = "#3b82f6",
  west       = "#ef4444"
)

theme_nba_dark <- function(base_size = 11, base_family = "") {
  theme_minimal(base_size = base_size, base_family = base_family) +
    theme(
      plot.background   = element_rect(fill = NBA_COLORS$bg, color = NA),
      panel.background  = element_rect(fill = NBA_COLORS$panel, color = NA),
      panel.border      = element_rect(color = NBA_COLORS$border, fill = NA, linewidth = 0.5),
      panel.grid.major  = element_line(color = NBA_COLORS$grid, linewidth = 0.35),
      panel.grid.minor  = element_blank(),
      legend.background = element_rect(fill = NBA_COLORS$bg, color = NA),
      legend.key        = element_rect(fill = "transparent", color = NA),
      legend.text       = element_text(color = NBA_COLORS$subtext, size = rel(0.85)),
      legend.title      = element_text(color = NBA_COLORS$text, face = "bold", size = rel(0.9)),
      text              = element_text(color = NBA_COLORS$text),
      plot.title        = element_text(color = NBA_COLORS$text, face = "bold", size = rel(1.3), margin = margin(b = 5)),
      plot.subtitle     = element_text(color = NBA_COLORS$subtext, size = rel(0.95), margin = margin(b = 10)),
      plot.caption      = element_text(color = NBA_COLORS$subtext, size = rel(0.75), margin = margin(t = 10), hjust = 1),
      axis.title        = element_text(color = NBA_COLORS$subtext, size = rel(0.9)),
      axis.title.x      = element_text(margin = margin(t = 8)),
      axis.title.y      = element_text(margin = margin(r = 8)),
      axis.text         = element_text(color = NBA_COLORS$subtext, size = rel(0.85)),
      axis.ticks        = element_line(color = NBA_COLORS$grid, linewidth = 0.35),
      strip.background  = element_rect(fill = NBA_COLORS$panel, color = NBA_COLORS$border),
      strip.text        = element_text(color = NBA_COLORS$text, face = "bold", size = rel(0.9), margin = margin(t = 4, b = 4)),
      plot.margin       = margin(16, 20, 14, 16)
    )
}

# ------------------------------------------------------------------------------
# 2. Conference & Division Palettes
# ------------------------------------------------------------------------------
NBA_CONFERENCE_COLORS <- c(
  "East" = "#3b82f6",  # Eastern Conference Blue
  "West" = "#ef4444"   # Western Conference Red
)

NBA_DIVISION_COLORS <- c(
  # Eastern Conference
  "Atlantic"  = "#38bdf8", # Sky Blue
  "Central"   = "#818cf8", # Indigo Blue
  "Southeast" = "#a855f7", # Purple

  # Western Conference
  "Northwest" = "#f97316", # Orange
  "Pacific"   = "#eab308", # Amber / Gold
  "Southwest" = "#ef4444"  # Crimson / Red
)

# ------------------------------------------------------------------------------
# 3. Canonical 30 NBA Team Palette (Primary, Secondary, Accent)
# Sourced from official franchise identities and web/lib/teams.ts
# ------------------------------------------------------------------------------
NBA_TEAM_COLORS <- list(
  ATL = list(primary = "#E03A3E", secondary = "#C1D32F", accent = "#26282A"),
  BOS = list(primary = "#007A33", secondary = "#BA9653", accent = "#000000"),
  BKN = list(primary = "#000000", secondary = "#FFFFFF", accent = "#707271"),
  CHA = list(primary = "#1D1160", secondary = "#00788C", accent = "#A1A1A4"),
  CHI = list(primary = "#CE1141", secondary = "#000000", accent = "#FFFFFF"),
  CLE = list(primary = "#860038", secondary = "#041E42", accent = "#FDBB30"),
  DAL = list(primary = "#00538C", secondary = "#002B5E", accent = "#B8C4CA"),
  DEN = list(primary = "#0E2240", secondary = "#FEC524", accent = "#8B2131"),
  DET = list(primary = "#C8102E", secondary = "#1D42BA", accent = "#BEC0C2"),
  GSW = list(primary = "#1D428A", secondary = "#FFC72C", accent = "#000000"),
  HOU = list(primary = "#CE1141", secondary = "#000000", accent = "#9EA2A2"),
  IND = list(primary = "#002D62", secondary = "#FDBB30", accent = "#BEC0C2"),
  LAC = list(primary = "#C8102E", secondary = "#1D428A", accent = "#000000"),
  LAL = list(primary = "#552583", secondary = "#FDB927", accent = "#000000"),
  MEM = list(primary = "#5D76A9", secondary = "#12173F", accent = "#F5B112"),
  MIA = list(primary = "#98002E", secondary = "#F9A01B", accent = "#000000"),
  MIL = list(primary = "#00471B", secondary = "#EEE1C6", accent = "#0077C0"),
  MIN = list(primary = "#0C2340", secondary = "#236192", accent = "#78BE20"),
  NOP = list(primary = "#0C2340", secondary = "#C8102E", accent = "#85714D"),
  NYK = list(primary = "#006BB6", secondary = "#F58426", accent = "#BEC0C2"),
  OKC = list(primary = "#007AC1", secondary = "#EF3B24", accent = "#FDBB30"),
  ORL = list(primary = "#0077C0", secondary = "#C4CED4", accent = "#000000"),
  PHI = list(primary = "#006BB6", secondary = "#ED174C", accent = "#002B5C"),
  PHX = list(primary = "#1D1160", secondary = "#E56020", accent = "#000000"),
  POR = list(primary = "#E03A3E", secondary = "#000000", accent = "#FFFFFF"),
  SAC = list(primary = "#5A2D81", secondary = "#63727A", accent = "#000000"),
  SAS = list(primary = "#C4CED4", secondary = "#000000", accent = "#8A8D8F"),
  TOR = list(primary = "#CE1141", secondary = "#000000", accent = "#A1A1A4"),
  UTA = list(primary = "#002B5C", secondary = "#F9A01B", accent = "#00471B"),
  WAS = list(primary = "#002B5C", secondary = "#E31837", accent = "#C4CED4")
)

# ------------------------------------------------------------------------------
# 4. Team Nickname / Abbreviation Normalization
# ------------------------------------------------------------------------------
.NICKNAME_TO_ABBR <- c(
  "Hawks"          = "ATL", "Celtics"        = "BOS", "Nets"           = "BKN",
  "Hornets"        = "CHA", "Bulls"          = "CHI", "Cavaliers"     = "CLE",
  "Mavericks"      = "DAL", "Nuggets"        = "DEN", "Pistons"        = "DET",
  "Warriors"       = "GSW", "Rockets"        = "HOU", "Pacers"         = "IND",
  "Clippers"       = "LAC", "Lakers"         = "LAL", "Grizzlies"      = "MEM",
  "Heat"           = "MIA", "Bucks"          = "MIL", "Timberwolves"   = "MIN",
  "Pelicans"       = "NOP", "Knicks"         = "NYK", "Thunder"        = "OKC",
  "Magic"          = "ORL", "76ers"          = "PHI", "Suns"           = "PHX",
  "Trail Blazers"  = "POR", "Kings"          = "SAC", "Spurs"          = "SAS",
  "Raptors"        = "TOR", "Jazz"           = "UTA", "Wizards"        = "WAS"
)

.ALT_ABBR_TO_STANDARD <- c(
  "GS" = "GSW", "NO" = "NOP", "NY" = "NYK",
  "SA" = "SAS", "UTAH" = "UTA", "WSH" = "WAS",
  "PHO" = "PHX", "BK" = "BKN", "BRK" = "BKN"
)

resolve_team_abbr <- function(team_str) {
  if (is.null(team_str) || length(team_str) == 0) return(character(0))
  vapply(team_str, function(tm) {
    if (is.na(tm) || tm == "") return(NA_character_)
    s <- trimws(as.character(tm))
    u <- toupper(s)

    if (u %in% names(NBA_TEAM_COLORS)) return(u)
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
# 5. Team Color Resolver
# ------------------------------------------------------------------------------
get_nba_team_color <- function(team, type = c("primary", "secondary", "accent")) {
  type <- match.arg(type)
  if (is.null(team) || length(team) == 0) return(character(0))

  abbrs <- resolve_team_abbr(team)
  vapply(abbrs, function(ab) {
    if (is.na(ab) || !ab %in% names(NBA_TEAM_COLORS)) {
      # Fallback neutral color
      return("#3fd0c9")
    }
    NBA_TEAM_COLORS[[ab]][[type]]
  }, FUN.VALUE = character(1), USE.NAMES = FALSE)
}

# ------------------------------------------------------------------------------
# 6. Team Logo Resolution Helpers
# ------------------------------------------------------------------------------
.ESPN_SLUG_MAP <- c(
  ATL = "atl", BOS = "bos", BKN = "bkn", CHA = "cha", CHI = "chi", CLE = "cle",
  DAL = "dal", DEN = "den", DET = "det", GSW = "gsw", HOU = "hou", IND = "ind",
  LAC = "lac", LAL = "lal", MEM = "mem", MIA = "mia", MIL = "mil", MIN = "min",
  NOP = "no",  NYK = "nyk", OKC = "okc", ORL = "orl", PHI = "phi", PHX = "phx",
  POR = "por", SAC = "sac", SAS = "sas", TOR = "tor", UTA = "utah", WAS = "was"
)

get_nba_logo_url <- function(team) {
  if (is.null(team) || length(team) == 0) return(character(0))
  abbrs <- resolve_team_abbr(team)
  vapply(abbrs, function(ab) {
    if (is.na(ab)) return(NA_character_)
    slug <- if (ab %in% names(.ESPN_SLUG_MAP)) .ESPN_SLUG_MAP[[ab]] else tolower(ab)
    sprintf("https://a.espncdn.com/i/teamlogos/nba/500/%s.png", slug)
  }, FUN.VALUE = character(1), USE.NAMES = FALSE)
}

get_nba_logo_path <- function(team, dest_dir = NULL) {
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

    url <- get_nba_logo_url(ab)
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

read_nba_logo_grob <- function(team, dest_dir = NULL) {
  if (!requireNamespace("grid", quietly = TRUE) || !requireNamespace("png", quietly = TRUE)) {
    warning("Packages 'grid' and 'png' are required to construct logo grobs.")
    return(NULL)
  }
  p <- get_nba_logo_path(team, dest_dir = dest_dir)
  if (is.na(p) || !file.exists(p)) return(NULL)

  img <- tryCatch(png::readPNG(p), error = function(e) NULL)
  if (is.null(img)) return(NULL)
  grid::rasterGrob(img, interpolate = TRUE)
}

# ------------------------------------------------------------------------------
# 7. Standardized Animated Artifact Renderer (GIF + Static Reduced-Motion PNG)
# ------------------------------------------------------------------------------
# Dual artifacts:
#   1. gif_path: Animated sequence encoded with gifski
#   2. png_path: Static final frame for prefers-reduced-motion compliance
# ------------------------------------------------------------------------------
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
