if (!file.exists("Retail_forecasting.Rproj") ||
    !dir.exists("scripts")) {
  
  stop(
    "Open Retail_forecasting.Rproj before running this script.",
    call. = FALSE
  )
}

required_packages <- c(
  "data.table",
  "readxl"
)

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

if (any(!installed)) {
  
  missing_packages <- required_packages[!installed]
  
  message("Installing missing packages:")
  print(missing_packages)
  
  install.packages(
    missing_packages,
    repos = "https://cloud.r-project.org"
  )
  
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

message("All required packages are installed.")
message("R version: ", R.version.string)