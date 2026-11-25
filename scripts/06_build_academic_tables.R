# Academic tables for the Big Data Group Project
# Open Retail_forecasting.Rproj, then source this file from the project root.
# This script READS saved results. It never fits models or changes model settings.
# Reporting dependencies only; install once if required:
# install.packages(c("flextable", "officer"))

required_packages <- c("flextable", "officer")
for (package in required_packages) {
  if (!requireNamespace(package, quietly = TRUE)) {
    stop("Install the reporting packages first: install.packages(c('flextable', 'officer'))")
  }
}
library(flextable)
library(officer)

out_dir <- file.path("results", "paper_tables")
read_saved <- function(folder, filename) {
  path <- file.path("results", folder, filename)
  if (!file.exists(path)) stop("Missing saved input: ", path,
                               ". Open the project or supplied package folder first.")
  read.csv(path, stringsAsFactors = FALSE, check.names = FALSE)
}
validation <- read_saved("development", "validation_scores.csv")
validation_predictions <- read_saved("development", "validation_predictions.csv")
reduced <- read_saved("development", "reduced_comparison.csv")
conflict <- read_saved("development", "conflict_comparison.csv")
test <- read_saved("final", "test_scores.csv")
test_predictions <- read_saved("final", "test_predictions.csv")
country_scores <- read_saved("final", "test_country_scores.csv")
year_scores <- read_saved("final", "test_year_scores.csv")

# Deliberately do not read frozen_finalists_validation_scores.csv:
# it contains three forest scores from an earlier run.

# Verify the saved summary statistics against the saved predictions.
# These are arithmetic checks only; no models are re-estimated.
verify_scores <- function(predictions, scores, group_cols = "model") {
  if (any(!is.finite(predictions$actual)) ||
      any(!is.finite(predictions$prediction))) stop("Missing or non-finite predictions.")
  if (anyDuplicated(predictions[c("model", "country", "month")])) {
    stop("Duplicate model-country-month predictions.")
  }
  for (i in seq_len(nrow(scores))) {
    keep <- rep(TRUE, nrow(predictions))
    for (key in group_cols) keep <- keep & predictions[[key]] == scores[[key]][i]
    error <- predictions$actual[keep] - predictions$prediction[keep]
    if (length(error) != scores$observations[i] || !length(error)) {
      stop("Forecast-count mismatch for ", scores$model[i])
    }
    if (abs(mean(abs(error)) - scores$MAE[i]) > 1e-10 ||
        abs(sqrt(mean(error^2)) - scores$RMSE[i]) > 1e-10) {
      stop("Saved predictions and scores do not agree for ", scores$model[i])
    }
  }
}
verify_scores(validation_predictions, validation)
verify_scores(test_predictions, test)
verify_scores(test_predictions, country_scores, c("model", "country"))
test_predictions$year <- as.integer(substr(test_predictions$month, 1, 4))
verify_scores(test_predictions, year_scores, c("model", "year"))
stopifnot(nrow(validation) == 26, all(validation$observations == 60),
          nrow(test) == 6, all(test$observations == 120))

model_labels <- c(
  zero_growth = "Zero growth (primary)",
  latest_available_growth = "Latest available growth",
  country_mean = "Country mean",
  shared_slopes_without_conflict = "Shared slopes: full predictors",
  country_specific_without_conflict = "Country-specific slopes",
  tree_without_conflict = "Decision tree",
  bagging_without_conflict = "Bagging",
  forest_without_conflict = "Random forest: no conflict",
  shared_slopes_reduced_macro_only = "Shared slopes: macroeconomic only",
  forest_reduced_without_gdp = "Random forest: without GDP",
  forest_conflict_deaths_1000_lag2 = "Random forest: death-weighted conflict",
  shared_slopes_reduced_retail_only = "Shared slopes: retail only",
  shared_slopes_reduced_without_inflation = "Shared slopes: without inflation",
  shared_slopes_reduced_without_unemployment = "Shared slopes: without unemployment",
  shared_slopes_reduced_without_gdp = "Shared slopes: without GDP",
  shared_slopes_conflict_500_lag2 = "Shared slopes: events, 500 km",
  shared_slopes_conflict_1000_lag2 = "Shared slopes: events, 1,000 km",
  shared_slopes_conflict_2000_lag2 = "Shared slopes: events, 2,000 km",
  shared_slopes_conflict_deaths_1000_lag2 = "Shared slopes: death-weighted conflict",
  forest_reduced_retail_only = "Random forest: retail only",
  forest_reduced_without_inflation = "Random forest: without inflation",
  forest_reduced_without_unemployment = "Random forest: without unemployment",
  forest_reduced_macro_only = "Random forest: macroeconomic only",
  forest_conflict_500_lag2 = "Random forest: events, 500 km",
  forest_conflict_1000_lag2 = "Random forest: events, 1,000 km",
  forest_conflict_2000_lag2 = "Random forest: events, 2,000 km"
)
label_model <- function(x) {
  labels <- unname(model_labels[as.character(x)])
  if (anyNA(labels)) stop("Add a label for: ", paste(x[is.na(labels)], collapse = ", "))
  labels
}
fmt <- function(x, digits = 4) sprintf(paste0("%.", digits, "f"), x)
validation <- validation[order(validation$RMSE), ]
test <- test[order(test$RMSE), ]
zero_rmse <- validation$RMSE[validation$model == "zero_growth"]
stopifnot(length(zero_rmse) == 1, zero_rmse > 0,
          validation$model[1] == "zero_growth")
