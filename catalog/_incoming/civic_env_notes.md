# civic_env notes (2026-09-28)

**Boundary.** 29 sources, 80 metrics: transportation, broadband, public_safety, environment_climate, civic_participation, public_services_finance (+1 industries_business LODES metric). Every `verified` doc was fetched this session. FCC map, CDE and AirData pages were read in a browser (scripts blocked).

**Status changes that matter**
- EJScreen: EPA access ended 2025-02-05 and epa.gov/ejscreen returns 404. Only archived v2.3 remains (Harvard Dataverse doi:10.7910/DVN/RLR5AX, CC0; PEDP rebuilt the tool). Label it archived.
- FEMA NRI: the app is retired. v1.20 (Dec 2025) is on OpenFEMA/RAPT. Its inputs changed (flooding, tsunami, landslide, social vulnerability), so there are no cross-version trends.
- NFIRS: sunset Feb 2026. From 2026 it is NERIS only, a series break.
- FCC: Form 477 (blocks, to Jun 2021) and BDC (locations, Jun 2022-Dec 2025) are not comparable.
- FBI: 2021 was NIBRS-only. CDE coverage was about 77%, against about 96% in 2020. The FBI discourages rankings.
- ACS: B08301 transit sub-rows were redefined in 2019 and the taxi label changed in 2024. The B28 series starts 2013-2017 with a 2016 question change. B08013, B08014 and B08201 have no block groups.
- LODES 8.4: covers 2002-2023. OD/WAC files are missing for AK 2017-2023 and MI 2022-2023. Earnings bands are fixed nominal amounts.

**Access frictions**
- MEDSL 2000-2024: needs a Dataverse guestbook (not submitted). The legacy 2000-2016 GitHub copy is open.
- ICPSR county UCR: needs a login; no redistribution; ends with 2016.
- FCC: hosts return 403 to scripts. The BDC API needs an account and a token.
- AirData: aqs.epa.gov reset scripted connections (browser worked).
- CDC Tracking API: throttles requests without a token (429).
- NHTSA: pages and CrashAPI return 403; static FARS zips work.
- Lincoln FiSC terms: personal, non-commercial use only.

**Not verified / gaps**
- CDC heat: years and threshold.
- CEV: MSA tables.
- NCVS: sub-national estimates.
- Form 477: files before Dec 2015.
- ASPEP: history.
- FiSC: dollar base year.
- AirData: file headers.
- NFIRS: field names.
- Local EMS: none (NEMSIS is national and de-identified).
- CEV table: the 2023 friends/family discussion column duplicates the neighbors column in all 51 rows.

**Conventions and proposals**
- `uncertainty=acs_moe` also marks published CPS, NTIA and NCVS MOEs/SEs. Proposal: add `survey_moe`.
- Proposed subtopic `public_safety/reporting_coverage` for data-quality indicators (UCR coverage, ICPSR Coverage Indicator), filed under `crime` for now.
- EAVS town jurisdictions (New England, Wisconsin) need CVAP MCD denominators, which exist for 12 states only.
