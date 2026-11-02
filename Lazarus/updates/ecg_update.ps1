param([Parameter(Mandatory=$true)][string]$CurrentVersion,[Parameter(Mandatory=$true)][int]$AppPid)
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"
$logDir = Join-Path $env:LOCALAPPDATA "ECGMonitor"
New-Item -ItemType Directory -Force -Path $logDir | Out-Null
function Log([string]$Message) { Add-Content -LiteralPath (Join-Path $logDir "updater.log") -Value "[$(Get-Date -Format s)] $Message" }
try {
  $latest = Invoke-RestMethod -Uri "https://api.github.com/repos/marcelomaurin/ECG/releases/latest" -Headers @{"User-Agent"="ECGMonitor-Updater"} -TimeoutSec 20
  if ($latest.draft -or $latest.prerelease) { exit 0 }
  $remoteString = ([string]$latest.tag_name) -replace '^v',''
  $localString = $CurrentVersion -replace '^v',''
  try { $remote = [version]$remoteString; $local = [version]$localString } catch { Log "Invalid version"; exit 0 }
  if ($remote -le $local) { exit 0 }
  $name = "ECGMonitor_v" + $remoteString + "_Setup.exe"
  $asset = @($latest.assets | Where-Object { $_.name -eq $name }) | Select-Object -First 1
  $checksum = @($latest.assets | Where-Object { $_.name -eq "SHA256SUMS.txt" }) | Select-Object -First 1
  if (-not $asset -or -not $checksum) { Log "Installer/checksums missing"; exit 0 }
  if ($asset.size -le 0 -or $asset.size -gt 314572800) { Log "Invalid asset size"; exit 0 }
  $dir = Join-Path $logDir ("updates\" + $remoteString)
  New-Item -ItemType Directory -Force -Path $dir | Out-Null
  $installer = Join-Path $dir $name
  $sumFile = Join-Path $dir "SHA256SUMS.txt"
  Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $installer -TimeoutSec 180
  Invoke-WebRequest -Uri $checksum.browser_download_url -OutFile $sumFile -TimeoutSec 30
  $entry = @(Get-Content -LiteralPath $sumFile | Where-Object { $_ -match ('^([0-9a-fA-F]{64})\s+\*?' + [regex]::Escape($name) + '$') }) | Select-Object -First 1
  if (-not $entry) { Log "Checksum entry missing"; Remove-Item $installer -Force; exit 0 }
  $expected = [regex]::Match($entry,'^[0-9a-fA-F]{64}').Value
  $actual = (Get-FileHash -LiteralPath $installer -Algorithm SHA256).Hash
  if ($actual -ine $expected) { Log "SHA256 mismatch"; Remove-Item $installer -Force; exit 0 }
  # Never interrupt a running ECG acquisition: wait for natural shutdown.
  try { Wait-Process -Id $AppPid -Timeout 86400 -ErrorAction SilentlyContinue } catch {}
  if (Get-Process -Id $AppPid -ErrorAction SilentlyContinue) { Log "App still running"; exit 0 }
  $process = Start-Process -FilePath $installer -ArgumentList "/VERYSILENT /SUPPRESSMSGBOXES /NORESTART /CLOSEAPPLICATIONS" -Wait -PassThru
  Log ("Installer exit code: " + $process.ExitCode)
} catch { Log ("Update skipped: " + $_.Exception.Message) }
