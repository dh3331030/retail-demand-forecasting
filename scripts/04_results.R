# Reproducible research figures and a plain-language results page.
esc <- function(x) {x<-gsub("&","&amp;",as.character(x),fixed=TRUE);x<-gsub("<","&lt;",x,fixed=TRUE);gsub(">","&gt;",x,fixed=TRUE)}
html_table <- function(d) {
  d <- as.data.frame(d)
  for(k in seq_along(d)) if(is.numeric(d[[k]])) d[[k]] <- format(round(d[[k]],4),trim=TRUE)
  paste0("<table><thead><tr>",paste0("<th>",esc(names(d)),"</th>",collapse=""),
    "</tr></thead><tbody>",paste(apply(d,1,function(r)paste0("<tr>",paste0("<td>",esc(r),"</td>",collapse=""),"</tr>")),collapse=""),"</tbody></table>")
}
style <- "body{font:16px/1.6 'Segoe UI',sans-serif;color:#20343b;background:#f5f7f6;margin:0}main{max-width:1100px;margin:auto;padding:36px}h1{font-size:36px;line-height:1.15}h2{margin-top:40px}a{color:#086c63}table{border-collapse:collapse;width:100%;background:white;font-size:14px}th,td{padding:10px;text-align:left;overflow-wrap:anywhere;border-bottom:1px solid #dce4e2}img{max-width:100%}.notice{border-left:4px solid #aa7023;padding:14px;background:#fff5e5}code{overflow-wrap:anywhere}nav{display:flex;gap:20px;flex-wrap:wrap}.scroll{overflow-x:auto}td:not(:first-child){white-space:nowrap;overflow-wrap:normal}@media(max-width:650px){main{padding:18px}h1{font-size:28px}}"
final <- scores[period=="2024-2025 retrospective",.(model,n,MAE,RMSE)]
# Describe the retained model fitted through December 2025, without using 2026 data.
# Orders change over origins; this table is one endpoint snapshot, not all fitted orders.
endpoint <- list()
for(cc in unique(retail$iso3)) {
  h <- retail[iso3==cc & month<="2025-12" & is.finite(retail_growth_mom)]
  z <- ts(h$retail_growth_mom,frequency=12,start=c(as.integer(substr(h$month[1],1,4)),as.integer(substr(h$month[1],6,7))))
  fit <- auto.arima(z,seasonal=TRUE,stepwise=TRUE,approximation=TRUE)
  order <- arimaorder(fit)
  endpoint[[length(endpoint)+1L]] <- data.table(iso3=cc,training_start=h$month[1],training_end=tail(h$month,1),
    observations=nrow(h),order=paste(paste(names(order),order,sep="="),collapse="; "),AICc=fit$aicc)
}
fwrite(rbindlist(endpoint),"results/arima_endpoint_models.csv")
p <- ggplot(final,aes(x=reorder(model,MAE),y=MAE))+geom_col(fill="#17685e")+
  coord_flip()+labs(title="Average forecast error, 2024-2025",x=NULL,y="MAE (log percentage points)",
    caption="120 country-month forecasts per model. Previously inspected retrospective period; lower is better.")+theme_minimal(base_size=12)
ggsave("results/figures/model_errors.png",p,width=10,height=6,dpi=160)
pr <- predictions[model=="ARIMA full history" & target_month>="2024-01"]
long <- melt(pr[,.(iso3,date=as.Date(paste0(target_month,"-01")),Actual=actual,ARIMA=prediction)],id.vars=c("iso3","date"))
p <- ggplot(long,aes(date,value,color=variable))+geom_line(linewidth=.65)+facet_wrap(~iso3,ncol=2)+
  scale_color_manual(values=c(Actual="#263c45",ARIMA="#bd642e"))+labs(title="What ARIMA captured and missed",x="Target month",y="Monthly growth (log percentage points)",color=NULL,
  caption="Source: approved Eurostat retail workbook; rolling one-month forecasts, 2024-2025.")+theme_minimal(base_size=12)
ggsave("results/figures/arima_forecasts.png",p,width=11,height=8,dpi=160)
trend <- retail[month>="2015-01" & month<="2025-12"]
trend[,indexed:=100*retail_volume/retail_volume[month=="2015-01"],by=iso3]
p <- ggplot(trend,aes(as.Date(paste0(month,"-01")),indexed,color=iso3))+geom_line()+
  labs(title="Food, beverage and tobacco retail volumes",x="Month",y="Volume index (January 2015 = 100)",color="Country",caption="Source: approved Eurostat retail workbook. Rebasing is for visual comparison only.")+theme_minimal(base_size=12)
