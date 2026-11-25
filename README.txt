# European retail-growth forecasting

Forecasting monthly growth in the seasonally and calendar adjusted volume of food, beverages and tobacco retail sales in Germany, France, Italy, Poland and Portugal. The project compares simple forecasts, linear regressions and tree ensembles, and asks whether geographically weighted conflict exposure improves predictive accuracy.

The code predicts monthly growth, not retail index levels. This is a retrospective forecasting evaluation, not a causal analysis or a currently deployed forecasting service.

## Inspect the supplied project without refitting

Open `Retail_forecasting.Rproj`. Read the supplied report and presentation export, inspect `results/final/test_scores.csv`, and use the existing figures in `results/figures/`. No pipeline execution is necessary to read the findings.

For a dependency check only, run `source("00_setup.R")`. It does not fit models or write project results; if a dependency cannot be loaded, it attempts installation into the R package library. Do not run the full reproduction commands merely to inspect or edit documents.

## Full reproduction from the supplied raw snapshots

1. Extract the complete project, preserving its directories. Keep all project folders together.
2. Open `Retail_forecasting.Rproj` in RStudio. Alternatively, set R's working directory to the directory containing that file.
3. Keep the supplied raw snapshots and `results/development/frozen_config.rds` in place.
4. Run the following in the R console:

```r
# Rebuild datasets, refit development models, and regenerate validation outputs and figures.
source("run_development.R")

# Evaluate only the six previously frozen finalists on 2024-2025.
source("run_final_evaluation.R")
```

The commands above rerun the experiment; numerical forest results may differ across environments. They overwrite generated datasets, result CSVs, evaluation settings and figures in their established locations. They do not revise the finalist definitions in response to test scores. Keep a backup if you want to compare a reproduction with the submitted outputs.

Do not rerun `03b_freeze_development.R` during normal reproduction. A freeze is already included. That script deliberately stops if the frozen configuration exists.

## Requirements and installation

- R and a working internet connection if required packages are not installed.
- RStudio is recommended, but not required.
- Packages: `data.table`, `readxl`, `rpart`, `ranger`, `ggplot2`. No Python is needed to run the project.
- `00_setup.R` checks that all five required packages (`data.table`, `readxl`, `ggplot2`, `rpart` and `ranger`) can be loaded and attempts installation only for packages that fail that check. Open `Retail_forecasting.Rproj` and run `source("00_setup.R")` to check dependencies. This setup step does not fit models or overwrite result files.
- The two full-reproduction master commands are the full reproduction path: they rerun the experiment and overwrite generated outputs. Do not execute them merely to check documentation or setup edits. Do not upgrade existing packages solely to match the environment recorded below.
- Initial installations use `https://cloud.r-project.org`. Some platforms may require their normal R compilation tools if a binary is unavailable.

## Project contents

