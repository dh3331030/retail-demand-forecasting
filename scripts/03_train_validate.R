# READING GUIDE: Each model is refitted on an expanding history eligible at forecast time.
# `lm()` fits OLS, `rpart::rpart()` a tree, and `ranger::ranger()` a forest/bagging model.

# Development only: benchmarks, regressions and trees without conflict exposure.
# Run after run_development.R. Model selection and final testing are not frozen.
# Load project paths, model specifications and forecast-availability assumptions.
source("scripts/00_config.R")
# Attach `data.table` to manipulate observations and compute evaluation summaries.
library(data.table)

# Install missing tree packages, following the project's first-run convention.
# Declare `rpart` (single decision tree) and `ranger` (bagging/random forests) as dependencies.
tree_packages <- c("rpart", "ranger")
# Check which tree packages are installed without attaching them.
installed <- vapply(tree_packages, requireNamespace, logical(1), quietly = TRUE)
# Enter the installation branch only when one or more tree packages are unavailable.
if (any(!installed)) {
  # Install just the missing packages from CRAN.
  install.packages(tree_packages[!installed], repos = "https://cloud.r-project.org")
}
# Repeat the availability check after installation.
installed <- vapply(tree_packages, requireNamespace, logical(1), quietly = TRUE)
# Stop if any required tree package remains unavailable.
if (any(!installed)) stop("Tree package installation incomplete: ",
                          paste(tree_packages[!installed], collapse = ", "))

# 1. Load training and validation observations -----------------------------
# Load the model-ready panel and retain only training and validation observations, excluding test rows.
development <- as.data.table(
  readRDS(config$paths$model_panel)
)[sample %in% c("training", "validation")]
# Sort the development observations by country and integer month ID.
development <- development[order(country, month_id)]
# Country is nominal, not a numerical rank. Preserve common levels in all windows.
# Encode countries as an unordered categorical predictor, with consistent factor levels.
development[, country := factor(country)]
# Read the assumed delay before retail outcomes can be used for refitting.
retail_release_lag <- config$analysis$predictor_availability_rules$retail_lag_months
# Stop if the required retail release lag was not configured.
if (is.null(retail_release_lag)) stop("Set retail_lag_months in 00_config.R.")
# List all outcome and predictor variables required by the development models.
required <- c("retail_growth", "retail_growth_lag3", "inflation_lag2",
              "unemployment_lag3", "gdp_available")
# Reject missing values in development model variables.
if (anyNA(development[, required, with = FALSE])) stop("Missing development model values.")
# Reject duplicate country-month modelling rows.
if (anyDuplicated(development[, .(country, month_id)])) stop("Duplicate country-month rows.")
# Find the ordered set of distinct validation months.
validation_months <- sort(unique(development[sample == "validation", month_id]))
# Stop if no months have been assigned to validation.
if (length(validation_months) == 0) stop("No validation months found.")

# 2. Two benchmarks, neither of which requires fitted coefficients ----------
# Create two no-training baselines: predict zero monthly growth or repeat the latest eligible growth.
benchmark_predictions <- development[sample == "validation", .(
  country, month, actual = retail_growth,
  zero_growth = 0,
  latest_available_growth = retail_growth_lag3
)]
# Reshape the two benchmark columns into one row per model/country/month forecast.
benchmark_predictions <- melt(
  benchmark_predictions,
  id.vars = c("country", "month", "actual"),
  measure.vars = c("zero_growth", "latest_available_growth"),
  variable.name = "model", value.name = "prediction", variable.factor = FALSE
)
# Compute benchmark errors as observed growth minus forecast growth.
benchmark_predictions[, error := actual - prediction]

# 3. Compare shared slopes with country-specific slopes --------------------
# Country-specific slopes are equivalent to separate country OLS regressions.
# Define formulas for pooled macro slopes and for slopes interacting with country.
model_formulas <- list(
  shared_slopes_without_conflict = retail_growth ~ factor(country) +
    retail_growth_lag3 + inflation_lag2 + unemployment_lag3 + gdp_available,
  country_specific_without_conflict = retail_growth ~ factor(country) *
    (retail_growth_lag3 + inflation_lag2 + unemployment_lag3 + gdp_available)
)
# Create a list for pooled and country-interaction regression forecasts.
regression_results <- list()
# Create a list recording how much history each regression fit used.
training_records <- list()
# Create a list for tree, bagging and random-forest predictions.
tree_results <- list()
# Create a list for tree-model training metadata.
tree_records <- list()
# Specify the categorical country field and four numerical covariates for tree models.
tree_predictors <- c("country", "retail_growth_lag3", "inflation_lag2",
                     "unemployment_lag3", "gdp_available")
