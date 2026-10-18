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


# Harmonize municipal data -------------------------------------------------

harmonize_municipal_2025 <- function(survey) {
  # shortcut: past years retain the 2024 workbook cohort, rebuild them after the data audit.
  baseline <- readxl::read_excel(
    here::here("tabelas", "PEMOB Harmonizada 2024.xlsx"),
    sheet = "PEMOB Muni Harmonizada 24"
  )
  baseline <- as.data.frame(baseline)

  id_cols <- c("CÓDIGO IBGE", "UF", "Município")
  required_cols <- c(id_cols, "12.1.1", "1.3.1.A")
  if (!all(required_cols %in% names(survey))) {
    cli::cli_abort(
      "The municipal 2025 file lacks a required identifier or code."
    )
  }

  # SIMU: the municipal fund question moved from 12.2.1 to 12.1.1 in 2025.
  names(survey)[names(survey) == "12.1.1"] <- "12.2.1"
  baseline[["1.3.1.A"]] <- NA_character_

  indicator_cols <- setdiff(names(baseline), names(baseline)[1:8])
  baseline[indicator_cols] <- lapply(baseline[indicator_cols], as.character)
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

  states <- unique(baseline[c(
    "code_state",
    "abbrev_state",
    "name_state",
    "code_region",
    "name_region"
  )])
  if (!21 %in% states$code_state) {
    # Maranhão has no municipality in the 2024 workbook.
    states <- rbind(
      states,
      data.frame(
        code_state = 21,
        abbrev_state = "MA",
        name_state = "Maranhão",
        code_region = 2,
        name_region = "Nordeste"
      )
    )
  }
  if (anyDuplicated(states$code_state)) {
    cli::cli_abort("The 2024 workbook has conflicting state metadata.")
  }
  state_code <- as.numeric(substr(survey[["CÓDIGO IBGE"]], 1, 2))
  state_rows <- states[match(state_code, states$code_state), , drop = FALSE]
  if (
    anyNA(state_rows$code_state) ||
      any(state_rows$abbrev_state != survey[["UF"]])
  ) {
    cli::cli_abort(
      "The municipal 2025 state identifiers do not match the 2024 workbook."
    )
  }

  current <- baseline[rep(NA_integer_, nrow(survey)), , drop = FALSE]
  current$code_muni <- code_muni
  current$name_muni <- survey[["Município"]]
  current$code_state <- state_rows$code_state
  current$abbrev_state <- survey[["UF"]]
  current$name_state <- state_rows$name_state
  current$code_region <- state_rows$code_region
  current$name_region <- state_rows$name_region
  current$year <- 2025
  current[survey_codes] <- survey[survey_codes]

  result <- rbind(baseline, current)
  if (anyDuplicated(result[c("code_muni", "year")])) {
    cli::cli_abort(
      "The municipal data contain duplicate municipality-year keys."
    )
  }

  return(result)
}


# Harmonize metropolitan data ---------------------------------------------

harmonize_metro_2025 <- function(survey) {
  # shortcut: past years retain the 2024 workbook cohort, rebuild them after the data audit.
  baseline <- readxl::read_excel(
    here::here("tabelas", "PEMOB Harmonizada 2024.xlsx"),
    sheet = "PEMOB Metro Harmonizada 24"
  )
  baseline <- as.data.frame(baseline)

  metro_2024 <- readxl::read_excel(
    here::here("data-raw", "pemob_metropolitana_2024.xlsx"),
    skip = 1
  )
  baseline_names <- canonicalize_pemob_metro_name(
    metro_2024$UF,
    metro_2024$REGIÃO,
    pemob_metro_aliases
  )
  baseline_state <- metro_2024$UF[match(baseline$name_metro, baseline_names)]
  if (anyNA(baseline_state)) {
    cli::cli_abort(
      "The 2024 metro workbook does not identify every harmonized region."
    )
  }
  baseline$abbrev_state <- baseline_state
  baseline$metro_key <- build_pemob_metro_key(
    baseline$abbrev_state,
    baseline$name_metro
  )
  baseline$name_metro_source <- baseline$name_metro

  id_cols <- c("UF", "Região Metropolitana")
  if (!all(id_cols %in% names(survey))) {
    cli::cli_abort("The metropolitan 2025 file lacks an identifier column.")
  }

  indicator_cols <- setdiff(names(baseline), c("name_metro", "year"))
  baseline[indicator_cols] <- lapply(baseline[indicator_cols], as.character)
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
    pemob_metro_aliases
  )

  current <- baseline[rep(NA_integer_, nrow(survey)), , drop = FALSE]
  current$name_metro <- name_metro
  current$name_metro_source <- name_metro_source
  current$abbrev_state <- abbrev_state
  current$metro_key <- build_pemob_metro_key(abbrev_state, name_metro)
  current$year <- 2025
  current[survey_codes] <- survey[survey_codes]

  result <- rbind(baseline, current)
  if (anyDuplicated(result[c("metro_key", "year")])) {
    cli::cli_abort("The metropolitan data contain duplicate region-year keys.")
  }

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

  municipal <- harmonize_municipal_2025(municipal_source)
  metro <- harmonize_metro_2025(metro_source)

  readr::write_excel_csv2(
    municipal,
    here::here("data", "pemob_harmonizada_2025.csv")
  )
  readr::write_excel_csv2(
    metro,
    here::here("data", "pemob_metro_harmonizada_2025.csv")
  )
  cli::cli_alert_warning(
    "Historical years still use the 2024 workbook cohort; see ROADMAP.md."
  )
  cli::cli_alert_success(
    "Wrote the municipal and metropolitan harmonized datasets through 2025."
  )

  return(invisible(list(municipal = municipal, metro = metro)))
}

if (sys.nframe() == 0L) {
  build_pemob_2025()
}
