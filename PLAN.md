# Implementation plan and completion checklist

Environment found: empty directory; R 4.6.1 (project library via renv), Quarto 1.9.38 (bundled with
RStudio), no git history. The Census Data API now **requires a key** for every request (verified
2026-09-28: keyless calls redirect to `missing_key.html`). Machine-specific settings live in the
git-ignored `.env` (read at startup by R/load.R): `CENSUS_API_KEY`, and `GR_HTTP_CONTACT` (the
user's email, sent only to BLS, which rejects automated requests without a contact).

## Architecture (one path: config -> data -> analysis -> report)

```
gr.R                    single CLI entry point (new, build, batch, text-export/import, catalog, verify)
config/                 settings.csv (scoped settings), reports.csv (report instances), themes.csv
catalog/                subjects.csv, sources.csv, metrics.csv, coverage.csv (machine-readable, browsable)
content/                text.csv (scoped canonical text), prose/*.md, history_events.csv (cited context)
profiles/               audience manifests (general, early-childhood, economic-development)
R/                      engine: fetch+cache, providers, geography graph, statistics, content, charts, build
modules/                trusted custom analyses (explicit R modules)
quarto/                 report template assets (Lua placeholder filter, SCSS generated from theme)
reports/<id>/           generated editable report.qmd + snapshot + rendered HTML + build.json
cache/                  shared persistent cache: raw downloads, normalized tables, computed metrics
tests/                  testthat: statistics, geography, content round trips, cache keys, fixtures
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

Status as of 2026-09-29 17:30 (session 5; details in FLIGHT_LOG.md). `[x]` done and exercised by the
sample reports and tests, `[~]` implemented but unfinished, `[ ]` not started.

- [x] Environment: renv library + `renv.lock`, Quarto discovery, `.env` for key/contact (never logged)
- [x] Fetch/cache layer: keys, atomic writes, locks, retries, throttling, offline/refresh, request log
- [x] Geography: spec parsing (type:GEOID@vintage), name lookup w/ ambiguity, relationship graph
      (contains/intersects/coterminous), unions, overlap/parent-child detection, decomposition into
      published pieces, benchmark policy, national scope, support matrix (catalog/geo_support.csv)
- [x] Statistics: counts, shares, ratios, medians from distributions, MOE propagation, significance tests
      incl. overlap + part-whole dependence, status codes, constant dollars (R-CPI-U-RS)
- [x] Providers: ACS 5-yr (2009-2024), decennial 2000/2010/2020 (1990 is not in the API), PEP, 1900-1990
      county counts, LAUS, BEA CAINC1 and county GDP, CPI, building permits, FHFA HPI, NDCP, CBP (all industries), Texas HHSC,
      SAIPE, SAHIE, CDC PLACES, Nonemployer Statistics, LEHD LODES, BLS QCEW, NHTSA FARS, FEMA National Risk Index, USDA Food Environment Atlas, EAC EAVS,
      Census of Governments finance, FBI Crime Data Explorer, IPUMS NHGIS (census years
      1790-2000, County Business Patterns 1970-1997)
- [x] Catalog: tables (17 subjects / 83 subtopics, 123 sources, 537 metrics, 335 operational), the
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
- [x] Tests: 288 expectations pass offline with fixtures (`gr.R test`)
- [x] Docs and lean review: README complete; dead code removed; R/blocks.R, R/geography.R and
      R/compose.R restructured, each with every report's output proven identical

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

## Proposed next steps (saved 2026-09-29, not started)

1. [ ] Constant dollars before 1978: extend the price index back with the regular CPI-U (BLS
       suggests CPI-U for years before the R-CPI-U-RS begins in 1978), scaled to meet the
       R-CPI-U-RS in 1978. Adds payroll per employee for 1974-1977 (payroll-trend could then
       start in 1974) and allows constant dollars before 1978 anywhere.
2. [ ] Connecticut planning regions: sum town (county subdivision) census values from NHGIS into
       the 2022 planning regions, mapping towns by code as the EAVS provider does
       (ct_town_regions()). Works for counts and shares (poverty, education, work, commuting,
       population); not for medians such as household income.
3. [ ] Long-run sentences in chart text: add a sentence on the change since the earliest census
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

## Step agreed with the user 2026-09-29 16:24: five more sources, in order

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
