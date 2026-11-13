# Development only: benchmarks, regressions and trees without conflict exposure.
# Run after run_development.R. Model selection and final testing are not frozen.
source("scripts/00_config.R")
library(data.table)

# Install missing tree packages, following the project's first-run convention.
tree_packages <- c("rpart", "ranger")
installed <- vapply(tree_packages, requireNamespace, logical(1), quietly = TRUE)
if (any(!installed)) {
  install.packages(tree_packages[!installed], repos = "https://cloud.r-project.org")
}
installed <- vapply(tree_packages, requireNamespace, logical(1), quietly = TRUE)
if (any(!installed)) stop("Tree package installation incomplete: ",
                          paste(tree_packages[!installed], collapse = ", "))

# 1. Load training and validation observations -----------------------------
development <- as.data.table(
  readRDS(config$paths$model_panel)
)[sample %in% c("training", "validation")]
development <- development[order(country, month_id)]
# Country is nominal, not a numerical rank. Preserve common levels in all windows.
development[, country := factor(country)]
retail_release_lag <- config$analysis$predictor_availability_rules$retail_lag_months
if (is.null(retail_release_lag)) stop("Set retail_lag_months in 00_config.R.")
required <- c("retail_growth", "retail_growth_lag3", "inflation_lag2",
              "unemployment_lag3", "gdp_available")
if (anyNA(development[, required, with = FALSE])) stop("Missing development model values.")
if (anyDuplicated(development[, .(country, month_id)])) stop("Duplicate country-month rows.")
validation_months <- sort(unique(development[sample == "validation", month_id]))
if (length(validation_months) == 0) stop("No validation months found.")

# 2. Two benchmarks, neither of which requires fitted coefficients ----------
benchmark_predictions <- development[sample == "validation", .(
  country, month, actual = retail_growth,
  zero_growth = 0,
  latest_available_growth = retail_growth_lag3
)]
benchmark_predictions <- melt(
  benchmark_predictions,
  id.vars = c("country", "month", "actual"),
  measure.vars = c("zero_growth", "latest_available_growth"),
  variable.name = "model", value.name = "prediction", variable.factor = FALSE
)
benchmark_predictions[, error := actual - prediction]

# 3. Compare shared slopes with country-specific slopes --------------------
# Country-specific slopes are equivalent to separate country OLS regressions.
model_formulas <- list(
  shared_slopes_without_conflict = retail_growth ~ factor(country) +
    retail_growth_lag3 + inflation_lag2 + unemployment_lag3 + gdp_available,
  country_specific_without_conflict = retail_growth ~ factor(country) *
    (retail_growth_lag3 + inflation_lag2 + unemployment_lag3 + gdp_available)
)
regression_results <- list()
training_records <- list()
tree_results <- list()
tree_records <- list()
tree_predictors <- c("country", "retail_growth_lag3", "inflation_lag2",
                     "unemployment_lag3", "gdp_available")
tree_formula <- retail_growth ~ country + retail_growth_lag3 +
  inflation_lag2 + unemployment_lag3 + gdp_available
# Fixed starting settings, not selected optima. Bagging and RF differ only in mtry.
tree_settings <- data.table(
  model = c("tree_without_conflict", "bagging_without_conflict", "forest_without_conflict"),
  trees = c(1L, 500L, 500L),
  max_depth = c(3L, 5L, 5L),
  minimum_leaf_size = c(20L, 20L, 20L),
  mtry = c(NA_integer_, length(tree_predictors), 2L)
)

