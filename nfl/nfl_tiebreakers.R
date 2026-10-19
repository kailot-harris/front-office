# ==============================================================================
# NFL Official Playoff Tiebreaker Procedures
# Path: c:/Users/kailo/kayceeslices/NFL Analytics/nfl_tiebreakers.R
#
# Replaces playoff_simulator.R's DELIBERATELY SIMPLIFIED tiebreak (win% -> games_played ->
# alphabetical) with the NFL's real, official multi-step procedure. Sourced by
# playoff_simulator.R; part of the pipeline DAG (stage 7), not a tools/ one-off.
#
# LIVE-VERIFIED PROCEDURE (WebSearch + WebFetch against nfl.com/standings/tie-breaking-
# procedures and espn.com's tiebreaker explainer, 2026-09-17 - re-verify at the start of a
# future season per CLAUDE.md's re-verification discipline; the NFL has changed these rules
# before, e.g. adding conference record and removing the pure coin-toss-first order):
#
# Two clubs, SAME DIVISION (in order):
#   1. Head-to-head        2. Division record        3. Common games (min. 4)
#   4. Conference record   5. Strength of victory     6. Strength of schedule
#   7. Combined rank, points scored/allowed, CONFERENCE teams
#   8. Combined rank, points scored/allowed, ALL teams
#   9. Net points, common games   10. Net points, all games
#   11. Net touchdowns, all games   12. Coin toss
#
# Three+ clubs, SAME DIVISION: identical list, step 1 becomes "head-to-head sweep."
#
# Two clubs, WILD CARD (different divisions):
#   1. Head-to-head (if applicable)   2. Conference record   3. Common games (min. 4)
#   4. Strength of victory   5. Strength of schedule
#   6. Combined rank, CONFERENCE teams   7. Combined rank, ALL teams
#   8. Net points, conference games   9. Net points, all games
#   10. Net touchdowns, all games   11. Coin toss
#
# Three+ clubs, WILD CARD: first reduce to one candidate per division (apply the division
# tiebreaker among any same-division clubs in the group, keep only the top finisher active),
# then apply the two-club wild-card list above (step 1 becomes "head-to-head sweep").
#
# CASCADE RULE (verified via ESPN's tiebreaker explainer): whenever a criterion splits a tied
# group into a strictly-better subgroup and a strictly-worse subgroup, each subgroup's
# remaining tie (if still 2+ members) is broken by RESTARTING at step 1 for that subgroup, not
# by continuing to the next criterion in the original list. Implemented recursively below.
#
# DOCUMENTED SCOPE LIMITATIONS (an honest gap, not a silent omission):
#   - "Head-to-head sweep" for 3+ clubs is approximated as "compare each club's win% in games
#     played against other members of the tied group" rather than the official's narrower
#     "applicable only if one club swept all the others" eligibility condition. This is the same
#     practical approximation most public NFL tiebreaker calculators use. Flagged here because a
#     future agent tightening this file should know it's an approximation, not verified-exact.
#   - "Net touchdowns in all games" and "coin toss" (the final two of ~12 steps) are NOT
#     implemented. Net touchdowns would require pulling full CACHE_PBP touchdown-play data
#     (a separate, expensive data dependency) for a criterion that is exceedingly rarely the
#     actual deciding factor in real NFL history (every other criterion above it has to tie
#     first, including net points in ALL games - i.e. matching combined season-long point
#     differential exactly). A coin toss is irreducibly random in reality anyway. Both are
#     replaced by a single deterministic alphabetical fallback, matching the prior simplified
#     script's own final tiebreak - this keeps pipeline output reproducible rather than
#     introducing real randomness for a criterion this repo cannot verify happened.
#   - The wild-card same-division-representative reduction places an eliminated division-mate
#     immediately after its division's active representative in final order, rather than fully
#     modeling the official rule's re-entry into a later tied comparison. This is a documented
#     simplification of a genuinely intricate corner case, not the full official recursive rule.
#
# No top-level side effects beyond function definitions - safe to source() from any script.
# ==============================================================================

.pct <- function(w, l, t) {
  g <- w + l + t
  ifelse(g > 0, (w + 0.5 * t) / g, NA_real_)
}

