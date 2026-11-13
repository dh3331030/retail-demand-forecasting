# Proposed 15-minute group presentation

Twelve slides, with 13 minutes 45 seconds of planned content and 1 minute 15 seconds for transitions/overrun. Put long equations, the 26-model table and detailed source links in backup slides or the report. These are proposed slide contents, not a completed deck. Allocate speakers using the actual group contribution note.

| Slide | Title / purpose | Suggested content or visual | Time |
|---|---|---|---:|
| 1 | Forecasting food-retail growth | Research question, five countries, team names; one line defining growth target | 0:30 |
| 2 | Why compare simple and complex forecasts? | Hypothesized macro/conflict channels; explain that added complexity must earn an accuracy gain | 0:45 |
| 3 | Data and sample | Source table with exact retail scope; five countries; 660 source rows and 630 usable rows | 1:00 |
| 4 | Forecast timing and chronological evaluation | Training/validation/test timeline and January forecast example; distinguish reference month from availability | 1:20 |
| 5 | Conflict exposure | exp(-distance/h), capital anchors, counts/deaths alternatives; annual versus Candidate provenance | 1:20 |
| 6 | Models and monthly updating | Benchmarks, shared/country slopes, tree/bagging/forest; common expanding-window cutoff | 1:05 |
| 7 | Validation and model reduction | Selected validation comparisons; zero wins, reduced models improve internally; six finalists frozen | 1:00 |
| 8 | Overall holdout accuracy | Six-model table or RMSE improvement versus zero; identify country mean as best comparator and zero as original primary | 1:40 |
| 9 | Differences across countries and years | One country comparison and concise 2024/2025 takeaway; do not overwhelm with all 30 score rows | 1:15 |
| 10 | Did conflict improve the forecast? | Matched forest pair, with/without weighted deaths; RMSE 1.2712 versus 1.2825 | 1:00 |
| 11 | Limitations and reproducibility | Revised data, timing conventions/early-2024 caveat, limited test sample, fixed seeds and runnable scripts | 1:30 |
| 12 | Conclusion | Simple methods remain competitive; extra predictors/complexity did not deliver an aggregate gain; practical scope and next steps | 1:20 |

Total planned content: 13:45. Buffer to 15:00: 1:15. Adjust only if the class's 15 minutes includes Q&A.

## Exact evidence for visuals

- Slide 7: `results/development/validation_scores.csv`, `reduced_comparison.csv`, `frozen_finalists_validation_scores.csv`.
- Slide 8: `results/final/test_scores.csv`. A percentage-gain chart around a clearly labelled zero reference makes small differences legible without exaggerating them through an unlabelled truncated RMSE axis.
- Slide 9: `test_country_scores.csv` and `test_year_scores.csv`. Compare like metrics and show the five countries, rather than selectively highlighting favorable ones.
- Slide 10: the two full-forest rows in `test_scores.csv`; optional country exceptions from `test_country_scores.csv`.
- Timing and source visuals: `docs/PREPROCESSING.md`, `docs/DATA_SOURCES.md` and the actual configuration.

The current archive exports CSV/RDS data, not these figures. Add any plotting R code used to the final project so the group's figures are reproducible. Avoid screenshot-only results.

## Presentation emphasis

Spend more time explaining the experiment and its results than walking through code syntax. Report the small observed 1.16% RMSE reduction for country mean without calling it statistically significant. The conclusion is about forecasting value under this setup, not whether conflict has an economic effect.

Keep on-slide text short. Use the report for the annual/Candidate distinction and the precise retrospective-evaluation caveat, but mention both limitations aloud and on the limitations slide.

## Optional backup slides

Full 26-model validation table; exact forest controls; country/year test table; variable dictionary and source links; forecast-error definitions; group contributions. These are outside the twelve-slide timed sequence.
