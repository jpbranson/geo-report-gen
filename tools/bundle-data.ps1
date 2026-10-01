<#
Bundle the data cache and rendered reports into one tar file, to move them to another machine
(Windows, Mac or Linux; see docs/data-sync.md).

  .\tools\bundle-data.cmd [-NoReports] [-OutDir <folder>]

Writes <OutDir, default your Downloads folder>\geo-report-data-<date>-<commit>.tar and a .sha256
next to it. The archive holds cache\ and reports\ as they sit in the project folder, never .env
(API keys). Lock files and partial downloads are left out. Uses the tar.exe built into Windows 10
and 11. On a Mac or Linux, tools/bundle-data.sh writes the same archive.
#>
param(
  [switch]$NoReports,
  [string]$OutDir
)
$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
if (-not (Test-Path (Join-Path $root 'cache'))) { throw "No cache folder in ${root}: nothing to bundle." }
$tar = Join-Path $env:SystemRoot 'System32\tar.exe'
if (-not (Test-Path $tar)) { throw "tar.exe was not found (it comes with Windows 10 version 1803 and later)." }

if (-not $OutDir) {
  # The real Downloads folder, even if it was moved (for example into OneDrive).
  try { $OutDir = (New-Object -ComObject Shell.Application).NameSpace('shell:Downloads').Self.Path } catch { $OutDir = $null }
  if (-not $OutDir) { $OutDir = Join-Path $env:USERPROFILE 'Downloads' }
}
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$OutDir = (Resolve-Path $OutDir).Path

$folders = @('cache')
if (-not $NoReports -and (Test-Path (Join-Path $root 'reports'))) { $folders += 'reports' }

$commit = 'unknown'
try {
  $c = & git -C $root rev-parse --short HEAD 2>$null
  if ($LASTEXITCODE -eq 0 -and $c) { $commit = "$c".Trim() }
} catch { }
$name = "geo-report-data-$(Get-Date -Format 'yyyyMMdd-HHmm')-$commit.tar"
$archive = Join-Path $OutDir $name

# A note inside the archive saying where it came from (cache\ is not tracked by git).
$note = @(
  'geo-report-gen data bundle',
  "Created: $(Get-Date -Format 'yyyy-MM-dd HH:mm') on Windows",
  "Code: commit $commit (use the same or a later commit on the receiving machine)",
  "Folders: $($folders -join ' ')",
  "Extract from the project folder:  tar -xf <path to $name>"
)
Set-Content -Path (Join-Path $root 'cache\BUNDLE.txt') -Value $note -Encoding ascii

Write-Host "Bundling $($folders -join ' ') from $root (this can take a few minutes for several GB)..."
$tarArgs = @('-cf', $archive, '-C', $root,
             '--exclude', '*.lock', '--exclude', '*.tmp-*', '--exclude', '*.download-*',
             '--exclude', '.DS_Store', '--exclude', 'Thumbs.db') + $folders
& $tar @tarArgs
if ($LASTEXITCODE -ne 0) { throw "tar failed (exit code $LASTEXITCODE)." }

$hash = (Get-FileHash -Algorithm SHA256 -Path $archive).Hash.ToLower()
Set-Content -Path "$archive.sha256" -Value "$hash  $name" -Encoding ascii

$bytes = (Get-Item $archive).Length
Write-Host ''
Write-Host ("Created {0} ({1:N1} GB)" -f $archive, ($bytes / 1GB))
Write-Host "Checksum in $archive.sha256"
if ($bytes -gt 4000000000) { Write-Host 'Note: over 4 GB, too big for a FAT32 USB drive; use exFAT or NTFS, or split it.' }
Write-Host ''
Write-Host 'On the other machine, from the project folder (after git pull):'
Write-Host "  tar -xf <path to $name>"
