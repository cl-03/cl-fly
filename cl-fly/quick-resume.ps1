param(
    [switch]$RunTests,
    [switch]$ShowFullStatus
)

$ErrorActionPreference = "Stop"

$repoDir = $PSScriptRoot
Set-Location $repoDir

Write-Host "== cl-fly quick resume =="
Write-Host "Repo: $repoDir"

Write-Host "`n[1/4] Branch"
git rev-parse --abbrev-ref HEAD

Write-Host "`n[2/4] Latest commit"
git log -1 --oneline

Write-Host "`n[3/4] Working tree"
if ($ShowFullStatus) {
    git status --short
} else {
    git status --short
    Write-Host "Tip: use -ShowFullStatus for full short status output."
}

Write-Host "`n[4/4] Resume note"
$note = Join-Path $repoDir "docs/dev-resume-state.md"
if (Test-Path $note) {
    Write-Host "Open: $note"
} else {
    Write-Host "Resume note not found."
}

if ($RunTests) {
    Write-Host "`nRunning full tests..."
    sbcl --script tests/run-tests.lisp
}

Write-Host "`nQuick resume complete."
