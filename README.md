# European retail demand forecasting

This repository contains a reproducible R workflow for forecasting monthly retail-volume growth in Germany, France, Italy, Poland, and Portugal. It includes the source data, data preparation scripts, forecasting models, validation checks, and generated reports.

## Run the analysis

1. Clone the repository and open `Retail_forecasting.Rproj` in RStudio, or open the project directory in Positron.
2. Run `source("00_setup.R")` and install any missing packages using the command printed by the setup script.
3. Run `source("run_project.R")` to rebuild the processed data, fit the models, and generate the reports.
4. Check that `results/run_status.json` reports `"status": "complete"`. Open `results/analysis.html` and `results/model_comparison.csv` to review the results.

From a terminal, run the workflow from any working directory:

```sh
Rscript --vanilla /path/to/project/run_project.R --check
Rscript --vanilla /path/to/project/run_project.R
```

The `--check` option verifies that the original source files are present and readable without fitting models. A full run always rebuilds derived data from the original source files.

## Data and reproducibility

The original Excel and ZIP datasets are stored in `data/raw/`. Excel and ZIP files are tracked with Git LFS; install Git LFS before cloning so the source files are downloaded rather than their pointer files. The source datasets retain their respective providers' attribution and usage terms.

The large UCDP workbook exceeds GitHub's regular file-size limit and is stored through Git LFS. Downloading the complete data may require additional bandwidth and Git LFS storage.

## Repository structure

- `data/raw/` — original source datasets.
- `data/processed/` — derived datasets created by the workflow.
- `scripts/00_preflight.R` — checks that the original source files are present and readable.
- `scripts/01_prepare_data.R` — rebuilds derived inputs from the original datasets.
- `scripts/02_forecast.R` — fits rolling one-month-ahead forecasting models.
- `scripts/03_supporting_analysis.R` — prepares economic/context features and supporting forecasts.
- `scripts/04_results.R` — generates the HTML report, score tables, and figures.
- `tests/check_outputs.R` — checks forecast counts, uniqueness, finite predictions, and forecast timing.
- `evidence/previous_results/` — earlier results retained for reference.
- `results/` — current analysis outputs.

## Interpretation

The analysis predicts one-month-ahead log growth in the seasonally and calendar-adjusted food, beverage, and tobacco retail-volume index. The 2023 period is diagnostic; 2024–2025 is a retrospective evaluation, not an untouched hold-out. The supporting regression uses global conflict measures and cannot establish causality. The underlying data are revised historical extracts and do not establish real-time data availability.

## Verification

Run `Rscript --vanilla run_project.R` to rebuild the analysis and execute the output checks. The workflow records its status and any failing stage in `results/run_status.json`.
