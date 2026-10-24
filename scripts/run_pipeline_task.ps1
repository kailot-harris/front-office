# ==============================================================================
# run_pipeline_task.ps1 -- Automated Execution Wrapper for MLB Pipeline
# Used for Windows Task Scheduler, Cron/Automation, or standalone daemon runs.
# ==============================================================================

$ProjectDir = "c:\Users\kailo\kayceeslices\front-office\MLB Analytics"
Set-Location -Path $ProjectDir

$LogFile = Join-Path $ProjectDir "logs\scheduled_runs.log"
$Timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")

Add-Content -Path $LogFile -Value "[$Timestamp] Starting MLB Analytics Pipeline Scheduled Run"

$Rscript = "C:\Program Files\R\R-4.5.2\bin\Rscript.exe"
if (-not (Test-Path $Rscript)) {
    $Rscript = (Get-Command Rscript.exe).Source
}

& $Rscript "run_full_pipeline.R" *>> $LogFile
$ExitCode = $LASTEXITCODE

$EndTimestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
if ($ExitCode -eq 0) {
    Add-Content -Path $LogFile -Value "[$EndTimestamp] MLB Pipeline executed successfully (Exit Code 0)."
} else {
    Add-Content -Path $LogFile -Value "[$EndTimestamp] ERROR: MLB Pipeline failed with Exit Code $ExitCode!"
}

exit $ExitCode
