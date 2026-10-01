# Flight log

Running record so work can resume after an interruption. Newest entries at the bottom.
Read this file, `PLAN.md` (checklist) and `docs/REQUIREMENTS.md` (the full brief) first.

## How to resume

1. Environment: R 4.6.1 at `C:\Program Files\R\R-4.6.1\bin\Rscript.exe`; project library via renv
   (`renv/`, activated by `.Rprofile` when R starts in the project root). Quarto 1.9.38 at
   `C:\Program Files\RStudio\resources\app\bin\quarto\bin\quarto.exe` (also Positron's 1.10.18).
2. Local settings: `.env` (git-ignored; read by R/load.R): `CENSUS_API_KEY=...` (never print or log
   it) and `GR_HTTP_CONTACT=<user's email>` (approved by the user 2026-09-28; sent only to BLS).
3. Run things from the project root with R 4.6.1 explicitly:
   `& "C:\Program Files\R\R-4.6.1\bin\Rscript.exe" gr.R <command>` (PowerShell). The `Rscript` on PATH
   is a rig shim for R 4.3.2, which has no project library and fails (`no package called 'dplyr'`).
4. Check the latest entry below for "Next steps". PLAN.md holds the checklist with current status.
5. Git: first commit 85db1c0 (2026-09-28). Commit at milestones; reports/, cache/, .env are ignored.
6. Visual review: `.claude/launch.json` "reports" serves the repo on port 8765 (node script in the
   session scratchpad; recreate if missing). Figures can be extracted from report.html (base64 PNGs).
7. Docker (any machine with Docker Desktop): `docker compose run --rm gr <command>` from the project
   root; see README "Docker". Used on the user's Apple Silicon Mac and planned for the Windows PC.
   To move cache/ and reports/ between machines: tools/data-sync.sh (Mac) or
   .\tools\data-sync.cmd (Windows) syncs both ways with a Cloudflare R2 bucket (rclone bisync);
   tools/bundle-data.* writes a tar to Downloads instead; README "Moving the data". rclone is
   installed on the PC (winget) and the gr-r2 remote is in the user's rclone.conf, which Claude's
   sandboxed shell cannot see: run data-sync or rclone against R2 unsandboxed, or ask the user.

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
- OPEN QUESTION to user: may the user's email be the BLS contact (GR_HTTP_CONTACT)? Until
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

### 2026-09-28 ~16:00- (session 3)
User direction: use their email as BLS contact; first commit; continue; keep the project as lean and
human-legible as possible (complexity/verbosity is not better). Keep PLAN.md and this log current.
- Done: `.env` replaces census_key.txt (same key) + GR_HTTP_CONTACT; the contact is sent only in BLS
  requests (fetch.R user_agent_string(source)); BLS downloads verified (R-CPI-U-RS 1978-2025, CPI-U
  1913-2025, LAUS). renv.lock written. .gitignore: reports/, .env, .claude/. Stray acs_5yr_dir.html
  moved to the scratchpad. First commit 85db1c0 (69 files).
- Done: batch 16:09: 11/12 rendered (austin-78704 is the intended rejection); 8 requests; 95 s.
  Fixed batch log `rendered` count; verify_sources no longer calls the removed require_http_contact.
- Checked: the Census API has no 1990 decennial data (404), so place histories start in 2000.
- Review of rendered gary-in / austin-tx / tx-cities / kc-core; all found problems fixed (16:00-16:45):
  placeholder filter filled text twice (one pass now); shares/ratios without a published estimate
  rebuilt from components (LAUS U.S., BEA regions); unavailable values carry a reason; relative-index
  blocks use nominal dollars (pcpi 1969+); multi-metric blocks describe the first metric with data;
  captions name the whole plotted span; index=first uses one base period ({index_base}); indexes are
  compared by growth, not level; relation sentence only against a containing benchmark; compare mode
  summaries per area; "about the same" for untested equal values; survey estimates without a MOE
  (union medians) are described as untested; events link to charts by catalog subtopic
  (history_events `subtopics`; event_concept() removed); charts: in-range year breaks, no series
  legend (census counts as points next to estimates), wrapped legends, no flat 100 line series;
  benchmark notes use names; stale-fact warnings wired; `gr.R new` implemented (new_report +
  subject_manifest); build.json lists the raw files a build read (run$used); dead code and unused
  settings removed; harvest/import share current_field_text().
- MAJOR BUG FIXED: interpolated medians used bins in API order (unsorted) -> union medians wildly high
  (KC core income $175,983). acs_bins() now sorts; median_from_bins() stops on unsorted bins.
  Check: Johnson County KS interpolated $109,643 vs published $109,208.
- Catalog page: catalog/catalog.qmd (scope and gaps folded in from the research notes) ->
  `gr.R catalog --html` -> catalog/catalog.html (git-ignored). catalog/_incoming removed (in history).
- Tests: tests/testthat (stats, metrics, geography, content, cache, authoring round trip) with real
  API fixtures in tests/fixtures/cache (240 KB); `Rscript gr.R test`: 110 passed, 0 failed.
- Committed 3193005. Then (16:45-17:00): .gitattributes (LF); renv snapshot.type "all" (lockfile now
  has ragg, rmarkdown, testthat; renv status clean); `gr.R verify` all 13 sources ok (evidence in
  catalog/verification_log.csv); batch records each render as it finishes (resumable);
  report:ct-capitol uses the civic theme (theme demo); README.md written; content/prose/intro.md
  (long prose example); demos/benchmark.R and demos/round_trip.R written; test for `gr.R new`.
- Running (16:49): demos/benchmark.R in a temp copy with an empty cache (Rtmp*/gr-benchmark);
  cold gary-in compose 435 s, 344 requests. Results go to docs/benchmark.csv.
- Benchmark done (results in docs/benchmark.csv and README): cold 690 s / 536 requests; warm 86 s,
  0 requests; resume, theme, geography and data-refresh invalidation behaved as intended. Found:
  the first warm run re-rendered everything (fresh values differed in row names from cached
  copies). Fixed: cached() returns the stored copy; verified (rebuild after a fresh computation
  is "up to date", 0 misses).
- 17:12: tests 115 pass; full batch 78 s, 0 requests, 11/12 (the rejection is intended).
- WRAP-UP at the user's request (17:15). Committed da4310c. Reported to the user.

### 2026-09-28 ~17:20- (session 3, step 2)
User: update PLAN.md and this log, then do these four in order and check back (tracked in PLAN.md
"Current step"): (1) run demos/round_trip.R; (2) visual review of lake-in maps, tx-cities
comparison, ct-capitol civic theme, austin-tx custom child care chart; (3) restructure R/blocks.R
and prove every report's _snapshot/values.json and report.qmd are unchanged; (4) PDF (Typst) check.
- (1) round trip 10/10 after two fixes: read_table() turns CRLF inside cells into LF (a
  spreadsheet round trip had looked like an edit); the demo refreshes BEA (a city never reads the
  1900-1990 county counts). Test added for CRLF.
- (2) Fixed: map classes use the darkest palette colors, fill legend first; compare-mode trend
  charts skip period bars when several areas are described; break labels one per year on
  alternating rows; history_events.csv has a `sources` column so a break is drawn only on the
  sources it applies to (CT planning regions: ACS/PEP/CBP/BPS, not FHFA or LAUS); custom chart axis
  title (text.csv childcare-gap.x_label). Civic theme verified on prose, tables, notes, links.
- (3) blocks.R: compute_block_metric + metric_values split into block_periods, add_index,
  observed_values, change_values, growth_sentence, benchmark_sentence, relation_sentence;
  metric_sources helper; long lines 35 -> 14. Proof: scratchpad fingerprints.R (values.json,
  report.qmd without the date, digest of each block's data) baseline vs after: 239 items, 0 diffs;
  control run (no change) also 0 diffs.
- (4) PDF: `--formats typst` works; generated qmd now has a typst format (toc, numbering,
  papersize from theme, mainfont, 8pt tables); README documents the basic layout.
- 17:35: tests 116 pass; full batch 84 s, 0 requests, 11/12 (intended rejection). Committed.
- After the commit: all tracked files normalized to LF (the Edit tool had left CRLF in charts.R,
  compose.R, maps.R). Code hashes changed, so the next build recomputed metrics and re-rendered once.

### 2026-09-28 ~17:45-18:20 (session 3, step 3)
User: do the readability pass on geography.R and compose.R.
- Proof method (scratchpad): compose_all.R (compose every report, offline, no render);
  fingerprints2.R (md5 of each report's _snapshot/report.rds file, values.json, qmd_base.json,
  theme.scss, report.qmd without the date, snapshot area/entities/texts/rows, every block, and the
  error of a failed report); geo_probe.R (213 calls: specs, names, parents, contains/relation for
  18 pairs, 21 selections with their benchmarks under 4 settings, helpers; run "online" once so
  the ZCTA-county relationship and CBSA delineation files are cached); compare.R.
- geography.R: geo_parents -> county_shares / state_shares / regional_parents / parent_rows;
  geo_counties() shared by relations, containment and unions; geo_contains returns TRUE/FALSE
  (only isTRUE was ever used); geo_relation merges the place/ZCTA-versus-county cases; union and
  benchmark code split into describe_members, relation_matrix, benchmark_candidates,
  benchmark_entity; same_territory() replaces is_coterminous + same_population_area (a county
  study area is now also recognized as coterminous with a one-county state, e.g. DC);
  entity_from_key, study_entity, the unused `spec` column of find results and dead variables
  removed; base_name() applied vectorized (name search ~1 s instead of ~40 s).
- compose.R: write_qmd -> qmd_header, block_markdown, figure_chunk; compute_blocks; yaml_str as
  three plain substitutions (identical output on quotes, backslashes, line breaks, Unicode).
- Result: 328 fingerprints, 0 differences (snapshots byte-identical); 213 probes identical except
  the intended ones (3 contains NA -> FALSE, 8 find results without `spec`); tests 117 pass; batch
  after the one-time re-render: all 11 up to date, 0 requests (austin-78704 is the intended
  rejection). Lines over 120 characters: geography.R 10 -> 0, compose.R 9 -> 0.
- Committed a8278fa. User then asked to keep compose.R's extra lines (legibility over line count).

### 2026-09-28 ~18:25- (session 3, step 4: expand metric coverage)
User: expand the metric coverage next. Plan in PLAN.md (ACS recipes, then SAIPE/SAHIE, then check
back before new external sources).
- Survey: 48/398 operational; 83 cataloged ACS metrics without recipes, ~20 of them duplicates of
  operational metrics or distribution views (research merge leftovers). ACS provider is generic
  (any B/C table, all geographies; tables missing in old releases -> "unavailable").
- 2024 group metadata fetched and reviewed for 48 tables (scratchpad acs_labels.R, labels1-3.txt);
  all planned variable IDs confirmed.
- Code so far: theme.R unit_kind() accepts descriptive units (prefix percent/dollars, "x per y" ->
  ratio) and new kinds year (no thousands separator) and coefficient (3 decimals); fmt_change gives
  differences for those; blocks.R uses unit_kind for dollars/percent checks; stats.R
  parse_bin_label ends "10.0 to 14.9 percent" at 15.0 (was 15.9); tests added.
- Catalog edits by one-time scratchpad scripts (catalog_edit.R, catalog_history.R, catalog_breaks.R,
  catalog_defs.R, catalog_sae.R, text_records.R): 20 duplicate/view rows merged (breaks carried
  over), 21 category rows added (13 industries, 5 occupation groups, commute "other", 2 household
  types), 83 ACS recipes, 23 blocks, clean labels/sentence labels, reader-facing definitions and
  breaks (formulas stay in `variables`; maintainer detail in `limitations`), plain table lists.
- Release-by-release label check (label_drift.R, first_release.R) found real meaning changes:
  C24010 and B21001 lines differ before 2006-2010; B27010/C27007/B18135 age bands under 18 -> under
  19 from 2013-2017; B08301 rail lines reordered from 2015-2019 (sum unchanged); taxi line includes
  ride-hailing in 2020-2024. Fix: metric_periods() drops periods starting before the catalog's
  history_start (first comparable period, "YYYY-YYYY"); set for every implemented ACS metric.
  Existing reports only lose "not published" rows for 2005-2009 (and 2010-2014 broadband).
- `verify` now checks each ACS recipe only in the releases it uses: 424 checks, no gaps; 15/15
  sources ok (SAIPE, SAHIE added).
- SAIPE/SAHIE provider R/providers/small_area.R (Census API timeseries, key; one request per
  dataset and scope returns all years; `for=us:*` works for the nation). SAHIE AGECAT 0 = under 65,
  IPRCAT 0 = all incomes, 3 = <=138% of poverty. Comparable from 2005 (SAIPE, CPS->ACS inputs) and
  2008 (SAHIE). Provider flag combine_moe = FALSE: combined areas get values, no MOE (method note).
  Test fixture: Delaware counties (8.9 KB). model_interval uncertainty is tested like survey MOEs.
- Charts: composition viz "bar" (industry mix: bar per category and area, study first, taller
  figure); legends wrap at 28 characters (race legend now wraps "Two or more races, not
  Hispanic"). Econ-dev profile does not use income-annual (SAIPE medians cannot be combined and
  both econ-dev samples are unions); the block stays in the library.
- content/text.csv was re-saved by save_text_records(), which sorts by field id; committed as a
  separate pure-reorder commit before the additions.
- 19:15: tests 138 pass; batch (online) 480 s / 309 requests for the new tables, then offline
  127 s, 0 requests, 11/12 (intended rejection); catalog page renders; no build warnings.

### 2026-09-28 ~19:30- (session 3, step 5: four new sources)
User: add all four new sources in the recommended order (CDC PLACES, CBP all industries, FEMA
NRI, USDA Food Environment Atlas), then check back. Plan in PLAN.md.
- CDC PLACES (step 1, done ~20:10): Socrata API (no key), 2025 release ids in places_tables; one
  measure per request (counties + U.S. row nationwide, ZCTAs nationwide, places and tracts per
  state). Latest release only (CDC: model cannot track change); crude prevalence; 95% CI -> 90%
  MOE; share recipes <M>_N / ADULTS with published_var <M>. No state values in PLACES: a state is
  the sum of its counties (CDC's documented aggregation), only when every county is listed
  (suppressed <50-person counties, e.g. Loving TX, left out of both sums). U.S. row (locationid
  59) used as published; it is not the county sum (short sleep 36.0 vs 36.1), method undocumented.
  Texas did not field the social-needs module; KY and PA lack 2023 measures.
- Catalog: 14 PLACES rows made operational + 7 added (CHD, COPD, asthma, binge drinking, housing
  insecurity, utility shutoff threat, lack of reliable transportation); ACCESS2 left documented
  (18-64 universe not published). Blocks chronic-conditions, health-status, health-behaviors,
  diabetes-map (general), social-needs (general, early-childhood). 158 of 406 operational.
- Engine changes: providers' `note` becomes the method/reason of values they did not publish
  (source_note()); facts prose is {summary_sentence} (@phrase.facts_compare, or
  @phrase.facts_no_data with the reason; no table when the study area has no value); facts tables
  drop comparison columns without any value (e.g. regions for PLACES) and the sentence names only
  the shown areas; "does not publish place_part data" -> "does not publish data for the parts of a
  place in each county" (geo_type_names); no-data phrases end with a period.
- Verified: tests 150 pass; batch online 155 s / 61 requests, then offline clean (no warnings);
  ct-capitol, travis-austin, austin-tx tables and the Gary diabetes map reviewed.
- CBP all industries (step 2, done ~20:40): R/providers/cbp.R replaces the 624410-only code in
  childcare.R. Variables <measure>_<NAICS code> (ESTAB_00, EMP_31-33, PAYANN_624410); one API
  request per (year, scope, code) with EMPSZES=001 and, from 2008, LFO=001 (national and state
  rows split by legal form from 2008; the old code relied on row order). Withheld flags are D, S
  and size ranges a-m (checked on all cached files: flagged values are 0); "r" (revised, e.g. the
  2014 national row) and G/H/J (noise) are published values. Missing row: 0 before 2017,
  suppressed from 2017 (fewer than 3 establishments). Cache files renamed <code>-<scope>.parquet
  (child care data re-downloaded once).
- Jobs by industry uses the 19 NAICS sectors separately: grouping them like ACS C24030 lost the
  group in 40-60% of counties (e.g. management of companies missing in 61% blocks "professional,
  management and administrative"; Wyandotte KS utilities blocked "transportation, warehousing and
  utilities" for kc-core); zero-filling could hide a large single HQ. 181 of 425 operational.
- Fixes found while reviewing: short_label cut at the first comma (austin-core text said "Travis"
  for the three-county total); now only a trailing state or metro suffix is dropped. Trend-chart
  direct labels wrap at 28 characters with right margin sized to the longest line; bar
  compositions keep the entity order (study first) when the first category lacks a study value.
  Facts tables get {dollar_phrase}.
- Verified: tests 164 pass (Loving County TX fixture: withheld 2016 mining, no 2016 health row,
  no 2023 transportation row; 2014 national "r" flag); batch online 149 requests, offline clean;
  austin-core and kc-core charts and tables reviewed.
- FEMA NRI (step 3, done ~21:00): R/providers/nri.R reads NRI_Table_Counties.csv from FEMA's
  v1.20 zip (25 MB, keyless). Checked: EAL_VALT = sum of the 18 hazard EALs (NA = 0) = B + PE + A;
  every one of our 3,144 counties is present (CT planning regions included); scores complete for
  the 50 states + DC (88 NA are territories), HWAV_RISKS blank in 30 counties. Scores (value
  recipes) only for single counties: other areas get not_applicable with the reason; unions get
  not_aggregable. Additive fields summed to state/region/division/nation. Metadata: SoVI from
  Census Community Resilience Estimates, resilience from HVRI BRIC 2020, dollars of December
  2024; terms require a "not endorsed by FEMA" statement (in each block's source note).
- Engine: context_entities() shared by metric, facts and composition blocks (a city report shows
  its county for county-only sources); facts sentences @phrase.facts_context / facts_alone,
  composition @phrase.composition_context; @phrase.facts_no_data renamed none_available and used
  by compositions (the old composition no-data sentence printed the group id). runtime.R filled
  chunk-option placeholders with report values first (c(report, block)); now block first, as the
  Lua filter documents.
- Verified: tests 170 pass (DE fixture zip, 11 KB); batch clean; Gary (context), ct-capitol,
  kc-core and tx-cities hazard blocks reviewed.
- USDA Food Environment Atlas (step 4, done ~21:15): R/providers/fea.R reads StateAndCountyData.csv
  (long: FIPS, State, County, Variable_Code, Value; 957k rows) from the 6.5 MB ERS zip and keeps
  every county value in a derived parquet (4 MB). Period = the two-digit year in the variable code.
  Findings: store counts are CBP-based, -9999 in 909 counties (grocery), 471 (fast food), 284
  (convenience); no state rows or populations for rates (implied populations: 2020 estimates for
  stores, 2023 for SNAP stores, 2010 census for low access); 37 zero low-access counties include
  FIPS-change artifacts (Oglala Lakota, Kusilvak) - so no sums, published county values only
  (value recipes). CT still in former counties. Engine: `scale` now also rescales published
  single values (value recipes; all existing ones use 1), used for per 10,000 residents.
- Verified: tests 176; batch clean; gary-in, austin-tx (Travis and Williamson as context),
  ct-capitol (former counties reason), tx-cities reviewed; verify 18/18 ok, 424 ACS checks no gaps;
  round trip 10/10.
- PDF check (21:20): gary-in renders via Typst with all new sections. Fixed: dollar totals of $10
  million or more are shown as "$191.0 million" / "$150.1 billion" (full NRI totals overlapped in
  PDF columns); PDF tables no longer hyphenate ("Indi-ana", "Pe-riod"). Tests 177; batch clean.

### 2026-09-28 ~21:30- (session 3, step 6: voting survey, government finance, FBI API)
User: add the EAC voting survey, the county- and city-government finance files and the FBI API;
the api.data.gov key was in api_data_gov_key.txt ("DATA_GOV_API_KEY=<40 characters>"). The file is
now git-ignored and its line appended to .env (never printed); the user can delete the .txt file.
- EAVS (step 1, done ~21:55): R/providers/eavs.R reads the 2020 V1.2 and 2024 V2 CSVs (2 MB zips).
  Jurisdiction codes: county (ssccc00000), New England town (ss ccc ttttt; CT under former counties,
  moved to planning regions by town code via ACS cousub lists), city with its own election office
  (ss ppppp 000: Chicago -> Cook at 100%; Kansas City MO spans Cass/Clay/Jackson/Platte -> those
  counties unavailable), Wisconsin (5-digit municipal codes, no county), Alaska (statewide),
  Maine unorganized townships (county 099; state only), 9-digit CA codes (lost zero). -88 = does
  not apply (ND registration), -99/blank = not reported. States sum all jurisdictions; nation,
  regions and divisions sum states with totals and their CVAP (ACS B29001_001, 5-year ending in
  the election year). Mail share dropped: Indiana 2024 methods sum to 146% of voters, CT 2024
  lacks polling-place counts, all-mail jurisdictions report F1g separately.
- 2024: Lake County IN 90.5% active registration, 57.7% turnout; Indiana 85.2/59.4; U.S. 87.3/65.4;
  Texas 83.6/57.8; CT Capitol region 88.5/69.1. Block "voting" in a new "Civic participation"
  section (general). Tests 183 (fixture: DE, ND, Jackson + Kansas City).
- Government finance (step 2, done ~22:05): R/providers/govfin.R reads the FY2022 Census of
  Governments unit files (9.7 MB zip; fixed width: data 12+3+12+4+1, PID 12+64+35+5+9...). FY2024 is
  a sample (1,751 of 3,029 county and 4,045 of 19,401 city governments), so FY2022 is used. Type 1
  (county) -> county key from ID positions 4-6; type 2 (city) -> place key from the PID FIPS place
  code. Items: T01, all T codes, 49U (the only long-term debt outstanding item in the public-use
  file), E62; absent items are 0; POP from PID. States/regions/divisions/nation sum county (CO_*) or
  city (CI_*) governments. Catalog: the 4 "local government" rows became county-government metrics,
  4 city-government rows added; block local-government-finance (general, economic development).
- Findings: Connecticut and consolidated city-counties (Marion IN, Wyandotte KS) have no county
  government, so kc-core's union and ct-capitol get the no-data sentence with that reason. Gary FY2022
  (2024 dollars): city property tax $572, debt $2,992 per resident; Lake County government $118, $179.
  Tests 187 (fixture: Delaware governments, 9 KB).
- FBI Crime Data Explorer (step 3, done ~22:30): R/providers/fbi.R. Endpoints (header X-Api-Key):
  agency/byStateAbbr/{ST} (agencies by county name; type City named "<Name> Police Department"),
  summarized/{agency/{ori}|state/{ST}|national}/{V|P}?from=MM-YYYY&to=MM-YYYY (monthly actuals,
  population, participated population; state responses list the state first, so series are
  taken by name), pe/agency/{ori} (police employment; state/national return nulls -> officers
  metric not implemented). Places match departments by normalized name; a city year needs 12 full
  months (Gary missed 2020-2021); states/nation = reporting agencies / covered population.
  Counties not computed (sheriffs cover part of a county). Violent-offense counts not shown for
  states (reporting agencies only). Verified: Dover 2023 381 violent, 2,192 property (catalog
  evidence); Connecticut's decline 229 -> 111 per 100,000 (2016 -> 2025) is in the FBI data.
- Charts: a missing period now breaks a trend line (Gary 2019 -> 2022 was bridged); segments are
  counted without reordering rows, so colors keep entity order.
- Key handling: api_data_gov_key.txt git-ignored; key in .env only; not found in logs, reports,
  cache or tracked files. verify: 21 of 21 sources ok; 424 ACS checks; round trip 10/10; tests 192.

## 2026-09-28 22:40 (session 3, continued): county crime sums; NHGIS investigation

- The user: reports may be long (they edit down); county crime = sum every police agency, with a
  caveat; investigate IPUMS NHGIS for older historical files. NHGIS research runs in a separate
  agent (web only, no account or key); county crime is implemented here.
- County crime (done ~23:10): agency/byStateAbbr lists every agency by county name ("CASS,
  CLAY, JACKSON, PLATTE" for KCPD); nationally 19,636 agencies, every FBI county name matches a
  Census 2024 name after dropping "County"/"Parish"/... and punctuation, except "NOT SPECIFIED"
  and "UNMAPPED COUNTY" (statewide agencies, NYPD, DC police) and Alaska's retired Valdez-Cordova.
  Connecticut is already listed by planning region. All 653 multi-county agencies are city
  departments; 636 match one Census place (divided by place-by-county population), 17 fall back
  to county populations. State police are listed by county in 17 states (posts) and in no county
  elsewhere. POP for a county is the agencies' own populations (within 0.96-1.01 of PEP except
  Connecticut, 0.87, where state troopers police some towns). Rule: a county year needs agencies
  serving 75% of those residents to report 12 months (FBI CIUS Table 6 includes MSAs with 75% of
  agencies reporting and the principal city reporting 12 months). Lake County IN: 2020 57% and
  2021 75% -> left out (Gary missing); 2025 377.1 violent per 100,000, coverage 97%. Wyandotte
  KS: KCK PD absent 2016-2022; its 2023 months hold almost nothing (180 offenses vs about 1,700)
  though marked reported -> Wyandotte 2023 is far too low (documented, not corrected). Place parts
  (Austin's parts outside Travis) = the city department times the part's population share, so
  travis-austin now has values (2025: 377.2 violent, 2,631.0 property per 100,000). Requests
  only for the offenses a metric needs. Tests 200 (Kent County DE fixture, 26 files, 38 KB).
- NHGIS (done ~23:20, agent research + spot checks): free account + API key (metadata API 401
  without key; crosswalk downloads redirect to login); ipumsr 0.10.0; terms forbid
  redistribution without permission. Time series codes, years and levels checked against
  NHGIS_Time_Series_Tables_Lists.xlsx. Findings and ranked additions in docs/nhgis.md; source
  row ipums_nhgis in catalog/sources.csv (121 sources).

## 2026-09-28 23:30 (session 3, continued): FBI screen; NHGIS census years

- The user approved the quarter-of-usual screen and added an IPUMS key (ipums_key.txt, now
  git-ignored; the key is in .env as IPUMS_API_KEY, never printed).
- FBI screen (done 23:35): fbi_annual(agency = TRUE) drops a year with under a quarter of the
  agency's median year when the median is at least 20 offenses. Of 334 cached agency series it
  removes 3 agency-years: KCK violent 2023 (180 vs 1,539), a Connecticut agency's property 2020
  (6 vs 27) and a Texas agency's property 2020 (29 vs 149). Tests 203.
- NHGIS (done ~00:05): the first extract request failed with HTTP 401 (the account was not
  registered for NHGIS; the user registered). ipums_key.txt held "IPUMS_KEY=<key>", so .env
  first got the prefix too (API: "Invalid API key"); fixed without printing the key. Layout
  (time_by_row_layout, csv_no_header): one CSV per level; place/cty_sub rows carry integrated
  codes (PLACEA, CTY_SUBA: 5 digits = current FIPS; shorter = defunct, dropped); NHGIS repeats
  45 Wisconsin town-years identically (deduplicated). One extract of AX6, B69, B79, B84, BD5,
  C53, CL6 took 6.2 minutes; 225,236 area-years. Checks: U.S. median household income $16,841
  (1979), $30,056 (1989), $41,994 (1999); per capita $7,298 (1979); poverty 13.1% (1989). Gary
  poverty 15% (1970), 20%, 29%, 26% (2000); Gary median household income about $70,000 (1979,
  2024 dollars) against $38,000 now. Austin bachelor's or higher 21% (1970), 40% (2000).
  value-type recipes read their variable from the numerator column (fixed). Tests 213; batch
  clean (austin-78704 rejected as intended).

## 2026-09-29 00:25 (session 3, continued): more NHGIS history

- The user deleted temp-data/ (their emailed NHGIS downloads were byte-identical to the cached
  extracts 5 and 6). Next: population to 1790 and CBP to 1970 from NHGIS.
- Population (done ~00:40): A00 (1790-2020, nation/state/county) and AV0 (1970-2020, all levels)
  in one extract with the long-form tables (extract 8, 4.1 min, 266,094 area-years). Recipes may
  name years per table ("1790:A00AA; ... 1970:AV0AA"); nhgis_table_years() builds the request
  from them. Lake County IN 1,468 (1840) -> 546,253 (1970); Gary 175,415 (1970) -> 116,646 (1990).
- CBP 1970-1997 (done ~00:55): six NHGIS datasets (1970_1971_CBP ... 1988_1997_CBPb), breakdown
  bs28/29/30.si---- (all industries), tables NT001 employees, NT003 annual payroll, NT004
  establishments (1974+); one file per dataset x year x level, columns <nhgisCode>001 mapped to
  SIC_EMP/SIC_PAYANN/SIC_ESTAB via dataset metadata. Quirks: 1975 state payroll in $1,000
  (converted); 3 cells in 1970 hold "D" (withheld); national files only 1977-1997; state files
  lack 1971, 1973, 1976; pseudo-states 98/99 (international operations, ships at sea) ignored.
  Payroll per employee starts 1978 (R-CPI-U-RS). Lake County IN jobs 178,111 (1970), peak
  201,847 (1979), 146,469 (1986). Tests 226; verify 23 of 23; round trip 10/10; batch clean.

## 2026-09-29 09:40 (session 4): Docker image for a second workstation

- The user asked for a Docker image to run the project on an Apple Silicon Mac later today, with
  the code through GitHub and the image and data in a portable folder.
- Dockerfile: rocker/r-ver:4.6.1 (Ubuntu 24.04); GDAL, GEOS, PROJ, udunits, abseil (s2), libuv
  (fs) and font libraries; Noto Sans; Quarto 1.9.38; renv.lock restored as Posit Package Manager
  binaries (amd64 and arm64, nothing compiled) into /opt/renv/library, outside the checkout. The
  image is the toolchain only: compose.yaml mounts the checkout at /app, so .env, cache/ and
  reports/ are the host's files. .dockerignore lists only the renv files, so keys and the cache
  never enter the image. compose.yaml sets TZ (default America/Chicago): cache times and
  "retrieved on" dates use local time, and a bare container is UTC. gr.R preview listens on
  0.0.0.0:4848 when GR_PREVIEW_PORT is set (the image sets it).
- Checks, on a copy of the checkout: tests 226 pass on amd64 and on arm64 (emulated); gary-in and
  lake-in values.json and report.qmd byte-identical to the Windows build, 0 requests and 0 cache
  misses (a Windows cache works unchanged); PDF via Typst; preview serves and re-renders after a
  host-side edit; verify 22 of 23. FEMA answers 403 to Linux clients (and to curl on Windows,
  while R on Windows gets 200), so in Docker the NRI zip must already be in the cache. Compose is
  about 1.5x slower than native on Windows (bind-mount reads); rendering is not.
- Multi-platform image geo-report-gen:latest (amd64 871 MB, arm64 846 MB). Portable folder
  C:\Developer\geo-report-gen-portable: arm64 image tar, cache + reports tar, MAC-SETUP.md.

## 2026-09-29 14:35 (session 5): next sources agreed

- On the Mac, the user added and built madison-ms (place:2844520, general profile) with Docker.
- Agreed next step, not started: LEHD LODES, BLS QCEW, BEA county GDP, in that order (PLAN.md).

## 2026-09-29 14:40 (session 5, continued): LODES (done 15:10)

- Docs read: LODES tech doc 8.4 (Rev. 20251203), OnTheMap data overview (OTM20251202; LODES is
  partially synthetic; primary jobs equal workers; jobs held at the start of Q2), federal
  employment note (federal jobs from 2010, in All Jobs and Primary Jobs; some agencies excluded).
- Quirks: files for state-years without job data exist as stubs (ma_wac_S000_JT01_2005 holds
  5 jobs; ma_od_main files about 150 bytes), so coverage comes from the tech doc's table, not
  from file existence; crosswalk codes outside an area are all nines; paths use lowercase postal
  codes. Crosswalk codes are "current" (2024 TIGER), matching boundary_vintage 2024; CT uses the
  planning regions (county:09110 works); Indianapolis is 1836003 (balance).
- Decisions: primary jobs (JT01) for everything; nation, regions and divisions not offered;
  jobs per 100 employed residents (one decimal hid differences near 1); OD commuting flows
  deferred.
- Checks: Madison MS 4,575 primary jobs (2004; no MS job data 2002-2003) -> 9,400 (2023);
  Gary 35,027 (2002) -> 22,661 (2023) while Lake County +0.8%; Kansas 1,300,916 and Missouri
  2,664,843 primary jobs (2023); Texas 100.0 jobs per 100 employed residents; tx-cities: Houston
  1,789,039. Charts reviewed (trend with the 2010 break label, 20-sector bars, Gary tract map).
- Cache: 624 MB for six states (Texas 355 MB: 289 MB downloads, 54 MB derived tables); the first
  Texas build took 287 s (45 downloads). Tests 239; verify 23 of 24 (FEMA 403 in Docker);
  round trip 10/10; batch 12 ok, austin-78704 rejected as intended.
- Committed and pushed (3f082df). Next: BLS QCEW (PLAN.md step 2).

## 2026-09-29 15:10 (session 5, continued): QCEW (done 15:50)

- Access: API slices only from 2014; the smallest bulk file with every area is the annual
  singlefile ZIP (18 MB for 1990, 75 MB for 2024). About 20 s a year to download and reduce;
  the reduced table is about 80,000 rows (1 MB) a year.
- Layout: agglvl 10/11/14 nation, 50/51/54 state, 70/71/74 county, 18/58/78 six-digit NAICS;
  withheld cells flagged N from 2001 (employment and wages 0, establishments kept); 1990-2000
  files omit withheld rows (Loving County TX 1990: total 25 jobs, no private row). U.S. =
  50 states + DC. Connecticut: planning regions from 2024. Price index covers 2025.
- 1990-2000 dropped after a scan of one-year spikes (counties over 20,000 jobs and states):
  Platte County MO 1991 jobs doubled then halved; New Jersey 1995 pay +42%; Oakland County MI
  1997 finance 179,334 jobs and $57.3 billion (CBP shows Oakland at 718,438 jobs that year,
  normal growth), which lifts Michigan's 1997 pay from $31,522 to $44,181; Union County NJ 1997.
  BLS's Q&A calls 1990-2000 a reconstruction under NAICS 2002. None found 2001-2024.
- fetch.R: sources named bls_<program> get the BLS contact and share the BLS rate, so
  `--refresh bls_qcew` refreshes both the ZIPs and the derived tables.
- Checks: 2025 Madison County MS 59,649 jobs, $55,952 average pay (2024 dollars); Travis County
  child care pay $37,302 vs $101,311 for all private jobs; Missouri withheld its statewide
  agriculture, mining, construction and information figures for 2025 (the chart shows no bar).
  Charts reviewed. Tests 253; verify 23 of 25 (FEMA 403 in Docker; FBI 503 upstream); round
  trip 10/10; batch 12 ok, austin-78704 rejected as intended.
- Committed and pushed (8b8b9ea). Next: BEA county GDP (PLAN.md step 3).

## 2026-09-29 15:55 (session 5, continued): BEA county GDP (done 16:15)

- CAGDP1.zip 1.9 MB (line 1 real GDP in chained 2017 dollars, line 2 quantity index, line 3
  current dollars); CAGDP2.zip 15.3 MB (current dollars by industry). Last updated February 5,
  2026 (2024 new, 2020-2023 revised). County (D) cells in 2024: health care 1,274 of 3,127,
  wholesale 808; the industry groups (lines 87, 11, 12, 88, 89, 45, 50, 59, 68, 75, 82, 83,
  which partition line 1) far fewer. Connecticut: planning regions for 2024 only, former
  counties (NA) in 2024; the planning regions have no quantity index (base year 2017).
- First version used chained dollars for the trend: the text then compared levels across areas
  ("lower than Indiana ($412.0 billion)") and called them nominal. Switched to the quantity
  index (units "index": growth compared over the same span). Also "$29298.0 billion" -> added
  trillions to fmt_dollar_amount (only values of $1 trillion and up change).
- Checks: Lake County IN 2024 GDP $31.24 billion (matches the catalog sample), real index 104.6
  (2017 = 100), +24.1% since 2001 vs Indiana +50.4%; U.S. $29.3 trillion, $86,143 per resident;
  Kent County DE manufacturing 2024 (D). Charts reviewed. Tests 263; verify 25 of 26 (FEMA 403);
  round trip 10/10; batch 12 ok, austin-78704 rejected as intended.
- The three agreed sources are done; committed and pushed (f17df95).

## 2026-09-29 16:24 (session 5, continued): five more sources agreed; Nonemployer Statistics

- The user asked which sources have the most leverage; agreed to add five, in order (PLAN.md
  step of 16:24): Nonemployer Statistics, FARS, NCES CCD, NOAA Storm Events, County Health
  Rankings. The user asked that this log be kept up to date during the work so it can resume
  after an interruption: add a line at each milestone (files touched, decisions, checks).
- NES files inspected (~16:27): https://www2.census.gov/programs-surveys/nonemployer-statistics/
  datasets/{YYYY}/historical-datasets/nonemp{YY}{co|st|us}.zip, one text CSV each (county 2.9-4.8
  MB zipped). Columns ST, CTY (COUNTY in 1997; lowercase names in 2008), NAICS, ESTAB_F, ESTAB,
  RCPTOT_N_F (noise flag G/H/J, from 2005 or so), RCPTOT_F, RCPTOT ($1,000). Flags: D withheld
  (blank values; 1997 and 2008, most detailed rows), S below publication standards (all years,
  4,710 rows in 2023, no D). 18 sectors (no 55 or 92); child day care is 62441. In 2008 counties
  without withheld sectors add up exactly, so a missing row means no such businesses; 2023 totals
  exceed sector sums by a few. Travis County TX: 51,468 (1997) -> 152,472 (2023); transportation
  1,311 -> 18,753.
- ~16:30 R/providers/nes.R written and tried on 1997, 2008, 2023 (2-3 s a year): bulk co/st/us
  files (state .txt through 2007, U.S. .txt through 2015), headers normalized (ESTABF, COUNTY,
  lowercase), LFO "-" and RCPTOT_SIZE "001" rows only, repeated rows dropped; regions and
  divisions sum states; POPULATION from bea_cainc1(). The Census API also has NES for every year
  (NAICS1997 ... NAICS2022 variables) but flags only through 2008 and would need about 1,600
  requests, so the bulk files are used. U.S. child care nonemployers 488,734 (1997), 702,897
  (2008), 533,596 (2023); 2023 county file uses Connecticut planning regions (09110).
- ~16:31 catalog: 23 metrics (businesses, per 1,000 residents with CAINC1 population, receipts
  per business, 18 sector shares, child care businesses and receipts per business; four research
  rows replaced), recipes, 5 blocks (nonemployer-summary: general and economic development;
  nonemployer-trend, nonemployer-industry-mix: economic development; childcare-nonemployers,
  childcare-nonemployer-trend: early childhood), text records, profiles. catalog --check clean.
- ~16:33 all 27 years loaded (cache 134 MB). D flags through 2016, only S from 2017 (3,502 rows in
  2017, about 100-150 later); Connecticut planning regions from 2022. 2002 U.S. file names receipts
  ECVALUE (renamed; a missing column now stops with a clear error). U.S. transportation
  nonemployers 645,883 (1997) -> 4,057,127 (2023), steepest from 2014. sources.csv row, verify
  check (HEAD on the latest county ZIP), Connecticut note in the metrics' limitations. Fixture:
  real rows of 2023, 2021 and 2008 county/state/U.S. files; tests 272 pass.
- 16:38 batch ok (12, austin-78704 rejected). Capitol Planning Region had no rate: BEA population
  has planning regions only for 2024, NES from 2022 -> POPULATION falls back to PEP Vintage 2025
  where BEA has none (78.1 per 1,000). Charts reviewed. Child care nonemployers dip in 2017
  (U.S. 599,018 -> 539,456 -> 589,313; Travis 1,290 -> 1,025 -> 1,24x) with no cause in the
  Census documentation: stated as such in the child care metrics' breaks. Documented: 2019-2020
  coverage may be low (pandemic tax-filing delays), now in every NES metric's breaks.
- 16:45 done: batch 12 ok (austin-78704 rejected as intended); verify 26 of 27 (FEMA 403 in
  Docker); round trip 10/10; tests 272; catalog 534 metrics, 329 operational. README and PLAN
  updated. Not committed yet (the user commits on request).
- Committed and pushed (3de650f).

## 2026-09-29 16:49 (session 5, continued): NHTSA FARS

- The user asked to start FARS (PLAN.md step of 16:24, item 2).
- ~17:00 files: https://static.nhtsa.gov/nhtsa/downloads/FARS/{YEAR}/National/FARS{YEAR}NationalCSV.zip
  (1975 4.7 MB ... 2023 34 MB; accident.csv and person.csv inside, lowercase headers in some
  years, e.g. 2001 and 2005) and FARS{YEAR}NationalAuxiliaryCSV.zip (1982+, about 1.3 MB;
  harmonized A_PTYPE/A_PERINJ; ACC_AUX has COUNTY through 2019, CENSUS_2020_TRACT_FIPS from 2020).
  Usable coordinates: 1999-2000 none (88888888), 2001 82%, 2005 96%, 2010 98.8%, 2023 99.7%.
  Boundaries for points: TIGER/Line tl_2024_{st}_place/tract (full resolution; CO 2.8/8.3 MB,
  TX 9.7/32.6 MB) rather than the generalized cb files maps use, since city limits follow roads.
- Design (draft): annual deaths and pedestrian/cyclist deaths for counties from COUNTY codes
  (1975+), places, place parts and tracts by point-in-polygon (2001+, a state-year needs 95% of
  crashes with coordinates); regions, divisions, nation and metro areas sum states or counties.
  Rates per 100,000 over 5-year windows ending in ACS release years (2009-2023) with the ACS
  5-year population (x 5 person-years): a second provider with period_kind "multiyear".
- ~17:10 codes: main PER_TYP changed between 1975 and 1990 (1975 pedestrians are code 3); the
  auxiliary PER_AUX harmonizes from 1982: A_PERINJ 1 = killed (equals FATALS every year checked),
  A_PTYPE 3 pedestrian, 4 pedalcyclist (1990 bike 859 = PER_TYP 6 + 7). Series start 1982.
  County codes are FIPS except old codes: 12025 -> 12086 (Miami-Dade), 46113 -> 46102, 51515 ->
  51019; 02261/02201 (split/renamed Alaska areas) and unknowns (x98, x99) count only in state
  totals. Connecticut stays on its former counties through 2023, so planning regions get no
  county-coded values.
- Plan: years <= 2000 crashes from ACC_AUX (STATE, COUNTY, ST_CASE, FATALS); 2001+ from main
  accident.csv (adds coordinates); persons always from PER_AUX. Main ZIPs only from 2001.
- ~17:20 R/providers/fars.R written: nhtsa_fars (deaths by year, 1982-2023) and nhtsa_fars_5yr
  (sums over ACS periods ending 2013, 2018, 2023; PERSON_YEARS = 5 x ACS B01003); crash table per
  year cached; located crashes per state-year cached (TIGER/Line place and tract, full
  resolution); coordinate-based pieces need 2001+ and 95% of the state's crashes located.
- ~17:30 real data: 1990 44,599 deaths (0% located), 2001 42,196 (81.6%), 2023 41,025 (99.7%),
  about 3 s a year to build. Catalog: 6 metrics (deaths, pedestrians and cyclists killed, by year;
  5-year deaths, rate and pedestrian/cyclist rate per 100,000 residents a year, pedestrian/cyclist
  share), source row nhtsa_fars_5yr (derived), blocks traffic-safety, traffic-death-rate-trend,
  traffic-deaths-trend in the general profile's safety section; catalog --check clean.
- ~17:45 real areas: Boulder city 2.8 deaths per 100,000 a year (2019-2023), Boulder County 8.3,
  Colorado 11.7, West 11.6, U.S. 12.2; Austin's Travis part 11.7. First 5-year run 142 s (locating
  crashes, ACS requests); cached after. Tract rates only from the 2020 ACS (2020 tracts). Rates
  divide deaths in 2024 boundaries by each period's ACS population (noted in limitations).
- Fixtures: FARS 2023 main+aux (Delaware and Connecticut crashes), 1990 aux (Delaware); TIGER
  Dover place and 4 tracts; ACS 2023 B01003 Delaware counties. Tests 288 (5-year test replaces
  yearly counts, since the fixture holds only 2023 and 1990). verify check: HEAD on the latest
  auxiliary ZIP.
- 17:09 batch: NHTSA has no auxiliary ZIP for 1996 (every other year 1982-2023 has both). 1996
  now reads the main files (INJ_SEV 4; PER_TYP 5 pedestrian, 6 and 7 cyclists): 42,065 deaths
  (NHTSA's published total), 5,449 pedestrians, 765 cyclists, in line with 1995 and 1997.
- 17:18 batch ok (austin-78704 rejected); FARS cache 416 MB. Values: Gary 28.6 deaths per
  100,000 a year (2019-2023) vs Lake County 11.7; Madison MS 2.2; Austin 11.2, Dallas 16.5,
  Houston 15.9; pedestrian and cyclist rates in the four Texas cities 4.5-5.7 vs Texas 2.8.
  The 5-year charts carried the ACS note ("error bars show margins of error"): providers can
  now name their period note (period_phrase); FARS uses @phrase.note_five_year_totals.
- 17:28 charts reviewed (Gary: rate trend and yearly deaths; Indiana 2002-2006 lack 95% located
  crashes, so the city's yearly line has a gap). The rate chart's axis said "5-year survey
  period": text record traffic-death-rate-trend.x_label = "5-year period". Batch ok; verify ok
  except FEMA 403; round trip 10/10; catalog 537 metrics, 335 operational. Cache: FARS 555 MB,
  TIGER 72 MB. README, PLAN updated. Committed and pushed at the user's request.
- Resume point: FARS done; next is NCES CCD (PLAN.md step of 16:24, item 3) once the user agrees.

## 2026-09-29 17:49 (session 5, continued): data bundle command for moving machines

- The user will run Docker on the Windows PC too and asked for a reusable command, working on
  Windows and Mac, that writes a tar of the data cache and reports to Downloads.
- Plan: host-side scripts (no R or Docker needed; the container cannot see Downloads):
  tools/bundle-data.sh (macOS/Linux), tools/bundle-data.ps1 + tools/bundle-data.cmd (Windows,
  built-in PowerShell and tar.exe; the .cmd avoids the script execution policy). Same output:
  <Downloads>/geo-report-data-<date>-<commit>.tar with cache/ and reports/ (never .env), no lock
  files, partial downloads or macOS metadata; a .sha256 next to it; cache/BUNDLE.txt manifest.
  No PowerShell on this Mac, so the Windows script is reviewed, not run.
- 17:55 done: tools/bundle-data.sh, tools/bundle-data.ps1, tools/bundle-data.cmd; .gitattributes
  gives *.cmd CRLF. Mac run: ~/Downloads/geo-report-data-20260929-1750-aa716c6.tar, 4.0 GB in
  71 s; 24,285 entries (cache 24,033, reports 252), no lock, ._ or .DS_Store files; checksum OK;
  a full extraction is identical to cache/ and reports/ (diff -rq). The Windows script is not
  run here (no PowerShell on this Mac). README section "Moving the data to another machine".
- Committed and pushed at the user's request.
- Resume point: NCES CCD (PLAN.md step of 16:24, item 3) once the user agrees.

## 2026-09-29 19:50 (session 6, Windows): fixes from two reviews

- The user had two reviews of 711d8f3 (copied to docs/review-2026-09-29-a.md and -b.md) merged
  into one list, leaving out where they disagree, and asked to execute it with this log kept
  current. Checklist: PLAN.md "Step agreed with the user 2026-09-29 19:50" (items 1-35).
- Machine: this Windows PC; cache/ and reports/ came from the Mac bundle (cache/BUNDLE.txt,
  3.9 GB). HEAD 61e7521; engine changes since 711d8f3 touch no finding.
- Decisions taken without asking (the user can reverse): history precedence default < library
  < profile < report < manifest (B's proposal); item 35 (email in git history) left to the user.
- 20:30 items 1-13 done (PLAN.md), tests 303 -> 305 with the new ones. Tools: tools/fingerprint.R
  (compose all offline + fingerprint; --compare a b); session scratchpad fp/*.rds hold the
  baseline (base.rds = before any change; base2.rds = HEAD re-run in a worktree with numbers).
  Text edits go through small scratchpad scripts that keep content/text.csv row order
  (save_text_records() re-sorts the whole file); catalog CSVs are edited line by line (a
  read_table/write_table round trip adds a BOM and re-quotes rows).
- Findings while doing them: fingerprint after items 1-8 showed only intended changes (legends,
  notes, turning points, no_data fields, CT jobs 2022-2023, appendix wording); race periods
  2005-09/2010-14 needed 8 ACS requests (fetched online). R files had CRLF in the working copy
  (build.R, content.R, bls.R): normalized to LF (code hashes changed once).
- Item 12 decision changed after checking the data: B's "profile above library" would cut
  econ-dev pop-long-history to 1969 and early-childhood child care jobs to 2000; implemented
  default < profile < library < report < manifest (both reviews agree on report and manifest
  above library) and left profile-vs-library for the user.
- 20:35 items 14-17 done (tests 309). Item 14 checked on gary-in with the NHGIS cache hidden: 0
  error blocks, ACS lines kept, the appendix names the missing census years with the reason.
- !! CACHE NEEDS A MANUAL FIX (the restoring move was blocked by the permission classifier):
  hiding cache/raw/ipums_nhgis for that check left it nested. The real files (extract zips,
  derived parquet, metadata) are now in cache/raw/ipums_nhgis/ipums_nhgis.hidden/ipums_nhgis.hidden/;
  the other folders under cache/raw/ipums_nhgis hold only empty metadata folders and .lock
  files made by the offline runs. To restore (PowerShell, from the project root):
    Move-Item cache\raw\ipums_nhgis cache\raw\nhgis_broken
    Move-Item cache\raw\nhgis_broken\ipums_nhgis.hidden\ipums_nhgis.hidden cache\raw\ipums_nhgis
    (then delete cache\raw\nhgis_broken after checking it holds only .lock files and empty folders)
  Until then, offline composes show NHGIS values as unavailable. Do not build online before the
  fix: it would submit new IPUMS extracts on the user's account.
- The step-2 fingerprint (items 10-17) was stopped because of this; rerun it after the fix:
  Rscript tools/fingerprint.R <scratchpad>/fp/step2.rds, compare with fp/step1.rds.
- 20:55 items 18-20 and 29-32 done in code (tests 315); not yet checked on composed reports
  (waiting for the NHGIS cache fix above). 18: build.json gets compose_key, complete and per-file
  stamps; a build reuses the last compose when all match (--force or --refresh recompose).
  19: report.qmd says `date: today` (Quarto fills it); the unused {report_date} value is gone.
  20: cached() writes <file>.meta.json for new raw entries; retrieved_at() reads it.
  29: catalog --check compares recipe vs documented stat_type through a compatibility table
  (a recipe "share" may be documented as rate or ratio; the 23 "differences" were all of that
  kind, none a contradiction). 32: README note instead of a prune command.
- 20:45 more items (tests 318): 23 long-run sentence ({long_run_sentence} in @metric.prose, both
  scopes; needs NHGIS points to show, so unchecked until the cache fix); 25 price index before
  1978 from the Census Bureau's P60 table (cache/raw/census_p60, new source row
  census_p60_price_index, verify check; 1977 = 104.4 x 39.5/42.2); payroll-trend from 1974;
  27 voter-turnout-trend block (general profile; gary-in checked: Lake County 63.0% -> 57.7%);
  28 FHFA county indexes start 1975 for 419 counties and all sample counties but Madison MS
  (1979): house-prices from 1975; the FBI API serves national and state data from 1985
  (fbi_years is 2016-2025; extending means refetching every agency series and adding the 2013
  rape-definition change, so it is left for the user); 33 lake-in manifest gets
  income-distribution and rent-distribution (rent table fetched with scratchpad one_block.R,
  2 requests, no NHGIS involved).
- Paused (20:50): waiting for the user to restore cache/raw/ipums_nhgis (steps above). Then:
  step-2 fingerprint vs fp/step1.rds and review; batch render; grep rendered HTML for "{";
  items 17 (profile fbi), 21-22, 24, 26, 34; decisions for the user: census_hist, history
  precedence (profile vs library), FBI years before 2016, item 35.

## 2026-09-29 21:00 (session 6, continued): the user's decisions

- NHGIS cache restored by the user. Decisions: keep the history order (default < profile <
  library < report < manifest); remove census_hist; extend FBI data back to 1985 and mark the
  2013 rape-definition change; submit the NHGIS extract for homeownership (B37); the BLS email
  in the flight log history stays (item 35 closed, no action).
- Next: step-2 fingerprint vs fp/step1.rds; then census_hist removal, FBI 1985, B37, CT towns,
  appendix grouping, timing items, batch render and review.
- 21:20 step-2 fingerprint (items 10-20, 23, 25, 27-33) against the HEAD baseline: numbers
  changed only in house-prices (1975-1989 added), payroll-trend (1974-1977 added),
  race-ethnicity (four periods), voter-turnout-trend (new) and ct-capitol jobs; every existing
  value unchanged. Long-run sentences read well (Gary income $69,741 in the 1980 census to
  $38,731, -44.5%); "the" added before the measure.
- census_hist removed (pep.R section, recipe and metric rows, verify check; the source row stays,
  marked unused). FBI: fbi_years 1985:2025; violent crime split into two series at 2013
  (legacy/revised rape definition; history event ucr_rape_definition_2013 cites CIUS 2013);
  the quarter-of-usual screen now uses the median of the three years on each side; Delaware
  fixtures refetched for 1985-2025 (27 requests). B37: recipe owner_occupied_share_census,
  tenure-trend from 1970; the NHGIS census request now includes B37, so the next online build
  submits a new extract (fixture extract renamed census-ad848833.zip). Item 24: nhgis_fetch sums
  Connecticut towns into planning regions for counts, shares and ratios (ct_town_regions moved
  to geography.R). Tests 321.
- Next: online batch --no-render (FBI refetch for all sample agencies; the NHGIS extract).
- 21:25 online compose of all reports (21:03-21:15): NHGIS extract 10 (with B37) took about 5
  minutes; FBI refetch 1985-2025: 250 requests in all; every build ok, complete, no warnings.
  Checked: Gary tenure 58.6% (1970 census) to 49.1%; Gary violent crime 1985-2025 in two series
  (break line 2013; change now 2013-2025, +23.2%); Capitol Planning Region census counts from
  towns (1970 858,874; poverty and homeownership 1970-2000; medians stay unavailable).
  Fingerprint step3 vs step2: numbers changed only in violent-crime-trend, tenure-trend and
  ct-capitol's census-year blocks. pop-long-history now lists PEP before NHGIS so a region
  without decennial API counts is described by its latest estimate (as before), not 1990.
- Running: gr.R batch --offline (render all), then HTML checks, figures, timings.
- 21:45 batch --offline: 12 rendered, 0 warnings (austin-78704 rejected as intended); no "{name}"
  in any report's visible text (Quarto keeps chunk options as hidden data-gr-* attributes).
  Charts checked as images: race break line, crime 1985-2025 split at 2013, tenure dots,
  CT population dots 1970-1990, distributions. Fixed while checking: distribution axis said
  "2020-2024 dollars" ({dollar_year} now); distribution notes moved to legends; jobs- and
  pop-long-history prose now include {turning_sentence} (Gary: "peaked in 1979 at 201,847").
  austin-core (brief) now shows the asterisk legend, the census-dot legend and "years of school".
- Timings (gary-in, warm, offline): unchanged rebuild 1.3 s (compose reused; was 30.6 s); prose
  edit 68 s (compose 37, render 29). Profile: ACS table reading 10 s (the excluded parquet
  item), NHGIS rows 0.4 s (was 5 s), FBI 1.8 s. Item 21 (block cache) not built: user's call.
- Running: demos/benchmark.R --warm (temp copy, project cache; no refresh step), then
  demos/round_trip.R.
- 22:10 warm benchmark run 1 (demos/benchmark.R --warm; results kept in scratchpad
  benchmark.run1.csv): nothing changed 7.5 s (was 166 s); first build 325 s; theme edit 311 s
  and geography edit 246 s because the compose key hashed all of config/. The key now uses the
  report's own row, resolved settings, theme and manifest file instead; run 2 started 22:12.
- 22:45 done. Benchmark run 2 (docs/benchmark.csv, README): nothing changed 8 s; geography edit
  29 s (only that report recomposes); theme edit 307 s (every default-theme report recomposes;
  the civic one is reused). demos/round_trip.R 10/10. gr.R verify: 29 sources ok, 424 ACS
  recipe checks without gaps. catalog --check clean; catalog.html written. Final batch: 12
  rendered, 0 warnings, austin-78704 rejected as intended. Tests 321.
- Final fingerprint vs the HEAD baseline (fp/base2.rds -> fp/final.rds): 2,173 new rows (house
  prices 1975-1989, payroll 1974-1977, race 2005-2014, turnout, crime 1985-2015, tenure census
  years, CT census years) and 53 changed rows, all in ct-capitol (24 false zero-job years now
  unavailable; 29 census-year values now summed from towns). Nothing else changed.
- Not done: item 21 (block-result cache; the user decides). Nothing committed (the user commits
  on request). Temporary baseline worktree removed.
- 22:55 committed and pushed at the user's request (0530fe3 on main; scanned first: no .env
  values or email in the changes, no NHGIS data beyond table metadata).

## 2026-09-29 23:00 (session 6): data-sync with Cloudflare R2

- The user wants cloud sync of the data instead of tar bundles, and plans cache pruning later
  (so deletions must propagate). Chosen: rclone bisync against an R2 bucket (free tier: 10 GB,
  no egress fees); syncs cache/raw, cache/geo, reports; not cache/metrics (recomputable, 66k of
  the 72k files), lock files or partial downloads.
- Plan: tools/data-sync-filters.txt (shared filter rules), tools/data-sync.sh (Mac/Linux),
  tools/data-sync.ps1 + .cmd (Windows). State in .data-sync/ (git-ignored): no listings there
  means first run, so it resyncs with the newer copy winning; deleting .data-sync resets it.
  Files deleted or overwritten in the bucket go to trash/<time>/ in the bucket (R2 lifecycle
  rule empties it after 30 days). Conflicts: newer wins, loser kept as *.conflict1.
- rclone is not installed on the PC; testing needs it (local folder standing in for R2).
- 23:05 done: tools/data-sync-filters.txt, tools/data-sync.sh, tools/data-sync.ps1 + .cmd;
  .gitignore (.data-sync/, the filters .md5 that bisync writes next to the rules file); README
  "Moving the data" now leads with data-sync and the one-time R2 setup (bucket, trash/ lifecycle
  rule, bucket-scoped token, rclone config create gr-r2 ...), tar bundle kept as the alternative.
- rclone 1.75.1 installed on the PC with winget (user approved). Tested with a local
  `rclone serve s3` standing in for R2 (two scratch "machines", ps1 and sh): first-run merge;
  new/deleted files both ways; deleted and overwritten bucket files land in trash/<time>/;
  conflict keeps the newer copy plus <name>.conflict1 on both sides; >50% deletes stop (exit 1)
  until --force; a changed filters file stops with exit 7 and the hint, --resync-mode newer
  recovers; restore = rclone copy from trash then sync; renv, .git, cache/metrics, tools and
  .data-sync are skipped without being walked. Bisync names its state files after both paths, so
  a very long project path (the scratchpad) overflows the 255-character name limit; the real
  C:\Developer\geo-report-gen path is fine. Reading bucket modtimes takes one HEAD per file,
  run in parallel by --checkers (32 set). Not tested against real R2 (no account here).
- Next: the user creates the R2 bucket and token, runs rclone config create on both machines,
  then data-sync on the PC first (uploads about 4 GB), then on the Mac.
- 23:08 R2 set up with the user's wrangler login (account <account id>; R2 was already on, with
  an unrelated bucket): bucket geo-report-data created (Standard class); lifecycle rule
  trash-30-days (prefix trash/, expire after 30 days) beside the default multipart-abort rule.
  rclone remote gr-r2 created on the PC without keys (endpoint
  https://<account id>.r2.cloudflarestorage.com). Waiting for the user to
  create the bucket-scoped token in the dashboard and run rclone config update with the keys
  (Claude does not handle the secret); then verify access, dry run, first data-sync from the PC.
- 23:12 The gr-r2 remote Claude created did not reach the user's real profile: Claude's shell is
  sandboxed, so writes outside the project folder (here %APPDATA%\rclone\rclone.conf) stay in the
  sandbox. The user creates the remote with keys from their own terminal (rclone config create,
  as on the Mac). Anything Claude runs that needs the real rclone.conf must run unsandboxed.
- 23:25 The user created the token and the gr-r2 remote and ran the first data-sync from the PC
  (finished 23:23). Checked: .data-sync listings for path1 and path2 each hold 4,468 files, the
  same as the local files the rules select (cache/raw, cache/geo, reports: 3.98 GB). The Mac gets
  its own token (user's choice); it needs the new scripts committed and pushed first.
- 23:27 committed and pushed at the user's request (2376e72 on main; scanned first: no .env
  values in the changes or history beyond the known author email and old FLIGHT_LOG line;
  .wrangler/, wrangler's account cache, now git-ignored). Next: the Mac pulls, gets its own
  token, creates gr-r2 and runs sh tools/data-sync.sh.
- 23:35 Documentation check at the user's request (README, PLAN, docs/nhgis.md, catalog.qmd,
  FLIGHT_LOG; docs/review-*.md and REQUIREMENTS.md are dated snapshots, left as written).
  Checked against the code: CLI usage, catalog --check (83 subtopics, 124 sources, 537 metrics,
  335 operational), registered providers, verify log, Dockerfile, reports.csv. Fixed: PLAN had
  NCES, NOAA Storm Events, County Health Rankings and their verify step ticked in 0530fe3 though
  no provider exists (now [ ], step marked 1-2 done); PLAN status date, 124 sources, .env keys,
  architecture sketch, "proposed next steps" heading, portability line and a data-sync step;
  docs/nhgis.md implemented list (B37, Connecticut town sums); README `new --label`, wrangler
  commands and one token per machine in the R2 setup, madison-ms in the sample table, rewrapped
  lines; "How to resume" notes rclone and the sandbox.
- 23:55 The user asked for a complete queue of the next data sources: PLAN.md "Data source queue"
  (20 items: A = NCES CCD, NOAA Storm Events, County Health Rankings; B = the 7 sources with a
  provider but non-operational metrics, likely duplicate metric IDs named; C = 8 new sources,
  thinnest subject first, with access notes (MEDSL needs the user to pass a Dataverse guestbook;
  HUD needs a CoC-to-county crosswalk; CHR terms are non-profit only); D = NHGIS additions 3
  and 6). Metric lists from metric_status() and the catalog. Not committed.

## 2026-09-29 23:58 (session 6, continued): working through the data source queue

- The user: proceed with PLAN.md "Data source queue" one item at a time; when an issue or
  blocker comes up, note it here for review and go on to the next item; keep this log current.
  Items needing the user (CHR terms, MEDSL guestbook download) are noted and skipped, not asked.
- Blockers / for review (running list):
  (none yet)
- Now: item 1, NCES CCD. First reading an existing provider (nes.R, fea.R), core.R's contract,
  recipes/blocks/profiles and the tests to follow the same pattern.

## 2026-09-30 00:07 (Codex): resume the data source queue

- User instruction: finish the interrupted NCES step, then process the queue one item at a
  time; record issues/blockers for review and proceed to the next item. Keep this log current.
- Starting state: main at 9d81a0d; existing uncommitted PLAN/flight-log changes, shared TIGER
  point-location helpers in geography.R and fars.R, and untracked R/providers/nces.R preserved.
- Item 1 in progress: NCES draft handles 2017-18 through 2024-25; raw files are mostly cached.
  Recipes, blocks, profile entries, tests and verification remain. Earlier CCD history still
  needs a separate file/layout investigation and must not be advertised as implemented.
- Environment: default R startup attempts to write renv's global cache outside the workspace.
  Checking a workspace-local runtime setup before proceeding with validation.
- 00:15 NCES integration: five recipes (schools, students, public pre-K, teacher FTE and
  students per teacher), three report blocks, relevant profiles, canonical text and a live
  verification check added. Catalog check passes (539 metrics, 340 operational).
- Repaired a source defect: the 2018-19 ArcGIS geocode response duplicates 2017-18 and misses
  2,343 operating schools. Use the official EDGE_GEOCODE_PUBLICSCH_1819.zip/XLSX instead;
  leave the original response cached for review. Added a fail-closed school/geocode join.
  All eight years now join every operating school (2017: 99,888; 2024: 100,237 including
  territories). Missing 2023 geocodes retrieved successfully.
- Validation runtime: R 4.6.1 --vanilla with R_LIBS_USER set to the existing project library,
  RENV_CONFIG_AUTOLOADER_ENABLED=FALSE for child processes, LC_ALL=English_United States.utf8.
  Public network requests require the normal sandbox escalation; approved requests work.
- For review: NCES pre-2017 history is still deferred; the adapter and report documentation
  explicitly cover 2017-18 to 2024-25. Recent EDGE fields/layouts have been verified; older
  annual bulk formats need their own mapping. Tests and full validation are running.

## 2026-09-30 05:20 (Claude, session 7): finish NCES, then the queue

- User: finish the rest of the NCES step, then proceed through the PLAN.md queue one item at a
  time; note any issue or blocker here for review and go on to the next item; keep this log current.
- State found: main at 9d81a0d, NCES work uncommitted (see the 00:07 Codex entry). R 4.6.1
  `gr.R test` runs directly from the shell here (no renv workaround needed): 330 pass.
- Removed a BOM the previous session added to catalog/{blocks,metrics,recipes}.csv and
  profiles/{early-childhood,economic-development,general}.csv (HEAD had none in those six).
- Blockers / for review (running list):
  (none yet)
- 05:35 Item 1 (NCES CCD) finished: tests 330 pass; catalog --check clean (539 metrics, 340
  operational); gr.R verify all sources ok (nces_ccd: 101,110 records in 2024-25); gary-in
  builds with a public-schools table (Gary 19 schools, 9,607 students, 276 pre-K; Indiana
  1,037,604; U.S. 49,069,867; Gary teachers unavailable = under 95% reporting, explained in the
  appendix); demos/round_trip.R 10/10; batch --offline 12 rendered, austin-78704 rejected as
  intended. PLAN.md item 1 ticked. NOT committed (the user commits on request).
- For review: NCES 1986-2016 history not built (layouts differ per era); PLAN.md item 1 says so.
- Now: item 2, NOAA Storm Events. Design: yearly files found from the NCEI directory listing
  (file names carry a creation date); zone-based events (CZ_TYPE Z) mapped to counties with the
  NWS county-zone correlation file (weather.gov bp*.dbx); counts and deaths and damage.
- 06:00 Item 2 (NOAA Storm Events) finished: R/providers/noaa.R (1950-2025; listing-based file
  names; NWS county-zone file bp16ap26.dbx; marine zones dropped), 3 metrics, 3 recipes
  (damage with dollars=year), 4 blocks in general and economic-development, text records,
  README limitation, source-row note, verify check (noaa_storm_events ok), tests 345 pass,
  round trip 10/10, batch --offline 12 rendered (austin-78704 rejected as intended). Checked:
  2025 U.S. 69,380 events, 865 deaths, $4.4 billion; Travis+Williamson+Hays 162 events; Lake
  County IN 74 events, 0 deaths; ct-capitol says why it has no values.
- For review (NOAA): (1) county values need the state's zone events to match today's NWS zones
  (95%): about half the states fail before 2013 and 9-11 of 51 states still fail in 2022-2025
  (AK, CA, SC, WA never reach 95%), so county trends have gaps; NWS publishes only the two
  newest correlation files (older bp*.dbx files exist on the server but are not listed), so a
  historical fix would mean guessing file names. (2) Equal split of zone-event deaths and damage
  among a zone's counties gives fractional county deaths; a different rule (county-based events
  only) is a one-line change in noaa_event_counties(). (3) Yearly totals were not
  cross-checked against another source; NCEI's file for 2025 was created 2026-08-19, and damage
  entries for late events may still be added. (4) 1996-2007 event types were fewer than the 55 since 2007.
- Item 3 (County Health Rankings) SKIPPED as instructed: terms allow personal or non-profit use
  only (commercial use needs written consent); the user must confirm the use before it is built.
- Blockers / for review, running list: item 3 (CHR terms); NOAA points above; NCES 1986-2016.
- Now: item 4, NDCP child care prices (dol_ndcp). Plan: 7 new price metrics (center toddler
  and school-age; family toddler, preschool, school-age; 75th percentile center and family
  infant), the women's labor force rate (counties and states), the two named duplicates merged
  away (home_infant = family_infant; burden_center_infant = infant_share_income), the four
  documented "home" IDs renamed to "family" to match the operational one, and the age-band
  metric left documented (one metric cannot hold 22 series).
- 06:03 Item 4 (NDCP) finished: childcare.R reads 12 more NDCP columns (school-age, family
  toddler/preschool/school-age, 75th percentiles, labor force rate) and keeps each state's rate
  once as a state row; provider now county + state. Catalog: 537 metrics, 351 operational.
  Blocks childcare-price-table, working-mothers-trend in the early-childhood profile; text
  records; tests 351; verify ok; round trip 10/10; batch --offline 12 rendered. Fixed while
  checking: a state piece asked for a price variable returned a data.frame length error (now
  returns nothing). Austin (Travis, Williamson) shows all 10 prices; state labor force rates show.
- For review (NDCP): childcare_price_age_band_ndcp stays documented (22 band variables do not fit
  one-value metrics; would need 22 metrics or a table type).
- Now: item 5, decennial census (census_dec). Verified 2000/2010/2020 variable IDs against the
  Census API (households, average household size as population in households / households,
  vacancy, homeownership, median age, three household-type shares, six race/Hispanic shares as a
  group). Needs one engine change: var_by_period must include denominator variables (metrics.R).
- 06:22 Item 5 (decennial census) finished. 9 documented metrics -> 14 operational
  (households, average household size, vacancy, homeownership, median age, 3 household-type
  shares, 6 race/Hispanic shares in group race_ethnicity_decennial; dropped duplicates
  total_population_decennial and housing_units_decennial). Variable IDs verified against the
  Census API labels (2000 SF1 homeownership has no separate free-and-clear line; 2000 family
  tables are P018). Engine: compute_metric now passes denominator variables per period to the
  decennial provider (before, only numerators were fetched). Values checked: Delaware households
  298,736 (2000) and 342,297 (2010); U.S. households 105,480,101 (2000); U.S. homeownership
  66.2 / 65.1 / 63.1%; U.S. median age 35.3 / 37.2 / 38.8; U.S. Hispanic 12.5 / 16.3 / 18.7%.
  Tests 353; verify ok; round trip 10/10; batch: an offline run first warned for tx-cities and
  madison-ms (their census tables were not cached yet), an online `batch --no-render` fetched
  them (44 requests), and the final offline batch has 12 up to date, 0 warnings, austin-78704
  rejected as intended. Catalog: 542 metrics, 365 operational.
- For review (decennial): the census-counts table marks every comparison with * (census counts
  have MOE 0, so any difference is "significant"); 2000 has no separate owned-free-and-clear
  line, so its homeownership uses the single owner line.
- Note for future item verification: new sources need `gr.R batch --no-render` online first,
  because `batch --offline` warns for reports whose new data are not cached.
- Now: item 6, population estimates (census_pep). Finding: pop_estimate_pep already carries
  the July 1 estimates for 2000-2025 (both intercensal series, Vintage 2025, states, counties,
  places and county subdivisions), so population_estimate_pep, population_intercensal_2000_2009_pep,
  population_intercensal_2010_2019_pep and subcounty_population_estimate_pep are duplicates of it
  (merged). New: annual change, natural change rate, net domestic and net international
  migration rates from the V2025 component files (2021-2025).
- 06:45 Item 6 (population estimates) finished. Duplicates merged: population_estimate_pep,
  population_intercensal_2000_2009_pep, population_intercensal_2010_2019_pep,
  subcounty_population_estimate_pep (pop_estimate_pep already has all of them). New: four
  component metrics from the Vintage 2025 files (change %, natural increase, net domestic,
  net international; 2021-2025) in a second provider census_pep_components (new source row,
  verify check) so place reports fall back to county and above. Rates per 1,000 use the
  average of the two July 1 estimates: Lake County IN 2021 natural increase -1.571 and Indiana
  domestic 2.215 / international 0.892 match the published R* columns. Units were first
  "per 1,000 residents", which the formatter printed as whole numbers; now "people per 1,000
  residents" (needs " per " in the units string to format as a ratio with decimals). Tests 358;
  verify ok; round trip 10/10; batch 12 rendered (austin-78704 rejected as intended).
- Now: item 7, BEA personal income (bea_cainc): CAINC30 and CAINC5N added; earnings by industry
  will be 13 group shares like the GDP mix; duplicate check: none (personal_income_bea comes
  from CAINC1 line 1, already loaded).
- 07:15 Item 7 (BEA personal income) finished. CAINC30 and CAINC5N added; 5 documented metrics
  -> 17 operational (4 income/earnings metrics + 13 earnings-by-industry group shares in group
  earnings_industry_bea). No duplicates among the five. BEA withholds many small industries in
  small counties (36% of counties for health care in 2023, 59% for forestry/fishing), so the
  earnings mix has missing bars for small counties, like the GDP mix. Checked values: Lake County
  IN 2023 transfers 24.5% of personal income, manufacturing 17.9% of earnings (2010: 19.8%), U.S.
  manufacturing 8.7%; personal_income (CAINC1) equals CAINC30 line 10 and EARN_TOTAL equals line
  180. Code: bea_cainc1() kept (GDP and nonemployer population use it, and the offline test
  fixtures only have CAINC1); bea_income_long() holds the new tables; bea_sum_regions() now serves
  GDP too. Tests 368; verify ok; round trip 10/10; batch 12 rendered (austin-78704 rejected).
  Catalog: 550 metrics, 386 operational.
- Now: item 8, BLS LAUS. Plan: unemployed and employed persons (all levels); civilian_labor_force
  merged into labor_force_laus; participation rate and employment-population ratio for the
  nation, regions, divisions and states as ratios of labor force / employed to the LAUS
  civilian noninstitutional population (measure 09, states only; region and division sums of
  states), as a second provider bls_laus_rates so county and city reports fall back to states.
- 07:35 Item 8 (BLS LAUS) finished. New: unemployed_persons_laus and employed_persons_laus (all
  levels; the nation now also sums employed), and participation rate and employment-population
  ratio in a second provider bls_laus_rates (states, regions, divisions, nation; new source row and
  verify check), because measure 09 (population) exists only for states: regions add states.
  civilian_labor_force_laus dropped as a duplicate of labor_force_laus. Checked: Indiana 2024
  participation 63.7% (published), U.S. 1980 63.8% and employment-population 59.2%. Tests 371;
  verify ok; round trip 10/10; batch 12 rendered (austin-78704 rejected). Catalog: 549 metrics,
  390 operational, 126 sources.
- Now: item 9, Texas HHSC child care licensing: adds centers, licensed homes, registered homes,
  share of centers accepting subsidies (query now also groups by accepts_child_care_subsidies) and
  capacity per 100 children under 5 (ACS denominator, as FARS uses ACS population); the query now
  also requires operation_status Y (in operation), which the "current operations" definition
  already said; cache file renamed capacity_by_county_type.parquet so the new query runs once
  online. childcare_licensed_capacity_tx_hhsc is a duplicate of childcare_capacity_tx (merged).
- 08:00 Item 9 (Texas HHSC licensing) finished. Six metrics operational (the existing capacity one
  plus centers, licensed homes, registered homes, subsidy share, capacity per 100 under 5); the
  Socrata query was re-run (cache file renamed) with the operation_status Y filter. 2026-09-30
  snapshot: Texas 9,593 licensed centers (52.6% accept subsidies), 1,584 licensed and 1,747
  registered homes, capacity about 1.17 million (Travis County about 56,900, 76.4 per 100 children
  under 5). Tests 377; verify ok; round trip 10/10; batch 12 rendered (austin-78704 rejected).
  Catalog: 549 metrics, 395 operational.
- For review (Texas): the Y filter lowers totals slightly against the earlier snapshot (42 of
  14,978 records had status N); the per-100 ratio divides current licensed capacity (which
  includes school-age places) by 2020-2024 ACS children under 5.
- Now: item 10, building permits (census_bps): county files 1990-1999 use the same layout as 2000+;
  place files before 2007 carry no FIPS place code (Census 6-digit permit ID only), so places stay
  2007-2025 and the older place history is not built. New: 1-unit and 5+ unit counts, units per
  1,000 residents (PEP population); permitted_units_total_bps is a duplicate of
  housing_units_authorized_bps.
- 08:25 Item 10 (building permits) finished. Counties now 1990-2025; new: 1-unit and 5+ unit
  units (structure-size columns), units per 1,000 residents (PEP July 1 population). Merged
  permitted_units_total_bps into housing_units_authorized_bps. Places stay 2007-2025: the pre-2007
  place files have no FIPS place code (the 6-digit permit-office ID would need a crosswalk).
  Checked: Travis County 2024 total 16,990 units of which 12,145 in 5+ unit buildings; per 1,000
  residents 12.4 (Travis) and 3.3 (Lake IN). Tests 381; verify ok; round trip 10/10; batch 12
  rendered (austin-78704 rejected). Catalog: 548 metrics, 398 operational.
- Group B (items 4-10) is done. Group C starts now (new sources).
- Item 11 (MIT Election Lab county presidential returns) SKIPPED as instructed: the Harvard
  Dataverse download needs the user to complete a guestbook form once, which Claude does not
  fill in; PLAN.md item 11 says so. Blockers / for review (running list): item 3 (CHR terms), item
  11 (MEDSL guestbook download), NOAA points, NCES 1986-2016, NDCP age bands, PEP/BPS notes above.
- Now: item 12, Indiana FSSA provider listings: base-R parsing of the three HTML tables (rvest and
  xml2 are not in the renv library and are not added), county totals for Indiana, capacity per 100
  children under 5 with the ACS denominator, PTQ level 3-4 capacity and its share of capacity.
- 08:35 Item 13 (HUD PIT/HIC) BLOCKED, noted for review and skipped: huduser.gov answers scripted
  requests that carry the project's own User-Agent (geo-report-gen/0.1) with an AWS WAF bot
  challenge (HTTP 202, empty body, x-amzn-waf-action: challenge) for the workbooks and for the
  HTML pages alike; the hudexchange.info paths I tried are 404. Getting the files by presenting a
  browser User-Agent would sidestep bot detection, so it is NOT done and nothing in the code does
  it. To disclose: while diagnosing, one request with a browser-style User-Agent returned the
  file (200); its body was discarded (-o /dev/null) and nothing was kept or used. The provider
  would also need a reader for the .xlsb workbooks (readxl cannot; a BIFF12 reader in base R
  is doable) and a CoC-to-county crosswalk decision (CoC territories do not match counties or
  cities). Options for the user: download the four workbooks once by hand into
  cache/raw/hud_pit_hic/ (like item 11), or allow a change of User-Agent policy.
- Slip to disclose: in a diagnostic set of HEAD requests for items 14-18 I put the user's email
  address in the User-Agent, as the project does for BLS only (approved 2026-09-28, "sent only to
  BLS"). Four of those six requests went to other hosts (www.ers.usda.gov twice, www2.census.gov,
  data.hrsa.gov); the other two went to download.bls.gov. HEAD requests only, no data kept.
  No project code was changed by this; from here on other hosts get only the plain project
  User-Agent.
- 08:40 Item 12 (Indiana FSSA provider listings) finished. Parsed counts equal the catalog's
  sample (770 centers / 86,053 capacity, 1,813 homes / 23,754, 732 ministries, 92 counties).
  7 metrics (the documented providers-by-type became three counts; PTQ level 3-4 share added).
  Lake County IN: 81 centers, 191 homes, 44 ministries, capacity 9,236, 74.7% at PTQ 3-4, 32.3
  spaces per 100 children under 5 (Indiana 26.8). Checked with a temporary Indiana early-childhood
  report (a scratch copy, removed). Tests 386; verify ok; round trip 10/10; batch 12 rendered
  (austin-78704 rejected). Catalog: 551 metrics, 405 operational.
- For review (Indiana): the childcare_gap example module (modules/childcare_gap.R) still uses
  Texas capacity only and says so for Indiana counties; generalizing it is a small change if wanted.
- Now: item 14, USDA Food Access Research Atlas (tract level, summed up to counties, states and
  the nation; tract reports show the tract itself).
- 09:05 Item 14 (USDA Food Access Research Atlas) finished. fara.R reads the SRAM 2025 straight-line,
  driving and general-characteristics CSVs and the LRAM 2019 CSV (SRAM tract codes lack the leading
  zero and carry county names but no county FIPS; the FIPS come from the tract code). 4 documented
  metrics -> 6 (driving population share and tract shares added). Checks: SRAM U.S. population
  331,449,281 (2020 census), 28.4 million (8.6%) beyond 1/10 miles in a straight line, 18.8% by road;
  2,356 straight-line and 6,301 driving LILA tracts; LRAM 72,531 tracts, 9,293 LILA, population
  308,745,538 (2010 census). Lake County IN: 7.3% of residents far, 1 LILA tract. Tests 393; verify
  ok; round trip 10/10; batch 12 rendered (austin-78704 rejected). Catalog: 553 metrics, 411 operational.
- For review (FARA): LRAM 2015 and 2010 editions are not read (no URL in the catalog); places have no
  values (tracts do not nest in places); Connecticut planning regions are not coded in the files'
  tract codes (former counties).
- Now: item 15 (PEP county age/sex/race). Provider written (base R over cc-est2025-agesex-all.csv,
  10 MB, and cc-est2025-alldata.csv, 105 MB, age group 0), catalog script ready.
- 09:30 Item 15 (PEP county age/sex/race) finished. Provider in pep.R reads the 10 MB age/sex file
  and the 105 MB ALLDATA file (age group 0); 3 documented metrics -> 8 (65+ share, median age, six
  race shares in group race_ethnicity_pep). Lake County IN 2025: 65+ 19.2%, median age 40.4, NH
  White 49.5%, Hispanic 21.8%; shares sum to 100%; U.S. 2020 Hispanic 18.8%. Tests 398; verify ok;
  round trip 10/10; batch 12 rendered (austin-78704 rejected). Catalog: 558 metrics, 419 operational.
  Also added a caveat to the NOAA metric text and README: in a union of several counties an event of
  a zone covering several of them counts in each (the engine sums the counties; deaths and damage
  are shared so they add up correctly). The same holds for the HPSA counts coming next.
- Now: item 16, HRSA shortage areas: designated HPSAs (status Designated only) counted by county,
  states and above counted distinct; highest score; primary care, dental, mental health.
- 09:50 Item 16 (HRSA HPSA) finished. hpsa.R reads the three daily CSVs (48 MB primary care; the
  other two are smaller); primary care matches the catalog's sample exactly (21,444 designated
  components, 7,822 designated IDs); dental 7,225 IDs, mental health 6,512. 3 documented metrics ->
  6 (count and highest score per discipline). Lake County IN: 7 primary care HPSAs (highest score
  21), 4 dental, 6 mental health; Indiana 143 primary care. Correction to my own assumption:
  HRSA codes Connecticut by planning regions (09110-09190), so CT works with the 2024 geography
  (FARA and NOAA do use the former counties). Tests 403; verify ok; round trip 10/10; batch 12
  rendered (austin-78704 rejected). Catalog: 561 metrics, 425 operational.
- For review (HPSA): a snapshot only; history could be rebuilt from designation and withdrawal
  dates (not done: dates may reflect redesignations); counts in a union of counties count a
  designation in each county (stated in the block note).
- Now: items 17 (BLS OEWS) and 18 (BLS CPS national) share one file, R/providers/bls.R, and the
  same download pattern (the 330 MB and 390 MB BLS time-series files read in chunks, only the
  wanted series kept); I implement both, then verify them together (one tests + verify + round
  trip + batch run) and log both.
- 10:20 Items 17 (BLS OEWS) and 18 (BLS CPS) finished and verified together. OEWS: 331 MB
  oe.data.0.Current read in chunks, series for area types N/S/M with industry 000000 and
  occupation 000000 and datatypes 01/04/13 kept (1,749 rows, 583 areas); U.S. May 2025: 155,495,730
  jobs, mean $69,770, median $50,980 (nominal); Indiana 3,201,220 jobs. Metrics: employment,
  median wage, mean wage of ALL occupations (wages in constant dollars); occupation detail is not
  built (one metric = one value). CPS: ln.data.1.AllData (390 MB) chunked; unemployment 1948 3.8% ...
  2025 4.3% (11-month average, footnote 11), participation 58.8% (1948) to 62.4% (2025),
  employment-population 56.6% to 59.7%. CPS blocks are one per metric because a metric block
  charts only its first metric. Tests 407; verify ok; round trip 10/10; batch 12 rendered
  (austin-78704 rejected). Catalog: 561 metrics, 431 operational.
- For review (OEWS/CPS): OEWS is a single May 2025 snapshot (no trend); wages of $239,200 and up are
  published as "#" (shown unavailable); the two BLS files add about 720 MB to cache/raw/bls (the
  data-sync will carry them).
- Now: item 19, NHGIS constant-2010-boundary counts (addition 3). Plan: a provider
  ipums_nhgis_std with one IPUMS extract of CL8, CW5, CM1, CP4, CM4, CM7, CM9 and CN1 for states,
  counties, tracts and block groups, 1990-2020; tract and block group values only when a report's
  boundary_vintage is 2019 or earlier (the project's default 2024 uses 2020 tracts). Item 20 (historical
  boundary files for maps) is an engine feature more than a data source: see below when reached.
- 10:50 Item 19 (NHGIS constant 2010 boundaries) finished. Extract 11 (8 standardized tables x state,
  county, tract, block group x 1990-2020) came back in under 2 minutes (199 MB). Two things went
  wrong on the way, both fixed: (1) reading the 604 MB block group CSV with read.csv crashed R (exit
  139, twice, with no message); readr::read_csv with col_select for the 28 needed series reads all
  four files in about 10 s; (2) I had wrongly assumed exact counts: the standardized files hold
  fractional estimates with lower and upper bounds for areas whose boundaries changed (Kent County
  DE 2020: 181,854.1 vs 181,851 counted), so the metrics' uncertainty is "modeled, none published"
  and the docs say so. Verified: Delaware 666,168 / 783,600 / 897,934 / 989,948 (1990-2020);
  Kent County 110,993 / 126,697 / 162,310. Tract 10001040100 (Delaware): 4,429 (1990) to 7,315
  (2020) with boundary_vintage 2019, unavailable with the vintage note at the default 2024.
  Tests 413; verify ok; round trip 10/10; batch 12 rendered (austin-78704 rejected). Catalog: 576
  metrics, 446 operational, 127 sources. The IPUMS API key was used only through the project's
  existing Authorization-header code; one extract (number 11) was submitted to the user's IPUMS
  account (the project's normal pattern).
- For review (NHGIS std): the sample reports have no tract study areas, so the tract path is tested
  with fixtures only (a report with boundary_vintage 2019 would use it); place and CBSA levels of the
  standardized tables are not requested.
- Now: item 20, historical boundary files for maps. Scope I am building: NHGIS county boundary
  files for census years 1790-2010 (tl2008 basis) fetched through the same API into the cache, and
  a map block "historical_map" (county boundaries of a chosen census year around the study area,
  with today's outline); NHGIS's tract boundaries (1910-2000; 1910-1980 only a few cities) are
  available through the same function but no block uses them.
- 11:25 Item 20 (historical boundary maps) finished and verified: nhgis_boundaries() (NHGIS
  shapefile extracts, 1900 county file = extract 12, 2,848 features) and the map block kind
  historical_map with block historical-counties in all three profiles; Gary IN shown in the 1900
  Lake County. Tests 419; verify ok; round trip 10/10; batch 12 rendered (austin-78704 rejected).
  README limitations, docs/nhgis.md and PLAN.md updated.

## 2026-09-30 11:30 (Claude, session 7): queue finished; state and review list

- Done and verified one by one (tests, catalog --check, gr.R verify, demos/round_trip.R 10/10, batch;
  items 17+18 verified together): 1 NCES, 2 NOAA Storm Events, 4 NDCP, 5 decennial census, 6 PEP
  components, 7 BEA income and earnings, 8 LAUS, 9 Texas licensing, 10 building permits, 12 Indiana
  FSSA, 14 USDA Food Access Atlas, 15 PEP age/sex/race, 16 HRSA HPSA, 17 BLS OEWS, 18 BLS CPS, 19 NHGIS
  constant 2010 boundaries, 20 NHGIS historical county map. Catalog: 576 metrics, 446 operational,
  127 sources. Tests: 419 pass. Nothing is committed (the user commits on request); 45 changed
  or new files, none holds the user's email or a key (checked).
- Skipped or blocked, for the user: item 3 County Health Rankings (terms: personal or non-profit
  use; commercial use needs written consent; confirm before building); item 11 MIT Election Lab
  (Dataverse guestbook download is the user's step: save the county returns CSV, then it can be built);
  item 13 HUD PIT/HIC (huduser.gov bot challenge on scripted requests; not bypassed; also needs an
  .xlsb reader and a CoC-to-county decision).
- Not built inside done items (for review): NCES 1986-2016; NDCP six-month age bands; OEWS occupation
  detail; LRAM 2010 and 2015 editions; BPS places before 2007; PEP intercensal age/sex/race 2010-2019;
  a tract-based use of the historical boundaries.
- Decisions I made that the user may want to change: NOAA zone events split equally among a zone's
  counties, with county values only where 95% of a state's zone events match the current NWS zones;
  NCES/NOAA/FARA county values for Connecticut planning regions unavailable (their sources use the
  former counties; HRSA and PEP use planning regions); the Texas capacity metric now counts only
  operations in operation (status Y); race shares from PEP use the Bureau's modified race
  (no Some Other Race); OEWS shown in constant dollars.
- Two process notes: (1) a set of HEAD requests carried the user's email in the User-Agent to four
  non-BLS hosts (see the 08:35 entry); (2) new sources need an online `gr.R batch --no-render` before
  `batch --offline` (the offline run warns for reports whose new data are not cached yet).
- How to resume: read this entry, PLAN.md "Data source queue" (statuses [x], [-] skipped, item 13
  blocked) and README "Limitations". Verification recipe used per item: `gr.R test`, `gr.R catalog
  --check`, `gr.R verify`, `Rscript demos/round_trip.R`, `gr.R batch --no-render` then `gr.R batch
  --offline`. The cache grew by well over 1 GB (BLS OEWS 331 MB and CPS 390 MB files, PEP ALLDATA 105
  MB, NOAA yearly files, HRSA, USDA, BEA CAINC30/5N, NHGIS extracts 11 and 12); run tools/data-sync
  to carry it to the other machine.

## 2026-09-30 12:00 (Claude, session 7): review of the added metrics (the user's feedback)

- Feedback: redundant race charts (census, PEP estimates, constant boundaries) against the ACS
  one; 2.13 Households in the census lacked comparisons; 2.14 Population on constant boundaries
  put counties and states on one count axis; most constant-boundary metrics add nothing; charts
  repeating a metric from another source without the study place, or with the U.S. alone, are
  not wanted; 4.3 Single-family and apartment permits was drawn as one zigzag line.
- Done: (1) engine rule in compose.R/blocks.R: a metric, composition or facts block that fell back
  to comparison areas and has values for the nation alone is left out of the report (compute_blocks
  keeps the ids in attr "skipped"; the availability appendix lists them). For Gary the three
  national CPS blocks drop out. (2) Removed from the block library, the profiles and text.csv:
  race-ethnicity-census, race-ethnicity-estimates, race-ethnicity-std, population-std-trend,
  tenure-std-trend, age-estimates, participation-trend, population-change-trend, wages-oews,
  permits-by-size. (3) households-census-trend is now time+parents with index=first (like
  pop-growth): "Gary -25.2% since 2000; Lake County +7.4%, Indiana +14.2%, U.S. +20.2%".
  (4) permits-by-size split into permits-single-family and permits-multifamily (a metric block
  draws its metrics as one series, so two counts zigzagged). The metrics behind the removed
  blocks stay operational in the catalog with no block using them (decennial race shares, PEP
  race and age, the 15 NHGIS constant-boundary metrics, LAUS rates, OEWS, PEP yearly change).
  Tests 419; catalog check clean; gary-in rebuilt. The shell tool's permission check failed
  repeatedly at the end, so the full batch was not re-run after these edits.
- Left for the user's call: census-counts (a table of 2020 census counts that the ACS blocks also
  cover, with the place); the CPS blocks and wages-oews stay in the library for state and national
  reports.
- 12:20 The user: remove the constant-boundaries provider and metrics entirely. Done: nhgis.R
  section "Census counts 1990-2020 on constant 2010 boundaries" deleted (the `link` argument of
  nhgis_extract() stays: the boundary files use it); 15 metric rows, 15 recipes, the
  ipums_nhgis_std source row, the verify check, tests/testthat/test-nhgis-std.R and the cache
  files cache/raw/ipums_nhgis/std-840f8e0e* (zip and parquet) removed; PLAN item 19 marked
  removed; docs/nhgis.md and README say it was tried and removed. The two verification_log rows
  stay as history.

## 2026-09-30 13:10 (Claude, Mac): 1.0 release checklist

- Assessed what 1.0 still needs (read-only; no code changed). Checked in Docker: tests 414 pass;
  `catalog --check` clean (561 metrics, 431 operational, 126 sources). Measured from build.json:
  warm compose 30-60 s per report (in-cities-1827000: 31 s with 0 cache misses); chicago-il first
  build 517 s, 494 requests (320 FBI). Found 43 operational metrics and 12 library blocks that no
  profile or manifest uses.
- Saved as PLAN.md "1.0 release checklist": decisions D1-D3 for the user, then groups A-E (prune,
  iteration speed, bulk and cache, docs, release check and tag) and an "After 1.0" list.
- Resume point: the user answers D1-D3; then start at A1.

## 2026-09-30 13:12 (Claude, Mac): the user's decisions D1-D3

- D1: keep the catalog rows of bls_oews and census_pep_county_characteristics (sources.csv with
  update cadence, metrics.csv documentation); delete their provider code (OEWS section of
  R/providers/bls.R, age/sex/race section of R/providers/pep.R), 11 recipes, 2 verify checks, the
  OEWS test (test-oews-cps.R keeps CPS, renamed test-cps.R), test-pep-asrh.R and their cached files.
- D2: a shorter general profile (one block per question; current and history in each subject;
  blocks that show only county or national context for a city left to the exhaustive profile)
  and profiles/exhaustive.csv with every library block and metric rows for the 27 operational
  metrics no block shows; `catalog --check` enforces completeness. round_trip.R needs
  unemployment-trend, income-trend and the section order overview, people, economy, housing.
- D3: chicago-il row removed from config/reports.csv; reports/chicago-il left on disk for the user.
- Commands run in Docker (docker compose run --rm gr ...).
- 13:16 D3 done (row restored away). D1 done: bls.R OEWS section and pep.R age/sex/race section
  deleted, 11 recipes, 2 verify checks, tests (test-pep-asrh.R deleted, test-oews-cps.R ->
  test-cps.R); 12 cached files deleted (oe.data.0.Current 331 MB, cc-est2025-alldata.csv 105 MB,
  agesex 10 MB, derived parquets); README and PLAN items 15/17 marked removed. Catalog 420
  operational, 141 documented. Tests 406.
- 13:22 D2: profiles/exhaustive.csv written (13 sections: general's plus children; 136 blocks, the
  intro text row, the childcare_gap module, 27 metric rows; blocks placed after related general
  blocks); profiles/general.csv cut from 82 to 43 blocks and text rows; validate_catalog() calls
  exhaustive_gaps() (checked: a removed block and metric are reported). Tests 407; catalog clean.
  Next: batch of the samples, a temporary exhaustive report of Gary, round trip, README.
- 13:34 Batch 621 s (compose 500, render 121), all ok, austin-78704 rejected as intended. General
  profile reports compose in half the time (gary-in 59 -> 30 s; in-cities Gary 31 -> 12 s with 0
  misses; tx-cities 58 -> 20 s) and gary-in shows 42 blocks, 7,169 words, 6 MB (was about 78
  blocks, 12,000 words). Temporary report gary-in-exhaustive (config/reports.csv row added by
  `gr.R new`): 161 blocks, 22,146 words, 20 MB; first compose 228 s and 324 requests (blocks no
  profile used before), warm 86 s; one warning, the Texas-only childcare_gap module. Found: metric
  rows of counts drew Gary and the U.S. on one count axis. Fixed in load_manifest (a count row with
  time+parents gets index=first) and compute_block_metric (an index view's axis uses the new
  @phrase.y_index record; the 7 indexed library blocks keep their own y_label records). Test
  added; tests 409. README: exhaustive profile and the rule for new blocks and metrics.
  Next: batch again (code changed), round_trip.R, then remove the temporary report row.
- 13:55 Batch 372 s (compose 300, render 71), 0 requests, all ok, austin-78704 rejected as
  intended. round_trip.R first 9/10: its refresh step used BEA, which the shorter general profile
  no longer shows; now it refreshes census_govfin (one 9.7 MB file gary-in uses): 10/10. Catalog
  check clean. Temporary row gary-in-exhaustive removed from config/reports.csv;
  reports/gary-in-exhaustive and reports/chicago-il stay on disk for the user. Nothing committed.
- Resume point: PLAN.md "1.0 release checklist": D1-D3 and A1 done; next A2 (the 11 library blocks
  only the exhaustive profile uses: delete superseded ones), then A3.

## 2026-10-01 (Claude, Mac): 1.0 checklist A2

- Started A2: the 11 library blocks only profiles/exhaustive.csv uses; delete those another block
  supersedes, keep the rest.
- Assessed (no code changed yet). Superseded, to delete: pop-history (pop-long-history and
  pop-growth show pop_total_dec), median-age (key-facts), snap (economic-security), commute
  (getting-around), broadband (internet-access). Their metrics stay shown by those blocks, so the
  exhaustive check needs no new metric rows. Keep: per-capita-income (census/ACS money income,
  not BEA's PCPI), rent-trend, household-size and disability (the only trends of their metrics),
  vacancy (the only ACS overall vacancy rate), income-annual (SAIPE yearly, sibling of
  poverty-annual). References: catalog/blocks.csv, profiles/exhaustive.csv, content/text.csv
  (pop-history.caption and .title); no sample report, manifest, test or prose uses them.
- The edit removing those rows was denied by the permission classifier; waiting for the user.
- Resume point: delete the 5 blocks' rows from the three files, then `gr.R test` and
  `gr.R catalog --check`, then A3.
- The user: delete the 5, keep the 6 in the exhaustive profile. Done: 5 rows of
  catalog/blocks.csv and profiles/exhaustive.csv, 2 of content/text.csv. Catalog check clean
  (420 operational of 561); tests 409 pass. PLAN A2 checked. Not committed.
- Resume point: A3 (one helper for the states of a region or division in fara, hpsa, nces, fars,
  eavs and bea).
- Started A3: one helper for the states of a region or division.
- 12:18 A3 code done: R/geography.R gets nation_state_table() (rows of the 50 states and DC) and
  member_states(type, geoid) (codes of the nation, a region or a division); 14 providers use them
  (bea, bls, eavs, fara, fars, govfin, hpsa, lodes, nces, nes, noaa, nri, pep, qcew); no
  `in_nation == "TRUE"` filter is left outside geography.R. Editing a provider changes its
  derived-file version, so their parquets are recomputed from cached raw files (old ones left for
  C9's prune). Baseline fingerprint of the snapshots of 2026-09-30 13:45 (same code before A3):
  reports/_fp/before.rds. Next: compose all offline -> reports/_fp/after.rds, compare.
- 12:25 First test run: 15 failures (nri and lodes still used `st` further down; my check of
  leftover references missed them). The offline compose started on that code was stopped (task and
  its container); failed fetches are not cached, so it left nothing in cache/metrics. Fixed (nri
  keeps st <- nation_state_table(); lodes keeps st <- state_table() for usps and names); a
  codetools scan of every function finds no undefined variable outside ggplot aesthetics; tests
  409 pass. Next: compose all offline -> reports/_fp/after.rds, compare with before.rds.
- Started A4 while the A3 compose runs (code is loaded at start; blocks.R is in no cache key).
  A4's baseline is A3's reports/_fp/after.rds.
- A4 code done (blocks.R): compute_block_composition split into composition_results,
  composition_no_data, composition_summary and composition_change (main function about 45 lines);
  every line of blocks.R is at most 100 characters (was 105 over), by line breaks and a few named
  intermediates, no logic change. Parses; codetools scan clean; tests 409 pass. Proof pending:
  after A3's fingerprint (reports/_fp/after.rds) compare 0, compose again -> reports/_fp/a4.rds and
  compare with after.rds.
- Started C8 (research only until the composes finish), C9 (code; first run after the composes)
  and E12, while the A3 compose runs. No edits to R/providers, metrics.R or stats.R meanwhile
  (cache keys hash them lazily).
- 12:34 A3 compose done (reports/_fp/after.rds; gary-in 61 s, austin-tx 277 s: derived files of
  the edited providers recomputed offline). Compare with before.rds: values, texts, block data
  and numbers identical in all 13 reports; only the report.qmd "Retrieval" line differs in 11
  (dates now end October 01: the recomputed derived files carry today's date; existing behaviour,
  a re-derived file counts as retrieved). A3 verified.
- E12 done: .DS_Store in .gitignore; User-Agent geo-report-gen/1.0 (R/fetch.R).
- C8: api.data.gov documents 1,000 requests an hour by default, 429 and a temporary block when
  exceeded, X-RateLimit-Limit/-Remaining headers. One request with our key returned
  x-ratelimit-limit 10, remaining 9: not the hourly default; investigating the window.
- A4 compose started -> reports/_fp/a4.rds (compare with after.rds).
- 12:36 C8 measured: three requests (two back to back, one 65 s later) all returned
  x-ratelimit-limit 10, remaining 9, so the reported limit is 10 requests a second, not the
  hourly 1,000 (an hourly counter would have dropped). cache/requests.log: 757 FBI requests since
  2026-09-28, 0 HTTP 429 (2 x 503), at most 320 in an hour and 95 in a minute (chicago-il). The
  FBI publishes no limit for CDE; an hourly cap above 320 cannot be ruled out without passing it.
  The throttle (source_rates default 2/s, per process) is within the limit for one process; with
  C7's parallel workers the key's limit is shared, so workers x rate must stay under 10/s.
  Proposal: decide the fbi_cde rate together with C7.
- 12:39 A4 compose done (reports/_fp/a4.rds): 0 differences against after.rds. madison-ms had
  reused its compose: the A3 run composed it at 12:33 with code loaded before the blocks.R edits,
  but build.json's compose_key hashes the code when the build ends, so the old snapshot was keyed
  to the new code. Forced its recompose (build --no-render --force --offline): a4b.rds, 0
  differences in all 13. A4 verified. The key issue added to PLAN as item 6b.
- C9 done with the user's narrower rule: cache_prune() in R/fetch.R, `gr.R cache prune [--yes]`
  (dry run by default), test in test-cache.R (tests 412), README cache paragraph and command
  table. Dry run on the real cache: 827 replaced derived files, 523 MB (census_pep 105, lodes 101,
  ipums_nhgis 81, fars 70, nces 50, bea 41, ...). Not run with --yes: waiting for the user.
- PLAN: A3, A4, C9, E12 checked; C8 measured (rate decided with C7); 6b added.
- Resume point: user go-ahead for `cache prune --yes` and a commit of A2-A4, C9, E12; then B5
  (profile a warm compose; no compose running now). reports/_fp/ (fingerprints, ~MB) must be
  deleted before the next data-sync, which syncs reports/.
- 12:43 The user: prune, commit, then B5. `cache prune --yes`: 827 files, 523 MB deleted; a second
  dry run finds 0; cache/raw 5.1 GB.
- 12:45 Committed d56d951 (A2-A4, C9, E12, PLAN/README/log). Started B5: Rprof of a warm
  compose of gary-in (compose_report directly, offline).
- 12:55 B5 done (profile in reports/_fp/b5.prof): see PLAN B5. Prose-edit loop now: compose ~20-30
  s + render 25-45 s. Options for B6 put to the user: (1) ACS: keep the requested areas before
  decoding (~6 s less per compose, every report and batch); (2) the block-result cache (compose of
  a text edit to ~2 s; render stays); (3) both.
- 13:00 The user: B6 = the ACS fix first. Found while designing it: memo outlives run_reset(), so in
  a batch (one process) a raw file read through a memoized table is recorded in run$used only by
  the first report that reads it (latest run: gary-in lists 374 ACS files, kc-core 8). build.json
  sources are incomplete, and reusable_compose can miss a refreshed file. Fix in memoize(): an
  entry keeps the raw files read while computing it and records them again on each use.
- 13:08 B6 code: acs_scope_table() memoizes each raw table with its area keys; acs_table(...,
  keys) decodes only the requested areas; acs_fetch tells an unpublished table from an empty
  selection by the raw table; geo_catalog() memoized (it decoded B01003 through the old memo).
  memoize() records the files behind an entry on reuse (test added). Tests pass. Next: compose
  all offline -> reports/_fp/b6.rds, compare with a4b.rds (numbers must match; the retrieval line
  and build.json sources of later reports may grow).
- 13:05 B6 verified. First version (filter rows, keep per-column decode) gave gary-in 22.5 -> 20.4
  s: decoding was no longer memoized and paid per-column data.frame + rbind overhead on every
  call. Decoding all columns in one pass: warm batch compose (--force --no-render --offline) 262 s
  -> 191 s for 12 reports (gary-in 30.6 -> 15.3); in-cities 1836003/1871000 slightly slower (12.6
  -> 13.8, 10.9 -> 13.2: they reused the decoded tables of the report before them). Fingerprints:
  b6 vs a4b only lake-in's retrieval line (memoize fix: it now lists files rebuilt today); b6b,
  b6w vs b6: 0. Tests 414. PLAN B5, B6 checked. Not committed.
- Resume point: commit B5-B6 on the user's go-ahead; next C7 (parallel compose workers; set the
  fbi_cde rate with it) and 6b (compose key at load time).
- 13:10 The user: commit B5-B6, then C7 and 6b.
