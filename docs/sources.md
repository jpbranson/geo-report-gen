# How each source is used

What the adapters in `R/providers/` take from each source, and the limits that follow. Each
source's own documentation, coverage, suppression rules and checks are in the catalog
(`catalog/sources.csv`, `catalog/metrics.csv`; `gr.R catalog --html` writes
`catalog/catalog.html`). The README lists the limits that apply across sources.

## Population and households

- Population census counts reach back to 1790 for counties, states and the nation, and to 1970
  for places and county subdivisions (IPUMS NHGIS until 1990). A county's early counts cover
  its territory at each census, which may differ from today's.
- Census counts of households, household types, vacancy, homeownership, median age and race come
  from the 2000, 2010 and 2020 censuses; Population Estimates components of change (natural
  increase and migration) cover 2021-2025.
- A county map of 1900 is drawn from NHGIS historical boundary files.
- Census years before the ACS (IPUMS NHGIS) cover income and poverty (1970 or 1980 to 2000),
  education, work, commuting (commuting modes 1990 and 2000) and homeownership (1970 to 2000).
  Most come from the census long form, a sample; NHGIS publishes no margins of error for them,
  so they are drawn as dots and never tested. Areas are linked across censuses by name and code,
  on each census's boundaries. A chart with census years and ACS periods also states the change
  from the first census to the latest period, as approximate and untested. Connecticut's planning
  regions get census counts and shares summed from their towns (which kept their codes); their
  medians, and combined areas' medians, have no census values. The NHGIS terms forbid
  redistributing the data: extracts stay in the cache, and the test fixtures are made up. Other
  NHGIS holdings (constant-boundary counts, tried and removed; Connecticut crosswalks) are described in
  `docs/nhgis.md`.

## Income, poverty and hardship

- SAIPE and SAHIE (annual poverty, income and health insurance estimates) cover counties, states
  and the nation, so city reports show county context; combined areas get a value without a
  margin of error, because the model errors of different counties cannot be combined.
- BEA county income gives personal income, transfers, income maintenance benefits, earnings and
  earnings by industry.

## Jobs, business and the economy

- QCEW (jobs, establishments and pay at employers covered by unemployment insurance, 2001-2025)
  covers counties, states and the nation; regions are sums of states. BLS's 1990-2000 files are a
  NAICS reconstruction with one-year spikes (Oakland County, Michigan, 1997; New Jersey 1995) and
  are not used. Values withheld to protect employers are shown as not published, never as zero.
  The annual files take 1.9 GB in the cache (downloaded once and shared by every report).
- LODES (jobs by workplace and employed residents, 2002-2023) counts primary jobs, each worker's
  highest-paying job, summed from census blocks: cities, tracts and unions get exact values, on
  2024 boundaries in every year. It has no national or regional totals, and states that supplied
  no job data in some years (Alaska from 2017, Michigan from 2022, Washington, DC, before 2010,
  Massachusetts before 2011, four more states in 2002-2003) have no values then. Federal civilian
  jobs are counted from 2010. Commuting flows (the origin-destination files) are not used yet.
- County Business Patterns (jobs, establishments and payroll where businesses are located)
  covers counties, states and the nation. From 2017 a sector with fewer than 3 establishments in
  a county is not published, so jobs by industry are shown by NAICS sector (combining sectors
  would lose whole groups) and small sectors can be missing for small counties.
- County Business Patterns before 1998 (IPUMS NHGIS) give all-industry jobs from 1970 and
  payroll and establishments from 1974 for counties, states and the nation, under SIC industry
  codes; they are drawn as a separate series from the NAICS years. National files start in 1977
  and state files skip 1971, 1973 and 1976. The 1975 state file reports payroll in thousands
  of dollars; the provider converts it. Payroll per employee starts in 1974.
