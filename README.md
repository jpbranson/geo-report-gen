# geo-report-gen

Reproducible community reports for U.S. places, counties, states and combinations of them, in
the spirit of datausa.io. It is for analysts, planners and community organizations who need a
sourced profile of an area that they can check, edit and rebuild when new data are released.

A report covers one area, several areas side by side, or a union of areas. For each subject
(demographics, income, housing, work, education, health, child care, public safety and more) it
pairs current conditions with the longest comparable history the sources support, compares the
area with the county, state, region and nation around it, and states margins of error and gaps
plainly. Data come from 34 public sources (the Census Bureau, BLS, BEA, CDC, FBI and others),
downloaded when first needed and cached. Each report is an editable Quarto document
(`reports/<id>/report.qmd`) rendered to HTML, and optionally to PDF.

## Quick start (Docker)

You need git, [Docker Desktop](https://www.docker.com/products/docker-desktop/) and a free
[Census API key](https://api.census.gov/data/key_signup.html).

1. Clone the repository and put your key in `.env` at its root (git-ignored; never commit it):

   ```
   git clone https://github.com/jpbranson/geo-report-gen.git
   cd geo-report-gen
   echo "CENSUS_API_KEY=<your key>" > .env
   ```

2. Build a sample report, then open `reports/madison-ms/report.html` in a browser:

   ```
   docker compose run --rm gr build madison-ms
   ```

   The first run builds the Docker image (a few minutes) and downloads the data the report needs
   into `cache/`: about 10 minutes and 1 GB, mostly national files that later reports reuse.
   The build prints nothing while it downloads; that is expected.

3. Make a report for your own area: look up its ID, add the report, build it (under 3 minutes
   with the cache from step 2).

   ```
   docker compose run --rm gr find "Boulder, Colorado"
   #            key                     name    pop
   #   county:08013 Boulder County, Colorado 328961
   #  place:0807850   Boulder city, Colorado 106433
   docker compose run --rm gr new boulder-co --geo place:0807850
   docker compose run --rm gr build boulder-co
   ```

   `new` takes `--profile` (`general`, `early-childhood`, `economic-development`, `exhaustive`)
   and `--mode` for a list of areas; see [Geography](#geography) and [Commands](#commands).

`docker compose run --rm gr <command>` runs `Rscript gr.R <command>` (see [Commands](#commands))
in an image with R 4.6.1, the packages in `renv.lock` and Quarto 1.9.38. The project folder is
mounted into the container, so `.env`, the configuration, `cache/` and `reports/` stay on your
machine. To preview edits live: `docker compose run --rm --service-ports gr preview <id>`, then
open http://localhost:4848. Differences from running R directly:

- Charts use Noto Sans instead of the default theme's Segoe UI, a Windows font.
- FEMA's server refuses downloads from Linux (HTTP 403), so National Risk Index values are shown
  only if the file is already in `cache/raw/fema_nri/` (from a build outside Docker).
- Dates and times (cache times, "retrieved on") use `TZ`: Central time unless you set `TZ` in the
  shell.
- After `renv.lock` changes, rebuild the image with `docker compose build`.

## Setup without Docker

1. Install R 4.6 and Quarto 1.4 or later. Quarto is found on the PATH, in the usual
   RStudio/Positron install folders, or through `QUARTO_PATH`. On Linux, the spatial packages
   need the system libraries listed in `Dockerfile` (GDAL, GEOS, PROJ, udunits and others).
2. In the project root, install the locked packages: `Rscript -e "renv::restore()"`.
3. Create `.env` as in the quick start, then `Rscript gr.R build madison-ms`. Run every command
   from the project root. On Windows, call R 4.6's `Rscript.exe` explicitly if another R version
   is first on the PATH.

## Keys

`.env` holds your keys. Each is sent only to its own service and never written to logs, the
cache or reports.

| Key | Needed for |
|---|---|
| `CENSUS_API_KEY` | Required: geography lookup and every Census Bureau table. [Free key](https://api.census.gov/data/key_signup.html). |
| `GR_HTTP_CONTACT` | Your email address. BLS (prices, employment, wages) refuses automated downloads without a contact, so it is sent in the User-Agent of BLS requests only. |
| `DATA_GOV_API_KEY` | FBI crime data. [Free key](https://api.data.gov/signup/). |
| `IPUMS_API_KEY` | Census years 1970-2000 (IPUMS NHGIS). [Free key](https://account.ipums.org/api_keys); the account must also be [registered for NHGIS](https://uma.pop.umn.edu/nhgis/registration/new). The first build requests data extracts, which IPUMS takes about 5 minutes each to produce. |

Without an optional key, a report lists the sources that need it under "What is not shown and
why" and shows everything else.

The downloaded data (`cache/`, several GB once many reports are built) and the reports are not in
git. To keep them in step between two machines, see [docs/data-sync.md](docs/data-sync.md).

## Commands

Everything runs through one entry point, `Rscript gr.R <command>`:

| Command | What it does |
|---|---|
| `build <id>...` | fold inline edits back into the content, compute, write `report.qmd`, render if anything changed |
| `batch [id...]` | build many reports: compose, then render, each in up to `--workers` processes (shared cache) |
| `new <id> --geo <spec> [--mode ...] [--profile ...] [--subjects a,b] [--metrics m1,m2] [--label ...]` | add a report, optionally with a manifest built from subjects and metrics |
| `preview <id>` | live preview while editing `reports/<id>/report.qmd` |
| `harvest <id>` | save inline edits without rebuilding |
| `text-export <id> <file.csv>` / `text-import <file.csv>` | bulk text editing in a spreadsheet |
| `find "<name>"` | look up geography IDs by name |
| `catalog [--check] [--html]` | validate the catalog (`--check`: exit 1 on problems); `--html` writes `catalog/catalog.html` |
| `verify` | live checks of every operational source (appends to `catalog/verification_log.csv`) |
| `test` | automated tests (offline, with fixtures) |
| `cache prune [--yes]` | list (with `--yes`, delete) derived files that newer versions replaced |

Options: `--offline` (cache only), `--refresh <source,...>` (re-download the raw files in those
`cache/raw/<source>` folders, e.g. `census_acs5`, `bls`, `bea`), `--force` (recompose and re-render),
`--no-render`, `--workers <n>`, `--formats html,typst`. A build whose inputs, code and raw
files are unchanged since its last compose reuses that compose (build.json says so).

Memory: a compose process can use 3-4 GB while it builds large tables (on a cold cache, or
after a provider's code changes). `batch` runs 4 at once by default (12-16 GB at worst); with
less, such as Docker Desktop's 8 GB (Settings > Resources), use `--workers 2`. A process the
system kills for lack of memory is reported in the batch output, and its reports are marked
failed.

The cache grows unless pruned. An edit to a provider's code gives its derived tables
(`cache/raw/<source>/<name>-<version>.parquet`) a new version, built from the cached downloads, and
leaves the old version behind: `Rscript gr.R cache prune` lists the old versions that no report's
build.json lists, and `cache prune --yes` deletes them (the newest version of each table and every
download stay). Run it when no build is running; data-sync then removes the same files from the
bucket. `cache/metrics/` holds computed results, including ones no longer used after code or data
changes; it can be deleted whenever no build is running, and the next build recomputes what it
needs (about 7 seconds per report). The `.lock` files beside cache entries can be deleted at the
same time. `cache/raw/` holds downloads, some slow to get again (IPUMS extracts need a new request
on your account), so delete from it only with `--refresh` in mind.

PDF: `--formats typst` (or `--formats html,typst`) also writes `reports/<id>/report.pdf` through
Quarto's Typst engine, with the same text, tables, charts and maps, a table of contents and
numbered sections, in the theme's font and paper size. The page layout is basic: a figure or
table that does not fit moves to the next page and can leave white space, and tables use a
smaller font. HTML is the primary format.

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
| `content/history_events.csv` | cited events: dates, `geo_scope`, `subjects`, `subtopics`, `sources` (the data a definitional or boundary break applies to; blank for all), `statement`, `evidence_type`, citation and access date |
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
  constant `dollar_year` dollars with the R-CPI-U-RS from 1978 (earlier years follow the Census
  Bureau's historical income index, joined by ratio at 1978); nominal values are kept. Estimate
  series of different vintages are separate lines, never spliced.

## Editing text

Every visible text (titles, prose, captions, axis labels, legends, notes, source lines, alt text,
category labels, history statements) lives in `content/text.csv`, scoped `default`,
`profile:<id>` or `report:<id>`. For a field, the report scope wins over the profile scope, which
wins over the default; a field falls back to the library block's text and then to the template
for its kind (e.g. `@metric.caption`). Long prose can live in `content/prose/*.md`, referenced as
`@prose/<file>.md`. Templates use `{placeholders}` filled from computed values; they are never
evaluated. A number typed into text that matches a computed value is remembered, and later builds
warn when the data no longer match. Under a figure, the `legend` field says what its marks show
and what limits comparisons (always shown); the `note` field holds definitions and methods (left
out when the `detail` setting is `brief`). A block without data shows its `no_data` text instead
of its prose.

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
  or directly as a manifest row of type `metric`. The row's `history_start` is the first
  comparable period (e.g. `2008-2012`); earlier periods are never computed, so check the ACS
  table's line labels in older releases before moving it back. `breaks` is shown to readers.
  Every new block, and every metric that no block shows, also gets a row in
  `profiles/exhaustive.csv`; `gr.R catalog --check` (and the tests) report any that are missing.
  A block that shows a count over time against benchmarks needs `index=first` in its options
  (levels would put the area beside a state or the nation many times its size); the check
  reports any that lack it, and manifest metric rows get it automatically.
- **Change text:** edit the report inline or `content/text.csv` (see above).
- **Change the look:** edit `config/themes.csv` (fonts, colors, sizes, number formats, print), or
  add a theme and select it with the `theme` setting. Themes never change a statistic.
- **Change the historical window:** `history_start` (the first year shown). Later layers win:
  `config/settings.csv` for everyone, then a profile; then a library block's own window in
  `catalog/blocks.csv` (e.g. 1790 for the long population chart); then one report
  (`report:<id>`); then one block (`history_start=2000` in the manifest row's options).
  `build.json` lists each block's window and the layer it came from. A metric's catalog
  `history_start` is a floor that no setting crosses.
- **Add a data source:** write `R/providers/<name>.R` returning the long-data contract documented
  in `R/core.R` and call `register_provider()`. Add a block kind with `compute_block_<kind>()`
  and `render_block_<kind>()`. Neither needs changes elsewhere.
- **Custom analysis:** a trusted R file in `modules/` defines `title`, `compute(ctx, options)` and
  `render(output, text, theme)`; insert it with a manifest row of type `custom`. See
  `modules/childcare_gap.R`.
- **Audience profiles:** copy a file in `profiles/`; profile-scoped text records and settings
  change wording and depth without touching the analysis. `general` is a short community
  overview: one block per question, with current conditions and history in each subject.
  `early-childhood` and `economic-development` go deeper on their topics. `exhaustive` shows
  everything: every library block, the custom child care module and every operational metric
  that no block shows, in the general sections plus one for children and child care. Use it to
  see all that exists for an area, or as a starting point to edit down in a report's own
  manifest (`config/manifests/<id>.csv`).

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
| `ct-capitol` | a Connecticut planning region: the 2022 boundary change breaks the county history (census counts are summed from its towns); civic theme |
| `lake-in` | tract maps within a county, income and rent distributions, and time-only blocks without parent charts |
| `tx-cities` | four cities compared side by side against their shared benchmarks |
| `in-cities` | one list split into one report per city |
| `madison-ms` | a smaller city (Madison, Mississippi) with the general profile |

The catalog of subjects, sources and metrics, with verification status and known gaps, is
`catalog/catalog.html` (`gr.R catalog --html`).

## Verification

- `Rscript gr.R test`: automated tests of the statistics, aggregation rules, geography
  (unions, overlaps, benchmarks), settings and text precedence, CSV round trips, caching, and the
  inline/bulk editing round trip with conflict detection. They run offline on trimmed real
  responses in `tests/fixtures/` (made-up values for IPUMS NHGIS, whose data may not be shared).
- `Rscript gr.R verify`: live checks of every operational source; results with dates and
  evidence go to `catalog/verification_log.csv`.
- `Rscript demos/round_trip.R`: the editing round trip on a real report through a data refresh.
- `Rscript demos/benchmark.R [--warm]`: cold (or, with `--warm`, the project's cache), warm
  and resumed batches and what each kind of edit invalidates (results in `docs/benchmark.csv`).

Results on 2026-10-01 (Mac with Apple Silicon, in Docker; the 12 sample builds and the intended
rejection; 4 compose and 4 render processes; `--warm`, so no cold run and no data refresh):

| Step | Seconds | Compose / render | Rendered |
|---|---:|---:|---|
| First build of a fresh copy (warm cache) | 164 | 104 / 60 | 12 |
| Nothing changed | 2 | 2 / 0 | 0; every compose reused |
| Forced re-render | 169 | 106 / 63 | 12 |
| Resumed after an interruption (default intro edited) | 132 | 87 / 45 | 9; 3 up to date |
| Theme edit (default accent color) | 164 | 102 / 62 | 11; the civic-themed report reused |
| Geography edit (one report becomes a union) | 14 | 7 / 7 | 1; the other reports reused |

A build reuses its last compose when its code, catalog, content, own configuration, raw files
and report.qmd are unchanged; a text or theme edit therefore recomposes every report it may
touch (10-40 s each), and rendering takes 15-30 s per report. For one report (gary-in), a prose
edit takes about 36 s (compose 20 s, render 15 s). Several compose processes help most when a
batch waits on downloads (24 new Maryland counties: 123 s for half of them with 4 processes,
233 s for the other half with one). Building every sample from an empty cache takes about 2,500
requests and 1 GB of downloads, plus about 5 minutes per IPUMS extract.

## Limitations

These apply across sources. How each source is used, and its own limits, is in
`docs/sources.md`; each source's documentation and checks are in the catalog
(`catalog/catalog.html`).

- 420 of the 561 cataloged metrics are operational, from 34 of its 126 sources; the rest are
  documented only. Not built: County Health Rankings (pending a review of its terms of use), MIT
  Election Lab returns and HUD homelessness counts (their downloads block scripts).
- Many sources publish counties, not cities (SAIPE, SAHIE, BEA, QCEW, County Business Patterns,
  FEMA, the Food Environment Atlas): a city report then shows its county as context, labeled as
  such. Cities, tracts and combined areas get exact values only where a source publishes them or
  its records can be placed (LODES blocks, crash coordinates, school addresses).
- City histories from the Census API start in 2000; census years 1970-2000 come from IPUMS
  NHGIS, linked across censuses by name and code on each census's boundaries.
- Census years before the ACS have no margins of error, so they are drawn as dots and never
  tested; a chart that joins them to ACS periods states the long-run change as approximate.
- Combined areas have no margin of error for medians (the Census Bureau publishes no method) or
  for model-based estimates (the model errors of SAIPE and SAHIE areas cannot be combined).
- Connecticut's planning regions (counties since 2022) are missing from sources that still use
  the former counties (FARS, NOAA zones, the Food Environment Atlas, the Food Access Research
  Atlas, county-level GDP before 2024).
- Some sources are current snapshots only (child care licensing in Texas and Indiana, HRSA
  shortage areas, the latest CDC PLACES release), so they have no history.
- Custom polygons and area-weighted allocation are not supported.

## License

The code is licensed under the GNU General Public License v3.0 ([LICENSE](LICENSE)). Data you
download keep their sources' terms: IPUMS NHGIS forbids redistributing its data (extracts stay in
your `cache/`), and FEMA requires the statement printed under its tables and charts. Check a
source's terms before publishing reports built from it: the `license` column of
`catalog/sources.csv` records them, with links to each source's documentation.
