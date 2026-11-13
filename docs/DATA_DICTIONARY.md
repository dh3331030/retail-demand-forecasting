# Analysis panel data dictionary

The 15 columns below are saved in `analysis_panel.rds` and retained in `model_panel.rds`. The former has 660 rows; the latter has 630 complete modeling rows.

| Column | Meaning | Unit / coding | Modeling role |
|---|---|---|---|
| `country` | Focal demand country | Germany, France, Italy, Poland, Portugal | Identifier; categorical predictor where specified |
| `month` | Month being predicted | `YYYY-MM` | Forecast key, not an automatic predictor |
| `month_id` | Consecutive target-month index | `year*12 + month_number` | Calendar ordering and availability cutoffs |
| `sample` | Nominal chronological sample | training / validation / testing | Workflow selection |
| `retail_growth` | 100 times log ratio of current to preceding retail volume index | Log percentage points | Outcome |
| `retail_growth_lag3` | Growth three calendar months before target | Log percentage points | Predictor |
| `inflation_lag2` | Annual HICP inflation two months before target | Percent year-on-year | Predictor |
| `unemployment_lag3` | Unemployment three months before target | Percent of labour force | Predictor |
| `gdp_available` | Monthly-equivalent rate from the latest eligible quarter | Percent monthly-equivalent growth | Predictor |
| `gdp_source_quarter` | Quarter supplying `gdp_available` | `YYYY-Qn` | Provenance only |
| `conflict_500_lag2` | Distance-weighted event count in reference month t-2 | Sum of exp(-km/500) | Conflict alternative |
| `conflict_1000_lag2` | Distance-weighted event count in reference month t-2 | Sum of exp(-km/1000) | Conflict alternative |
| `conflict_2000_lag2` | Distance-weighted event count in reference month t-2 | Sum of exp(-km/2000) | Conflict alternative |
| `conflict_deaths_1000_lag2` | Distance-weighted best death estimates in reference month t-2 | Sum of best*exp(-km/1000) | Conflict alternative |
| `conflict_source` | Source used for the four conflict fields | annual_GED_23.1 / monthly_Candidate; missing for initial unavailable rows | Provenance only |

For small values, one log percentage point approximates a 1% monthly volume change. The GDP predictor uses ordinary compounded percentage growth, not the retail target's log-growth transformation. A five-point inflation value means 5% annual inflation, not 0.05 in the stored column.

`prepared_panel.rds` additionally contains unlagged retail index, inflation, unemployment, reference-month GDP equivalents, COVID stringency and annual conflict measures. Those unlagged fields are not automatically forecast-ready inputs. The annual conflict fields in that preparation table are missing beyond training by design.

Model formulas are explicit. Do not replace them with `retail_growth ~ .`, which would accidentally include sample/provenance identifiers and change the experiment.
