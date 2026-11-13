# Structural checks before preparation. Run after setup and configuration.
raw_files <- list.files(config$paths$raw, pattern = "\\.(xlsx|zip)$",
                        ignore.case = TRUE)

raw_files <- raw_files[!startsWith(raw_files, "~$")]

if (length(raw_files) != config$sources$expected_count) {
  stop("Expected ", config$sources$expected_count,
       " top-level Excel/ZIP files; found ", length(raw_files), ".")
}

for (prefix in config$sources$expected_prefixes) {
  if (sum(startsWith(raw_files, prefix)) != 1) {
    stop("Expected exactly one source beginning with: ", prefix)
  }
}

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

annual_zip <- file.path(config$paths$raw, "ucdp/annual/GEDEvent_v23_1.csv.zip")

if (!file.exists(annual_zip)) stop("Annual GED ZIP missing: ", annual_zip)

members <- unzip(annual_zip, list = TRUE)$Name

csv_members <- members[grepl("\\.csv$", members, ignore.case = TRUE) &
                         !grepl("__MACOSX/", members)]

if (length(csv_members) != 1) stop("Annual GED ZIP must contain exactly one CSV.")

message("Preflight passed: top-level sources and annual GED ZIP checked.")
