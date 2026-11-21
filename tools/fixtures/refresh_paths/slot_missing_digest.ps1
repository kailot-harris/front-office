# FIXTURE for tools/test_check_refresh_paths_sync.mjs -- the $SPORT_REFRESH
# table as it stood before the landing digest was added to NBA's Paths.
$SPORT_REFRESH = [ordered]@{
    mlb  = @{ Dir = 'MLB Analytics';  Args = @();    Paths = @('web/public/data') }
    nba  = @{ Dir = 'NBA Analytics';  Args = @('3'); Paths = @('web/public/data/matchups_slates.json') }
}