for (i in 1:length(validation_months)) {
  target_month <- validation_months[i]
  # Under our publication convention, outcomes through t-3 are available.
  # Earlier validation outcomes enter training only once they are eligible.
  available_training <- development[
    month_id <= target_month - retail_release_lag
  ]
  forecast_rows <- development[sample == "validation" & month_id == target_month]
  if (!all(forecast_rows$country %in% available_training$country)) {
    stop("A validation country has no available training history.")
  }
  
  for (j in 1:length(model_formulas)) {
    model_name <- names(model_formulas)[j]
    fit <- lm(model_formulas[[j]], data = available_training, na.action = na.fail)
    if (fit$rank < length(coef(fit))) {
      stop("Unidentified coefficients for ", model_name,
           " at ", forecast_rows$month[1], ". Inspect collinearity.")
    }
    predictions <- forecast_rows[, .(country, month, actual = retail_growth)]
    predictions[, model := model_name]
    predictions[, prediction := as.numeric(predict(fit, newdata = forecast_rows))]
    if (any(!is.finite(predictions$prediction))) stop("Non-finite regression forecasts.")
    predictions[, error := actual - prediction]
    index <- (i - 1) * length(model_formulas) + j
    regression_results[[index]] <- predictions
    training_records[[index]] <- data.table(
      model = model_name,
      target_month = forecast_rows$month[1],
      training_observations = nrow(available_training),
      last_training_month = max(available_training$month),
      coefficients = length(coef(fit))
    )
  }
  
  # Train the three tree methods on exactly the same historical rows.
  for (j in 1:nrow(tree_settings)) {
    settings <- tree_settings[j]
    model_name <- settings$model
    model_seed <- 20564L + i
    if (model_name == "tree_without_conflict") {
      tree_fit <- rpart::rpart(
        tree_formula, data = available_training, method = "anova",
        control = rpart::rpart.control(
          maxdepth = settings$max_depth,
          minsplit = 40L, minbucket = settings$minimum_leaf_size,
          cp = 0.01, xval = 0
        )
      )
      forecast_values <- as.numeric(predict(tree_fit, newdata = forecast_rows))
    } else {
      tree_fit <- ranger::ranger(
        tree_formula, data = available_training,
        num.trees = settings$trees, mtry = settings$mtry,
        min.node.size = 40L, min.bucket = settings$minimum_leaf_size,
        max.depth = settings$max_depth, splitrule = "variance",
        replace = TRUE, sample.fraction = 1,
        respect.unordered.factors = "partition",
        seed = model_seed, num.threads = 1L, oob.error = FALSE
      )
      forecast_values <- as.numeric(
        predict(tree_fit, data = forecast_rows)$predictions
      )
    }
    if (any(!is.finite(forecast_values))) stop("Non-finite tree forecasts: ", model_name)
    predictions <- forecast_rows[, .(country, month, actual = retail_growth)]
    predictions[, model := model_name]
    predictions[, prediction := forecast_values]
    predictions[, error := actual - prediction]
    index <- (i - 1) * nrow(tree_settings) + j
    tree_results[[index]] <- predictions
    tree_records[[index]] <- data.table(
      model = model_name, target_month = forecast_rows$month[1],
      training_observations = nrow(available_training),
      last_training_month = max(available_training$month),
      seed = if (model_name == "tree_without_conflict") NA_integer_ else model_seed
    )
  }
}
regression_predictions <- rbindlist(regression_results)
regression_training_log <- rbindlist(training_records)
tree_predictions <- rbindlist(tree_results)
tree_training_log <- rbindlist(tree_records)
validation_predictions <- rbindlist(
  list(benchmark_predictions, regression_predictions, tree_predictions), use.names = TRUE
)

# 4. Validation accuracy: lower MAE/RMSE is better --------------------------
validation_scores <- validation_predictions[, .(
  observations = .N, MAE = mean(abs(error)), RMSE = sqrt(mean(error^2))
), by = model][order(RMSE)]
validation_country_scores <- validation_predictions[, .(
  observations = .N, MAE = mean(abs(error)), RMSE = sqrt(mean(error^2))
), by = .(model, country)][order(country, RMSE)]
benchmark_scores <- validation_scores[
  model %in% c("zero_growth", "latest_available_growth")
]
benchmark_country_scores <- validation_country_scores[
  model %in% c("zero_growth", "latest_available_growth")
]
print(validation_scores)
print(validation_country_scores)
print(regression_training_log)
print(tree_training_log)
# Each method must predict exactly the same validation observations.
expected_rows <- nrow(development[sample == "validation"])
if (any(validation_scores$observations != expected_rows)) stop("Unequal forecast counts.")
if (anyDuplicated(validation_predictions[, .(model, country, month)])) {
  stop("Duplicate validation forecasts.")
}

# 5. Save development results ---------------------------------------------
dir.create(config$paths$development, recursive = TRUE, showWarnings = FALSE)
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
for (name in names(outputs)) {
  fwrite(outputs[[name]], file.path(config$paths$development, paste0(name, ".csv")))
}
message("Validation complete: seven methods compared without conflict exposure.")

