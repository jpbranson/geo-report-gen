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
   is running; docs/data-sync.md. Delete scratch folders under reports/ first (it syncs).
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

## 2026-10-01 (Claude, Mac): public release review (before E15)

- The user asked for a release-readiness pass for the public 1.0 on GitHub: newcomer walkthrough
  from a clean clone, clarity of docs/code/CLI text, release blockers. No push, tag or publish.
- Resume point: audit in progress (README, CLI, docs, code, tests, secrets, license).
- 14:55 Baseline: tests 416 pass. Clean clone + Docker: no .env gives a clear Census-key error
  (README wrongly called every key optional); with keys, a cold build of madison-ms (IPUMS and
  FEMA files seeded) took 612 s, 771 requests, 1.05 GB, 0 warnings, and its report.qmd equals the
  warm one but for retrieval dates. Done: LICENSE (GPL-3.0, the user's choice); README quick
  start, keys table, License section; data-sync moved to docs/data-sync.md; build prints a
  "composing" line; snapshot sources (HRSA, Texas HHSC, Indiana FSSA) take their period from the
  retrieval year (they went blank every 1 January), with a test.
- Resume point: CLI argument checks, Census invalid-key message, provider and text fixes from
  the four reviews (list in the final report), then full test, catalog --check, batch.
- 15:20 Done since: CLI rejects unknown options and missing values, checks --workers/--formats
  and missing arguments (tests in test-cli.R); clear invalid-Census-key error; text-import keeps
  the import file whatever its name and checks for a build; verify survives a failing ACS recipe
  check; census counts compared at face value (MOE 0 made every difference "higher"); compare-mode
  distribution colors and legal-boundary note; FARS Connecticut metros and Kusilvak; LAUS for DC;
  QCEW contact check; Food Access Atlas Connecticut guard; render key includes content.R and
  blocks.R; wording in text.csv and the child care module; stale comments; compose.yaml binds
  preview to 127.0.0.1. Fresh image build from Dockerfile: 120 s, ok.
- Resume point: full test run, catalog --check, a batch rebuild of the samples to compare
  reports before/after, then the final report.
- 15:20 Verification: tests 438 pass (on an image built from scratch too); catalog --check clean.
  All 13 sample builds rebuilt offline in a scratch clone (copy of cache/ and reports/): the only
  differences are the intended wording fixes, the annexation note in tx-cities and the Connecticut
  reason in ct-capitol's food access block. The first batch with 4 workers had 3 compose
  processes killed for lack of memory (Docker's 8 GB), rebuilding derived tables after the
  provider edits; batch now reports such kills and README says to use --workers 2. The NDCP table
  (ndcp_long-ff43c37e, identical values) was built alone and copied into cache/ so the next build
  here does not hit that limit. Two misdirected runs (a backgrounded `cd`) built in this checkout
  instead of the clone; both were killed mid-compose and only added derived cache entries.
- Resume point: E15 (tag v1.0.0) on the user's go-ahead; open findings are in PLAN.md "After 1.0".
