# Called by run_final_evaluation.R after the configuration guard passes.
# Six prespecified finalists; chronological holdout scoring, no model selection.
if (!exists("frozen_config")) stop("Run run_final_evaluation.R, not file 04 alone.")
if (!requireNamespace("ranger", quietly = TRUE)) {
  install.packages("ranger", repos = "https://cloud.r-project.org")
}
if (!requireNamespace("ranger", quietly = TRUE)) stop("ranger installation incomplete.")
library(data.table)

spec <- frozen_config$analysis$model_specifications
protocol <- frozen_config$analysis$evaluation_protocol
selected <- spec$selected_models
supported <- c("zero_growth", "country_mean", "shared_slopes_reduced_macro_only",
               "forest_reduced_without_gdp", "forest_without_conflict",
               "forest_conflict_deaths_1000_lag2")
if (length(selected) != 6 || !setequal(selected, supported)) {
  stop("Frozen finalist list differs from the six supported specifications.")
}
# Zero growth was the RMSE winner in validation; comparators are not reselected here.
primary_model <- "zero_growth"
retail_lag <- protocol$outcome_availability_lag_months
if (length(retail_lag) != 1 || is.na(retail_lag) || retail_lag != 3L) {
  stop("Expected the frozen three-month retail-outcome availability rule.")
}
forest_settings <- spec$forest_settings
all_data <- as.data.table(readRDS(frozen_config$paths$model_panel))
all_data[, country := factor(country)]
all_data <- all_data[order(country, month_id)]
if (anyDuplicated(all_data[, .(country, month_id)])) stop("Duplicate modeling rows.")
required <- c("retail_growth", "retail_growth_lag3", "inflation_lag2",
              "unemployment_lag3", "gdp_available", "conflict_deaths_1000_lag2")
if (anyNA(all_data[, required, with = FALSE])) stop("Missing final-evaluation model values.")
test_rows <- all_data[sample == "testing"]
test_months <- sort(unique(test_rows$month_id))
if (length(test_months) != 24 || nrow(test_rows) != 120) {
  stop("Expected 24 test months and 120 country-month observations.")
}
forest_predictors <- list(
  forest_reduced_without_gdp = c("country", "retail_growth_lag3",
                                 "inflation_lag2", "unemployment_lag3"),
  forest_without_conflict = c("country", "retail_growth_lag3", "inflation_lag2",
                              "unemployment_lag3", "gdp_available"),
  forest_conflict_deaths_1000_lag2 = c("country", "retail_growth_lag3",
    "inflation_lag2", "unemployment_lag3", "gdp_available", "conflict_deaths_1000_lag2")
)
regression_formula <- as.formula(paste(
  "retail_growth ~", paste(spec$macro_regression_predictors, collapse = " + ")
))
prediction_tables <- list()
training_records <- list()

