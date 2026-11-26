#train and validate benchmark, regression and tree-based forecasting models
#run after run_development.R; final testing is handled separately
source("scripts/00_config.R")
library(data.table)

#check and install the rpart and ranger packages if missing
tree_packages <- c("rpart", "ranger")
installed <- vapply(tree_packages, requireNamespace, logical(1), quietly = TRUE)
if (any(!installed)) {
  install.packages(tree_packages[!installed], repos = "https://cloud.r-project.org")
}

#recheck installation and stop if either package remains unavailable
installed <- vapply(tree_packages, requireNamespace, logical(1), quietly = TRUE)
if (any(!installed)) stop("Tree package installation incomplete: ",
                          paste(tree_packages[!installed], collapse = ", "))

# 1. Load training and validation observations -----------------------------
#load complete-case model data and retain training and validation observations
development <- as.data.table(
  readRDS(config$paths$model_panel)
)[sample %in% c("training", "validation")]
#sort development observations by country and month
development <- development[order(country, month_id)]
#treat country as a categorical predictor with consistent factor levels
development[, country := factor(country)]

#retrieve the retail outcome-availability lag from the configuration
retail_release_lag <- config$analysis$predictor_availability_rules$retail_lag_months

#stop if the required availability setting is undefined
if (is.null(retail_release_lag)) stop("Set retail_lag_months in 00_config.R.")

#define the target and common macroeconomic predictors
required <- c("retail_growth", "retail_growth_lag3", "inflation_lag2",
              "unemployment_lag3", "gdp_available")
#stop if any required development variable contains missing values
if (anyNA(development[, required, with = FALSE])) stop("Missing development model values.")
#stop if duplicate country-month observations are found
if (anyDuplicated(development[, .(country, month_id)])) stop("Duplicate country-month rows.")
#extract distinct validation months in chronological order
validation_months <- sort(unique(development[sample == "validation", month_id]))
#stop if the validation sample is empty
if (length(validation_months) == 0) stop("No validation months found.")

# 2. Two benchmarks, neither of which requires fitted coefficients
#predict zero growth or the latest available (t-3) retail growth
benchmark_predictions <- development[sample == "validation", .(
  country, month, actual = retail_growth,
  zero_growth = 0,
  latest_available_growth = retail_growth_lag3
)]

#reshape benchmark forecasts into one row per country-month-model
benchmark_predictions <- melt(
  benchmark_predictions,
  id.vars = c("country", "month", "actual"),
  measure.vars = c("zero_growth", "latest_available_growth"),
  variable.name = "model", value.name = "prediction", variable.factor = FALSE
)

#calculate forecast errors as actual minus predicted growth
benchmark_predictions[, error := actual - prediction]

# 3. Compare shared slopes with country-specific slopes --------------------
#define OLS models with shared slopes or country-specific interactions
#see Technical Report, Section 4.2
model_formulas <- list(
  shared_slopes_without_conflict = retail_growth ~ factor(country) +
    retail_growth_lag3 + inflation_lag2 + unemployment_lag3 + gdp_available,
  country_specific_without_conflict = retail_growth ~ factor(country) *
    (retail_growth_lag3 + inflation_lag2 + unemployment_lag3 + gdp_available)
)
#initialize lists for regression/tree predictions and training logs
regression_results <- list()
training_records <- list()
tree_results <- list()
tree_records <- list()

#define the common predictors used by all three tree-based methods
tree_predictors <- c("country", "retail_growth_lag3", "inflation_lag2",
                     "unemployment_lag3", "gdp_available")

#construct the shared prediction formula for tree-based models
tree_formula <- retail_growth ~ country + retail_growth_lag3 +
  inflation_lag2 + unemployment_lag3 + gdp_available

#define fixed initial settings for tree, bagging and random forest
#bagging uses all predictors at each split; forest uses mtry = 2
tree_settings <- data.table(
  model = c("tree_without_conflict", "bagging_without_conflict", "forest_without_conflict"),
  trees = c(1L, 500L, 500L),
  max_depth = c(3L, 5L, 5L),
  minimum_leaf_size = c(20L, 20L, 20L),
  mtry = c(NA_integer_, length(tree_predictors), 2L)
)

