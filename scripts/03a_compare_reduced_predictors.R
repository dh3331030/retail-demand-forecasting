# READING GUIDE: This is an extension of the development workflow and requires objects
# created by 03_train_validate.R to exist in the same R session.

# Run from the END of 03_train_validate.R, after the existing comparisons.
# Compare a predefined small set; retain identical rows and training cutoffs.
# Define five reduced predictor sets to test whether individual macro variables improve forecasting.
reduced_sets <- list(
  retail_only = "retail_growth_lag3",
  without_inflation = c("retail_growth_lag3", "unemployment_lag3", "gdp_available"),
  without_unemployment = c("retail_growth_lag3", "inflation_lag2", "gdp_available"),
  without_gdp = c("retail_growth_lag3", "inflation_lag2", "unemployment_lag3"),
  macro_only = c("inflation_lag2", "unemployment_lag3", "gdp_available")
)
# Reuse the validated no-conflict random-forest configuration from the preceding script.
forest_settings <- tree_settings[model == "forest_without_conflict"]
# Create a list to accumulate predictions for reduced models.
reduced_results <- list()
# Create a list to accumulate reduced-model training metadata.
reduced_training_records <- list()

# Common prediction format, also used for the country-mean benchmark.
# Define a shared helper that checks forecast validity and formats country-month predictions.
record_reduced_forecast <- function(label, values, rows) {
  # Verify there is exactly one finite numeric forecast per supplied target observation.
  if (length(values) != nrow(rows) || any(!is.finite(values))) {
    # Stop if the forecast vector has the wrong length or invalid values.
    stop("Invalid forecasts for ", label)
  }
  # Construct the country-month table of observed growth for these predictions.
  result <- rows[, .(country, month, actual = retail_growth)]
  # Add the supplied model name to the prediction rows.
  result[, model := label]
  # Coerce and store the forecast vector as numeric values.
  result[, prediction := as.numeric(values)]
  # Compute actual-minus-prediction errors.
  result[, error := actual - prediction]
  # Return the formatted prediction table to the caller.
  result
}

