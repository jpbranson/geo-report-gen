# Plan

What the project does and how to use it: README.md. The full brief: docs/REQUIREMENTS.md. How
each source is used: docs/sources.md. The plan as it stood before 1.0, the running log of the
sessions that built it, and the two reviews of 2026-09-29 are in docs/history/.

## Status: 1.0 (2026-10-01)

- Catalog: 17 subjects, 83 subtopics, 126 sources, 561 metrics; 420 metrics operational from 34
  sources, the rest documented. `gr.R catalog --check` is clean; `gr.R verify` reaches every
  operational source (FEMA refuses downloads from Docker, so its file comes from a Windows build).
- Reports: 11 sample configurations (13 report builds; austin-78704 is rejected on purpose), each
  built, rendered and reviewed chart by chart; profiles general, early-childhood,
  economic-development and exhaustive.
- Checks: 416 test expectations pass offline (`gr.R test`); the editing round trip passes 10/10
  (`demos/round_trip.R`); the warm benchmark is in the README and docs/benchmark.csv.
- The 1.0 checklist (docs/history/PLAN-before-1.0.md, "1.0 release checklist"), done:
  - A. Prune: metrics no report used removed (OEWS, PEP characteristics) or added to the
    exhaustive profile; five superseded blocks removed; one helper for the states of a
    region or division; R/blocks.R split into named steps and wrapped at 100 characters.
  - B. Iteration speed: ACS tables decode only a report's areas (warm compose of the samples
    262 s -> 191 s); the compose key holds the code and catalog as loaded.
  - C. Bulk runs: compose in parallel processes (`--workers`), source request rates shared among
    them (the FBI at 8 a second, its key allows 10); `gr.R cache prune`.
  - D. Docs: README limits across sources; per-source detail in docs/sources.md; this file.
  - E. Release check, fresh benchmark, User-Agent 1.0. Open: E15, the tag.

## After 1.0 (not started before the tag)

- Cold benchmark from an empty cache, on the Windows machine (FEMA downloads work there); README
  and docs/benchmark.csv updated with it.
- Queue items waiting on the user: County Health Rankings (terms), MIT Election Lab (guestbook
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
- Speed: austin-core and kc-core take ~40 s each to compose warm, in providers other than the
  ACS; the block-result cache (review item 21) is undecided now that a prose edit of gary-in
  takes 36 s, of which 15 s is rendering.
