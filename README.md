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
4. Run `data-sync` first on the machine with the most data: it uploads everything (about 4 GB).

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
| `batch [id...]` | build many reports: compose one by one (shared cache), then render in parallel |
| `new <id> --geo <spec> [--mode ...] [--profile ...] [--subjects a,b] [--metrics m1,m2] [--label ...]` | add a report, optionally with a manifest built from subjects and metrics |
| `preview <id>` | live preview while editing `reports/<id>/report.qmd` |
| `harvest <id>` | save inline edits without rebuilding |
| `text-export <id> <file.csv>` / `text-import <file.csv>` | bulk text editing in a spreadsheet |
| `find "<name>"` | look up geography IDs by name |
| `catalog [--check] [--html]` | validate the catalog, write `catalog/catalog.html` |
| `verify` | live checks of every operational source (appends to `catalog/verification_log.csv`) |
| `test` | automated tests (offline, with fixtures) |

Options: `--offline` (cache only), `--refresh <source,...>` (re-download the raw files in those
`cache/raw/<source>` folders, e.g. `census_acs5`, `bls`, `bea`), `--force` (recompose and re-render),
`--no-render`, `--workers <n>`, `--formats html,typst`. A build whose inputs, code and raw
files are unchanged since its last compose reuses that compose (build.json says so).

The cache only grows. `cache/metrics/` holds computed results, including ones no longer used
after code or data changes; it can be deleted whenever no build is running, and the next build
recomputes what it needs (about 7 seconds per report). The `.lock` files beside cache entries
can be deleted at the same time. `cache/raw/` holds downloads, some slow to get again (IPUMS
extracts need a new request on your account), so delete from it only with `--refresh` in mind.

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

Results on 2026-09-29 (Windows laptop; the 12 sample builds and the intended rejection; 4
parallel renders; `--warm`, so no cold run and no data refresh):

| Step | Seconds | Compose / render | Rendered |
|---|---:|---:|---|
| First build of a fresh copy (warm cache) | 327 | 232 / 95 | 12 |
| Nothing changed | 8 | 8 / 0 | 0; every compose reused |
| Forced re-render | 329 | 234 / 95 | 12 |
| Resumed after an interruption (default intro edited) | 271 | 195 / 77 | 9; 3 up to date |
| Theme edit (default accent color) | 307 | 221 / 86 | 11; the civic-themed report reused |
| Geography edit (one report becomes a union) | 29 | 17 / 12 | 1; the other reports reused |

A build reuses its last compose when its code, catalog, content, own configuration, raw files
and report.qmd are unchanged; a text or theme edit therefore recomposes every report it may
touch (about 20 s each), and rendering takes 20-40 s per report. For one report (gary-in), a
prose edit takes about 68 s (compose 37 s, render 29 s). The last cold run (2026-09-28, when
48 metrics were operational) took 690 s and 536 requests; the current catalog needs far more
(the review of 2026-09-29 counted 2,488 requests and 978 MB for the samples), and IPUMS takes
about 5 minutes per extract.

## Limitations

- 335 of the 537 cataloged metrics are operational (ACS detailed tables, decennial census,
  population estimates, SAIPE, SAHIE, CDC PLACES, County Business Patterns, Nonemployer
  Statistics, LEHD LODES, BLS QCEW, BEA county income and GDP, NHTSA FARS, FEMA National Risk
  Index, USDA Food Environment Atlas, EAC Election Administration and Voting Survey, Census of
  Governments finance, FBI Crime Data Explorer, IPUMS NHGIS, BLS unemployment, FHFA, building
  permits, child care prices, Texas licensing); the rest are documented only.
- LODES (jobs by workplace and employed residents, 2002-2023) counts primary jobs, each worker's
  highest-paying job, summed from census blocks: cities, tracts and unions get exact values, on
  2024 boundaries in every year. It has no national or regional totals, and states that supplied
  no job data in some years (Alaska from 2017, Michigan from 2022, Washington, DC, before 2010,
  Massachusetts before 2011, four more states in 2002-2003) have no values then. Federal civilian
  jobs are counted from 2010. Commuting flows (the origin-destination files) are not used yet.
- QCEW (jobs, establishments and pay at employers covered by unemployment insurance, 2001-2025)
  covers counties, states and the nation; regions are sums of states. BLS's 1990-2000 files are a
  NAICS reconstruction with one-year spikes (Oakland County, Michigan, 1997; New Jersey 1995) and
  are not used. Values withheld to protect employers are shown as not published, never as zero.
  The annual files take 1.9 GB in the cache (downloaded once and shared by every report).
- County GDP (BEA, 2001-2024) is in current dollars, which add up across areas, plus BEA's real
  GDP index for growth, which does not: combined areas and Census regions have no real growth
  line. The industry mix uses twelve industry groups, withheld far less often than single
  sectors. Connecticut's planning regions have GDP for 2024 only and no real GDP index.