# Move across the validation months in chronological order.
for (i in 1:length(validation_months)) {
  # Choose the target month for the current iteration.
  target_month <- validation_months[i]
  # Use only historical outcomes old enough to satisfy the configured retail release delay.
  available_training <- development[month_id <= target_month - retail_release_lag]
  # Extract the target-month validation observations for prediction.
  forecast_rows <- development[sample == "validation" & month_id == target_month]

  # Country intercepts only: equivalent to each country's available historical mean.
  # Fit country-only OLS, giving each country its available-history mean as a benchmark.
  mean_fit <- lm(retail_growth ~ country, data = available_training, na.action = na.fail)
  # Call the formatting helper on the country-mean forecasts and append the result.
  reduced_results[[length(reduced_results) + 1]] <- record_reduced_forecast(
    "country_mean", predict(mean_fit, newdata = forecast_rows), forecast_rows
  )
  # Record country-mean forecast date, training count, last eligible month and settings.
  reduced_training_records[[length(reduced_training_records) + 1]] <- data.table(
    model = "country_mean", target_month = forecast_rows$month[1],
    training_observations = nrow(available_training),
    last_training_month = max(available_training$month),
    predictors = "country", mtry = NA_integer_, seed = NA_integer_
  )

  # Iterate through the five predefined reduced predictor combinations.
  for (subset_name in names(reduced_sets)) {
    # Add the country categorical variable to the selected numerical predictors.
    predictors <- c("country", reduced_sets[[subset_name]])
    # Build a model formula from that predictor list using `paste()` and `as.formula()`.
    model_formula <- as.formula(paste("retail_growth ~", paste(predictors, collapse = " + ")))
    # Fit a reduced pooled-slope OLS model on the eligible training rows.
    regression_fit <- lm(model_formula, data = available_training, na.action = na.fail)
    # Verify that the reduced regression coefficients can be identified.
    if (regression_fit$rank < length(coef(regression_fit))) {
      # Stop if the current reduced formula produces a rank-deficient regression.
      stop("Unidentified reduced regression: ", subset_name, " at ", forecast_rows$month[1])
    }
    # Keep the existing forest configuration. Only cap mtry if necessary.
    # Limit the number of considered split variables to the predictors actually available.
    used_mtry <- min(forest_settings$mtry, length(predictors))
    # Fit a fixed-parameter random forest using this reduced set and monthly random seed.
    forest_fit <- ranger::ranger(
      model_formula, data = available_training,
      num.trees = forest_settings$trees, mtry = used_mtry,
      min.node.size = 40L, min.bucket = forest_settings$minimum_leaf_size,
      max.depth = forest_settings$max_depth, splitrule = "variance",
      replace = TRUE, sample.fraction = 1,
      respect.unordered.factors = "partition",
      seed = 20564L + i, num.threads = 1L, oob.error = FALSE
    )
    # Collect held-out numeric forecasts from the reduced regression and forest.
    forecasts <- list(
      shared_slopes = as.numeric(predict(regression_fit, newdata = forecast_rows)),
      forest = as.numeric(predict(forest_fit, data = forecast_rows)$predictions)
    )
    # Loop over these two model families to record both types of forecast.
    for (family in names(forecasts)) {
      # Make a unique readable label from the model family and reduced-set name.
      label <- paste0(family, "_reduced_", subset_name)
      # Append this model's forecasts after calling the common validation/formatting helper.
      reduced_results[[length(reduced_results) + 1]] <- record_reduced_forecast(
        label, forecasts[[family]], forecast_rows
      )
      # Record its training cutoff, predictor set and (for forests) mtry and seed.
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
# Row-bind all reduced-model predictions into one table.
reduced_predictions <- rbindlist(reduced_results)
# Row-bind all training records from the reduced experiments.
reduced_training_log <- rbindlist(reduced_training_records)
# Safe to rerun: replace earlier predictions from this module.
# Remove prior runs of these model labels from the combined forecasts before appending fresh results.
validation_predictions <- rbindlist(list(
  validation_predictions[!model %in% unique(reduced_predictions$model)],
  reduced_predictions
), use.names = TRUE)
# Check that model-country-month keys remain unique after replacement.
if (anyDuplicated(validation_predictions[, .(model, country, month)])) {
  # Stop if the combined forecasts contain duplicate keys.
  stop("Duplicate validation forecasts.")
}
# Calculate overall RMSE, MAE and observation counts for every combined validation model.
validation_scores <- validation_predictions[, .(
  observations = .N, MAE = mean(abs(error)), RMSE = sqrt(mean(error^2))
), by = model][order(RMSE)]
# Ensure each model predicted exactly the expected number of observations.
if (any(validation_scores$observations != expected_rows)) stop("Unequal forecast counts.")
# Calculate RMSE and MAE separately by country for the expanded model set.
validation_country_scores <- validation_predictions[, .(
  observations = .N, MAE = mean(abs(error)), RMSE = sqrt(mean(error^2))
), by = .(model, country)][order(country, RMSE)]

#charts
local({
  library(ggplot2)
  pretty_model <- function(x) {
    replacements <- c(country_mean="Country historical mean", zero_growth="Zero growth",
      latest_available_growth="Latest available growth", shared_slopes_reduced_macro_only="Macro-only regression",
      country_specific_without_conflict="Country-specific regression", shared_slopes="Shared-slope regression",
      forest="Random forest", bagging="Bagging", tree="Decision tree", reduced="reduced predictors",
      conflict_deaths="conflict deaths", without_conflict="without conflict", lag2="(2-month lag)",
      `1000`="1,000 km", `2000`="2,000 km", `500`="500 km", gdp="GDP")
    for (key in names(replacements)) x <- gsub(key, replacements[[key]], x, fixed=TRUE)
    gsub("_", " ", x, fixed=TRUE)
  }
  pct_label <- function(x) ifelse(abs(x) < 0.01 & x != 0,
    ifelse(x > 0, "+<0.01%", "-<0.01%"), sprintf("%+.2f%%", x))
  d <- data.table::copy(validation_scores)
  d[, label := pretty_model(model)]
  d[model == "zero_growth", label := paste0(label, " (primary)")]
  d[, label := factor(label, levels = rev(label[order(RMSE)]))]
  d <- data.table::melt(d, id.vars = c("model", "label"),
                        measure.vars = c("RMSE", "MAE"), variable.name = "metric", value.name = "error")
  p <- ggplot(d, aes(error, label)) +
    geom_text(aes(label=sprintf("%.3f", error)), hjust=-0.35, size=2.6) +
    geom_point(aes(shape=model == "zero_growth"), colour = "#075A9C", size = 2.5) + scale_shape_manual(values=c(`FALSE`=16, `TRUE`=18), guide="none") +
    facet_wrap(~metric, nrow = 1) +
    scale_x_continuous(limits = c(0, NA), expand = expansion(mult = c(0, .28))) +
    labs(title = "2023 validation: complete 26-model comparison", x = "Forecast error (log percentage points)", y = NULL,
         caption = "Lower error is better. Primary = zero growth, selected using validation RMSE.")
  p <- p + scale_y_discrete(labels=function(x) vapply(x, function(z) paste(strwrap(z, 27), collapse="\n"), character(1))) + theme_minimal(base_size = 10.5) +
    theme(
          panel.grid.minor = element_blank(), legend.position = "bottom",
          plot.caption = element_text(hjust = 0, size=8), plot.title.position="plot", plot.margin=margin(8,12,8,8), strip.text = element_text(face = "bold"), strip.text.y = element_text(angle=0), plot.title=element_text(size=13, face="bold", colour="#082B50"))
  dir.create("results/figures/development", recursive = TRUE, showWarnings = FALSE)
  # Explicit print displays the figure when sourcing in RStudio.
  if (interactive()) print(p)
  ggsave(paste0("results/figures/development/", "validation_complete_accuracy", ".png"), plot = p,
         width=7, height = 11, dpi = 300, bg = "white")
  ggsave(paste0("results/figures/development/", "validation_complete_accuracy", ".pdf"), plot = p,
         width=7, height = 11, bg = "white")
})

# Compare each reduced regression/forest with its full no-conflict version.
# Map the country-mean benchmark to zero growth and each reduced model to its full no-conflict counterpart.
baseline_map <- data.table(
  model = c("country_mean", paste0("shared_slopes_reduced_", names(reduced_sets)),
            paste0("forest_reduced_", names(reduced_sets))),
  baseline_model = c("zero_growth",
    rep("shared_slopes_without_conflict", length(reduced_sets)),
    rep("forest_without_conflict", length(reduced_sets)))
)
# Extract baseline model names and RMSEs from the overall scores.
baselines <- validation_scores[, .(baseline_model = model, baseline_RMSE = RMSE)]
# Merge reduced-model scores with their comparison baseline mapping.
reduced_comparison <- merge(baseline_map, validation_scores, by = "model")
# Join baseline RMSE into each reduced-model result.
reduced_comparison <- merge(reduced_comparison, baselines, by = "baseline_model")
# Calculate percentage RMSE improvement relative to the corresponding baseline.
reduced_comparison[, RMSE_improvement_pct := 100 * (1 - RMSE / baseline_RMSE)]
# Sort comparisons first by baseline, then by RMSE.
reduced_comparison <- reduced_comparison[order(baseline_model, RMSE)]

#charts
local({
  library(ggplot2)
  pretty_model <- function(x) {
    replacements <- c(country_mean="Country historical mean", zero_growth="Zero growth",
      latest_available_growth="Latest available growth", shared_slopes_reduced_macro_only="Macro-only regression",
      country_specific_without_conflict="Country-specific regression", shared_slopes="Shared-slope regression",
      forest="Random forest", bagging="Bagging", tree="Decision tree", reduced="reduced predictors",
      conflict_deaths="conflict deaths", without_conflict="without conflict", lag2="(2-month lag)",
      `1000`="1,000 km", `2000`="2,000 km", `500`="500 km", gdp="GDP")
    for (key in names(replacements)) x <- gsub(key, replacements[[key]], x, fixed=TRUE)
    gsub("_", " ", x, fixed=TRUE)
  }
  pct_label <- function(x) ifelse(abs(x) < 0.01 & x != 0,
    ifelse(x > 0, "+<0.01%", "-<0.01%"), sprintf("%+.2f%%", x))
  d <- data.table::copy(reduced_comparison)
  d[, label := pretty_model(model)]
  d[, baseline := paste0("Baseline: ", pretty_model(baseline_model))]
  p <- ggplot(d, aes(RMSE_improvement_pct, reorder(label, RMSE_improvement_pct))) +
    geom_text(aes(label=pct_label(RMSE_improvement_pct)), hjust=-0.2, size=2.7) + scale_x_continuous(expand=expansion(mult=c(.1,.35))) +
    geom_vline(xintercept = 0, colour = "grey50", linetype = "dashed") +
    geom_point(colour = "#075A9C", size = 3) +
    facet_wrap(~baseline, ncol=1, scales="free_y", labeller=label_wrap_gen(55)) +
    labs(title = "Do simpler predictor sets improve validation accuracy?", x = "RMSE improvement over named baseline (%)", y = NULL,
         caption = "Positive = lower error; negative = higher error.
Observed differences; no significance test.")
  p <- p + scale_y_discrete(labels=function(x) vapply(x, function(z) paste(strwrap(z, 27), collapse="\n"), character(1))) + theme_minimal(base_size = 10.5) +
    theme(
          panel.grid.minor = element_blank(), legend.position = "bottom",
          plot.caption = element_text(hjust = 0, size=8), plot.title.position="plot", plot.margin=margin(8,12,8,8), strip.text = element_text(face = "bold"), strip.text.y = element_text(angle=0), plot.title=element_text(size=13, face="bold", colour="#082B50"))
  dir.create("results/figures/development", recursive = TRUE, showWarnings = FALSE)
  # Explicit print displays the figure when sourcing in RStudio.
  if (interactive()) print(p)
  ggsave(paste0("results/figures/development/", "validation_reduced_comparison", ".png"), plot = p,
         width=7, height = 8, dpi = 300, bg = "white")
  ggsave(paste0("results/figures/development/", "validation_reduced_comparison", ".pdf"), plot = p,
         width=7, height = 8, bg = "white")
})

# Print the full validation score ranking.
print(validation_scores)
# Print the reduced-versus-full predictor comparisons.
print(reduced_comparison)

# Refresh overall outputs and save the additional module-specific results.
# Collect reduced-model forecasts, training logs and refreshed validation summaries for export.
reduced_outputs <- list(
  reduced_predictions = reduced_predictions, reduced_training_log = reduced_training_log,
  reduced_comparison = reduced_comparison, validation_predictions = validation_predictions,
  validation_scores = validation_scores, validation_country_scores = validation_country_scores
)
# Loop through the named result objects.
for (name in names(reduced_outputs)) {
  # Write each object to its own CSV in the development folder.
  fwrite(reduced_outputs[[name]], file.path(config$paths$development, paste0(name, ".csv")))
}
# Report that reduced-predictor comparisons have completed.
message("Reduced-predictor comparison complete: country mean plus ten fitted specifications.")
