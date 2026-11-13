# Data sources and exact input register

This register describes the files in the submitted archive. Prefer the supplied snapshots for numerical reproduction. Source websites can revise historical data. The accompanying JSON records all 45 raw files, exact relative paths, versions, sizes and SHA-256 hashes.

## Eurostat exports

All modeled series retain Germany, France, Italy, Poland and Portugal. Monthly inputs are selected for 2015-01 to 2025-12; quarterly GDP for 2015-Q1 to 2025-Q4. Sheet names identify actual workbook tabs, not the XML worksheet order.

### Gdp

- File: `data/raw/(new)Gross domestic product (GDP) and main components (output, expenditure and income)(namq_10_gdp__custom_7680558_spreadsheet).xlsx`
- Role: Modeled predictor.
- Dataset: `namq_10_gdp`. Custom extract: `namq_10_gdp__custom_7680558`.
- Original extract: https://ec.europa.eu/eurostat/databrowser/view/namq_10_gdp__custom_7680558/default/table
- Canonical dataset: https://ec.europa.eu/eurostat/databrowser/view/namq_10_gdp/default/table
- Sheet: `Sheet 2`.
- extraction_statement: Data extracted on 08/10/2026 10:24:58 from [ESTAT].
- Last updated: 07/10/2026 23:00.
- Time frequency: Quarterly.
- Unit of measure: Chain linked volumes, percentage change on previous period.
- Seasonal adjustment: Seasonally and calendar adjusted data.
- National accounts indicator (ESA 2010): Gross domestic product at market prices.

### Inflation

- File: `data/raw/Headline inflation.xlsx`
- Role: Modeled predictor.
- Dataset: `prc_hicp_minr`. Custom extract: `prc_hicp_minr__custom_24209958`.
- Original extract: https://ec.europa.eu/eurostat/databrowser/view/prc_hicp_minr__custom_24209958/default/table
- Canonical dataset: https://ec.europa.eu/eurostat/databrowser/view/prc_hicp_minr/default/table
- Sheet: `Sheet 16`.
- extraction_statement: Data extracted on 07/11/2026 21:31:05 from [ESTAT].
- Last updated: 04/11/2026 11:00.
- Time frequency: Monthly.
- Unit of measure: Annual rate of change.
- Classification of individual consumption by purpose (COICOP) - 2018: Total.

### Household Consumption

- File: `data/raw/Household final consumption expenditure.xlsx`
- Role: Present but not imported or modeled.
- Dataset: `nama_10_cp18`. Custom extract: `nama_10_cp18__custom_24209994`.
- Original extract: https://ec.europa.eu/eurostat/databrowser/view/nama_10_cp18__custom_24209994/default/table
- Canonical dataset: https://ec.europa.eu/eurostat/databrowser/view/nama_10_cp18/default/table
- Sheet: `Sheet 1`.
- extraction_statement: Data extracted on 07/11/2026 21:38:01 from [ESTAT].
- Last updated: 06/11/2026 23:00.
- Time frequency: Annual.
- Unit of measure: Chain linked volumes, index 2020=100.
- Classification of individual consumption by purpose (COICOP) - 2018: Total.

### Retail

- File: `data/raw/Retail trade volume of sales - food, beverages and tobacco(sts_trtu_m__custom_22913457_spreadsheet).xlsx`
- Role: Outcome input.
- Dataset: `sts_trtu_m`. Custom extract: `sts_trtu_m__custom_22913457`.
- Original extract: https://ec.europa.eu/eurostat/databrowser/view/sts_trtu_m__custom_22913457/default/table
- Canonical dataset: https://ec.europa.eu/eurostat/databrowser/view/sts_trtu_m/default/table
- Sheet: `Sheet 1`.
- extraction_statement: Data extracted on 25/09/2026 21:53:25 from [ESTAT].
- Last updated: 24/09/2026 11:00.
- Time frequency: Monthly.
- Business trend indicator: Volume of sales.
- Statistical classification of economic activities in the European Community (NACE Rev. 2): Retail sale of food, beverages and tobacco.
- Seasonal adjustment: Seasonally and calendar adjusted data.
- Unit of measure: Index, 2021=100.

### Unemployment

- File: `data/raw/Unemployment.xlsx`
- Role: Modeled predictor.
- Dataset: `une_rt_m`. Custom extract: `une_rt_m__custom_24215081`.
- Original extract: https://ec.europa.eu/eurostat/databrowser/view/une_rt_m__custom_24215081/default/table
- Canonical dataset: https://ec.europa.eu/eurostat/databrowser/view/une_rt_m/default/table
- Sheet: `Sheet 1`.
- extraction_statement: Data extracted on 08/11/2026 17:20:51 from [ESTAT].
- Last updated: 05/11/2026 23:00.
- Time frequency: Monthly.
- Seasonal adjustment: Seasonally adjusted data, not calendar adjusted data.
- Age class: Total.
- Unit of measure: Percentage of population in the labour force.
- Sex: Total.

