# This file verifies the structure
# Run after setup and configuration.

#find excel and ZIP inputs in the config raw-data folder
raw_files <- list.files(config$paths$raw, pattern = "\\.(xlsx|zip)$",
                        ignore.case = TRUE)

#exclude tmp Excel lock files(they start with ~$ at least on windows)
#we ran into this because we forgot some data files open while running scripts
raw_files <- raw_files[!startsWith(raw_files, "~$")]

#STOP1 to check if nr. of source files matches the config
if (length(raw_files) != config$sources$expected_count) {
  stop("Expected ", config$sources$expected_count,
       " top-level Excel/ZIP files; found ", length(raw_files), ".")
}

#loop for each source that requires exactly one raw file matching the prefix
for (prefix in config$sources$expected_prefixes) {
  if (sum(startsWith(raw_files, prefix)) != 1) {
    stop("Expected exactly one source beginning with: ", prefix)
  }
}


#inspects each source file, constructs its full path for both excel and ZIP
#STOP2 when something is missing
for (filename in raw_files) {
  path <- file.path(config$paths$raw, filename)
  if (grepl("\\.xlsx$", filename, ignore.case = TRUE)) {
    sheet <- config$sources$eurostat_sheet
    if (filename == "Headline inflation.xlsx") sheet <- config$sources$headline_inflation_sheet
    if (filename == "Unemployment.xlsx") sheet <- config$sources$unemployment_sheet
    if (startsWith(filename, "(new)Gross domestic product (GDP)")) sheet <- config$sources$gdp_sheet
    if (!(sheet %in% readxl::excel_sheets(path))) {
      stop("Expected ", sheet, " in ", filename)
    }
  } else if (startsWith(filename, "Oxford Covid-19")) {
    if (!(config$sources$covid_member %in% unzip(path, list = TRUE)$Name)) {
      stop("Expected COVID CSV missing from ZIP.")
    }
  }
}

#build path to the separately stored UCDP archive
annual_zip <- file.path(config$paths$raw, "ucdp/annual/GEDEvent_v23_1.csv.zip")

#STOP3 if archive doesn't exist
if (!file.exists(annual_zip)) stop("Annual GED ZIP missing: ", annual_zip)

#read archive's internal filenames
members <- unzip(annual_zip, list = TRUE)$Name

#select only CSV files. excludes macOS metadata for running on mac
csv_members <- members[grepl("\\.csv$", members, ignore.case = TRUE) &
                         !grepl("__MACOSX/", members)]

#STOP4 if archive has not only 1 CSV
if (length(csv_members) != 1) stop("Annual GED ZIP must contain exactly one CSV.")

#success message after checks pass
message("Preflight passed: top-level sources and annual GED ZIP checked.")
