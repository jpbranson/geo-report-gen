# IPUMS NHGIS: older history for this project (investigated 2026-09-28)

NHGIS (IPUMS, University of Minnesota) republishes every decennial census from 1790, the ACS,
County Business Patterns 1970-2002 and other historical tables. It links them across years in
"time series tables" and has boundary files and crosswalks. The source is in `catalog/sources.csv`
as `ipums_nhgis`.

**Implemented (2026-09-29):** addition 1 below, in `R/providers/nhgis.R`. It covers census years
1970-2000 of B79, BD5, CL6/AX6, B84, B69, C53 and B37. They appear in the income, per capita
income, poverty, labor force, employment ratio, education and homeownership charts (as dots) and
the commuting chart (1990 and 2000 bars), for the nation, regions, divisions, states, counties,
towns and places. Additions 4 and 5: population counts from 1790 (A00; places and towns from
1970, AV0) in the long population history, and County Business Patterns 1970-1997 (all
industries, SIC) in a jobs history chart and the payroll chart. For Connecticut's planning
regions (addition 2), census counts and shares are summed from their towns, which kept their
codes, rather than carried through the crosswalks; medians have no census values there.
Additions 3 and 6, and the topics without time series tables, are still open.

## What it would add

| Topic | The project starts | NHGIS starts | NHGIS time series tables | Levels |
|---|---|---|---|---|
| Population | 1900 counties; 2000 places, tracts | 1790 counties; 1970 all levels | A00; AV0 | A00: nation, state, county. AV0: all 8 |
| Age and sex, race, Hispanic origin, households | 2000; ACS 2005-2009 | 1970 | B58, B18, A35, AR5 | all 8 |
| Housing units, occupancy, tenure | 2000; ACS 2005-2009 | 1970 | A41, A43, B37 | all 8 |
| Median household and family income, per capita income | ACS 2005-2009 (SAIPE 2005) | 1980 (income brackets from 1970, BS7) | B79, AB2, BD5 | all 8 |
| Poverty | ACS 2005-2009 (SAIPE 2005) | 1970 | CL6 / AX6 | all 8 |
| Educational attainment | ACS 2005-2009 | 1970 | B69 (B85 from 1990) | all 8 |
| Labor force and employment | ACS; LAUS 1990 | 1970 (census years) | B84 | all 8 |
| Commuting | ACS 2005-2009 | 1970 mode (no tracts); 1980 travel time | C54, C50 (C53 from 1990) | C54: state, county, towns, places |
| Home value, rent, industry, occupation | ACS 2005-2009 | 1970, source tables only (no time series) | 1970 Count 4, 1980 STF 3, 1990 STF 3, 2000 SF 3 | down to tracts |
| Jobs and establishments (CBP) | 1998 | 1970 (SIC industry codes to 1997) | CBP datasets 1970-2002 | state, county |

"All 8" means nation, region, division, state, county, tract, county subdivision (town) and place.
Counts such as population, age, race and housing run through 2020. Long-form topics (income,
poverty, education, work, commuting) stop at the 2000 census and continue with ACS 2006-2010 to
2020-2024, which the project already has. Tracts covered only some
cities before 1990 (8 in 1910) and the whole country from 1990.

Two further options:
- **Constant boundaries:** standardized tables put 1990, 2000, 2010 and 2020 counts on 2010
  boundaries: CL8 population, CW5 age and sex, CM1 race, CP4 Hispanic origin, CM4 households,
  CM7 housing units, CM9 occupancy, CN1 tenure. They cover 10 levels, including block groups and
  ZCTAs. They hold counts only; there are no medians and no long-form or ACS data yet.
- **Connecticut planning regions:** the crosswalks `nhgis_blk2010_co2022`, `nhgis_bg2010_co2022`
  and `nhgis_tr2010_co2022` map 2010-geography data onto the 2022 planning regions. Chained with
  the standardized tables, they would carry 1990-2020 counts into the regions (an inference, not
  tested). Planning regions are made of whole towns, so summing town tables from 1970 should also
  work. There is no 2020-to-2022 crosswalk; NHGIS points to CTData and Geocorr 2022.

## Access and terms

- **Account and key:** a free IPUMS account and API key are needed.
  - Even the metadata API needs the key (HTTP 401 without it).
  - Crosswalk downloads redirect to the IPUMS login.
- **Extracts are asynchronous:** define, submit, wait, download.
  - In R, ipumsr 0.10.0 (CRAN, 2026-03-13): `set_ipums_api_key()`, `get_metadata_catalog()`,
    `define_extract_agg()`, `submit_extract()`, `wait_for_extract()`, `download_extract()`,
    `read_ipums_agg()`, `read_ipums_sf()`, `download_supplemental_data()`.
- **Terms:**
  - Cite NHGIS Version 21.0 (doi:10.18128/D050.V21.0).
  - The terms say "You will not redistribute the data without permission." So extracts stay in the
    git-ignored cache, and reports publish derived statistics with the citation.

## Cautions when extending history

- Nominally integrated series link areas by name and code, so a series stops when a code changes
  (Connecticut in 2022). Boundaries also change between censuses.
- Race comparisons break in 2000, when people could first report more than one race.
- Census income is for the prior calendar year, in nominal dollars; the project's CPI adjustment
  would apply.
- The poverty definition changed in 1980. Education was counted in years of school through 1980
  and in degrees from 1990.
- 1970 sample tables omit places under 2,500 people.

## Ranked additions

1. Census-year points (1970 or 1980 to 2000) for existing ACS metrics: income, poverty,
   education, labor force, commuting, tenure. They would cover tracts, places, towns and counties
   (B79, AB2, BD5, CL6/AX6, B69, B84, C54, B37).
2. Continuous Connecticut planning-region history through the 2010-to-2022 crosswalks.
3. Population and housing counts 1990-2020 on constant 2010 tract and block group boundaries
   (CL8, CM7, CN1, CW5, CP4).
4. County population 1790-1890 (A00), extending the 1900-1990 series.
5. County Business Patterns 1970-1997 (all-industry totals, since industry codes change).
6. Historical boundary files for maps: counties from 1790, tracts from 1910.

## Sources

- https://www.nhgis.org/data-availability
- https://www.nhgis.org/overview-nhgis-datasets
- https://www.nhgis.org/time-series-tables and https://assets.nhgis.org/NHGIS_Time_Series_Tables_Lists.xlsx
  (285 nominal and 115 standardized tables; codes and years above checked against it)
- https://www.nhgis.org/geographic-crosswalks
- https://www.nhgis.org/citation-and-use-nhgis-data
- https://developer.ipums.org/docs/v2/apiprogram/apis/nhgis/
- https://cran.r-project.org/package=ipumsr and https://tech.popdata.org/ipumsr/reference/index.html
