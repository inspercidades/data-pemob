source(here::here("R", "pemob_helpers.R"))

# Read 2025 files ----------------------------------------------------------

read_pemob_2025 <- function(path) {
  if (!file.exists(path)) {
    cli::cli_abort("The 2025 source file {.file {path}} does not exist.")
  }

  dat <- utils::read.csv(
    path,
    skip = 1,
    fileEncoding = "latin1",
    check.names = FALSE,
    colClasses = "character",
    na.strings = character(),
    strip.white = TRUE
  )

  if (anyNA(names(dat)) || any(names(dat) == "") || anyDuplicated(names(dat))) {
    cli::cli_abort(
      "The 2025 file {.file {path}} has missing or duplicate codes."
    )
  }

  return(dat)
}


# Read rebuilt history -----------------------------------------------------

read_pemob_history <- function(path) {
  if (!file.exists(path)) {
    cli::cli_abort(c(
      "The rebuilt history {.file {path}} does not exist.",
      "i" = "Run {.code Rscript R/build_pemob.R} to rebuild it."
    ))
  }

  dat <- readr::read_delim(
    path,
    delim = ";",
    col_types = readr::cols(.default = readr::col_character()),
    na = "",
    trim_ws = FALSE,
    progress = FALSE
  )

  if (!all(c("year", "participated") %in% names(dat))) {
    cli::cli_abort(
      "The history {.file {path}} lacks {.field year} or {.field participated}."
    )
  }

  dat$year <- as.numeric(dat$year)
  dat$participated <- as.logical(dat$participated)
  if ("code_muni" %in% names(dat)) {
    dat$code_muni <- as.numeric(dat$code_muni)
  }

  return(dat)
}


# Complete the place-year panel --------------------------------------------

complete_pemob_panel <- function(dat, place_cols, key_col) {
  places <- dat |>
    dplyr::arrange(dplyr::desc(year)) |>
    dplyr::distinct(dplyr::across(dplyr::all_of(key_col)), .keep_all = TRUE) |>
    dplyr::select(dplyr::all_of(place_cols))

  result <- dat |>
    dplyr::select(-dplyr::all_of(setdiff(place_cols, key_col))) |>
    tidyr::complete(.data[[key_col]], year) |>
    dplyr::mutate(participated = dplyr::coalesce(participated, FALSE)) |>
    dplyr::left_join(places, by = key_col) |>
    dplyr::relocate(dplyr::all_of(place_cols), year) |>
    dplyr::arrange(.data[[key_col]], year)

  return(result)
}


# Harmonize municipal data -------------------------------------------------

harmonize_municipal_2025 <- function(survey, history) {
  place_cols <- c("code_muni", "name_muni", "abbrev_state")
  history_cols <- c(place_cols, "year", "participated")
  if (!all(history_cols %in% names(history))) {
    cli::cli_abort("The municipal history lacks an identifier column.")
  }

  id_cols <- c("CÓDIGO IBGE", "UF", "Município")
  required_cols <- c(id_cols, "12.1.1", "1.3.1.A")
  if (!all(required_cols %in% names(survey))) {
    cli::cli_abort(
      "The municipal 2025 file lacks a required identifier or code."
    )
  }

  # SIMU: the municipal fund question moved from 12.2.1 to 12.1.1 in 2025.
  names(survey)[names(survey) == "12.1.1"] <- "12.2.1"
  if (!"1.3.1.A" %in% names(history)) {
    history[["1.3.1.A"]] <- NA_character_
  }

  indicator_cols <- setdiff(names(history), history_cols)
  survey_codes <- setdiff(names(survey), id_cols)
  unknown_codes <- setdiff(survey_codes, indicator_cols)
  if (length(unknown_codes) > 0L) {
    cli::cli_abort(
      "Unmapped municipal 2025 codes: {paste(unknown_codes, collapse = ', ')}"
    )
  }

  code_muni <- suppressWarnings(as.numeric(survey[["CÓDIGO IBGE"]]))
  if (anyNA(code_muni) || anyDuplicated(code_muni)) {
    cli::cli_abort("The municipal 2025 identifiers must be unique IBGE codes.")
  }

  history_states <- dplyr::distinct(history, code_muni, abbrev_state)
  known <- match(code_muni, history_states$code_muni)
  state_mismatch <- !is.na(known) &
    history_states$abbrev_state[known] != survey[["UF"]]
  if (any(state_mismatch)) {
    cli::cli_abort(
      "The municipal 2025 states do not match the history for {sum(state_mismatch)} municipalit{?y/ies}."
    )
  }

  current <- tibble::tibble(
    code_muni = code_muni,
    name_muni = survey[["Município"]],
    abbrev_state = survey[["UF"]],
    year = 2025,
    participated = TRUE
  )
  current[survey_codes] <- survey[survey_codes]

  # The history's municipality names take precedence over the 2025 spelling.
  history_names <- dplyr::distinct(history, code_muni, name_muni)
  known_names <- match(current$code_muni, history_names$code_muni)
  current$name_muni[!is.na(known_names)] <- history_names$name_muni[
    known_names[!is.na(known_names)]
  ]

  combined <- dplyr::bind_rows(history, current)
  if (anyDuplicated(combined[c("code_muni", "year")])) {
    cli::cli_abort(
      "The municipal data contain duplicate municipality-year keys."
    )
  }

  result <- complete_pemob_panel(combined, place_cols, "code_muni")
  return(result)
}