validation$gain <- 100 * (1 - validation$RMSE / zero_rmse)
test$gain <- 100 * (1 - test$RMSE / test$RMSE[test$model == "zero_growth"])

accuracy_data <- function(x, include_n = FALSE) {
  d <- data.frame(Model = label_model(x$model), check.names = FALSE)
  if (include_n) d$N <- as.character(x$observations)
  d$MAE <- fmt(x$MAE)
  d$RMSE <- fmt(x$RMSE)
  d[["Gain (%)"]] <- fmt(x$gain, 2)
  d
}

tables <- list()
add_table <- function(key, data, bold = list()) {
  tables[[key]] <<- list(data = data, bold = bold)
}

# Table 1: nominal sample partitions, distinct from each monthly fitting window.
add_table("table_1", data.frame(
  Partition = c("Training", "Validation", "Test", "Total"),
  Period = c("Jul 2015–Dec 2022", "Jan–Dec 2023", "Jan 2024–Dec 2025", "Jul 2015–Dec 2025"),
  "Months per country" = c(90, 12, 24, 126),
  Countries = c(5, 5, 5, 5), Observations = c(450, 60, 120, 630),
  check.names = FALSE
))

# Table 2: main comparisons, ranked by unrounded validation RMSE.
main_models <- c(
  "zero_growth", "latest_available_growth", "country_mean",
  "shared_slopes_without_conflict", "country_specific_without_conflict",
  "tree_without_conflict", "bagging_without_conflict", "forest_without_conflict",
  "shared_slopes_reduced_macro_only", "forest_reduced_without_gdp",
  "forest_conflict_deaths_1000_lag2"
)
stopifnot(all(main_models %in% validation$model))
main <- validation[validation$model %in% main_models, ]
add_table("table_2", accuracy_data(main),
          list(c(which.min(main$MAE), 2), c(which.min(main$RMSE), 3)))

# Table 3, Panel A: selected predictor reductions, with extra precision.
selected_reductions <- c("shared_slopes_reduced_macro_only", "forest_reduced_without_gdp")
rr <- reduced[match(selected_reductions, reduced$model), ]
add_table("table_3a", data.frame(
  "Reduced specification" = label_model(rr$model),
  "Baseline RMSE" = fmt(rr$baseline_RMSE, 6),
  "Reduced RMSE" = fmt(rr$RMSE, 6),
  "Gain (%)" = fmt(rr$RMSE_improvement_pct, 4), check.names = FALSE
))

# Table 3, Panel B: matched linear and forest conflict comparisons.
suffix <- c("", "500_lag2", "1000_lag2", "2000_lag2", "deaths_1000_lag2")
panel_b <- data.frame("Conflict exposure" = c(
  "No conflict (baseline)", "Events, 500 km", "Events, 1,000 km",
  "Events, 2,000 km", "Death-weighted, 1,000 km"), check.names = FALSE)
for (family in c("shared_slopes", "forest")) {
  prefix <- if (family == "shared_slopes") "Linear" else "Forest"
  ids <- c(paste0(family, "_without_conflict"),
           paste0(family, "_conflict_", suffix[-1]))
  panel_b[[paste(prefix, "RMSE")]] <- fmt(validation$RMSE[match(ids, validation$model)])
  panel_b[[paste(prefix, "gain (%)")]] <- c(
    "—", fmt(conflict$RMSE_improvement_pct[match(ids[-1], conflict$model)], 2))
}
add_table("table_3b", panel_b)

# Table 4: all prespecified test comparators, with zero growth still primary.
add_table("table_4", accuracy_data(test),
          list(c(which.min(test$MAE), 2), c(which.min(test$RMSE), 3)))