# 6. Add conflict exposure to regression and random forest ------------------

conflict_columns <-
  config$analysis$predictor_specification$conflict_alternatives

common_predictors <- c(
  "country",
  "retail_growth_lag3",
  "inflation_lag2",
  "unemployment_lag3",
  "gdp_available"
)

forest_settings <- tree_settings[
  model == "forest_without_conflict"
]

conflict_results <- list()

for (i in 1:length(validation_months)) {
  
  target_month <- validation_months[i]
  
  available_training <- development[
    month_id <= target_month - retail_release_lag
  ]
  
  forecast_rows <- development[
    sample == "validation" &
      month_id == target_month
  ]
  
  for (j in 1:length(conflict_columns)) {
    
    conflict_measure <- conflict_columns[j]
    
    predictors <- c(
      common_predictors,
      conflict_measure
    )
    
    # Build the same predictor formula for both model families.
    model_formula <- as.formula(
      paste(
        "retail_growth ~",
        paste(predictors, collapse = " + ")
      )
    )
    
    regression_fit <- lm(
      model_formula,
      data = available_training,
      na.action = na.fail
    )
    
    if (regression_fit$rank < length(coef(regression_fit))) {
      stop(
        "Unidentified regression coefficients: ",
        conflict_measure, " at ", forecast_rows$month[1]
      )
    }
    
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
    model_predictions <- list(
      shared_slopes = as.numeric(
        predict(regression_fit, newdata = forecast_rows)
      ),
      forest = as.numeric(
        predict(forest_fit, data = forecast_rows)$predictions
      )
    )
    
    for (family in names(model_predictions)) {
      
      predictions <- forecast_rows[
        , .(
          country,
          month,
          actual = retail_growth
        )
      ]
      
      predictions[
        , model := paste0(family, "_", conflict_measure)
      ]
      
      predictions[, prediction := model_predictions[[family]]]
      
      if (any(!is.finite(predictions$prediction))) {
        stop("Non-finite predictions for: ", family, "_", conflict_measure)
      }
      
      predictions[, error := actual - prediction]
      
      conflict_results[[length(conflict_results) + 1]] <- predictions
    }
  }
}

conflict_predictions <- rbindlist(conflict_results)

# Replace previous runs of these specifications if this block is rerun.
validation_predictions <- rbindlist(
  list(
    validation_predictions[
      !model %in% unique(conflict_predictions$model)
    ],
    conflict_predictions
  ),
  use.names = TRUE
)

validation_scores <- validation_predictions[
  , .(
    observations = .N,
    MAE = mean(abs(error)),
    RMSE = sqrt(mean(error^2))
  ),
  by = model
][order(RMSE)]

validation_country_scores <- validation_predictions[
  , .(
    observations = .N,
    MAE = mean(abs(error)),
    RMSE = sqrt(mean(error^2))
  ),
  by = .(model, country)
][order(country, RMSE)]

# Confirm that each specification predicts the same validation rows.
if (any(validation_scores$observations != expected_rows)) {
  stop("Unequal validation forecast counts.")
}

if (anyDuplicated(
  validation_predictions[, .(model, country, month)]
)) {
  stop("Duplicate validation forecasts.")
}

print(validation_scores)

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

conflict_comparison <- merge(
  conflict_definitions,
  validation_scores,
  by = "model"
)

conflict_comparison <- merge(
  conflict_comparison,
  baseline_scores,
  by = "baseline_model"
)

conflict_comparison[
  , RMSE_improvement_pct :=
    100 * (1 - RMSE / baseline_RMSE)
]

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
fwrite(
  conflict_predictions,
  file.path(config$paths$development, "conflict_predictions.csv")
)

fwrite(
  conflict_comparison,
  file.path(config$paths$development, "conflict_comparison.csv")
)

fwrite(
  validation_predictions,
  file.path(config$paths$development, "validation_predictions.csv")
)

fwrite(
  validation_scores,
  file.path(config$paths$development, "validation_scores.csv")
)

fwrite(
  validation_country_scores,
  file.path(config$paths$development, "validation_country_scores.csv")
)