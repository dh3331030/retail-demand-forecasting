# Run in RStudio after opening Retail_forecasting.Rproj.
if (!file.exists("Retail_forecasting.Rproj") || !file.exists("run_project.R"))
  stop("Open Retail_forecasting.Rproj in RStudio before running the setup script.", call. = FALSE)
required <- c("data.table", "readxl", "forecast", "ggplot2", "jsonlite")
installed <- vapply(required, requireNamespace, logical(1), quietly = TRUE)
print(data.frame(package = required, installed = installed), row.names = FALSE)
if (any(!installed)) {
  cat("\nInstall missing packages with:\n")
  cat("install.packages(c(", paste(sprintf('"%s"', required[!installed]), collapse = ", "), "))\n", sep = "")
} else cat("\nAll required packages are installed.\n")
cat("R version:", R.version.string, "\n")
cat("Once packages are installed: source('run_project.R')\n")
