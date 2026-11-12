# 1. Check that we are working in the project folder ------------------------

if (!file.exists("Retail_forecasting.Rproj") ||
    !dir.exists("scripts")) {
  
  stop(
    "Open Retail_forecasting.Rproj before running this script.",
    call. = FALSE
  )
}


# 2. List the required packages --------------------------------------------

# Packages required by the currently implemented scripts.
# Add modeling packages when we implement the corresponding models.

required_packages <- c(
  "data.table",
  "readxl"
)


# 3. Check which packages are installed ------------------------------------

installed <- vapply(
  required_packages,
  requireNamespace,
  logical(1),
  quietly = TRUE
)

package_status <- data.frame(
  package = required_packages,
  installed = installed
)

print(package_status, row.names = FALSE)


# 4. Report missing packages ----------------------------------------------

# 4. Install missing packages ---------------------------------------------

if (any(!installed)) {
  
  missing_packages <- required_packages[!installed]
  
  message("Installing missing packages:")
  print(missing_packages)
  
  install.packages(
    missing_packages,
    repos = "https://cloud.r-project.org"
  )
  
  # Check that installation succeeded.
  installed <- vapply(
    required_packages,
    requireNamespace,
    logical(1),
    quietly = TRUE
  )
  
  if (any(!installed)) {
    stop(
      "Could not install: ",
      paste(required_packages[!installed], collapse = ", "),
      ". Check the installation messages above.",
      call. = FALSE
    )
  }
}


# 5. Confirm completion ----------------------------------------------------

message("All required packages are installed.")
message("R version: ", R.version.string)