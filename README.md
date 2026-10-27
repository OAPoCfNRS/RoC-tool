# RoC tool

**A settings-driven R workflow for estimating and comparing rates of change in biotic and abiotic time series**

RoC processes long-term biological and physicochemical observations at one or more sites. It estimates annual biotic rates, optionally separates a biological trajectory into two locally linear intervals, removes the recurring seasonal cycle from abiotic variables, estimates one full-window abiotic rate per variable, and pairs the resulting rates by site.

The workflow is designed for researchers with or without prior experience in R. All user-defined inputs-including file paths, column mappings, analysis periods, screening thresholds, segmentation rules, and abiotic variables are configured through an Excel settings workbook, without requiring users to edit the underlying R code.

## Contents

- [Purpose and scope](#purpose-and-scope)
- [Terminology and code identifiers](#terminology-and-code-identifiers)
- [Repository contents](#repository-contents)
- [Requirements](#requirements)
- [Input data](#input-data)
- [Configure the analysis](#configure-the-analysis)
- [Run the workflow](#run-the-workflow)
- [Analytical workflow](#analytical-workflow)
- [Output files](#output-files)
- [Interpretation and methodological boundaries](#interpretation-and-methodological-boundaries)
- [Troubleshooting](#troubleshooting)
- [Reproducibility and reporting](#reproducibility-and-reporting)
- [Citation](#citation)
- [License and support](#license-and-support)

## Purpose and scope

RoC addresses a recurring problem in ecological time series synthesis: biotic and abiotic variables are often sampled at different frequencies and may not follow the same temporal structure.

The workflow therefore treats the two data domains differently:

| Data domain | Temporal treatment | Reported rate |
|---|---|---|
| Biotic data | Aggregated by site, year, and biological group; represented by one full-period linear trend or two independently fitted locally linear intervals | Absolute biotic rate and bounded relative biotic rate for each accepted segment |
| Abiotic data | Deseasoned at observation level, aggregated to monthly means, and fitted across the complete selected period | One full-window abiotic rate in the physicochemical variable's native units per year |
| Biotic-abiotic pairing | Biotic segments are joined to abiotic rates by site | Each segment-specific biotic rate is paired with the same full-window rate for every selected abiotic variable at that site |

The tool is suitable when the objective is to compare the direction and magnitude of long-term biological change with concurrent physicochemical change. It assesses temporal coherence; it does not establish causality, estimate biotic-abiotic regression coefficients, or prove that an identified biological breakpoint was caused by an abiotic variable.

## Terminology and code identifiers

The workflow includes two principal analytical streams:

- **Biotic stream:** analysis of biological time series. Each time series unit is one category of a biological group represented by a biological trait value through time.
- **Abiotic stream:** analysis of carbonate chemistry and other physicochemical time series.

The principal rates are denoted conceptually as:

- $RC_{bio}$: absolute or bounded relative rate of change of a biotic variable within one fitted segment;
- $RC_{abio}$: full-window rate of change of an abiotic variable in its native physical units per year.

The current version implementation retains `BIO` and `CHEM` in worksheet names, object names, column names, output filenames, and some plot labels. In these machine-readable identifiers:

- `bio` corresponds to the **biotic stream**;
- `chem` corresponds to the broader **abiotic stream**, not only carbonate chemistry;
- `bio_group` corresponds to **biological group**;
- `bio_trait_var` contains the **biological trait value**;
- `bio_rate_abs_per_year` corresponds to absolute $RC_{bio}$;
- `bio_rate_pct_per_year` corresponds to bounded relative $RC_{bio}(\%)$;
- `chem_rate_abs_per_year` corresponds to $RC_{abio}$.


## Repository contents

| File or folder | Purpose | User action |
|---|---|---|
| `RUN.R` | Launcher that starts the workflow | Open and run this file |
| `DO_NOT_RUN.R` | Analytical engine for data processing, models, plots and exports | Do not run directly during normal use |
| `settings_configuration.xlsx` | Configuration workbook for input files, column mappings, analysis periods and analytical settings | Edit the designated value cells; retain worksheet names and required keys |
| `data/biotic_data_example.xlsx` | Example biological time series | Use for the demonstration run |
| `data/abiotic_data_example.xlsx` | Example abiotic time series | Use for the demonstration run |
| `STEP BY STEP GUIDE for RoC tool.pdf` | Methodological guidance, demonstration-data description and practical instructions | Read before preparing data and interpreting results |

Example input data are included in the `data/` folder. They can be used to practise configuring the workflow, running the analysis and interpreting the outputs before applying RoC to another dataset.

## Requirements

### Software

- R version 4.1 or later is required because the workflow uses the native R pipe.
- RStudio is recommended for the simplest launch procedure, but the launcher can also be executed with R outside RStudio.
- An internet connection may be required during the first run because missing R packages are installed automatically from CRAN.

### R packages

The workflow uses `readxl`, `writexl`, `dplyr`, `tidyr`, `lubridate`, `ggplot2`, `tibble`, and `ggrepel`. The `rstudioapi` package is used only when needed to locate the active launcher in RStudio.

### Folder arrangement

Keep the launcher, analytical engine, and settings workbook together in the project folder. By default, place the biotic and abiotic workbooks in a `data` subfolder. Results are written to an `out` subfolder. Both locations can be changed on the `Project` sheet.

## Input data

RoC reads Excel workbooks. For each input workbook, the first worksheet is read. Prepare one biotic workbook, one abiotic workbook, or both, depending on the selected modules.

Data quality control must be completed before running RoC. The tool does not detect analytical outliers, harmonize taxonomic names, standardize units, identify duplicated sampling events, or decide whether a missing biological record means absence.

### Demonstration dataset

The supplied example workbooks contain time series derived from Copernicus Marine Service reanalysis products for nine surface sites across the Iberian–Biscay–Irish, Baltic Sea and Mediterranean Sea regions. The source data are daily surface fields extracted at approximately 0.5–2 m depth.

The biological example represents net primary production (`nppv`), used as a proxy for phytoplankton primary production. Abiotic variables include temperature, salinity, pH, pCO₂ and additional carbonate-system variables calculated during data preparation.

These are reanalysis-derived demonstration data, not direct field observations. Additional carbonate variables were calculated using the R package `seacarb` from pH, pCO₂, temperature and salinity. They must be distinguished from directly measured quantities. Scientific use requires evaluation of the source products, pH scale, calculation settings and uncertainties.

The step-by-step guide describes the source products, demonstration sites and carbonate calculations under “Preparing input files” and “Demonstration dataset”, including Tables 3 and 4.

To run the supplied examples, set the following values in the `Project` worksheet of `settings_configuration.xlsx`:

| Key | Value |
|---|---|
| `data_dir` | `data` |
| `bio_infile` | `biotic_data_example.xlsx` |
| `abio_infile` | `abiotic_data_example.xlsx` |
| `run_bio` | `TRUE` |
| `run_abio` | `TRUE` |

Check the column mappings, selected variables and analysis periods before running `RUN.R`. Save a copy of the settings and outputs before changing settings and rerunning.

When using your own data, replace the input filenames and review all relevant settings. Follow the guide’s data-preparation and quality-control procedures before analysis.

### Biological input

The biological table must contain columns that can be mapped to these operated names:

| Operated name | Required | Meaning |
|---|---:|---|
| `grid_id` | Yes | Site, station, grid cell, or location identifier |
| `year` | Yes | Sampling year as an integer |
| `bio_group` | Yes | Taxon, genus, species, size class, functional group, or other biological unit |
| `bio_trait_var` | Yes | Numeric response such as abundance, biomass, cover, or growth |

Multiple rows for the same site, year, and biological group are allowed. They are combined using the selected annual aggregation rule: sum, mean, or median.

The input must distinguish true zero from missing data. A zero means the group was assessed and absent or its measured value was genuinely zero. A missing value means the observation is unavailable. This distinction directly affects screening, annual completion, fitted trends, and rates.

### Abiotic input

The abiotic table must contain:

| Operated name | Required | Meaning |
|---|---:|---|
| `date` | Yes | Full sampling date |
| `grid_id` | Yes | Site identifier; values must match the biological `grid_id` values for rate pairing |
| Selected variables | Yes | Numeric carbonate chemistry or other physicochemical variables listed as enabled in `Abio_selected_variables` |

The optional input columns `year`, `month`, and `day` are not required. RoC derives them from `date` after import.

Dates may be stored as Excel dates or common year-month-day, day-month-year, or month-day-year strings. Ambiguous date strings should be standardized before analysis. Rows with an unparseable date or missing site identifier are removed.

All selected abiotic variables must use consistent units within a variable and site. RoC does not convert units or reconcile pH scales, carbonate-system conventions, analytical methods, or sensor calibrations.

### Recommended scientific screening before use

Before interpreting rates, verify that:

- biotic and abiotic records have a defensible common analysis period;
- the time series is long enough for the intended trend analysis;
- missing years and months are quantified and their pattern is understood;
- sampling effort, season, depth or layer, method, and taxonomic resolution are sufficiently consistent;
- true zeros are separated from missing observations;
- abiotic variables have adequate seasonal coverage for estimating monthly climatology;
- biological aggregation is scientifically appropriate for the response variable;
- all values have passed source-level quality control.

As a general case-study screening rule, an overlap of at least 15 years and no more than 30% missing years may be useful, but these are study-design criteria rather than hardcoded RoC checks. The current code enforces only the thresholds specified in the settings workbook.

## Configure the analysis

Open `settings_configuration.xlsx` and edit values without renaming worksheets, deleting required keys, or changing the operated column names expected by the workflow.

### `Project`

| Key | Meaning |
|---|---|
| `project_dir` | Project folder. A value of `.` uses the folder containing the launcher and settings workbook |
| `data_dir` | Input-data folder, resolved relative to `project_dir` unless an absolute path is supplied |
| `out_dir` | Main results folder |
| `bio_infile` | Biological workbook filename inside `data_dir` |
| `abio_infile` | Abiotic workbook filename inside `data_dir` |
| `run_bio` | Run or skip the biological module |
| `run_abio` | Run or skip the abiotic module |
| `overwrite_outputs` | Reserved setting; the current version reads this value but does not enforce it. Existing files with the same names are overwritten |
| `log_runs` | Append a completion timestamp to `run.log` |

### `Bio_ColMap`

Map the biological workbook's original column names to the four required operated names. Matching of original names is case-insensitive. Do not map two input columns to the same operated name, because duplicate names stop the workflow.

### `Bio_settings`

| Key | Meaning |
|---|---|
| `analysis_years` | Inclusive biological analysis period, written as start year and end year separated by a semicolon |
| `aggregation` | Annual within-group aggregation: sum, mean, or median |
| `complete_missing_groups_as_zero` | If true, newly created missing group–year combinations are filled with zero; if false, they remain missing |
| `min_non_missing_years` | Minimum observed, non-missing group–years required to retain a site–group series |
| `min_non_zero_years` | Minimum observed years with a value greater than zero |

Screening occurs before missing group–year combinations are created. Consequently, zeros added during annual completion do not help a group pass the screening thresholds.

Use `complete_missing_groups_as_zero` only when absence can be inferred from the sampling design. Setting it to true for unsampled years converts missing information into biological absence and can materially bias trends.

### `Bio_segmentation`

| Key | Meaning |
|---|---|
| `enabled` | Allow a one-line or two-segment biological representation; false forces one line |
| `min_segment_years` | Minimum number of non-missing observations in each candidate segment |
| `max_segments` | Maximum number of segments; the current implementation accepts only 1 or 2 |
| `selection_method` | `bic` selects between one and two segments using Bayesian Information Criterion|
| `boundary_fraction` | Excludes candidate breakpoints near the beginning and end of the observed series |
| `bic_count_breakpoint` | When true, counts the breakpoint as an additional parameter in the two-segment BIC |
| `apply_min_r2_gain_filter` | Requires an additional adjusted-R² improvement after the primary selection rule |
| `min_r2_gain` | Minimum adjusted-R² improvement when the additional filter is enabled |

The default workbook uses BIC with the breakpoint counted as a parameter and an additional ecological filter based on adjusted-R² gain.

### `Abio_ColMap`

Map only structural columns, particularly the sampling date and site identifier. Abiotic variables do not need to be listed here. The names entered on `Abio_selected_variables` must match their names after any column mapping has been applied.

### `Abio_selected_variables`

Add any carbonate chemistry or other physicochemical variable to this table and set `enabled` to true to analyse it. No fixed set of ocean-acidification variables is required.

| Column | Meaning |
|---|---|
| `enabled` | Include or exclude the variable without deleting its row |
| `variable` | Exact post-mapping column name in the abiotic workbook |
| `title` | Optional readable title used in plots and tables |
| `ylab` | Optional axis label; include units where appropriate |
| `description` | User note; not used by the analytical engine |

### `Abio_settings`

| Key | Meaning |
|---|---|
| `analysis_years` | Inclusive abiotic analysis period |
| `min_months_for_trend` | Minimum number of finite deseasoned monthly means required to fit a trend |
| `tdt_min_months` | Minimum number of monthly means required for an `OK` TDT length flag |

The biotic and abiotic analysis periods may differ. If they do, RoC still pairs their rates by site. Such pairs must not be described as rates calculated over a common aligned analysis window. 

## Run the workflow

1. Download or clone the repository.
2. Keep `RUN.R`, `DO_NOT_RUN.R`, and `settings_configuration.xlsx` together.
3. Place the input workbooks in the configured data folder.
4. Complete all relevant settings sheets.
5. Open `RUN.R` in RStudio and run the complete file.
6. Read the console messages and correct any reported input or configuration error.
7. Inspect the tables and plots in the configured output folder before using the rates.

The launcher should be run directly. The analytical engine is sourced automatically. Running only selected lines of the engine can leave incomplete objects and is not supported as a normal workflow.

Missing packages are installed automatically. The analysis then runs the enabled biotic and abiotic modules and performs rate pairing only when both modules finish successfully.

## Analytical workflow

### 1. Configuration and column harmonization

RoC resolves relative paths from the project folder, reads the settings sheets, imports the first worksheet from each selected input workbook, trims column names, and applies the user-defined mappings. The workflow stops when required columns are absent, mapped names become duplicated, selected abiotic variables are missing, a selected abiotic variable is entirely non-numeric, or no data remain after filtering.

### 2. Biological processing

For each site and biological group, RoC:

1. restricts observations to the selected biological years;
2. aggregates repeated rows within each year using sum, mean, or median;
3. counts observed years, non-missing years, and non-zero years;
4. retains only groups that pass both screening thresholds;
5. creates the complete requested year sequence for retained groups;
6. fills newly created combinations with zero or leaves them missing according to the settings;
7. fits a single linear trend and, when allowed, evaluates candidate two-segment models;
8. reports fitted endpoints, absolute $RC_{bio}$, and bounded relative $RC_{bio}(\%)$ for every accepted segment.

### 3. Abiotic processing

Abiotic processing follows the deseasonalisation and long-term trend principles described by Sutton et al. (2022) and occurs independently for each site and selected physicochemical variable.

RoC:

1. parses dates and calculates decimal year;
2. filters observations to the selected abiotic analysis years;
3. fits a preliminary linear trend to observation-level values;
4. calculates detrended residuals;
5. calculates the mean residual for each represented calendar month;
6. subtracts the relevant monthly residual climatology from every original observation;
7. averages raw and deseasoned observations by calendar month;
8. fits one full-window linear regression to the deseasoned monthly means;
9. reports $RC_{abio}$ in native units per year, its standard error, p-value, R², adjusted R², and fitted full-period change;
10. calculates TDT and diagnostic curve outputs.

A variable requires at least 12 usable observation-level records across at least two calendar months to be deseasoned. This is a computational minimum, not evidence that the seasonal cycle is adequately characterized. A trend is returned only when the number of finite monthly means reaches `min_months_for_trend`.

#### Trend Detection Time

RoC calculates Trend Detection Time (TDT) from the full-window linear slope, residual standard deviation, and lag-one residual autocorrelation. It also reports an uncertainty-adjusted value, `uTDT`. TDT fails when fewer than 24 monthly values are available or the trend or autocorrelation is invalid. It receives an `OK` flag only when the series reaches `tdt_min_months` and autocorrelation < 0.6$; otherwise it receives a warning with the reason recorded.

The flag evaluates basic computational conditions. It is not a complete validation of the trend model or the observation system.

#### Diagnostic abiotic curves

For visualization only, RoC compares linear, quadratic, and cubic polynomial fits using adjusted R² and saves the best curve. This curve does not determine the reported abiotic rate. $RC_{abio}$ always comes from the full-window linear regression of deseasoned monthly means.

### 4. Biotic-abiotic rate pairing

When both modules are enabled, RoC identifies site IDs present in both results. It then joins every retained biotic segment at a site to every successful abiotic-variable rate at the same site.

Each unique biological site-group-segment combination receives a `point_id`. The same `point_id` is repeated across abiotic-variable panels so that one biological trajectory can be followed across comparisons.

The combined table is a pairing of $RC_{bio}$ and $RC_{abio}$, not a fitted relationship. The current tool does not calculate correlation, regression, causality, lagged response, or significance for the biotic- abiotic association.

## Output files

Results are divided into `bio`, `chem`, and `bio_chem` subfolders. Existing files with the same names are overwritten in the current version.

### Biological outputs

| File | Contents | Primary use |
|---|---|---|
| `bio/bio_yearly_observed_aggregated.xlsx` | One observed annual value per site and biological group after the selected aggregation; does not include newly created missing years | Audit annual aggregation and observed-data coverage |
| `bio/bio_yearly_input_for_segmentation.xlsx` | Complete annual sequence for retained and fitted groups, including zeros or missing values introduced according to the completion setting | Verify the exact values supplied to segmentation |
| `bio/bio_group_screening.xlsx` | Observed-year counts, non-missing-year counts, non-zero-year counts, `keep`, and `fitted` status for every site-group series | Explain inclusion and exclusion |
| `bio/bio_segmented_rates.xlsx` | One row per fitted biological line or segment, model-selection diagnostics, fitted endpoints, slope statistics, absolute $RC_{bio}$, and bounded relative $RC_{bio}(\%)$ | Main biotic rate table |
| `bio/bio_segments_<site>_p<page>.png` | Observations, fitted line segments, and accepted breakpoints, with up to 20 biological groups per page | Visual validation of segment fits |

Important fields in `bio_segmented_rates.xlsx` include:

- `seg_id`, `segment_model`, `x1`, and `x2`: segment identity and observed time limits;
- `n`: number of finite annual observations used in the segment;
- `slope`, `slope_se`, `slope_p`, `r2`, and `adj_r2`: regression statistics;
- `breakpoint_year`, `segmentation_accepted`, and `segmentation_reason`: segmentation result;
- `bic_single`, `bic_two`, `bic_delta`, `r2_gain`, and `penalty`: selection diagnostics;
- `bio_y_start_hat`, `bio_y_end_hat`, and `bio_abs_change`: fitted boundary values and change;
- `bio_rate_abs_per_year`: absolute annual biological rate in the response variable's native units;
- `bio_rate_pct_per_year`: annual rate standardized by the larger fitted boundary value;
- `bio_total_pct_change`: fitted total segment change standardized by the same boundary value.

### Abiotic outputs

| File | Contents | Primary use |
|---|---|---|
| `chem/chem_deseasoned_observations.xlsx` | Original retained observations plus derived date fields, decimal year, monthly residual climatology, and deseasoned values for each selected abiotic variable | Audit observation-level deseasonalisation |
| `chem/chem_deseasoned_monthly.xlsx` | Raw and deseasoned monthly means, observation counts, dates, and decimal years in long format by site and variable | Verify the data used for abiotic trends |
| `chem/chem_full_window_rates.xlsx` | One full-window $RC_{abio}$ per site and abiotic variable, regression statistics, status, TDT, and TDT QC | Main abiotic rate table |
| `chem/chem_best_fit_diagnostic_models.xlsx` | Selected diagnostic polynomial form and adjusted R² for each site and variable | Identify the curve displayed for visual context |
| `chem/chem_best_fit_diagnostic_curves.xlsx` | Prediction coordinates for the selected diagnostic curve | Reproduce or inspect diagnostic curves |
| `chem/chem_trends_<site>.png` | Raw observations, raw monthly means, deseasoned monthly means, diagnostic curve, rate-defining linear trend, and TDT label | Visual validation of deseasonalisation and trend form |

Important fields in `chem_full_window_rates.xlsx` include:

- `chem_n_months`, `chem_analysis_start`, and `chem_analysis_end`: temporal coverage;
- `chem_y_start_hat`, `chem_y_end_hat`, and `chem_abs_change`: fitted full-window change;
- `chem_rate_abs_per_year`: $RC_{abio}$ in native units per year;
- `chem_slope_se`, `chem_slope_p`, `chem_r2`, and `chem_adj_r2`: linear-model diagnostics;
- `chem_status`: whether the minimum number of months was available;
- `TDT`, `uTDT`, `omega0`, `sigmaN`, and `phi`: time-of-detection components;
- `tdt_n`, `tdt_qc`, and `tdt_qc_reason`: TDT sample size and QC status.

### Combined outputs

| File | Contents | Primary use |
|---|---|---|
| `bio_chem/bio_chem_rate_comparison.xlsx` | Biotic segment records joined to all successful full-window abiotic rates at the same site | Main integrated result table |
| `bio_chem/bio_chem_rate_comparison.png` | $RC_{abio}$ versus bounded relative $RC_{bio}(\%)$, faceted by abiotic variable and labelled with `point_id` | Explore direction and magnitude across biological trajectories |

The combined plot uses the biological segment duration as the colour scale. Zero-reference lines divide positive and negative biotic and abiotic rates. Because the abiotic x-axis retains native physical units, panels should be interpreted separately unless variables share a directly comparable scale.

### Run log

When logging is enabled, `out/run.log` receives a timestamp and a `Run complete` message. This confirms that execution reached the end; it does not record settings, package versions, warnings, source-data identity, or analytical checksums.

## Interpretation and methodological boundaries

### What can be concluded

RoC can quantify:

- the direction and fitted magnitude of change within biological periods;
- whether a one-line or eligible two-segment representation is selected under the configured rule;
- the full-window linear rate of each deseasoned abiotic variable;
- basic uncertainty and model-fit statistics for the fitted slopes;
- TDT diagnostics for abiotic trends;
- which biotic and abiotic rate estimates belong to the same site.

### What cannot be concluded from RoC alone

RoC does not demonstrate:

- that abiotic change caused a biological response;
- that a biological breakpoint is driven by an abiotic variable;
- that a non-significant slope represents no ecological change;
- that the selected linear or polynomial form captures all temporal dependence;
- that seasonal coverage, missingness, measurement uncertainty, or sampling effort are adequate;
- that rates calculated over different periods are directly comparable;
- that bounded relative $RC_{bio}(\%)$ is interchangeable with conventional initial-value percentage change.

### Known implementation boundaries in version 5

- Only Excel input files are read as data, and only their first worksheets are imported.
- Biological segmentation allows at most two independent linear segments.
- The workflow does not test for seasonality before applying monthly adjustment.
- It does not weight monthly means by sampling uncertainty or effort.
- It does not model heteroscedasticity, residual autocorrelation in the slope regression, nonlinear biological trends, or uncertainty in breakpoint selection.
- It does not propagate uncertainty from biotic and abiotic rates into the combined comparison.
- The run log is minimal and should not be treated as a complete reproducibility record.

## Troubleshooting

### The launcher cannot determine its location

Open `RUN.R` directly in RStudio and run the complete file, or execute the launcher as a file rather than pasting isolated lines into the console.

### A settings or pipeline file is not found

Confirm that the launcher, analytical engine, and settings workbook retain their original filenames and are stored in the same folder.

### An input workbook is not found

Check `project_dir`, `data_dir`, and the two input filenames. Relative data and output paths are resolved from `project_dir`.

### Required operated columns are missing

Check the relevant column-map sheet. Original names must correspond to columns in the input workbook, while operated names must use the required RoC names exactly.

### Duplicate columns are reported after mapping

Two original columns have been mapped to the same operated name, or an operated name already exists beside the column being renamed. Resolve the duplication in the input or map.

### An abiotic variable is not found

The value in `Abio_selected_variables` does not exactly match the abiotic column name after column mapping. Correct the name or disable that row.

### An abiotic variable cannot be converted to numeric

The selected column contains no readable numeric values. Remove unit text and non-numeric symbols from data cells while retaining missing values as blank or explicit missing values.

### No biological groups pass screening

Inspect the observed data coverage, then review `min_non_missing_years` and `min_non_zero_years`. Do not lower thresholds solely to force output; first decide whether the remaining time series could support a defensible trend.

### No biotic-abiotic comparison is produced

Both modules must run successfully, abiotic rates must have `chem_status` equal to `ok`, and at least one `grid_id` must match exactly between the biotic and abiotic results.

### A TDT result is missing or flagged

Inspect `tdt_qc_reason`. Common reasons are fewer than 24 monthly values, fewer months than the configured TDT threshold, high lag-one residual autocorrelation, a zero or invalid slope, or invalid autocorrelation.

### Existing outputs were replaced

This is current version-5 behavior. The workbook's `overwrite_outputs` setting is not yet enforced. Copy or rename an existing output folder before rerunning if it must be preserved.

### A plot and a rate appear to describe different shapes

The flexible abiotic curve is diagnostic only. The reported $RC_{abio}$ and dark-red trend line come from the full-window linear fit to deseasoned monthly means.

## Reproducibility and reporting

For every analysis, archive:

- the exact versions of both R scripts and the settings workbook;
- immutable copies of both input workbooks;
- the complete output folder;
- the R version and installed package versions;
- data-source citations, units, quality-control procedures, and preprocessing decisions;
- the rationale for analysis windows, missing-data treatment, annual aggregation, screening thresholds, and segmentation settings;
- a record of any excluded sites, groups, years, months, or variables.

At minimum, a methods description should state:

1. the biotic and abiotic analysis periods and whether they form a common aligned analysis window;
2. how biological replicates were aggregated;
3. how zero and missing biological observations were distinguished;
4. the biological inclusion thresholds;
5. the segmentation selection method, minimum segment size, boundary exclusion, breakpoint parameter treatment, and adjusted-R² filter;
6. that abiotic variables were detrended, adjusted using monthly residual climatologies, aggregated to monthly means, and fitted with one full-window linear trend;
7. the minimum monthly coverage and TDT QC rules;
8. the definitions of absolute and bounded relative biotic rates;
9. that segment-specific $RC_{bio}$ values were paired with site-level full-window $RC_{abio}$ values and that the pairing assessed temporal coherence rather than causality.

## Citation

If RoC is used to generate or support results reported in a scientific article, please cite both:

1. the version of the RoC software used in the analysis; and
2. the associated methodological article (preprint is available at https://doi.org/10.5194/egusphere-2026-4577).

The formal RoC citation and preferred methodological-article citation will be added after the first archived software release.

The abiotic trend procedure follows the methodological recommendations of:

Sutton, A. J., Battisti, R., Carter, B. R., Evans, W., Newton, J., Alin, S. R., Bates, N. R., Cai, W.-J., Currie, K., Feely, R. A., Sabine, C. L., Tanhua, T., Tilbrook, B., and Wanninkhof, R. (2022). Advancing best practices for assessing trends of ocean acidification time series. *Frontiers in Marine Science*, 9, 1045667. [https://doi.org/10.3389/fmars.2022.1045667](https://doi.org/10.3389/fmars.2022.1045667)

## License and support

RoC is licensed under the [MIT License](https://opensource.org/license/mit). The software may be used, copied, modified, merged, published, distributed, sublicensed, and incorporated into other work, provided that the copyright and license notice are retained. The full MIT license text must be included in a `LICENSE` file in the repository root.

Scientific citation is requested to ensure appropriate credit and reproducibility, but it is separate from the legal permissions granted by the MIT License.

The software is provided without warranty. Users are responsible for checking input-data quality, selecting scientifically defensible settings, validating the generated results, and reporting any modifications that could affect interpretation.


