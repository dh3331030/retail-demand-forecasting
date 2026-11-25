# Run from the extracted diagnostic folder. No packages are installed or updated.
# This reproduces two January 2023 fits with the original fixed settings.
needed <- c("data.table", "ranger")
missing <- needed[!vapply(needed, requireNamespace, logical(1), quietly = TRUE)]
if (length(missing)) stop("Missing installed packages: ", paste(missing, collapse = ", "),
                          ". Use the original project environment for this diagnostic.")
if (!file.exists("forest_fixture.rds"))
  stop("Set R's working directory to the extracted diagnostic folder, then run this file.")
library(data.table)
fixture <- readRDS("forest_fixture.rds")
training <- as.data.table(fixture$training)
targets <- as.data.table(fixture$targets)
reference <- fread("reference_predictions.csv")
dir.create("diagnostic_output", showWarnings = FALSE)

formulas <- list(
  forest_without_conflict = retail_growth ~ country + retail_growth_lag3 +
    inflation_lag2 + unemployment_lag3 + gdp_available,
  forest_reduced_without_gdp = retail_growth ~ country + retail_growth_lag3 +
    inflation_lag2 + unemployment_lag3
)
results <- list()
counts <- list()
capture_differences <- numeric()
for (name in names(formulas)) {
  args <- list(formula = formulas[[name]], data = training,
               num.trees = 500L, mtry = 2L, max.depth = 5L,
               min.node.size = 40L, min.bucket = 20L, splitrule = "variance",
               replace = TRUE, sample.fraction = 1,
               respect.unordered.factors = "partition",
               seed = 20565L, num.threads = 1L, oob.error = FALSE)
  ordinary_fit <- do.call(ranger::ranger, args)
  recorded_fit <- do.call(ranger::ranger, c(args, list(keep.inbag = TRUE)))
  ordinary <- as.numeric(predict(ordinary_fit, data = targets)$predictions)
  recorded <- as.numeric(predict(recorded_fit, data = targets)$predictions)
  capture_differences[name] <- max(abs(ordinary - recorded))
  results[[name]] <- data.table(model = name, country = as.character(targets$country),
                                month = as.character(targets$month), prediction = ordinary)
  counts[[name]] <- recorded_fit$inbag.counts
}
actual <- rbindlist(results)
comparison <- merge(actual, reference, by = c("model", "country", "month"), sort = TRUE)
comparison[, difference_from_published := prediction - published_prediction]
comparison[, difference_from_windows_reference := prediction - windows_reference_prediction]
fwrite(comparison, "diagnostic_output/predictions.csv")
saveRDS(counts, "diagnostic_output/inbag_counts.rds")
writeLines(c(capture.output(sessionInfo()), "", capture.output(str(R.version)), "",
             paste("ranger version:", as.character(packageVersion("ranger"))),
             paste("ranger Built:", packageDescription("ranger")$Built),
             paste("data.table version:", as.character(packageVersion("data.table"))),
             paste("Fixture MD5:", unname(tools::md5sum("forest_fixture.rds")))),
           "diagnostic_output/session_info.txt")

lines <- c("Original-code fixed-seed January 2023 diagnostic",
           paste("Training rows:", nrow(training)), paste("Forecast rows:", nrow(targets)),
           paste("Seed:", 20565L),
           paste("Maximum difference from published predictions:",
                 format(max(abs(comparison$difference_from_published)), digits = 17)),
           paste("Maximum difference from Windows reference predictions:",
                 format(max(abs(comparison$difference_from_windows_reference)), digits = 17)),
           paste("Maximum effect of keeping bootstrap counts:",
                 format(max(capture_differences), digits = 17)))
if (file.exists("reference_inbag_counts.rds")) {
  reference_counts <- readRDS("reference_inbag_counts.rds")
  for (name in names(counts)) {
    current_values <- unlist(counts[[name]], use.names = FALSE)
    reference_values <- unlist(reference_counts[[name]], use.names = FALSE)
    if (length(current_values) != length(reference_values))
      stop("Bootstrap-count dimensions differ for ", name)
    difference <- max(abs(current_values - reference_values))
    lines <- c(lines, paste(name, "bootstrap counts equal to Windows reference:",
                            isTRUE(all.equal(current_values, reference_values, tolerance = 0,
                                             check.attributes = FALSE))),
               paste(name, "largest bootstrap-count difference:", difference))
  }
}
lines <- c(lines, "",
           "Different bootstrap counts identify a difference in random sampling for this fixture.",
           "They do not, by themselves, identify whether package version or compiler/library caused it.",
           "Equal bootstrap counts with different predictions point to a later fitting difference.",
           "This small diagnostic does not replace the complete project rerun.")
writeLines(lines, "diagnostic_output/comparison.txt")
cat(paste(lines, collapse = "\n"), "\n")
cat("Please return the complete diagnostic_output folder. No project files were changed.\n")