#refit models and generate forecasts separately for each validation month
for (i in 1:length(validation_months)) {
  target_month <- validation_months[i]
  #use outcomes through target month minus the retail publication lag
  available_training <- development[
    month_id <= target_month - retail_release_lag
  ]
  #select the five country observations for the current validation month
  forecast_rows <- development[sample == "validation" & month_id == target_month]
  #stop if any validation country lacks eligible training observations
  if (!all(forecast_rows$country %in% available_training$country)) {
    stop("A validation country has no available training history.")
  }
  
  #fit each regression specification using the current training window
  for (j in 1:length(model_formulas)) {
    model_name <- names(model_formulas)[j]
    #estimate OLS coefficients using the eligible historical observations
    fit <- lm(model_formulas[[j]], data = available_training, na.action = na.fail)
    #stop if the regression design matrix is rank-deficient
    if (fit$rank < length(coef(fit))) {
      stop("Unidentified coefficients for ", model_name,
           " at ", forecast_rows$month[1], ". Inspect collinearity.")
    }
    
    #create forecast records with country, month, actual value and model name
    predictions <- forecast_rows[, .(country, month, actual = retail_growth)]
    #assign the regression model name
    predictions[, model := model_name]
    predictions[, prediction := as.numeric(predict(fit, newdata = forecast_rows))]
    #stop if any regression prediction is non-finite
    if (any(!is.finite(predictions$prediction))) stop("Non-finite regression forecasts.")
    #calculate forecast errors as actual minus predicted growth
    predictions[, error := actual - prediction]
    
    #store the current model-month predictions in the results list
    index <- (i - 1) * length(model_formulas) + j
    regression_results[[index]] <- predictions
    #log the model, forecast month, training window and coefficient count
    training_records[[index]] <- data.table(
      model = model_name,
      target_month = forecast_rows$month[1],
      training_observations = nrow(available_training),
      last_training_month = max(available_training$month),
      coefficients = length(coef(fit))
    )
  }
  
  #fit the three tree-based methods using the same eligible training window
  for (j in 1:nrow(tree_settings)) {
    #retrieve the settings and model name for the current method
    settings <- tree_settings[j]
    model_name <- settings$model
    #set a reproducible seed for the current forecast month
    model_seed <- 20564L + i
    #fit a single regression tree using rpart
    if (model_name == "tree_without_conflict") {
      tree_fit <- rpart::rpart(
        tree_formula, data = available_training, method = "anova",
        control = rpart::rpart.control(
          maxdepth = settings$max_depth,
          minsplit = 40L, minbucket = settings$minimum_leaf_size,
          cp = 0.01, xval = 0
        )
      )
      
      #generate predictions from the fitted decision tree
      forecast_values <- as.numeric(predict(tree_fit, newdata = forecast_rows))
      
    } else {
      #fit bagging or random forest with the corresponding mtry setting
      tree_fit <- ranger::ranger(
        tree_formula, data = available_training,
        num.trees = settings$trees, mtry = settings$mtry,
        min.node.size = 40L, min.bucket = settings$minimum_leaf_size,
        max.depth = settings$max_depth, splitrule = "variance",
        replace = TRUE, sample.fraction = 1,
        respect.unordered.factors = "partition",
        seed = model_seed, num.threads = 1L, oob.error = FALSE
      )
      #generate predictions from the fitted bagging or random-forest model
      forecast_values <- as.numeric(
        predict(tree_fit, data = forecast_rows)$predictions
      )
    }
    #stop if any tree-based prediction is non-finite
    if (any(!is.finite(forecast_values))) stop("Non-finite tree forecasts: ", model_name)
    
    #record actual values, predictions and errors for the current method
    predictions <- forecast_rows[, .(country, month, actual = retail_growth)]
    predictions[, model := model_name]
    predictions[, prediction := forecast_values]
    predictions[, error := actual - prediction]
    
    #store the current model-month forecasts in the tree results list
    index <- (i - 1) * nrow(tree_settings) + j
    
    tree_results[[index]] <- predictions
    #log the training window and random seed for each tree-based model
    tree_records[[index]] <- data.table(
      model = model_name, target_month = forecast_rows$month[1],
      training_observations = nrow(available_training),
      last_training_month = max(available_training$month),
      seed = if (model_name == "tree_without_conflict") NA_integer_ else model_seed
    )
  }
}
#combine monthly regression forecasts and their training logs
regression_predictions <- rbindlist(regression_results)
regression_training_log <- rbindlist(training_records)
#combine monthly tree forecasts and their training logs
tree_predictions <- rbindlist(tree_results)
tree_training_log <- rbindlist(tree_records)
#combine benchmark, regression and tree predictions into one table
validation_predictions <- rbindlist(
  list(benchmark_predictions, regression_predictions, tree_predictions), use.names = TRUE
)