# Table 5: test RMSE by country, ordered as in Table 4.
countries <- c("France", "Germany", "Italy", "Poland", "Portugal")
country_table <- data.frame(Model = label_model(test$model), check.names = FALSE)
bold_country <- list()
for (j in seq_along(countries)) {
  one <- country_scores[country_scores$country == countries[j], ]
  values <- one$RMSE[match(test$model, one$model)]
  country_table[[countries[j]]] <- fmt(values)
  bold_country[[j]] <- c(which.min(values), j + 1)
}
add_table("table_5", country_table, bold_country)

# Appendix: complete comparisons, without repeating the old frozen snapshot.
add_table("table_a1", accuracy_data(validation, include_n = TRUE),
          list(c(which.min(validation$MAE), 3), c(which.min(validation$RMSE), 4)))
rr <- reduced[reduced$baseline_model != "zero_growth", ]
rr <- rr[order(rr$baseline_model, rr$RMSE), ]
add_table("table_a2", data.frame(
  "Reduced specification" = label_model(rr$model),
  "Baseline RMSE" = fmt(rr$baseline_RMSE, 6), "Reduced RMSE" = fmt(rr$RMSE, 6),
  "Gain (%)" = fmt(rr$RMSE_improvement_pct, 4), check.names = FALSE))
cc <- conflict[order(conflict$baseline_model, conflict$RMSE), ]
add_table("table_a3", data.frame(
  "Augmented specification" = label_model(cc$model),
  "Baseline RMSE" = fmt(cc$baseline_RMSE), "Model RMSE" = fmt(cc$RMSE),
  "Gain (%)" = fmt(cc$RMSE_improvement_pct, 2), check.names = FALSE))
cs <- country_scores[order(country_scores$country, country_scores$RMSE), ]
add_table("table_a4", data.frame(
  Country = cs$country, Model = label_model(cs$model), N = as.character(cs$observations),
  MAE = fmt(cs$MAE), RMSE = fmt(cs$RMSE), check.names = FALSE))
ys <- year_scores[order(year_scores$year, year_scores$RMSE), ]
add_table("table_a5", data.frame(
  Year = as.character(ys$year), Model = label_model(ys$model),
  N = as.character(ys$observations), MAE = fmt(ys$MAE), RMSE = fmt(ys$RMSE),
  check.names = FALSE))

