# geo-report-gen

Reproducible community reports for U.S. geographies, in the spirit of datausa.io. A report
covers one area, a list of areas side by side, or a union of areas. For each subject it pairs
current conditions with the longest comparable history the sources support, compares the area
with its parent geographies where that is meaningful, and states uncertainty and gaps plainly.
The output of every report is an editable Quarto document (`report.qmd`) and its HTML rendering.

## Setup

1. R 4.6 and Quarto 1.4 or later. Quarto is found on the PATH, in the usual RStudio/Positron
   install folders, or through `QUARTO_PATH`.
2. Restore the package library: `Rscript -e "renv::restore()"`.
3. Create `.env` in the project root (it is git-ignored; never commit it):

   ```
   CENSUS_API_KEY=<free key from https://api.census.gov/data/key_signup.html>
   GR_HTTP_CONTACT=<your email address>
   ```

   The Census Data API needs the key for every request. BLS rejects automated downloads that
   carry no contact, so the email is sent in the User-Agent of BLS requests, and only those.
4. Run commands from the project root. On Windows, call the R 4.6 `Rscript.exe` explicitly if
   another R version is first on the PATH.

## Commands

Everything runs through one entry point, `Rscript gr.R <command>`:

| Command | What it does |
|---|---|
| `build <id>...` | fold inline edits back into the content, compute, write `report.qmd`, render if anything changed |
| `batch [id...]` | build many reports: compose one by one (shared cache), then render in parallel |
| `new <id> --geo <spec> [--mode ...] [--profile ...] [--subjects a,b] [--metrics m1,m2]` | add a report, optionally with a manifest built from subjects and metrics |
| `preview <id>` | live preview while editing `reports/<id>/report.qmd` |
| `harvest <id>` | save inline edits without rebuilding |
| `text-export <id> <file.csv>` / `text-import <file.csv>` | bulk text editing in a spreadsheet |
| `find "<name>"` | look up geography IDs by name |
| `catalog [--check] [--html]` | validate the catalog, write `catalog/catalog.html` |
| `verify` | live checks of every operational source (appends to `catalog/verification_log.csv`) |
| `test` | automated tests (offline, with fixtures) |

Options: `--offline` (cache only), `--refresh <source,...>` (re-download), `--force` (re-render),
`--no-render`, `--workers <n>`, `--formats html,typst`.

## From configuration to report

```
config/reports.csv           which reports: geography, mode, profile, optional manifest
profiles/<profile>.csv       which blocks, in which order (or config/manifests/<id>.csv for one report)
catalog/blocks.csv           what each library block shows (metrics, comparison, chart)
catalog/recipes.csv          how each operational metric is computed from source variables
        |
R/geography.R    resolve the areas, their non-overlapping published pieces and the benchmarks
R/providers/*.R  fetch source data (Census API, BLS, BEA, FHFA, ...) into the shared cache/
R/metrics.R      aggregate pieces into values with MOEs and statuses (R/stats.R has the formulas)
R/blocks.R       per block: data for the chart plus values for the text ({placeholders})
R/compose.R      resolve text (content/text.csv), write reports/<id>/report.qmd + _snapshot/
        |
Quarto           R/runtime.R draws charts and maps (R/charts.R, R/maps.R) from the snapshot;
                 quarto/gr-placeholders.lua fills {placeholders} in the text
        |
reports/<id>/report.html, build.json (sources, versions, settings, warnings, timings)
```

Rendering reads only the snapshot, so text or theme edits never refetch data. Every cache entry
is keyed by what it depends on (release, table, geography scope, code version), so changed code
recomputes only what it affects. Quarto's freeze and knitr caching are not used: a report is
re-rendered when the hash of its `.qmd`, snapshot and drawing code changes. `build.json` records
the inputs' hashes and every raw file used.

### Configuration files

| File | Columns |
|---|---|
| `config/reports.csv` | `report_id`, `geography` (specs joined by `+`), `mode` (single, union, compare, separate), `label`, `profile`, `manifest`, `vintage`, `enabled`, `note` |
| `config/settings.csv` | `scope` (`default`, `profile:<id>`, `report:<id>`), `key`, `value`, `note`; every key is declared in the default scope |
| `config/themes.csv` | `theme`, `key`, `value`, `note`; a theme overrides the `default` rows it names |
| `profiles/*.csv`, `config/manifests/*.csv` | `id`, `type` (section, subsection, block, metric, text, custom), `ref`, `enabled`, `compare`, `viz`, `options` (`key=value; ...`) |
| `content/text.csv` | `field_id`, `scope`, `text` (or `@prose/<file>.md`), `updated`, `fixed_facts`, `note` |
| `content/history_events.csv` | cited events: dates, `geo_scope`, `subjects`, `subtopics`, `statement`, `evidence_type`, source and access date |
| `catalog/*.csv` | subjects, sources, metrics (documentation), recipes (computation), blocks, geography support |