## Annual UCDP GED

- Use version **23.1**, not the current annual release. Its event history ends in 2022.
- Official archive: https://ucdp.uu.se/downloads/olddw.html
- Official CSV ZIP: https://ucdp.uu.se/downloads/ged/ged231-csv.zip
- Codebook: https://ucdp.uu.se/downloads/ged/ged231.pdf
- Required local path: `data/raw/ucdp/annual/GEDEvent_v23_1.csv.zip`.
- The supplied local ZIP contains `GEDEvent_v23_1.csv`. Extraction occurs in `data/processed/ucdp_annual/`.
- If downloading the official ZIP, rename the ZIP to the required local name. Its container hash may differ from the repackaged local ZIP. Do not compare ZIP hashes as proof of a different data version; the JSON also records the supplied inner CSV hash.
- Credit: Sundberg and Melander (2013), *Introducing the UCDP Georeferenced Event Dataset*, and Högbladh (2023), *UCDP GED Codebook v23.1*.

## Monthly UCDP Candidate

Keep these 38 monthly CSVs in `data/raw/ucdp/candidate/`. Do not substitute cumulative quarterly files or the latest annual GED. All provided files are inventoried below. Only November 2022 through October 2025 are needed as two-month-lag reference periods for the actual 2023-2025 forecasts; November and December 2025 are collected but not used by those forecast origins.

The local January 2024 file has no header. The import intentionally supplies annual GED column names. If a new download includes a header, it must be harmonized with this explicit exception before running unchanged code.

Credit: Hegre et al. (2020), *Introducing the UCDP Candidate Events Dataset*. https://doi.org/10.1177/2053168020935257

