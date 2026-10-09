# ================= BIO + CHEM rate-of-change pipeline =================
# Settings-driven, no hardcoded chemical/environmental variables.
# BIO: yearly aggregation + one/two-segment linear segmentation.
# CHEM: Sutton-style deseasoning + one full-window trend. CHEM is never segmented.
# BIO x CHEM: each BIO segment is paired with the same full-window CHEM rate.
# =====================================================================

# ---- Packages --------------------------------------------------------

load_pkgs <- function(pkgs, repos = "https://cloud.r-project.org") {
  pkgs <- unique(pkgs)
  missing <- setdiff(pkgs, rownames(installed.packages()))
  if (length(missing)) install.packages(missing, repos = repos, dependencies = TRUE)
  invisible(lapply(pkgs, function(x) suppressPackageStartupMessages(require(x, character.only = TRUE))))
}

load_pkgs(c(
  "readxl", "writexl", "dplyr", "tidyr", "lubridate", "ggplot2",
  "tibble", "ggrepel"
))

`%||%` <- function(a, b) {
  if (!is.null(a) && length(a) == 1 && !is.na(a) && nzchar(as.character(a))) a else b
}

# ---- Small helpers ----------------------------------------------------

parse_bool <- function(x) {
  if (is.logical(x)) return(isTRUE(x))
  tolower(trimws(as.character(x))) %in% c("true", "t", "yes", "y", "1")
}

split_list <- function(x) {
  x <- trimws(as.character(x %||% ""))
  if (!nzchar(x)) return(character())
  trimws(unlist(strsplit(x, ";|,", perl = TRUE)))
}

parse_year_span <- function(x, label) {
  y <- suppressWarnings(as.integer(split_list(x)))
  if (length(y) < 2 || anyNA(y[1:2]) || y[1] > y[2]) {
    stop(label, " must be written as start;end, for example 1999;2018")
  }
  y[1:2]
}

norm_path <- function(p, base = ".") {
  p <- as.character(p %||% "")
  if (!nzchar(p)) return(normalizePath(base, mustWork = FALSE))
  if (grepl("^(/|[A-Za-z]:)", p)) return(normalizePath(p, mustWork = FALSE))
  normalizePath(file.path(base, p), mustWork = FALSE)
}

read_kv_sheet <- function(path, sheet) {
  x <- readxl::read_excel(path, sheet = sheet, .name_repair = "minimal")
  if (!all(c("key", "value") %in% names(x))) {
    stop(sheet, " must contain columns: key, value")
  }
  out <- as.list(setNames(x$value, x$key))
  lapply(out, function(z) if (is.character(z)) trimws(z) else z)
}

read_colmap <- function(path, sheet) {
  x <- readxl::read_excel(path, sheet = sheet, .name_repair = "minimal")
  if (!all(c("original", "operated") %in% names(x))) {
    stop(sheet, " must contain columns: original, operated")
  }

  x <- x |>
    dplyr::mutate(
      original = trimws(as.character(original)),
      operated = trimws(as.character(operated))
    ) |>
    dplyr::filter(!is.na(original), nzchar(original), !is.na(operated), nzchar(operated))

  stats::setNames(x$operated, x$original)
}

apply_colmap <- function(df, colmap, sheet_name) {
  names(df) <- trimws(names(df))
  if (!length(colmap)) return(df)

  lower_names <- tolower(names(df))
  for (old in names(colmap)) {
    hit <- match(tolower(old), lower_names)
    if (!is.na(hit)) names(df)[hit] <- unname(colmap[[old]])
  }

  if (anyDuplicated(names(df))) {
    stop(sheet_name, ": duplicate column names after renaming: ",
         paste(unique(names(df)[duplicated(names(df))]), collapse = ", "))
  }

  df
}

check_required <- function(df, required, label) {
  missing <- setdiff(required, names(df))
  if (length(missing)) {
    stop(label, " is missing required operated columns: ", paste(missing, collapse = ", "))
  }
}

parse_mixed_date <- function(x) {
  x_chr <- trimws(as.character(x))
  x_chr[x_chr %in% c("", "NA", "NaN", "NULL")] <- NA_character_

  out <- rep(as.Date(NA), length(x_chr))

  num <- suppressWarnings(as.numeric(x_chr))
  idx_num <- !is.na(num)
  if (any(idx_num)) out[idx_num] <- as.Date(num[idx_num], origin = "1899-12-30")

  idx_chr <- !idx_num & !is.na(x_chr)
  if (any(idx_chr)) {
    parsed <- suppressWarnings(lubridate::parse_date_time(
      x_chr[idx_chr],
      orders = c("ymd", "dmy", "mdy", "Ymd", "dmY", "mdY")
    ))
    out[idx_chr] <- as.Date(parsed)
  }

  out
}

decimal_year <- function(d) {
  d <- as.Date(d)
  y <- lubridate::year(d)
  y0 <- as.Date(paste0(y, "-01-01"))
  y1 <- as.Date(paste0(y + 1L, "-01-01"))
  y + as.numeric(d - y0) / as.numeric(y1 - y0)
}

safe_slug <- function(x) {
  x <- tolower(as.character(x))
  x <- gsub("[^a-z0-9]+", "_", x)
  gsub("^_+|_+$", "", x)
}

label_lookup <- function(label_tbl, variable, field = "title") {
  hit <- which(label_tbl$variable == variable)[1]
  val <- if (!is.na(hit) && field %in% names(label_tbl)) label_tbl[[field]][hit] else NA_character_
  val <- trimws(as.character(val %||% ""))
  if (nzchar(val)) val else variable
}

# ---- Read settings ----------------------------------------------------

