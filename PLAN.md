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

Status as of 2026-09-29 00:15 (session 3; details in FLIGHT_LOG.md). `[x]` done and exercised by the
sample reports and tests, `[~]` implemented but unfinished, `[ ]` not started.

- [x] Environment: renv library + `renv.lock`, Quarto discovery, `.env` for key/contact (never logged)
- [x] Fetch/cache layer: keys, atomic writes, locks, retries, throttling, offline/refresh, request log
- [x] Geography: spec parsing (type:GEOID@vintage), name lookup w/ ambiguity, relationship graph
      (contains/intersects/coterminous), unions, overlap/parent-child detection, decomposition into
      published pieces, benchmark policy, national scope, support matrix (catalog/geo_support.csv)
- [x] Statistics: counts, shares, ratios, medians from distributions, MOE propagation, significance tests
      incl. overlap + part-whole dependence, status codes, constant dollars (R-CPI-U-RS)
- [x] Providers: ACS 5-yr (2009-2024), decennial 2000/2010/2020 (1990 is not in the API), PEP, 1900-1990
      county counts, LAUS, BEA CAINC1, CPI, building permits, FHFA HPI, NDCP, CBP (all industries), Texas HHSC,
      SAIPE, SAHIE, CDC PLACES, FEMA National Risk Index, USDA Food Environment Atlas, EAC EAVS,
      Census of Governments finance, FBI Crime Data Explorer, IPUMS NHGIS (census years 1970-2000)
- [x] Catalog: tables (17 subjects / 82 subtopics, 121 sources, 458 metrics, 232 operational), the
      browsable page (`gr.R catalog --html`) with scope and gaps, live `gr.R verify` (22
      sources: 21 ok, the FBI API briefly down and ok on retry; 424 ACS recipe x release
      checks, no gaps)
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
- [x] Tests: 213 expectations pass offline with fixtures (`gr.R test`)
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
3. [ ] Check back with the user