# Define the common response/predictor formula supplied to all three tree methods.
tree_formula <- retail_growth ~ country + retail_growth_lag3 +
  inflation_lag2 + unemployment_lag3 + gdp_available
# Fixed starting settings, not selected optima. Bagging and RF differ only in mtry.
# Fix each tree model's number of trees, maximum depth, minimum leaf size and split-variable count.
tree_settings <- data.table(
  model = c("tree_without_conflict", "bagging_without_conflict", "forest_without_conflict"),
  trees = c(1L, 500L, 500L),
  max_depth = c(3L, 5L, 5L),
  minimum_leaf_size = c(20L, 20L, 20L),
  mtry = c(NA_integer_, length(tree_predictors), 2L)
)

# Move month by month through the validation holdout.
for (i in 1:length(validation_months)) {
  # Select the current calendar month to predict.
  target_month <- validation_months[i]
  # Under our publication convention, outcomes through t-3 are available.
  # Earlier validation outcomes enter training only once they are eligible.
  # Build an expanding training window ending before the target by the configured release delay.
  available_training <- development[
    month_id <= target_month - retail_release_lag
  ]
  # Select all five countries' target-month validation observations.
  forecast_rows <- development[sample == "validation" & month_id == target_month]
  # Verify that each target country is represented in the eligible training history.
  if (!all(forecast_rows$country %in% available_training$country)) {
    # Stop if a country cannot be predicted from historical observations.
    stop("A validation country has no available training history.")
  }
  
  # Loop over both regression formulas for the same validation month.
  for (j in 1:length(model_formulas)) {
    # Identify the current regression specification by name.
    model_name <- names(model_formulas)[j]
    # Estimate ordinary least squares on the eligible historical rows, failing on missing data.
    fit <- lm(model_formulas[[j]], data = available_training, na.action = na.fail)
    # Check whether the regression design is full rank and its coefficients identifiable.
    if (fit$rank < length(coef(fit))) {
      # Stop if collinearity leaves some regression coefficients unidentified.
      stop("Unidentified coefficients for ", model_name,
           " at ", forecast_rows$month[1], ". Inspect collinearity.")
    }
    # Create a prediction table containing country, month and observed retail growth.
    predictions <- forecast_rows[, .(country, month, actual = retail_growth)]
    # Label predictions with the current regression model name.
    predictions[, model := model_name]
    # Call `predict()` on held-out rows and coerce its output to a numeric prediction column.
    predictions[, prediction := as.numeric(predict(fit, newdata = forecast_rows))]
    # Reject non-finite regression forecasts before scoring.
    if (any(!is.finite(predictions$prediction))) stop("Non-finite regression forecasts.")
    # Compute regression forecast errors (actual minus predicted growth).
    predictions[, error := actual - prediction]
    # Calculate a unique list index for this month-model combination.
    index <- (i - 1) * length(model_formulas) + j
    # Save the regression forecasts at that index.
    regression_results[[index]] <- predictions
    # Record the forecast month, eligible training count, last eligible month and number of coefficients.
    training_records[[index]] <- data.table(
      model = model_name,
      target_month = forecast_rows$month[1],
      training_observations = nrow(available_training),
      last_training_month = max(available_training$month),
      coefficients = length(coef(fit))
    )
  }
  
  # Train the three tree methods on exactly the same historical rows.
  # Loop over the three fixed tree settings for the current target month.
  for (j in 1:nrow(tree_settings)) {
    # Extract the current tree setting row.
    settings <- tree_settings[j]
    # Identify which tree/bagging/forest method is being fitted.
    model_name <- settings$model
    # Create a deterministic monthly random seed.
    model_seed <- 20564L + i
    # Use `rpart` for the single-tree specification.
    if (model_name == "tree_without_conflict") {
      # Fit a regression tree with the fixed depth, split-size, leaf-size and complexity controls.
      tree_fit <- rpart::rpart(
        tree_formula, data = available_training, method = "anova",
        control = rpart::rpart.control(
          maxdepth = settings$max_depth,
          minsplit = 40L, minbucket = settings$minimum_leaf_size,
          cp = 0.01, xval = 0
        )
      )
      # Call the fitted tree's prediction method on target-month observations.
      forecast_values <- as.numeric(predict(tree_fit, newdata = forecast_rows))
    } else {
      # Otherwise fit bagging or a random forest using `ranger` and the stored settings.
      tree_fit <- ranger::ranger(
        tree_formula, data = available_training,
        num.trees = settings$trees, mtry = settings$mtry,
        min.node.size = 40L, min.bucket = settings$minimum_leaf_size,
        max.depth = settings$max_depth, splitrule = "variance",
        replace = TRUE, sample.fraction = 1,
        respect.unordered.factors = "partition",
        seed = model_seed, num.threads = 1L, oob.error = FALSE
      )
      # Call `predict()` for the `ranger` model and extract its numeric predictions.
      forecast_values <- as.numeric(
        predict(tree_fit, data = forecast_rows)$predictions
      )
    }
    # Stop if any tree-model prediction is infinite or missing.
    if (any(!is.finite(forecast_values))) stop("Non-finite tree forecasts: ", model_name)
    # Create target-month rows with observed outcomes for tree-model scoring.
    predictions <- forecast_rows[, .(country, month, actual = retail_growth)]
    # Attach the tree-model name to these rows.
    predictions[, model := model_name]
    # Store the computed tree-model predictions.
    predictions[, prediction := forecast_values]
    # Calculate target-minus-prediction errors.
    predictions[, error := actual - prediction]
    # Compute a distinct list index for this month and tree method.
    index <- (i - 1) * nrow(tree_settings) + j
    # Append this tree method's predictions to the indexed results list.
    tree_results[[index]] <- predictions
    # Log training observations, last eligible month and seed (where relevant).
    tree_records[[index]] <- data.table(
      model = model_name, target_month = forecast_rows$month[1],
      training_observations = nrow(available_training),
      last_training_month = max(available_training$month),
      seed = if (model_name == "tree_without_conflict") NA_integer_ else model_seed
    )
  }
}
# Combine all regression forecast tables into one data table.
regression_predictions <- rbindlist(regression_results)
# Combine the regression training logs.
regression_training_log <- rbindlist(training_records)
# Combine all tree-model forecast tables.
tree_predictions <- rbindlist(tree_results)
# Combine all tree-model training logs.
tree_training_log <- rbindlist(tree_records)
# Stack benchmark, regression and tree predictions under the same column names.
validation_predictions <- rbindlist(
  list(benchmark_predictions, regression_predictions, tree_predictions), use.names = TRUE
)

