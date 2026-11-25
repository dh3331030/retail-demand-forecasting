#six prespecified finalists; chronological holdout scoring

#required to have loaded a frozen configuration from previous scripts
#stop if this stage is run in isolation.
if (!exists("frozen_config"))
  stop("Run run_final_evaluation.R, not file 04 alone.")

#check if `ranger` random-forest package is available.
if (!requireNamespace("ranger", quietly = TRUE)) {
  #else install `ranger` from CRAN only when it is missing.
  install.packages("ranger", repos = "https://cloud.r-project.org")
}

#STOP1 abort if the package still cannot be loaded after installation.
if (!requireNamespace("ranger", quietly = TRUE))
  stop("ranger installation incomplete.")

library(data.table)

#extract frozen configs into local variables.
spec <- frozen_config$analysis$model_specifications
protocol <- frozen_config$analysis$evaluation_protocol

#retrieve the frozen finalist model names.
selected <- spec$selected_models

#six supported model specifications for a compatibility check.
supported <- c("zero_growth", "country_mean", "shared_slopes_reduced_macro_only",
               "forest_reduced_without_gdp", "forest_without_conflict",
               "forest_conflict_deaths_1000_lag2")

#STOP2 reject frozen configurations with missing, extra or unsupported finalists.
if (length(selected) != 6 || !setequal(selected, supported)) {
  stop("Frozen finalist list differs from the six supported specifications.")
}


#zero growth was the winner in validation
#set zero predicted growth as the primary model
primary_model <- "zero_growth"

#reads the frozen number of months before a retail outcome becomes training-eligible.
retail_lag <- protocol$outcome_availability_lag_months

#STOP3 require this delay to be one non-missing integer equal to three months.
if (length(retail_lag) != 1 || is.na(retail_lag) || retail_lag != 3L) {
  stop("Expected the frozen three-month retail-outcome availability rule.")
}

#read the frozen random-forest hyperparameters.
forest_settings <- spec$forest_settings

#load the complete modelling panel, including the final holdout.
all_data <- as.data.table(readRDS(frozen_config$paths$model_panel))

#treat country as a categorical rather than a continuous predictor.
all_data[, country := factor(country)]
#sort all observations by country and month index.
all_data <- all_data[order(country, month_id)]

#STOP4 if more than one observation exists for any country-month.
if (anyDuplicated(all_data[, .(country, month_id)]))
  stop("Duplicate modeling rows.")

#list the outcome and all predictors needed by the finalist models.
required <- c("retail_growth", "retail_growth_lag3", "inflation_lag2",
              "unemployment_lag3", "gdp_available", "conflict_deaths_1000_lag2")

#and reject missing values in these final-evaluation variables.
if (anyNA(all_data[, required, with = FALSE]))
  stop("Missing final-evaluation model values.")

#then select the testing portion of the panel only.
test_rows <- all_data[sample == "testing"]

#getting the sorted set of unique test month identifiers.
test_months <- sort(unique(test_rows$month_id))

#STOP5 when the holdout is not 24 months times five countries equals 120 rows
if (length(test_months) != 24 || nrow(test_rows) != 120) {
  stop("Expected 24 test months and 120 country-month observations.")
}

#define the exact predictor columns used by each of the three finalist forests.
forest_predictors <- list(
  forest_reduced_without_gdp = c("country", "retail_growth_lag3",
                                 "inflation_lag2", "unemployment_lag3"),
  forest_without_conflict = c("country", "retail_growth_lag3", "inflation_lag2",
                              "unemployment_lag3", "gdp_available"),
  forest_conflict_deaths_1000_lag2 = c("country", "retail_growth_lag3",
    "inflation_lag2", "unemployment_lag3", "gdp_available", "conflict_deaths_1000_lag2")
)

#now construct the reduced macroeconomic OLS model formula from frozen predictor names.
regression_formula <- as.formula(paste(
  "retail_growth ~", paste(spec$macro_regression_predictors, collapse = " + ")
))

#initialize a list of month-by-month test forecast tables and training audit log
prediction_tables <- list()
training_records <- list()

