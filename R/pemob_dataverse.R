# Prepare local long-form files for the Phase 4 Dataverse release.

source(here::here("R", "pemob_treatment.R"))
source(here::here("R", "pemob_question_registry.R"))


# Long observations -------------------------------------------------------

build_pemob_long <- function(panel, level, treated = NULL, registry = NULL) {
  if (!level %in% c("municipal", "metropolitan")) {
    cli::cli_abort("{.arg level} must be municipal or metropolitan.")
  }
  place_col <- if (level == "municipal") "code_muni" else "metro_key"
  name_col <- if (level == "municipal") "name_muni" else "name_metro"
  id_cols <- c(place_col, name_col, "abbrev_state", "year", "participated")
  if (!all(id_cols %in% names(panel))) {
    cli::cli_abort("The {level} panel lacks required identifier columns.")
  }
  if (
    anyNA(panel[c(place_col, "year")]) ||
      anyDuplicated(panel[c(place_col, "year")])
  ) {
    cli::cli_abort(
      "The {level} panel has incomplete or duplicate place-year keys."
    )
  }
  if (!is.logical(panel$participated) || anyNA(panel$participated)) {
    cli::cli_abort(
      "The {level} participation flag must be complete and logical."
    )
  }

  question_cols <- setdiff(names(panel), c(id_cols, "name_metro_source"))
  if (!all(vapply(panel[question_cols], is.character, logical(1)))) {
    cli::cli_abort("The {level} question responses must remain text.")
  }
  long <- panel[c(id_cols, question_cols)] |>
    tidyr::pivot_longer(
      cols = dplyr::all_of(question_cols),
      names_to = "code_variable",
      values_to = "value_raw",
      values_drop_na = FALSE
    )
  if (anyDuplicated(long[c(place_col, "year", "code_variable")])) {
    cli::cli_abort("The {level} long data have duplicate observation keys.")
  }

  parsed <- parse_pemob_response(long$value_raw)
  long$value_num <- parsed$parsed_value
  long$parsed_unit <- parsed$parsed_unit
  long$parse_status <- parsed$parse_status
  long$missing_code <- ifelse(
    parsed$missing_reason == "blank" & !is.na(parsed$missing_reason),
    "blank",
    ifelse(!is.na(parsed$missing_reason), long$value_raw, NA_character_)
  )
  long$value_type <- NA_character_
  long$unit <- NA_character_
  if (!is.null(registry)) {
    metadata_cols <- c(
      "level",
      "code_variable",
      "value_type",
      "unit",
      "reviewed_type_editions"
    )
    if (
      !all(metadata_cols %in% names(registry)) ||
        anyNA(registry[c("level", "code_variable")]) ||
        anyDuplicated(registry[c("level", "code_variable")])
    ) {
      cli::cli_abort(
        "The question registry needs unique, complete keys and metadata columns."
      )
    }
    selected_registry <- registry[registry$level == level, ]
    matches <- match(long$code_variable, selected_registry$code_variable)
    if (anyNA(matches)) {
      cli::cli_abort("The question registry lacks {level} panel codes.")
    }
    reviewed_years <- strsplit(
      ifelse(
        is.na(selected_registry$reviewed_type_editions[matches]),
        "",
        selected_registry$reviewed_type_editions[matches]
      ),
      ";",
      fixed = TRUE
    )
    supported <- mapply(
      function(year, editions) as.character(year) %in% editions,
      long$year,
      reviewed_years
    )
    long$value_type[supported] <- selected_registry$value_type[matches[
      supported
    ]]
    long$unit[supported] <- selected_registry$unit[matches[supported]]
  }
  long$value_treated <- long$value_num
  long$treatment_status <- ifelse(
    long$parse_status == "missing",
    "missing",
    "reported"
  )
  long$treatment_method <- NA_character_

  if (!is.null(treated)) {
    if (level != "municipal") {
      cli::cli_abort(
        "The current treatment series applies only to municipalities."
      )
    }
    treatment_cols <- c(
      "code_muni",
      "year",
      "code_variable",
      "raw_response",
      "treated_value",
      "treatment_status",
      "treatment_method"
    )
    if (
      !all(treatment_cols %in% names(treated)) ||
        anyDuplicated(treated[c("code_muni", "year", "code_variable")])
    ) {
      cli::cli_abort("The treatment series needs unique, complete target keys.")
    }
    matches <- match(
      build_pemob_candidate_id(
        long$code_muni,
        long$code_variable,
        long$year
      ),
      build_pemob_candidate_id(
        treated$code_muni,
        treated$code_variable,
        treated$year
      )
    )
    selected <- which(!is.na(matches))
    submitted <- selected[!is.na(long$value_raw[selected])]
    stale <- submitted[
      is.na(treated$raw_response[matches[submitted]]) |
        treated$raw_response[matches[submitted]] != long$value_raw[submitted]
    ]
    if (length(stale) > 0L) {
      cli::cli_abort("Treatment responses differ from the rebuilt panel.")
    }
    untreated_absent <- selected[
      is.na(long$value_raw[selected]) &
        !is.na(treated$raw_response[matches[selected]]) &
        nzchar(treated$raw_response[matches[selected]])
    ]
    if (length(untreated_absent) > 0L) {
      cli::cli_abort("A treatment claims source text for an absent cell.")
    }
    long$value_treated[selected] <- treated$treated_value[matches[selected]]
    long$treatment_status[selected] <- treated$treatment_status[matches[
      selected
    ]]
    long$treatment_method[selected] <- treated$treatment_method[matches[
      selected
    ]]
  }

  keep <- (long$participated & !is.na(long$value_raw)) |
    long$treatment_status %in% c("reconstructed", "interpolated")
  long <- long[keep, ]

  long$level <- level
  long$place_key <- as.character(long[[place_col]])
  long$place_name <- as.character(long[[name_col]])
  result <- long |>
    dplyr::select(
      level,
      place_key,
      place_name,
      abbrev_state,
      participated,
      dplyr::all_of(place_col),
      year,
      code_variable,
      value_raw,
      value_num,
      value_type,
      unit,
      parsed_unit,
      parse_status,
      missing_code,
      value_treated,
      treatment_status,
      treatment_method
    ) |>
    dplyr::arrange(place_key, year, code_variable)
  return(result)
}

