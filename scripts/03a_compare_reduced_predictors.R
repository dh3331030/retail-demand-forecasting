#run after script 03 in the same R session

#define five reduced predictor sets to compare forecasting accuracy
reduced_sets <- list(
  retail_only = "retail_growth_lag3",
  without_inflation = c("retail_growth_lag3", "unemployment_lag3", "gdp_available"),
  without_unemployment = c("retail_growth_lag3", "inflation_lag2", "gdp_available"),
  without_gdp = c("retail_growth_lag3", "inflation_lag2", "unemployment_lag3"),
  macro_only = c("inflation_lag2", "unemployment_lag3", "gdp_available")
)

#reuse the settings of the random forest without conflict predictors
forest_settings <- tree_settings[model == "forest_without_conflict"]

#initialize a list to store the forecasts
reduced_results <- list()

#initialize a list to store the training details
reduced_training_records <- list()

#define a function to check and organize each model's forecasts
record_reduced_forecast <- function(label, values, rows) {
  
#check that forecasts are finite and match the number of observations
  if (length(values) != nrow(rows) || any(!is.finite(values))) {
    
#stop if the forecasts fail these checks
    stop("Invalid forecasts for ", label)
  }
  
#retain country, month and observed retail growth
  result <- rows[, .(country, month, actual = retail_growth)]
  
#add the model name
  result[, model := label]
  
#store the predicted growth values as numbers
  result[, prediction := as.numeric(values)]
  
#calculate forecast errors as observed minus predicted growth
  result[, error := actual - prediction]
  
#return the completed forecast table
  result
}

