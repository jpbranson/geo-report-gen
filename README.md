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
   DATA_GOV_API_KEY=<free key from https://api.data.gov/signup/>
   IPUMS_API_KEY=<free key from https://account.ipums.org/api_keys>
   ```

   The Census Data API needs the key for every request. BLS rejects automated downloads that
   carry no contact, so the email is sent in the User-Agent of BLS requests, and only those. The
   FBI Crime Data Explorer needs the api.data.gov key, sent only as a request header (never in
   URLs or logs). Census years 1970-2000 come from IPUMS NHGIS, which needs the IPUMS key (sent
   only as a request header) and an IPUMS account registered for NHGIS
   (https://uma.pop.umn.edu/nhgis/registration/new). The first build requests the extracts, which
   IPUMS takes about 5 minutes each to produce; adding an NHGIS table to the catalog requests a
   new extract. Without a key, the sources that need it are listed in each report's "What is not
   shown" appendix with the reason, and every other value is still shown.
4. Run commands from the project root. On Windows, call the R 4.6 `Rscript.exe` explicitly if
   another R version is first on the PATH.

### Docker (instead of steps 1, 2 and 4)

With Docker Desktop, the only other setup is `.env` (step 3). From the project root:

```
docker compose run --rm gr build gary-in
docker compose run --rm --service-ports gr preview gary-in    # then open http://localhost:4848
```

`compose.yaml` runs `Rscript gr.R <command>` in the image built from `Dockerfile` (R 4.6.1,
the packages in `renv.lock`, Quarto 1.9.38 and the system libraries), which the first run builds
in a few minutes on Intel/AMD machines or Apple Silicon. The checkout is mounted at `/app`, so
`.env`, the configuration, `cache/` and `reports/` are the host's own files; a cache made on
Windows works unchanged. Values and `report.qmd` are identical to a Windows build. Differences:

- Charts use Noto Sans, since the default theme's Segoe UI is a Windows font.
- FEMA's server refuses downloads from Linux clients (HTTP 403), so the National Risk Index
  file must already be in `cache/raw/fema_nri/` (copy it from a Windows build).
- Times and dates (cache times, "retrieved on") use `TZ` from `compose.yaml`: Central time
  unless `TZ` is set in the shell.
- After `renv.lock` changes, rebuild the image with `docker compose build`.

### Moving the data to another machine

The downloaded data (`cache/`, several GB) and rendered reports (`reports/`) are not in git. Keep
them in step through a Cloudflare R2 bucket with `data-sync`, or carry them in a tar file.

#### Sync through Cloudflare R2

Run this on a machine when you start working there and again when you stop, while no build is
running:

```
sh tools/data-sync.sh                      # Mac or Linux
.\tools\data-sync.cmd                      # Windows (Command Prompt or PowerShell)
```

It syncs `cache/raw/`, `cache/geo/` and `reports/` both ways with rclone's `bisync`: new, changed
and deleted files on either machine reach the other. `cache/metrics/` stays local (builds
recompute it), as do lock files and partial downloads; `tools/data-sync-filters.txt` holds the
rules. Safeguards:

- Files the sync deletes or overwrites in the bucket are moved to `trash/<date-time>/` in the
  bucket, kept 30 days by the lifecycle rule below. To restore, copy them back into the project
  folder and sync again: `rclone copy gr-r2:geo-report-data/trash/<date-time> .`
- A file changed on both machines keeps the newer copy; the other becomes `<name>.conflict1`.
- A run that would delete more than half the files stops; add `--force` if that is intended.
- The first run on a machine merges both sides without deleting anything.

Other `rclone bisync` options can be added, e.g. `--dry-run` to see what would change. If rclone
stops and asks for a resync (after `data-sync-filters.txt` changes, or a damaged state), run it
again with `--resync-mode newer`, which merges both sides like a first run. The sync state is
kept in `.data-sync/` (git-ignored). `GR_SYNC_REMOTE` selects another bucket or rclone remote
(default `gr-r2:geo-report-data`).

One-time setup:

1. In the Cloudflare dashboard, turn on R2 (the free tier covers 10 GB with no download fees, but
   Cloudflare asks for a payment card) and create a bucket named `geo-report-data`. In the
   bucket's settings, add an object lifecycle rule: prefix `trash/`, delete objects 30 days
   after upload. With Cloudflare's `wrangler` CLI, the same is
   `npx wrangler r2 bucket create geo-report-data` and
   `npx wrangler r2 bucket lifecycle add geo-report-data trash-30-days trash/ --expire-days 30`.
2. R2 > Manage API tokens > Create API token: "Object Read & Write", applied to the
   `geo-report-data` bucket only. Note the access key ID, the secret access key and the S3
   endpoint (`https://<account id>.r2.cloudflarestorage.com`). One token per machine lets you
   revoke one without touching the other.
