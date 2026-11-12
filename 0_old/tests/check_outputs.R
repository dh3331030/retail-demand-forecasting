# Output audit: run after forecast, supporting analysis and reporting.
# Do not source directly before running run_project.R, as output files may be archived.
core <- data.table::fread("results/forecasts.csv")
req <- c("model","iso3","target_month","actual","prediction","training_end")
if (!all(req %in% names(core)) || nrow(core)!=1800L ||
    data.table::uniqueN(core$model)!=10L ||
    data.table::uniqueN(core$iso3)!=5L ||
    anyDuplicated(core[,.(model,iso3,target_month)]) ||
    any(!is.finite(core$actual)) || any(!is.finite(core$prediction)) ||
    any(core$training_end >= core$target_month))
  stop("Invalid core forecasts: expected 1800 unique leakage-checked model/country/month rows.",call.=FALSE)
comp <- data.table::fread("results/model_comparison.csv")
if (nrow(comp)!=20L || !setequal(comp$period,c("2023 diagnostic","2024-2025 retrospective")))
  stop("Expected two scoring periods for all ten core models.",call.=FALSE)
for (i in seq_len(nrow(comp))) {
  r <- comp[i]
  z <- if (r$period=="2023 diagnostic") core[model==r$model & target_month<"2024-01"] else
    core[model==r$model & target_month>="2024-01"]
  if (nrow(z)!=r$n || abs(mean(abs(z$actual-z$prediction))-r$MAE)>1e-8 ||
      abs(sqrt(mean((z$actual-z$prediction)^2))-r$RMSE)>1e-8)
    stop("Scoring mismatch for ",r$model," / ",r$period,call.=FALSE)
}
sup <- data.table::fread("results/supporting_forecasts.csv")
if (nrow(sup)!=240L || data.table::uniqueN(sup$model)!=2L ||
    anyDuplicated(sup[,.(model,iso3,target_month)]) ||
    any(sup$training_end >= sup$target_month) ||
    any(!is.finite(sup$prediction)))
  stop("Supporting forecast integrity check failed.",call.=FALSE)
if (!file.exists("results/analysis.html") ||
    !all(file.exists(file.path("results/figures",c("arima_forecasts.png","model_errors.png","retail_trends.png","conflict_context.png")))))
  stop("Missing HTML report or figures.",call.=FALSE)
message("PASS: checked 1800 core forecasts, twenty score rows, 240 supporting forecasts and outputs.")