build_pemob_participation_export <- function(municipal, metro) {
  municipal_rows <- municipal |>
    dplyr::transmute(
      level = "municipal",
      place_key = as.character(code_muni),
      place_name = name_muni,
      abbrev_state,
      year,
      participated
    )
  metro_rows <- metro |>
    dplyr::transmute(
      level = "metropolitan",
      place_key = metro_key,
      place_name = name_metro,
      abbrev_state,
      year,
      participated
    )
  result <- dplyr::bind_rows(municipal_rows, metro_rows) |>
    dplyr::arrange(level, place_key, year)
  if (anyDuplicated(result[c("level", "place_key", "year")])) {
    cli::cli_abort("The participation table has duplicate place-year keys.")
  }
  return(result)
}

check_pemob_treatment_coverage <- function(municipal, treated) {
  expected <- tidyr::expand_grid(
    municipal[c("code_muni", "year")],
    code_variable = pemob_target_variables
  )
  key_cols <- c("code_muni", "year", "code_variable")
  absent <- dplyr::anti_join(expected, treated, by = key_cols)
  extra <- dplyr::anti_join(treated, expected, by = key_cols)
  if (nrow(absent) > 0L || nrow(extra) > 0L) {
    cli::cli_abort(
      "The treatment series does not cover every target panel cell."
    )
  }
  return(invisible(TRUE))
}


# Edition codebook --------------------------------------------------------