read_config <- function(path = "settings_configuration.xlsx") {
  if (!file.exists(path)) stop("Settings file not found: ", normalizePath(path, mustWork = FALSE))

  project <- read_kv_sheet(path, "Project")
  bio <- read_kv_sheet(path, "Bio_settings")
  seg <- read_kv_sheet(path, "Bio_segmentation")
  chem <- read_kv_sheet(path, "Abio_settings")

  project$project_dir <- norm_path(project$project_dir %||% ".")
  project$data_dir <- norm_path(project$data_dir %||% "data", project$project_dir)
  project$out_dir <- norm_path(project$out_dir %||% "out", project$project_dir)
  project$run_bio <- parse_bool(project$run_bio %||% TRUE)
  project$run_abio <- parse_bool(project$run_abio %||% TRUE)
  project$overwrite_outputs <- parse_bool(project$overwrite_outputs %||% TRUE)
  project$log_runs <- parse_bool(project$log_runs %||% TRUE)

  bio$analysis_years <- parse_year_span(bio$analysis_years, "Bio_settings$analysis_years")
  bio$aggregation <- tolower(trimws(as.character(bio$aggregation %||% "sum")))
  if (!bio$aggregation %in% c("sum", "mean", "median")) {
    stop("Bio_settings$aggregation must be one of: sum, mean, median")
  }
  bio$complete_missing_groups_as_zero <- parse_bool(bio$complete_missing_groups_as_zero %||% TRUE)
  bio$min_non_missing_years <- as.integer(bio$min_non_missing_years %||% 3)
  bio$min_non_zero_years <- as.integer(bio$min_non_zero_years %||% 0)

  seg$enabled <- parse_bool(seg$enabled %||% TRUE)
  seg$min_segment_years <- as.integer(seg$min_segment_years %||% 3)
  seg$max_segments <- as.integer(seg$max_segments %||% 2)
  if (seg$max_segments > 2) stop("Bio_segmentation$max_segments must be 1 or 2 in this pipeline.")
  seg$min_r2_gain <- as.numeric(seg$min_r2_gain %||% 0.05)
  seg$boundary_fraction <- as.numeric(seg$boundary_fraction %||% 0.15)
  seg$selection_method <- tolower(trimws(as.character(seg$selection_method %||% "bic")))
  if (seg$selection_method != "bic") {
    stop("Bio_segmentation$selection_method must be bic")
  }
  seg$bic_count_breakpoint <- parse_bool(seg$bic_count_breakpoint %||% TRUE)
  seg$apply_min_r2_gain_filter <- parse_bool(seg$apply_min_r2_gain_filter %||% TRUE)

  chem$analysis_years <- parse_year_span(chem$analysis_years, "Abio_settings$analysis_years")
  chem$min_months_for_trend <- as.integer(chem$min_months_for_trend %||% 24)
  chem$tdt_min_months <- as.integer(chem$tdt_min_months %||% 60)

  chem_vars <- readxl::read_excel(path, sheet = "Abio_selected_variables", .name_repair = "minimal")
  if (!all(c("enabled", "variable") %in% names(chem_vars))) {
    stop("Abio_selected_variables must contain at least: enabled, variable")
  }
  if (!"title" %in% names(chem_vars)) chem_vars$title <- NA_character_
  if (!"ylab" %in% names(chem_vars)) chem_vars$ylab <- NA_character_

  chem_vars <- chem_vars |>
    dplyr::mutate(
      enabled = vapply(enabled, parse_bool, logical(1)),
      variable = trimws(as.character(variable)),
      title = trimws(as.character(title)),
      ylab = trimws(as.character(ylab))
    ) |>
    dplyr::filter(enabled, !is.na(variable), nzchar(variable)) |>
    dplyr::distinct(variable, .keep_all = TRUE)

  if (project$run_abio && !nrow(chem_vars)) {
    stop("No enabled variables in Abio_selected_variables.")
  }

  list(
    project = project,
    bio = bio,
    seg = seg,
    chem = chem,
    colmap_bio = read_colmap(path, "Bio_ColMap"),
    colmap_chem = read_colmap(path, "Abio_ColMap"),
    chem_vars = chem_vars
  )
}

# ---- BIO segmentation -------------------------------------------------

fit_line_stats <- function(x, y) {
  fit <- stats::lm(y ~ x)
  s <- summary(fit)

  tibble::tibble(
    intercept = unname(coef(fit)[1]),
    slope = unname(coef(fit)[2]),
    slope_se = as.numeric(s$coefficients[2, 2]),
    slope_p = as.numeric(s$coefficients[2, 4]),
    r2 = as.numeric(s$r.squared),
    adj_r2 = as.numeric(s$adj.r.squared),
    sse = sum(resid(fit)^2, na.rm = TRUE)
  )
}

calc_bic_score <- function(sse, n, k) {
  safe_sse <- ifelse(is.finite(sse) & sse > 0, sse, .Machine$double.eps)
  n * log(safe_sse / n) + k * log(n)
}

single_segment_output <- function(x, y, reason = "single_line") {
  st <- fit_line_stats(x, y)
  tibble::tibble(
    seg_id = 1L,
    segment_model = "single",
    x1 = min(x),
    x2 = max(x),
    n = length(y),
    intercept = st$intercept,
    slope = st$slope,
    slope_se = st$slope_se,
    slope_p = st$slope_p,
    r2 = st$r2,
    adj_r2 = st$adj_r2,
    sse = st$sse,
    breakpoint_year = NA_real_,
    segmentation_accepted = FALSE,
    segmentation_reason = reason,
    selection_method = NA_character_,
    selection_score_single = NA_real_,
    selection_score_two = NA_real_,
    bic_single = NA_real_,
    bic_two = NA_real_,
    bic_delta = NA_real_,
    r2_gain = NA_real_
  )
}

