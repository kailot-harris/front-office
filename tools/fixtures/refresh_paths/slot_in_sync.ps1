# FIXTURE for tools/test_check_refresh_paths_sync.mjs -- an excerpt of the
# $SPORT_REFRESH table in tools/run_refresh_slot.ps1, not a runnable script.
$SPORT_REFRESH = [ordered]@{
    mlb  = @{ Dir = 'MLB Analytics';  Args = @();    Paths = @('web/public/data') }
    nba  = @{ Dir = 'NBA Analytics';  Args = @('3'); Paths = @('web/public/data/matchups_slates.json', 'web/public/data/landing_digest.json') }
}