read_pemob_question_header <- function(path, id_count) {
  header <- utils::read.csv(
    path,
    header = FALSE,
    nrows = 2,
    colClasses = "character",
    na.strings = character(),
    fileEncoding = "latin1",
    check.names = FALSE
  )
  codes <- unname(unlist(header[2, -(seq_len(id_count))]))
  texts <- unname(unlist(header[1, -(seq_len(id_count))]))
  tibble::tibble(source_code = codes, question_text = texts)
}

read_pemob_crosswalk_for_export <- function(level) {
  sheet <- if (level == "municipal") {
    "pemob_municipal"
  } else {
    "pemob_metropolitana"
  }
  crosswalk <- readxl::read_excel(
    here::here("data-raw", "pemob_códigos.xlsx"),
    sheet = sheet
  ) |>
    janitor::clean_names()
  if (level == "municipal") {
    crosswalk <- repair_pemob_municipal_crosswalk(
      crosswalk,
      read_pemob_code_repairs()
    )
  }
  result <- correct_pemob_crosswalk(
    crosswalk,
    read_pemob_crosswalk_corrections(),
    level = level
  )
  return(result)
}

build_pemob_codebook <- function() {
  outputs <- list()
  for (level in c("municipal", "metropolitan")) {
    crosswalk <- read_pemob_crosswalk_for_export(level)
    years <- if (level == "municipal") 2019:2024 else c(2019, 2021:2024)
    for (year in years) {
      source_codes <- as.character(crosswalk[[paste0("x", year)]])
      linked <- tibble::tibble(
        level = level,
        year = year,
        code_variable = as.character(crosswalk$x2024),
        source_code = source_codes
      ) |>
        dplyr::filter(!is.na(source_code), nzchar(source_code)) |>
        dplyr::distinct()

      dict_path <- here::here(
        "data",
        paste0(
          "dicionario_variaveis_pemob_",
          if (level == "metropolitan") "metro_" else "",
          year,
          ".csv"
        )
      )
      if (file.exists(dict_path)) {
        dictionary <- readr::read_csv(
          dict_path,
          col_types = readr::cols(.default = readr::col_character()),
          na = character(),
          show_col_types = FALSE
        ) |>
          dplyr::transmute(
            source_code = code_variable,
            question_text = name_variable
          ) |>
          dplyr::distinct(source_code, .keep_all = TRUE)
        linked <- dplyr::left_join(linked, dictionary, by = "source_code")
      } else {
        linked$question_text <- NA_character_
      }
      outputs[[length(outputs) + 1L]] <- linked
    }

    raw_2025 <- if (level == "municipal") {
      here::here("data-raw", "pemob_municipal_2025(pemob_municipal_25).csv")
    } else {
      here::here(
        "data-raw",
        "pemob_metropolitana_2025(pemob_metropolitana_2025).csv"
      )
    }
    current <- read_pemob_question_header(
      raw_2025,
      if (level == "municipal") 3L else 2L
    )
    current$level <- level
    current$year <- 2025
    current$code_variable <- current$source_code
    if (level == "municipal") {
      current$code_variable[current$source_code == "12.1.1"] <- "12.2.1"
    }
    outputs[[length(outputs) + 1L]] <- current |>
      dplyr::select(level, year, code_variable, source_code, question_text)
  }
  result <- dplyr::bind_rows(outputs) |>
    dplyr::distinct() |>
    dplyr::arrange(level, year, code_variable, source_code)
  if (
    anyDuplicated(result[c(
      "level",
      "year",
      "code_variable",
      "source_code"
    )])
  ) {
    cli::cli_abort("The edition codebook has duplicate keys.")
  }
  return(result)
}


# Local draft export ------------------------------------------------------