# 4. Validation accuracy: lower MAE/RMSE is better --------------------------
# Calculate overall model observation counts, MAE and RMSE, sorted by RMSE.
validation_scores <- validation_predictions[, .(
  observations = .N, MAE = mean(abs(error)), RMSE = sqrt(mean(error^2))
), by = model][order(RMSE)]
# Calculate the same metrics for each model within each country.
validation_country_scores <- validation_predictions[, .(
  observations = .N, MAE = mean(abs(error)), RMSE = sqrt(mean(error^2))
), by = .(model, country)][order(country, RMSE)]
# Extract overall results for the two simple benchmarks.
benchmark_scores <- validation_scores[
  model %in% c("zero_growth", "latest_available_growth")
]
# Extract country-level results for the two benchmarks.
benchmark_country_scores <- validation_country_scores[
  model %in% c("zero_growth", "latest_available_growth")
]
# Display all overall validation scores.
print(validation_scores)
# Display country-specific validation scores.
print(validation_country_scores)
# Display the regression expanding-window training log.
print(regression_training_log)
# Display the tree expanding-window training log.
print(tree_training_log)
# Each method must predict exactly the same validation observations.
# Determine the expected country-month count in the validation period.
expected_rows <- nrow(development[sample == "validation"])
# Reject comparisons where some models produced fewer forecasts than others.
if (any(validation_scores$observations != expected_rows)) stop("Unequal forecast counts.")
# Detect duplicate model-country-month forecast keys.
if (anyDuplicated(validation_predictions[, .(model, country, month)])) {
  # Stop if a model has duplicate forecasts for the same country and month.
  stop("Duplicate validation forecasts.")
}

