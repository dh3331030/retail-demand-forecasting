# Preprocessing and forecast construction

This describes the submitted scripts, not a proposed alternative. Run from the project root. The README gives the execution order.

## 1. Eurostat workbook reshaping

`read_eurostat()` reads the designated sheet as text, identifies its `TIME` row, retains the five countries and reference periods, converts values to numeric, and melts the country-by-period export into long form. `:` and blanks become missing values. It requires one row per selected country and unique country-period keys. The embedded metadata identify the precise selection and source vintage in DATA_SOURCES.md.

Retail is food, beverages and tobacco volume, seasonally/calendar adjusted, index 2021=100. Inflation is the annual all-items HICP change, not monthly inflation. Unemployment is the total-sex, total-age percentage of the labour force, seasonally adjusted. GDP is seasonally/calendar adjusted chain-linked volume growth on the previous quarter.

## 2. GDP frequency conversion

For quarterly growth q expressed in percent, define:

`monthly_equivalent = 100 * ((1 + q/100)^(1/3) - 1)`

The conversion assumes an equivalent compounded monthly rate, not three observed monthly GDP changes. Stage 01 repeats it across the quarter's reference months for the preparation panel and also saves `gdp_quarterly.rds`. Stage 02 uses the quarterly table to select the most recent eligible quarter, so the repeated reference-month values are not directly used as contemporaneous forecast inputs.

## 3. COVID

Extract the national compact CSV from the Oxford ZIP, retain the five ISO country codes and `NAT_TOTAL`, and average daily `StringencyIndex_Average` by country/month. The code retains the ordinary `mean()` missing-value behavior. COVID is present in preparation but omitted from `analysis_panel` and all fitted specifications. Coverage stops in 2022, so post-2022 absence is not interpreted as zero restrictions.

Household consumption is a separate annual export present in the raw folder. It is not imported or modeled. Preflight still expects the file.

## 4. Conflict sources and cleaning

The annual ZIP contains GED 23.1, covering events through 2022. Extract it into the processed folder on each preparation run. Keep required fields, convert dates and retain event-start months 2015-01 through 2022-12 for training history.

Read the 38 Candidate monthly files covering November 2022 through December 2025. Preserve filename, source reference month and event start month separately. Supply annual column names for the confirmed headerless January 2024 CSV. A leading index column in October 2024 is ignored by named-column selection.

Both sources require valid event IDs, dates and best death estimates. Reversed dates, negative best deaths, duplicate IDs within one release and out-of-range coordinates cause a stop. Records without coordinates are saved in exclusion RDS files before removal. Zero-death events remain eligible for event counts.

The supplied Candidate files contain 77,952 records before exclusions and no repeated IDs within a release. Two records lack coordinates:

| File | Event ID | Country | Best deaths |
|---|---:|---|---:|
| `GEDEvent_v23_0_5.csv` | 477738 | Mexico | 4 |
| `GEDEvent_v25_0_6.csv` | 581178 | Unspecified | 0 |

After exclusions, the retained 77,950 Candidate release/event records are copied for each of five capitals when calculating exposure. This gives 389,750 weighted rows before stage 02 eligibility selection. Repeated IDs across different source releases are intentionally retained until forecast construction.

## 5. Distance and exposure definitions

Calculate Haversine distance d in kilometres from each event to Berlin, Paris, Rome, Warsaw and Lisbon. Use Earth radius 6,371 km. The hard-coded capital coordinates are modeling anchors, not event locations. Their separate external provenance was not recorded.

| Country | Capital latitude | Capital longitude |
|---|---:|---:|
| Germany | 52.5200 | 13.4050 |
| France | 48.8566 | 2.3522 |
| Italy | 41.9028 | 12.4964 |
| Poland | 52.2297 | 21.0122 |
| Portugal | 38.7223 | -9.1393 |

For decay distance h, event weight is `exp(-d/h)`. Sum weights for event-count exposures with h=500, 1000 or 2000 km. For deaths exposure, sum `best * exp(-d/1000)`.

These are continuous weighted counts, not integer event totals or literal deaths in the focal country. The global event universe includes all retained violence types. Geographic proximity is not a causal identification strategy or a complete measure of economic exposure.

Annual events are aggregated by focal country and event-start month. Candidate weighted rows retain event/release identities for stage 02.

## 6. Retail target and lags

Order every country chronologically and check duplicate country-month keys and missing calendar months. Define `retail_growth = 100 * log(retail_index / previous_month_index)`. January 2015 growth is missing because December 2014 is outside the preparation sample.

Construct retail-growth lag 3, annual inflation lag 2 and unemployment lag 3 within each country. No lag crosses country boundaries. Initial missing values remain missing.

GDP quarter-end month plus four target months is the first eligible forecast month. Q1 ending March is first usable for a July target, forecast at end-June. Carry forward the latest eligible quarter. This is a conservative regular-release convention rather than reconstructed first flash estimates.

## 7. Conflict availability and source integration

A Candidate source reference month M becomes eligible for targets M+2 and later. This is a stated scheduling assumption, not a measured date for every historical release.

For each validation/test target month t:

1. Keep only releases with `available_forecast_month_id <= t`.
2. Sort releases by source month and retain the last record per focal-country/event-ID group.
3. Keep events whose start month equals t-2.
4. Aggregate the four weights by focal country and merge them onto target month t.

For training rows, align the annual monthly measures by shifting the month key forward two months. Populate the same four `_lag2` columns. Label available training values `annual_GED_23.1` and evaluation values `monthly_Candidate`.

Late reports of earlier-starting events are not automatically backfilled into an earlier forecast. The construction measures events starting in the selected reference month as represented by eligible releases, not all violence active at any time in that month.

Before complete-case selection, the annual lag creates ten missing training exposure rows: January-February 2015 for each country. All 180 validation/test country-month rows have Candidate exposure values in the supplied outputs.

## 8. Refined panel

Keep only the target, country/month/sample identifiers, implemented predictors and provenance fields. Complete cases are required across the target, four common numerical predictors and all four conflict alternatives, even for models using smaller subsets. This fixes the common sample for fair comparisons.

Save all 660 selected rows in `analysis_panel.rds`, 630 complete rows in `model_panel.rds`, and 30 excluded January-June 2015 rows in the exclusion file. Evaluation-period missingness causes a stop. Eligible GDP determines the July 2015 usable start.

## 9. Training and scoring

For each validation or test target t, refit on all retained rows with outcome month <= t-3. This allows earlier validation/test outcomes to enter later training windows. Forecast the five countries without using their target outcomes in model fitting. Compute MAE and RMSE from forecast errors, pooled with equal weight per country-month and separately by country/year.

No test score is used to tune parameters in the submitted scripts. Finalist selection used the full retrospective 2023 validation exercise. Revised macro values and annual GED history mean that the exercise does not reconstruct a complete historical real-time information set.
