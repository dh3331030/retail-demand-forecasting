# Run from the END of 03_train_validate.R, after the existing comparisons.
# Compare a predefined small set; retain identical rows and training cutoffs.
reduced_sets <- list(
  retail_only = "retail_growth_lag3",
  without_inflation = c("retail_growth_lag3", "unemployment_lag3", "gdp_available"),
  without_unemployment = c("retail_growth_lag3", "inflation_lag2", "gdp_available"),
  without_gdp = c("retail_growth_lag3", "inflation_lag2", "unemployment_lag3"),
  macro_only = c("inflation_lag2", "unemployment_lag3", "gdp_available")
)
forest_settings <- tree_settings[model == "forest_without_conflict"]
reduced_results <- list()
reduced_training_records <- list()

# Common prediction format, also used for the country-mean benchmark.
record_reduced_forecast <- function(label, values, rows) {
  if (length(values) != nrow(rows) || any(!is.finite(values))) {
    stop("Invalid forecasts for ", label)
  }
  result <- rows[, .(country, month, actual = retail_growth)]
  result[, model := label]
  result[, prediction := as.numeric(values)]
  result[, error := actual - prediction]
  result
}

for (i in 1:length(validation_months)) {
  target_month <- validation_months[i]
  available_training <- development[month_id <= target_month - retail_release_lag]
  forecast_rows <- development[sample == "validation" & month_id == target_month]

  # Country intercepts only: equivalent to each country's available historical mean.
  mean_fit <- lm(retail_growth ~ country, data = available_training, na.action = na.fail)
  reduced_results[[length(reduced_results) + 1]] <- record_reduced_forecast(
    "country_mean", predict(mean_fit, newdata = forecast_rows), forecast_rows
  )
  reduced_training_records[[length(reduced_training_records) + 1]] <- data.table(
    model = "country_mean", target_month = forecast_rows$month[1],
    training_observations = nrow(available_training),
    last_training_month = max(available_training$month),
    predictors = "country", mtry = NA_integer_, seed = NA_integer_
  )

  for (subset_name in names(reduced_sets)) {
    predictors <- c("country", reduced_sets[[subset_name]])
    model_formula <- as.formula(paste("retail_growth ~", paste(predictors, collapse = " + ")))
    regression_fit <- lm(model_formula, data = available_training, na.action = na.fail)
    if (regression_fit$rank < length(coef(regression_fit))) {
      stop("Unidentified reduced regression: ", subset_name, " at ", forecast_rows$month[1])
    }
    # Keep the existing forest configuration. Only cap mtry if necessary.
    used_mtry <- min(forest_settings$mtry, length(predictors))
    forest_fit <- ranger::ranger(
      model_formula, data = available_training,
      num.trees = forest_settings$trees, mtry = used_mtry,
      min.node.size = 40L, min.bucket = forest_settings$minimum_leaf_size,
      max.depth = forest_settings$max_depth, splitrule = "variance",
      replace = TRUE, sample.fraction = 1,
      respect.unordered.factors = "partition",
      seed = 20564L + i, num.threads = 1L, oob.error = FALSE
    )
    forecasts <- list(
      shared_slopes = as.numeric(predict(regression_fit, newdata = forecast_rows)),
      forest = as.numeric(predict(forest_fit, data = forecast_rows)$predictions)
    )
    for (family in names(forecasts)) {
      label <- paste0(family, "_reduced_", subset_name)
      reduced_results[[length(reduced_results) + 1]] <- record_reduced_forecast(
        label, forecasts[[family]], forecast_rows
      )
      reduced_training_records[[length(reduced_training_records) + 1]] <- data.table(
        model = label, target_month = forecast_rows$month[1],
        training_observations = nrow(available_training),
        last_training_month = max(available_training$month),
        predictors = paste(predictors, collapse = ", "),
        mtry = if (family == "forest") used_mtry else NA_integer_,
        seed = if (family == "forest") 20564L + i else NA_integer_
      )
    }
  }
}
reduced_predictions <- rbindlist(reduced_results)
reduced_training_log <- rbindlist(reduced_training_records)
# Safe to rerun: replace earlier predictions from this module.
validation_predictions <- rbindlist(list(
  validation_predictions[!model %in% unique(reduced_predictions$model)],
  reduced_predictions
), use.names = TRUE)
if (anyDuplicated(validation_predictions[, .(model, country, month)])) {
  stop("Duplicate validation forecasts.")
}
validation_scores <- validation_predictions[, .(
  observations = .N, MAE = mean(abs(error)), RMSE = sqrt(mean(error^2))
), by = model][order(RMSE)]
if (any(validation_scores$observations != expected_rows)) stop("Unequal forecast counts.")
validation_country_scores <- validation_predictions[, .(
  observations = .N, MAE = mean(abs(error)), RMSE = sqrt(mean(error^2))
), by = .(model, country)][order(country, RMSE)]

# Compare each reduced regression/forest with its full no-conflict version.
baseline_map <- data.table(
  model = c("country_mean", paste0("shared_slopes_reduced_", names(reduced_sets)),
            paste0("forest_reduced_", names(reduced_sets))),
  baseline_model = c("zero_growth",
    rep("shared_slopes_without_conflict", length(reduced_sets)),
    rep("forest_without_conflict", length(reduced_sets)))
)
baselines <- validation_scores[, .(baseline_model = model, baseline_RMSE = RMSE)]
reduced_comparison <- merge(baseline_map, validation_scores, by = "model")
reduced_comparison <- merge(reduced_comparison, baselines, by = "baseline_model")
reduced_comparison[, RMSE_improvement_pct := 100 * (1 - RMSE / baseline_RMSE)]
reduced_comparison <- reduced_comparison[order(baseline_model, RMSE)]
print(validation_scores)
print(reduced_comparison)

# Refresh overall outputs and save the additional module-specific results.
reduced_outputs <- list(
  reduced_predictions = reduced_predictions, reduced_training_log = reduced_training_log,
  reduced_comparison = reduced_comparison, validation_predictions = validation_predictions,
  validation_scores = validation_scores, validation_country_scores = validation_country_scores
)
for (name in names(reduced_outputs)) {
  fwrite(reduced_outputs[[name]], file.path(config$paths$development, paste0(name, ".csv")))
}
message("Reduced-predictor comparison complete: country mean plus ten fitted specifications.")