- `Retail_forecasting.Rproj`: RStudio project with workspace restoration/saving disabled.
- `00_setup.R`: project-location and dependency checks; no model fitting.
- `run_development.R`: runs setup, configuration, preflight, helpers, raw preparation, target/predictor construction, stage 03 validation and stage 03a reduced comparisons, in that order.
- `run_final_evaluation.R`: runs setup/configuration, checks current versus frozen configuration, and executes stage 04.
- `scripts/00_config.R`: paths, countries, sample dates, predictors, six finalists and evaluation protocol.
- `scripts/00_preflight.R`: checks six top-level inputs, selected Excel sheets, the COVID archive member and the annual GED archive structure. It does not check registry hashes or every Candidate CSV; Candidate file/schema checks occur during preparation.
- `scripts/01_prepare_helpers.R`: Excel, event-cleaning and capital-distance helpers.
- `scripts/01_prepare_data.R`: raw imports, GDP conversion, conflict preparation, merged panel and index-history figure.
- `scripts/02_construct_model_data.R`: growth target, lags, GDP eligibility, annual/Candidate integration, complete cases and growth-history figure.
- `scripts/03_train_validate.R`: seven initial procedures and eight conflict additions, with validation outputs and figures.
- `scripts/03a_compare_reduced_predictors.R`: country mean and ten reduced-predictor specifications; assembles the complete 26-specification validation comparison and related figures.
- `scripts/03b_freeze_development.R`: one-time serialization of the six prespecified finalists and protocol; preserve the supplied freeze during normal reproduction.
- `scripts/04_final_evaluation.R`: monthly test refits, six-finalist forecasts, pooled/country/year scores, training logs and test figures.
- `data/raw/`: six top-level Excel/ZIP files plus annual and monthly UCDP subdirectories.
- `data/processed/`: extracted annual CSV, prepared data, provenance/exclusion records and generated RDS panels.
- `results/development/`: 2023 validation forecasts/scores, training logs, selected settings and historical freeze evidence.
- `results/final/`: 2024-2025 forecasts/scores, training log and `evaluation_settings.rds`.
- `results/figures/`: 23 figures, each supplied as PNG and PDF; see [chart guide](docs/CHART_GUIDE.html).
- `Big Data Working Paper.docx` and `Big Data Working Paper.pdf`: the local editable report and PDF export.
- Presentation files in the project root: see the dated file/status note below; a file prefixed `backup_` is not automatically the final submission copy.
- `docs/`: source descriptions/register, preprocessing, data dictionary, contribution template, chart guide, audit evidence and manual correction guide.
- `index.html`: entry point to the internal submission audit.

Run scripts from the project root. Neither filenames nor numeric prefixes execute files automatically.

The two master scripts use `local()`, so intermediate objects need not appear in RStudio's Global Environment. This does not prevent file outputs. To inspect the saved modeling table:

```r
source("scripts/00_config.R")
library(data.table)
model_panel <- as.data.table(readRDS(config$paths$model_panel))
View(model_panel)
```

## Data location and source recovery

The current local project contains the 45 required raw inputs: six top-level files, one annual GED ZIP and 38 Candidate CSVs. Keep those snapshots and directory names together when packaging the project; this README does not certify the contents of a separately created ZIP. Use the snapshots for reproduction rather than redownloading the latest series.

- The four modeled Eurostat inputs are retail volume, annual HICP inflation, unemployment and quarterly GDP.
- The Oxford COVID ZIP is imported during preparation, but COVID stringency is excluded from modeling.
- Household consumption is not imported or modeled, but remains one of the six top-level files required by preflight.
- Annual GED 23.1 must be at `data/raw/ucdp/annual/GEDEvent_v23_1.csv.zip`.
- The 38 monthly Candidate CSVs belong in `data/raw/ucdp/candidate/`, with original filenames.

See [DATA_SOURCES.md](docs/DATA_SOURCES.md) for exact source links, export filters, selected sheets, extraction timestamps, version notes and all 38 Candidate downloads. [data_source_register.json](docs/data_source_register.json) adds every required relative path, file size and SHA-256 hash. It also records the inner annual CSV hash because the supplied annual ZIP is repackaged and its ZIP hash may differ from the official distribution.

The January 2024 Candidate CSV is headerless in the supplied snapshot. The code supplies annual GED column names for that file. October 2024 has an additional leading index column; reading required fields by name ignores it. Do not add headers or change files silently and expect the original hashes to match.

The 38 Candidate CSV snapshots use Windows CRLF line endings in the local copy. Normalizing CRLF to LF reproduces the registered sizes and SHA-256 values. This is a text line-ending difference; the raw snapshots were not edited for the final report corrections. No raw file or registered hash needs to be rewritten. The normalization is an integrity-comparison convention, not a preprocessing edit. Preflight does not perform this checksum comparison automatically.

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

All 38 Candidate files, November 2022 through December 2025, are imported. Only reference months November 2022 through October 2025 can serve the stated two-month-lag schedule for targets through December 2025; November/December 2025 releases are not eligible for any target in this evaluation.