segment_one_series <- function(df, seg_cfg) {
  d <- df |>
    dplyr::filter(is.finite(year), is.finite(bio_trait_var)) |>
    dplyr::arrange(year)

  x <- as.numeric(d$year)
  y <- as.numeric(d$bio_trait_var)
  n <- length(y)
  min_n <- seg_cfg$min_segment_years

  if (n < 3 || length(unique(x)) < 3) return(tibble::tibble())

  one <- single_segment_output(x, y)

  if (!seg_cfg$enabled || seg_cfg$max_segments == 1 || n < 2 * min_n) {
    one$segmentation_reason <- "single_or_too_short_for_two_segments"
    return(one)
  }

  x_span <- max(x) - min(x)
  if (!is.finite(x_span) || x_span <= 0) {
    one$segmentation_reason <- "invalid_year_span"
    return(one)
  }

  candidate_idx <- seq(min_n, n - min_n)
  if (!length(candidate_idx)) {
    one$segmentation_reason <- "no_candidate_breakpoint"
    return(one)
  }

  boundary_ok <- x[candidate_idx] > min(x) + seg_cfg$boundary_fraction * x_span &
    x[candidate_idx] < max(x) - seg_cfg$boundary_fraction * x_span
  candidate_idx <- candidate_idx[boundary_ok]

  if (!length(candidate_idx)) {
    one$segmentation_reason <- "no_candidate_after_boundary_filter"
    return(one)
  }

  best <- NULL
  for (k in candidate_idx) {
    s1 <- fit_line_stats(x[1:k], y[1:k])
    s2 <- fit_line_stats(x[(k + 1):n], y[(k + 1):n])
    sse2 <- s1$sse + s2$sse

    # Select the breakpoint minimising the combined SSE.
    # The BIC parameter penalty is constant across candidate breakpoints.
    if (is.null(best) || sse2 < best$sse2) {
      best <- list(k = k, s1 = s1, s2 = s2, sse2 = sse2)
    }
  }

  if (is.null(best)) {
    one$segmentation_reason <- "no_valid_two_segment_candidate"
    return(one)
  }


  bic_k_single <- 2
  bic_k_two <- if (isTRUE(seg_cfg$bic_count_breakpoint)) 5 else 4
  bic_single <- calc_bic_score(one$sse, n, bic_k_single)
  bic_two <- calc_bic_score(best$sse2, n, bic_k_two)
  bic_delta <- bic_two - bic_single

  tss <- sum((y - mean(y, na.rm = TRUE))^2, na.rm = TRUE)
  k_params <- 4
  r2_two <- if (tss > 0) 1 - best$sse2 / tss else NA_real_
  adj_r2_two <- if (is.finite(r2_two) && n > k_params + 1) {
    1 - (1 - r2_two) * ((n - 1) / (n - k_params - 1))
  } else {
    NA_real_
  }
  r2_gain <- adj_r2_two - one$adj_r2

  one$selection_method <- "bic"
  one$selection_score_single <- bic_single
  one$selection_score_two <- bic_two
  one$bic_single <- bic_single
  one$bic_two <- bic_two
  one$bic_delta <- bic_delta
  one$r2_gain <- r2_gain
  
  if (!is.finite(bic_single) || !is.finite(bic_two) ||
      bic_two >= bic_single) {
    one$segmentation_reason <- "bic_not_improved"
    return(one)
  }

  if (isTRUE(seg_cfg$apply_min_r2_gain_filter) &&
      (!is.finite(r2_gain) || r2_gain < seg_cfg$min_r2_gain)) {
    one$segmentation_reason <- "r2_gain_too_small"
    return(one)
  }

  k <- best$k
  bp <- x[k]

  dplyr::bind_rows(
    tibble::tibble(
      seg_id = 1L,
      segment_model = "two_segment",
      x1 = x[1],
      x2 = x[k],
      n = k,
      intercept = best$s1$intercept,
      slope = best$s1$slope,
      slope_se = best$s1$slope_se,
      slope_p = best$s1$slope_p,
      r2 = best$s1$r2,
      adj_r2 = best$s1$adj_r2,
      sse = best$s1$sse
    ),
    tibble::tibble(
      seg_id = 2L,
      segment_model = "two_segment",
      x1 = x[k + 1],
      x2 = x[n],
      n = n - k,
      intercept = best$s2$intercept,
      slope = best$s2$slope,
      slope_se = best$s2$slope_se,
      slope_p = best$s2$slope_p,
      r2 = best$s2$r2,
      adj_r2 = best$s2$adj_r2,
      sse = best$s2$sse
    )
  ) |>
    dplyr::mutate(
      breakpoint_year = bp,
      segmentation_accepted = TRUE,
      segmentation_reason = "two_segment_accepted",
      selection_method = "bic",
      selection_score_single = bic_single,
      selection_score_two = bic_two,
      bic_single = bic_single,
      bic_two = bic_two,
      bic_delta = bic_delta,
      r2_gain = r2_gain
    )
}

add_bio_rates <- function(seg_tbl) {
  seg_tbl |>
    dplyr::mutate(
      bio_y_start_hat = intercept + slope * x1,
      bio_y_end_hat = intercept + slope * x2,
      bio_duration_years = x2 - x1,
      bio_abs_change = bio_y_end_hat - bio_y_start_hat,
      bio_rate_abs_per_year = dplyr::if_else(
        is.finite(bio_duration_years) & bio_duration_years > 0,
        bio_abs_change / bio_duration_years,
        NA_real_
      ),
      bio_boundary_max = pmax(bio_y_start_hat, bio_y_end_hat, na.rm = TRUE),
      bio_rate_pct_per_year = dplyr::if_else(
        is.finite(bio_rate_abs_per_year) & is.finite(bio_boundary_max) & bio_boundary_max > 0,
        100 * bio_rate_abs_per_year / bio_boundary_max,
        NA_real_
      ),
      bio_total_pct_change = dplyr::if_else(
        is.finite(bio_boundary_max) & bio_boundary_max > 0,
        100 * bio_abs_change / bio_boundary_max,
        NA_real_
      )
    )
}

split_pages <- function(x, per_page = 20) {
  x <- sort(unique(as.character(x)))
  split(x, ceiling(seq_along(x) / per_page))
}