#evaluate the chosen six models separately for each chronological test month.
for (i in 1:length(test_months)) {
  #read month ID.
  target_month <- test_months[i]
  #earlier test outcomes become training observations only after publication.
  #create fit window of all outcomes known at least three months before the target.
  training <- all_data[month_id <= target_month - retail_lag]
  #select the current target month's country observations to forecast.
  forecast_rows <- test_rows[month_id == target_month]
  #confirm that all configured countries are present in this month of the test sample.
  if (nrow(forecast_rows) != length(frozen_config$analysis$countries)) {
    # Stop if the expected country coverage is incomplete.
    stop("Incomplete country coverage for test month ID ", target_month)
  }
  #stop if any target country has no historical training records.
  if (!all(forecast_rows$country %in% training$country)) stop("Missing country history.")
  #and sett a deterministic monthly random-forest seed from the frozen base seed.
  model_seed <- protocol$forest_seed_base + i

  #loop over each of the six preselected finalist specifications.
  for (j in 1:length(selected)) {
    #identify the current finalist's label.
    label <- selected[j]
    #initialize the coefficient-count field to missing; tree models have no OLS coefficient count.
    coefficients <- NA_integer_
    #initialize predictor metadata to `none`, appropriate for the zero-growth benchmark.
    predictors <- "none"
    #branch to the zero-growth benchmark when the current label matches.
    if (label == "zero_growth") {
      #produce one zero forecast for each target-country row without fitting a model.
      values <- rep(0, nrow(forecast_rows))
    } else if (label == "country_mean") {
      #for the country-mean model, fit country-only OLS on the eligible training window.
      fit <- lm(retail_growth ~ country, data = training, na.action = na.fail)
      #predict test values from the fitted country-mean OLS.
      values <- as.numeric(predict(fit, newdata = forecast_rows))
      #count the fitted regression coefficients for the audit log.
      coefficients <- length(coef(fit))
      #record that this benchmark uses country membership as its only predictor.
      predictors <- "country"
    } else if (label == "shared_slopes_reduced_macro_only") {
      #for the reduced macro regression, estimate the frozen formula on eligible history.
      fit <- lm(regression_formula, data = training, na.action = na.fail)
      #stop if its design matrix is rank deficient and coefficients are unidentified.
      if (fit$rank < length(coef(fit))) stop("Unidentified final regression coefficients.")
      #generate numeric test-month predictions from the regression.
      values <- as.numeric(predict(fit, newdata = forecast_rows))
      #record how many regression coefficients were fitted.
      coefficients <- length(coef(fit))
      #store the actual macro predictor names used by the regression.
      predictors <- paste(spec$macro_regression_predictors, collapse = ", ")
    } else {
      #for a forest model, look up its named frozen predictor set.
      inputs <- forest_predictors[[label]]
      #build a response formula dynamically from those forest inputs.
      formula <- as.formula(paste("retail_growth ~", paste(inputs, collapse = " + ")))
      #fit `ranger` using all frozen forest settings, a monthly seed and single-thread execution.
      fit <- ranger::ranger(
        formula, data = training,
        num.trees = forest_settings$num_trees, mtry = forest_settings$mtry,
        min.node.size = forest_settings$min_node_size,
        min.bucket = forest_settings$min_bucket, max.depth = forest_settings$max_depth,
        replace = forest_settings$replace, sample.fraction = forest_settings$sample_fraction,
        splitrule = "variance", respect.unordered.factors = "partition",
        seed = model_seed, num.threads = 1L, oob.error = FALSE
      )
      #predict retail growth for the test-country observations with the fitted forest.
      values <- as.numeric(predict(fit, data = forecast_rows)$predictions)
      #log the forest's predictor column names.
      predictors <- paste(inputs, collapse = ", ")
    }
    #check that the model returned one finite prediction per country.
    if (length(values) != nrow(forecast_rows) || any(!is.finite(values))) {
      #stop if predictions are missing, infinite or the wrong length.
      stop("Invalid forecasts for ", label)
    }
    #create the current month/model table containing actual growth and observation keys.
    predictions <- forecast_rows[, .(country, month, actual = retail_growth)]
    #add the current finalist model name to those observations.
    predictions[, model := label]
    #store the vector of predicted retail growth.
    predictions[, prediction := values]
    #calculate the error between observed growth and its forecast.
    predictions[, error := actual - prediction]
    #mark predictions from the predefined primary model.
    predictions[, primary := model == primary_model]
    #compute a unique list index for this month-model combination.
    index <- (i - 1) * length(selected) + j
    #store the completed model forecast table at that index.
    prediction_tables[[index]] <- predictions
    #record training sample size, last eligible month, predictors, coefficients and seed.
    training_records[[index]] <- data.table(
      model = label, target_month = forecast_rows$month[1],
      training_observations = if (label == "zero_growth") 0L else nrow(training),
      last_eligible_training_month = max(training$month),
      predictors = predictors, coefficients = coefficients,
      seed = if (label %in% names(forest_predictors)) model_seed else NA_integer_
    )
  }
}
#combine all individual monthly finalist predictions into one test table.
test_predictions <- rbindlist(prediction_tables)
#dombine the per-month model audit records into a training log.
test_training_log <- rbindlist(training_records)
#reject duplicate `(model, country, month)` test forecasts.
if (anyDuplicated(test_predictions[, .(model, country, month)]))
  stop("Duplicate test forecasts.")

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
  d <- data.table::copy(test_predictions)
  d[, date := as.Date(paste0(month, "-01"))]
  limits <- range(c(d$actual, d$prediction), finite = TRUE)
  for (model_name in unique(d$model)) {
    one <- data.table::copy(d[model == model_name])
    label <- pretty_model(model_name)
    if (model_name == "zero_growth") label <- paste0(label, " (validation-selected primary)")
    lines <- data.table::melt(one, id.vars=c("country", "date"), measure.vars=c("actual", "prediction"),
                              variable.name="series", value.name="growth")
    p <- ggplot(lines, aes(date, growth, colour=series, linetype=series)) +
      geom_vline(xintercept=as.Date("2025-01-01"), colour="grey85") + geom_hline(yintercept=0, colour="grey60", linetype="dotted") + geom_line(linewidth=0.7) +
      facet_wrap(~country, ncol=1) +
      scale_colour_manual(values=c(actual="#075A9C", prediction="#E8790B"), labels=c(actual="Actual", prediction="Predicted")) +
      scale_linetype_manual(values=c(actual="solid", prediction="dashed"), labels=c(actual="Actual", prediction="Predicted")) +
      scale_x_date(breaks=as.Date(c("2024-01-01","2024-07-01","2025-01-01","2025-07-01")), date_labels="%b %Y") + coord_cartesian(ylim=limits) +
      labs(title="Actual versus predicted retail growth", subtitle=label, x="Target month",
           y="Growth (log percentage points)", colour=NULL, linetype=NULL,
           caption="2024-2025 retrospective test. Shared scales; dotted line = zero.")
    p <- p + theme_minimal(base_size = 10.5) +
      theme(
            panel.grid.minor = element_blank(), legend.position = "bottom",
            plot.caption = element_text(hjust = 0, size=8), plot.title.position="plot", plot.margin=margin(8,12,8,8), strip.text = element_text(face = "bold"), strip.text.y = element_text(angle=0), plot.title=element_text(size=13, face="bold", colour="#082B50"))
    dir.create("results/figures/final", recursive = TRUE, showWarnings = FALSE)
    if (interactive()) print(p)
    ggsave(paste0("results/figures/final/", paste0("test_forecast_lines_", model_name), ".png"), plot=p, width=7, height=9, dpi=300, bg="white")
    ggsave(paste0("results/figures/final/", paste0("test_forecast_lines_", model_name), ".pdf"), plot=p, width=7, height=9, bg="white")
    
    panel_scores <- one[, .(note=sprintf("RMSE %.3f", sqrt(mean((actual-prediction)^2)))), by=country]
    p <- ggplot(one, aes(actual, prediction)) +
      geom_text(data=panel_scores, aes(x=-Inf,y=Inf,label=note), inherit.aes=FALSE, hjust=-0.08,vjust=1.3,size=2.7) +
      geom_abline(slope=1, intercept=0, colour="grey50", linetype="dashed") +
      geom_point(colour="#075A9C", size=2, alpha=0.75) + facet_wrap(~country, ncol=2) +
      coord_equal(xlim=limits, ylim=limits) +
      labs(title="How close are forecasts to actual growth?", subtitle=label,
           x="Actual growth (log percentage points)", y="Predicted growth (log percentage points)",
           caption="Dashed line = perfect prediction. One point per month;
shared scales across models.")
    p <- p + theme_minimal(base_size = 10.5) +
      theme(
            panel.grid.minor = element_blank(), legend.position = "bottom",
            plot.caption = element_text(hjust = 0, size=8), plot.title.position="plot", plot.margin=margin(8,12,8,8), strip.text = element_text(face = "bold"), strip.text.y = element_text(angle=0), plot.title=element_text(size=13, face="bold", colour="#082B50"))
    dir.create("results/figures/final", recursive = TRUE, showWarnings = FALSE)
    if (interactive()) print(p)
    ggsave(paste0("results/figures/final/", paste0("test_forecast_scatter_", model_name), ".png"), plot=p, width=7, height=10, dpi=300, bg="white")
    ggsave(paste0("results/figures/final/", paste0("test_forecast_scatter_", model_name), ".pdf"), plot=p, width=7, height=10, bg="white")
  }
})

