# Open Retail_forecasting.Rproj, then source("run_project.R").
# Command line: Rscript --vanilla run_project.R
local({
  origin <- getwd()
  on.exit(setwd(origin), add=TRUE)
  files <- as.character(unlist(lapply(sys.frames(), function(f) f$ofile)))
  cli <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value=TRUE))
  entry <- c(files[basename(files)=="run_project.R"],cli)
  if(length(entry)) setwd(dirname(normalizePath(tail(entry,1),mustWork=TRUE)))
  packages <- c("data.table","readxl","forecast","jsonlite","digest","ggplot2")
  missing <- packages[!vapply(packages,requireNamespace,logical(1),quietly=TRUE)]
  if(length(missing)) stop("Install required packages first: ",paste(missing,collapse=", "))
  suppressPackageStartupMessages(invisible(lapply(packages,library,character.only=TRUE)))
  setDTthreads(2L); set.seed(20261103)
  for(d in c("data/processed","results","results/figures")) dir.create(d,recursive=TRUE,showWarnings=FALSE)
  write_json(list(status="running"),"results/run_status.json",auto_unbox=TRUE)
  research_environment <- environment()
  for(script in c("01_prepare_data.R","02_forecast.R","03_supporting_analysis.R","04_results.R")) {
    message("Running ",script)
    tryCatch(source(file.path("scripts",script),local=research_environment,encoding="UTF-8"),error=function(e) {
      write_json(list(status="failed",step=script,error=conditionMessage(e)),
                 "results/run_status.json",auto_unbox=TRUE,pretty=TRUE)
      stop(conditionMessage(e),call.=FALSE)
    })
  }
  capture.output(sessionInfo(),file="results/session_info.txt")
  write_json(list(status="complete",completed=format(Sys.time(),tz="UTC",usetz=TRUE),
    evaluation="Retrospective one-month forecasts; 2024-2025 was previously inspected",
    news_integration=FALSE),"results/run_status.json",auto_unbox=TRUE,pretty=TRUE)
  message("Complete. Open README.html and results/analysis.html.")
})