run_bio_pipeline <- function(cfg) {
  infile <- file.path(cfg$project$data_dir, cfg$project$bio_infile)
  if (!file.exists(infile)) stop("BIO input file not found: ", infile)

  raw <- readxl::read_excel(infile) |>
    apply_colmap(cfg$colmap_bio, "Bio_ColMap")

  check_required(raw, c("grid_id", "year", "bio_group", "bio_trait_var"), "BIO data")

  yr <- cfg$bio$analysis_years

  bio_raw <- raw |>
    dplyr::mutate(
      grid_id = as.character(grid_id),
      year = suppressWarnings(as.integer(year)),
      bio_group = as.character(bio_group),
      bio_trait_var = suppressWarnings(as.numeric(bio_trait_var))
    ) |>
    dplyr::filter(
      !is.na(grid_id), nzchar(grid_id),
      !is.na(bio_group), nzchar(bio_group),
      !is.na(year), year >= yr[1], year <= yr[2]
    )

  if (!nrow(bio_raw)) stop("BIO data empty after filtering to analysis_years.")

  agg_fun <- switch(
    cfg$bio$aggregation,
    
    sum = function(x) {
      if (all(is.na(x))) {
        NA_real_
      } else {
        sum(x, na.rm = TRUE)
      }
    },
    
    mean = function(x) {
      if (all(is.na(x))) {
        NA_real_
      } else {
        mean(x, na.rm = TRUE)
      }
    },
    
    median = function(x) {
      if (all(is.na(x))) {
        NA_real_
      } else {
        median(x, na.rm = TRUE)
      }
    }
  )

  bio_observed_yearly <- bio_raw |>
    dplyr::group_by(grid_id, year, bio_group) |>
    dplyr::summarise(bio_trait_var = agg_fun(bio_trait_var), .groups = "drop")

  # Screening is based on actually observed group-year rows, before any missing combinations are completed as zero.
  bio_screen <- bio_observed_yearly |>
    dplyr::group_by(grid_id, bio_group) |>
    dplyr::summarise(
      observed_years = dplyr::n_distinct(year[!is.na(bio_trait_var)]),
      non_missing_years = sum(!is.na(bio_trait_var)),
      non_zero_years = sum(bio_trait_var > 0, na.rm = TRUE),
      .groups = "drop"
    ) |>
    dplyr::mutate(
      keep = non_missing_years >= cfg$bio$min_non_missing_years &
        non_zero_years >= cfg$bio$min_non_zero_years
    )

  taxa_keep <- bio_screen |>
    dplyr::filter(keep) |>
    dplyr::select(grid_id, bio_group)

  if (!nrow(taxa_keep)) {
    stop("BIO: no groups passed screening. Check Bio_settings thresholds.")
  }

  bio_fit_input <- bio_observed_yearly |>
    dplyr::inner_join(taxa_keep, by = c("grid_id", "bio_group"))

  # Complete the annual time series for every retained group.
  # Newly created years are initialized either as 0 (confirmed absence)
  # or NA (missing observation), depending on the settings.
  
  if (cfg$bio$complete_missing_groups_as_zero) {
    
    bio_fit_input <- bio_fit_input |>
      group_by(grid_id, bio_group) |>
      complete(
        year = seq(yr[1], yr[2]),
        fill = list(bio_trait_var = 0),
        explicit = FALSE
      ) |>
      ungroup()
    
  } else {
    
    bio_fit_input <- bio_fit_input |>
      group_by(grid_id, bio_group) |>
      complete(
        year = seq(yr[1], yr[2])
      ) |>
      ungroup()
    
  }

  bio_segments <- bio_fit_input |>
    dplyr::group_by(grid_id, bio_group) |>
    dplyr::group_modify(~ segment_one_series(.x, cfg$seg)) |>
    dplyr::ungroup() |>
    add_bio_rates() |>
    dplyr::mutate(
      bio_analysis_start = yr[1],
      bio_analysis_end = yr[2],
      .before = 1
    )

  fitted_groups <- bio_segments |>
    dplyr::distinct(grid_id, bio_group) |>
    dplyr::mutate(fitted = TRUE)

  bio_screen <- bio_screen |>
    dplyr::left_join(fitted_groups, by = c("grid_id", "bio_group")) |>
    dplyr::mutate(fitted = dplyr::coalesce(fitted, FALSE)) |>
    dplyr::arrange(grid_id, dplyr::desc(keep), bio_group)

  bio_fit_input <- bio_fit_input |>
    dplyr::inner_join(fitted_groups, by = c("grid_id", "bio_group")) |>
    dplyr::select(-fitted)

  out_dir <- file.path(cfg$project$out_dir, "bio")
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

  writexl::write_xlsx(bio_observed_yearly, file.path(out_dir, "bio_yearly_observed_aggregated.xlsx"))
  writexl::write_xlsx(bio_fit_input, file.path(out_dir, "bio_yearly_input_for_segmentation.xlsx"))
  writexl::write_xlsx(bio_screen, file.path(out_dir, "bio_group_screening.xlsx"))
  writexl::write_xlsx(bio_segments, file.path(out_dir, "bio_segmented_rates.xlsx"))

  for (gid in unique(bio_fit_input$grid_id)) {
    groups <- split_pages(
      bio_fit_input$bio_group[bio_fit_input$grid_id == gid],
      per_page = 20
    )
    
    for (page_i in seq_along(groups)) {
      keep_groups <- groups[[page_i]]
      
      d_plot <- bio_fit_input |>
        dplyr::filter(grid_id == gid, bio_group %in% keep_groups)
      
      seg_plot <- bio_segments |>
        dplyr::filter(grid_id == gid, bio_group %in% keep_groups)
      
      cuts_plot <- seg_plot |>
        dplyr::filter(segmentation_accepted, seg_id == 1, is.finite(breakpoint_year)) |>
        dplyr::distinct(bio_group, breakpoint_year)
      
      p <- ggplot2::ggplot(d_plot, ggplot2::aes(year, bio_trait_var)) +
        ggplot2::geom_point(alpha = 0.6, size = 1) +
        ggplot2::geom_segment(
          data = seg_plot,
          ggplot2::aes(
            x = x1,
            xend = x2,
            y = bio_y_start_hat,
            yend = bio_y_end_hat
          ),
          inherit.aes = FALSE,
          linewidth = 0.9
        ) +
        ggplot2::geom_vline(
          data = cuts_plot,
          ggplot2::aes(xintercept = breakpoint_year),
          linetype = "dashed",
          alpha = 0.7
        ) +
        ggplot2::facet_wrap(~ bio_group, scales = "free_y") +
        ggplot2::theme_bw() +
        ggplot2::labs(
          title = paste0("BIO segmented rates: ", gid),
          subtitle = paste0("Page ", page_i, " of ", length(groups)),
          x = "Year",
          y = "BIO value"
        )
      
      ggplot2::ggsave(
        file.path(
          out_dir,
          paste0("bio_segments_", safe_slug(gid), "_p", sprintf("%02d", page_i), ".png")
        ),
        p,
        width = 14,
        height = 9,
        dpi = 300
      )
    }
  }

  list(
    observed_yearly = bio_observed_yearly,
    fit_input = bio_fit_input,
    screen = bio_screen,
    segments = bio_segments
  )
}

