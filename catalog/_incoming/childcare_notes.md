# Childcare, early childhood and education: research notes (checked 2026-09-28)

## Covered (30 sources, 71 metrics)
- Prices: DOL NDCP county and state files.
- Licensing capacity: TX, IN, NY, CA, CO, WA, MO; Kansas is search-only.
- Establishments: CBP 624410 (SIC 835 before 1998), Nonemployer Statistics, QCEW.
- Subsidy and need: CCDF tables, TWC county counts, WA DCYF.
- Head Start: service locations; PIR (on request).
- Children: ACS 5-year, PEP V2025, SAIPE.
- Education: CCD, EDGE, PSS, IPEDS, Urban Education Data Portal.

## Caveats
- NDCP has no prices for Indiana or New Mexico in any year. Missouri covers only 2015-2020 and Colorado only 2014, 2015 and 2022.
- NDCP values are weekly nominal market-rate prices and are heavily imputed. Read the `i*` flags as text, and pad `COUNTY_FIPS_CODE` to 5 digits.
- Licensing files are current snapshots, except the Colorado 2017-2019 series and the California CSV, which keeps closed facilities.
- Capacity is the regulatory maximum, including school-age slots. It is not enrollment. Rules differ by state, so do not compare ratios across states.
- State-specific gaps:
  - Texas Listed Family Homes show a placeholder capacity of 3.
  - New York omits NYC centers.
  - Indiana hides home addresses and gives ministries no capacity.
  - Washington lacks family homes.
- CBP, NES and QCEW count businesses and jobs, not slots. NES uses mailing addresses.
- Preschool enrollment (ACS, CCD) is not childcare availability.
- All available parents in the labor force = B23008_004+_010+_013 over _002 (US 2020-2024: 68.1%). DP03_0015PE uses a different universe, and its label changed in 2015.
- No Census API key was used. The ACS sample came from the summary file.

## Gaps and unverified items
- No open national facility-level capacity file was found. Web reports say HIFLD Open child care data ended in August 2025; this was not verified.
- There is no county data on childcare enrollment or use, so `childcare_enrollment` has no metrics.
- Kansas has no bulk data (koec.ks.gov returned 403; KDHE data pages returned 404).
- Also unverified: PIR variable IDs, CCDF Policies Database formats, ICPSR NDCP deposit (403), NIEER yearbook (404). The Indiana CCR&R hub dataset is now private.

## Proposed subtopic
`childcare_workforce`: 624410 jobs and wages (QCEW, CBP), now filed under `childcare_supply`.

## Files
- `ndcp_sample.csv` (90 rows x 370 columns; full 91.7 MB xlsx not kept)
- `acs2024_5yr_table_shells.txt`
