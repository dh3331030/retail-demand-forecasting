# European retail-growth forecasting

Forecasting monthly growth in the seasonally and calendar adjusted volume of food, beverages and tobacco retail sales in Germany, France, Italy, Poland and Portugal. The project compares simple forecasts, linear regressions and tree ensembles, and asks whether geographically weighted conflict exposure improves predictive accuracy.

The code predicts monthly growth, not retail index levels. This is a retrospective forecasting evaluation, not a causal analysis or a currently deployed forecasting service.

## Quick start

1. Extract the complete project, preserving its directories. Keep all project folders together.
2. Open `Retail_forecasting.Rproj` in RStudio. Alternatively, set R's working directory to the directory containing that file.
3. Keep the supplied raw snapshots and `results/development/frozen_config.rds` in place.
4. Run the following in the R console:

```r
# Rebuild all preparation and modeling datasets from raw inputs.
source("run_development.R")

# Evaluate only the six previously frozen finalists on 2024-2025.
source("run_final_evaluation.R")
```

The commands above rerun the experiment; numerical forest results may differ across environments. They overwrite generated datasets and result CSVs in their established locations. They do not revise the finalist definitions in response to test scores. Keep a backup if you want to compare a reproduction with the submitted outputs.

Do not rerun `03b_freeze_development.R` during normal reproduction. A freeze is already included. That script deliberately stops if the frozen configuration exists.

## Requirements and installation

- R and a working internet connection if required packages are not installed.
- RStudio is recommended, but not required.
- Packages: `data.table`, `readxl`, `rpart`, `ranger`, `ggplot2`. No Python is needed to run the project.
- `00_setup.R` checks/installs `data.table` and `readxl`. Script `03` checks/installs `rpart` and `ranger`. The final evaluation also checks `ranger`.
- Initial installations use `https://cloud.r-project.org`. Some platforms may require their normal R compilation tools if a binary is unavailable.

## Project contents

`Retail_forecasting.Rproj` | RStudio project, with workspace restoration disabled|
`00_setup.R` | Project-location and dependency checks|
`run_development.R` | Runs setup, config, preflight, helpers, preparation, stage 02, validation and reduced-predictor comparisons|
`run_final_evaluation.R` | Checks current/frozen configuration equality, then runs stage 04|
`scripts/00_config.R` | Paths, countries, sample dates, predictors, finalists and protocol|
`scripts/00_preflight.R` | Checks source inventory, sheets, COVID member and annual GED ZIP|
`scripts/01_prepare_helpers.R` | Reusable Excel, event-cleaning and distance functions|
`scripts/01_prepare_data.R` | Imports raw data and prepares the merged panel/conflict files|`scripts/02_construct_model_data.R` | Target, lags, GDP availability, conflict integration,|complete cases
`scripts/03_train_validate.R` | Initial seven methods and eight conflict additions|
`scripts/03a_compare_reduced_predictors.R` | Country mean and ten reduced-predictor specifications|
`scripts/03b_freeze_development.R` | One-time freeze, already executed in the submitted project|
`scripts/04_final_evaluation.R` | Monthly test forecasts for six frozen finalists|
`data/raw/` | Six top-level Excel/ZIP files and UCDP subdirectories|
`data/processed/` | Extracted source data and generated RDS datasets|
`results/development/` | 2023 validation predictions, scores and frozen settings|
`results/final/` | 2024-2025 test predictions, scores and training audit|
`docs/` | Sources, preprocessing, variable definitions and writing outlines|

Run scripts from the project root. Neither filenames nor numeric prefixes execute files automatically.

The two master scripts use `local()`, so intermediate objects need not appear in RStudio's Global Environment. This does not prevent file outputs. To inspect the saved modeling table:

```r
source("scripts/00_config.R")
library(data.table)
model_panel <- as.data.table(readRDS(config$paths$model_panel))
View(model_panel)
```

## Data location and source recovery

All 45 raw inputs are included in the supplied project archive. Use those snapshots for reproduction rather than redownloading the latest series.

- The four modeled Eurostat inputs are retail volume, annual HICP inflation, unemployment and quarterly GDP.
- The Oxford COVID ZIP is imported during preparation, but COVID stringency is excluded from modeling.
- Household consumption is not imported or modeled, but remains one of the six top-level files required by preflight.
- Annual GED 23.1 must be at `data/raw/ucdp/annual/GEDEvent_v23_1.csv.zip`.
- The 38 monthly Candidate CSVs belong in `data/raw/ucdp/candidate/`, with original filenames.

See [DATA_SOURCES.md](docs/DATA_SOURCES.md) for exact source links, export filters, selected sheets, extraction timestamps, version notes and all 38 Candidate downloads. [data_source_register.json](docs/data_source_register.json) adds every required relative path, file size and SHA-256 hash. It also records the inner annual CSV hash because the supplied annual ZIP is repackaged and its ZIP hash may differ from the official distribution.