for (i in 1:length(test_months)) {
  target_month <- test_months[i]
  # Earlier test outcomes become training observations only after publication.
  training <- all_data[month_id <= target_month - retail_lag]
  forecast_rows <- test_rows[month_id == target_month]
  if (nrow(forecast_rows) != length(frozen_config$analysis$countries)) {
    stop("Incomplete country coverage for test month ID ", target_month)
  }
  if (!all(forecast_rows$country %in% training$country)) stop("Missing country history.")
  model_seed <- protocol$forest_seed_base + i

  for (j in 1:length(selected)) {
    label <- selected[j]
    coefficients <- NA_integer_
    predictors <- "none"
    if (label == "zero_growth") {
      values <- rep(0, nrow(forecast_rows))
    } else if (label == "country_mean") {
      fit <- lm(retail_growth ~ country, data = training, na.action = na.fail)
      values <- as.numeric(predict(fit, newdata = forecast_rows))
      coefficients <- length(coef(fit))
      predictors <- "country"
    } else if (label == "shared_slopes_reduced_macro_only") {
      fit <- lm(regression_formula, data = training, na.action = na.fail)
      if (fit$rank < length(coef(fit))) stop("Unidentified final regression coefficients.")
      values <- as.numeric(predict(fit, newdata = forecast_rows))
      coefficients <- length(coef(fit))
      predictors <- paste(spec$macro_regression_predictors, collapse = ", ")
    } else {
      inputs <- forest_predictors[[label]]
      formula <- as.formula(paste("retail_growth ~", paste(inputs, collapse = " + ")))
      fit <- ranger::ranger(
        formula, data = training,
        num.trees = forest_settings$num_trees, mtry = forest_settings$mtry,
        min.node.size = forest_settings$min_node_size,
        min.bucket = forest_settings$min_bucket, max.depth = forest_settings$max_depth,
        replace = forest_settings$replace, sample.fraction = forest_settings$sample_fraction,
        splitrule = "variance", respect.unordered.factors = "partition",
        seed = model_seed, num.threads = 1L, oob.error = FALSE
      )
      values <- as.numeric(predict(fit, data = forecast_rows)$predictions)
      predictors <- paste(inputs, collapse = ", ")
    }
    if (length(values) != nrow(forecast_rows) || any(!is.finite(values))) {
      stop("Invalid forecasts for ", label)
    }
    predictions <- forecast_rows[, .(country, month, actual = retail_growth)]
    predictions[, model := label]
    predictions[, prediction := values]
    predictions[, error := actual - prediction]
    predictions[, primary := model == primary_model]
    index <- (i - 1) * length(selected) + j
    prediction_tables[[index]] <- predictions
    training_records[[index]] <- data.table(
      model = label, target_month = forecast_rows$month[1],
      training_observations = if (label == "zero_growth") 0L else nrow(training),
      last_eligible_training_month = max(training$month),
      predictors = predictors, coefficients = coefficients,
      seed = if (label %in% names(forest_predictors)) model_seed else NA_integer_
    )
  }
}
test_predictions <- rbindlist(prediction_tables)
test_training_log <- rbindlist(training_records)
if (anyDuplicated(test_predictions[, .(model, country, month)])) stop("Duplicate test forecasts.")
test_scores <- test_predictions[, .(
  observations = .N, MAE = mean(abs(error)), RMSE = sqrt(mean(error^2))
), by = model][order(RMSE)]
if (any(test_scores$observations != 120)) stop("Unequal test forecast counts.")
zero_rmse <- test_scores[model == "zero_growth", RMSE]
test_scores[, RMSE_improvement_vs_zero_pct := NA_real_]
if (zero_rmse > 0) {
  test_scores[, RMSE_improvement_vs_zero_pct := 100 * (1 - RMSE / zero_rmse)]
}
test_scores[, primary := model == primary_model]
test_country_scores <- test_predictions[, .(
  observations = .N, MAE = mean(abs(error)), RMSE = sqrt(mean(error^2))
), by = .(model, country)][order(country, RMSE)]
test_predictions[, year := substr(month, 1, 4)]
test_year_scores <- test_predictions[, .(
  observations = .N, MAE = mean(abs(error)), RMSE = sqrt(mean(error^2))
), by = .(model, year)][order(year, RMSE)]

final_path <- frozen_config$paths$final
dir.create(final_path, recursive = TRUE, showWarnings = FALSE)
outputs <- list(test_predictions = test_predictions, test_scores = test_scores,
  test_country_scores = test_country_scores, test_year_scores = test_year_scores,
  test_training_log = test_training_log)
for (name in names(outputs)) fwrite(outputs[[name]], file.path(final_path, paste0(name, ".csv")))
saveRDS(list(config = frozen_config, primary_model = primary_model,
             seed_rule = "forest_seed_base + test-month index (January 2024 = 1)"),
        file.path(final_path, "evaluation_settings.rds"))
print(test_scores)
print(test_country_scores)
print(test_year_scores)
message("Final holdout evaluation complete. These scores do not select or retune models.")