- Nonemployer Statistics (1997-2023, counties, states and the nation) count businesses without
  paid employees, mostly the self-employed, which the job sources leave out, including home-based
  child care. Rates use BEA's population, or the Census Bureau's estimates where BEA has none
  (Connecticut's planning regions before 2024). Child care counts dip in 2017 nationally with no
  documented cause.
- Traffic deaths (NHTSA FARS, 1982-2023) are counted where crashes happened. Counties come from
  the crash codes; cities, their county parts and tracts from crash coordinates, which start in
  2001, located in full-resolution 2024 TIGER/Line boundaries (a state-year needs 95% of crashes
  with coordinates). Rates per 100,000 residents use 5-year totals and the ACS 5-year population.
  Connecticut's planning regions are not coded (FARS keeps the former counties).
- Census years before the ACS (IPUMS NHGIS) cover income and poverty (1970 or 1980 to 2000),
  education, work, commuting (commuting modes 1990 and 2000) and homeownership (1970 to 2000).
  Most come from the census long form, a sample; NHGIS publishes no margins of error for them,
  so they are drawn as dots and never tested. Areas are linked across censuses by name and code,
  on each census's boundaries. A chart with census years and ACS periods also states the change
  from the first census to the latest period, as approximate and untested. Connecticut's planning
  regions get census counts and shares summed from their towns (which kept their codes); their
  medians, and combined areas' medians, have no census values. The NHGIS terms forbid
  redistributing the data: extracts stay in the cache, and the test fixtures are made up. Other
  NHGIS holdings (constant-boundary counts, Connecticut crosswalks) are described in
  `docs/nhgis.md`.
- Population census counts reach back to 1790 for counties, states and the nation, and to 1970
  for places and county subdivisions (IPUMS NHGIS until 1990). A county's early counts cover
  its territory at each census, which may differ from today's.
- County Business Patterns before 1998 (IPUMS NHGIS) give all-industry jobs from 1970 and
  payroll and establishments from 1974 for counties, states and the nation, under SIC industry
  codes; they are drawn as a separate series from the NAICS years. National files start in 1977
  and state files skip 1971, 1973 and 1976. The 1975 state file reports payroll in thousands
  of dollars; the provider converts it. Payroll per employee starts in 1974.
- Constant dollars use the R-CPI-U-RS from 1978. Earlier years follow the Census Bureau's
  historical income index (the CPI-U-X1 for 1967-1977, the CPI-U before), joined by ratio at
  1978 as the Census Bureau joins them.
- Crime rates (FBI Crime Data Explorer, 1985-2025) need a free api.data.gov key in `.env`
  (`DATA_GOV_API_KEY`), sent only as a request header. The FBI publishes police agencies: a city
  is its police department (matched by name) and needs all 12 months reported in a year (Gary did
  not report in 2020 or 2021); states and the nation cover the agencies that reported. A county
  adds up every agency the FBI lists in it, dividing a department that serves several counties
  by where its residents live; agencies listed in no county (most state police, and the New York
  City and D.C. police) are left out, and a year needs agencies serving 75% of the county's
  residents to report every month, so county figures are approximate. An agency's year with under
  a quarter of its usual offenses (the median of the three years on each side, when that is at
  least 20) also counts as not reported: Kansas City, Kansas marked 2023 as reported while moving
  to NIBRS but sent almost nothing. From 2013 violent crime counts rape under a revised, broader
  definition, so the years before and after are separate series. Agencies that report through
  NIBRS are converted by the FBI to the same summary counts, so that move is not a break.
- Government finances (2022 Census of Governments) describe the county government for counties
  and the city's own government for cities, not all local governments in an area. Connecticut
  has no county governments, and consolidated city-counties (Indianapolis, Wyandotte County and
  Kansas City, Kansas) count as cities, so those counties have no county-government values.
- Voter registration and turnout (EAC survey, 2020 and 2024) are totals of election
  jurisdictions: counties, New England towns, Wisconsin municipalities and a few cities that run
  their own elections. Counties split by such a city (Kansas City, Missouri) and Wisconsin and
  Alaska counties have no values; the national value covers the states that reported every
  jurisdiction. Counts by voting method are not used, because they do not add up in some states.
- The USDA Food Environment Atlas publishes county values only (no state or national values and
  no populations behind its rates), so its table shows the county alone and combined areas get
  no value. It still uses Connecticut's former counties, so Connecticut planning regions have no
  Atlas values.
- The FEMA National Risk Index is used for counties (city reports show their county). Its
  scores rank counties against each other, so they exist only for single counties; expected
  losses add up to states, the nation and combined areas. FEMA's terms require the statement
  printed under each hazard table and chart. Census tracts (a 635 MB national file) are not used.
- County Business Patterns (jobs, establishments and payroll where businesses are located)
  covers counties, states and the nation. From 2017 a sector with fewer than 3 establishments in
  a county is not published, so jobs by industry are shown by NAICS sector (combining sectors
  would lose whole groups) and small sectors can be missing for small counties.
- City histories start in 2000: the Census API has no earlier census tables for places.
- Medians of combined areas have no margin of error (the Census Bureau publishes no method).
- SAIPE and SAHIE (annual poverty, income and health insurance estimates) cover counties, states
  and the nation, so city reports show county context; combined areas get a value without a
  margin of error, because the model errors of different counties cannot be combined.
- CDC PLACES health measures are model-based estimates from the latest release only (CDC advises
  against comparing releases). They are not age-adjusted, and CDC publishes no state values, so a
  state is the sum of its counties. Kentucky and Pennsylvania lack most measures in the 2025
  release, and the social-needs questions were asked only in some states (not Texas); tables then
  say why no estimate is shown.
- Licensed child care capacity is implemented for Texas only; it is a current snapshot.
- Custom polygons and area-weighted allocation are not supported.