Candidate reference month M is eligible from target month M+2. Event start month and source reference month are stored separately. Within each information set, the latest eligible record per focal country/event ID is selected before reference-period filtering and aggregation.

The source assignments above describe the nominal sample partitions: annual GED for 2015-2022 rows and Candidate for 2023-2025 rows. Eligible earlier validation/test rows, with their stored predictors, can subsequently enter expanding estimation windows.

GDP is a monthly-equivalent transformation of quarterly growth, not an independently observed monthly GDP series. These are scheduling conventions, not individually reconstructed historical release dates. See [DATA_DICTIONARY.md](docs/DATA_DICTIONARY.md) for every analysis column.

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

Complexity controls are fixed starting settings, not selected optima:

- Single regression tree (`rpart`, method `anova`): maximum depth 3, `minsplit = 40`, `minbucket = 20`, `cp = 0.01`, `xval = 0`. This disables internal tree cross-validation, not the external chronological validation exercise.
- Bagging: 500 trees, all five predictors eligible at each split (`mtry = 5`), maximum depth 5, minimum node size 40 and minimum leaf size 20.
- Forests: 500 trees, `mtry = 2`, maximum depth 5, minimum node size 40 and minimum leaf size 20. The reduced retail-only variant has just country and lagged retail growth, so both are candidates at each split; this variant does not restrict splitting to a strict subset of its two predictors.
- Ranger ensembles use bootstrap replacement, sample fraction 1, variance splitting, nominal-factor partitioning, one thread and no out-of-bag error calculation.
- Monthly ensemble seeds are `20564 + i`, with `i = 1` for January 2023 validation and separately `i = 1` for January 2024 testing. The first seed in each stage is 20565.

Source scripts and frozen configuration contain the full controls. Saved settings/training CSVs record selected settings, training cutoffs, predictors and seeds; they are not a complete substitute for the code.

## Freeze and reproducibility paths

### Reproduce the submitted experiment

Use the two full-reproduction master commands above. Preserve the included frozen configuration. `run_development.R` already executes both 03 and 03a in the same local environment; do not run them again as additional steps.

For advanced manual stage-by-stage work, 03a must follow 03 in the same R environment because it uses objects created by 03. Being in the same R session alone is insufficient: the master runner uses `local()`, so those intermediate objects need not survive after it returns. Do not source 03a alone after the master. Manually executing 03 and 03a also refits models and overwrites development outputs.

### Starting from raw inputs with no frozen file

This route is only for a separate reconstruction copy where `results/development/frozen_config.rds` is absent from the outset. Keep the same prespecified configuration. Never delete the supplied freeze just to use this route.

```r
source("run_development.R")
source("scripts/03b_freeze_development.R")
source("run_final_evaluation.R")
```

The freeze script reloads configuration and reads the saved validation CSV, so it can follow the master without its in-memory model objects. It saves the six models already named in configuration; it does not automatically choose the six best scores. This produces a new supporting score summary from the reconstruction, not byte-for-byte recovery of the original historical forest summary. Do not reconsider finalists after seeing test results.

### Refit final models from the supplied processed data

If the purpose is only to refit the six test procedures, keep `scripts/00_config.R`, `data/processed/model_panel.rds`, `results/development/frozen_config.rds`, the project structure and required packages in place:

```r
source("run_final_evaluation.R")
```

This route does not run raw-data preflight, preparation or development validation. It refits test models and overwrites final CSVs, `evaluation_settings.rds` and final figures.

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
| `results/development/frozen_finalists_validation_scores.csv` | Historical freeze-time score summary, not the current rerun table |
| `results/final/test_predictions.csv` | 720 forecasts: six models x 120 observations |
| `results/final/test_scores.csv` | Overall holdout MAE/RMSE and comparison with zero |
| `results/final/test_country_scores.csv` | 24 observations per model/country |
| `results/final/test_year_scores.csv` | 60 observations per model/year |
| `results/final/test_training_log.csv` | Training cutoffs, predictors, sizes and seeds |
| `results/final/evaluation_settings.rds` | Frozen configuration, primary method and test seed rule |

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