# 4. Validation accuracy: lower MAE/RMSE is better --------------------------
#calculate overall MAE and RMSE for each model, sorted by RMSE
validation_scores <- validation_predictions[, .(
  observations = .N, MAE = mean(abs(error)), RMSE = sqrt(mean(error^2))
), by = model][order(RMSE)]
#calculate MAE and RMSE separately for each model and country
validation_country_scores <- validation_predictions[, .(
  observations = .N, MAE = mean(abs(error)), RMSE = sqrt(mean(error^2))
), by = .(model, country)][order(country, RMSE)]
#extract overall accuracy scores for the two benchmark models
benchmark_scores <- validation_scores[
  model %in% c("zero_growth", "latest_available_growth")
]
#extract country-level benchmark accuracy scores
benchmark_country_scores <- validation_country_scores[
  model %in% c("zero_growth", "latest_available_growth")
]
#print validation accuracy tables and model-training records
print(validation_scores)
print(validation_country_scores)
print(regression_training_log)
print(tree_training_log)
#stop if any model predicts fewer or more than the expected validation rows
expected_rows <- nrow(development[sample == "validation"])
if (any(validation_scores$observations != expected_rows)) stop("Unequal forecast counts.")
#stop if a model has duplicate country-month predictions
if (anyDuplicated(validation_predictions[, .(model, country, month)])) {
  stop("Duplicate validation forecasts.")
}

# 5. Save development results ---------------------------------------------
#create the development results folder if it does not exist
dir.create(config$paths$development, recursive = TRUE, showWarnings = FALSE)

#collect benchmark, regression, tree and validation results for export
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
#write each results table as a CSV file in the development folder
for (name in names(outputs)) {
  fwrite(outputs[[name]], file.path(config$paths$development, paste0(name, ".csv")))
}
message("Validation complete: seven methods compared without conflict exposure.")

# 6. Add conflict exposure to regression and random forest ------------------
#see Technical Report, Section 4.4

#retrieve the four conflict-exposure variables from the configuration
conflict_columns <-
  config$analysis$predictor_specification$conflict_alternatives

#define the predictors shared by all conflict-augmented models
common_predictors <- c(
  "country",
  "retail_growth_lag3",
  "inflation_lag2",
  "unemployment_lag3",
  "gdp_available"
)

#reuse the no-conflict random-forest hyperparameters
forest_settings <- tree_settings[
  model == "forest_without_conflict"
]

#initialize a list for conflict-augmented forecasts
conflict_results <- list()

