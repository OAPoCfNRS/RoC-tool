# ================= LAUNCHER =================
# Run this file from RStudio or with Rscript.
# It uses this file's folder as the project root.
# ===========================================

get_script_path <- function() {
  cmd_args <- commandArgs(trailingOnly = FALSE)
  file_idx <- grep("^--file=", cmd_args)
  if (length(file_idx)) {
    return(normalizePath(sub("^--file=", "", cmd_args[file_idx[1]])))
  }

  if (!is.null(sys.frames()[[1]]$ofile)) {
    return(normalizePath(sys.frames()[[1]]$ofile))
  }

  if (requireNamespace("rstudioapi", quietly = TRUE) && rstudioapi::isAvailable()) {
    path <- rstudioapi::getActiveDocumentContext()$path
    if (nzchar(path)) return(normalizePath(path))
  }

  stop("Cannot determine script path. Open and run this launcher file directly, or use Rscript.")
}

project_dir <- dirname(get_script_path())
setwd(project_dir)
message("Working directory: ", getwd())

settings_file <- "settings_configuration_v5.xlsx"
pipeline_file <- "ROC_v5_DO_NOT_RUN.R"

if (!file.exists(settings_file)) stop(settings_file, " not found in: ", getwd())
if (!file.exists(pipeline_file)) stop(pipeline_file, " not found in: ", getwd())

source(pipeline_file, chdir = TRUE)