#repeat the forecasting process for each validation month
for (i in 1:length(validation_months)) {
  
#select the current forecast month
  target_month <- validation_months[i]
  
#retain training observations available under the retail publication lag
  available_training <- development[month_id <= target_month - retail_release_lag]
  
#select the validation observations for the current month
  forecast_rows <- development[sample == "validation" & month_id == target_month]

#fit a historical mean benchmark for each country
  mean_fit <- lm(retail_growth ~ country, data = available_training, na.action = na.fail)
  
#generate and store the country-mean forecasts
  reduced_results[[length(reduced_results) + 1]] <- record_reduced_forecast(
    "country_mean", predict(mean_fit, newdata = forecast_rows), forecast_rows
  )
  
#record the training sample and settings for the country-mean benchmark
  reduced_training_records[[length(reduced_training_records) + 1]] <- data.table(
    model = "country_mean", target_month = forecast_rows$month[1],
    training_observations = nrow(available_training),
    last_training_month = max(available_training$month),
    predictors = "country", mtry = NA_integer_, seed = NA_integer_
  )

#repeat the estimation for each reduced predictor set
  for (subset_name in names(reduced_sets)) {
    
#include country alongside the selected predictors
    predictors <- c("country", reduced_sets[[subset_name]])
    
#build the model formula from the selected predictors
    model_formula <- as.formula(paste("retail_growth ~", paste(predictors, collapse = " + ")))
    
#fit a regression with country intercepts and shared predictor coefficients
    regression_fit <- lm(model_formula, data = available_training, na.action = na.fail)
    
#check that the regression coefficients can be estimated separately
    if (regression_fit$rank < length(coef(regression_fit))) {
      
#stop if the regression coefficients cannot be estimated separately
      stop("Unidentified reduced regression: ", subset_name, " at ", forecast_rows$month[1])
    }
    
#limit mtry to the number of available predictors
    used_mtry <- min(forest_settings$mtry, length(predictors))
    
#fit a random forest using the reduced predictors and existing settings
    forest_fit <- ranger::ranger(
      model_formula, data = available_training,
      num.trees = forest_settings$trees, mtry = used_mtry,
      min.node.size = 40L, min.bucket = forest_settings$minimum_leaf_size,
      max.depth = forest_settings$max_depth, splitrule = "variance",
      replace = TRUE, sample.fraction = 1,
      respect.unordered.factors = "partition",
      seed = 20564L + i, num.threads = 1L, oob.error = FALSE
    )
    
#predict validation growth using the regression and random forest
    forecasts <- list(
      shared_slopes = as.numeric(predict(regression_fit, newdata = forecast_rows)),
      forest = as.numeric(predict(forest_fit, data = forecast_rows)$predictions)
    )
    
#store the results for both model types
    for (family in names(forecasts)) {
      
#label the model using its type and predictor set
      label <- paste0(family, "_reduced_", subset_name)
      
#check and store the model's forecasts
      reduced_results[[length(reduced_results) + 1]] <- record_reduced_forecast(
        label, forecasts[[family]], forecast_rows
      )
      
#record the training sample, predictors and forest settings
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

#combine all reduced-model and country-mean forecasts
reduced_predictions <- rbindlist(reduced_results)

#combine the training records
reduced_training_log <- rbindlist(reduced_training_records)

#replace earlier forecasts for these models and append the new results
validation_predictions <- rbindlist(list(
  validation_predictions[!model %in% unique(reduced_predictions$model)],
  reduced_predictions
), use.names = TRUE)

#check for duplicate forecasts for the same model, country and month
if (anyDuplicated(validation_predictions[, .(model, country, month)])) {
  
#stop if duplicate forecasts are found
  stop("Duplicate validation forecasts.")
}

#calculate overall forecast errors and rank models by RMSE
validation_scores <- validation_predictions[, .(
  observations = .N, MAE = mean(abs(error)), RMSE = sqrt(mean(error^2))
), by = model][order(RMSE)]

#stop if any model has an unexpected number of forecasts
if (any(validation_scores$observations != expected_rows)) stop("Unequal forecast counts.")

#calculate forecast errors and rank models within each country
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

  if (interactive()) print(p)
  ggsave(paste0("results/figures/development/", "validation_complete_accuracy", ".png"), plot = p,
         width=7, height = 11, dpi = 300, bg = "white")
  ggsave(paste0("results/figures/development/", "validation_complete_accuracy", ".pdf"), plot = p,
         width=7, height = 11, bg = "white")
})

#assign a baseline to each reduced model and the country-mean benchmark
baseline_map <- data.table(
  model = c("country_mean", paste0("shared_slopes_reduced_", names(reduced_sets)),
            paste0("forest_reduced_", names(reduced_sets))),
  baseline_model = c("zero_growth",
    rep("shared_slopes_without_conflict", length(reduced_sets)),
    rep("forest_without_conflict", length(reduced_sets)))
)

#extract the model names and RMSE values for the baseline comparison
baselines <- validation_scores[, .(baseline_model = model, baseline_RMSE = RMSE)]

#join each model's accuracy scores to its assigned baseline
reduced_comparison <- merge(baseline_map, validation_scores, by = "model")

#add the RMSE of the corresponding baseline
reduced_comparison <- merge(reduced_comparison, baselines, by = "baseline_model")

#calculate the percentage improvement in RMSE over the baseline
reduced_comparison[, RMSE_improvement_pct := 100 * (1 - RMSE / baseline_RMSE)]

#sort the comparisons by baseline and RMSE
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

#display the overall model ranking
print(validation_scores)

#display the RMSE comparisons with the assigned baselines
print(reduced_comparison)

#collect the forecasts, training records and accuracy comparisons for export
reduced_outputs <- list(
  reduced_predictions = reduced_predictions, reduced_training_log = reduced_training_log,
  reduced_comparison = reduced_comparison, validation_predictions = validation_predictions,
  validation_scores = validation_scores, validation_country_scores = validation_country_scores
)

#loop through the output tables
for (name in names(reduced_outputs)) {
#save each table as a CSV in the development folder
  fwrite(reduced_outputs[[name]], file.path(config$paths$development, paste0(name, ".csv")))
}
#display a completion message
message("Reduced-predictor comparison complete: country mean plus ten fitted specifications.")
