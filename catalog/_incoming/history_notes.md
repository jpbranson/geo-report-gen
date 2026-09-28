# History events: research notes

**Output.** 40 rows.
- Geography: nation 11; state:09 3; Gary 8; Austin 8; Travis 1; Williamson 1; Hays 2; Wyandotte 2; Jackson 1; Johnson 3.
- Evidence: documented_event 26; documented_explanation 7; definitional_change 4; boundary_change 3.

**Verification.** Every row cites a page fetched on 2026-09-28. For 39 rows, a script confirmed that the support quote appears exactly in the fetched text, with whitespace collapsed. The Gary schools quote was transcribed by eye from a scanned PDF. `history_work/` holds the cached text and `build_history.py`, which re-runs the checks.

**Blocked or substituted sources**
- The Encyclopedia of Chicago domain does not resolve, so its Internet Archive snapshot (2024-12-27) was used.
- federalregister.gov returned a bot check, so the GovInfo text of the same notice was used.
- CRS report R48872 returned 403 and investors.ussteel.com did not resolve, so the Nippon Steel acquisition of U.S. Steel (reported June 18, 2025) is omitted.
- The kchistory.org stockyards-closure FAQ is gone. The ussteel.com Gary Works page returned 404.

**Not verified or omitted**
- No source calls 1960 Gary's population peak. The row gives the 1960 count; the 1980 count was not fetched.
- Encyclopedia of Chicago claims about why Gary declined were excluded.
- Conflicting or unclear items were not used:
  - the Handbook's Austin 1990 population (472,020, vs. Census 465,622);
  - the Travis entry's 1951 Texas Instruments reference;
  - Johnson County's "129% in the 1960s" (it matches 1950-60);
  - the "unanimous" 1997 Wyandotte vote.

**Caveats for report use**
- Causal wording is allowed only in the 7 documented_explanation rows, always attributed. Their sources include secondary histories (Handbook of Texas, a library blog, a county magazine) and interested parties (Unified Government, U.S. Steel).
- All other rows are events. Next to local trends they show timing only, not causes. NBER recessions are national.
- Flag these series breaks:
  - race, 2010 to 2020;
  - 2020 ACS 1-year estimates (experimental only);
  - CBP, SIC to NAICS at 1997/98;
  - LAUS at 2009/10;
  - Connecticut, planning regions from 2022;
  - Hays County joining the Austin MSA in 1973.
- Encyclopedia figures (steelworkers, race shares) measure different things than modern data; do not splice them into series.
- Approximations:
  - "late 1960s" is coded 1967, "early 1940s" 1940, "mid-2025" 2025;
  - Gary schools are coded to the city;
  - the 1951 flood also hit Kansas City, MO.