# ---- CHEM processing --------------------------------------------------

deseason_one_variable <- function(df, var) {
  fit_df <- df |>
    dplyr::filter(is.finite(.data[[var]]), !is.na(date), !is.na(month), is.finite(dec_year))

  des_col <- paste0(var, "_deseasoned")
  clim_col <- paste0(var, "_monthly_residual_clim")

  if (nrow(fit_df) < 12 || length(unique(fit_df$month)) < 2) {
    df[[des_col]] <- NA_real_
    df[[clim_col]] <- NA_real_
    return(df)
  }

  trend_fit <- lm(fit_df[[var]] ~ fit_df$dec_year)
  fit_df$resid_trend <- resid(trend_fit)

  clim <- fit_df |>
    dplyr::group_by(month) |>
    dplyr::summarise(!!clim_col := mean(resid_trend, na.rm = TRUE), .groups = "drop")

  out <- df |>
    dplyr::left_join(clim, by = "month")

  out[[des_col]] <- out[[var]] - out[[clim_col]]
  out
}

calc_tdt_qc <- function(x, y, min_months = 60) {
  ok <- is.finite(x) & is.finite(y)
  x <- x[ok]
  y <- y[ok]
  n <- length(y)

  base <- tibble::tibble(
    TDT = NA_real_, uTDT = NA_real_, omega0 = NA_real_,
    sigmaN = NA_real_, phi = NA_real_, tdt_n = n,
    tdt_qc = "FAIL", tdt_qc_reason = NA_character_
  )

  if (n < 24) {
    base$tdt_qc_reason <- "too_few_points_<24"
    return(base)
  }

  fit <- lm(y ~ x)
  omega0 <- unname(coef(fit)[2])
  res <- resid(fit)
  sigmaN <- sd(res, na.rm = TRUE)
  phi <- as.numeric(stats::acf(res, plot = FALSE, lag.max = 1)$acf[2])

  if (!is.finite(omega0) || omega0 == 0 || !is.finite(phi) || abs(phi) >= 0.999) {
    base$omega0 <- omega0
    base$sigmaN <- sigmaN
    base$phi <- phi
    base$tdt_qc_reason <- "invalid_trend_or_autocorrelation"
    return(base)
  }

  TDT <- ((3.3 * sigmaN / abs(omega0)) * sqrt((1 + phi) / (1 - phi)))^(2 / 3)
  B <- (4 / (3 * sqrt(n))) * sqrt((1 + phi) / (1 - phi))
  uTDT <- TDT * exp(B)

  qc <- if (n >= min_months && abs(phi) < 0.6) "OK" else "WARN"
  reason <- if (qc == "OK") "none" else paste(c(
    if (n < min_months) paste0("short_<", min_months, "_months"),
    if (abs(phi) >= 0.6) "high_autocorrelation_phi>=0.6"
  ), collapse = ";")

  tibble::tibble(
    TDT = TDT, uTDT = uTDT, omega0 = omega0,
    sigmaN = sigmaN, phi = phi, tdt_n = n,
    tdt_qc = qc, tdt_qc_reason = reason
  )
}

make_chem_monthly_table <- function(chem_deseasoned, vars, cfg) {
  yr <- cfg$chem$analysis_years

  pieces <- lapply(vars, function(var) {
    des_col <- paste0(var, "_deseasoned")

    chem_deseasoned |>
      dplyr::filter(year >= yr[1], year <= yr[2]) |>
      dplyr::mutate(monthly_date = lubridate::floor_date(date, "month")) |>
      dplyr::group_by(grid_id, monthly_date) |>
      dplyr::summarise(
        raw_monthly_mean = mean(.data[[var]], na.rm = TRUE),
        deseasoned_monthly_mean = mean(.data[[des_col]], na.rm = TRUE),
        n_obs = sum(is.finite(.data[[var]])),
        .groups = "drop"
      ) |>
      dplyr::mutate(
        chem_var = var,
        year = lubridate::year(monthly_date),
        dec_year = decimal_year(monthly_date),
        .before = 1
      )
  })

  dplyr::bind_rows(pieces)
}