# 5. Save development results ---------------------------------------------
# Create the development output folder, including missing parent directories.
dir.create(config$paths$development, recursive = TRUE, showWarnings = FALSE)
# Collect the first set of benchmark, regression, tree, prediction and score tables for exporting.
outputs <- list(
  benchmark_predictions = benchmark_predictions,
  benchmark_scores = benchmark_scores,
  benchmark_country_scores = benchmark_country_scores,
  regression_predictions = regression_predictions,
  regression_training_log = regression_training_log,
  tree_predictions = tree_predictions,
  tree_training_log = tree_training_log,
  tree_model_settings = tree_settings,
  validation_predictions = validation_predictions,
  validation_scores = validation_scores,
  validation_country_scores = validation_country_scores
)
# Loop over named output objects to save them consistently.
for (name in names(outputs)) {
  # Write each object to its own CSV in the development directory.
  fwrite(outputs[[name]], file.path(config$paths$development, paste0(name, ".csv")))
}
# Report completion of the initial seven-model comparison.
message("Validation complete: seven methods compared without conflict exposure.")

# 6. Add conflict exposure to regression and random forest ------------------

# Retrieve the four alternative conflict predictor names from the configuration.
conflict_columns <-
  config$analysis$predictor_specification$conflict_alternatives

# Define the common country and macro predictors to use alongside each conflict measure.
common_predictors <- c(
  "country",
  "retail_growth_lag3",
  "inflation_lag2",
  "unemployment_lag3",
  "gdp_available"
)

# Select the baseline random-forest settings used in the no-conflict comparison.
forest_settings <- tree_settings[
  model == "forest_without_conflict"
]

# Initialize the list for conflict-augmented model predictions.
conflict_results <- list()

# Iterate over the validation months to preserve chronological forecasts.
for (i in 1:length(validation_months)) {
  
  # Select the current target month.
  target_month <- validation_months[i]
  
  # Rebuild the expanding historical training subset using the retail outcome release lag.
  available_training <- development[
    month_id <= target_month - retail_release_lag
  ]
  
  # Select the matching validation target-month rows.
  forecast_rows <- development[
    sample == "validation" &
      month_id == target_month
  ]
  
  # Loop over each possible conflict-exposure predictor.
  for (j in 1:length(conflict_columns)) {
    
    # Retrieve this iteration's conflict measure name.
    conflict_measure <- conflict_columns[j]
    
    # Combine the common predictors with the selected conflict variable.
    predictors <- c(
      common_predictors,
      conflict_measure
    )
    
    # Build the same predictor formula for both model families.
    # Construct an R formula dynamically from the predictor-name vector.
    model_formula <- as.formula(
      paste(
        "retail_growth ~",
        paste(predictors, collapse = " + ")
      )
    )
    
    # Fit an OLS regression using the conflict-augmented predictor formula.
    regression_fit <- lm(
      model_formula,
      data = available_training,
      na.action = na.fail
    )
    
    # Check that the added conflict predictor has not made the regression rank deficient.
    if (regression_fit$rank < length(coef(regression_fit))) {
      # Stop if any regression coefficients cannot be uniquely estimated.
      stop(
        "Unidentified regression coefficients: ",
        conflict_measure, " at ", forecast_rows$month[1]
      )
    }
    
    # Fit a fixed-parameter `ranger` random forest on exactly the same eligible training rows.
    forest_fit <- ranger::ranger(
      model_formula,
      data = available_training,
      num.trees = forest_settings$trees,
      mtry = forest_settings$mtry,
      min.node.size = 40L,
      min.bucket = forest_settings$minimum_leaf_size,
      max.depth = forest_settings$max_depth,
      splitrule = "variance",
      replace = TRUE,
      sample.fraction = 1,
      respect.unordered.factors = "partition",
      seed = 20564L + i,
      num.threads = 1L,
      oob.error = FALSE
    )
    
    # Collect predictions from both models.
    # Collect numeric predictions from the regression and random forest in a named list.
    model_predictions <- list(
      shared_slopes = as.numeric(
        predict(regression_fit, newdata = forecast_rows)
      ),
      forest = as.numeric(
        predict(forest_fit, data = forecast_rows)$predictions
      )
    )
    
    # Loop over the two model families for this conflict measure.
    for (family in names(model_predictions)) {
      
      # Create observation rows with country, month and actual retail growth.
      predictions <- forecast_rows[
        , .(
          country,
          month,
          actual = retail_growth
        )
      ]
      
      # Build a model label combining the family and the conflict-measure name.
      predictions[
        , model := paste0(family, "_", conflict_measure)
      ]
      
      # Copy the selected family forecasts into the prediction table.
      predictions[, prediction := model_predictions[[family]]]
      
      # Check for missing or infinite forecasts.
      if (any(!is.finite(predictions$prediction))) {
        # Stop and identify the failing family/conflict specification if a forecast is invalid.
        stop("Non-finite predictions for: ", family, "_", conflict_measure)
      }
      
      # Compute forecast errors for this family and conflict measure.
      predictions[, error := actual - prediction]
      
      # Append the completed prediction table to the result list.
      conflict_results[[length(conflict_results) + 1]] <- predictions
    }
  }
}

