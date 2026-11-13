# Proposed technical report structure

Suggested title: **Forecasting food-retail volume growth in five European countries: macroeconomic indicators, conflict exposure and model complexity**.

Use a compact main report of approximately 8-10 pages excluding references/appendices, subject to the professor's requirements. Write connected explanations and reserve detailed model tables for an appendix. This is a structure and evidence guide, not a completed report.

## Abstract / executive summary (150-200 words)

State the question, five-country sample, target, chronological design and principal result. Country mean attained test RMSE 1.2530 versus zero growth 1.2678, an observed 1.16% reduction. The macro-only regression did not improve on country mean; the matched forest did not improve when adding weighted conflict deaths. Describe results as modest predictive differences rather than significant or causal effects.

## 1. Research question and motivation (approximately 0.75 page)

Question: Can delayed macroeconomic indicators and geographically weighted conflict exposure improve next-calendar-month forecasts of monthly food, beverages and tobacco retail-volume growth in Germany, France, Italy, Poland and Portugal?

Explain potential mechanisms as hypotheses: purchasing power, labour-market conditions, aggregate activity and geographically transmitted conflict shocks. Distinguish forecasting growth from estimating economic effects. Explain why simple benchmarks are substantive competitors. Give country/sample scope rather than implying all European retail sectors are covered.

## 2. Data and source construction (1-1.5 pages)

Introduce the four modeled Eurostat sources and UCDP sources. Use the exact export selections, adjustment status, units and snapshot dates from DATA_SOURCES.md. Describe OxCGRT as prepared but excluded, and household consumption as unused. Include a compact source table.

Explain annual GED 23.1 for training and historical Candidate records for evaluation, with the resulting measurement-quality difference. Describe date parsing, missing-coordinate exclusions and retained zero-death events. The detailed 45-file source inventory belongs in an appendix or repository.

Evidence: DATA_SOURCES.md, data_source_register.json, PREPROCESSING.md and exclusion outputs.

## 3. Prediction task and information timing (1-1.5 pages)

Define g_it = 100*log(R_it/R_i,t-1). State log-percentage-point units and the end-of-prior-month forecast origin. Show the nominal split and usable sample: training 450 rows, validation 60, testing 120. Explain why complete-case training begins in July 2015.

Include the predictor-availability table. Explain GDP quarterly carry-forward and the Candidate eligibility/latest-version/start-month sequence. Explicitly label publication timing as conservative conventions and the experiment as retrospective, using revised data. Full-2023 validation information was not available for every earliest-2024 origin.

Evidence: scripts 01/02, training logs, configuration. Suggested visual: a timeline with sample boundaries and a worked January forecast example.

## 4. Methods and model development (1.5-2 pages)

Describe benchmarks (zero, available growth and country mean), country-intercept shared-slope regression, fully country-specific slopes, regression tree, bagging and random forest. Explain the parameter-sharing trade-off and why country is categorical.

Describe the 26-specification development sequence: initial methods, four conflict alternatives in two model families, and reduced-predictor comparisons. Show the conflict weighting formula exp(-distance/h), with the weighted-deaths extension. Do not list every specification in the main text.

Explain expanding-window refitting with outcomes through t-3. Note that earlier held-out outcomes may enter later refits after eligibility, while model definitions stay fixed. State fixed initial tree/forest controls, seeds, one-thread execution and absence of a broad tuning search.

Define MAE/RMSE. RMSE is primary and MAE secondary. Explain the freeze and six finalists, with zero growth remaining the validation-selected primary method.

Evidence: validation scripts, tree settings, frozen configuration and frozen validation scores.

## 5. Results (2 pages)

### 5.1 Validation

Start with the strongest benchmark. Zero growth won RMSE in 2023. Reduced macro-only regression improved on its full regression but did not beat zero. Ensembles beat the single tree under the tested settings, without a clear overall gain over zero. Conflict improvements were small and specification-dependent. Put all 26 validation scores in an appendix.

### 5.2 Frozen holdout

Give the six-model test table, including both metrics and the primary designation. Country mean has the lowest overall MAE/RMSE. Macro-only regression is close but slightly worse than country mean, so improvement against zero alone does not establish incremental macroeconomic value. Show the observed percentage improvements with restrained precision.

### 5.3 Country and year variation

Discuss France/Germany/Portugal improvements from simple methods and Italy's different forest ranking. Poland's larger errors disproportionately influence pooled RMSE. Country mean beats zero in both years; the no-conflict forest leads 2025 RMSE but not overall. Lower errors in 2025 do not alone prove better learning.

### 5.4 Conflict's incremental value

Use the matched full-forest pair: RMSE 1.2712 without conflict versus 1.2825 with weighted deaths. Do not compare unrelated predictor sets and attribute the whole difference to conflict. State the narrower conclusion for this feature/lag/design.

Evidence: results/development/validation_scores.csv and results/final/test_scores.csv, test_country_scores.csv, test_year_scores.csv. Suggested visuals: test RMSE gain relative to zero; country-level relative errors; matched conflict comparison.

## 6. Limitations (approximately 1 page)

Address revised data, conventional rather than exact historical publication dates, retrospective validation timing, the annual/Candidate source change, five related countries, only 24 test months, repeated validation comparisons and fixed forest settings. Describe omitted economic channels as possible limitations, not excuses for results.

No formal significance analysis was completed. Do not describe small differences as statistically significant. Capital distance is a proxy rather than trade/supply-chain exposure. Aggregating by event-start month and missing coordinates can lose information. An operational model today would require updated data and a documented index-level forecasting procedure.

## 7. Conclusion (approximately 0.5 page)

Answer the research question directly. Simple country-specific historical averages were hard to beat in the holdout. Added complexity and the tested conflict feature did not deliver an aggregate advantage. Describe the project's value as a reproducible comparison with realistic information delays, without claiming exact real-time reconstruction or causal identification.

## References and appendices

Cite Eurostat, the GED/Candidate publications and codebooks, OxCGRT if discussing its preparation, and relevant course/method references actually used. Add full validation scores, predictor dictionary, source inventory, training/seed settings, reproducibility instructions and the completed contribution note.

## Claims to avoid

- "The country-mean improvement is statistically significant."
- "Conflict does not affect consumption."
- "We proved that machine learning cannot forecast retail growth."
- "We forecast aggregate European retail levels in real time."
- "Country mean was selected as primary before testing."

Each overstates the actual evidence or changes the task that was evaluated.