fit_chem_rates <- function(chem_monthly, cfg) {
  yr <- cfg$chem$analysis_years
  x_start <- decimal_year(as.Date(paste0(yr[1], "-01-01")))
  x_end <- decimal_year(as.Date(paste0(yr[2], "-12-31")))

  chem_monthly |>
    dplyr::group_by(grid_id, chem_var) |>
    dplyr::group_modify(~ {
      d <- .x |>
        dplyr::filter(is.finite(dec_year), is.finite(deseasoned_monthly_mean))

      title <- label_lookup(cfg$chem_vars, unique(.y$chem_var), "title")
      ylab <- label_lookup(cfg$chem_vars, unique(.y$chem_var), "ylab")

      if (nrow(d) < cfg$chem$min_months_for_trend || length(unique(d$dec_year)) < 2) {
        return(tibble::tibble(
          chem_title = title,
          chem_ylab = ylab,
          chem_n_months = nrow(d),
          chem_analysis_start = yr[1],
          chem_analysis_end = yr[2],
          chem_y_start_hat = NA_real_,
          chem_y_end_hat = NA_real_,
          chem_abs_change = NA_real_,
          chem_rate_abs_per_year = NA_real_,
          chem_slope_se = NA_real_,
          chem_slope_p = NA_real_,
          chem_r2 = NA_real_,
          chem_adj_r2 = NA_real_,
          chem_status = "too_few_months"
        ))
      }

      fit <- lm(deseasoned_monthly_mean ~ dec_year, data = d)
      s <- summary(fit)
      y_start <- unname(coef(fit)[1] + coef(fit)[2] * x_start)
      y_end <- unname(coef(fit)[1] + coef(fit)[2] * x_end)
      tdt <- calc_tdt_qc(d$dec_year, d$deseasoned_monthly_mean, cfg$chem$tdt_min_months)

      tibble::tibble(
        chem_title = title,
        chem_ylab = ylab,
        chem_n_months = nrow(d),
        chem_analysis_start = yr[1],
        chem_analysis_end = yr[2],
        chem_y_start_hat = y_start,
        chem_y_end_hat = y_end,
        chem_abs_change = y_end - y_start,
        chem_rate_abs_per_year = unname(coef(fit)[2]),
        chem_slope_se = as.numeric(s$coefficients[2, 2]),
        chem_slope_p = as.numeric(s$coefficients[2, 4]),
        chem_r2 = as.numeric(s$r.squared),
        chem_adj_r2 = as.numeric(s$adj.r.squared),
        chem_status = "ok"
      ) |>
        dplyr::bind_cols(tdt)
    }) |>
    dplyr::ungroup()
}


# Diagnostic only: flexible curve for CHEM plots.
# It does NOT affect CHEM rates; rates still use the full-window linear trend.
fit_best_chem_curve <- function(d, min_n = 6, n_grid = 200) {
  d <- d |>
    dplyr::filter(is.finite(dec_year), is.finite(deseasoned_monthly_mean)) |>
    dplyr::arrange(dec_year)

  if (nrow(d) < min_n || length(unique(d$dec_year)) < 3) {
    return(list(
      curve = tibble::tibble(),
      model = tibble::tibble(
        best_fit_model = NA_character_,
        best_fit_adj_r2 = NA_real_,
        best_fit_note = "too_few_points"
      )
    ))
  }

  candidates <- list(
    linear = tryCatch(lm(deseasoned_monthly_mean ~ dec_year, data = d), error = function(e) NULL),
    poly2 = tryCatch(lm(deseasoned_monthly_mean ~ poly(dec_year, 2, raw = TRUE), data = d), error = function(e) NULL),
    poly3 = tryCatch(lm(deseasoned_monthly_mean ~ poly(dec_year, 3, raw = TRUE), data = d), error = function(e) NULL)
  )

  candidates <- candidates[!vapply(candidates, is.null, logical(1))]
  if (!length(candidates)) {
    return(list(
      curve = tibble::tibble(),
      model = tibble::tibble(
        best_fit_model = NA_character_,
        best_fit_adj_r2 = NA_real_,
        best_fit_note = "all_fits_failed"
      )
    ))
  }

  scores <- vapply(candidates, function(m) summary(m)$adj.r.squared, numeric(1))
  best_name <- names(scores)[which.max(scores)]
  best_fit <- candidates[[best_name]]

  xg <- seq(min(d$dec_year, na.rm = TRUE), max(d$dec_year, na.rm = TRUE), length.out = n_grid)
  pred <- as.numeric(predict(best_fit, newdata = data.frame(dec_year = xg)))

  list(
    curve = tibble::tibble(
      dec_year = xg,
      best_fit_value = pred,
      best_fit_model = best_name
    ),
    model = tibble::tibble(
      best_fit_model = best_name,
      best_fit_adj_r2 = as.numeric(scores[[best_name]]),
      best_fit_note = "diagnostic_plot_only_not_used_for_rate"
    )
  )
}

