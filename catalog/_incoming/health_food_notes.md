# Health and food access: inventory notes

**Scope.** 21 sources and 59 metrics, checked 2026-09-28. Every doc_url was fetched. Data rows were pulled for 17 sources. Four were not sampled:
- SAHIE and ACS: the Census API rule applies. I range-sampled the ACS 2024 summary files to check geography. B27010 has block groups; B18101, C18108, C27007, B27001, B22001 and B22003 do not.
- WONDER: the query needs data-use consent, and its API returns national data only.
- MMG: data come only through a request form.

**Measure types.**
- Model-based: PLACES, SAHIE, SVI, USALEEP, MMG, FARA.
- Direct survey: ACS, BRFSS.
- Administrative, event or facility: NVSS deaths, HRSA, CMS, FNA SNAP.

**Key caveats**
- PLACES
  - The 2025 release uses BRFSS 2023. Its IDs (swc5-untb, eav7-hnsx, cwsq-ngmh, qnzd-25i4) are overwritten yearly, so pin the archive IDs.
  - CDC says the model cannot track local change.
  - 2024 switched to 2020 geography and CT planning regions. Measure IDs change (ISOLATION became LONELINESS).
  - KY and PA lack the 2023 measures. BRFSS 2024 lacks TN and BRFSS 2025 lacks CA, MS and NV.
- BRFSS: not comparable before 2011.
- FARA: the July 2026 SRAM (all SNAP retailers, 2020 tracts, driving distance) is not comparable with LRAM 2010/2015/2019.
- Food Environment Atlas: state values repeat on county rows. USDA ended future Household Food Security Reports (Sept 2025), which threatens its food-insecurity items and MMG inputs.
- WONDER: suppresses counts of 1-9. The unreliable-rate rule changed with the 2024 data. Connecticut county rates are unavailable for 2022 and later.
- CHR&R: licensed for non-commercial use only, and its future after 2026 is unclear.
- SNAP: admin counts fell sharply in some states in 2025-26 (Arizona -52.5%). ACS receipt runs well below admin counts.
- HRSA and CMS: current snapshots only, so archive them.
- AHRF: variable labels were inferred from variable names.

**Proposed taxonomy additions**
- `health/social_vulnerability`: SVI is in environment_climate/hazard_risk for now.
- `health/health_behaviors`: smoking and inactivity sit in health_outcomes for now.
- Uncertainty code `survey_ci`: BRFSS and WONDER CIs are coded model_interval for now.

**Not covered or verified**
- WIC and school meals
- HRSA UDS patient counts
- NPPES and CMS Provider of Services files
- Medicaid enrollment
- WONDER natality and provisional mortality
- MMG variable names
- bhw.hrsa.gov pages (403)
- `census_acs_1yr` has no metric rows of its own; the ACS metrics list 1-year periods.
