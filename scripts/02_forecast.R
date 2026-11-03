# A compact, fixed comparison replaces the large experimental search.
# Each target is predicted using observations strictly before its month.
# The historical scoring period was inspected during development: not an untouched test.

library(forecast)
retail <- as.data.table(readRDS("data/processed/approved_retail_country_month.rds"))[core_country==TRUE]
setorder(retail,iso3,month)
targets <- retail[month>="2023-01" & month<="2025-12",.(iso3,target_month=month,actual=retail_growth_mom)]
stopifnot(nrow(targets)==180L,all(is.finite(targets$actual)),!anyDuplicated(targets[,.(iso3,target_month)]))
specs <- c("Zero growth","Last observed growth","Same month last year growth",
           "Mean previous 3 months","Mean previous 12 months","AR(1)",
           "ETS growth","Theta growth","ARIMA full history","ARIMA since 2016")
# Always refit models from the observations rebuilt from raw files in stage 01.
{
  rows <- list(); warning_rows <- list()
  for(cc in unique(targets$iso3)) {
    message("Forecasting ",cc," (36 months, 10 models)")
    for(tm in targets[iso3==cc,target_month]) {
      h <- retail[iso3==cc & month<tm & is.finite(retail_growth_mom)]
      ym <- function(x) as.integer(substr(x,1,4))*12L+as.integer(substr(x,6,7))
      stopifnot(nrow(h)>=24L,all(diff(ym(h$month))==1L),tail(ym(h$month),1)+1L==ym(tm))
      v <- h$retail_growth_mom
      values <- c(0,tail(v,1),v[length(v)-11L],mean(tail(v,3)),mean(tail(v,12)))
      reg <- data.frame(y=v[-1],lag=head(v,-1))
      values <- c(values,as.numeric(predict(lm(y~lag,reg),newdata=data.frame(lag=tail(v,1)))))
      make_ts <- function(x) ts(x$retail_growth_mom,frequency=12,
        start=c(as.integer(substr(x$month[1],1,4)),as.integer(substr(x$month[1],6,7))))
      values <- withCallingHandlers({
        c(values,as.numeric(forecast(ets(make_ts(h),additive.only=TRUE),h=1)$mean[1]),
          as.numeric(thetaf(ts(v,frequency=1),h=1)$mean[1]),
          as.numeric(forecast(auto.arima(make_ts(h),seasonal=TRUE,stepwise=TRUE,approximation=TRUE),h=1)$mean[1]),
          as.numeric(forecast(auto.arima(make_ts(h[month>="2016-01"]),seasonal=TRUE,stepwise=TRUE,approximation=TRUE),h=1)$mean[1]))
      },warning=function(w) {
        warning_rows[[length(warning_rows)+1L]] <<- data.table(iso3=cc,target_month=tm,warning=conditionMessage(w))
        invokeRestart("muffleWarning")
      })
      stopifnot(length(values)==length(specs),all(is.finite(values)))
      rows[[length(rows)+1L]] <- data.table(model=specs,iso3=cc,target_month=tm,
        actual=targets[iso3==cc & target_month==tm,actual],prediction=values,training_end=tail(h$month,1))
    }
  }
  predictions <- rbindlist(rows)
  warnings <- if(length(warning_rows)) rbindlist(warning_rows) else data.table(iso3=character(),target_month=character(),warning=character())
  fwrite(warnings,"results/fit_warnings.csv")
}
stopifnot(nrow(predictions)==1800L,!anyDuplicated(predictions[,.(model,iso3,target_month)]),
  all(predictions$training_end<predictions$target_month),all(is.finite(predictions$prediction)))
fwrite(predictions,"results/forecasts.csv")
score <- function(d,by="model") d[,.(n=.N,MAE=mean(abs(actual-prediction)),RMSE=sqrt(mean((actual-prediction)^2))),by=by]
scores <- rbind(score(predictions[target_month<"2024-01"])[,period:="2023 diagnostic"],
                score(predictions[target_month>="2024-01"])[,period:="2024-2025 retrospective"])
setorder(scores,period,MAE,RMSE)
fwrite(scores,"results/model_comparison.csv")
fwrite(score(predictions[target_month>="2024-01"],c("model","iso3")),"results/errors_by_country.csv")
# Check the migration against the saved ARIMA predictions, not just rounded metrics.
previous <- fread("evidence/previous_reviewed_forecasts.csv")[model=="arima_growth / all / seasonal / full_history"]
check <- merge(predictions[model=="ARIMA full history"],previous,by=c("iso3","target_month"),suffixes=c("_new","_previous"))
stopifnot(nrow(check)==120L,max(abs(check$actual_new-check$actual_previous))<1e-10)
parity <- data.table(targets=nrow(check),max_actual_difference=max(abs(check$actual_new-check$actual_previous)),
  max_prediction_difference=max(abs(check$prediction_new-check$prediction_previous)))
fwrite(parity,"results/arima_reproduction_check.csv")
if(parity$max_prediction_difference>1e-7) warning("ARIMA differs from the saved result; inspect reproduction check and package versions.")