#calculate each finalist's total forecast count, MAE and RMSE, ranked by RMSE.
test_scores <- test_predictions[, .(
  observations = .N, MAE = mean(abs(error)), RMSE = sqrt(mean(error^2))
), by = model][order(RMSE)]
#verify that each finalist produced all 120 expected test forecasts.
if (any(test_scores$observations != 120)) stop("Unequal test forecast counts.")

#extract the zero-growth benchmark RMSE for relative comparisons.
zero_rmse <- test_scores[model == "zero_growth", RMSE]
#create a numeric column for percentage improvement relative to zero growth.
test_scores[, RMSE_improvement_vs_zero_pct := NA_real_]
#compute that improvement only when the baseline RMSE is greater than zero.
if (zero_rmse > 0) {
  #convert each RMSE to a percentage improvement over zero-growth RMSE.
  test_scores[, RMSE_improvement_vs_zero_pct := 100 * (1 - RMSE / zero_rmse)]
}
#then mark the predefined primary model in the overall score table.
test_scores[, primary := model == primary_model]

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
  d <- data.table::copy(test_scores)
  d[, label := pretty_model(model)]
  d[model == "zero_growth", label := paste0(label, " (primary)")]
  d[, label := factor(label, levels=rev(label[order(RMSE)]))]
  d <- data.table::melt(d, id.vars=c("model", "label"), measure.vars=c("RMSE", "MAE"),
                        variable.name="metric", value.name="error")
  p <- ggplot(d, aes(error, label)) +
    scale_y_discrete(labels=function(x) vapply(x,function(z) paste(strwrap(z,25),collapse="\n"),character(1))) +
    geom_text(aes(label=sprintf("%.3f", error)), hjust=-0.35, size=2.6) + geom_point(aes(shape=model == "zero_growth"), colour="#075A9C", size=3) + scale_shape_manual(values=c(`FALSE`=16, `TRUE`=18), guide="none") + facet_wrap(~metric, nrow=1) +
    scale_x_continuous(breaks=c(0,0.5,1,1.5,2),limits=c(0,NA), expand=expansion(mult=c(0,.28))) +
    labs(title="2024-2025 test accuracy: six frozen finalists", x="Forecast error (log percentage points)", y=NULL,
         caption="Lower error is better. Primary = zero growth, selected using validation RMSE.")
  p <- p + theme_minimal(base_size = 10.5) +
    theme(
          panel.grid.minor = element_blank(), legend.position = "bottom",
          plot.caption = element_text(hjust = 0, size=8), plot.title.position="plot", plot.margin=margin(8,12,8,8), strip.text = element_text(face = "bold"), strip.text.y = element_text(angle=0), plot.title=element_text(size=13, face="bold", colour="#082B50"))
  dir.create("results/figures/final", recursive = TRUE, showWarnings = FALSE)
  if (interactive()) print(p)
  ggsave(paste0("results/figures/final/", "test_accuracy", ".png"), plot=p, width=7, height=6, dpi=300, bg="white")
  ggsave(paste0("results/figures/final/", "test_accuracy", ".pdf"), plot=p, width=7, height=6, bg="white")
  
})

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
  d <- data.table::copy(test_scores)
  d[, label := pretty_model(model)]
  d[model == "zero_growth", label := paste0(label, " (primary)")]
  p <- ggplot(d, aes(RMSE_improvement_vs_zero_pct, reorder(label, RMSE_improvement_vs_zero_pct))) +
    scale_y_discrete(labels=function(x) vapply(x,function(z) paste(strwrap(z,25),collapse="\n"),character(1))) +
    geom_text(aes(label=pct_label(RMSE_improvement_vs_zero_pct)), hjust=-0.2, size=2.7) + scale_x_continuous(expand=expansion(mult=c(.1,.35))) +
    geom_vline(xintercept=0, colour="grey50", linetype="dashed") + geom_point(aes(shape=model == "zero_growth"), colour="#075A9C", size=3) + scale_shape_manual(values=c(`FALSE`=16, `TRUE`=18), guide="none") +
    labs(title="Test accuracy relative to zero growth", x="RMSE improvement over zero growth (%)", y=NULL,
         caption="Positive = better accuracy. Primary selected on validation;
test results do not select models.")
  p <- p + theme_minimal(base_size = 10.5) +
    theme(
          panel.grid.minor = element_blank(), legend.position = "bottom",
          plot.caption = element_text(hjust = 0, size=8), plot.title.position="plot", plot.margin=margin(8,12,8,8), strip.text = element_text(face = "bold"), strip.text.y = element_text(angle=0), plot.title=element_text(size=13, face="bold", colour="#082B50"))
  dir.create("results/figures/final", recursive = TRUE, showWarnings = FALSE)
  if (interactive()) print(p)
  ggsave(paste0("results/figures/final/", "test_improvement_vs_zero", ".png"), plot=p, width=7, height=6, dpi=300, bg="white")
  ggsave(paste0("results/figures/final/", "test_improvement_vs_zero", ".pdf"), plot=p, width=7, height=6, bg="white")
  
})


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
  d <- data.table::copy(test_scores[model %in% c("forest_without_conflict","forest_conflict_deaths_1000_lag2")])
  d <- data.table::melt(d,id.vars="model",measure.vars=c("RMSE","MAE"),variable.name="metric",value.name="error")
  pair <- d[, .(without=error[model=="forest_without_conflict"],with=error[model!="forest_without_conflict"]),by=metric]
  pair[, note := sprintf("Change with conflict: %+.4f",with-without)]
  d[, variant := ifelse(model=="forest_without_conflict","Without conflict","With conflict")]
  p <- ggplot(d,aes(error,variant)) +
    geom_segment(data=pair,aes(x=without,xend=with,y="Without conflict",yend="With conflict"),inherit.aes=FALSE,colour="grey60") +
    geom_point(colour="#075A9C",size=3) + geom_text(aes(label=sprintf("%.3f",error)),hjust=-.25,size=3) +
    geom_text(data=pair,aes(x=0,y=Inf,label=note),inherit.aes=FALSE,hjust=0,vjust=1.5,size=2.7) +
    facet_wrap(~metric,nrow=1) + scale_x_continuous(breaks=c(0,0.5,1,1.5,2),limits=c(0,NA),expand=expansion(mult=c(0,.28))) +
    labs(title="Does conflict improve the matched forest?",x="Error (log percentage points)",y=NULL,
      caption="Lower error is better. Observed differences; no significance or causal claim.")

  p <- p + theme_minimal(base_size=10.5) + theme(panel.grid.minor=element_blank(),
    plot.title=element_text(size=13,face="bold",colour="#082B50"), plot.title.position="plot",
    plot.caption=element_text(size=8,hjust=0), legend.position="bottom")
  dir.create("results/figures/final",recursive=TRUE,showWarnings=FALSE)
  if(interactive()) print(p)
  ggsave("results/figures/final/test_conflict_comparison.png",p,width=7,height=4,dpi=300,bg="white")
  ggsave("results/figures/final/test_conflict_comparison.pdf",p,width=7,height=4,bg="white")
})



