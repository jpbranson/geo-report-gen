# Economy inventory notes

## Coverage

This inventory has 26 sources and 75 metrics. All docs were fetched on 2026-09-28, and data samples were retrieved for 22 of the sources.

- **BLS:** LAUS, national CPS, QCEW, CES State and Area, OEWS, CPI-U, R-CPI-U-RS.
- **BEA:** CAINC, SAINC, CAGDP, RPP.
- **Census:** ACS, SAIPE, CBP/ZBP, SUSB, ABS, NES, BFS, BDS, LODES, QWI, HPS/HTOPS, SIPP.
- **Other:** IRS SOI, United For ALICE, Map the Meal Gap.

## Caveats

- **2025 shutdown.** October 2025 is missing in LAUS, CPS and CPI.
  - LAUS and CPS 2025 annual averages cover 11 months.
  - The CPI-U 2025 annual average (M13 = 321.943) is the mean of the 11 available months.
- **Connecticut planning regions start at different points:**
  - LAUS has regions only, back to 1990.
  - QCEW and BEA switch in 2024. BEA has no overlap: counties run 1969-2023.
  - SAIPE, CBP and BFS switch in 2022.
- **BEA:**
  - Metro aggregates have been dropped; sum counties instead.
  - The county employment table (CAEMP25N) ended with 2022 data.
  - SAINC1.zip does not exist; use SAINC.zip.
  - A bad zip URL returns HTML with HTTP status 200.
- **QCEW:**
  - MSA data are totals only from 2025 Q2.
  - Suppressed cells show 0 with code N.
  - Open-data slices start in 2014.
- **Commerce DAO 216-26 (2026)** bans noise infusion, so CBP, NES and BFS disclosure methods may change.
- **HTOPS 2025-2026:**
  - The tables are U.S.-only.
  - The expense item's reference period changed from 7 days to 2 months.
- **R-CPI-U-RS:** values change between vintages, so record the vintage used.

## Gaps

- **SSA SSI by county:** omitted because the site returned 403.
- **Rules I did not verify:** Map the Meal Gap license terms, ABS withheld-cell rules, SOI small-cell rules, BDS flag codes, and table-specific ACS start years (those `history_start` fields are left blank).
- **Not catalogued:** CPS ASEC/SPM, USDA SNAP administrative data, HUD income limits, and monthly BFS.
- **ACS 2024 5-year tables that stop at tract level:** B17001, B17020, B22001, B19083, C24050.

## Proposed extensions (used in the CSVs)

1. **Subtopic `income_poverty_hardship/prices_inflation`** for CPI-U, R-CPI-U-RS and RPP. No existing subtopic fits deflators or price levels. If you reject it, remap to `household_income`.
2. **Uncertainty value `survey_se`** for non-ACS sampling error: CPS, OEWS and ABS RSEs, HPS SEs, and SIPP replicate weights. If you reject it, remap to `none_published`.
