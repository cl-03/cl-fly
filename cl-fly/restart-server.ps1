$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$startScript = Join-Path $root 'start-server.lisp'

# Enforce project runtime ports.
$env:KEFU_HTTP_PORT = '4000'
$env:KEFU_WS_PORT = '4001'

if (-not (Get-Command sbcl -ErrorAction SilentlyContinue)) {
  Write-Error 'sbcl not found in PATH. Please install SBCL or add it to PATH.'
  exit 1
}

# Stop old cl-fly server processes started with this script.
$old = Get-CimInstance Win32_Process |
  Where-Object {
    $_.Name -ieq 'sbcl.exe' -and
    $_.CommandLine -match 'start-server\.lisp'
  }

foreach ($p in $old) {
  try {
    Stop-Process -Id $p.ProcessId -Force -ErrorAction Stop
    Write-Host "Stopped old SBCL process: $($p.ProcessId)"
  } catch {
    Write-Warning "Failed to stop process $($p.ProcessId): $($_.Exception.Message)"
  }
}

$proc = Start-Process -FilePath 'sbcl' `
  -ArgumentList @('--disable-debugger', '--script', $startScript) `
  -WorkingDirectory $root `
  -PassThru

$ready = $false
for ($i = 0; $i -lt 30; $i++) {
  Start-Sleep -Seconds 1
  $listen = Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue |
    Where-Object { $_.LocalPort -in 4000, 4001 -and $_.OwningProcess -eq $proc.Id }
  if (($listen | Measure-Object).Count -ge 2) {
    $ready = $true
    break
  }
}

if (-not $ready) {
  Write-Error "Server started (PID=$($proc.Id)) but ports 4000/4001 were not both ready within 30 seconds."
  exit 1
}

Write-Host "Server is running. PID=$($proc.Id)"
Write-Host 'HTTP: http://127.0.0.1:4000/chat'
Write-Host 'AGENT: http://127.0.0.1:4000/agent-demo'