# ------------------------------------------------------------------------------------------
# build_tiebreak_data(): from CACHE_SCHEDULES, CURRENT_SEASON REG games. Returns
# list(game_log, records) - game_log is long-format one-row-per-team-per-game (with division/
# conference game flags), records is one row per NFL_TEAMS team with season win/loss/tie/points
# totals and win_pct (NA for a team with 0 completed games, same convention playoff_simulator.R
# already used).
# ------------------------------------------------------------------------------------------
build_tiebreak_data <- function(sch) {
  completed <- sch |>
    dplyr::filter(season == CURRENT_SEASON, game_type == "REG",
                  !is.na(home_score), !is.na(away_score))

  game_log <- dplyr::bind_rows(
    completed |> dplyr::transmute(team = home_team, opponent = away_team,
                                   own_score = home_score, opp_score = away_score),
    completed |> dplyr::transmute(team = away_team, opponent = home_team,
                                   own_score = away_score, opp_score = home_score)
  ) |>
    dplyr::mutate(
      win  = as.integer(own_score > opp_score),
      loss = as.integer(own_score < opp_score),
      tie  = as.integer(own_score == opp_score),
      team_conf = sub(" .*$", "", NFL_DIVISIONS[team]),
      opp_conf  = sub(" .*$", "", NFL_DIVISIONS[opponent]),
      team_div  = NFL_DIVISIONS[team],
      opp_div   = NFL_DIVISIONS[opponent],
      is_division_game   = team_div == opp_div,
      is_conference_game = team_conf == opp_conf
    )

  totals <- game_log |>
    dplyr::group_by(team) |>
    dplyr::summarise(wins = sum(win), losses = sum(loss), ties = sum(tie),
                      games_played = dplyr::n(),
                      points_for = sum(own_score), points_against = sum(opp_score),
                      .groups = "drop")

  all_teams <- data.frame(team = names(NFL_TEAMS), stringsAsFactors = FALSE)
  records <- all_teams |>
    dplyr::left_join(totals, by = "team") |>
    dplyr::mutate(
      wins = ifelse(is.na(wins), 0L, wins), losses = ifelse(is.na(losses), 0L, losses),
      ties = ifelse(is.na(ties), 0L, ties),
      games_played = ifelse(is.na(games_played), 0L, games_played),
      points_for = ifelse(is.na(points_for), 0, points_for),
      points_against = ifelse(is.na(points_against), 0, points_against),
      win_pct = ifelse(games_played > 0, .pct(wins, losses, ties), NA_real_)
    )

  list(game_log = game_log, records = records)
}

# ------------------------------------------------------------------------------------------
# Criterion functions. Each takes `group` (character vector of >=2 tied team abbreviations,
# all in the same conference) and returns either NULL (criterion not applicable - skip to the
# next one) or a named numeric vector (one value per group member) where HIGHER IS ALWAYS
# BETTER (rank-based criteria are negated so this convention holds everywhere).
# ------------------------------------------------------------------------------------------
.crit_head_to_head <- function(game_log) function(group) {
  sub <- game_log |> dplyr::filter(team %in% group, opponent %in% group)
  if (nrow(sub) == 0) return(NULL)
  rec <- sub |> dplyr::group_by(team) |>
    dplyr::summarise(w = sum(win), l = sum(loss), t = sum(tie), .groups = "drop")
  if (!all(group %in% rec$team)) return(NULL)  # not every member played another member
  vals <- stats::setNames(.pct(rec$w, rec$l, rec$t), rec$team)
  if (length(unique(vals)) <= 1) return(NULL)
  vals[group]
}

.crit_division_record <- function(game_log) function(group) {
  sub <- game_log |> dplyr::filter(team %in% group, is_division_game)
  if (nrow(sub) == 0) return(NULL)
  rec <- sub |> dplyr::group_by(team) |>
    dplyr::summarise(w = sum(win), l = sum(loss), t = sum(tie), .groups = "drop")
  full <- stats::setNames(rep(NA_real_, length(group)), group)
  vals <- stats::setNames(.pct(rec$w, rec$l, rec$t), rec$team)
  full[names(vals)] <- vals
  if (length(unique(stats::na.omit(full))) <= 1) return(NULL)
  full
}

.crit_conference_record <- function(game_log) function(group) {
  sub <- game_log |> dplyr::filter(team %in% group, is_conference_game)
  if (nrow(sub) == 0) return(NULL)
  rec <- sub |> dplyr::group_by(team) |>
    dplyr::summarise(w = sum(win), l = sum(loss), t = sum(tie), .groups = "drop")
  full <- stats::setNames(rep(NA_real_, length(group)), group)
  vals <- stats::setNames(.pct(rec$w, rec$l, rec$t), rec$team)
  full[names(vals)] <- vals
  if (length(unique(stats::na.omit(full))) <= 1) return(NULL)
  full
}

# Common-opponent set is a function of exactly which clubs are being compared - computed fresh
# for each candidate group, per the official "common games" definition (opponents ALL tied
# clubs have played, minimum four).
.common_opponents <- function(game_log, group) {
  opp_sets <- lapply(group, function(tm) unique(game_log$opponent[game_log$team == tm]))
  Reduce(intersect, opp_sets)
}

