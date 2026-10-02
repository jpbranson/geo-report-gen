# Plan

What the project does and how to use it: README.md. The full brief: docs/REQUIREMENTS.md. How
each source is used: docs/sources.md. The plan as it stood before 1.0, the maintainer's working
log (docs/history/FLIGHT_LOG.md) and the two reviews of 2026-09-29 are in docs/history/.

## Status: 1.0 (2026-10-02)

- Catalog: 17 subjects, 83 subtopics, 126 sources, 561 metrics; 420 metrics operational from 34
  sources, the rest documented. `gr.R catalog --check` is clean; `gr.R verify` reaches every
  operational source (FEMA refuses downloads from Docker, so its file comes from a Windows build).
- Reports: 11 sample configurations (13 report builds; austin-78704 is rejected on purpose), each
  built, rendered and reviewed chart by chart; profiles general, early-childhood,
  economic-development and exhaustive.
- Checks: 457 test expectations pass offline (`gr.R test`, also in GitHub Actions on every
  push); the editing round trip passes 10/10 (`demos/round_trip.R`); the warm benchmark is in the
  README and docs/benchmark.csv.
- The 1.0 checklist (docs/history/PLAN-before-1.0.md, "1.0 release checklist"), done:
  - A. Prune: metrics no report used removed (OEWS, PEP characteristics) or added to the
    exhaustive profile; five superseded blocks removed; one helper for the states of a
    region or division; R/blocks.R split into named steps and wrapped at 100 characters.
  - B. Iteration speed: ACS tables decode only a report's areas (warm compose of the samples
    262 s -> 191 s); the compose key holds the code and catalog as loaded.
  - C. Bulk runs: compose in parallel processes (`--workers`), source request rates shared among
    them (the FBI at 8 a second, its key allows 10); `gr.R cache prune`.
  - D. Docs: README limits across sources; per-source detail in docs/sources.md; this file.
  - E. Release check, fresh benchmark, User-Agent 1.0; E15, the tag v1.0.0.
- Public release review (2026-10-01): LICENSE (GPL-3.0); README quick start from a clean clone
  (cold madison-ms in Docker: 612 s, 1 GB) and keys table; data-sync moved to docs/data-sync.md;
  stricter CLI options; fixes to snapshot periods, census comparisons, compare mode, FARS, LAUS
  (DC), QCEW, the Food Access Atlas in Connecticut. FLIGHT_LOG.md has the details.
- Second release review (2026-10-02), fixed: the gap sentence ("N points above the nation")
  now follows the significance test like the benchmark sentence; parallel builds no longer lose
  inline edits (content/text.csv locked from read to write); transient download failures are no
  longer cached as missing data (building permits, ACS labels, EAVS); error text in reports is
  plain and escaped; FEMA's statement is always printed with its data, and a 403 says how to
  save the file from a browser; the User-Agent names the project (FEMA and the Department of
  Labor refused the bare one); locator and historical maps work for metro areas and ZCTAs;
  tract maps and custom modules that do not apply are left out with a reason; compare-mode
  distributions show every area; ZCTA benchmark shares are labeled as land area; `--refresh`
  checks its names, `--offline` applies to every command; README quick start asks for the BLS
  contact. Git history was rewritten to drop a Cloudflare account ID and an unrelated bucket name.

## After 1.0 (not started before the tag)

- Separate the engine from the user's project (first structural item). A user's reports,
  settings and text now live in tracked files (config/reports.csv, config/settings.csv,
  content/text.csv, config/manifests/), so pulling a new release means merge conflicts.
  - Engine: this repository (R/, the catalog, quarto/, the default profiles, themes, settings
    and text).
  - Project: a folder named by `GR_PROJECT` (default: the checkout, so nothing changes for a
    current clone) holding the user's reports.csv, settings and text records, manifests,
    profiles, modules, reports/ and cache/. Engine defaults are read first and the project's
    rows override them, as text scopes already do.
  - Start from `GR_ROOT` and `GR_CACHE` (root_path() would split into engine and project
    paths), and the test helpers that build temporary project copies. Writes (`new`, inline
    and bulk edits, `verify`) go to the project only; Docker mounts the project folder.
  - Done when a project made by a 1.0 checkout builds unchanged after pulling a newer engine,
    with a test for it and README steps for moving an existing checkout's edits into a
    project folder.
  - Not a full R package: the audience runs Docker, and the product is a folder of
    configuration and editable reports. Reconsider if people want parts from their own R code
    (a small package of the margin-of-error and geography functions would fit that).
