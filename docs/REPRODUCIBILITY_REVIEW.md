# Reproducibility and submission review

Review of the full `Archive.zip` supplied on 13 November 2026. This is a documentation and arithmetic audit, not an independent end-to-end R rerun.

## Checks completed

- Inspected the actual configuration, master runners and all numbered R scripts in the uploaded folder.
- Identified all 45 raw inputs and their exact relative paths. Recorded SHA-256 hashes and sizes, plus the annual CSV member hash.
- Extracted Eurostat dataset links, custom extract IDs, selected sheets, filters and download/update timestamps from the workbook XML. This avoids inferring source identities from renamed filenames.
- Checked the official UCDP historical download page, version-specific Candidate codebooks and official OxCGRT repository.
- Read all 38 Candidate CSVs with their actual schemas. Found 77,952 source records, no duplicate event IDs within a release, and the two documented missing-coordinate records. January 2024 is headerless. October 2024 has an additional index header but retains the named required columns.
- Recomputed overall MAE and RMSE from all 1,560 validation forecasts across 26 models and all 720 test forecasts across six models.
- Recomputed country-level and, for testing, year-level metrics from saved forecasts.
- Verified forecast errors equal actual minus prediction and checked unique model/country/month keys.
- Verified the first logged training windows: January 2023 through October 2022 with 440 observations, January 2024 through October 2023 with 500 observations for fitted methods.
- Verified 03a is not called automatically by the submitted 03 script. The README includes its separate call.
- Verified the freeze already exists and the freeze script refuses to overwrite it. The README skips it in the normal reproduction path.

The supplied score arithmetic agrees with recomputed values within 1e-12. Full-precision audit details are in `reproducibility_checks.json`.

## What was changed

Only documentation was added, and PROJECT_GUIDE.txt was replaced with a short pointer to the current README. Original modeling scripts, raw files, processed RDS files, result CSVs and frozen settings were not changed. The downloadable package is a small documentation overlay, not a second copy of the full raw-data archive.

## What remains to complete before submission

1. Run the README Quick start once in the intended R environment. R is unavailable in the reviewing environment, so an independent refit has not been performed here.
2. Save `sessionInfo.txt` and `package_versions.csv` using the README commands. The archive contains no dependency lockfile or complete software-version record. RDS serialization headers report writer R 4.6.2, which is not a complete package/environment specification.
3. Keep the exact raw snapshots or distribute the source register and enough version information to restore them. Current Eurostat downloads can differ from the supplied snapshots.
4. Add the group's technical report PDF and slide deck. Suggested destinations: `report/technical_report.pdf` and `presentation/presentation.pptx` (or the required presentation format).
5. Add the R code used to generate any final figures. No plot-export code or exported report figures are present in the supplied archive.
6. Complete the contribution note with actual names/tasks. The template is intentionally unfinished.

## Interpretation constraints to preserve

This is retrospective chronological holdout evaluation with revised macro data and conventional availability rules, not exact historical-vintage reconstruction. Full-2023 validation outcomes were not published for the earliest 2024 origins. Annual GED and Candidate records have different completeness/revision properties. No significance or causal-identification analysis was completed. Do not present the small RMSE differences as statistically significant.

The validation-selected primary method is zero growth. Country mean is the best-performing prespecified test comparator. Keep that distinction in the report rather than relabeling the test winner as a preselected model.
