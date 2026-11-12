# Supporting economic and conflict context uses the same approved observations.
# Global conflict is not a country-distance exposure and does not identify causality.
meta <- fread("data/processed/source_series_metadata.csv")
obs <- as.data.table(readRDS("data/processed/approved_workbook_observations.rds"))
map <- c(Germany="DEU",France="FRA",Italy="ITA",Poland="POL",Portugal="PRT")
context <- obs[geography %in% names(map)]
context[,iso3:=unname(map[geography])]
context <- merge(context,meta[,.(series_id,file,sheet,metadata)],by="series_id")
fwrite(context,"data/processed/economic_context_long.csv")
coverage <- context[,.(nonmissing=sum(is.finite(value)),first_period=min(period),last_period=max(period)),
                    by=.(series_id,file,sheet,iso3)]
fwrite(coverage,"results/economic_coverage.csv")

panel <- copy(retail)
setorder(panel,iso3,month)
panel[,`:=`(growth_lag1=shift(retail_growth_mom),growth_lag12=shift(retail_growth_mom,12L)),by=iso3]
panel[,origin_index:=month_index-1L]
gdp_id <- meta[grepl("^[(]new[)]Gross",file) &
  grepl("Unit of measure = Chain linked volumes, percentage change on previous period ",metadata) &
  grepl("Seasonally and calendar adjusted data",metadata),series_id]
stopifnot(length(gdp_id)==1L)
gdp <- context[series_id==gdp_id,.(iso3,period,value)]
# At the forecast origin (month before target), use only quarters assumed available.
# Quarter-end + two months is a timing assumption; these are revised, not vintage data.
gdp[,release_index:=as.integer(substr(period,1,4))*12L+3L*as.integer(substr(period,7,7))+2L]
setkey(gdp,iso3,release_index)
gdp_match <- gdp[panel[,.(iso3,release_index=origin_index)],on=.(iso3,release_index),roll=TRUE]
panel[,`:=`(gdp_qoq_available=gdp_match$value,gdp_reference_quarter=gdp_match$period)]
conflict <- as.data.table(readRDS("data/processed/approved_ucdp_global_month.rds"))
setorder(conflict,month)
# Use target minus two months, matching the prior approved regression's extra lag.
# This is a sensitivity assumption, not proof that GED was published at the time.
conflict[,`:=`(conflict_events_lag2=shift(log1p(ucdp_events),2L),
               conflict_deaths_lag2=shift(log1p(ucdp_deaths),2L))]
panel <- merge(panel,conflict,by="month",all.x=TRUE)
setorder(panel,iso3,month)
covid <- as.data.table(readRDS("data/processed/approved_covid_country_month.rds"))
panel <- merge(panel,covid[CountryCode %in% unname(map),.(iso3=CountryCode,month,
  covid_stringency=StringencyIndex_Average)],by=c("iso3","month"),all.x=TRUE)
panel[,country:=factor(iso3,levels=sort(unname(map)))]
fwrite(panel[month>="2015-01" & month<="2025-12"],"data/processed/supporting_monthly_panel.csv")
fwrite(conflict,"data/processed/conflict_global_monthly.csv")

# A matched comparison asks if GDP/conflict improves a simple retail regression.
# Both specifications use exactly the same training rows and all 120 scoring targets.
forms <- list("Retail regression"=retail_growth_mom~country+growth_lag1+growth_lag12,
 "Retail + GDP + global conflict"=retail_growth_mom~country+growth_lag1+growth_lag12+
   gdp_qoq_available+conflict_events_lag2+conflict_deaths_lag2)
needed <- c("retail_growth_mom","growth_lag1","growth_lag12","gdp_qoq_available",
            "conflict_events_lag2","conflict_deaths_lag2")
support <- list()
for(tm in sort(unique(targets[target_month>="2024-01",target_month]))) {
  tr <- panel[month>="2015-01" & month<tm]
  tr <- tr[complete.cases(tr[,..needed])]
  va <- panel[month==tm]
  stopifnot(nrow(tr)>100L,nrow(va)==5L,all(complete.cases(va[,..needed])),max(tr$month)<tm)
  for(nm in names(forms)) {
    fit <- lm(forms[[nm]],data=tr)
    pr <- as.numeric(predict(fit,newdata=va))
    stopifnot(all(is.finite(pr)))
    support[[length(support)+1L]] <- data.table(model=nm,iso3=va$iso3,target_month=tm,
      actual=va$retail_growth_mom,prediction=pr,training_n=nrow(tr),training_end=max(tr$month))
  }
}
support <- rbindlist(support)
stopifnot(nrow(support)==240L,!anyDuplicated(support[,.(model,iso3,target_month)]))
fwrite(support,"results/supporting_forecasts.csv")
fwrite(score(support),"results/supporting_model_comparison.csv")
# Descriptive country statistics are distinct from pooled predictive evaluation.
summary <- panel[month>="2015-01" & month<="2025-12",.(months=.N,
 mean_growth=mean(retail_growth_mom),sd_growth=sd(retail_growth_mom),
 min_growth=min(retail_growth_mom),max_growth=max(retail_growth_mom)),by=iso3]
fwrite(summary,"results/retail_country_summary.csv")