read_pemob_treated_export <- function(path) {
  dat <- readr::read_csv(
    path,
    col_types = readr::cols(.default = readr::col_character()),
    na = character(),
    show_col_types = FALSE
  )
  dat$code_muni <- as.numeric(dat$code_muni)
  dat$year <- as.numeric(dat$year)
  dat$parsed_value <- suppressWarnings(as.numeric(dat$parsed_value))
  dat$treated_value <- suppressWarnings(as.numeric(dat$treated_value))
  return(dat)
}

build_pemob_treatment_ledger_export <- function(treated) {
  result <- treated |>
    dplyr::filter(
      treatment_status %in%
        c(
          "pending",
          "accepted",
          "corrected",
          "excluded",
          "reconstructed",
          "interpolated"
        )
    ) |>
    dplyr::mutate(
      level = "municipal",
      source_file = unname(
        pemob_municipal_source_files[as.character(year)]
      )
    ) |>
    dplyr::select(
      level,
      code_muni,
      name_muni,
      abbrev_state,
      year,
      code_variable,
      raw_response,
      parsed_value,
      treated_value,
      treatment_status,
      treatment_method,
      review_evidence,
      reviewer,
      source_file
    ) |>
    dplyr::arrange(code_variable, code_muni, year)
  return(result)
}

check_pemob_export_coverage <- function(exports, treated) {
  long_codes <- dplyr::bind_rows(
    dplyr::select(
      exports$municipal_long,
      level,
      year,
      code_variable
    ),
    dplyr::select(
      exports$metropolitan_long,
      level,
      year,
      code_variable
    )
  ) |>
    dplyr::distinct()
  codebook_codes <- dplyr::distinct(
    exports$codebook,
    level,
    year,
    code_variable
  )
  missing_codes <- dplyr::anti_join(
    long_codes,
    codebook_codes,
    by = c("level", "year", "code_variable")
  )
  if (nrow(missing_codes) > 0L) {
    cli::cli_abort("The codebook lacks questions present in the long files.")
  }

  filled_statuses <- c("reconstructed", "interpolated")
  expected_filled <- sum(treated$treatment_status %in% filled_statuses)
  actual_filled <- sum(
    exports$municipal_long$treatment_status %in% filled_statuses
  )
  if (expected_filled != actual_filled) {
    cli::cli_abort("The long file does not retain every treated gap.")
  }
  return(invisible(TRUE))
}

.pemob_draft_files <- c(
  "municipal_long.csv",
  "metropolitan_long.csv",
  "participation.csv",
  "codebook.csv",
  "treatment_ledger.csv"
)
.pemob_draft_marker <- ".pemob_dataverse_draft"
.pemob_draft_marker_text <- "pemob_dataverse_draft_v1"

is_pemob_source_tree_dirty <- function(status, output_relative) {
  if (!is.raw(status)) {
    return(TRUE)
  }
  if (length(status) == 0L) {
    return(FALSE)
  }
  if (
    !is.character(output_relative) ||
      length(output_relative) != 1L ||
      is.na(output_relative) ||
      !nzchar(output_relative)
  ) {
    return(length(status) > 0L)
  }
  ends <- which(status == as.raw(0))
  if (length(ends) == 0L || tail(ends, 1L) != length(status)) {
    return(TRUE)
  }
  output_bytes <- charToRaw(output_relative)
  child_prefix <- charToRaw(paste0(output_relative, "/"))
  tracked_codes <- c(" ", "M", "A", "D", "R", "C", "U", "T")
  start <- 1L
  for (end in ends) {
    if (end - start < 4L) {
      return(TRUE)
    }
    record <- status[start:(end - 1L)]
    code <- rawToChar(record[1:2])
    valid_code <- code %in%
      c("??", "!!") ||
      all(strsplit(code, "", fixed = TRUE)[[1]] %in% tracked_codes) &&
        code != "  "
    if (!valid_code || !identical(record[[3]], charToRaw(" "))) {
      return(TRUE)
    }
    path <- record[-(1:3)]
    generated <- identical(path, output_bytes) ||
      length(path) >= length(child_prefix) &&
        identical(path[seq_along(child_prefix)], child_prefix)
    if (!generated) {
      return(TRUE)
    }
    start <- end + 1L
  }
  return(FALSE)
}

