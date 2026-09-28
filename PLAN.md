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

Status as of 2026-09-28 17:15 (session 3; details in FLIGHT_LOG.md). `[x]` done and exercised by the
sample reports and tests, `[~]` implemented but unfinished, `[ ]` not started.

- [x] Environment: renv library + `renv.lock`, Quarto discovery, `.env` for key/contact (never logged)
- [x] Fetch/cache layer: keys, atomic writes, locks, retries, throttling, offline/refresh, request log
- [x] Geography: spec parsing (type:GEOID@vintage), name lookup w/ ambiguity, relationship graph
      (contains/intersects/coterminous), unions, overlap/parent-child detection, decomposition into
      published pieces, benchmark policy, national scope, support matrix (catalog/geo_support.csv)
- [x] Statistics: counts, shares, ratios, medians from distributions, MOE propagation, significance tests
      incl. overlap + part-whole dependence, status codes, constant dollars (R-CPI-U-RS)
- [x] Providers: ACS 5-yr (2009-2024), decennial 2000/2010/2020 (1990 is not in the API), PEP, 1900-1990
      county counts, LAUS, BEA CAINC1, CPI, building permits, FHFA HPI, NDCP, CBP 624410, Texas HHSC
- [x] Catalog: tables (17 subjects / 82 subtopics, 120 sources, 398 metrics, 48 operational), the
      browsable page (`gr.R catalog --html`) with scope and gaps, live `gr.R verify` (13 of 13 ok)
- [x] Content: manifests, block library, 3 profiles, scoped text, templates, cited history events,
      stale-fact warnings, `gr.R new` (subject/metric selection)
- [~] Authoring: inline harvest, bulk CSV export/import and conflict detection, covered by tests; to do:
      demonstrate on a real report through regeneration
- [x] Rendering: theme, charts, maps, tables; reviewed and fixed (see FLIGHT_LOG.md)
- [x] Custom module example (modules/childcare_gap.R, inserted via profiles/early-childhood.csv)
- [x] Batch: two phases (compose, parallel render), isolated failures, per-report progress (resumable),
      logs, build manifests; cold/warm/resumed benchmark and invalidation checks (README, docs/)
- [~] Demos: 1-5 and 7-11 shown by the sample reports, benchmark and README; 6 is covered by tests,
      and demos/round_trip.R (on a real report) is written but not yet run; PDF (Typst) unchecked
- [x] Tests: 115 expectations pass offline with fixtures (`gr.R test`)
- [~] Docs: README (setup, commands, configuration, authoring, maintainer walkthrough, results,
      limitations) done. Lean review: dead code removed; R/blocks.R restructure still to do