3. On each machine, install rclone 1.66 or later (`brew install rclone` on a Mac;
   `winget install Rclone.Rclone` on Windows, then open a new terminal) and add the remote:

   ```
   rclone config create gr-r2 s3 provider=Cloudflare region=auto no_check_bucket=true endpoint=https://<account id>.r2.cloudflarestorage.com access_key_id=<key id> secret_access_key=<secret>
   ```

   The keys are saved in rclone's own configuration in your user profile, never in the project.
   (`rclone config` asks for the same settings one by one and keeps the keys out of your shell
   history.)
4. Run `data-sync` first on the machine with the most data: it uploads everything (about 6 GB).

#### Tar bundle

To carry the data on a drive instead, bundle it into one tar file in your Downloads folder, then
extract it in the other machine's project folder after `git pull`:

```
sh tools/bundle-data.sh                    # Mac or Linux
.\tools\bundle-data.cmd                    # Windows (Command Prompt or PowerShell)
tar -xf <path to geo-report-data-...tar>   # on the receiving machine, from the project folder
```

The archive (`geo-report-data-<date>-<commit>.tar`, with a `.sha256` checksum next to it) never
contains `.env`: copy your keys separately or create `.env` again. Options: `--no-reports` /
`-NoReports` to leave out `reports/`, and an output folder (`-OutDir <folder>` on Windows). Cached
files are keyed by the code's content and line endings are fixed to LF, so the receiving machine
reuses them at the same or a later commit; the first `gr.R batch` there should make no requests
for data already bundled. A bundle over 4 GB does not fit on a FAT32 USB drive (use exFAT or NTFS).

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
| `catalog [--check] [--html]` | validate the catalog, write `catalog/catalog.html` |
| `verify` | live checks of every operational source (appends to `catalog/verification_log.csv`) |
| `test` | automated tests (offline, with fixtures) |
| `cache prune [--yes]` | list (with `--yes`, delete) derived files that newer versions replaced |

Options: `--offline` (cache only), `--refresh <source,...>` (re-download the raw files in those
`cache/raw/<source>` folders, e.g. `census_acs5`, `bls`, `bea`), `--force` (recompose and re-render),
`--no-render`, `--workers <n>`, `--formats html,typst`. A build whose inputs, code and raw
files are unchanged since its last compose reuses that compose (build.json says so).

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
  inline/bulk editing round trip with conflict detection. They run offline on real API responses
  in `tests/fixtures/`.
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
edit takes about 36 s (compose 20 s, render 15 s). Composing in several processes helps most when
a batch waits on downloads: Maryland's 24 counties, new to the cache, composed in 123 s for half of
them with 4 processes and 233 s for the other half in one. The last cold run of the samples
(2026-09-28, when 48 metrics were operational) took 690 s and 536 requests; the current catalog
needs far more (the review of 2026-09-29 counted 2,488 requests and 978 MB), and IPUMS takes
about 5 minutes per extract.

## Limitations

These apply across sources. How each source is used, and its own limits, is in
`docs/sources.md`; each source's documentation and checks are in the catalog
(`catalog/catalog.html`).

- 420 of the 561 cataloged metrics are operational, from 34 of its 126 sources; the rest are
  documented only. Not built: County Health Rankings (terms need the user's decision), MIT
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
  the former counties (FARS, NOAA zones, the Food Environment Atlas, county-level GDP before 2024).
- Some sources are current snapshots only (child care licensing in Texas and Indiana, HRSA
  shortage areas, the latest CDC PLACES release), so they have no history.
- Licenses: IPUMS NHGIS forbids redistributing its data (extracts stay in the cache; test fixtures
  are made up), and FEMA requires the statement printed under its tables and charts.
- Custom polygons and area-weighted allocation are not supported.
