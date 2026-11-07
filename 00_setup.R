# Run in RStudio after opening Retail_forecasting.Rproj.
# stop if not ran from the Rproj or run_project.R script doesn't exist
if (!file.exists("Retail_forecasting.Rproj") || !file.exists("run_project.R"))
  stop("Open Retail_forecasting.Rproj in RStudio before running the setup script.", call. = FALSE)

# defining the needed R packages
required <- c("data.table", "readxl", "forecast", "ggplot2", "jsonlite")

# use requireNamespace to check if packs are installed
installed <- vapply(required, requireNamespace, logical(1), quietly = TRUE)

# make a table with no row numbers to display if required packs are installed
print(data.frame(package = required, installed = installed), row.names = FALSE)

# if any give FALSE when defining installed, it tells you which to install
if (any(!installed)) {
  cat("\nInstall missing packages with:\n")
  cat("install.packages(c(", paste(sprintf('"%s"', required[!installed]), collapse = ", "), "))\n", sep = "")
# else a success message is shown
} else cat("\nAll required packages are installed.\n")
        cat("R version:", R.version.string, "\n")
        cat("Once packages are installed: source('run_project.R')\n")
