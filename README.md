# European retail demand forecasting — run from the original datasets

This is the Bocconi 20564 group project's R analysis, packaged **with the 13 original Excel and ZIP data files**. Everything is included under `data/raw/` and the full workflow reads those original files by default. No precomputed input data are required.

## Run the project (RStudio)

1. Extract the entire ZIP to a folder on your computer. **Do not run files from the ZIP preview.**
2. Open **`Retail_forecasting.Rproj`** in RStudio (or Positron with an R project working directory).
3. Run `source("00_setup.R")`. Install any missing packages using the command printed by the setup script.
4. Run `source("run_project.R")`. It reads all 13 original datasets, creates `data/processed/`, refits the forecasting models and creates new `results/` files.
5. Check that `results/run_status.json` shows `"status": "complete"`; open `results/analysis.html` and `results/model_comparison.csv`.

To check the 13 original datasets without running the models, use a terminal. The following commands work from **any** working directory:

```sh
Rscript --vanilla /path/to/project/run_project.R --check
Rscript --vanilla /path/to/project/run_project.R
```

`--check` only confirms that the original datasets exist and are openable. It does not execute the forecasting models. The default command always reads the original Excel and ZIP sources, even when derived files already exist.

## Project structure

- `data/raw/` — **13 real, original datasets** (Excel source workbooks and the Oxford COVID ZIP). Leave their filenames unchanged.
- `data/raw_sources.csv` — filenames used by the importing script. It contains no fingerprints.
- `scripts/00_preflight.R` — checks that original files exist and can be opened.
- `scripts/01_prepare_data.R` — rebuilds every derived input directly from the original Excel and ZIP datasets. The large UCDP workbook is re-read for every full run.
- `scripts/02_forecast.R` — fits ten historical-growth forecasting models on rolling one-month forecast origins.
- `scripts/03_supporting_analysis.R` — constructs economic/context features and matched supporting forecasts.
- `scripts/04_results.R` — generates the HTML report, score tables and figures.
- `tests/check_outputs.R` — checks final row counts, uniqueness, prediction finiteness and forecast timing.
- `evidence/previous_results/` — earlier results retained for reference only. They are not presented as outputs from the new run.
- `results/` — new outputs appear here after the full run.

## Statistical interpretation

The analysis predicts one-month-ahead log growth in the seasonally and calendar-adjusted food, beverage and tobacco retail-volume index for Germany, France, Italy, Poland and Portugal. 2023 is used as a diagnostic period; 2024–2025 is a **previously reviewed retrospective evaluation**, not a pristine held-out test. The supporting regression uses global conflict, not country-specific exposure, and cannot establish causality. The underlying data are historical revised extracts and do not prove real-time release-vintage availability.

## Sharing with teammates and GitHub

Share the **complete ZIP** so every teammate receives the genuine original datasets. The original UCDP Excel workbook is larger than GitHub's 100 MB regular-file limit; GitHub will not accept that single workbook in a normal repository commit. If you keep code on GitHub, distribute the large original file separately through the team's shared drive and copy it into `data/raw/` before running. This ZIP is self-contained for direct exchange.

## Verification status

The original dataset archives and their expected workbook/ZIP members were independently inspected while preparing this package. R and its packages are not available in this preparation environment, so **the complete R pipeline has not been execution-tested here**. `results/run_status.json` starts as `not_run` and reports success or a precise failed stage when run on an R-enabled computer.