## Geography

A geography is `type:GEOID`, optionally `@vintage` (`place:1827000`, `county:48453@2024`, `us`) or
`name:Gary, Indiana` (ambiguous names are an error listing the candidates). ZIP codes are refused
with a pointer to ZCTAs. Types and what each can do: `catalog/geo_support.csv`.

A list of areas needs an explicit mode: `union` (one combined area), `compare` (side by side),
or `separate` (one report each). Unions are built from non-overlapping published pieces: members
inside another member are dropped, and a city overlapping a county contributes only its published
parts outside that county. Overlaps without published parts (a ZCTA and a city) are rejected with
an explanation; no area-based allocation is applied.

Benchmarks: every level in `benchmark_levels` (county, state, region, nation) that contains the
area is offered. If no county contains it, each intersecting county holding at least
`benchmark_min_share` of the residents is offered and labeled with that share; the others are
listed in the report's notes. Coterminous and duplicate benchmarks are dropped. Compare mode uses
only benchmarks shared by all areas. `benchmarks` in the settings overrides the policy. National
totals cover the 50 states and DC; Puerto Rico and the Island Areas have no Census region.

## Statistics

- Counts are summed over non-overlapping pieces; shares, rates and means are recomputed from
  summed numerators and denominators, never averaged. Medians of combined areas are interpolated
  from the summed published distribution and carry no MOE; indexes and prices are not combined.
- MOEs follow the ACS handbook (chapter 8). Differences are tested at 90%, with the
  overlapping-period adjustment for ACS trends and a part-whole adjustment when the area is part
  of its benchmark. Survey values are called higher or lower only when the test supports it; a
  survey value without an MOE is described as untested.
- Status codes distinguish ok, controlled, open-ended, suppressed, insufficient sample, not
  applicable, unavailable, not aggregable and invalid denominator. Each report lists what it
  could not show, and why.
- One ACS release for every area; trends use non-overlapping 5-year periods. Dollars are shown in
  constant `dollar_year` dollars with the R-CPI-U-RS; nominal values are kept. Estimate series
  of different vintages are separate lines, never spliced.

## Editing text

Every visible text (titles, prose, captions, axis labels, legends, notes, source lines, alt text,
category labels, history statements) lives in `content/text.csv`, scoped `default`,
`profile:<id>` or `report:<id>`. For a field, the report scope wins over the profile scope, which
wins over the default; a field falls back to the library block's text and then to the template
for its kind (e.g. `@metric.caption`). Long prose can live in `content/prose/*.md`, referenced as
`@prose/<file>.md`. Templates use `{placeholders}` filled from computed values; they are never
evaluated. A number typed into text that matches a computed value is remembered, and later builds
warn when the data no longer match.

- **Inline:** edit `reports/<id>/report.qmd` itself: headings, the text between `:::` fences,
  and the `fig-cap`, `fig-alt`, `tbl-cap` and `gr-*` chunk options (axis labels, legend title,
  category labels). `gr.R preview <id>` shows edits live. The next build saves each changed field
  as a `report:<id>` record.
- **Bulk:** `gr.R text-export <id> file.csv`, edit in a spreadsheet (`edit_scope` can be changed
  to `profile:<id>` or `default`), then `gr.R text-import file.csv`.

Both write the same records. An edit is applied only if the record is still what the editor saw;
otherwise nothing is saved and both versions are written to a conflicts CSV (next to the report
for inline edits, next to the imported file for bulk edits).

Structure lives in the manifest: row order is document order, and a block belongs to the section
above it. Moving a row moves the block; numbering and the table of contents follow.

## Maintaining the project

- **Change or add a metric:** add its documentation row to `catalog/metrics.csv` and its recipe
  to `catalog/recipes.csv` (source, statistic type, numerator/denominator variables or a
  published variable, distribution table for medians). Use it in a block (`catalog/blocks.csv`)
  or directly as a manifest row of type `metric`.
- **Change text:** edit the report inline or `content/text.csv` (see above).
- **Change the look:** edit `config/themes.csv` (fonts, colors, sizes, number formats, print), or
  add a theme and select it with the `theme` setting. Themes never change a statistic.