# Captions, widths and explanatory notes used by the supplied Word tables.
table_specs <- list(
  table_1 = list(caption = "Table 1. Estimation sample and chronological partitions",
    notes = "Notes: Countries are France, Germany, Italy, Poland and Portugal. Training denotes the nominal chronological partition. Each monthly fit uses the expanding history eligible under the three-month outcome publication rule. Counts follow the balanced monthly panel and configured date boundaries.",
    widths = c(0.9, 1.85, 1.4, 0.75, 1.1)),
  table_2 = list(caption = "Table 2. Validation performance and the selected primary model",
    notes = "Notes: Validation: January–December 2023; five countries; N = 60 forecasts per model. Errors are in log percentage points. Lower MAE and RMSE indicate greater accuracy. Gain = 100 × (1 − model RMSE / zero-growth RMSE); positive values indicate improvement. Primary denotes the model selected by validation RMSE. Bold identifies the lowest displayed MAE and RMSE; rankings use unrounded values.",
    widths = c(3.65, 0.75, 0.75, 0.85)),
  table_3a = list(caption = "Table 3. Predictor reduction and conflict comparisons\nPanel A. Selected predictor reductions",
    notes = "Notes: Validation N = 60 per model. Each reduction is compared with its own full-predictor baseline, retaining country effects. RMSE is shown to six decimals to make the very small forest improvement visible. Gain is computed from unrounded scores.",
    widths = c(3.0, 1.0, 1.0, 1.0)),
  table_3b = list(caption = "Panel B. Conflict exposure additions",
    notes = "Notes: All conflict measures enter with a two-month lag. Gains compare each augmented model with its own no-conflict baseline. Positive values indicate lower RMSE. Linear denotes the shared-slope regression with country intercepts.",
    widths = c(2.1, 1.0, 0.95, 1.0, 0.95)),
  table_4 = list(caption = "Table 4. Overall test performance of the six retained models",
    notes = "Notes: Test: January 2024–December 2025; five countries; N = 120 forecasts per model. Errors are in log percentage points. Lower MAE and RMSE indicate greater accuracy. Gain is the percentage reduction in RMSE relative to zero growth. Primary denotes the validation-selected model. Bold identifies the lowest MAE and RMSE.",
    widths = c(3.65, 0.75, 0.75, 0.85)),
  table_5 = list(caption = "Table 5. Test RMSE by country",
    notes = "Notes: January 2024–December 2025; N = 24 forecasts per country and model. Errors are in log percentage points. Bold identifies the lowest RMSE within each country. Country winners are descriptive comparisons, not models selected after inspecting the test period.",
    widths = c(2.55, 0.65, 0.75, 0.65, 0.7, 0.7)),
  table_a1 = list(caption = "Table A1. Complete validation results",
    notes = "Notes: Validation: January–December 2023; five countries; N = 60 forecasts per model. Errors are in log percentage points. Lower MAE and RMSE indicate greater accuracy. Gain = 100 × (1 − model RMSE / zero-growth RMSE); positive values indicate improvement. Primary denotes the model selected by validation RMSE. Bold identifies the lowest displayed MAE and RMSE; rankings use unrounded values.",
    widths = c(3.4, 0.4, 0.7, 0.7, 0.8)),
  table_a2 = list(caption = "Table A2. Complete predictor-reduction comparisons",
    notes = "Notes: Validation N = 60 per model. Each model is compared with its corresponding full-predictor linear or forest baseline. Country effects are retained. The country-mean comparison is reported in Table A1 rather than classified as predictor reduction.",
    widths = c(3.0, 1.0, 1.0, 1.0)),
  table_a3 = list(caption = "Table A3. Complete conflict-augmentation comparisons",
    notes = "Notes: Validation N = 60 per model. Baselines are the corresponding shared-slope regression and forest without conflict. Positive gain indicates lower RMSE. All conflict predictors enter with a two-month lag.",
    widths = c(3.0, 1.0, 1.0, 1.0)),
  table_a4 = list(caption = "Table A4. Complete test accuracy by country",
    notes = "Notes: Test targets cover January 2024–December 2025. N = 24 forecasts per country and model. Errors are in log percentage points. Rows are ranked by RMSE within each country.",
    widths = c(0.8, 3.4, 0.4, 0.7, 0.7)),
  table_a5 = list(caption = "Table A5. Test accuracy by year",
    notes = "Notes: Each year contains five countries and 12 target months, giving N = 60 forecasts per model. Errors are in log percentage points. Rows are ranked by RMSE within each year.",
    widths = c(0.55, 3.65, 0.4, 0.7, 0.7))
)

# Export native editable Word tables, plus the formatted values as CSVs.
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
doc <- read_docx()
section <- prop_section(
  page_size = page_size(width = 8.5, height = 11),
  page_margins = page_mar(top = .75, bottom = .75, left = 1, right = 1))
for (i in seq_along(tables)) {
  key <- names(tables)[i]
  entry <- tables[[key]]
  spec <- table_specs[[key]]
  if (i > 1 && key != "table_3b") doc <- body_add_break(doc)
  doc <- body_add_fpar(doc, fpar(ftext(spec$caption,
    fp_text(font.family = "Times New Roman", font.size = 11, bold = TRUE))))
  ft <- flextable(entry$data)
  ft <- theme_booktabs(ft, bold_header = TRUE)
  ft <- font(ft, fontname = "Times New Roman", part = "all")
  ft <- fontsize(ft, size = 9, part = "all")
  ft <- padding(ft, padding = 3, part = "all")
  ft <- align(ft, align = "right", part = "all")
  ft <- align(ft, j = 1, align = "left", part = "all")
  if (key %in% c("table_1", "table_a4", "table_a5")) {
    ft <- align(ft, j = 2, align = "left", part = "all")
  }
  ft <- width(ft, j = seq_along(spec$widths), width = spec$widths)
  ft <- set_table_properties(ft, layout = "fixed",
    opts_word = list(split = FALSE, keep_with_next = FALSE, repeat_headers = TRUE))
  for (cell in entry$bold) ft <- bold(ft, i = cell[1], j = cell[2], bold = TRUE)
  doc <- body_add_flextable(doc, ft)
  doc <- body_add_fpar(doc, fpar(ftext(spec$notes,
    fp_text(font.family = "Times New Roman", font.size = 9))))
  write.csv(entry$data, file.path(out_dir, paste0(key, ".csv")), row.names = FALSE)
}
output <- file.path(out_dir, "Academic_tables.docx")
doc <- body_set_default_section(doc, section)
print(doc, target = output)
writeLines(capture.output(sessionInfo()), file.path(out_dir, "table_export_session.txt"))
message("Saved editable Word tables: ", normalizePath(output))
message("No models were rerun. Original scores and frozen settings were not changed.")