- Cold benchmark from an empty cache, on the Windows machine (FEMA downloads work there); README
  and docs/benchmark.csv updated with it.
- Queue items waiting on the maintainer: County Health Rankings (terms), MIT Election Lab (guestbook
  download), HUD PIT/HIC (bot challenge).
- Not built inside done sources: NCES before 2017, NDCP six-month age bands, LRAM 2010 and 2015
  editions, building permits for places before 2007, a tract use of the NHGIS historical
  boundaries, LODES origin-destination commuting.
- School districts (catalog/geo_support.csv: planned).
- Seen in the 1.0 review, not defects:
  - Re-deriving a table from a cached download counts as a retrieval in the report's
    "Retrieval" dates (a provider edit moves them to that day).
  - The decennial census has no pieces for city parts, so a union of a county and a city's parts
    (travis-austin) shows its census counts as context areas.
  - An indexed chart leaves out an area with no value in the base period (the U.S. and the
    Midwest in kc-core's public school enrollment, whose CCD series start later).
- Open findings of the release review (not fixed for 1.0; file references as of the review):
  - Statistics: the part-whole adjustment weights by population share, not the share of the
    metric's denominator its comment describes (geography.R benchmark_entity, stats.R
    diff_test); distribution error bars take the total's MOE from the bins rather than the
    published total, and the block has no unavailable rows or zero-total guard (blocks.R
    distribution); moe_sum counts every zero estimate's MOE (Census guidance keeps only the
    largest).
  - Checks: the `benchmarks` setting is not validated and its benchmarks get no part-whole
    adjustment (geography.R); metric completeness counts rows, not (piece, variable) pairs, and
    calls a missing variable a boundary change (metrics.R); ZCTA-county parts include water-only
    intersections (geography.R zcta_county_parts); EAVS national totals omit states without a
    note; Texas HHSC drops unmatched county names silently.
  - Behavior: `batch` and `verify` exit 0 when reports or checks fail; an NHGIS extract that
    outlasts the 30-minute wait is requested again next build; map legend labels are fixed
    English.
  - Memory: rebuilding the NDCP table (any edit to R/providers/childcare.R) peaks near 7.3 GB,
    since readxl parses the whole 92 MB workbook (skipping columns does not help); in Docker's
    8 GB it fits only alone. Moving NDCP into its own provider file would stop unrelated child
    care edits from forcing it.
  - Low: Docker on Linux writes root-owned files; `tar -xf` of a bundle overwrites newer cache
    files; NHGIS unzips whole archives and sends its key to the download URL the API names;
    `new --label` is ignored for mode separate; geom_errorbarh is deprecated in ggplot2 4.
- Open findings of the second review (2026-10-02), not fixed for 1.0:
  - Releases: latest years are set in each provider file, and some cached downloads keep their
    name when a year is added (README "New data releases" says to use `--refresh`); one table
    of release pins would be simpler. `%||% 2024` fallbacks for `boundary_vintage`/`acs_release`
    repeat config/settings.csv in several providers; FARS and NCES label "2024 boundaries"
    whatever `boundary_vintage` is.
  - Text: a facts table marks significant differences but not untested ones (union medians);
    medians without a bins table are not aggregable, which README "Statistics" does not say;
    "Built 1939 or earlier" has an upper bound of 1940; fmt_moe does not shorten large dollars.
  - CLI: `find Boulder Colorado` (unquoted) searches for the first word; `batch a a` composes a
    report twice; a failed `preview` exits 0; outside the project root gr.R fails with "cannot
    open file 'R/load.R'"; build.json strips the cache prefix with a regular expression (a
    `GR_CACHE` path with regex characters keeps absolute paths).
  - Code: duplicated helpers (FARS/NOAA county successors, the Connecticut planning-region test,
    BEA line parsing three times, the UNDER5 ACS block in childcare.R, `pad()` defined in
    pep.R); prefetch_acs writes cache entries without .meta.json; nhgis_extract does not check
    for a NULL lock and names extracts with digest() rather than hash_value(); the FBI note says
    no department matches when two do; the Food Access Atlas sums tracts missing from the
    distance files as zero; `study_share` in compare mode is the sum of all areas (unused);
    unknown `benchmark_levels` are ignored silently; the Lua filter's comment says text is
    filled once, but figure captions pass through knitr hooks first.
  - tools/data-sync-filters.txt still says "see README" (editing it forces a resync on every
    machine; change it with the next filter change).
- Speed: austin-core and kc-core take ~40 s each to compose warm, in providers other than the
  ACS; the block-result cache (review item 21) is undecided now that a prose edit of gary-in
  takes 36 s, of which 15 s is rendering.
