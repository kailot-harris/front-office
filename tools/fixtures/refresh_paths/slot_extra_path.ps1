# FIXTURE for tools/test_check_refresh_paths_sync.mjs -- NBA stages a file its
# refresh workflow does not.
$SPORT_REFRESH = [ordered]@{
    mlb  = @{ Dir = 'MLB Analytics';  Args = @();    Paths = @('web/public/data') }
    nba  = @{ Dir = 'NBA Analytics';  Args = @('3'); Paths = @('web/public/data/matchups_slates.json', 'web/public/data/landing_digest.json', 'web/public/data/data_manifest.json') }
}
