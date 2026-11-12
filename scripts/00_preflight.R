if (!dir.exists(config$paths$raw)) {
  stop("The raw-data folder is missing.", call. = FALSE)
}

message("Raw-data folder found.")

raw_files <- list.files(
  path = config$paths$raw,
  pattern = "\\.(xlsx|zip)$",
  ignore.case = TRUE
)

raw_files <- raw_files[!startsWith(raw_files, "~$")]

print(raw_files)

if (length(raw_files) != config$sources$expected_count) {
  stop(
    "Expected ", config$sources$expected_count,
    " source files, but found ", length(raw_files), ".",
    call. = FALSE
  )
}

message("Source-file count is correct.")

for (prefix in config$sources$expected_prefixes) {
  
  matches <- sum(startsWith(raw_files, prefix))
  
  if (matches != 1L) {
    stop(
      "Expected exactly one file beginning with: ", prefix,
      ". Found: ", matches, ".",
      call. = FALSE
    )
  }
}

message("All expected source filenames were found.")

source_list <- data.frame(
  file = raw_files,
  read_path = file.path(config$paths$raw, raw_files),
  stringsAsFactors = FALSE
)

print(source_list)

for (i in seq_len(nrow(source_list))) {
  
  file_name <- source_list$file[i]
  file_path <- source_list$read_path[i]
  
  if (grepl("\\.xlsx$", file_name, ignore.case = TRUE)) {
    
    sheets <- readxl::excel_sheets(file_path)
    
    if (length(sheets) == 0L) {
      stop("Workbook has no sheets: ", file_name, call. = FALSE)
    }
    
    # Select the expected sheet for each Eurostat workbook.
    if (!startsWith(file_name, "UCDP") &&
        file_name != "project_data_sources.xlsx") {

      expected_sheet <- config$sources$eurostat_sheet

      if (file_name == "Headline inflation.xlsx") {
        expected_sheet <- config$sources$headline_inflation_sheet
      }

      if (file_name == "Unemployment.xlsx") {
        expected_sheet <- config$sources$unemployment_sheet
      }

      if (startsWith(file_name, "(new)Gross domestic product (GDP)")) {
        expected_sheet <- config$sources$gdp_sheet
      }

      if (!(expected_sheet %in% sheets)) {
        stop(
          "Expected sheet ", expected_sheet,
          " missing in: ", file_name,
          call. = FALSE
        )
      }
    }

    message("Excel structure checked: ", file_name)
    
  } else if (grepl("\\.zip$", file_name, ignore.case = TRUE)) {
    
    members <- utils::unzip(file_path, list = TRUE)$Name
    
    if (!(config$sources$covid_member %in% members)) {
      stop(
        "Expected national COVID CSV missing from: ",
        file_name,
        call. = FALSE
      )
    }
    
    message("ZIP structure checked: ", file_name)
  }
}

# Check the annual UCDP CSV -----------------------------------------------

annual_file <- "data/raw/ucdp/annual/GEDEvent_v23_1.csv"

if (!file.exists(annual_file)) {
  stop(
    "Annual UCDP file missing: ",
    annual_file,
    call. = FALSE
  )
}

message("Annual UCDP CSV found.")


# Check the monthly Candidate CSVs ----------------------------------------

candidate_names <- c(
  paste0("GEDEvent_v22_0_", 11:12, ".csv"),
  paste0("GEDEvent_v23_0_", 1:12, ".csv"),
  paste0("GEDEvent_v24_0_", 1:12, ".csv"),
  paste0("GEDEvent_v25_0_", 1:12, ".csv")
)

candidate_paths <- file.path(
  "data/raw/ucdp/candidate",
  candidate_names
)

missing_candidates <- candidate_names[
  !file.exists(candidate_paths)
]

if (length(missing_candidates) > 0) {
  stop(
    "Missing UCDP Candidate files: ",
    paste(missing_candidates, collapse = ", "),
    call. = FALSE
  )
}

message("All 38 monthly UCDP Candidate CSVs found.")

message("Preflight passed: expected files and internal structures found.")
message("Data values, units, coverage, and timing have not yet been checked.")