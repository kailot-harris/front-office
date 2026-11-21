# FIXTURE for tools/test_check_refresh_paths_sync.mjs -- MLB lists one file
# under the directory its workflow stages; a directory covers its files.
$SPORT_REFRESH = [ordered]@{
    mlb  = @{ Dir = 'MLB Analytics';  Args = @();    Paths = @('web/public/data/landing_digest.json') }
    nba  = @{ Dir = 'NBA Analytics';  Args = @('3'); Paths = @('web/public/data/matchups_slates.json', 'web/public/data/landing_digest.json') }
}