The January 2024 Candidate CSV is headerless in the supplied snapshot. The code supplies annual GED column names for that file. October 2024 has an additional leading index column; reading required fields by name ignores it. Do not add headers or change files silently and expect the original hashes to match.

The old `ucdp_sheet = "GEDEvent_v26_1"` configuration entry is unused by the current CSV imports. It does not mean version 26.1 was used. Some configuration fields for conversion/missing-value rules remain `NULL`; the implemented rules are documented in [PREPROCESSING.md](docs/PREPROCESSING.md).

## Target, samples and predictor timing

For country i and target month t:

`retail_growth = 100 * log(retail_index[t] / retail_index[t-1])`

The unit is log percentage points. A value of `0.12` is approximately 0.12% growth, not 12%. Forecasts target the next calendar month from the preceding month-end.

| Sample | Nominal period | Usable rows after preprocessing |
|---|---|---:|
| Training | 2015-01 to 2022-12 | 450, from 2015-07 to 2022-12 |
| Validation | 2023-01 to 2023-12 | 60 |
| Testing | 2024-01 to 2025-12 | 120 |

There are 660 original country-month rows and 630 usable modeling rows. The first six months of 2015 for each country are excluded because complete predictors, principally eligible GDP, are unavailable.

| Predictor | Implemented convention |
|---|---|
| Retail growth | `t-3` |
| Annual HICP inflation | `t-2` |
| Unemployment | `t-3` |
| GDP | Latest quarter eligible from quarter-end month + 4 target months |
| Conflict | Events starting in `t-2`; annual GED for training, eligible Candidate releases for validation/testing |

Candidate reference month M is eligible from target month M+2. Event start month and source reference month are stored separately. Within each information set, the latest eligible record per focal country/event ID is selected before reference-period filtering and aggregation.

These are scheduling conventions, not individually reconstructed historical release dates. See [DATA_DICTIONARY.md](docs/DATA_DICTIONARY.md) for every analysis column.

## Model comparisons and monthly refitting

The development exercise compares 26 specifications: two initial benchmarks, two regressions, a tree, bagging, a forest, eight conflict additions, a country-mean benchmark and ten reduced-predictor specifications.

Country is categorical. The shared regression has country intercepts and common slopes. The fully interacted regression allows country-specific intercepts and slopes. Forests can split on country. Conflict alternatives are added individually, not all together.

The finalized test comparison contains:

1. Zero growth, the validation-selected primary method under RMSE.
2. Country historical mean.
3. Shared-slope macro-only regression: country, inflation, unemployment and GDP.
4. Random forest without GDP: country, lagged retail growth, inflation and unemployment.
5. Full random forest without conflict.
6. Full random forest with the 1,000-km weighted-deaths exposure.

All fitted methods refit monthly using outcomes through `target_month_id - 3`. Earlier validation/test outcomes can enter later training windows once eligible. January 2023 uses 440 available training rows through October 2022. January 2024 uses 500 rows through October 2023. These are expanding-window forecasts, not a single fit held fixed for two years.

Random forests use 500 trees, `mtry = 2`, depth 5, node split minimum 40, leaf minimum 20, bootstrap replacement, sample fraction 1, and nominal-factor partitioning. Seeds are `20564 + forecast-month index`; indexing restarts for the test stage. Forests use one thread. The saved training/settings files record these choices.

## Freeze and reproducibility paths

### Reproduce the submitted experiment

Use the Quick start commands. Preserve the included frozen configuration. Script `03a` must follow `03` because it uses objects created by that script. Run it in the same R session, not in a separate process.

### Starting from raw inputs with no frozen file

Use the same fixed configuration and run preparation, `03`, and `03a`. Then run `source("scripts/03b_freeze_development.R")` once before final evaluation. This reconstructs the already specified freeze; it is not a reason to reconsider finalists after seeing test performance.

### Refit final models from the supplied processed data

If the purpose is only to reproduce the six test models and the included `model_panel.rds` is present:

```r
source("run_final_evaluation.R")
```

The master checks that the current configuration equals `results/development/frozen_config.rds`. Changing config causes it to stop. Documentation changes do not affect this guard. Do not overwrite the frozen snapshot merely to suppress a mismatch.

## Expected outputs and reference numbers

