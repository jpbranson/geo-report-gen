# Implementation plan and completion checklist

Environment found: empty directory; R 4.6.1 (project library via renv), Quarto 1.9.38 (bundled with
RStudio), no git history. The Census Data API now **requires a key** for every request (verified
2026-09-28: keyless calls redirect to `missing_key.html`); the key is read from `census_key.txt`
(git-ignored) or `CENSUS_API_KEY`.

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

- [ ] Environment: renv library, Quarto discovery, key handling (never logged)
- [ ] Fetch/cache layer: keys, atomic writes, locks, retries, throttling, offline/refresh, request log
- [ ] Geography: spec parsing (type:GEOID@vintage), name lookup w/ ambiguity, gazetteer index,
      relationship graph (contains/intersects/coterminous), unions, overlap/parent-child detection,
      decomposition into non-overlapping published pieces, benchmark policy, national scope, support matrix
- [ ] Statistics: counts, shares, ratios, medians from distributions, weighted means, MOE propagation,
      significance tests incl. overlap + part-whole dependence, status codes, CPI adjustment
- [ ] Providers: ACS 5-yr (2009-2024), decennial 2000/2010/2020, PEP, LAUS, BEA CAINC1, CPI,
      building permits, FHFA HPI, NDCP childcare prices, CBP child care establishments, state licensing
- [ ] Catalog: subjects, sources, metrics, coverage; verification status/evidence; browsable HTML page
- [ ] Content: manifest (row order = document order), block library, profiles, scoped text precedence,
      templates, Markdown prose, cited history events, stale-fact warnings
- [ ] Authoring: inline (.qmd) harvest, bulk CSV export/import, conflict detection, round-trip demo
- [ ] Rendering: theme (fonts/colors/spacing/formats/figure sizes/print), charts, maps, tables, labels
- [ ] Custom module example inserted via manifest without engine changes
- [ ] Batch: planning, prefetch dedup, parallel workers, isolated failures, resume, build manifest, timings
- [ ] Demos (acceptance 1-11) rendered and inspected; PDF (Typst) status checked
- [ ] Tests (deterministic fixtures) + live verification command; benchmarks cold/warm/resume
- [ ] Docs: README (setup, commands, authoring guide, maintainer walkthrough), limitations; lean review
