# Moving the data to another machine

The downloaded data (`cache/`, several GB) and rendered reports (`reports/`) are not in git. Keep
them in step through a Cloudflare R2 bucket with `data-sync`, or carry them in a tar file.

## Sync through Cloudflare R2

Run this on a machine when you start working there and again when you stop, while no build is
running:

```
sh tools/data-sync.sh                      # Mac or Linux
.\tools\data-sync.cmd                      # Windows (Command Prompt or PowerShell)
```

It syncs `cache/raw/`, `cache/geo/` and `reports/` both ways with rclone's `bisync`: new, changed
and deleted files on either machine reach the other. `cache/metrics/` stays local (builds
recompute it), as do lock files and partial downloads; `tools/data-sync-filters.txt` holds the
rules. Safeguards:

- Files the sync deletes or overwrites in the bucket are moved to `trash/<date-time>/` in the
  bucket, kept 30 days by the lifecycle rule below. To restore, copy them back into the project
  folder and sync again: `rclone copy gr-r2:geo-report-data/trash/<date-time> .`
- A file changed on both machines keeps the newer copy; the other becomes `<name>.conflict1`.
- A run that would delete more than half the files stops; add `--force` if that is intended.
- The first run on a machine merges both sides without deleting anything.

Other `rclone bisync` options can be added, e.g. `--dry-run` to see what would change. If rclone
stops and asks for a resync (after `data-sync-filters.txt` changes, or a damaged state), run it
again with `--resync-mode newer`, which merges both sides like a first run. The sync state is
kept in `.data-sync/` (git-ignored). `GR_SYNC_REMOTE` selects another bucket or rclone remote
(default `gr-r2:geo-report-data`).

One-time setup:

1. In the Cloudflare dashboard, turn on R2 (the free tier covers 10 GB with no download fees, but
   Cloudflare asks for a payment card) and create a bucket named `geo-report-data`. In the
   bucket's settings, add an object lifecycle rule: prefix `trash/`, delete objects 30 days
   after upload. With Cloudflare's `wrangler` CLI, the same is
   `npx wrangler r2 bucket create geo-report-data` and
   `npx wrangler r2 bucket lifecycle add geo-report-data trash-30-days trash/ --expire-days 30`.
2. R2 > Manage API tokens > Create API token: "Object Read & Write", applied to the
   `geo-report-data` bucket only. Note the access key ID, the secret access key and the S3
   endpoint (`https://<account id>.r2.cloudflarestorage.com`). One token per machine lets you
   revoke one without touching the other.
3. On each machine, install rclone 1.66 or later (`brew install rclone` on a Mac;
   `winget install Rclone.Rclone` on Windows, then open a new terminal) and add the remote:

   ```
   rclone config create gr-r2 s3 provider=Cloudflare region=auto no_check_bucket=true endpoint=https://<account id>.r2.cloudflarestorage.com access_key_id=<key id> secret_access_key=<secret>
   ```

   The keys are saved in rclone's own configuration in your user profile, never in the project.
   (`rclone config` asks for the same settings one by one and keeps the keys out of your shell
   history.)
4. Run `data-sync` first on the machine with the most data: it uploads everything (about 6 GB).

## Tar bundle

To carry the data on a drive instead, bundle it into one tar file in your Downloads folder, then
extract it in the other machine's project folder after `git pull`:

```
sh tools/bundle-data.sh                    # Mac or Linux
.\tools\bundle-data.cmd                    # Windows (Command Prompt or PowerShell)
tar -xf <path to geo-report-data-...tar>   # on the receiving machine, from the project folder
```

The archive (`geo-report-data-<date>-<commit>.tar`, with a `.sha256` checksum next to it) never
contains `.env`: copy your keys separately or create `.env` again. Options: `--no-reports` /
`-NoReports` to leave out `reports/`, and an output folder (`-OutDir <folder>` on Windows). Cached
files are keyed by the code's content and line endings are fixed to LF, so the receiving machine
reuses them at the same or a later commit; the first `gr.R batch` there should make no requests
for data already bundled. A bundle over 4 GB does not fit on a FAT32 USB drive (use exFAT or NTFS).
