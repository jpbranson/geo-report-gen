#!/bin/sh
# Bundle the data cache and rendered reports into one tar file, to move them to another machine
# (Mac, Linux or Windows; see docs/data-sync.md).
#
#   sh tools/bundle-data.sh [--no-reports] [output-folder]
#
# Writes <output-folder, default ~/Downloads>/geo-report-data-<date>-<commit>.tar and a .sha256
# next to it. The archive holds cache/ and reports/ as they sit in the project folder, never
# .env (API keys). Lock files, partial downloads and macOS metadata are left out. Windows uses
# tools\bundle-data.cmd, which writes the same archive.
set -eu

root=$(cd "$(dirname "$0")/.." && pwd)
reports=yes
out_dir="$HOME/Downloads"
for arg in "$@"; do
  case "$arg" in
    --no-reports) reports=no ;;
    -h | --help) sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    -*) echo "Unknown option $arg (use --no-reports or an output folder)." >&2; exit 2 ;;
    *) out_dir=$arg ;;
  esac
done

if [ ! -d "$root/cache" ]; then
  echo "No cache folder in $root: nothing to bundle." >&2
  exit 1
fi
mkdir -p "$out_dir"
out_dir=$(cd "$out_dir" && pwd)
folders=cache
if [ "$reports" = yes ] && [ -d "$root/reports" ]; then folders="cache reports"; fi

commit=$(git -C "$root" rev-parse --short HEAD 2>/dev/null || echo unknown)
name="geo-report-data-$(date +%Y%m%d-%H%M)-$commit.tar"
archive="$out_dir/$name"

# A note inside the archive saying where it came from (cache/ is not tracked by git).
cat > "$root/cache/BUNDLE.txt" <<EOF
geo-report-gen data bundle
Created: $(date '+%Y-%m-%d %H:%M %Z') on $(uname -s)
Code: commit $commit (use the same or a later commit on the receiving machine)
Folders: $folders
Extract from the project folder:  tar -xf <path to $name>
EOF

echo "Bundling $folders from $root (this can take a few minutes for several GB)..."
if [ "$(uname -s)" = Darwin ]; then
  # Without these, macOS adds ._ metadata files that turn up as clutter on Windows.
  COPYFILE_DISABLE=1 tar -cf "$archive" -C "$root" --no-mac-metadata \
    --exclude '*.lock' --exclude '*.tmp-*' --exclude '*.download-*' --exclude '.DS_Store' $folders
else
  tar -cf "$archive" -C "$root" \
    --exclude '*.lock' --exclude '*.tmp-*' --exclude '*.download-*' --exclude '.DS_Store' $folders
fi

if command -v shasum >/dev/null 2>&1; then sum=$(shasum -a 256 "$archive"); else sum=$(sha256sum "$archive"); fi
echo "${sum%% *}  $name" > "$archive.sha256"

size=$(du -h "$archive" | cut -f1)
echo ""
echo "Created $archive ($size)"
echo "Checksum in $archive.sha256"
if [ "$(wc -c < "$archive")" -gt 4000000000 ]; then
  echo "Note: over 4 GB, too big for a FAT32 USB drive; use exFAT or NTFS, or split it."
fi
echo ""
echo "On the other machine, from the project folder (after git pull):"
echo "  tar -xf <path to $name>"
