# Run the entire analysis directly from the original Excel / ZIP datasets.
# RStudio: open Retail_forecasting.Rproj; source("00_setup.R"); source("run_project.R")
# Terminal: Rscript --vanilla run_project.R [--check]
run_retail_project <- function() {
  original_wd <- getwd()
  on.exit(setwd(original_wd), add = TRUE)
  frames <- unlist(lapply(sys.frames(), function(fr) fr$ofile), use.names = FALSE)
  cli <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE))
  paths <- c(frames[basename(frames) == "run_project.R"], cli)
  if (length(paths)) {
    root <- dirname(normalizePath(tail(paths, 1L), mustWork = TRUE))
  } else if (file.exists("Retail_forecasting.Rproj") && file.exists("scripts/01_prepare_data.R")) {
    root <- normalizePath(".", mustWork = TRUE)
  } else {
    stop("Cannot find the project. Open Retail_forecasting.Rproj, then source('run_project.R'), or run Rscript /path/to/run_project.R.", call. = FALSE)
  }
  setwd(root)

  args <- commandArgs(trailingOnly = TRUE)
  if (length(args) > 1L || (length(args) == 1L && !identical(args, "--check")))
    stop("Usage: Rscript --vanilla run_project.R [--check]", call. = FALSE)
  check_only <- identical(args, "--check")
  needed <- c("data.table", "readxl", "jsonlite")
  if (!check_only) needed <- c(needed, "forecast", "ggplot2")
  missing <- needed[!vapply(needed, requireNamespace, logical(1), quietly = TRUE)]
  if (length(missing)) stop("Missing R packages: ", paste(missing, collapse = ", "),
    "\nInstall with: install.packages(c(", paste(sprintf('"%s"', missing), collapse = ", "), "))",
    "\nNo dependencies are installed automatically.", call. = FALSE)

  suppressPackageStartupMessages(library("data.table"))
  suppressPackageStartupMessages(library("readxl"))
  if (!check_only) {
    suppressPackageStartupMessages(library("forecast"))
    suppressPackageStartupMessages(library("ggplot2"))
  }
  data.table::setDTthreads(2L)
  set.seed(20261103)
  for (d in c("data/processed", "results", "results/figures"))
    dir.create(d, recursive = TRUE, showWarnings = FALSE)

  stage <- "preflight"
  write_status <- function(state, description = "") {
    jsonlite::write_json(list(status = state, input = "original local raw datasets",
      stage = stage, at = format(Sys.time(), tz = "UTC", usetz = TRUE),
      detail = description), "results/run_status.json", auto_unbox = TRUE, pretty = TRUE)
  }
  write_status("running")
  tryCatch({
    source("scripts/00_preflight.R", local = environment(), encoding = "UTF-8")
    if (check_only) {
      write_status("checked", "All 13 raw Excel/ZIP sources are present and readable; models were not fitted")
      message("PASS: all 13 original raw datasets are present and their file formats can be opened.")
      message("To rebuild the analysis, run: Rscript --vanilla run_project.R")
    } else {
      for (script in c("01_prepare_data.R", "02_forecast.R", "03_supporting_analysis.R", "04_results.R")) {
        stage <- script
        message("Running ", script, " using raw-source data")
        source(file.path("scripts", script), local = environment(), encoding = "UTF-8")
      }
      stage <- "tests/check_outputs.R"
      source("tests/check_outputs.R", local = environment(), encoding = "UTF-8")
      capture.output(sessionInfo(), file = "results/session_info.txt")
      stage <- "finished"
      write_status("complete", "Raw Excel/ZIP sources re-read and derived observations, forecasts and reports rebuilt")
      message("Complete. Open results/analysis.html and results/model_comparison.csv")
    }
  }, error = function(e) {
    write_status("failed", conditionMessage(e))
    stop("Project failed in ", stage, ": ", conditionMessage(e), call. = FALSE)
  })
  invisible(TRUE)
}
run_retail_project()
rm(run_retail_project)
