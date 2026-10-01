# Implementation plan and completion checklist

Environment found: empty directory; R 4.6.1 (project library via renv), Quarto 1.9.38 (bundled with
RStudio), no git history. The Census Data API now **requires a key** for every request (verified
2026-09-28: keyless calls redirect to `missing_key.html`). Machine-specific settings live in the
git-ignored `.env` (read at startup by R/load.R): `CENSUS_API_KEY`, `GR_HTTP_CONTACT` (the
user's email, sent only to BLS, which rejects automated requests without a contact),
`DATA_GOV_API_KEY` (FBI Crime Data Explorer) and `IPUMS_API_KEY` (IPUMS NHGIS).

## Architecture (one path: config -> data -> analysis -> report)

```
gr.R                    single CLI entry point (build, batch, preview, new, harvest,
                        text-export/import, find, catalog, verify, test)
config/                 settings.csv (scoped settings), reports.csv (report instances), themes.csv
catalog/                subjects, sources, metrics (documentation), recipes (computation), blocks,
                        geo_support (CSV, browsable as catalog.html)
content/                text.csv (scoped canonical text), prose/*.md, history_events.csv (cited context)
profiles/               audience manifests (general, early-childhood, economic-development)
R/                      engine: fetch+cache, providers, geography graph, statistics, content, charts, build
modules/                trusted custom analyses (explicit R modules)
quarto/                 report template assets (Lua placeholder filter, SCSS generated from theme)
reports/<id>/           generated editable report.qmd + snapshot + rendered HTML + build.json
cache/                  shared persistent cache: raw downloads, normalized tables, computed metrics
tests/                  testthat: statistics, geography, content round trips, cache keys, fixtures
demos/                  editing round trip and benchmark scripts
tools/                  moving cache/ and reports/ between machines (R2 sync, tar bundle)
Dockerfile, compose.yaml  the same toolchain in a container (amd64 and arm64)
```

Key decisions
- Census data through the Census Data API (targeted, cached per release/table/summary level/state);
  other programs through their bulk files (BLS, BEA, FHFA, BPS, PEP, NDCP). One fetch layer
  (httr2: retry/backoff, throttling, bounded parallel requests; atomic writes + file locks).
- Plain parquet (nanoparquet) + RDS cache with explicit, readable cache keys; no pipeline framework.
- The generated `report.qmd` is the inline-editing surface: prose in fenced divs, figure text in chunk
  options; builds harvest edits back into canonical records with 3-way conflict detection.
  Placeholders (`{name}`) are filled by a small Lua filter from a per-report values file.
- Tables as Markdown (knitr::kable) styled by the same theme; charts/maps with ggplot2 + sf.

## Checklist

Status as of 2026-09-29 23:30 (session 6; details in FLIGHT_LOG.md). `[x]` done and exercised by the
sample reports and tests, `[~]` implemented but unfinished, `[ ]` not started.

- [x] Environment: renv library + `renv.lock`, Quarto discovery, `.env` for key/contact (never logged)
- [x] Fetch/cache layer: keys, atomic writes, locks, retries, throttling, offline/refresh, request log
- [x] Geography: spec parsing (type:GEOID@vintage), name lookup w/ ambiguity, relationship graph
      (contains/intersects/coterminous), unions, overlap/parent-child detection, decomposition into
      published pieces, benchmark policy, national scope, support matrix (catalog/geo_support.csv)
- [x] Statistics: counts, shares, ratios, medians from distributions, MOE propagation, significance tests
      incl. overlap + part-whole dependence, status codes, constant dollars (R-CPI-U-RS)
- [x] Providers: ACS 5-yr (2009-2024), decennial 2000/2010/2020 (1990 is not in the API), PEP,
      LAUS, BEA CAINC1 and county GDP, CPI, building permits, FHFA HPI, NDCP, CBP (all
      industries), Texas HHSC, SAIPE, SAHIE, CDC PLACES, Nonemployer Statistics, LEHD LODES, BLS
      QCEW, NHTSA FARS, FEMA National Risk Index, USDA Food Environment Atlas, EAC EAVS, Census of
      Governments finance, FBI Crime Data Explorer, IPUMS NHGIS (census years 1790-2000, County
      Business Patterns 1970-1997)
- [x] Catalog: tables (17 subjects / 83 subtopics, 124 sources, 537 metrics, 335 operational), the
      browsable page (`gr.R catalog --html`) with scope and gaps, live `gr.R verify` (28 sources;
      424 ACS recipe x release checks, no gaps)
- [x] Content: manifests, block library, 3 profiles, scoped text, templates, cited history events,
      stale-fact warnings, `gr.R new` (subject/metric selection)
- [x] Authoring: inline harvest, bulk CSV export/import and conflict detection, covered by tests and
      demonstrated on a real report through regeneration (demos/round_trip.R, 10/10)
- [x] Rendering: theme, charts, maps, tables; reviewed and fixed (see FLIGHT_LOG.md)
- [x] Custom module example (modules/childcare_gap.R, inserted via profiles/early-childhood.csv)
- [x] Batch: two phases (compose, parallel render), isolated failures, per-report progress (resumable),
      logs, build manifests; cold/warm/resumed benchmark and invalidation checks (README, docs/)
- [x] Demos 1-11: sample reports, demos/round_trip.R (10/10), benchmark, README; PDF via Typst works
      (basic page layout, documented)
- [x] Tests: 321 expectations pass offline with fixtures (`gr.R test`)
- [x] Docs and lean review: README complete; dead code removed; R/blocks.R, R/geography.R and
      R/compose.R restructured, each with every report's output proven identical
- [x] Portability: Docker image (amd64, arm64); cache/ and reports/ move between machines by a
      two-way Cloudflare R2 sync (tools/data-sync.*) or a tar bundle (tools/bundle-data.*)

## Step agreed with the user 2026-09-28 17:20 (done 17:35; checking back)

1. [x] Run demos/round_trip.R: 10/10 checks pass (fixed: CRLF line breaks from a spreadsheet round
       trip looked like edits; read_table now normalizes them)
2. [x] Visual review of lake-in maps, tx-cities, ct-capitol (civic theme), austin-tx custom chart.
       Fixed: map palette and legend order; overlapping period bars in compare charts; overprinted
       and misapplied break labels (history_events.csv `sources` column); custom chart axis title
3. [x] R/blocks.R restructured (metric text split into named steps, long lines 35 -> 14); every
       report's values.json, report.qmd and block data identical (239 fingerprints, 0 differences)
4. [x] PDF via Typst: renders; added Typst format settings (TOC, numbering, theme font and paper,
       smaller table text); status documented in README

## Step agreed with the user 2026-09-28 17:45: readability pass on geography.R and compose.R (done 18:20)

- [x] R/geography.R (725 -> 686 lines; longest function 84 -> 50 lines): geo_parents split into
      county_shares, state_shares, regional_parents and parent_rows; one geo_counties() replaces
      three inline copies;
      geo_contains is a short list of known containments (TRUE/FALSE); union and benchmark code
      split into named steps (describe_members, relation_matrix, benchmark_candidates,
      benchmark_entity); same_territory() replaces is_coterminous + same_population_area; name
      search vectorized (`find` / name: specs about 1 s instead of about 40 s)
- [x] R/compose.R (357 -> 375 lines; write_qmd 107 -> 24 lines): write_qmd split into qmd_header
      (the literal YAML), block_markdown and figure_chunk; compute_blocks; simpler yaml_str
      (identical output on tricky strings); dead variables removed
- [x] Proof: 328 fingerprints (snapshot files byte-identical, values.json, qmd_base.json, report.qmd,
      every block) 0 differences; 213 geography probes (specs, names, parents, relations, unions,
      benchmarks, errors) identical except two intended changes; 117 tests; batch up to date

## Step agreed with the user 2026-09-28 18:25: expand metric coverage (steps 1-2 done 19:20; checking back)

Starting point: 48 of 398 cataloged metrics operational; health, food access, environment,
industries, households, civic, public safety and public finance had none. Now 137 of 399.
1. [x] ACS: 20 research-catalog rows that duplicated operational metrics or were views of them
       merged away; 83 recipes (variable IDs from the API group metadata, labels reviewed in 2009,
       2014, 2019 and 2024) for households and families, health insurance and disability, broadband
       and computers, commute mode and vehicles, school enrollment and attainment, industry and
       occupation of residents, earnings, income support, housing stock and cost burden, nativity,
       language, mobility, veterans; 23 blocks placed in the three profiles. The catalog's
       `history_start` now limits computed periods, so line numbers that meant something else in
       older releases (occupation and veterans before 2006-2010, children's insurance before
       2013-2017) are never read. Formatting for calendar years, coefficients and "x per y" units;
       bar layout for compositions with many categories; legends wrap
2. [x] SAIPE and SAHIE (R/providers/small_area.R): annual poverty, child poverty, median household
       income (comparable from 2005) and uninsured rates under 65 (from 2008) for counties, states
       and the nation; combined areas get values without a margin of error; 4 blocks
3. [x] Checked back with the user (19:30): add four new sources, in this order, then check back

## Step agreed with the user 2026-09-28 19:30: four new sources, in order, then check back

1. [x] CDC PLACES (R/providers/places.R): 21 metrics (chronic conditions, health status and
       disability, behaviors and checkups, social needs) for counties, places, tracts and ZCTAs from
       the latest release only; crude prevalence with 95% intervals converted to 90% MOEs; states
       summed from counties (CDC's method for groups of areas), the U.S. row as published; 5 blocks
       (3 tables, a tract map, social needs). Engine: a source's reason for a missing value is shown
       in "What is not shown"; a facts table without any study-area value says why instead of
       showing dashes; empty comparison columns are dropped
2. [x] County Business Patterns for all industries (R/providers/cbp.R, replacing the child care
       only adapter): establishments, mid-March jobs and payroll by NAICS code for counties, states
       and the nation, 1998-2023; withheld cells (before 2017) and unpublished cells with fewer than
       3 establishments (from 2017) are "suppressed" with the reason. 23 metrics (jobs,
       establishments, payroll per employee, child care jobs, 19 sectors); blocks jobs-trend,
       business-summary, jobs-industry-mix, payroll-trend (economic development), childcare-jobs
       (early childhood). Also fixed: short names cut at the first comma ("Travis" for a
       three-county area); long chart labels wrap and get room; bar compositions keep the study
       area first
3. [x] FEMA National Risk Index (R/providers/nri.R, v1.20 county table): 18 metrics (risk, social
       vulnerability, community resilience and heat wave scores for single counties; expected
       annual loss in total, per resident and per $1 million of buildings, summed to states,
       regions, divisions and the nation; loss by hazard in 11 groups); section "Natural hazards"
       (general: scores, losses, losses by hazard; economic development: losses). FEMA's required
       statement is in each block's source note. Tracts not used (national 635 MB file only).
       Engine: facts tables and compositions show the county as context for cities (as metric
       blocks do); render-time placeholders now prefer the block's values (runtime.R had the
       report's first, so context captions said "Gary")
4. [x] USDA ERS Food Environment Atlas (R/providers/fea.R, July 2025 CSV): 7 published county
       values (low access, low income and low access, households without a car and low access,
       2019; grocery, convenience and fast-food per 10,000 residents, 2020; SNAP-authorized stores,
       2023); block food-environment (general "Food access" section, early childhood). No state
       values or rate denominators are published, so no sums; Connecticut uses former counties.
       Verified: tests 176 pass; gr.R verify 18 of 18 sources ok, 424 ACS recipe checks, no gaps;
       demos/round_trip.R 10 of 10
5. [x] Checked back with the user (21:25)

## Step agreed with the user 2026-09-28 21:30: three more sources (keys and access checked)

1. [x] EAC Election Administration and Voting Survey (registration and turnout; by election
       jurisdiction, summed to counties, states and the nation): R/providers/eavs.R, 2020 and 2024;
       CVAP from ACS B29001; mail share left documented (method counts do not add up in some states)
2. [x] Census Bureau government finance individual unit files (county government for counties,
       city government for places): R/providers/govfin.R, FY2022 Census of Governments (complete);
       8 metrics (property tax, taxes, long-term debt, police spending per resident), one table
3. [x] FBI Crime Data Explorer API (api.data.gov key in .env as DATA_GOV_API_KEY, sent only as
       a request header, never logged)
4. [x] Checked back with the user (22:35)

## Step agreed with the user 2026-09-28 22:40: county crime and an NHGIS investigation

Reports may keep growing (the user edits down), so every new block goes into the profiles.
1. [x] County crime rates: sum every police agency the FBI lists in the county (city police,
       sheriff, county, university, state police posts, tribal), with a caveat on overlap,
       multi-county agencies and partial reporting. Done: R/providers/fbi.R lists every agency by
       the FBI's county names (all match Census names except statewide agencies); a city
       department in several counties is divided by Census place-by-county population (636 of
       653 match a place; the rest by county population); a county year needs agencies serving
       75% of residents (after the FBI's 75% rule for metropolitan areas). Parts of a city in one
       county use the same division, so the Travis County + Austin union now has values. Caveat
       in the crime table and trend notes, catalog and README
2. [x] Investigate IPUMS NHGIS for historical files older than the project's current data:
       docs/nhgis.md and catalog row ipums_nhgis (needs a free account and API key; not
       implemented)
3. [x] Checked back with the user (23:25)

## Step agreed with the user 2026-09-28 23:30: FBI screen; NHGIS census years

1. [x] FBI: an agency's year with under a quarter of its usual offenses (its median year, when
       that is at least 20) counts as not reported (Kansas City, Kansas in 2023)
2. [x] IPUMS NHGIS provider (IPUMS_API_KEY in .env, sent only as the Authorization header):
       census years 1970-2000 for the existing income, poverty, education, work and commuting
       measures. Done: R/providers/nhgis.R (httr2 client, one cached extract of 7 time series
       tables, nominal integration, current FIPS codes); 13 metrics (median household and per
       capita income 1980-2000 in constant dollars of the prior year, poverty, labor force
       participation, employment ratio, bachelor's or higher 1970-2000, 7 commuting modes
       1990-2000); dots in 6 trend charts and 1990/2000 bars in the commuting chart. Engine:
       recipe dollars "prior_year"; compositions accept a category from two sources; charts
       mixing census years and ACS periods label the axis "Year". Test fixture is made up
       (NHGIS terms)
3. [x] Checked back with the user (00:20)

## Step agreed with the user 2026-09-29 00:25: more NHGIS history

1. [x] Population census counts from NHGIS: counties, states and the nation from 1790 (A00),
       places and county subdivisions from 1970 (AV0), in the long population history chart.
       One metric (pop_census_nhgis) names its years per table; it replaces the NBER 1900-1990
       series in that chart. A table NHGIS lacks at a level is "not applicable" with the reason
2. [x] County Business Patterns 1970-1997 from NHGIS (all-industry jobs, establishments and
       payroll; SIC era, a separate series from the 1998+ NAICS data). Separate source
       ipums_nhgis_cbp (annual); new block jobs-long-history (general and economic development);
       payroll-trend from 1978 (the price index's first year). Data fixes: 1975 state payroll
       is in thousands of dollars; "D" in a value cell means withheld
3. [x] Checked back with the user (01:00)

## Proposed next steps (saved 2026-09-29; all three done as review items 23-25 below)

1. [x] Constant dollars before 1978: extend the price index back with the regular CPI-U (BLS
       suggests CPI-U for years before the R-CPI-U-RS begins in 1978), scaled to meet the
       R-CPI-U-RS in 1978. Adds payroll per employee for 1974-1977 (payroll-trend could then
       start in 1974) and allows constant dollars before 1978 anywhere.
2. [x] Connecticut planning regions: sum town (county subdivision) census values from NHGIS into
       the 2022 planning regions, mapping towns by code as the EAVS provider does
       (ct_town_regions()). Works for counts and shares (poverty, education, work, commuting,
       population); not for medians such as household income.
3. [x] Long-run sentences in chart text: add a sentence on the change since the earliest census
       year to charts that mix census years and ACS periods (e.g. "Since 1979, median household
       income fell from $70,000 to $38,000"), since the text now describes only the ACS years.

## Step agreed with the user 2026-09-29 09:00: Docker image for an Apple Silicon Mac (done 09:40)

1. [x] Dockerfile, .dockerignore and compose.yaml (checkout mounted at /app; local time zone;
       preview on port 4848); README section "Docker"
2. [x] Verified on amd64 and arm64: tests, byte-identical report values and text, PDF, preview
3. [x] Portable folder (arm64 image, cache and reports, setup steps); Docker files pushed to GitHub

## Step agreed with the user 2026-09-29 14:35: three jobs and output sources, in order (done 16:15)

All three are cataloged and their sample downloads worked (2026-09-28); each needs a provider,
recipes and blocks. As before, every new block goes into the profiles.
1. [x] LEHD LODES 8.4 (census_lehd_lodes), 2002-2023 (done 15:10): R/providers/lodes.R sums
       block-level WAC and RAC files through each state's crosswalk (2020 blocks, 2024
       boundaries) to states, counties, places and place parts, county subdivisions, tracts,
       block groups, ZCTAs and metro areas; unions are exact. Settled: primary jobs (JT01)
       throughout, so jobs and employed residents both count workers. No national or regional
       totals (not published; a sum of states is incomplete in most years). State-years without
       job data (AK 2017-2023, MI 2022-2023, DC 2002-2009, MA 2002-2010, AR, AZ, MS and NH in
       2002-2003) are unavailable with the reason; their stub files are ignored. 26 metrics (jobs,
       employed residents, jobs per 100 employed residents, 3 earnings bands, 20 sectors); blocks
       jobs-and-workers, primary-jobs-trend, jobs-per-resident-trend, primary-jobs-industry-mix,
       job-earnings-mix, jobs-per-resident-map (general: 3, economic development: 6); history
       event for federal jobs from 2010; a provider's fixed_boundaries replaces the annexation
       note. Verified: tests 239; verify 23 of 24 (FEMA 403 in Docker, as before); round trip
       10/10; batch 12 reports ok, austin-78704 rejected as intended. Commuting shares (OD files,
       83 MB a year for California) left for later
2. [x] BLS QCEW (bls_qcew), done 15:50: R/providers/qcew.R reads the annual singlefile ZIPs and keeps
       all-industry rows by ownership, private NAICS sectors and private child day care (624410)
       for counties, states and the nation; regions and divisions sum their states. Changed from
       the plan: years 2001-2025, not 1990-2025. BLS's 1990-2000 files are a NAICS reconstruction
       of SIC records that omit withheld rows and hold one-year spikes found by a scan of every
       county and state (Oakland County MI 1997 finance: 179,334 jobs and $57.3 billion vs 38,941
       and $1.6 billion in 1996, inflating Michigan and the nation; New Jersey 1995 pay +42%);
       none from 2001. Withheld cells (N) and absent rows are "suppressed", never zero. 29
       metrics (jobs, establishments, pay per job, private pay, 19 private sectors and 3 levels of
       government, child care establishments, jobs and pay); blocks employer-jobs-pay,
       pay-per-job-trend, jobs-by-ownership-industry (general / economic development),
       childcare-pay, childcare-pay-trend (early childhood); subtopic childcare_workforce. BLS
       sources named bls_<program> now get the BLS contact and rate. Cache 1.9 GB (25 ZIPs)
3. [x] BEA GDP by county (bea_cagdp), done 16:15: R/providers/bea.R reads CAGDP1 and CAGDP2 through a
       shared ZIP reader (CAINC1 uses it too). Current-dollar GDP, all industries and 12 industry
       groups that add up to the total (county detail by single sector is withheld up to 40% of
       the time); regions and divisions sum states; GDP per resident with CAINC1 population.
       Changed from the plan: real growth uses BEA's chain-type quantity index (2017 = 100)
       instead of chained dollars, so the text compares growth, not levels; like chained
       dollars, it has no value for combined areas or regions. 15 metrics; blocks gdp-summary,
       real-gdp-trend (general, economic development), gdp-industry-mix (economic development).
       Dollar amounts from $1 trillion print as trillions
4. [x] Verified after each source (tests 263; verify 25 of 26, FEMA 403 in Docker; round trip 10/10;
       batch 12 ok, austin-78704 rejected as intended); checking back with the user (16:15)

## Step agreed with the user 2026-09-29 16:24: five more sources, in order (1-2 done; 3-5 continue as items 1-3 of the data source queue below)

Ranked by gap filled, geography, history and effort (catalog 16:20: education has 5 operational
metrics, public safety 3, civic participation 2; nothing measures deaths, school enrollment or
self-employment). Every new block goes into the profiles; FLIGHT_LOG.md is kept as a running log
so work can resume after an interruption.
1. [x] Census Nonemployer Statistics (census_nes), done 16:45: R/providers/nes.R reads the bulk county,
       state and U.S. files for 1997-2023 (names and headers vary by year); flagged cells (D through
       2016, S) are suppressed, missing industries are zero; regions sum states; rates use BEA
       population with PEP where BEA has none. 23 metrics (businesses, per 1,000 residents,
       receipts per business, 18 sectors, child care businesses and receipts per business); blocks
       nonemployer-summary (general, economic development), nonemployer-trend and
       nonemployer-industry-mix (economic development), childcare-nonemployers and
       childcare-nonemployer-trend (early childhood). Tests 272; verify 26 of 27 (FEMA 403);
       round trip 10/10; batch 12 ok. Cache 134 MB
2. [x] NHTSA FARS (nhtsa_fars), done 17:30: R/providers/fars.R, 1982-2023. People from the harmonized
       auxiliary files (1996, which has none, from the main files with matching codes); crashes
       from ACC_AUX through 2000 and the main accident file from 2001 (coordinates). Counties by
       crash codes (retired codes mapped); places, place parts and tracts by point-in-polygon in
       full-resolution TIGER/Line 2024 boundaries from 2001 (95% of a state-year's crashes
       located); sums for the nation, regions, divisions and metro areas. A second provider,
       nhtsa_fars_5yr, sums deaths over ACS 5-year periods (2009-2013, 2014-2018, 2019-2023) with
       person-years = 5 x the ACS population; tracts only from 2020 tracts. 6 metrics; blocks
       traffic-safety, traffic-death-rate-trend, traffic-deaths-trend (general, safety section).
       Engine: providers can name their multiyear period note (period_phrase). Tests 288; verify
       ok (FEMA 403 only); round trip 10/10; batch 12 ok. Cache 555 MB plus 72 MB of TIGER boundaries
3. [ ] NCES Common Core of Data (nces_ccd), 1986-2025: public school enrollment by grade (public
       pre-K for early childhood), schools, student-teacher ratios; built from school locations
       (EDGE geocodes) since districts are not a supported geography; large files (school
       membership about 190 MB a year)
4. [ ] NOAA Storm Events (noaa_storm_events), 1950-present: storm deaths, injuries and damage by
       event type and year for counties; zone-based events (43% in 2024) need NOAA's zone-county
       correlation; damage is rough and nominal
5. [ ] County Health Rankings (uwphi_chrr), 2010-2025, counties: premature death, life expectancy,
       injury deaths and other county measures; secondary compilation with pooled years; terms
       allow non-profit use (commercial use needs written consent)
6. [ ] Verify (tests, gr.R verify, demos/round_trip.R, batch) after each source; check back with
       the user after all five

## Step agreed with the user 2026-09-29 17:49: data bundle command (done 17:55)

1. [x] tools/bundle-data.sh (Mac/Linux) and tools/bundle-data.cmd + .ps1 (Windows) write
       <Downloads>/geo-report-data-<date>-<commit>.tar (cache/ and reports/, never .env) and a
       .sha256; tested on the Mac (4.0 GB, extraction identical); README "Moving the data to
       another machine". Windows script reviewed, not run (no PowerShell on the Mac)

## Step agreed with the user 2026-09-29 23:00: two-way data sync through Cloudflare R2 (done 23:27)

1. [x] tools/data-sync.sh (Mac/Linux) and tools/data-sync.cmd + .ps1 (Windows) run rclone bisync
       between the project folder and the R2 bucket geo-report-data, with the rules in
       tools/data-sync-filters.txt (cache/raw, cache/geo and reports; not cache/metrics, lock files
       or partial downloads). Deletions reach the other machine (cache pruning may come later);
       deleted or overwritten bucket files move to trash/<time>/ (30-day lifecycle rule); newer
       copy wins a conflict, the other kept as <name>.conflict1; >50% deletes stop until --force
2. [x] Tested against a local `rclone serve s3` (both scripts, two scratch machines); README
       "Moving the data to another machine" leads with the sync and its one-time setup
3. [x] R2 bucket and lifecycle rule created with wrangler; first sync from the PC (4,468 files,
       3.98 GB); the Mac gets its own token and syncs next

## Step agreed with the user 2026-09-29 19:50: fixes from two reviews of 711d8f3

Merged from docs/review-2026-09-29-a.md (A) and docs/review-2026-09-29-b.md (B), ordered by harm.
Left out where the reviews disagree: the LAUS break marker year, saving normalized ACS tables as
parquet, and keeping or removing the per-entity metric cache (with its lock file per entry).
Before each change: fingerprint every report (values.json, report.qmd, block digests) and compare
after, so only the intended output changes. Progress notes in FLIGHT_LOG.md.

Wrong or unexplained output in published reports
1. [x] CBP: zero-fill a sector only when the county's all-industries row exists that year; otherwise
       unavailable with a reason; `change_values()` never says "higher than" from a first value of 0 [B]
2. [x] Placeholders: a missing value (NA) is a build warning (a typo stays an error); batch copies
       gr-placeholders warnings into build.json and counts them; no-data text field `no_data` [A]
3. [x] Race composition: no change sentence across a definitional break; show all four ACS periods [B]
4. [x] `detail = brief` keeps legends and caveats: new `legend` field shown at every level (marks,
       census dots, missing bars, breaks, county crime caveat); `note` keeps definitions/methods [A]
5. [x] `figure_notes()` (was method_note) collects `breaks` from every plotted metric [A]
6. [x] Appendix: keep the piece-level reason unless the provider says the table is not published;
       names instead of keys such as county:09110 [A + B]
7. [x] Turning points for census counts and administrative series (catalog `uncertainty`) [A]
8. [x] `@map.note` describes the dashed outline the map draws [A]
9. [x] Crime across the 2021 NIBRS change: FBI converts NIBRS reports to summary counts with the
       hierarchy rule reapplied, so no split; stated in the FBI rate metrics' breaks [both]

Author edits or settings silently lost
10. [x] Harvest stops when text outside the `:::` fences changed [A]
11. [x] text-import warns when a narrower record will hide the imported text [A]
12. [x] Block options: manifest row beats library option; precedence default < profile < library <
        report < manifest; effective window in build.json; README. Open for the user: B proposed
        profile above library, but then the economic-development profile (1969) would cut the
        long population chart from 1790 and early childhood (2000) would drop 1998-1999 child
        care jobs; the user chose to keep profiles below library windows (2026-09-29 21:00) [both]
13. [x] `viz` validated per block kind [B]

Failures and cache correctness
14. [x] Per-metric failure isolation (a missing IPUMS key keeps the ACS values); census_hist removed [A]
15. [x] Metric cache key includes the provider's code version [A]
16. [x] One text resolver for compose, harvest/import and labels [A]

Iteration speed
17. [x] NHGIS lookup key built once (nhgis_rows 5 s -> 0.4 s); FBI code is 1.8 s of a 37 s compose: left as is [both]
18. [x] Skip compose when the report's inputs and raw files are unchanged (unchanged batch 166 s -> 8 s) [B]
19. [x] Report date out of the render hash [both]
20. [x] "Retrieved on" dates from .meta.json, not file times [A]
21. [-] Block-result cache: not built. After 17-18 a prose edit of gary-in takes 68 s (compose 37, render 29); the user decides whether that needs the cache [A]
22. [x] README benchmark and docs/benchmark.csv refreshed (demos/benchmark.R --warm): unchanged batch 8 s [both]

History in the prose
23. [x] Long-run sentence across census years and ACS periods (proposed step 3), checked on all reports [both]
24. [x] Connecticut planning regions: NHGIS census counts and shares summed from towns (ct-capitol 1970-2000) [both]
25. [x] Price index before 1978: Census Bureau joins (CPI-U-X1 1967-1977, CPI-U before), payroll-trend from 1974 [both]
26. [x] Homeownership 1970-2000 from NHGIS B37 in tenure-trend (extract 10) [A]
27. [x] Both EAVS elections: new block voter-turnout-trend (general profile) [A]
28. [x] FHFA counties from 1975 -> house-prices from 1975; FBI from 1985 with the 2013 rape-definition break [B]

Cleanup
29. [x] `catalog --check`: `stat_type` agrees between recipes.csv and metrics.csv [A]
30. [x] Relative-index blocks: nominal dollars not blamed on a missing price index [B]
31. [x] Remove `library(tidyr)` and the `data/local` reference [B]
32. [x] Cache prune note in README (what can be deleted, and when) [A]
33. [x] lake-in shows income-distribution and rent-distribution [A]
34. [x] Availability appendix: rows that differ only in the measure are one row [B]
35. [x] BLS contact email in FLIGHT_LOG.md history: the user keeps it (no action) [B]

## Data source queue (agreed with the user 2026-09-29 23:50)

Everything proposed on 2026-09-29 23:45, in order. Groups: the three sources left from the 16:24
step (A), sources that already have a provider (B), new sources with the thinnest subject first
(C; operational / cataloged metrics as of 2026-09-29, so revisit the order after B), and the open
NHGIS additions (D). Each item starts by comparing its cataloged metrics with the operational ones
and merging duplicates (likely pairs are named), as the ACS step of 2026-09-28 did. After each
item: tests, `gr.R verify`, demos/round_trip.R, batch; every new block goes into the profiles;
check back with the user after each group.

A. Left from the 2026-09-29 16:24 step
1. [x] NCES Common Core of Data (nces_ccd), done 2026-09-30; Education 5 / 10. R/providers/nces.R,
       school years 2017-18 to 2024-25 from NCES's yearly EDGE school layers (administrative data
       joined to the geocode by school ID; the 2018-19 geocode layer serves 2017-18 records, so
       that year uses the dated EDGE_GEOCODE_PUBLICSCH_1819 file). Built from school locations,
       since districts are not a supported geography: states and counties by NCES codes, places
       and tracts by school coordinates, sums above. A value needs 95% reporting in every state
       part. 5 metrics (public_schools_count_ccd, public_school_membership_ccd,
       public_prek_membership_ccd, public_school_teachers_ccd,
       public_school_students_per_teacher_ccd); blocks public-schools,
       public-school-enrollment-trend, public-prek-trend. Earlier CCD history (1986-2016) needs
       the older bulk files and their layouts: not built. Tests 330; verify ok; round trip 10/10;
       batch 12 ok
2. [x] NOAA Storm Events (noaa_storm_events), done 2026-09-30; Environment and climate hazards
       21 / 30. R/providers/noaa.R, 1950-2025 (a year counts as complete 60 days after it ends).
       File names carry a creation date, so the yearly files come from the NCEI directory listing.
       Records are counties or NWS forecast zones (43% zone-based in 2024); marine zones (state
       codes 85-99) are left out. Zone events reach counties through NWS's current county-zone file
       (bp16ap26.dbx): a zone event counts in each county of its zone and shares its deaths and
       damage equally; a state has county values in a year only when 95% of its zone events match
       a current zone (about half the states before 2013, a fifth in 2022-2025; NWS keeps no
       public archive of older files). Nation, regions, divisions and states need no zones.
       Series labels split 1950-54 (tornadoes), 1955-95 (plus thunderstorm wind and hail) and
       1996 on (all types). Damage in event-year dollars, shown in constant dollars. 3 metrics
       (events, deaths, property damage); blocks storm-events, storm-events-trend,
       storm-deaths-trend, storm-damage-trend (from 1996; general and economic-development).
       Tests 345; verify ok; round trip 10/10; batch 12 ok
3. [-] County Health Rankings (uwphi_chrr); Health 24 / 42. premature_death_ypll_chr,
       life_expectancy_chr, food_environment_index_chr. Releases 2010-2025, counties, states and
       the nation; each measure pools its own years. Terms: personal or non-profit use only
       (commercial use needs written consent), so confirm with the user before building.
       SKIPPED 2026-09-30 on the user's instruction to skip items needing the user; see
       FLIGHT_LOG.md blockers

B. Sources that already have a provider (new recipes; possibly new tables or files)
4. [x] Child care prices, NDCP (dol_ndcp), done 2026-09-30: 8 new operational metrics from 11
       documented ones. Center toddler and school-age; family toddler, preschool and school-age
       (the documented "home" IDs renamed "family" to match childcare_price_family_infant_ndcp);
       75th percentile center and family infant; women's labor force participation with children
       under 6 only (counties and, from the file's state columns, states). Merged as duplicates:
       childcare_price_home_infant_ndcp (= family_infant) and
       childcare_price_burden_center_infant_ndcp (= infant_share_income). Not built:
       childcare_price_age_band_ndcp (22 six-month band series; one metric holds one value).
       Blocks childcare-price-table, working-mothers-trend (early childhood). Tests 351; verify
       ok; round trip 10/10; batch 12 ok. 2008-2022
5. [x] Decennial census (census_dec), done 2026-09-30: 9 documented metrics became 14 operational
       ones for 2000, 2010 and 2020 (variable IDs checked against the Census API): households,
       average household size (population in households / households), vacancy rate,
       homeownership rate, median age, three household-type shares (family, married-couple,
       living alone; 2000 works too, unlike the documented 2010-2020) and six race and Hispanic
       origin shares as the group race_ethnicity_decennial. Merged as duplicates:
       total_population_decennial (= pop_total_dec), housing_units_decennial
       (= housing_units_dec). Engine: period-specific recipes now fetch denominator variables
       (metrics.R var_by_period). Blocks race-ethnicity-census, census-counts,
       households-census-trend (general profile). Tests 353; verify ok; round trip 10/10
6. [x] Population estimates (census_pep), done 2026-09-30: of 8 documented metrics, four were
       duplicates of pop_estimate_pep (which already carries 2000-2025 from the intercensal and
       Vintage 2025 files, including cities and county subdivisions): population_estimate_pep,
       population_intercensal_2000_2009_pep, population_intercensal_2010_2019_pep and
       subcounty_population_estimate_pep. Four became operational: annual population change
       (percent), natural increase, net domestic and net international migration rates per 1,000
       residents, 2021-2025 (Vintage 2025), for the nation, regions, divisions, states and
       counties. They form a second provider, census_pep_components (new derived source), so
       cities report the county and larger areas instead of "not available"; rates use the
       average of the two July 1 estimates as the Census Bureau does (Lake County IN 2021
       natural increase -1.571, Indiana domestic 2.215, international 0.892 reproduce the
       published rates). Blocks population-change, population-change-trend (general). Tests
       358; verify ok; round trip 10/10; batch 12 ok
7. [x] BEA county personal income (bea_cainc), done 2026-09-30: 5 documented metrics became 17.
       Personal income (CAINC1 line 1, already loaded), government transfers as a share of
       personal income, income maintenance benefits per resident and earnings by place of work
       (CAINC30 lines 10, 50, 60, 100, 180; 1969-2024), and earnings by industry as 13 group shares
       of total earnings (CAINC5N, 2001-2024; the same groups as the GDP mix plus farm, and a
       group is withheld when any of its lines is (D)). Income and earnings are in dollars of each
       year and shown in constant dollars. Provider split into bea_cainc1() and bea_income_long()
       (the big tables are read only when asked for); region and division sums shared with the GDP
       code (bea_sum_regions). Blocks income-sources, transfer-share-trend (general, economic
       development), earnings-industry-mix (economic development). Tests 368; verify ok; round
       trip 10/10; batch 12 ok
8. [x] BLS unemployment, LAUS (bls_laus), done 2026-09-30: unemployed and employed persons (all
       levels) and, as a second provider bls_laus_rates (new derived source), the labor force
       participation rate and employment-population ratio for the nation, regions, divisions and
       states, 1976-2025: LAUS publishes the civilian noninstitutional population (measure 09)
       for states only, so the rates are labor force or employed over that population, with
       regions and the nation as sums of states (Indiana 2024: 63.7%, as published); counties and
       cities fall back to the state. Merged as a duplicate: civilian_labor_force_laus
       (= labor_force_laus). Blocks labor-force-counts, participation-trend (general, economic
       development). Tests 371; verify ok; round trip 10/10; batch 12 ok
9. [x] Texas child care licensing (tx_hhsc), done 2026-09-30: five documented metrics became six
       operational ones with the existing capacity metric: licensed centers, licensed homes and
       registered homes (the documented "homes by type" split in two), share of centers accepting
       subsidies, and capacity per 100 children under 5 (ACS 5-year denominator, as FARS uses ACS
       population). Merged as a duplicate: childcare_licensed_capacity_tx_hhsc
       (= childcare_capacity_tx). The query now groups by subsidy acceptance and keeps operations
       in operation (status Y), which the existing capacity definition already said; the cache
       file is capacity_by_county_type.parquet. Block childcare-supply-tx (early childhood).
       Current snapshot, Texas only. Tests 377; verify ok; round trip 10/10; batch 12 ok
10. [x] Building permits (census_bps), done 2026-09-30: county history extended from 2000 to 1990 (same
        file layout), with units in 1-unit buildings and in buildings of 5 or more units, and units
        per 1,000 residents (July 1 estimates from the population estimates, 2000 on). Places stay
        at 2007-2025: older place files have no FIPS place code (only a 6-digit permit-office ID,
        which would need a crosswalk). Merged as a duplicate: permitted_units_total_bps
        (= housing_units_authorized_bps). Blocks permits-by-size, permits-rate-trend (general,
        economic development). Tests 381; verify ok; round trip 10/10; batch 12 ok

C. New sources, thinnest subject first
11. [-] MIT Election Lab county presidential returns (medsl_county_pres); Civic participation
        2 / 12. Votes cast, Democratic and Republican shares (2000-2024), turnout of citizens of
        voting age (2012-2024). Counties, states, nation; CC0. The Harvard Dataverse download
        needs a guestbook form: the user downloads the file once (Claude does not fill in forms).
        SKIPPED 2026-09-30 on the user's instruction to skip items needing the user: once the
        user has saved the county returns file into cache/raw/medsl_county_pres/, the provider
        can be built (see FLIGHT_LOG.md blockers)
12. [x] Indiana child care provider listings (in_fssa_provider_listings), done 2026-09-30; Child care
        13 / 48 before. The three HTML tables of FSSA's provider page are parsed in base R
        (rvest and xml2 are not in the renv library and were not added; a layout change stops the
        build with a message). Parsed counts match the catalog's sample: 770 licensed centers
        (capacity 86,053), 1,813 licensed homes (23,754), 732 registered ministries (no
        capacity), 92 counties. Seven metrics: centers, homes and ministries (the documented
        "providers by type" split in three), licensed capacity, capacity at Paths to QUALITY
        levels 3-4 and its share of capacity, capacity per 100 children under 5 (ACS
        denominator). Current snapshot, Indiana only, county totals. Block childcare-supply-in
        (early childhood). The childcare_gap example module still reads Texas capacity only.
        Tests 386; verify ok; round trip 10/10; batch 12 ok
13. [-] HUD homelessness counts, PIT and HIC (hud_pit_hic); Housing 19 / 45. Total, sheltered,
        unsheltered, chronic, in families, veterans (2011-2025), year-round shelter beds;
        2007-2025. Published by Continuum of Care: first catalog and add a CoC-to-county
        crosswalk (not cataloged yet) for county and city values; .xlsb workbooks
        BLOCKED 2026-09-30: huduser.gov answers scripted requests with an AWS WAF bot challenge (HTTP
        202, no file), and bypassing it (for example with a browser User-Agent) is not done. Also
        needs an .xlsb reader and a CoC-to-county decision. See FLIGHT_LOG.md blockers
14. [x] USDA Food Access Research Atlas (usda_ers_fara), done 2026-09-30; Food access 10 / 20. R/providers/fara.R:
        the tract files of the 2025 SNAP-authorized Retailer Access Map (SRAM: straight-line and driving
        distance, 2020 tracts) and the 2019 Large Retailer Access Map (LRAM, 2010 tracts) are summed to
        counties, metro areas, states, regions and the nation; tract reports show the tract itself
        (SRAM only: 2010 and 2020 tract codes differ); cities have no values and show their county.
        Seven metrics from four documented ones: LILA tracts (straight-line and driving; count and
        share of tracts), residents beyond 1 mile urban / 10 miles rural (straight-line and driving)
        as a share of residents, and the 2019 LRAM LILA tract count. The 2015 and 2010 LRAM editions
        are not in the catalog's URLs and are not read. Checked: U.S. 8.6% of residents far from a
        SNAP retailer in a straight line (28.4 million), 2,356 LILA tracts; 2019 LRAM 9,293 LILA
        tracts. Block food-access-tracts (general). Tests 393; verify ok; round trip 10/10; batch 12 ok
15. [-] Census population estimates by age, sex, race and Hispanic origin
        (census_pep_county_characteristics), done 2026-09-30; Demographics 22 / 40. Counties 2020-2025
        (Vintage 2025) from cc-est2025-agesex-all.csv (10 MB) and cc-est2025-alldata.csv (105 MB), added
        up to states, regions, divisions and the nation (medians are county-only). Eight metrics from
        three documented ones: share age 65 and over, median age, and six race and Hispanic origin shares
        as the group race_ethnicity_pep (modified race: Some Other Race is reassigned, so shares differ
        from the census and the ACS). Blocks race-ethnicity-estimates, age-estimates (general). The
        2010-2019 intercensal files (same layout) are not read. Tests 398; verify ok; round trip 10/10;
        batch 12 ok. REMOVED 2026-09-30 (1.0 checklist D1): provider section, recipes, verify
        check, test and cached files deleted; source and metric rows kept as documentation
16. [x] HRSA health professional shortage areas (hrsa_hpsa), done 2026-09-30; Health 24 / 42. R/providers/hpsa.R:
        the current designations (status Designated) of primary care, dental health and mental health
        from HRSA's daily files, by county (the component's county or a facility's county), counted
        once per designation in a state or larger area and in a metro area. Six metrics from three
        documented ones: the number of designated HPSAs and the highest HPSA score for each
        discipline. Primary care check: 21,444 designated components and 7,822 designated HPSA IDs, as
        in the catalog's sample. HRSA codes Connecticut by its planning regions, which match the 2024
        geography. Current snapshot only (HRSA keeps no archive; the designation and withdrawal dates
        could rebuild a history but were not used); no city or tract values. Block shortage-areas
        (general, health). Tests 403; verify ok; round trip 10/10; batch 12 ok
17. [-] BLS occupational wages, OEWS (bls_oews), done 2026-09-30; Employment 20 / 34. R/providers/bls.R reads
        oe.data.0.Current (330 MB, in chunks; only the all-occupation, all-industry series are kept) for
        the nation, states and metro areas, May 2025 (the only release in the files): employment, median
        and mean annual wage of ALL occupations (three metrics from the three documented ones). The
        occupation detail (about 800 occupations, 22 major groups) is not built as metrics: one metric
        holds one value, so it would need 22 or more group metrics. Wages show in constant dollars.
        Checked: U.S. employment 155,495,730, median wage $50,980 nominal. Block wages-oews (general).
        No counties or cities. Verified together with item 18 (tests 407, verify ok, round trip 10/10,
        batch 12 ok). REMOVED 2026-09-30 (1.0 checklist D1): provider section, recipes, verify
        check, test and cached files deleted; source and metric rows kept as documentation
18. [x] BLS Current Population Survey (bls_cps_ln), done 2026-09-30: national annual averages (period M13,
        not seasonally adjusted) of the unemployment rate (1947 on), labor force participation rate
        and employment-population ratio (1948 on) from ln.data.1.AllData (390 MB, read in chunks);
        the 2025 average is an 11-month average (footnote 11; October was not collected) and is
        noted. Nation only. Blocks national-unemployment-trend, national-participation-trend,
        national-employment-ratio-trend (general; one metric per block because a block charts its
        first metric only)
D. Open NHGIS additions (docs/nhgis.md)
19. [-] Counts 1990-2020 on constant 2010 boundaries (addition 3): built on 2026-09-30 (one IPUMS
        extract of CL8, CW5, CM1, CP4, CM4, CM7, CM9 and CN1; 15 metrics; three blocks) and REMOVED
        the same day at the user's request: its charts repeated the ACS and census blocks for place
        reports, and the values are estimates (fractional where boundaries changed). Provider,
        metrics, recipes, source row, verify check, test and cache files deleted; docs/nhgis.md
        keeps a note. Lessons kept: the 604 MB block group CSV must be read with readr and
        col_select (read.csv crashed R)
20. [x] Historical boundary files for maps (addition 6), done 2026-09-30 in part: nhgis_boundaries(level, year)
        fetches NHGIS boundary shapefiles (counties 1790-2010, tracts 1910-2000, TIGER/Line 2008
        base) through the extract API into cache/geo/nhgis/ (the 1900 county file: 2,848 features,
        extract 12, about a minute), and a new map block kind, historical_map (option
        boundary_year, default 1900), draws a state's counties of that census with the study area's
        present outline; block historical-counties (general, early childhood, economic
        development; the block's one extract is shared by all reports). Checked: Gary IN sits in
        the 1900 Lake County. Not built: a block that uses the tract boundaries (1910-1980 cover
        only a few cities) or steps through several census years. Tests 419; verify, round trip and
        batch results in FLIGHT_LOG.md

Status of the whole queue, 2026-09-30: items 1-2, 4-10, 12, 14-20 done; item 3 (County Health
Rankings terms) and item 11 (MEDSL guestbook download) skipped for the user; item 13 (HUD PIT/HIC)
blocked by a bot challenge. Nothing is committed.

Review pass (2026-09-30, the user's feedback): blocks removed as redundant or meaningless for a
place report (race from the census, PEP and constant boundaries; population and tenure on
constant boundaries; PEP age table; LAUS participation trend; PEP yearly change; OEWS wages;
permits by size, replaced by one block per structure size); households in the census now indexed
with comparisons; and an engine rule leaves out any block that would show the nation alone. The
metrics stay in the catalog without blocks.

## 1.0 release checklist (agreed with the user 2026-09-30 13:10)

Priorities: lean, efficient in bulk and iteration, human-comprehensible. The features of
docs/REQUIREMENTS.md are done, so 1.0 is consolidation, not new content. Starting point
(2026-09-30): tests 414 pass offline (11 s); `catalog --check` clean (561 metrics, 431
operational, 126 sources); chicago-il, a city never built before, built on the first try with no
warnings (517 s, 494 requests, 320 of them to the FBI). Scope is frozen: nothing under "After
1.0" starts before the tag.

Decisions for the user (answered 2026-09-30 13:12; done 13:50)
- [x] D1. OEWS (bls_oews: 3 metrics, a 330 MB file) and PEP age, sex and race
      (census_pep_county_characteristics: 8 metrics, a 105 MB file) lost their blocks in the
      review. The user: keep their catalog information (source rows, update cadence, metric
      documentation) but delete the files for now. Done: provider sections, 11 recipes, 2 verify
      checks, their tests and 12 cached files (447 MB) deleted; the metrics are documented, not
      operational (catalog: 420 operational, 141 documented)
- [x] D2. Default size of the general profile (chicago-il: 12 sections, 76 figure and table
      chunks, about 12,000 words of report.qmd). The user: a shorter default, plus an option for
      an exhaustive report that uses everything. Done: profiles/general.csv has 43 blocks (was
      82): one block per question, current conditions with history in each subject; blocks that
      show only county or national context for a city are left to the exhaustive profile.
      profiles/exhaustive.csv holds every library block, the childcare_gap module and a metric
      row for each of the 27 operational metrics no block shows, in the general sections plus
      "children"; `catalog --check` (and the tests) fail when a block or metric is missing from
      it. Metric rows of counts are drawn as growth since the first period (index=first), with an
      index axis label. gary-in: 42 blocks, 7,169 words, compose 30 s (was 59 s); an exhaustive
      Gary report: 161 blocks, 22,146 words, compose 86 s warm
- [x] D3. chicago-il (an uncommitted row in config/reports.csv). The user: not a sample report.
      Row removed; reports/chicago-il is still on disk

A. Remove what nothing uses
1. [x] The 43 operational metrics that no profile or manifest reached: D1 removed OEWS and PEP
       characteristics (11); the other 32 are in profiles/exhaustive.csv, in a library block or a
       metric row, and the catalog check keeps it that way
2. [x] The 11 library blocks that only the exhaustive profile uses (pop-history, median-age,
       per-capita-income, snap, rent-trend, vacancy, commute, broadband, household-size,
       disability, income-annual): delete those another block supersedes (for example pop-history
       by pop-long-history, broadband by internet-access); keep the rest. Done 2026-10-01: deleted
       pop-history, median-age, snap, commute and broadband (their metrics stay in
       pop-long-history, key-facts, economic-security, getting-around and internet-access); the
       other 6 stay in the exhaustive profile
3. [x] One helper for the states of a region or division: the same rule
       (`st[[type]] == geoid & st$in_nation == "TRUE"`) is written out in fara, hpsa, nces, fars,
       eavs and bea. Done 2026-10-01: nation_state_table() and member_states(type, geoid) in
       R/geography.R, used by 14 providers; fingerprints identical but for the retrieval date
       line (the edited providers' derived files were rebuilt that day)
4. [x] Readability: compute_block_composition (about 110 lines) split into named steps; the 103
       lines over 100 characters in R/blocks.R wrapped. Proof as before: fingerprint every report
       before and after (tools/fingerprint.R), 0 differences. Done 2026-10-01: composition_results,
       _no_data, _summary and _change; no line over 100; 0 differences in 13 reports

B. Iteration speed
5. [x] Profile one warm compose and name the bottleneck: in-cities-1827000 spent 31 s computing
       with 1,290 cache hits and no misses; a render adds 25-45 s. Done 2026-10-01 (Rprof of
       gary-in, 20.3 s, 1,316 hits, 0 misses): providers' fetch 80%, because the metric cache's key
       includes a digest of the fetched data. acs_table 41% (8.3 s): it decodes whole tables (365
       tables, 5.6 million long rows: every county, every Indiana place) to keep 6 areas; keeping
       the areas before decoding takes 1.6 s instead of 7.5 s. Then cached-file reads 14%, R's
       byte compiler 8%, FBI aggregation 6%
6. [x] Then decide review item 21 (the block-result cache) or the fix the profile points to. Goal:
       a prose or theme edit of one report does not recompute its blocks. Record timings before
       and after. Done 2026-10-01, the user chose the ACS fix first: acs_table() decodes only the
       requested areas, in one pass over all columns (raw tables memoized per session). Warm
       compose, 12 reports: 262 s -> 191 s (gary-in 30.6 -> 15.3 s; austin-core and kc-core still
       40 s, in other providers); 0 fingerprint differences. Also fixed: memoize() now records the
       raw files behind an entry each time it is used, so every report of a batch lists them in
       build.json (kc-core listed 8 ACS files, now 152). The block-result cache stays undecided:
       a prose edit of gary-in is now about 15 s compose + 25-45 s render

C. Bulk runs and the cache
7. [ ] Compose in parallel worker processes, as render_pool renders (the cache already locks
       entries and writes atomically); benchmark a batch larger than the samples (for example
       every county of one state). Now compose runs one report at a time, 30-60 s each
8. [ ] FBI Crime Data Explorer: confirm the key's rate limit (api.data.gov's default is 1,000
       requests an hour) and throttle fbi_cde to it (now the default 2 per second). A batch
       across several states must finish with its crime data, not lose them to HTTP 429.
       Measured 2026-10-01: the key reports x-ratelimit-limit 10 and the count does not fall
       across requests a minute apart, so 10 a second; no 429 in 757 requests (up to 320 an hour,
       95 a minute). The throttle is per process, so set the fbi_cde rate with C7's workers
       (workers x rate under 10 a second)
9. [x] `cache prune`: delete raw files that no report's build.json lists (cache 6.1 GB; the R2
       free tier is 10 GB); README cache paragraph updated. Done 2026-10-01, narrowed with the
       user: build.json lists derived files, not the downloads they come from (4.5 GB, among them
       the FEMA NRI zip that Docker cannot download), so `cache prune [--yes]` deletes only
       derived files a newer version replaced and no build lists (dry run: 827 files, 523 MB)
6b. [ ] Compose key: build.json's compose_key hashes the code when the build ends, but the code
       was loaded when the process started, so an edit during a batch marks a snapshot made with
       the old code as current (seen 2026-10-01: madison-ms reused a compose made before an edit
       to R/blocks.R). Hash the code at load time

D. Documentation (after A-C, so it describes the final state)
10. [ ] README: current counts (431 of 561 metrics operational), Indiana child care capacity (not
        Texas only), Limitations cut to limits that apply across sources (per-source detail stays
        in the catalog and catalog.html), no dated changelog
11. [ ] PLAN.md cut to a status and the "After 1.0" list (its top checklist still says 537 metrics
        and 321 tests, and "Nothing is committed" is out of date); FLIGHT_LOG.md and
        docs/review-2026-09-29-*.md moved to docs/history/; "How to resume" covers the Mac with
        Docker as well as Windows

E. Release check and tag
12. [x] Small: .DS_Store in .gitignore; User-Agent version 1.0 (`geo-report-gen/0.1` in R/fetch.R)
13. [ ] Full check: `gr.R test`, `gr.R catalog --check`, `gr.R verify`, demos/round_trip.R,
        `gr.R batch` (the samples were last batch-built at 09:00, before the 12:00 block
        removals), then a visual review of every sample report
14. [ ] Fresh benchmark with demos/benchmark.R (the README's cold run dates from 2026-09-28, when
        48 metrics were operational), with a cold run on an empty cache copy if time allows;
        README table and docs/benchmark.csv updated
15. [ ] Commit, tag v1.0.0 and push, on the user's go-ahead

After 1.0 (not started before the tag)
- Queue items waiting on the user: County Health Rankings (terms), MIT Election Lab (guestbook
  download), HUD PIT/HIC (bot challenge)
- Not built inside done sources: NCES before 2017, NDCP six-month age bands, OEWS occupation
  detail (if D1 keeps OEWS), LRAM 2010 and 2015 editions, building permits for places before 2007,
  PEP characteristics 2010-2019 (if D1 keeps them), a tract use of the NHGIS historical
  boundaries, LODES origin-destination commuting
- School districts (catalog/geo_support.csv: planned)