.crit_common_games <- function(game_log) function(group) {
  common_opps <- .common_opponents(game_log, group)
  if (length(common_opps) < 4) return(NULL)
  sub <- game_log |> dplyr::filter(team %in% group, opponent %in% common_opps)
  rec <- sub |> dplyr::group_by(team) |>
    dplyr::summarise(w = sum(win), l = sum(loss), t = sum(tie), .groups = "drop")
  full <- stats::setNames(rep(NA_real_, length(group)), group)
  vals <- stats::setNames(.pct(rec$w, rec$l, rec$t), rec$team)
  full[names(vals)] <- vals
  if (length(unique(stats::na.omit(full))) <= 1) return(NULL)
  full
}

# Strength of victory / schedule: aggregate (not averaged) win-loss-tie record of every
# opponent beaten (SOV) or played (SOS), counted once per game (a division rival played twice
# counts twice), per the official "aggregate of all teams" wording.
.strength <- function(game_log, records, group, victory_only) {
  wlt <- stats::setNames(
    lapply(seq_len(nrow(records)), function(i) records[i, c("wins", "losses", "ties", "games_played")]),
    records$team
  )
  vapply(group, function(tm) {
    rows <- game_log |> dplyr::filter(team == tm)
    if (victory_only) rows <- rows |> dplyr::filter(win == 1)
    if (nrow(rows) == 0) return(NA_real_)
    opp_w <- vapply(rows$opponent, function(o) wlt[[o]]$wins, numeric(1))
    opp_l <- vapply(rows$opponent, function(o) wlt[[o]]$losses, numeric(1))
    opp_t <- vapply(rows$opponent, function(o) wlt[[o]]$ties, numeric(1))
    .pct(sum(opp_w), sum(opp_l), sum(opp_t))
  }, numeric(1)) |> stats::setNames(group)
}

.crit_strength_of_victory <- function(game_log, records) function(group) {
  vals <- .strength(game_log, records, group, victory_only = TRUE)
  if (length(unique(stats::na.omit(vals))) <= 1) return(NULL)
  vals
}
.crit_strength_of_schedule <- function(game_log, records) function(group) {
  vals <- .strength(game_log, records, group, victory_only = FALSE)
  if (length(unique(stats::na.omit(vals))) <= 1) return(NULL)
  vals
}

# Best combined ranking in points scored/allowed - lower rank sum wins, so this returns the
# NEGATIVE rank sum to keep this file's "higher is always better" convention.
.combined_rank <- function(records, scope_teams) {
  sub <- records[records$team %in% scope_teams, ]
  rank_pf <- rank(-sub$points_for, ties.method = "min")
  rank_pa <- rank(sub$points_against, ties.method = "min")
  stats::setNames(-(rank_pf + rank_pa), sub$team)
}

.crit_combined_rank_conference <- function(records) function(group) {
  conf <- unique(sub(" .*$", "", NFL_DIVISIONS[group]))
  if (length(conf) != 1) return(NULL)  # should not happen - wild-card groups are single-conference
  scope_teams <- names(NFL_DIVISIONS)[sub(" .*$", "", NFL_DIVISIONS) == conf]
  vals <- .combined_rank(records, scope_teams)[group]
  if (length(unique(vals)) <= 1) return(NULL)
  vals
}
.crit_combined_rank_all <- function(records) function(group) {
  vals <- .combined_rank(records, names(NFL_DIVISIONS))[group]
  if (length(unique(vals)) <= 1) return(NULL)
  vals
}

.crit_net_points_all <- function(records) function(group) {
  sub <- records[match(group, records$team), ]
  vals <- stats::setNames(sub$points_for - sub$points_against, group)
  if (length(unique(vals)) <= 1) return(NULL)
  vals
}
.crit_net_points_conference <- function(game_log) function(group) {
  sub <- game_log |> dplyr::filter(team %in% group, is_conference_game) |>
    dplyr::group_by(team) |> dplyr::summarise(pf = sum(own_score), pa = sum(opp_score), .groups = "drop")
  full <- stats::setNames(rep(NA_real_, length(group)), group)
  vals <- stats::setNames(sub$pf - sub$pa, sub$team)
  full[names(vals)] <- vals
  if (length(unique(stats::na.omit(full))) <= 1) return(NULL)
  full
}
.crit_net_points_common <- function(game_log) function(group) {
  common_opps <- .common_opponents(game_log, group)
  if (length(common_opps) < 4) return(NULL)
  sub <- game_log |> dplyr::filter(team %in% group, opponent %in% common_opps) |>
    dplyr::group_by(team) |> dplyr::summarise(pf = sum(own_score), pa = sum(opp_score), .groups = "drop")
  full <- stats::setNames(rep(NA_real_, length(group)), group)
  vals <- stats::setNames(sub$pf - sub$pa, sub$team)
  full[names(vals)] <- vals
  if (length(unique(stats::na.omit(full))) <= 1) return(NULL)
  full
}