- **Change the historical window:** `history_start` in `config/settings.csv`, for everyone, a
  profile, one report (`report:<id>`), or one block (`history_start=2000` in the manifest options).
- **Add a data source:** write `R/providers/<name>.R` returning the long-data contract documented
  in `R/core.R` and call `register_provider()`. Add a block kind with `compute_block_<kind>()`
  and `render_block_<kind>()`. Neither needs changes elsewhere.
- **Custom analysis:** a trusted R file in `modules/` defines `title`, `compute(ctx, options)` and
  `render(output, text, theme)`; insert it with a manifest row of type `custom`. See
  `modules/childcare_gap.R`.
- **Audience profiles:** copy a file in `profiles/`; profile-scoped text records and settings
  change wording and depth without touching the analysis.

## Sample reports

`config/reports.csv` defines the examples; `Rscript gr.R batch` builds them into `reports/<id>/`.

| Report | Shows |
|---|---|
| `gary-in` | a city with every parent benchmark; decline since 2000 with cited history back to its founding in 1906 |
| `austin-tx` | a city in four counties (Travis and Williamson offered, Hays and Bastrop noted); early-childhood profile with the custom child care module |
| `austin-core` | same-state union of three counties (economic-development profile) |
| `kc-core` | two-state union; state benchmarks labeled with their share of residents; untested union medians |
| `travis-austin` | a county plus the overlapping city, resolved with published place-by-county parts |
| `austin-78704` | a ZCTA plus an overlapping city: rejected with an explanation (the batch continues) |
| `ct-capitol` | a Connecticut planning region: the 2022 boundary change breaks the county history; civic theme |
| `lake-in` | tract maps within a county and time-only blocks without parent charts |
| `tx-cities` | four cities compared side by side against their shared benchmarks |
| `in-cities` | one list split into one report per city |

The catalog of subjects, sources and metrics, with verification status and known gaps, is
`catalog/catalog.html` (`gr.R catalog --html`).

## Verification

- `Rscript gr.R test`: automated tests of the statistics, aggregation rules, geography
  (unions, overlaps, benchmarks), settings and text precedence, CSV round trips, caching, and the
  inline/bulk editing round trip with conflict detection. They run offline on real API responses
  in `tests/fixtures/`.
- `Rscript gr.R verify`: live checks of every operational source; results with dates and
  evidence go to `catalog/verification_log.csv`.
- `Rscript demos/round_trip.R`: the editing round trip on a real report through a data refresh.
- `Rscript demos/benchmark.R`: cold, warm and resumed batches and what each kind of edit
  invalidates (results in `docs/benchmark.csv`).

Results on 2026-09-28 (Windows laptop; the 12 sample builds; 4 parallel renders):

| Step | Seconds | Requests | Cache hits / misses | Rendered |
|---|---:|---:|---:|---|
| Cold: empty cache | 690 | 536 | 879 / 1,117 | 11 |
| Warm: nothing changed | 86 | 0 | 1,528 / 23 | 11 (see note) |
| Warm: forced re-render | 84 | 0 | 1,551 / 0 | 11 |
| Resumed after an interruption (default intro edited) | 53 | 0 | 1,551 / 0 | 3; 8 up to date |
| Theme edit (default accent color) | 84 | 0 | 1,551 / 0 | 10; the civic-themed report untouched |
| Geography edit (one report becomes a union) | 55 | 2 | 1,536 / 21 | 1 |
| Data refresh (building permits; data unchanged) | 89 | 102 | 1,555 / 103 | 0 |

Note: in this run, values computed right after a download differed in row names from their
cached copies, so the first warm run re-rendered every report. Fixed afterwards (`cached()`
returns the stored copy); a rebuild after a fresh computation is now reported as up to date.

The cold run is dominated by downloads (compose 639 s, of which the first report took 435 s
while fetching the shared national tables; BLS asks for one request per second). A warm run
spends about 37 s composing twelve reports (reading cached tables and boundaries) and 13-19 s
per Quarto render, so rendering is the main cost whenever many reports change.

## Limitations

- Operational adapters cover 48 of the 398 cataloged metrics; the rest are documented only.
- City histories start in 2000: the Census API has no earlier census tables for places.
- Medians of combined areas have no margin of error (the Census Bureau publishes no method).
- Licensed child care capacity is implemented for Texas only; it is a current snapshot.
- Custom polygons and area-weighted allocation are not supported.