# Combine all conflict-augmented validation predictions.
conflict_predictions <- rbindlist(conflict_results)

# Replace previous runs of these specifications if this block is rerun.
# Replace matching models' previous forecasts, if any, then append the newly calculated ones.
validation_predictions <- rbindlist(
  list(
    validation_predictions[
      !model %in% unique(conflict_predictions$model)
    ],
    conflict_predictions
  ),
  use.names = TRUE
)

# Recompute model-level MAE and RMSE after adding conflict specifications.
validation_scores <- validation_predictions[
  , .(
    observations = .N,
    MAE = mean(abs(error)),
    RMSE = sqrt(mean(error^2))
  ),
  by = model
][order(RMSE)]

# Recompute country-level MAE and RMSE for the combined specifications.
validation_country_scores <- validation_predictions[
  , .(
    observations = .N,
    MAE = mean(abs(error)),
    RMSE = sqrt(mean(error^2))
  ),
  by = .(model, country)
][order(country, RMSE)]

# Confirm that each specification predicts the same validation rows.
# Check that every model predicted the expected number of validation observations.
if (any(validation_scores$observations != expected_rows)) {
  # Stop if different models have unequal prediction coverage.
  stop("Unequal validation forecast counts.")
}

# Check for duplicate `(model, country, month)` predictions.
if (anyDuplicated(
  validation_predictions[, .(model, country, month)]
)) {
  # Stop if duplicates remain after the replacement step.
  stop("Duplicate validation forecasts.")
}

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
    labs(title = "2023 validation: intermediate model comparison", x = "Forecast error (log percentage points)", y = NULL,
         caption = "Lower error is better. Primary = zero growth, selected using validation RMSE.")
  p <- p + scale_y_discrete(labels=function(x) vapply(x, function(z) paste(strwrap(z, 27), collapse="\n"), character(1))) + theme_minimal(base_size = 10.5) +
    theme(
          panel.grid.minor = element_blank(), legend.position = "bottom",
          plot.caption = element_text(hjust = 0, size=8), plot.title.position="plot", plot.margin=margin(8,12,8,8), strip.text = element_text(face = "bold"), strip.text.y = element_text(angle=0), plot.title=element_text(size=13, face="bold", colour="#082B50"))
  dir.create("results/figures/development", recursive = TRUE, showWarnings = FALSE)
  # Explicit print displays the figure when sourcing in RStudio.
  if (interactive()) print(p)
  ggsave(paste0("results/figures/development/", "validation_intermediate_accuracy", ".png"), plot = p,
         width=7, height = 8, dpi = 300, bg = "white")
  ggsave(paste0("results/figures/development/", "validation_intermediate_accuracy", ".pdf"), plot = p,
         width=7, height = 8, bg = "white")
})

# Display the updated accuracy rankings.
print(validation_scores)