| Reference month | Version | Original CSV |
|---|---|---|
| 2022-11 | 22.0.11 | [Download](https://ucdp.uu.se/downloads/candidateged/GEDEvent_v22_0_11.csv) |
| 2022-12 | 22.0.12 | [Download](https://ucdp.uu.se/downloads/candidateged/GEDEvent_v22_0_12.csv) |
| 2023-01 | 23.0.1 | [Download](https://ucdp.uu.se/downloads/candidateged/GEDEvent_v23_0_1.csv) |
| 2023-02 | 23.0.2 | [Download](https://ucdp.uu.se/downloads/candidateged/GEDEvent_v23_0_2.csv) |
| 2023-03 | 23.0.3 | [Download](https://ucdp.uu.se/downloads/candidateged/GEDEvent_v23_0_3.csv) |
| 2023-04 | 23.0.4 | [Download](https://ucdp.uu.se/downloads/candidateged/GEDEvent_v23_0_4.csv) |
| 2023-05 | 23.0.5 | [Download](https://ucdp.uu.se/downloads/candidateged/GEDEvent_v23_0_5.csv) |
| 2023-06 | 23.0.6 | [Download](https://ucdp.uu.se/downloads/candidateged/GEDEvent_v23_0_6.csv) |
| 2023-07 | 23.0.7 | [Download](https://ucdp.uu.se/downloads/candidateged/GEDEvent_v23_0_7.csv) |
| 2023-08 | 23.0.8 | [Download](https://ucdp.uu.se/downloads/candidateged/GEDEvent_v23_0_8.csv) |
| 2023-09 | 23.0.9 | [Download](https://ucdp.uu.se/downloads/candidateged/GEDEvent_v23_0_9.csv) |
| 2023-10 | 23.0.10 | [Download](https://ucdp.uu.se/downloads/candidateged/GEDEvent_v23_0_10.csv) |
| 2023-11 | 23.0.11 | [Download](https://ucdp.uu.se/downloads/candidateged/GEDEvent_v23_0_11.csv) |
| 2023-12 | 23.0.12 | [Download](https://ucdp.uu.se/downloads/candidateged/GEDEvent_v23_0_12.csv) |
| 2024-01 | 24.0.1 | [Download](https://ucdp.uu.se/downloads/candidateged/GEDEvent_v24_0_1.csv) |
| 2024-02 | 24.0.2 | [Download](https://ucdp.uu.se/downloads/candidateged/GEDEvent_v24_0_2.csv) |
| 2024-03 | 24.0.3 | [Download](https://ucdp.uu.se/downloads/candidateged/GEDEvent_v24_0_3.csv) |
| 2024-04 | 24.0.4 | [Download](https://ucdp.uu.se/downloads/candidateged/GEDEvent_v24_0_4.csv) |
| 2024-05 | 24.0.5 | [Download](https://ucdp.uu.se/downloads/candidateged/GEDEvent_v24_0_5.csv) |
| 2024-06 | 24.0.6 | [Download](https://ucdp.uu.se/downloads/candidateged/GEDEvent_v24_0_6.csv) |
| 2024-07 | 24.0.7 | [Download](https://ucdp.uu.se/downloads/candidateged/GEDEvent_v24_0_7.csv) |
| 2024-08 | 24.0.8 | [Download](https://ucdp.uu.se/downloads/candidateged/GEDEvent_v24_0_8.csv) |
| 2024-09 | 24.0.9 | [Download](https://ucdp.uu.se/downloads/candidateged/GEDEvent_v24_0_9.csv) |
| 2024-10 | 24.0.10 | [Download](https://ucdp.uu.se/downloads/candidateged/GEDEvent_v24_0_10.csv) |
| 2024-11 | 24.0.11 | [Download](https://ucdp.uu.se/downloads/candidateged/GEDEvent_v24_0_11.csv) |
| 2024-12 | 24.0.12 | [Download](https://ucdp.uu.se/downloads/candidateged/GEDEvent_v24_0_12.csv) |
| 2025-01 | 25.0.1 | [Download](https://ucdp.uu.se/downloads/candidateged/GEDEvent_v25_0_1.csv) |
| 2025-02 | 25.0.2 | [Download](https://ucdp.uu.se/downloads/candidateged/GEDEvent_v25_0_2.csv) |
| 2025-03 | 25.0.3 | [Download](https://ucdp.uu.se/downloads/candidateged/GEDEvent_v25_0_3.csv) |
| 2025-04 | 25.0.4 | [Download](https://ucdp.uu.se/downloads/candidateged/GEDEvent_v25_0_4.csv) |
| 2025-05 | 25.0.5 | [Download](https://ucdp.uu.se/downloads/candidateged/GEDEvent_v25_0_5.csv) |
| 2025-06 | 25.0.6 | [Download](https://ucdp.uu.se/downloads/candidateged/GEDEvent_v25_0_6.csv) |
| 2025-07 | 25.0.7 | [Download](https://ucdp.uu.se/downloads/candidateged/GEDEvent_v25_0_7.csv) |
| 2025-08 | 25.0.8 | [Download](https://ucdp.uu.se/downloads/candidateged/GEDEvent_v25_0_8.csv) |
| 2025-09 | 25.0.9 | [Download](https://ucdp.uu.se/downloads/candidateged/GEDEvent_v25_0_9.csv) |
| 2025-10 | 25.0.10 | [Download](https://ucdp.uu.se/downloads/candidateged/GEDEvent_v25_0_10.csv) |
| 2025-11 | 25.0.11 | [Download](https://ucdp.uu.se/downloads/candidateged/GEDEvent_v25_0_11.csv) |
| 2025-12 | 25.0.12 | [Download](https://ucdp.uu.se/downloads/candidateged/GEDEvent_v25_0_12.csv) |

Version-specific codebooks: [2022 archive codebook](https://ucdp.uu.se/downloads/candidateged/ucdp-candidate-codebook%201.1.pdf) [2023-2024 archive codebook](https://ucdp.uu.se/downloads/candidateged/ucdp-candidate-codebook1.3.pdf), and [2025 archive codebook](https://ucdp.uu.se/downloads/candidateged/ucdp-candidate-codebook1.4.pdf).

## Oxford COVID-19 Government Response Tracker

- Prepared for exploration, excluded from the final modeling dataset because coverage ends in 2022.
- Official repository: https://github.com/OxCGRT/covid-policy-dataset
- ZIP download: https://github.com/OxCGRT/covid-policy-dataset/archive/refs/heads/main.zip
- Required local filename: `data/raw/Oxford Covid-19 Government Response Tracker (OxCGRT).zip`.
- Required member: `covid-policy-dataset-main/data/OxCGRT_compact_national_v1.csv`.
- Fields: `CountryCode`, `CountryName`, `Jurisdiction`, `Date`, `StringencyIndex_Average`. Keep the five ISO codes and `Jurisdiction == "NAT_TOTAL"`; average stringency by country/month.
- Data cover 2020-2022. Stringency is a 0-100 index, not a measure of policy effectiveness.
- Credit: Hale et al. (2021), *A global panel database of pandemic policies*. https://doi.org/10.1038/s41562-021-01079-8

## Source status and recovery notes

- The six top-level Excel/ZIP inputs include the unused household-consumption workbook. Preflight still expects it even though no model uses it.
- Do not delete unused-but-required files without updating preflight/config together.
- No original UCDP 26.1 workbook is needed by this submitted workflow.
- Eurostat retrieval timestamps are embedded in the supplied files. UCDP and OxCGRT acquisition dates/commit pins were not preserved; no date has been invented.
- Publication rules in the scripts are conservative conventions, not exact release calendars or real-time data vintages.
- The latitude/longitude capital coordinates are hard-coded modeling anchors in file 01; their external provenance was not documented. Treat them as stated project assumptions.
