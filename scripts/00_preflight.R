# Validate the original Excel and ZIP datasets
# Can be sourced directly by absolute path from any RStudio working directory.
source_script_files <- unlist(lapply(sys.frames(), function(fr) fr$ofile),
                              use.names = FALSE)
source_script_files <- source_script_files[basename(source_script_files) == "00_preflight.R"]
project_candidates <- c(
  if (length(source_script_files))
    dirname(dirname(normalizePath(tail(source_script_files, 1L),
                                  winslash = "/", mustWork = TRUE))),
  getwd()
)
project_candidates <- unique(project_candidates)
project_candidates <- project_candidates[
  file.exists(file.path(project_candidates, "Retail_forecasting.Rproj")) &
    dir.exists(file.path(project_candidates, "data", "raw"))
]
if (!length(project_candidates))
  stop("Cannot locate the project folder. Open Retail_forecasting.Rproj in ",
       "RStudio, or source this file using its absolute path.", call. = FALSE)
project_root <- project_candidates[1L]
source(file.path(project_root, "scripts", "00_raw_files.R"), local = TRUE,
       encoding = "UTF-8")
source_list <- locate_raw_sources(project_root)
raw_paths <- source_list$read_path

if (!requireNamespace("readxl", quietly = TRUE))
  stop("Missing required package 'readxl'. Run source('00_setup.R') ",
       "from the project directory.", call. = FALSE)

for (i in seq_along(raw_paths)) {
  f <- raw_paths[i]
  nm <- source_list$file[i]
  if (grepl("[.]xlsx$", nm, ignore.case = TRUE)) {
    sheets <- tryCatch(readxl::excel_sheets(f), error = function(e)
      stop("Cannot open original Excel workbook: ", nm, "\n",
           conditionMessage(e), call. = FALSE))
    if (!length(sheets)) stop("Excel workbook has no sheets: ", nm, call. = FALSE)
    if (startsWith(nm, "UCDP") && !"GEDEvent_v26_1" %in% sheets)
      stop("UCDP workbook lacks its GEDEvent_v26_1 sheet.", call. = FALSE)
    if (!startsWith(nm, "UCDP") && nm != "project_data_sources.xlsx" &&
        !"Sheet 1" %in% sheets)
      stop("Eurostat workbook lacks Sheet 1: ", nm, call. = FALSE)
  } else if (grepl("[.]zip$", nm, ignore.case = TRUE)) {
    members <- tryCatch(utils::unzip(f, list = TRUE)$Name, error = function(e)
      stop("Cannot open original COVID ZIP: ", nm, "\n",
           conditionMessage(e), call. = FALSE))
    if (!"covid-policy-dataset-main/data/OxCGRT_compact_national_v1.csv" %in% members)
      stop("COVID ZIP lacks the expected national CSV.", call. = FALSE)
  } else stop("Unexpected source file extension: ", nm, call. = FALSE)
}
message("PASS: all ", length(raw_paths), " original source files are present and readable in ",
        file.path(project_root, "data", "raw"))