# Create a lookup connecting each conflict model to its no-conflict baseline.
conflict_definitions <- data.table(
  model = c(
    paste0("shared_slopes_", conflict_columns),
    paste0("forest_", conflict_columns)
  ),
  
  baseline_model = rep(
    c(
      "shared_slopes_without_conflict",
      "forest_without_conflict"
    ),
    each = length(conflict_columns)
  ),
  
  conflict_measure = rep(conflict_columns, 2)
)

# Extract baseline RMSE values for the no-conflict regression and forest.
baseline_scores <- validation_scores[
  model %in% c(
    "shared_slopes_without_conflict",
    "forest_without_conflict"
  ),
  .(
    baseline_model = model,
    baseline_RMSE = RMSE
  )
]

# Join each conflict specification to its validation accuracy result by model name.
conflict_comparison <- merge(
  conflict_definitions,
  validation_scores,
  by = "model"
)

# Attach the relevant no-conflict baseline RMSE to each conflict comparison.
conflict_comparison <- merge(
  conflict_comparison,
  baseline_scores,
  by = "baseline_model"
)

# Calculate relative RMSE improvement over baseline; positive means lower error.
conflict_comparison[
  , RMSE_improvement_pct :=
    100 * (1 - RMSE / baseline_RMSE)
]

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
  d <- data.table::copy(conflict_comparison)
  d[, label := pretty_model(model)]
  d[, baseline := paste0("Baseline: ", pretty_model(baseline_model))]
  p <- ggplot(d, aes(RMSE_improvement_pct, reorder(label, RMSE_improvement_pct))) +
    geom_text(aes(label=pct_label(RMSE_improvement_pct)), hjust=-0.2, size=2.7) + scale_x_continuous(expand=expansion(mult=c(.1,.35))) +
    geom_vline(xintercept = 0, colour = "grey50", linetype = "dashed") +
    geom_point(colour = "#075A9C", size = 3) +
    facet_wrap(~baseline, ncol=1, scales="free_y", labeller=label_wrap_gen(55)) +
    labs(title = "Does conflict improve validation accuracy?", x = "RMSE improvement over named baseline (%)", y = NULL,
         caption = "Positive = lower error; negative = higher error.
Observed differences; no significance test.")
  p <- p + scale_y_discrete(labels=function(x) vapply(x, function(z) paste(strwrap(z, 27), collapse="\n"), character(1))) + theme_minimal(base_size = 10.5) +
    theme(
          panel.grid.minor = element_blank(), legend.position = "bottom",
          plot.caption = element_text(hjust = 0, size=8), plot.title.position="plot", plot.margin=margin(8,12,8,8), strip.text = element_text(face = "bold"), strip.text.y = element_text(angle=0), plot.title=element_text(size=13, face="bold", colour="#082B50"))
  dir.create("results/figures/development", recursive = TRUE, showWarnings = FALSE)
  if (interactive()) print(p)
  ggsave(paste0("results/figures/development/", "validation_conflict_comparison", ".png"), plot = p,
         width=7, height = 8, dpi = 300, bg = "white")
  ggsave(paste0("results/figures/development/", "validation_conflict_comparison", ".pdf"), plot = p,
         width=7, height = 8, bg = "white")
})

# Display the conflict-versus-baseline results in a sorted comparison table.
print(
  conflict_comparison[
    order(baseline_model, RMSE),
    .(
      model,
      RMSE,
      baseline_RMSE,
      RMSE_improvement_pct
    )
  ]
)

# Save the additional forecasts and refreshed comparison tables.
# Export the forecasts from conflict-augmented models to CSV.
fwrite(
  conflict_predictions,
  file.path(config$paths$development, "conflict_predictions.csv")
)

# Export their accuracy comparisons against no-conflict models to CSV.
fwrite(
  conflict_comparison,
  file.path(config$paths$development, "conflict_comparison.csv")
)

# Overwrite the combined validation forecasts CSV with all current specifications.
fwrite(
  validation_predictions,
  file.path(config$paths$development, "validation_predictions.csv")
)

# Overwrite the overall validation scores CSV with the updated rankings.
fwrite(
  validation_scores,
  file.path(config$paths$development, "validation_scores.csv")
)

# Overwrite the country-level validation scores CSV with updated scores.
fwrite(
  validation_country_scores,
  file.path(config$paths$development, "validation_country_scores.csv")
)