#calculate forecast count, MAE and RMSE separately by model and country.
test_country_scores <- test_predictions[, .(
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
  d <- data.table::copy(test_country_scores)
  base <- d[model=="zero_growth", .(country, baseline=RMSE)]
  d <- merge(d,base,by="country")
  stopifnot(all(d$baseline>0))
  d[, improvement := 100*(1-RMSE/baseline)]
  d[, label := pretty_model(model)]
  d[model=="zero_growth",label := paste0(label," (Primary)")]
  span <- max(abs(d$improvement))
  p <- ggplot(d,aes(country,label,fill=improvement)) + geom_tile(colour="white") +
    geom_text(aes(label=pct_label(improvement)),size=2.7) +
    scale_fill_gradient2(low="#E9B68A",mid="white",high="#8BBAD9",midpoint=0,limits=c(-span,span),name="RMSE improvement (%)") +
    scale_y_discrete(labels=function(x) vapply(x,function(z) paste(strwrap(z,25),collapse="\n"),character(1))) +
    labs(title="Where do models improve on zero growth?",x=NULL,y=NULL,
         caption="Each country uses its own zero-growth baseline. Positive = better accuracy.")

  p <- p + theme_minimal(base_size=10.5) + theme(panel.grid.minor=element_blank(),
    plot.title=element_text(size=13,face="bold",colour="#082B50"), plot.title.position="plot",
    plot.caption=element_text(size=8,hjust=0), legend.position="bottom")
  dir.create("results/figures/final",recursive=TRUE,showWarnings=FALSE)
  if(interactive()) print(p)
  ggsave("results/figures/final/test_country_improvement.png",p,width=7,height=5,dpi=300,bg="white")
  ggsave("results/figures/final/test_country_improvement.pdf",p,width=7,height=5,bg="white")
})