| File | Meaning |
|---|---|
| `data/processed/prepared_panel.rds` | 660 merged rows, including source-level annual exposure |
| `data/processed/analysis_panel.rds` | 660 rows with analysis columns and provenance |
| `data/processed/model_panel.rds` | 630 complete rows for the model comparisons |
| `data/processed/model_panel_excluded_rows.rds` | 30 initial rows excluded from modeling |
| `results/development/validation_predictions.csv` | 1,560 forecasts: 26 models x 60 observations |
| `results/development/validation_scores.csv` | Overall validation MAE/RMSE |
| `results/development/frozen_config.rds` | Frozen finalist definitions and evaluation protocol |
| `results/final/test_predictions.csv` | 720 forecasts: six models x 120 observations |
| `results/final/test_scores.csv` | Overall holdout MAE/RMSE and comparison with zero |
| `results/final/test_country_scores.csv` | 24 observations per model/country |
| `results/final/test_year_scores.csv` | 60 observations per model/year |
| `results/final/test_training_log.csv` | Training cutoffs, predictors, sizes and seeds |

Reference overall test results from the current local result files:

| Model | MAE | RMSE |
|---|---:|---:|
| Country mean | 0.9043602 | 1.253043 |
| Macro-only regression | 0.9077705 | 1.256815 |
| Zero growth | 0.9196844 | 1.267812 |
| Forest without conflict | 0.9254848 | 1.276879 |
| Forest with conflict deaths | 0.9280226 | 1.284542 |
| Forest without GDP | 0.9283425 | 1.287888 |

These displayed numbers are rounded. Use the full-precision CSVs for numerical comparisons. MAE and RMSE are both in the target's log-percentage-point units. Positive `RMSE_improvement_vs_zero_pct` means lower RMSE than zero growth.

The local results are the reference for the updated working paper. In 2023 validation the forest without conflict has RMSE 1.3894093950 and the forest without GDP has RMSE 1.3893938752: a 0.001117% reduction, calculated against the forest without conflict. Both round to 1.389 at three decimals. The earlier GitHub results instead show 1.3929844225 and 1.3889601740 (0.288894%); do not mix figures or report text from the two sets.

The saved predictions reproduce their score tables. Two independent runs on this computer produced identical forest predictions to each other, but different forest predictions from the earlier GitHub outputs. The tested environment used R 4.6.1, ranger 0.18.0, data.table 1.18.6.1 and ggplot2 4.0.3 on Windows. The reason for the cross-environment difference is unconfirmed. A fixed seed alone does not establish identical output across environments. Record `sessionInfo()` when refitting, and preserve the supplied predictions and scores before running the pipeline. The frozen configuration and original freeze evidence record the historical model selection.

## Figures and writing deliverables

The analysis scripts export figures to `results/figures/` during their normal stages; see `docs/CHART_GUIDE.html`. Running the master scripts to regenerate figures also refits models and overwrites result tables. Confirm the figures, working paper and presentation all use the same result set. The PowerPoint is held separately by Adina. The working paper PDF must be re-exported after editing the Word document.

## Interpretation and limitations

Country mean is the best-performing prespecified comparator on overall test MAE/RMSE. Zero growth remains the validation-selected primary method. Macro variables do not improve aggregate accuracy over country mean. Weighted conflict deaths do not improve the matched forest overall. Small score differences have not been demonstrated statistically significant, and they do not establish causal economic effects.

The analysis uses revised macroeconomic downloads and finalized annual GED for historical training. Full-2023 validation outcomes were unavailable at the earliest 2024 forecast origins. The holdout is therefore retrospective, with publication-delay conventions rather than exact vintage reconstruction. Annual and Candidate conflict records also differ in revision/completeness. A 24-month test with five related countries is a limited evaluation, not 120 independent economic experiments.

An operational forecast today would require updating all input series, filling the more recent publication gaps, refitting the selected procedure and deciding how to translate growth predictions into index-level forecasts. Current files stop at December 2025 and do not constitute a live forecast.

## Troubleshooting

- **`config` not found:** source `scripts/00_config.R` before reading config paths in the console. Each analysis script should be started from its beginning.
- **No objects in the Environment pane:** expected for the local master runners; inspect saved files or source individual scripts.
- **Missing package:** allow the automatic installation, or run the installation command above. If an installed old `ranger` lacks `min.bucket`, use a compatible current version and record it.
- **Missing source/incorrect count:** preserve all six top-level inputs, the annual ZIP and the 38 exact Candidate filenames. See the source register.
- **Existing freeze error:** keep the submitted freeze and skip `03b` during reproduction.
- **Current/frozen settings mismatch:** restore the submitted config; do not change the snapshot just to proceed.
- **`03a` object not found:** first run `03` in that same R session.
- **Unexpected end of input:** use the full script from the archive, not a truncated preview copy.
- **Different forest results:** check R/package versions, raw hashes, seeds, thread count and model settings before interpreting a score difference.

## Group contributions

Complete [CONTRIBUTIONS_TEMPLATE.md](docs/CONTRIBUTIONS_TEMPLATE.md) with actual names and work before submission. No authorship or task allocation has been inferred. Replace the template title when complete.
