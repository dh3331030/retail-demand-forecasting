# 00_preflight.R - Preliminary source-file checks
#
# Checks that the expected input files and internal file structures exist.
# Detailed checks of values, units, and coverage belong in data preparation.
#
# Before running this script, run:
# source("00_setup.R")
# source("scripts/00_config.R")


# Check that the raw-data folder exists

if (!dir.exists(config$paths$raw)) {
  stop("The raw-data folder is missing.", call. = FALSE)
}

message("Raw-data folder found.")

# Identify the Excel and ZIP files in the raw-data folder

raw_files <- list.files(
  path = config$paths$raw,
  pattern = "\\.(xlsx|zip)$",
  ignore.case = TRUE
)

# Exclude temporary files created when an Excel workbook is open
raw_files <- raw_files[!startsWith(raw_files, "~$")]

print(raw_files)

# Check that the number of source files matches the configuration

if (length(raw_files) != config$sources$expected_count) {
  stop(
    "Expected ", config$sources$expected_count,
    " source files, but found ", length(raw_files), ".",
    call. = FALSE
  )
}

message("Source-file count is correct.")

# Check that each expected source matches exactly one filename

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

# Create a source-file table for subsequent checks

source_list <- data.frame(
  file = raw_files,
  read_path = file.path(config$paths$raw, raw_files),
  stringsAsFactors = FALSE
)

print(source_list)

# Check that Excel workbooks contain sheets

# Check Excel sheet names and the contents of the COVID ZIP

for (i in seq_len(nrow(source_list))) {
  
  file_name <- source_list$file[i]
  file_path <- source_list$read_path[i]
  
  
  # Excel workbooks -------------------------------------------------------
  
  if (grepl("\\.xlsx$", file_name, ignore.case = TRUE)) {
    
    sheets <- readxl::excel_sheets(file_path)
    
    if (length(sheets) == 0L) {
      stop("Workbook has no sheets: ", file_name, call. = FALSE)
    }
    
    # UCDP workbook
    if (startsWith(file_name, "UCDP")) {
      
      if (!(config$sources$ucdp_sheet %in% sheets)) {
        stop(
          "Expected UCDP sheet missing: ",
          config$sources$ucdp_sheet,
          call. = FALSE
        )
      }
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
    
    
    # COVID ZIP -------------------------------------------------------------
    
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


# Report completion -------------------------------------------------------

message("Preflight passed: expected files and internal structures found.")
message("Data values, units, coverage, and timing have not yet been checked.")