run_chem_pipeline <- function(cfg) {
  infile <- file.path(cfg$project$data_dir, cfg$project$abio_infile)
  if (!file.exists(infile)) stop("CHEM input file not found: ", infile)

  raw <- readxl::read_excel(infile, col_types = "text") |>
    apply_colmap(cfg$colmap_chem, "Abio_ColMap")

  check_required(raw, c("date", "grid_id"), "CHEM data")

  selected <- cfg$chem_vars$variable
  missing_vars <- setdiff(selected, names(raw))
  if (length(missing_vars)) {
    stop("These enabled Abio_selected_variables were not found in CHEM data after Abio_ColMap: ",
         paste(missing_vars, collapse = ", "))
  }

  chem <- raw |>
    dplyr::mutate(
      date = parse_mixed_date(date),
      grid_id = as.character(grid_id)
    ) |>
    dplyr::filter(!is.na(date), !is.na(grid_id), nzchar(grid_id))

  for (v in selected) {
    x <- trimws(as.character(chem[[v]]))
    non_empty <- sum(!is.na(x) & nzchar(x))
    chem[[v]] <- suppressWarnings(as.numeric(x))
    n_num <- sum(!is.na(chem[[v]]))
    if (non_empty > 0 && n_num == 0) {
      stop("CHEM variable `", v, "` could not be converted to numeric.")
    }
  }

  chem <- chem |>
    dplyr::mutate(
      year = lubridate::year(date),
      month = lubridate::month(date),
      day = lubridate::day(date),
      dec_year = decimal_year(date)
    )

  yr <- cfg$chem$analysis_years
  chem <- chem |>
    dplyr::filter(year >= yr[1], year <= yr[2])

  if (!nrow(chem)) stop("CHEM data empty after filtering to analysis_years.")

  deseasoned_by_grid <- chem |>
    split(chem$grid_id) |>
    lapply(function(dg) {
      for (v in selected) dg <- deseason_one_variable(dg, v)
      dg
    })

  chem_deseasoned <- dplyr::bind_rows(deseasoned_by_grid)
  chem_monthly <- make_chem_monthly_table(chem_deseasoned, selected, cfg)
  chem_rates <- fit_chem_rates(chem_monthly, cfg)

  if (!nrow(chem_rates)) stop("CHEM: no rates produced.")

  out_dir <- file.path(cfg$project$out_dir, "chem")
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

  writexl::write_xlsx(chem_deseasoned, file.path(out_dir, "chem_deseasoned_observations.xlsx"))
  writexl::write_xlsx(chem_monthly, file.path(out_dir, "chem_deseasoned_monthly.xlsx"))
  writexl::write_xlsx(chem_rates, file.path(out_dir, "chem_full_window_rates.xlsx"))

  label_titles <- setNames(
    vapply(selected, function(v) label_lookup(cfg$chem_vars, v, "title"), character(1)),
    selected
  )

  best_fit_models_all <- list()
  best_fit_curves_all <- list()

  for (gid in unique(chem$grid_id)) {
    raw_long <- chem |>
      dplyr::filter(grid_id == gid) |>
      dplyr::select(grid_id, date, dec_year, dplyr::all_of(selected)) |>
      tidyr::pivot_longer(dplyr::all_of(selected), names_to = "chem_var", values_to = "value") |>
      dplyr::mutate(series = "Raw observations")

    monthly_long <- chem_monthly |>
      dplyr::filter(grid_id == gid) |>
      dplyr::select(grid_id, monthly_date, dec_year, chem_var, raw_monthly_mean, deseasoned_monthly_mean) |>
      tidyr::pivot_longer(
        c(raw_monthly_mean, deseasoned_monthly_mean),
        names_to = "series",
        values_to = "value"
      ) |>
      dplyr::mutate(
        date = monthly_date,
        series = dplyr::recode(
          series,
          raw_monthly_mean = "Monthly mean",
          deseasoned_monthly_mean = "Deseasoned monthly mean"
        )
      ) |>
      dplyr::select(grid_id, date, dec_year, chem_var, value, series)

    trend_lines <- chem_rates |>
      dplyr::filter(grid_id == gid, chem_status == "ok") |>
      dplyr::mutate(
        x_start = decimal_year(as.Date(paste0(chem_analysis_start, "-01-01"))),
        x_end = decimal_year(as.Date(paste0(chem_analysis_end, "-12-31")))
      )

    best_by_var <- lapply(unique(monthly_long$chem_var), function(v) {
      d_v <- chem_monthly |>
        dplyr::filter(grid_id == gid, chem_var == v)

      bf <- fit_best_chem_curve(d_v)

      curve <- bf$curve
      if (nrow(curve)) {
        curve <- curve |>
          dplyr::mutate(grid_id = gid, chem_var = v)
      }

      model <- bf$model |>
        dplyr::mutate(
          grid_id = gid,
          chem_var = v,
          chem_title = label_lookup(cfg$chem_vars, v, "title"),
          .before = 1
        )

      list(curve = curve, model = model)
    })

    best_curves <- dplyr::bind_rows(lapply(best_by_var, `[[`, "curve"))
    best_models <- dplyr::bind_rows(lapply(best_by_var, `[[`, "model"))

    best_fit_curves_all[[gid]] <- best_curves
    best_fit_models_all[[gid]] <- best_models
    
    tdt_labels <- chem_rates |>
      dplyr::filter(grid_id == gid, chem_status == "ok") |>
      dplyr::mutate(
        label = paste0(
          "TDT: ",
          dplyr::if_else(is.finite(TDT), sprintf("%.1f y", TDT), "NA"),
          "\nQC: ", tdt_qc
        )
      )

    p <- ggplot2::ggplot() +
      ggplot2::geom_point(
        data = raw_long,
        ggplot2::aes(x = dec_year, y = value, colour = series),
        alpha = 0.35,
        size = 0.8
      ) +
      ggplot2::geom_point(
        data = monthly_long |> dplyr::filter(series == "Monthly mean"),
        ggplot2::aes(x = dec_year, y = value, colour = series),
        alpha = 0.8,
        size = 1.4
      ) +
      ggplot2::geom_point(
        data = monthly_long |> dplyr::filter(series == "Deseasoned monthly mean"),
        ggplot2::aes(x = dec_year, y = value, colour = series),
        alpha = 0.9,
        size = 1.4,
        shape = 15
      ) +
      ggplot2::geom_line(
        data = best_curves,
        ggplot2::aes(x = dec_year, y = best_fit_value, colour = "Best-fit diagnostic curve"),
        linewidth = 0.9
      ) +
      ggplot2::geom_segment(
        data = trend_lines,
        ggplot2::aes(x = x_start, xend = x_end, y = chem_y_start_hat, yend = chem_y_end_hat, colour = "Linear trend used for rate"),
        linewidth = 0.9
      ) +
      ggplot2::geom_text(
        data = tdt_labels,
        ggplot2::aes(
          x = -Inf,
          y = Inf,
          label = label
        ),
        inherit.aes = FALSE,
        hjust = -0.05,
        vjust = 1.1,
        size = 3
      )+
      ggplot2::facet_wrap(~ chem_var, scales = "free_y", labeller = ggplot2::as_labeller(label_titles)) +
      ggplot2::scale_colour_manual(
        values = c(
          "Raw observations" = "#6BAED6",              # light blue
          "Monthly mean" = "black",
          "Deseasoned monthly mean" = "brown2",
          "Linear trend used for rate" = "#8B0000",    # dark red
          "Best-fit diagnostic curve" = "aquamarine4"      # dark blue
        )
      )+
      ggplot2::theme_bw() +
      ggplot2::labs(
        title = paste0("CHEM deseasoning and full-window trends: ", gid),
        subtitle = "Dashed curve is diagnostic only; solid linear trend is used for CHEM rate calculation.",
        x = "Year",
        y = "Value",
        colour = "Series"
      )

    ggplot2::ggsave(
      file.path(out_dir, paste0("chem_trends_", safe_slug(gid), ".png")),
      p, width = 14, height = 9, dpi = 300
    )
  }

  chem_best_fit_models <- dplyr::bind_rows(best_fit_models_all)
  chem_best_fit_curves <- dplyr::bind_rows(best_fit_curves_all)

  if (nrow(chem_best_fit_models)) {
    writexl::write_xlsx(chem_best_fit_models, file.path(out_dir, "chem_best_fit_diagnostic_models.xlsx"))
  }

  if (nrow(chem_best_fit_curves)) {
    writexl::write_xlsx(chem_best_fit_curves, file.path(out_dir, "chem_best_fit_diagnostic_curves.xlsx"))
  }

  list(deseasoned = chem_deseasoned, monthly = chem_monthly, rates = chem_rates)
}

