# Read the original Excel/ZIP datasets and rebuild the derived observations.
# Called by run_project.R; missing observations and source flags remain explicit.

library("data.table")

out <- "data/processed"
dir.create(out, recursive = TRUE, showWarnings = FALSE)

# Import from actual originals, never a CSV manifest or a cached snapshot.
if (!exists("locate_raw_sources", mode="function")) {
  source("scripts/00_preflight.R", local = TRUE, encoding = "UTF-8")
}

sources <- as.data.table(locate_raw_sources(getwd()))
if (any(!file.exists(sources$read_path)))
  stop("Original raw datasets are missing. Run Rscript run_project.R --check.", call. = FALSE)
observations<-list();metadata<-list();series<-0L
for(fi in seq_len(nrow(sources))){
  f<-sources$file[fi];rp<-sources$read_path[fi]
  if(!grepl("[.]xlsx?$",f,ignore.case=TRUE)||grepl("UCDP|project_data_sources",f))next
  sheets<-grep("^Sheet [0-9]+$",readxl::excel_sheets(rp),value=TRUE)
  if(grepl("^[(]new[)]Gini coefficient",f)){
    sheets<-intersect(sheets,"Sheet 1")
    if(length(sheets)!=1L)stop("The Eurostat Gini workbook must contain one total-population data sheet.",call.=FALSE)
  }
  message("Extracting ",f," (",length(sheets)," data sheets)")
  for(sh in sheets){
    x<-as.data.frame(suppressMessages(readxl::read_excel(rp,sheet=sh,col_names=FALSE,col_types="text",.name_repair="minimal")),stringsAsFactors=FALSE)
    tr<-which(trimws(x[[1]])=="TIME")
    if(length(tr)!=1L)stop("Cannot identify unique TIME header: ",f," / ",sh)
    times<-unlist(x[tr,,drop=FALSE],use.names=FALSE)
    tc<-which(grepl("^[0-9]{4}(-[0-9]{2}|-Q[1-4])?$",times))
    if(!length(tc))stop("No time periods found: ",f," / ",sh)
    rr<-seq.int(tr+2L,nrow(x));rr<-rr[!is.na(x[[1]][rr])&nzchar(trimws(x[[1]][rr]))]
    eligible<-vapply(rr,function(r){v<-unlist(x[r,tc,drop=FALSE],use.names=FALSE);any(v==":"|grepl("^-?[0-9]+([.][0-9]+)?$",v),na.rm=TRUE)},logical(1))
    rr<-rr[eligible]
    series<-series+1L;sid<-sprintf("source_%03d",series)
    meta_rows<-seq_len(tr-1L)
    meta<-vapply(meta_rows,function(r){v<-unlist(x[r,,drop=FALSE],use.names=FALSE);paste(v[!is.na(v)&nzchar(v)],collapse=" = ")},character(1))
    metadata[[series]]<-data.table(series_id=sid,file=f,sheet=sh,metadata=paste(meta[nzchar(meta)],collapse=" | "),first_period=min(times[tc]),last_period=max(times[tc]),geographies=length(rr))
    obs<-rbindlist(lapply(tc,function(k){raw<-x[[k]][rr];flag<-if(k<ncol(x)&&!((k+1L)%in%tc))x[[k+1L]][rr]else rep(NA_character_,length(rr));data.table(series_id=sid,geography=trimws(x[[1]][rr]),period=times[k],raw_value=raw,value=suppressWarnings(as.numeric(raw)),flag=flag)}))
    stopifnot(!anyDuplicated(obs[,.(geography,period)]))
    observations[[series]]<-obs
  }
}
meta<-rbindlist(metadata);obs<-rbindlist(observations)
fwrite(meta,file.path(out,"source_series_metadata.csv"));saveRDS(obs,file.path(out,"approved_workbook_observations.rds"))
coverage<-merge(obs[,.(cells=.N,nonmissing=sum(!is.na(value)),geographies=uniqueN(geography),first_period=min(period),last_period=max(period)),by=series_id],meta[,.(series_id,file,sheet)],by="series_id")
fwrite(coverage,file.path(out,"source_series_coverage.csv"))

# Keep inequality at its observed annual frequency; do not carry it into monthly forecasts.
gini_series<-meta[grepl("^[(]new[)]Gini coefficient",file)&
  grepl("Age class = Total",metadata,fixed=TRUE)&
  grepl("Statistical information = Gini coefficient (scale from 0 to 100)",metadata,fixed=TRUE),series_id]
stopifnot(length(gini_series)==1L)
gini_map<-c(Germany="DEU",France="FRA",Italy="ITA",Poland="POL",Portugal="PRT")
gini<-obs[series_id==gini_series&geography%in%names(gini_map),
  .(country=geography,year=as.integer(period),gini=value,flag)]
gini[,iso3:=unname(gini_map[country])]
setcolorder(gini,c("iso3","country","year","gini","flag"))
setorder(gini,iso3,year)
stopifnot(nrow(gini)==50L,!anyDuplicated(gini[,.(iso3,year)]),
  all(is.finite(gini$gini)),setequal(gini$iso3,unname(gini_map)),
  setequal(gini$year,2016:2025),all(gini[, .N,by=iso3]$N==10L),
  all(gini$gini>=0&gini$gini<=100))