#repeat conflict-model estimation for each validation month
for (i in 1:length(validation_months)) {
  
  target_month <- validation_months[i]
  
  #select historical observations available under the retail release lag
  available_training <- development[
    month_id <= target_month - retail_release_lag
  ]
  
  #select the country observations for the current validation month
  forecast_rows <- development[
    sample == "validation" &
      month_id == target_month
  ]
  
  #evaluate each conflict-exposure measure separately
  for (j in 1:length(conflict_columns)) {
    
    conflict_measure <- conflict_columns[j]
    
    #append the selected conflict variable to the common predictors
    predictors <- c(
      common_predictors,
      conflict_measure
    )
    
    #construct the same predictor formula for regression and random forest
    model_formula <- as.formula(
      paste(
        "retail_growth ~",
        paste(predictors, collapse = " + ")
      )
    )
    
    #fit the shared-slope OLS regression with the selected conflict measure
    regression_fit <- lm(
      model_formula,
      data = available_training,
      na.action = na.fail
    )
    
    #stop if regression coefficients cannot be uniquely estimated
    if (regression_fit$rank < length(coef(regression_fit))) {
      stop(
        "Unidentified regression coefficients: ",
        conflict_measure, " at ", forecast_rows$month[1]
      )
    }
    
    #fit the random forest using the baseline hyperparameters
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
    
    #generate validation predictions from the regression and random forest
    model_predictions <- list(
      shared_slopes = as.numeric(
        predict(regression_fit, newdata = forecast_rows)
      ),
      forest = as.numeric(
        predict(forest_fit, data = forecast_rows)$predictions
      )
    )
    
    #process regression and forest predictions separately
    for (family in names(model_predictions)) {
      
      #create forecast records with country, month and actual retail growth
      predictions <- forecast_rows[
        , .(
          country,
          month,
          actual = retail_growth
        )
      ]
      
      #label each model by its family and conflict-exposure measure
      predictions[
        , model := paste0(family, "_", conflict_measure)
      ]
      
      #attach predictions from the corresponding model family
      predictions[, prediction := model_predictions[[family]]]
      
      #stop if any predicted value is missing or non-finite
      if (any(!is.finite(predictions$prediction))) {
        stop("Non-finite predictions for: ", family, "_", conflict_measure)
      }
      
      #calculate forecast errors as actual minus predicted growth
      predictions[, error := actual - prediction]
      
      #append the current model's forecasts to the results list
      conflict_results[[length(conflict_results) + 1]] <- predictions
    }
  }
}

#combine predictions from all eight conflict-augmented specifications
conflict_predictions <- rbindlist(conflict_results)

#remove existing conflict-model entries before appending the new predictions
validation_predictions <- rbindlist(
  list(
    validation_predictions[
      !model %in% unique(conflict_predictions$model)
    ],
    conflict_predictions
  ),
  use.names = TRUE
)

#recalculate overall validation MAE and RMSE for all specifications
validation_scores <- validation_predictions[
  , .(
    observations = .N,
    MAE = mean(abs(error)),
    RMSE = sqrt(mean(error^2))
  ),
  by = model
][order(RMSE)]

#recalculate validation MAE and RMSE by model and country
validation_country_scores <- validation_predictions[
  , .(
    observations = .N,
    MAE = mean(abs(error)),
    RMSE = sqrt(mean(error^2))
  ),
  by = .(model, country)
][order(country, RMSE)]

#stop if any specification has an unequal number of validation forecasts
if (any(validation_scores$observations != expected_rows)) {
  stop("Unequal validation forecast counts.")
}

#stop if duplicate model-country-month forecasts are found
if (anyDuplicated(
  validation_predictions[, .(model, country, month)]
)) {
  stop("Duplicate validation forecasts.")
}

#print updated validation accuracy scores for all 15 specifications
print(validation_scores)

#map each conflict-augmented specification to its no-conflict baseline
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

#extract RMSE scores for the two corresponding no-conflict models
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

#join conflict-model definitions with their validation accuracy scores
conflict_comparison <- merge(
  conflict_definitions,
  validation_scores,
  by = "model"
)

#attach the matched no-conflict RMSE to each conflict model
conflict_comparison <- merge(
  conflict_comparison,
  baseline_scores,
  by = "baseline_model"
)

#calculate percentage RMSE reduction relative to the matched baseline
conflict_comparison[
  , RMSE_improvement_pct :=
    100 * (1 - RMSE / baseline_RMSE)
]

#print conflict-model RMSE, baseline RMSE and percentage improvement
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

#save forecasts from the eight conflict-augmented models
fwrite(
  conflict_predictions,
  file.path(config$paths$development, "conflict_predictions.csv")
)

#save the conflict-versus-baseline accuracy comparison
fwrite(
  conflict_comparison,
  file.path(config$paths$development, "conflict_comparison.csv")
)

#save combined validation forecasts from all 15 specifications
fwrite(
  validation_predictions,
  file.path(config$paths$development, "validation_predictions.csv")
)

#save updated overall MAE and RMSE scores
fwrite(
  validation_scores,
  file.path(config$paths$development, "validation_scores.csv")
)

#save updated validation accuracy scores by model and country
fwrite(
  validation_country_scores,
  file.path(config$paths$development, "validation_country_scores.csv")
)