# ---- Pair BIO segments with full-window CHEM rates --------------------

pair_bio_chem <- function(cfg, bio_out, chem_out) {
  bio <- bio_out$segments
  chem <- chem_out$rates |>
    dplyr::filter(chem_status == "ok")

  common <- intersect(unique(bio$grid_id), unique(chem$grid_id))
  if (!length(common)) {
    warning("BIO x CHEM: no common grid_id values. Pairing skipped.")
    return(tibble::tibble())
  }

  # point_id identifies the BIO trajectory segment only.
  # The same BIO group-segment keeps the same point_id across all CHEM variables.
  bio_keyed <- bio |>
    dplyr::filter(grid_id %in% common) |>
    dplyr::arrange(grid_id, bio_group, seg_id, x1, x2) |>
    dplyr::mutate(
      point_id = dplyr::dense_rank(paste(grid_id, bio_group, seg_id, x1, x2, sep = "||")),
      .before = 1
    )

  paired <- bio_keyed |>
    dplyr::inner_join(chem |> dplyr::filter(grid_id %in% common), by = "grid_id",relationship = "many-to-many") |>
    dplyr::arrange(point_id, chem_var) |>
    dplyr::mutate(
      pair_note = "point_id identifies one unique BIO group-segment; the same point_id is repeated across CHEM variables. CHEM is full-window and not segmented.",
      .after = point_id
    )

  out_dir <- file.path(cfg$project$out_dir, "bio_chem")
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  writexl::write_xlsx(paired, file.path(out_dir, "bio_chem_rate_comparison.xlsx"))

  chem_titles <- paired |>
    dplyr::distinct(chem_var, chem_title)
  title_map <- setNames(chem_titles$chem_title, chem_titles$chem_var)

  plot_data <- paired |>
    dplyr::filter(is.finite(chem_rate_abs_per_year), is.finite(bio_rate_pct_per_year))

  p <- ggplot2::ggplot(
    plot_data,
    ggplot2::aes(
      x = chem_rate_abs_per_year,
      y = bio_rate_pct_per_year,
      colour = bio_duration_years
    )
  ) +
    ggplot2::geom_hline(yintercept = 0, linetype = "dotted") +
    ggplot2::geom_vline(xintercept = 0, linetype = "dotted") +
    ggplot2::geom_point(alpha = 0.85, size = 2.4) +
    ggrepel::geom_text_repel(
      ggplot2::aes(label = point_id),
      size = 2.4,
      max.overlaps = Inf,
      show.legend = FALSE
    ) +
    ggplot2::facet_wrap(~ chem_var, scales = "free_x", labeller = ggplot2::as_labeller(title_map)) +
    ggplot2::theme_bw() +
    ggplot2::labs(
      title = "BIO segment rates vs full-window CHEM rates",
      subtitle = "Same point_id = same BIO group-segment across all CHEM facets.",
      x = "CHEM rate, native units per year",
      y = "BIO rate, % of boundary maximum per year",
      colour = "BIO segment length\n(years)"
    )

  ggplot2::ggsave(file.path(out_dir, "bio_chem_rate_comparison.png"), p, width = 14, height = 9, dpi = 300)

  paired
}

# ---- Main -----------------------------------------------------------------

run_pipeline <- function(settings_file) {
  cfg <- read_config(settings_file)
  dir.create(cfg$project$out_dir, recursive = TRUE, showWarnings = FALSE)

  bio_out <- NULL
  chem_out <- NULL
  paired <- NULL

  if (cfg$project$run_bio) {
    message("Running BIO pipeline...")
    bio_out <- run_bio_pipeline(cfg)
  } else {
    message("BIO pipeline skipped: Project$run_bio = FALSE")
  }

  if (cfg$project$run_abio) {
    message("Running CHEM pipeline...")
    chem_out <- run_chem_pipeline(cfg)
  } else {
    message("CHEM pipeline skipped: Project$run_abio = FALSE")
  }

  if (!is.null(bio_out) && !is.null(chem_out)) {
    message("Pairing BIO segments with full-window CHEM rates...")
    paired <- pair_bio_chem(cfg, bio_out, chem_out)
  }

  if (cfg$project$log_runs) {
    cat(format(Sys.time()), "\tRun complete\n",
        file = file.path(cfg$project$out_dir, "run.log"),
        append = TRUE)
  }

  invisible(list(config = cfg, bio = bio_out, chem = chem_out, paired = paired))
}

run_pipeline(settings_file)