fwrite(gini,file.path(out,"approved_gini_eurostat_total_annual.csv"))

# Raw retail values from the approved workbook define the target; retain every geography/month.
retail_sid<-meta[grepl("^Retail trade volume",file),series_id]
stopifnot(length(retail_sid)==1L)
retail<-obs[series_id==retail_sid,.(geography,month=period,retail_volume=value,retail_flag=flag)]
stopifnot(!anyDuplicated(retail[,.(geography,month)]),all(retail$retail_volume[is.finite(retail$retail_volume)]>0))
setorder(retail,geography,month)
retail[,month_index:=as.integer(substr(month,1,4))*12L+as.integer(substr(month,6,7))]
stopifnot(retail[,all(diff(month_index)==1L),by=geography][,all(V1)])
retail[,retail_growth_mom:=100*log(retail_volume/shift(retail_volume)),by=geography]
retail[,iso3:=NA_character_]
map<-c(Germany="DEU",France="FRA",Italy="ITA",Poland="POL",Portugal="PRT")
for(nm in names(map))retail[grepl(paste0("^",nm,"($| \\()"),geography),iso3:=unname(map[nm])]
retail[,core_country:=!is.na(iso3)]
saveRDS(retail,file.path(out,"approved_retail_country_month.rds"))
fwrite(retail[core_country==TRUE],file.path(out,"retail_monthly.csv"))
fwrite(retail[core_country==TRUE,.(rows=.N,nonmissing_volume=sum(is.finite(retail_volume)),first_observed=min(month[is.finite(retail_volume)]),last_observed=max(month[is.finite(retail_volume)])),by=.(iso3,geography)],file.path(out,"core_retail_coverage.csv"))

# Read the original UCDP event workbook on every run (no cached input data).
ged_path <- sources[grepl("^UCDP", file), read_path]
if (length(ged_path) != 1L || !file.exists(ged_path))
  stop("Original UCDP event workbook is missing or ambiguous.", call. = FALSE)
sheet <- "GEDEvent_v26_1"
if (!sheet %in% readxl::excel_sheets(ged_path)) stop("UCDP workbook is missing sheet: ", sheet)
hdr <- names(readxl::read_excel(ged_path, sheet = sheet, n_max = 0))
keep <- c("id", "year", "active_year", "type_of_violence", "where_prec", "latitude",
          "longitude", "event_clarity", "date_prec", "date_start", "date_end", "best")
missing_fields <- setdiff(keep, hdr)
if (length(missing_fields)) stop("UCDP workbook is missing fields: ",
  paste(missing_fields, collapse = ", "))
types <- ifelse(hdr %in% keep, "numeric", "skip")
types[hdr == "active_year"] <- "logical"
types[hdr %in% c("date_start", "date_end")] <- "date"
message("Reading UCDP events directly from the raw Excel workbook")
e <- as.data.table(readxl::read_excel(ged_path, sheet = sheet, col_types = types))
stopifnot(nrow(e)==417968L,!anyDuplicated(e$id))
e[,month:=format(as.Date(date_start),"%Y-%m")]
global<-e[,.(ucdp_events=.N,ucdp_deaths=sum(best,na.rm=TRUE),ucdp_state_events=sum(type_of_violence==1L),ucdp_nonstate_events=sum(type_of_violence==2L),ucdp_onesided_events=sum(type_of_violence==3L)),by=month]
grid<-data.table(month=format(seq(as.Date(paste0(min(e$year),"-01-01")),as.Date(paste0(max(e$year),"-12-01")),by="month"),"%Y-%m"))
global<-merge(grid,global,by="month",all.x=TRUE);for(v in setdiff(names(global),"month"))set(global,which(is.na(global[[v]])),v,0)
saveRDS(global,file.path(out,"approved_ucdp_global_month.rds"))
rm(e); invisible(gc(verbose = FALSE))

# COVID monthly summaries are computed from the CSV inside the approved ZIP only.
zip<-sources[grepl("OxCGRT.*[.]zip$",file),read_path];member<-"covid-policy-dataset-main/data/OxCGRT_compact_national_v1.csv"
td<-tempfile("approved_covid_");dir.create(td);unzip(zip,files=member,exdir=td)
daily<-fread(file.path(td,member),select=c("CountryName","CountryCode","RegionCode","Jurisdiction","Date","StringencyIndex_Average","GovernmentResponseIndex_Average","ContainmentHealthIndex_Average","EconomicSupportIndex"))
daily<-daily[Jurisdiction=="NAT_TOTAL"&(is.na(RegionCode)|RegionCode=="")]
daily[,month:=format(as.Date(as.character(Date),"%Y%m%d"),"%Y-%m")]
cv<-c("StringencyIndex_Average","GovernmentResponseIndex_Average","ContainmentHealthIndex_Average","EconomicSupportIndex")
covid<-daily[,lapply(.SD,function(x)if(all(is.na(x)))NA_real_ else mean(x,na.rm=TRUE)),by=.(CountryName,CountryCode,month),.SDcols=cv]
saveRDS(covid,file.path(out,"approved_covid_country_month.rds"))
stopifnot(startsWith(normalizePath(td,winslash="/"),paste0(normalizePath(tempdir(),winslash="/"),"/")))
unlink(td,recursive=TRUE)

