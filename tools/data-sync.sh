#!/bin/sh
# Sync the downloaded data and rendered reports with a Cloudflare R2 bucket, both ways
# (see README "Moving the data to another machine").
#
#   sh tools/data-sync.sh [rclone bisync options, e.g. --dry-run]
#
# Syncs cache/raw, cache/geo and reports (rules in tools/data-sync-filters.txt) with the rclone
# remote in GR_SYNC_REMOTE, default gr-r2:geo-report-data. New, changed and deleted files on
# either side reach the other; a file changed on both sides keeps the newer copy. Files the sync
# deletes or overwrites in the bucket are moved to its trash/ folder first. Run it while no build
# is running. Windows uses tools\data-sync.cmd, which does the same.
set -eu

root=$(cd "$(dirname "$0")/.." && pwd)
remote=${GR_SYNC_REMOTE:-gr-r2:geo-report-data}
work="$root/.data-sync"
if ! command -v rclone >/dev/null 2>&1; then
  echo "rclone was not found: install it with  brew install rclone  (see README)." >&2
  exit 1
fi

# No listings from an earlier run: first sync on this machine, so merge both sides, the newer
# copy winning where they differ. Nothing is deleted.
if ! ls "$work"/*.path1.lst >/dev/null 2>&1; then set -- --resync-mode newer "$@"; fi

# --checkers 32: reading a file's time from the bucket takes one request per file.
status=0
rclone bisync "$root" "$remote" \
  --filters-file "$root/tools/data-sync-filters.txt" --workdir "$work" \
  --backup-dir2 "$remote/trash/$(date +%Y%m%d-%H%M%S)" \
  --conflict-resolve newer --resilient --recover --checkers 32 -v "$@" || status=$?
if [ "$status" -eq 7 ]; then echo "rclone asked for a resync: run  sh tools/data-sync.sh --resync-mode newer" >&2; fi
exit "$status"
