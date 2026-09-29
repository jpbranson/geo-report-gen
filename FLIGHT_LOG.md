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
   root; see README "Docker". Used on the user's second workstation, an Apple Silicon Mac.

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