read_pemob_git_status <- function() {
  status_file <- tempfile("pemob_git_status_")
  on.exit(unlink(status_file), add = TRUE)
  exit_status <- tryCatch(
    system2(
      "git",
      c(
        "status",
        "--porcelain=v1",
        "-z",
        "--no-renames",
        "--untracked-files=all"
      ),
      stdout = status_file
    ),
    error = function(e) NA_integer_
  )
  if (!identical(exit_status, 0L)) {
    return(NULL)
  }
  size <- file.info(status_file)$size
  if (is.na(size)) {
    return(NULL)
  }
  status <- readBin(status_file, what = "raw", n = size)
  if (length(status) != size) {
    return(NULL)
  }
  return(status)
}

.check_pemob_draft_target <- function(output_dir) {
  if (
    !is.character(output_dir) ||
      length(output_dir) != 1L ||
      is.na(output_dir) ||
      !nzchar(output_dir)
  ) {
    cli::cli_abort("{.arg output_dir} must be one directory path.")
  }
  link <- Sys.readlink(output_dir)
  if (!is.na(link) && nzchar(link)) {
    cli::cli_abort("{.arg output_dir} cannot be a symbolic link.")
  }
  output_path <- normalizePath(output_dir, winslash = "/", mustWork = FALSE)
  repo_root <- normalizePath(here::here(), winslash = "/")
  input_dirs <- c(
    repo_root,
    normalizePath(here::here("data"), winslash = "/"),
    normalizePath(here::here("data-raw"), winslash = "/"),
    normalizePath(here::here("tabelas"), winslash = "/")
  )
  if (
    output_path %in%
      input_dirs ||
      startsWith(repo_root, paste0(output_path, "/"))
  ) {
    cli::cli_abort("{.arg output_dir} points to a project or input directory.")
  }
  if (file.exists(output_path) && !dir.exists(output_path)) {
    cli::cli_abort("{.arg output_dir} points to an existing file.")
  }
  if (!dir.exists(output_path)) {
    return(output_path)
  }

  expected <- c(.pemob_draft_marker, "manifest.csv", .pemob_draft_files)
  present <- list.files(output_path, all.files = TRUE, no.. = TRUE)
  marker_path <- file.path(output_path, .pemob_draft_marker)
  expected_paths <- file.path(output_path, expected)
  links <- Sys.readlink(expected_paths)
  if (
    !setequal(present, expected) ||
      any(!is.na(links) & nzchar(links)) ||
      any(file.info(expected_paths)$isdir) ||
      !identical(readLines(marker_path, warn = FALSE), .pemob_draft_marker_text)
  ) {
    cli::cli_abort("{.arg output_dir} is not an owned Dataverse draft.")
  }
  manifest <- tryCatch(
    readr::read_csv(
      file.path(output_path, "manifest.csv"),
      show_col_types = FALSE
    ),
    error = function(e) NULL
  )
  if (
    is.null(manifest) ||
      !identical(
        names(manifest),
        c("file", "rows", "md5", "git_commit", "working_tree_dirty")
      ) ||
      !identical(manifest$file, .pemob_draft_files) ||
      anyNA(manifest$rows) ||
      any(manifest$rows < 0) ||
      !identical(
        manifest$md5,
        unname(tools::md5sum(file.path(output_path, .pemob_draft_files)))
      )
  ) {
    cli::cli_abort("{.arg output_dir} has an invalid draft manifest.")
  }
  return(output_path)
}

