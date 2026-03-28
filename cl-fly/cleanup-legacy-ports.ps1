$ErrorActionPreference = 'Stop'

$legacyPorts = @(8081, 8082)

$listeners = Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue |
  Where-Object { $_.LocalPort -in $legacyPorts }

if (-not $listeners -or ($listeners | Measure-Object).Count -eq 0) {
  Write-Host 'No listeners found on legacy ports 8081/8082.'
  exit 0
}

$pids = $listeners | Select-Object -ExpandProperty OwningProcess -Unique

Write-Host 'Found legacy listeners:'
$listeners |
  Select-Object LocalAddress, LocalPort, OwningProcess |
  Sort-Object LocalPort |
  Format-Table -AutoSize

foreach ($pid in $pids) {
  Write-Host "Stopping PID $pid ..."
  & taskkill /PID $pid /F | Out-Null
}

Start-Sleep -Seconds 1

$remaining = Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue |
  Where-Object { $_.LocalPort -in $legacyPorts }

if ($remaining -and ($remaining | Measure-Object).Count -gt 0) {
  Write-Warning 'Some legacy listeners still remain on 8081/8082.'
  $remaining |
    Select-Object LocalAddress, LocalPort, OwningProcess |
    Sort-Object LocalPort |
    Format-Table -AutoSize
  exit 1
}

Write-Host 'Legacy listeners on 8081/8082 have been cleaned up.'
