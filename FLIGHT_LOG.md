# Flight log

Running record so work can resume after an interruption. Newest entries at the bottom. Read this
file and PLAN.md (status and what comes after 1.0) first; docs/REQUIREMENTS.md is the full brief.
The log of the sessions up to 1.0 is docs/history/FLIGHT_LOG.md.

## How to resume

1. Local settings: `.env` in the project root (git-ignored; read by R/load.R) holds
   `CENSUS_API_KEY`, `GR_HTTP_CONTACT` (the user's email, sent only to BLS), `DATA_GOV_API_KEY`
   (FBI Crime Data Explorer) and `IPUMS_API_KEY`. Never print or log the keys.
2. Windows PC: R 4.6.1 at `C:\Program Files\R\R-4.6.1\bin\Rscript.exe` with the renv library
   (activated by `.Rprofile`); Quarto from RStudio or Positron. Run from the project root with R
   4.6.1 explicitly: `& "C:\Program Files\R\R-4.6.1\bin\Rscript.exe" gr.R <command>`. The `Rscript`
   on the PATH is an older R without the project library.
3. Mac (Apple Silicon): the native R has no project library; everything runs in Docker from the
   project root: `docker compose run --rm gr <command>` (test, build, batch, verify, catalog
   --check, cache prune), and `docker compose run --rm --entrypoint Rscript gr <script.R>` or
   `... gr -e '<R code>'` for scripts such as demos/round_trip.R and tools/fingerprint.R. FEMA
   refuses downloads from Docker (HTTP 403), so `verify` reports fema_nri failed; its file must
   already be in cache/raw/fema_nri/. After `renv.lock` changes: `docker compose build`.
4. Moving cache/ and reports/ between the machines: `sh tools/data-sync.sh` (Mac) or
   `.\tools\data-sync.cmd` (Windows) syncs both ways with the Cloudflare R2 bucket, when no build
   is running; README "Moving the data". Delete scratch folders under reports/ first (it syncs).
5. Proving a refactoring changes nothing: `tools/fingerprint.R <before.rds>`, change, then
   `<after.rds>` and `--compare` (0 differences). Visual review: the charts are base64 images in
   reports/<id>/report.html and can be extracted into contact sheets.
6. Git: commit at milestones; reports/, cache/ and .env are ignored. Check the latest entry below
   for the resume point.

## 2026-10-01 (Claude, Mac): 1.0 checklist D11 and the tag

- D11: PLAN.md cut to the 1.0 status and the "After 1.0" list; the plan before 1.0, the running
  log and the two reviews of 2026-09-29 moved to docs/history/ (git mv); this file started fresh.
- Resume point: E15 (commit, tag v1.0.0 and push) on the user's go-ahead.
- 14:30 Documentation check (the user asked before E15): every path the docs name exists (bar
  the generated catalog.html); CLI usage, parser and README options agree; no stale counts or
  removed features in README, PLAN, FLIGHT_LOG, docs/sources.md, docs/nhgis.md or code comments.
  Fixed: catalog/catalog.qmd said Indiana child care capacity was only documented (it is
  implemented); README now states the count-block index rule that catalog --check enforces.
  catalog.html renders; tests 416. docs/REQUIREMENTS.md (the brief) and docs/history/ are records,
  left as they are.
- Resume point: E15 (tag v1.0.0, push) on the user's go-ahead.
