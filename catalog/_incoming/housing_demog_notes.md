# housing_demog notes (checked 2026-09-28)

## Coverage
- 30 sources, 81 metrics: housing (incl. homelessness, evictions), demographics, households/families, population history, geography reference/change files.
- All doc_urls fetched; keyless bulk sources sampled.
- No Census API data calls. Variable IDs were checked on keyless metadata endpoints and the ACS 2020-2024 table shells.

## Adapter caveats
- **PEP files:**
  - CSVs are Latin-1.
  - `co-est00int-tot.csv` and `cc-est2020int-agesex-all.csv` have unpadded codes.
  - In 2000s alldata files, AGEGRP 99 = total.
  - Never mix vintages. The V2025 base (Marion IN 977,202) differs from the intercensal CENSUS2020POP (977,206).
- **Connecticut:**
  - Planning regions 09110-09190 are used in PEP V2022+, ACS 2022+, Gazetteer/TIGER 2022+ and BPS county files from 2023.
  - Legacy counties remain in 2020 Census products, 2010-2020 intercensal files and codes2020.
  - FHFA recast its whole history.
  - Rebuild series from town (MCD) data with the Census crosswalk.
- **ACS geography:** ACS uses boundaries as of January 1 of the final year. Chugach and Copper River first appear in 2016-2020. Bedford city (51515) last appears in 2009-2013.
- **ACS releases:**
  - The 2025 1-year release is delayed pending a Commerce disclosure-avoidance order.
  - The 2021-2025 5-year is unreleased.
  - -111111111 is absent from Census's annotation table.
- **ACS bins:** B25034, B25063 and B25075 bins changed (2012, 2015, 2021). C16001 changed in 2016. Race coding changed in 2020.
- **BPS:** two header lines plus a blank line; "reported" columns exclude imputation. In 2025, 12,894 of 12,907 place codes and 5,234 of 5,239 MCD codes matched PEP; 1,578 offices are unincorporated remainders.
- **Historical county counts:** The Census cencounts state files return 404. Use the NBER CSV or Wayback copies.

## Gaps / not verified
- HUD-USPS vacancy data is restricted. Only its dictionary was read, and it labels GEOID a 2000 tract.
- No CoC-to-county crosswalk was researched.
- Not checked:
  - Eviction Lab ETS coverage years
  - FMRs before FY2000
  - CHAS tables other than Table 8
  - ACS block-group availability by table
  - 2000 SF1 household type
  - A 1990s county intercensal file

## Taxonomy proposals
- **`housing/evictions` (new subtopic):** used for the two Eviction Lab metrics. Filings and judgments measure housing instability, which is distinct from cost burden or tenure.
- **Uncertainty code:** CPS/HVS survey MOEs (annual Table B-3) are coded `acs_moe` as the closest value. A generic `survey_moe` code would be clearer.