The current saved CSVs are the numerical reference when updating the working paper and presentation. In 2023 validation the forest without conflict has RMSE 1.3894093950 and the forest without GDP has RMSE 1.3893938752: a 0.001117% reduction, calculated against the forest without conflict. Both round to 1.389 at three decimals. The earlier GitHub results instead show 1.3929844225 and 1.3889601740 (0.288894%); do not mix figures or report text from the two sets.

The saved predictions reproduce their score tables. Two independent runs on this computer produced identical forest predictions to each other, but different forest predictions from the earlier GitHub outputs. The reason for the cross-environment difference is unconfirmed. A fixed seed alone does not establish identical output across environments. Record `sessionInfo()` when refitting, and preserve the supplied predictions and scores before running the pipeline.

`results/development/frozen_finalists_validation_scores.csv` preserves historical model-selection evidence. Current `results/development/validation_scores.csv` and `results/final/test_scores.csv` are the numerical references used in the final report, slides and figures. Preserve the frozen configuration and historical score summary.

Submission/reproduction environment checked on 25 November 2026: Windows, R 4.6.1, data.table 1.18.6.1, readxl 1.5.0, ggplot2 4.0.3, rpart 4.1.27 and ranger 0.18.0. This records the checked submission/reproduction environment, not proof of the environment that generated the original historical freeze. If your installed environment differs, record your actual package versions and `sessionInfo()` output; do not force upgrades to match this list.

## Figures, documentation and submission files

The analysis scripts export 23 figure pairs to `results/figures/` (23 PNG and 23 PDF files). Use [CHART_GUIDE.html](docs/CHART_GUIDE.html) to find existing exports. Running masters to regenerate plots also refits models and overwrites generated outputs; reading or inserting the supplied figures requires no rerun.

Local file check on 25 November 2026:

- [Editable report](Big%20Data%20Working%20Paper.docx) and [report PDF](Big%20Data%20Working%20Paper.pdf) are present. Re-export the PDF after any subsequent Word edits and inspect the actual PDF placed in the submission. File presence is not certification that all report corrections are complete.
- Presentation exports found in the root: `backup_Forecasting monthly retail growth in volume of FMCG.pdf`. A `backup_` prefix identifies a recovery copy; confirm and clearly designate the final presentation file before packaging. No assumption is made that the editable deck is available only on another member's computer.
- The contribution statement remains incomplete in the local template. See the contribution section below.
- No correctly named final submission archive was present at this check. Archive assembly, extraction checks, rehearsal and upload are separate completion steps, not established by the existence of this project folder.

Documentation by purpose:

- [DATA_SOURCES.md](docs/DATA_SOURCES.md), [source register](docs/data_source_register.json), [PREPROCESSING.md](docs/PREPROCESSING.md) and [DATA_DICTIONARY.md](docs/DATA_DICTIONARY.md): exact input snapshots, transformations, availability rules and analysis columns.
- [MANUAL_FIX_GUIDE.html](docs/MANUAL_FIX_GUIDE.html): manual report/slide/setup corrections that preserve the experiment. Some steps may already have been completed; check the actual current file.
- [PROJECT_REQUIREMENTS_STATUS.html](docs/PROJECT_REQUIREMENTS_STATUS.html): dated internal adversarial audit and closure checklist. It is not the submitted technical report and does not automatically update when a member edits a file.
- `docs/adversarial-audit/`: dated verification evidence and historical reviewer records. Historical records and `docs/reproducibility_checks.json` retain their original scope/date; do not treat every old status statement or score as current.