ggsave("results/figures/retail_trends.png",p,width=11,height=5,dpi=160)
cl <- conflict[month>="2015-01" & month<="2025-12"]
p <- ggplot(cl,aes(as.Date(paste0(month,"-01")),ucdp_events))+geom_line(color="#17685e")+
  labs(title="Global recorded conflict events",x="Event-start month",y="Recorded events (count)",caption="Source: approved UCDP GED workbook. Global counts are not country exposure or causal effects.")+theme_minimal(base_size=12)
ggsave("results/figures/conflict_context.png",p,width=11,height=4,dpi=160)
ar <- final[model=="ARIMA full history"]; zero <- final[model=="Zero growth"]
sup <- fread("results/supporting_model_comparison.csv")
body <- paste0('<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Core retail analysis</title><style>',style,'</style></head><body><main>',
 '<nav><a href="../README.html">Project guide</a><a href="../MODEL_DECISION.html">Why ARIMA?</a><a href="model_comparison.csv">Download scores</a></nav>',
 '<h1>Can retail history forecast next month&#8217;s demand?</h1><p>We compare one-month forecasts for food, beverage and tobacco retail-volume growth in Germany, France, Italy, Poland and Portugal. The unit is a country-month, not a store or product.</p>',
 '<p><strong>ARIMA full history: MAE ',sprintf('%.4f',ar$MAE),' and RMSE ',sprintf('%.4f',ar$RMSE),'.</strong> Its average absolute error is ',sprintf('%.1f',100*(1-ar$MAE/zero$MAE)),'% below predicting no change over the same 120 targets.</p>',
 '<p class="notice">These are retrospective results. The 2024-2025 period influenced earlier model searches. Each forecast uses only earlier observations, but that does not make the model-selection process an untouched test. The source workbook contains revised values; actual release-time availability is not established.</p>',
 '<h2>1. Understand the data</h2><p>Growth = 100 &#215; log(this month&#8217;s volume / previous month&#8217;s volume). A value near 1 means approximately 1% monthly growth. Earlier source history is retained for training; the descriptive study window is 2015-2025. No external data are downloaded and missing historical macro data are not invented.</p><img src="figures/retail_trends.png" alt="Retail volume trends by country">',
 '<h2>2. Compare forecasts fairly</h2><p>All models predict the same months. MAE is the average size of the error; RMSE penalises large misses more heavily. Models are refitted as each month passes. This is a sequence of one-month forecasts, not a 24-month forecast made at the end of 2023.</p><img src="figures/model_errors.png" alt="Mean absolute errors by model"><div class="scroll">',html_table(final),'</div>',
 '<h2>3. Inspect the misses</h2><img src="figures/arima_forecasts.png" alt="Actual and ARIMA monthly growth by country"><p>Country-level errors are in <a href="errors_by_country.csv">the country comparison</a>. An aggregate gain does not imply the same improvement in every country or month.</p>',
 '<h2>4. Keep economic and conflict context</h2><p>A matched supporting comparison adds lagged GDP and global conflict counts/deaths to a simple retail regression. Both versions use the same training rows. GDP is assumed available two months after quarter-end; conflict is lagged two months relative to the target. These are timing assumptions using revised data. They do not establish real-time availability or a causal effect of conflict.</p>',html_table(sup),
 '<img src="figures/conflict_context.png" alt="Global monthly conflict event counts"><p>Annual Gini remains annual context. COVID observations remain missing outside their observed range. Inflation, confidence and unemployment extracts have insufficient historical coverage for the full forecast experiment. The file labelled energy inflation duplicates headline inflation; workbook metadata identifies the inflation unit as monthly change, despite the filenames saying annual.</p>',
 '<h2>5. Reproduction and limits</h2>',html_table(fread("results/arima_reproduction_check.csv")),
 '<p><a href="arima_endpoint_models.csv">ARIMA orders fitted through December 2025</a> show what the automatic procedure selected for each country at the endpoint; orders can differ at earlier forecast origins.</p>',
 '<p>Tables round numeric values to four decimal places; the CSV files retain full precision. The reproduction check compares all 120 ARIMA predictions against the saved previous run. Source hashes are checked before extraction. Full outputs: <a href="forecasts.csv">core forecasts</a>, <a href="supporting_forecasts.csv">supporting forecasts</a>, <a href="economic_coverage.csv">economic coverage</a>, <a href="session_info.txt">R environment</a>.</p>',
 '<p>Business use: a transparent country-level baseline for planning discussions. This analysis does not measure store-level inventory savings, prove causality, or establish future deployment performance. The news extension is outside the scope of this final analysis.</p></main></body></html>')
writeLines(body,"results/analysis.html",useBytes=TRUE)