.write_pemob_dataverse_draft <- function(
  exports,
  output_dir,
  commit,
  dirty,
  rename = file.rename
) {
  if (!identical(paste0(names(exports), ".csv"), .pemob_draft_files)) {
    cli::cli_abort("The draft exports have an unexpected file inventory.")
  }
  output_path <- .check_pemob_draft_target(output_dir)
  parent <- dirname(output_path)
  if (!dir.exists(parent) && !dir.create(parent, recursive = TRUE)) {
    cli::cli_abort("Could not create the draft export parent directory.")
  }
  draft <- tempfile("pemob_dataverse_", tmpdir = parent)
  if (!dir.create(draft)) {
    cli::cli_abort("Could not create the temporary draft directory.")
  }
  on.exit(unlink(draft, recursive = TRUE), add = TRUE)
  for (i in seq_along(exports)) {
    readr::write_csv(
      exports[[i]],
      file.path(draft, .pemob_draft_files[[i]]),
      na = ""
    )
  }
  manifest <- tibble::tibble(
    file = .pemob_draft_files,
    rows = vapply(exports, nrow, integer(1)),
    md5 = unname(tools::md5sum(file.path(draft, .pemob_draft_files))),
    git_commit = commit,
    working_tree_dirty = dirty
  )
  readr::write_csv(manifest, file.path(draft, "manifest.csv"))
  writeLines(.pemob_draft_marker_text, file.path(draft, .pemob_draft_marker))

  .check_pemob_draft_target(output_path)
  backup <- tempfile("pemob_dataverse_previous_", tmpdir = parent)
  if (dir.exists(output_path) && !file.rename(output_path, backup)) {
    cli::cli_abort("Could not move the previous draft export aside.")
  }
  installed <- tryCatch(rename(draft, output_path), error = function(e) FALSE)
  if (!isTRUE(installed)) {
    if (dir.exists(backup) && !file.rename(backup, output_path)) {
      cli::cli_abort(
        "Could not restore the previous draft at {.file {backup}}."
      )
    }
    cli::cli_abort("Could not install the new draft export.")
  }
  if (dir.exists(backup)) {
    unlink(backup, recursive = TRUE)
  }
  return(invisible(output_path))
}

build_pemob_dataverse <- function(
  output_dir = here::here("data", "dataverse_draft")
) {
  .check_pemob_draft_target(output_dir)
  municipal <- read_pemob_history(
    here::here("data", "pemob_harmonizada_2025.csv")
  )
  metro <- read_pemob_history(
    here::here("data", "pemob_metro_harmonizada_2025.csv")
  )
  treated <- read_pemob_treated_export(
    here::here("data", "pemob_target_treated.csv")
  )
  check_pemob_treatment_coverage(municipal, treated)
  registry <- read_pemob_question_registry()
  exports <- list(
    municipal_long = build_pemob_long(
      municipal,
      "municipal",
      treated,
      registry
    ),
    metropolitan_long = build_pemob_long(
      metro,
      "metropolitan",
      registry = registry
    ),
    participation = build_pemob_participation_export(municipal, metro),
    codebook = build_pemob_codebook(),
    treatment_ledger = build_pemob_treatment_ledger_export(treated)
  )
  check_pemob_export_coverage(exports, treated)

  commit <- system2("git", c("rev-parse", "HEAD"), stdout = TRUE)
  repo_root <- normalizePath(here::here(), winslash = "/")
  output_path <- normalizePath(output_dir, winslash = "/", mustWork = FALSE)
  output_relative <- if (startsWith(output_path, paste0(repo_root, "/"))) {
    substring(output_path, nchar(repo_root) + 2L)
  } else {
    NA_character_
  }
  status <- read_pemob_git_status()
  dirty <- is_pemob_source_tree_dirty(status, output_relative)

  .write_pemob_dataverse_draft(exports, output_dir, commit[[1]], dirty)
  cli::cli_alert_success(
    "Wrote local Dataverse draft files to {.file {output_dir}}."
  )
  return(invisible(exports))
}

if (sys.nframe() == 0L) {
  build_pemob_dataverse()
}