- Nonemployer Statistics (1997-2023, counties, states and the nation) count businesses without
  paid employees, mostly the self-employed, which the job sources leave out, including home-based
  child care. Rates use BEA's population, or the Census Bureau's estimates where BEA has none
  (Connecticut's planning regions before 2024). Child care counts dip in 2017 nationally with no
  documented cause.
- County GDP (BEA, 2001-2024) is in current dollars, which add up across areas, plus BEA's real
  GDP index for growth, which does not: combined areas and Census regions have no real growth
  line. The industry mix uses twelve industry groups, withheld far less often than single
  sectors. Connecticut's planning regions have GDP for 2024 only and no real GDP index.
- BLS unemployment (LAUS) gives the labor force, employed and unemployed persons and, for states
  and larger areas, participation and employment-population rates; national Current Population
  Survey annual averages start in 1948.

## Housing

- Building permits are counted by structure size, from 1990 for counties.

## Children and child care

- Child care prices (National Database of Childcare Prices) are by age of child, with the labor
  force rate of mothers of young children; the six-month age bands are not used.
- Licensed child care providers come from Texas (HHSC) and Indiana (FSSA) records: current
  snapshots, with capacity per 100 children under 5. Other states have no capacity values.

## Education

- NCES public schools cover school years 2017-18 through 2024-25: schools, enrollment, public
  pre-K, teacher full-time equivalents and students per teacher (not class size). Students are
  counted at their school, not their residence. Fully virtual schools count only in state and
  larger totals. A measure needs reporting by at least 95% of schools in each state part;
  eligible totals omit nonreporting schools. Earlier CCD history remains to be implemented.

## Health

- CDC PLACES health measures are model-based estimates from the latest release only (CDC advises
  against comparing releases). They are not age-adjusted, and CDC publishes no state values, so a
  state is the sum of its counties. Kentucky and Pennsylvania lack most measures in the 2025
  release, and the social-needs questions were asked only in some states (not Texas); tables then
  say why no estimate is shown.
- HRSA health professional shortage areas are a daily snapshot.

## Safety, hazards and the environment

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
- Traffic deaths (NHTSA FARS, 1982-2023) are counted where crashes happened. Counties come from
  the crash codes; cities, their county parts and tracts from crash coordinates, which start in
  2001, located in full-resolution 2024 TIGER/Line boundaries (a state-year needs 95% of crashes
  with coordinates). Rates per 100,000 residents use 5-year totals and the ACS 5-year population.
  Connecticut's planning regions are not coded (FARS keeps the former counties).
- Severe weather (NOAA Storm Events, 1950-2025: events, deaths and property damage by year) counts
  what National Weather Service offices recorded, so counts follow reporting practice. Coverage
  widens in 1955 and 1996 (tornadoes only 1950-1954; tornadoes, thunderstorm wind and hail
  1955-1995; all event types from 1996), and the three periods are separate series. Winter, heat
  and flood events are recorded for forecast zones: such an event counts in each county of its zone
  and shares its deaths and damage equally among them, using NWS's current county-zone file. Zones
  were redrawn over the years, so a state has county values in a year only when 95% of its zone
  events match a current zone (about half the states before 2013, about a fifth in 2022-2025). States and
  larger areas need no zones. Damage is a rough estimate in dollars of the event year, shown in
  constant dollars. In an area made of several counties an event of a zone that covers several of them
  counts in each; deaths and damage are shared, so they add up. There are no cities or tracts;
  Connecticut's planning regions have no values.
- The FEMA National Risk Index is used for counties (city reports show their county). Its
  scores rank counties against each other, so they exist only for single counties; expected
  losses add up to states, the nation and combined areas. FEMA's terms require the statement
  printed under each hazard table and chart. Census tracts (a 635 MB national file) are not used.

## Food access

- The USDA Food Environment Atlas publishes county values only (no state or national values and
  no populations behind its rates), so its table shows the county alone and combined areas get
  no value. It still uses Connecticut's former counties, so Connecticut planning regions have no
  Atlas values.
- The USDA Food Access Research Atlas (SRAM 2025, LRAM 2019) is published for tracts; counties
  and larger areas are sums of their tracts. Its Connecticut tracts carry the former counties'
  codes, so planning regions, their tracts and metro areas that include them have no values.

## Civic life and government

- Voter registration and turnout (EAC survey, 2020 and 2024) are totals of election
  jurisdictions: counties, New England towns, Wisconsin municipalities and a few cities that run
  their own elections. Counties split by such a city (Kansas City, Missouri) and Wisconsin and
  Alaska counties have no values; the national value covers the states that reported every
  jurisdiction. Counts by voting method are not used, because they do not add up in some states.
- Government finances (2022 Census of Governments) describe the county government for counties
  and the city's own government for cities, not all local governments in an area. Connecticut
  has no county governments, and consolidated city-counties (Indianapolis, Wyandotte County and
  Kansas City, Kansas) count as cities, so those counties have no county-government values.

## Not built, or built and removed

- Not built: County Health Rankings (their terms need the user's decision), MIT Election Lab
  returns (a guestbook download), HUD homelessness counts (a bot challenge blocks scripted
  downloads), NCES before 2017, NDCP six-month age bands.
- BLS OEWS wages and the Population Estimates by county age, sex and race were built and then
  removed (no report used them); their catalog rows remain as documentation.