# ------------------------------------------------------------------------------------------
# .cascade(): the recursive engine. `group` = tied team abbreviations (already equal win_pct).
# `criteria` = ordered list of criterion functions to try, in the official order. Splits the
# group at the first criterion that produces more than one distinct value, recurses into each
# resulting tier RESTARTING at criteria[[1]] (the official cascade rule), and concatenates
# best-tier-first. Falls back to alphabetical order if every criterion is exhausted with the
# group still fully tied (standing in for net-touchdowns/coin-toss - see header).
# ------------------------------------------------------------------------------------------
.cascade <- function(group, criteria) {
  if (length(group) <= 1) return(group)
  for (crit in criteria) {
    vals <- crit(group)
    if (is.null(vals)) next
    tier_values <- sort(unique(vals), decreasing = TRUE)
    if (length(tier_values) <= 1) next  # criterion applicable but didn't actually split anyone
    tiers <- lapply(tier_values, function(v) names(vals)[vals == v])
    return(unlist(lapply(tiers, function(tier) {
      if (length(tier) == 1) tier else .cascade(tier, criteria)
    }), use.names = FALSE))
  }
  sort(group)  # fully exhausted - alphabetical fallback (see header's documented scope limits)
}

# ------------------------------------------------------------------------------------------
# resolve_division_ties() / resolve_wildcard_ties(): the two public entry points. Both return
# `group` reordered best-to-worst. `game_log`/`records` come from build_tiebreak_data().
# ------------------------------------------------------------------------------------------
resolve_division_ties <- function(group, game_log, records) {
  if (length(group) <= 1) return(group)
  criteria <- list(
    .crit_head_to_head(game_log),
    .crit_division_record(game_log),
    .crit_common_games(game_log),
    .crit_conference_record(game_log),
    .crit_strength_of_victory(game_log, records),
    .crit_strength_of_schedule(game_log, records),
    .crit_combined_rank_conference(records),
    .crit_combined_rank_all(records),
    .crit_net_points_common(game_log),
    .crit_net_points_all(records)
  )
  .cascade(group, criteria)
}

resolve_wildcard_ties <- function(group, game_log, records) {
  if (length(group) <= 1) return(group)

  # Step: reduce any same-division clusters within the group to their single top finisher
  # (per the official "three+ clubs for wild card" rule) - see header's documented
  # simplification of the eliminated division-mate's re-entry.
  divs <- NFL_DIVISIONS[group]
  by_div <- split(group, divs)
  active <- character(0)
  held_back <- list()
  for (d in names(by_div)) {
    members <- by_div[[d]]
    if (length(members) == 1) {
      active <- c(active, members)
    } else {
      ordered <- resolve_division_ties(members, game_log, records)
      active <- c(active, ordered[1])
      held_back[[ordered[1]]] <- ordered[-1]
    }
  }

  criteria <- list(
    .crit_head_to_head(game_log),
    .crit_conference_record(game_log),
    .crit_common_games(game_log),
    .crit_strength_of_victory(game_log, records),
    .crit_strength_of_schedule(game_log, records),
    .crit_combined_rank_conference(records),
    .crit_combined_rank_all(records),
    .crit_net_points_conference(game_log),
    .crit_net_points_all(records)
  )
  active_order <- .cascade(active, criteria)

  # Re-insert each held-back division-mate immediately after its division's representative.
  unlist(lapply(active_order, function(tm) c(tm, held_back[[tm]])), use.names = FALSE)
}

# ------------------------------------------------------------------------------------------
# order_by_record(): given a data.frame with columns team/win_pct (and any others), returns it
# reordered best-to-worst - grouping by win_pct (NA last, treated as its own worst tier,
# alphabetical within it) and calling `tiebreak_fn` on any tier with more than one team.
# ------------------------------------------------------------------------------------------
order_by_record <- function(df, tiebreak_fn, game_log, records) {
  if (nrow(df) == 0) return(df)
  na_rows <- df[is.na(df$win_pct), , drop = FALSE]
  ranked_rows <- df[!is.na(df$win_pct), , drop = FALSE]

  pct_tiers <- sort(unique(ranked_rows$win_pct), decreasing = TRUE)
  ordered_teams <- unlist(lapply(pct_tiers, function(p) {
    tier <- ranked_rows$team[ranked_rows$win_pct == p]
    if (length(tier) > 1) tiebreak_fn(tier, game_log, records) else tier
  }), use.names = FALSE)

  na_teams <- sort(na_rows$team)
  all_ordered <- c(ordered_teams, na_teams)
  df[match(all_ordered, df$team), , drop = FALSE]
}