The obsolete report outline, which mixed earlier forest scores into a writing plan, has been removed. Use the current result CSVs and the manual guide. Earlier retired run/presentation/reproduction guides are not part of the current run order.

The syllabus specifies a 15-minute presentation, as confirmed by the group. The submission cutoff supplied by David is 26 November 2026 at 16:00 Europe/Berlin. Package the final report PDF, final presentation, all R scripts, data or exact documented recovery sources plus preprocessing, README, frozen configuration and completed contributions as `20564 – Group Project – Group 02.zip`, then upload to the designated Google Drive Group Projects Submission Folder. Exclude internal scratch work, recovery copies, caches and obsolete drafts. Keep the required raw inputs even when a source is excluded from modeling, because the current preparation/preflight expects them.

## Interpretation and limitations

Country mean is the best-performing prespecified comparator on overall test MAE/RMSE. Zero growth wins validation RMSE, not every loss measure: the fatality-conflict forest has validation MAE 1.0208424 versus zero growth 1.0256610, despite worse RMSE. Zero growth remains the validation-selected primary method. On pooled 2024-2025 test MAE/RMSE, the tested macro-only regression does not improve on country mean, and weighted conflict deaths do not improve the matched forest. Small score differences have not been demonstrated statistically significant, and they do not establish causal economic effects.

The analysis uses revised macroeconomic downloads and finalized annual GED for historical training. Full-2023 validation outcomes were unavailable at the earliest 2024 forecast origins. The final evaluation is therefore retrospective, with publication-delay conventions rather than exact vintage reconstruction. Earlier ARIMA-lasso/Laya and TimesFM experiments described in the report also evaluated outcomes overlapping 2024-2025; that prior exploration limits the independence of this test period. Those earlier workflows are not rerun by the current master scripts, and their scores use different information assumptions. Annual and Candidate conflict records also differ in revision/completeness. A 24-month test with five related countries is a limited evaluation, not 120 independent economic experiments.

An operational forecast today would require updating all input series, filling the more recent publication gaps, refitting the selected procedure and deciding how to translate growth predictions into index-level forecasts. Evaluation targets stop at December 2025; the supplied outputs do not constitute a live forecast.

## Troubleshooting

- **`config` not found:** source `scripts/00_config.R` before reading config paths in the console. Each analysis script should be started from its beginning.
- **No objects in the Environment pane:** expected for the local master runners; inspect saved files or source individual scripts.
- **Missing package:** open `Retail_forecasting.Rproj` and run `source("00_setup.R")`; it checks whether all five dependencies can be loaded and attempts installation for any that fail. This does not run the forecasting pipeline. If an installed `ranger` lacks `min.bucket`, record its version and resolve compatibility before a separate reproduction run; preserve submitted outputs and document any environment change.
- **Missing source/incorrect count:** preserve all six top-level inputs, the annual ZIP and the 38 exact Candidate filenames. See the source register.
- **Existing freeze error:** keep the submitted freeze and skip `03b` during reproduction.
- **Current/frozen settings mismatch:** restore the submitted config; do not change the snapshot just to proceed.
- **`03a` object not found:** the development master already runs 03 then 03a in one local environment. For deliberate standalone stages, run 03 then 03a in the same environment; do not source 03a alone after the local master returns.
- **Unexpected end of input:** use the full script from the archive, not a truncated preview copy.
- **Different forest results:** check R/package versions, raw hashes, seeds, thread count and model settings before interpreting a score difference.

## Group contributions

The existing [contribution template](docs/CONTRIBUTIONS_TEMPLATE.md) still contains placeholders and only four example rows, while the group has five members. Create a completed short HTML contribution statement covering all five members’ confirmed work and shared decisions. Different roles according to strengths do not require equal hours, identical tasks or invented percentages. Have everyone confirm the wording, include the finished statement in the ZIP, then remove the unused blank template. Member names on the report cover alone do not satisfy this requirement.
