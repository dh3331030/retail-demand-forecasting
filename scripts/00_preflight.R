# checks for the original datasets (filenames and worksheets).



# STEP 1: Locate the project root
# automatically detect the directory of the currently running script
source_script_files <- unlist(lapply(sys.frames(), function(fr) fr$ofile),
                              use.names = FALSE)
# keeps only the paths whose filename is exactly "00_preflight.R"
source_script_files <- source_script_files[
  basename(source_script_files) == "00_preflight.R"
]

# if source_script_files contains a path, move up two folders
# and add R's current working drive
project_candidates <- c(
  if (length(source_script_files))
    dirname(dirname(normalizePath(tail(source_script_files, 1L),
                                  winslash = "/", mustWork = TRUE))),
  getwd()
)
# remove duplicates if getwd() and the script folder are the same
project_candidates <- unique(project_candidates)
# check if file Rproj and directory data/raw exist there
project_candidates <- project_candidates[
  file.exists(file.path(project_candidates, "Retail_forecasting.Rproj")) &
    dir.exists(file.path(project_candidates, "data", "raw"))
]
# if project_candidates is 0, display message
if (!length(project_candidates))
  stop("Cannot locate the project folder. Open Retail_forecasting.Rproj in ",
       "RStudio, or source this file using its absolute path.", call. = FALSE)
# otherwise define project_root as the first integer candidate
project_root <- project_candidates[1L]



# STEP 2: Defining the function
# look inside the project root
# for the actual database files downloaded by us. (covid ZIP too)
locate_raw_sources <- function(project_root) {
  raw_dir <- file.path(project_root, "data", "raw")
  if (!dir.exists(raw_dir))
    stop("Raw-data directory is missing: ", raw_dir, call. = FALSE)
  
  filenames <- list.files(raw_dir, pattern = "\\.(xlsx|zip)$",
                          ignore.case = TRUE, full.names = FALSE)
  # Ignore temporary Excel lock files left behind while a workbook is open
  # because when Excel has a workbook open, 
  # it may create a temporary file whose name starts with ~$
  filenames <- sort(filenames[!startsWith(filenames, "~$")])
  if (length(filenames) != 13L || anyDuplicated(filenames))
    #error message
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
  # for each item in expected, run the function with that item as prefix.
  counts <- vapply(expected, function(prefix)
    # check if every filename begins with the prefix, and return (1)TRUE if so
    sum(startsWith(filenames, prefix)), integer(1))
  # if any not TRUE, displays error with the wrong one
  if (any(counts != 1L))
    stop("Raw dataset missing or duplicated: ",
         paste(expected[counts != 1L], collapse = "; "),
         ". Do not rename the 13 original files.", call. = FALSE)
  #create a table with one row per file, keeping text columns as text
  data.frame(file = filenames, read_path = file.path(raw_dir, filenames),
             stringsAsFactors = FALSE)
}



# STEP 3: Call the function
# define source_list as the raw sources inside the project_root path
source_list <- locate_raw_sources(project_root)
# define raw_paths as only the read_path ($)column from the source_list table 
raw_paths <- source_list$read_path



# STEP 4: Check dependencies and validate datasets
# if readxl pckg is not installed, display error
if (!requireNamespace("readxl", quietly = TRUE))
  stop("Missing required package 'readxl'. Run source('00_setup.R') ",
       "from the project directory.", call. = FALSE)

# loop to check basic readability and expected sheets + covid ZIP check
for (i in seq_along(raw_paths)) {
  # define file's full path
  f <- raw_paths[i]
  # define the file's name
  nm <- source_list$file[i]
  #check whether the f ends in .xlsx, and if so handle it as excel
  if (grepl("[.]xlsx$", nm, ignore.case = TRUE)) {
    # list sheet names. tryCatch is used to catch error if workbook can't open 
    sheets <- tryCatch(readxl::excel_sheets(f), error = function(e)
      stop("Cannot open original Excel workbook: ", nm, "\n",
           conditionMessage(e), call. = FALSE))
    #if the xlsx f has 0 sheets
    if (!length(sheets)) 
      stop("Excel workbook has no sheets: ", nm, call. = FALSE)
    # if xlsx f starts with UCDP but it's not the right version or no event sheet
    if (startsWith(nm, "UCDP") && !"GEDEvent_v26_1" %in% sheets)
      stop("UCDP workbook lacks its GEDEvent_v26_1 sheet.", call. = FALSE)
    # if xlsx f is not UCDP nor the sources excel, check if "Sheet 1" exists
    # because Eurostat excels are the only ones using this sheet name for data.
    if (!startsWith(nm, "UCDP") && nm != "project_data_sources.xlsx" &&
        !"Sheet 1" %in% sheets)
      stop("Eurostat workbook lacks Sheet 1: ", nm, call. = FALSE)
  # else if it's not excel file, check if it's a ZIP
  } else if (grepl("[.]zip$", nm, ignore.case = TRUE)) {
    # if it can be unzipped
    members <- tryCatch(utils::unzip(f, list = TRUE)$Name, error = function(e)
      stop("Cannot open original COVID ZIP: ", nm, "\n",
           conditionMessage(e), call. = FALSE))
    # if it lacks the expected dataset inside the ZIP
    if (!"covid-policy-dataset-main/data/OxCGRT_compact_national_v1.csv" %in% members)
      stop("COVID ZIP lacks the expected national CSV.", call. = FALSE)
  # else stop if it's neither an xlsx nor a ZIP type file  
  } else stop("Unexpected source file extension: ", nm, call. = FALSE)
}

# STEP 5: Report success
# if nothing made the script stop, display this message
message("PASS: all ", length(raw_paths), " original source files are present and readable in ",
        file.path(project_root, "data", "raw"))

