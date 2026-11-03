# Discover the 13 source datasets from the actual original files.
# This is intentionally independent of raw_sources.csv: filenames can contain commas.
locate_raw_sources <- function(project_root) {
  raw_dir <- file.path(project_root, "data", "raw")
  if (!dir.exists(raw_dir))
    stop("Raw-data directory is missing: ", raw_dir, call. = FALSE)
  filenames <- list.files(raw_dir, pattern = "\\.(xlsx|zip)$",
                          ignore.case = TRUE, full.names = FALSE)
  # Ignore temporary Excel lock files left behind while a workbook is open.
  filenames <- sort(filenames[!startsWith(filenames, "~$")])
  if (length(filenames) != 13L || anyDuplicated(filenames))
    stop("Expected 13 original Excel/ZIP datasets in data/raw/, found ",
         length(filenames), ". Check that all source files are extracted and ",
         "that no additional Excel/ZIP files were added.", call. = FALSE)

  expected <- c(
    "(new)Gini coefficient of equivalised disposable income",
    "(new)Gross domestic product (GDP)",
    "Annual energy inflation rate",
    "Annual food inflation rate",
    "Annual headline inflation rate",
    "Consumers confidence indicator",
    "Household final consumption expenditure",
    "Key indicators for sector accounts",
    "Oxford Covid-19 Government Response Tracker",
    "Retail trade volume of sales",
    "UCDP Georeferenced Event Dataset",
    "Unemployment by sex and age",
    "project_data_sources.xlsx"
  )
  counts <- vapply(expected, function(prefix)
    sum(startsWith(filenames, prefix)), integer(1))
  if (any(counts != 1L))
    stop("Raw dataset missing or duplicated: ",
         paste(expected[counts != 1L], collapse = "; "),
         ". Do not rename the 13 original files.", call. = FALSE)
  data.frame(file = filenames, read_path = file.path(raw_dir, filenames),
             stringsAsFactors = FALSE)
}