# Harmonize metropolitan data ---------------------------------------------

harmonize_metro_2025 <- function(
  survey,
  history,
  aliases = pemob_metro_aliases
) {
  place_cols <- c("metro_key", "abbrev_state", "name_metro")
  history_cols <- c(place_cols, "year", "participated")
  if (!all(history_cols %in% names(history))) {
    cli::cli_abort("The metropolitan history lacks an identifier column.")
  }

  id_cols <- c("UF", "Região Metropolitana")
  if (!all(id_cols %in% names(survey))) {
    cli::cli_abort("The metropolitan 2025 file lacks an identifier column.")
  }

  indicator_cols <- setdiff(
    names(history),
    c(history_cols, "name_metro_source")
  )
  survey_codes <- setdiff(names(survey), id_cols)
  unknown_codes <- setdiff(survey_codes, indicator_cols)
  if (length(unknown_codes) > 0L) {
    cli::cli_abort(
      "Unmapped metropolitan 2025 codes: {paste(unknown_codes, collapse = ', ')}"
    )
  }

  name_metro_source <- survey[["Região Metropolitana"]]
  abbrev_state <- survey[["UF"]]
  if (
    anyNA(name_metro_source) ||
      anyDuplicated(name_metro_source) ||
      anyNA(abbrev_state) ||
      any(!grepl("^[A-Z]{2}$", abbrev_state))
  ) {
    cli::cli_abort(
      "The metropolitan 2025 identifiers are invalid or duplicated."
    )
  }
  name_metro <- canonicalize_pemob_metro_name(
    abbrev_state,
    name_metro_source,
    aliases
  )

  current <- tibble::tibble(
    metro_key = build_pemob_metro_key(abbrev_state, name_metro),
    abbrev_state = abbrev_state,
    name_metro = name_metro,
    year = 2025,
    participated = TRUE,
    name_metro_source = name_metro_source
  )
  current[survey_codes] <- survey[survey_codes]

  combined <- dplyr::bind_rows(history, current)
  if (anyDuplicated(combined[c("metro_key", "year")])) {
    cli::cli_abort("The metropolitan data contain duplicate region-year keys.")
  }

  result <- complete_pemob_panel(combined, place_cols, "metro_key")
  return(result)
}


# Export -------------------------------------------------------------------

build_pemob_2025 <- function() {
  municipal_source <- read_pemob_2025(
    here::here("data-raw", "pemob_municipal_2025(pemob_municipal_25).csv")
  )
  metro_source <- read_pemob_2025(
    here::here(
      "data-raw",
      "pemob_metropolitana_2025(pemob_metropolitana_2025).csv"
    )
  )
  municipal_history <- read_pemob_history(
    here::here("data", "pemob_harmonizada_2024.csv")
  )
  metro_history <- read_pemob_history(
    here::here("data", "pemob_metro_harmonizada_2024.csv")
  )

  municipal <- harmonize_municipal_2025(municipal_source, municipal_history)
  metro <- harmonize_metro_2025(metro_source, metro_history)

  readr::write_excel_csv2(
    municipal,
    here::here("data", "pemob_harmonizada_2025.csv"),
    na = ""
  )
  readr::write_excel_csv2(
    metro,
    here::here("data", "pemob_metro_harmonizada_2025.csv"),
    na = ""
  )
  cli::cli_alert_success(
    "Wrote the municipal and metropolitan harmonized datasets through 2025."
  )

  return(invisible(list(municipal = municipal, metro = metro)))
}

if (sys.nframe() == 0L) {
  build_pemob_2025()
}
