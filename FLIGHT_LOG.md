# Flight log

Running record so work can resume after an interruption. Newest entries at the bottom.
Read this file, `PLAN.md` (checklist) and `docs/REQUIREMENTS.md` (the full brief) first.

## How to resume

1. Environment: R 4.6.1 at `C:\Program Files\R\R-4.6.1\bin\Rscript.exe`; project library via renv
   (`renv/`, activated by `.Rprofile` when R starts in the project root). Quarto 1.9.38 at
   `C:\Program Files\RStudio\resources\app\bin\quarto\bin\quarto.exe` (also Positron's 1.10.18).
2. Census API key: `census_key.txt` (git-ignored, `CENSUS_API_KEY=...`). Never print or log it.
3. Run things from the project root with R 4.6.1 explicitly:
   `& "C:\Program Files\R\R-4.6.1\bin\Rscript.exe" gr.R <command>` (PowerShell). The `Rscript` on PATH
   is a rig shim for R 4.3.2, which has no project library and fails (`no package called 'dplyr'`).
4. Check the latest entry below for "Next steps".

## Standing facts (verified 2026-09-28)

- Census Data API **requires a key for every request** (keyless -> 302 to `missing_key.html`).
- ACS 5-year API: releases 2009-2024; `group(TABLE)` returns E/EA/M/MA + GEO_ID + NAME.
  Non-overlapping periods used for trends: 2005-09, 2010-14, 2015-19, 2020-24.
- Place-by-county parts (summary level 155): `for=county (or part):*&in=state:SS place:PPPPP`
  works, but the place cannot be a wildcard (one request per place).
  Austin city TX parts (2020-24): Travis 912,870; Williamson 65,693; Hays 976; Bastrop 0 (MOE 15).
  Gary city IN: single part, Lake County (68,113).
- Nationwide `for=place:*` works (32,330 places, 1.6 MB). Nonexistent geography -> HTTP 204.
- Decennial via API: 2000/2010 `dec/sf1` (P001001), 2020 `dec/pl` & `dec/dhc` (P1_001N).
  Gary: 102,746 (2000), 80,294 (2010), 69,093 (2020).
- Keyless bulk alternative exists (ACS table-based summary files 2021+, 2019/2020 prototypes,
  older sequence-based) but is not used; documented as an alternate route.
- ACS guidance captured: handbook ch.7/8 formulas (sum, proportion incl. negative-radicand
  fallback and P=1 case, ratio, percent change, product), z-test 1.645, controlled estimates
  (MOE `*****`) -> SE 0, `**`/`***` -> no statistical test; census counts SE 0; multiyear
  tabulation uses final-year boundaries; dollars adjusted to final year with national CPI-U.
  Overlapping-period adjustment sqrt(1-C) from the Multiyear Accuracy of the Data (2012-2017).
  No official MOE method for medians of aggregated areas -> interpolate from published bins,
  label "MOE not computed" (Variance Replicate Tables are the documented extension).
- renv install quirk: `s2` 1.1.13 had no Windows binary; installed binary 1.1.12 with
  `renv::install(c("s2","sf"), type = "binary")`.

## Log

### 2026-09-28 ~12:05-12:45 (session 1)
- Surveyed environment (empty dir), installed renv + 20 direct packages into project library,
  `git init` + `.gitignore` (no commits made; user has not asked for commits).
- Wrote `PLAN.md` (architecture + checklist).
- Dispatched 6 background research agents writing catalog rows (schema in
  `<scratchpad>/research/BRIEF.md`): childcare/education, economy, housing/demographics,
  health/food, civic/environment, cited history events. Outputs land in the session scratchpad
  (`...\9c50061e-...\scratchpad\research\*.csv|md`); copy into `catalog/_research/` when done.
- Wrote `R/core.R` (paths, run state, hashing, CSV I/O), `R/fetch.R` (HTTP via httr2 with
  retry/throttle/parallel, request log without secrets, locked atomic cache, census_key()),
  `R/providers/census.R` (ACS + decennial via API, scopes, special values).
- Next steps: geography module (spec parsing, index, relationships, unions, benchmarks),
  stats module, metric engine, then content/authoring, rendering, batch.

### 2026-09-28 ~12:45-13:55 (session 1, continued)
- All 6 research agents finished; raw outputs copied to `catalog/_incoming/` (merge into
  catalog/sources.csv + metrics.csv still TODO; map research ids to provider ids:
  dol_wb_ndcp->dol_ndcp, fhfa_hpi_annual->fhfa_hpi, tx_hhsc_ccl_operations->tx_hhsc,
  nber_census_cencounts_1900_1990->census_hist, census_pep_* totals/intercensal->census_pep,
  census_dec_*->census_dec, census_acs_5yr/census_acs->census_acs5, census_cartographic_boundaries
  & census_cbsa_delineations->census_geo). History events installed in content/history_events.csv.
- Engine written: geography.R (graph, unions, benchmarks), stats.R, metrics.R, blocks.R, charts.R,
  maps.R, theme.R, content.R, compose.R, authoring.R (harvest/export/import), build.R, cli.R,
  runtime.R, quarto/gr-placeholders.lua. Providers: census (ACS, decennial), pep (PEP + 1900-1990
  county counts via NBER copy), bea (CAINC1), fhfa_bps (FHFA HPI, building permits), childcare
  (NDCP, CBP 624410, Texas HHSC capacity), bls (CPI/R-CPI-U-RS + LAUS; need GR_HTTP_CONTACT).
- Gary report builds and renders (reports/gary-in/report.html). Dev preview server: .claude/launch.json
  ("reports", node static server in scratchpad serve.js, port 8765).
- Key design facts learned: Quarto converts labeled figures to crossref nodes before user filters,
  so fig-cap/fig-alt placeholders are filled by knitr opts_hooks (runtime.R); prose/headings via Lua.
- OPEN QUESTION to user: may BLS contact email (GR_HTTP_CONTACT) be jpbranson@gmail.com? Until
  answered, CPI (constant dollars) and LAUS are unavailable (reports degrade gracefully).
- Next: Austin/unions/compare builds; batch runner; custom module; catalog merge + HTML page;
  verify command; tests; README; demos (inline/bulk edit round trip, theme change); benchmarks.

### 2026-09-28 ~13:53-14:11 (session 1, not logged at the time; reconstructed at 14:15 by session 2 from file timestamps and batch logs)
- Wrote R/batch.R (4 workers, per-report failure isolation, logs in reports/_batch/),
  modules/childcare_gap.R (custom module, inserted via profiles/early-childhood.csv, used by austin-tx),
  config/manifests/lake-in.csv. All 10 config/reports.csv entries (12 builds) now exist.
- Batch 14:02: 6/12 ok. Failures: pretty_years() axis breaks (travis-austin, in-cities-1836003/-1871000),
  unknown placeholders {first_period} (ct-capitol) and {metric_label_lower} (lake-in), austin-78704
  (the intended overlap rejection). 92 requests, 473 cache misses.
- Fixed (charts/blocks/text.csv, 14:05-14:06). Batch 14:06: 11/12 rendered; only austin-78704 failed (intended).
  Warm: 0 requests, 1,499 hits / 1 miss, 89 s total (compose 38.7 s, render 50.1 s; Quarto render
  ~14-19 s per report is the largest per-report cost).
- After that batch: R/maps.R edited 14:08 (rendered reports predate it). Catalog merged:
  subjects.csv (17 subjects, 82 subtopics), sources.csv (120; doc_status all verified; sample_status
  96 retrieved / 15 not attempted / 6 need registration / 3 failed), metrics.csv (398 rows);
  48 computable recipes, 41 blocks. R/catalog.R written 14:10 (catalog --check/--html, verify_sources),
  but catalog/catalog.html and catalog/verification_log.csv do not exist yet. R/content.R edited 14:11
  (last change). All 26 R files parse (5,278 lines).
- Small bug: batch log field `rendered` counts attempted renders (R/batch.R:53); the 14:02 log says 9, but only 6 succeeded.
- Still open: GR_HTTP_CONTACT unset (BLS CPI/LAUS unavailable); no renv.lock (renv reports out-of-sync);
  no tests/, no README, no git commits; PLAN.md boxes never ticked; stray acs_5yr_dir.html at root.
- Next: re-run batch to confirm the 14:08/14:11 edits; catalog --check/--html; verify; tests; demos 6-11;
  cold/warm/resume benchmarks; README; renv::snapshot(); cleanup; update PLAN.md checklist.

### 2026-09-28 ~14:12-14:27 (session 2: status review, no engine changes)
- Verified with R 4.6.1 on the latest code: `help`, `find`, `build gary-in --offline` (rendered 14:24 in
  25.3 s, 0 requests, 325 cache hits; harvest found no inline edits, content/text.csv untouched).
- `gr.R new` is in the usage text but `new_report()` does not exist ("could not find function");
  until it is written, add reports by editing config/reports.csv. Add to next steps: implement it.
- PATH `Rscript` = R 4.3.2 (rig default); `rig default 4.6.1` would fix it machine-wide (user's call).
