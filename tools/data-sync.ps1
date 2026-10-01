<#
Sync the downloaded data and rendered reports with a Cloudflare R2 bucket, both ways
(see docs/data-sync.md).

  .\tools\data-sync.cmd [rclone bisync options, e.g. --dry-run]

Syncs cache\raw, cache\geo and reports (rules in tools\data-sync-filters.txt) with the rclone
remote in GR_SYNC_REMOTE, default gr-r2:geo-report-data. New, changed and deleted files on
either side reach the other; a file changed on both sides keeps the newer copy. Files the sync
deletes or overwrites in the bucket are moved to its trash/ folder first. Run it while no build
is running. On a Mac or Linux, tools/data-sync.sh does the same.
#>
$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$remote = if ($env:GR_SYNC_REMOTE) { $env:GR_SYNC_REMOTE } else { 'gr-r2:geo-report-data' }
$work = Join-Path $root '.data-sync'
if (-not (Get-Command rclone -ErrorAction SilentlyContinue)) {
  throw 'rclone was not found: install it with  winget install Rclone.Rclone  and open a new terminal (see README).'
}

# --checkers 32: reading a file's time from the bucket takes one request per file.
$opts = @('--filters-file', (Join-Path $root 'tools\data-sync-filters.txt'), '--workdir', $work,
          '--backup-dir2', "$remote/trash/$(Get-Date -Format 'yyyyMMdd-HHmmss')",
          '--conflict-resolve', 'newer', '--resilient', '--recover', '--checkers', '32', '-v')
# No listings from an earlier run: first sync on this machine, so merge both sides, the newer
# copy winning where they differ. Nothing is deleted.
if (-not (Test-Path (Join-Path $work '*.path1.lst'))) { $opts += @('--resync-mode', 'newer') }

& rclone bisync $root $remote @opts @args
if ($LASTEXITCODE -eq 7) { Write-Host 'rclone asked for a resync: run  .\tools\data-sync.cmd --resync-mode newer' }
exit $LASTEXITCODE