#extract each prediction's year from its month string.
test_predictions[, year := substr(month, 1, 4)]
#and calculate model-level forecast performance separately by calendar year.
test_year_scores <- test_predictions[, .(
  observations = .N, MAE = mean(abs(error)), RMSE = sqrt(mean(error^2))
), by = .(model, year)][order(year, RMSE)]


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
  d <- data.table::copy(test_year_scores)
  base <- d[model=="zero_growth", .(year,baseline=RMSE)]
  d <- merge(d,base,by="year")
  stopifnot(all(d$baseline>0))
  d[, improvement := 100*(1-RMSE/baseline)]
  d[, label := pretty_model(model)]
  d[model=="zero_growth",label := paste0(label," (Primary)")]
  p <- ggplot(d,aes(improvement,label)) + geom_vline(xintercept=0,linetype="dashed",colour="grey60") +
    geom_point(aes(shape=model=="zero_growth"),colour="#075A9C",size=2.5) +
    scale_shape_manual(values=c(`FALSE`=16,`TRUE`=18),guide="none") +
    geom_text(aes(label=pct_label(improvement)),hjust=-.2,size=2.6) +
    facet_wrap(~year,nrow=1) + scale_x_continuous(expand=expansion(mult=c(.1,.5))) +
    scale_y_discrete(labels=function(x) vapply(x,function(z) paste(strwrap(z,24),collapse="\n"),character(1))) +
    labs(title="Does relative accuracy change between years?",x="RMSE improvement (%)",y=NULL,
         caption="Each year uses its own zero-growth baseline. Shared scale; positive = better.")

  p <- p + theme_minimal(base_size=10.5) + theme(panel.grid.minor=element_blank(),
    plot.title=element_text(size=13,face="bold",colour="#082B50"), plot.title.position="plot",
    plot.caption=element_text(size=8,hjust=0), legend.position="bottom")
  dir.create("results/figures/final",recursive=TRUE,showWarnings=FALSE)
  if(interactive()) print(p)
  ggsave("results/figures/final/test_year_improvement.png",p,width=7,height=5,dpi=300,bg="white")
  ggsave("results/figures/final/test_year_improvement.pdf",p,width=7,height=5,bg="white")
})

#read the frozen final-output destination.
final_path <- frozen_config$paths$final

#then create the final-results folder if it does not yet exist.
dir.create(final_path, recursive = TRUE, showWarnings = FALSE)
#collect prediction tables, score tables and training audit logs under export names.
outputs <- list(test_predictions = test_predictions, test_scores = test_scores,
  test_country_scores = test_country_scores, test_year_scores = test_year_scores,
  test_training_log = test_training_log)

#write each named final output table to a separate CSV file.
for (name in names(outputs)) fwrite(outputs[[name]], file.path(final_path, paste0(name, ".csv")))
#save the frozen configuration, primary-model identity and monthly seed rule together in an RDS.
saveRDS(list(config = frozen_config, primary_model = primary_model,
             seed_rule = "forest_seed_base + test-month index (January 2024 = 1)"),
        file.path(final_path, "evaluation_settings.rds"))

#display the overall finalist, each country, and the year-by-year test scores.
print(test_scores)
print(test_country_scores)
print(test_year_scores)

#confirm that holdout scoring ended without further model selection or retuning.
message("Final holdout evaluation complete.")
