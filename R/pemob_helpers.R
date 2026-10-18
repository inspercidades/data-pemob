filter_pemob_municipal_respondents <- function(dat) {
  code_muni <- suppressWarnings(as.numeric(dat[["code_muni"]]))
  name_muni <- trimws(as.character(dat[["name_muni"]]))
  respondent <- is.finite(code_muni) &
    nchar(as.character(code_muni)) == 7L &
    !is.na(name_muni) &
    nzchar(name_muni)

  result <- dat[respondent, , drop = FALSE]
  result[["code_muni"]] <- code_muni[respondent]

  if (anyDuplicated(result[["code_muni"]])) {
    cli::cli_abort("The municipal source has duplicate respondent codes.")
  }

  return(result)
}

join_pemob_editions <- function(editions, by) {
  invalid_keys <- purrr::map_lgl(editions, function(dat) {
    !all(by %in% names(dat)) || anyNA(dat[by]) || anyDuplicated(dat[by])
  })

  if (any(invalid_keys)) {
    cli::cli_abort("Each edition must have unique, nonmissing join keys.")
  }

  result <- purrr::reduce(editions, dplyr::full_join, by = by)
  return(result)
}

build_pemob_participation <- function(editions, by) {
  participation <- purrr::imap(editions, function(dat, edition) {
    result <- unique(dat[by])
    result$year <- as.numeric(stringr::str_remove(edition, "^year_"))
    result$participated <- TRUE
    return(result)
  })

  result <- dplyr::bind_rows(participation)
  return(result)
}

build_pemob_municipality_dimension <- function(editions) {
  id_cols <- c("code_muni", "name_muni", "abbrev_state")
  missing_cols <- purrr::map_lgl(editions, function(dat) {
    !all(id_cols %in% names(dat))
  })

  if (any(missing_cols)) {
    cli::cli_abort("Municipal editions must include code, name, and state.")
  }

  identifiers <- lapply(editions, function(dat) {
    dat[id_cols]
  })
  result <- dplyr::bind_rows(identifiers)
  state_conflicts <- vapply(
    split(result$abbrev_state, result$code_muni),
    function(states) length(unique(states)) > 1L,
    logical(1)
  )

  if (any(state_conflicts)) {
    cli::cli_abort("A municipal code is associated with multiple states.")
  }

  result <- result[!duplicated(result$code_muni), , drop = FALSE]
  return(result)
}

repair_pemob_municipal_crosswalk <- function(dat) {
  changed_question <- dat$x2024 == "1.4.1.B"
  dat$x2019[changed_question] <- NA_character_

  return(dat)
}

pemob_metro_aliases <- data.frame(
  abbrev_state = c(
    "AL",
    "BA",
    "ES",
    "GO",
    "MG",
    "PB",
    "PE",
    "PR",
    "RJ",
    "RN",
    "SP",
    "SP",
    "SP",
    "SP",
    "SP"
  ),
  source_name = c(
    "RM Maceió",
    "RM Salvador",
    "RM Grande Vitória",
    "RM Goiânia",
    "RM Belo Horizonte",
    "RM João Pessoa",
    "RM Recife",
    "RM Curitiba",
    "RM Rio de Janeiro",
    "RM Natal",
    "RM Baixada Santista",
    "RM Campinas",
    "RM São Paulo",
    "RM Sorocaba",
    "RM Vale do Paraíba e Litoral Norte"
  ),
  canonical_name = c(
    "Região Metropolitana de Maceió",
    "Região Metropolitana de Salvador",
    "Região Metropolitana da Grande Vitória",
    "Região Metropolitana de Goiânia",
    "Região Metropolitana de Belo Horizonte",
    "Região Metropolitana de João Pessoa",
    "Região Metropolitana de Recife",
    "Região Metropolitana de Curitiba",
    "Região Metropolitana do Rio de Janeiro",
    "Região Metropolitana de Natal",
    "Região Metropolitana da Baixada Santista",
    "Região Metropolitana de Campinas",
    "Região Metropolitana de São Paulo",
    "Região Metropolitana de Sorocaba",
    "Região Metropolitana do Vale do Paraíba e Litoral Norte"
  ),
  stringsAsFactors = FALSE
)

canonicalize_pemob_metro_name <- function(abbrev_state, name_metro, aliases) {
  if (length(abbrev_state) != length(name_metro)) {
    cli::cli_abort("Metro state and name vectors must have equal lengths.")
  }

  alias_key <- paste(aliases$abbrev_state, aliases$source_name, sep = "::")
  if (anyDuplicated(alias_key)) {
    cli::cli_abort(
      "Metro aliases must have unique state and source-name pairs."
    )
  }

  source_key <- paste(abbrev_state, name_metro, sep = "::")
  alias_match <- match(source_key, alias_key)
  result <- name_metro
  matched <- !is.na(alias_match)
  result[matched] <- aliases$canonical_name[alias_match[matched]]

  return(result)
}

build_pemob_metro_key <- function(abbrev_state, name_metro) {
  if (length(abbrev_state) != length(name_metro)) {
    cli::cli_abort("Metro state and name vectors must have equal lengths.")
  }

  result <- paste(abbrev_state, name_metro, sep = "::")
  return(result)
}

add_pemob_metro_identity <- function(dat) {
  valid <- !is.na(dat$abbrev_state) &
    grepl("^[A-Z]{2}$", dat$abbrev_state) &
    !dat$abbrev_state %in% c("NA", "NR", "ND") &
    !is.na(dat$name_metro) &
    nzchar(trimws(dat$name_metro)) &
    !toupper(trimws(dat$name_metro)) %in% c("NA", "NR", "ND", "-")
  result <- dat[valid, , drop = FALSE]
  result$name_metro <- canonicalize_pemob_metro_name(
    result$abbrev_state,
    result$name_metro,
    pemob_metro_aliases
  )
  result$metro_key <- build_pemob_metro_key(
    result$abbrev_state,
    result$name_metro
  )

  if (anyDuplicated(result$metro_key)) {
    cli::cli_abort("The metropolitan source has duplicate state-region keys.")
  }

  return(result)
}

read_pemob_source <- function(path, skip = 0) {
  result <- readxl::read_excel(
    path,
    skip = skip,
    col_types = "text",
    na = character()
  )
  cells <- readxl::read_excel(
    path,
    skip = skip,
    col_types = "list",
    na = character()
  )
  for (column in seq_along(result)) {
    dates <- vapply(cells[[column]], inherits, logical(1), what = "POSIXt")
    result[[column]][dates] <- vapply(
      cells[[column]][dates],
      as.character,
      character(1)
    )
  }
  # shortcut: readxl merges blank and Excel-error cells as NA; inspect XML if errors appear.
  result[] <- lapply(result, function(column) {
    column[is.na(column)] <- ""
    return(column)
  })

  return(result)
}

parse_pemob_response <- function(response) {
  raw_response <- as.character(response)
  text <- trimws(raw_response)
  normalized_text <- toupper(text)
  missing_reason <- rep(NA_character_, length(text))
  missing_reason[is.na(text) | normalized_text == "NA"] <- "NA"
  missing_reason[
    normalized_text %in% c("NR", "NÃO RESPONDEU", "NAO RESPONDEU")
  ] <- "NR"
  missing_reason[normalized_text == "ND"] <- "ND"
  missing_reason[normalized_text == "N/D"] <- "N/D"
  missing_reason[normalized_text == "N/A"] <- "N/A"
  missing_reason[
    normalized_text %in% c("NÃO DISPONÍVEL", "NAO DISPONIVEL")
  ] <- "not_available"
  missing_reason[
    normalized_text %in% c("SEM INFORMAÇÃO", "SEM INFORMACAO")
  ] <- "no_information"
  missing_reason[
    normalized_text %in% c("NÃO SE APLICA", "NAO SE APLICA")
  ] <- "not_applicable"
  missing_reason[
    normalized_text %in% c("NÃO INFORMADO", "NAO INFORMADO")
  ] <- "not_reported"
  excel_errors <- normalized_text %in%
    c(
      "#N/A",
      "#VALUE!",
      "#DIV/0!",
      "#REF!",
      "#NAME?",
      "#NUM!",
      "#NULL!"
    )
  missing_reason[excel_errors] <- normalized_text[excel_errors]
  missing_reason[text == "-"] <- "-"
  missing_reason[!is.na(text) & text == ""] <- "blank"
  is_missing <- !is.na(missing_reason)

  has_currency <- grepl("^(R\\$|RS)[[:space:]]*", text, ignore.case = TRUE)
  number <- sub("^(R\\$|RS)[[:space:]]*", "", text, ignore.case = TRUE)
  has_km <- grepl(
    "[[:space:]]*(km|quil[oô]metros?)$",
    number,
    ignore.case = TRUE
  )
  has_m <- !has_km &
    grepl("[[:space:]]*(m|metros?)$", number, ignore.case = TRUE)
  parsed_unit <- rep(NA_character_, length(number))
  parsed_unit[has_currency] <- "BRL"
  parsed_unit[has_km] <- "km"
  parsed_unit[has_m] <- "m"
  number <- sub(
    "[[:space:]]*(km|quil[oô]metros?|m|metros?)$",
    "",
    number,
    ignore.case = TRUE
  )

  ambiguous_separator <- grepl("^[+-]?[1-9][0-9]{0,2}[.,][0-9]{3}$", number)
  grouped_thousands <- grepl("^[0-9]{1,3}(\\.[0-9]{3}){2,}$", number) |
    grepl("^[0-9]{1,3}(,[0-9]{3}){2,}$", number)
  grouped_decimal <- grepl("^[0-9]{1,3}(\\.[0-9]{3})+,[0-9]+$", number)
  scientific_number <- grepl(
    "^[+-]?[0-9]+[.,]?[0-9]*[eE][+-]?[0-9]+$",
    number
  )
  simple_number <- grepl("^[+-]?[0-9]+$", number) |
    grepl("^[+-]?[0-9]+[.,][0-9]+$", number)
  logical_response <- !is.na(text) &
    toupper(text) %in% c("TRUE", "FALSE", "SIM", "NÃO", "NAO")
  parseable <- (!is.na(number) &
    !is_missing &
    !ambiguous_separator &
    (grouped_thousands | grouped_decimal | scientific_number | simple_number)) |
    logical_response

  normalized_number <- number
  normalized_number[grouped_thousands] <- gsub(
    "[.,]",
    "",
    normalized_number[grouped_thousands]
  )
  normalized_number[grouped_decimal] <- gsub(
    "\\.",
    "",
    normalized_number[grouped_decimal]
  )
  normalized_number[grepl(",", normalized_number) & parseable] <- sub(
    ",",
    ".",
    normalized_number[grepl(",", normalized_number) & parseable],
    fixed = TRUE
  )

  parsed_value <- rep(NA_real_, length(number))
  numeric_values <- parseable & !logical_response
  parsed_value[numeric_values] <- as.numeric(normalized_number[numeric_values])
  parsed_value[logical_response] <- as.numeric(
    toupper(text[logical_response]) %in% c("TRUE", "SIM")
  )
  parse_status <- rep("review", length(number))
  parse_status[is_missing] <- "missing"
  parse_status[parseable] <- "parsed"

  result <- data.frame(
    raw_response = raw_response,
    parsed_value = parsed_value,
    parsed_unit = parsed_unit,
    parse_status = parse_status,
    missing_reason = missing_reason,
    stringsAsFactors = FALSE
  )

  return(result)
}

# Review targets -----------------------------------------------------------

pemob_expected_units <- c(
  "3.1.1.A" = "BRL",
  "1.6.1.G" = "km",
  "1.6.1.H" = "km"
)
pemob_target_variables <- names(pemob_expected_units)

build_pemob_candidate_id <- function(code_muni, code_variable, year) {
  result <- paste(
    sprintf("%.0f", as.numeric(code_muni)),
    code_variable,
    year,
    sep = "::"
  )
  return(result)
}

# Collapse logical flag columns into "flag_a;flag_b" strings, one per row.
collapse_pemob_flags <- function(dat, flag_cols) {
  result <- purrr::pmap_chr(dat[flag_cols], function(...) {
    flags <- c(...)
    return(paste(names(flags)[flags], collapse = ";"))
  })
  return(result)
}

# Flag values above Q3 + 3 * IQR among eligible observations. Groups with
# fewer than 8 eligible values or no spread are never flagged.
flag_pemob_outliers <- function(value, eligible) {
  result <- rep(FALSE, length(value))
  observed <- value[eligible]
  spread <- stats::IQR(observed)
  if (length(observed) < 8L || spread == 0) {
    return(result)
  }

  fence <- stats::quantile(observed, 0.75, names = FALSE) + 3 * spread
  result[eligible] <- observed > fence
  return(result)
}

parse_pemob_target_responses <- function(dat, required_cols, label) {
  if (!all(required_cols %in% names(dat))) {
    cli::cli_abort("{label} inputs must include {.field {required_cols}}.")
  }

  dat <- dplyr::filter(dat, code_variable %in% pemob_target_variables)
  if (anyDuplicated(dat[c("code_muni", "code_variable", "year")])) {
    cli::cli_abort(
      "{label} inputs must have unique municipality-question-year keys."
    )
  }

  parsed <- parse_pemob_response(dat$raw_response)
  result <- dplyr::bind_cols(
    tibble::as_tibble(dat),
    dplyr::select(parsed, -"raw_response")
  )
  result$expected_unit <- unname(pemob_expected_units[result$code_variable])
  return(result)
}


# Review candidates --------------------------------------------------------

build_pemob_review_candidates <- function(dat) {
  required_cols <- c(
    "code_muni",
    "name_muni",
    "abbrev_state",
    "year",
    "code_variable",
    "raw_response"
  )
  flag_cols <- c(
    "unparsed_response",
    "negative_value",
    "unit_mismatch",
    "cross_city_outlier",
    "zero_transition",
    "abrupt_change_10x"
  )
  helper_cols <- c(
    "expected_unit",
    "outlier_eligible",
    "previous_year",
    "previous_value",
    "consecutive"
  )

  responses <- parse_pemob_target_responses(dat, required_cols, "Review")

  value_flags <- responses |>
    dplyr::mutate(
      unparsed_response = parse_status == "review",
      negative_value = !is.na(parsed_value) & parsed_value < 0,
      unit_mismatch = !is.na(parsed_unit) & parsed_unit != expected_unit,
      outlier_eligible = !is.na(parsed_value) &
        parsed_value > 0 &
        (is.na(parsed_unit) | parsed_unit == expected_unit)
    ) |>
    dplyr::mutate(
      cross_city_outlier = flag_pemob_outliers(parsed_value, outlier_eligible),
      .by = c(code_variable, year)
    )

  # shortcut: flag 10-fold changes for review; confirm them against records.
  series_flags <- value_flags |>
    dplyr::arrange(code_muni, code_variable, year) |>
    dplyr::mutate(
      previous_year = dplyr::lag(year),
      previous_value = dplyr::lag(parsed_value),
      .by = c(code_muni, code_variable)
    ) |>
    dplyr::mutate(
      consecutive = !is.na(previous_year) &
        year - previous_year == 1 &
        !is.na(parsed_value) &
        !is.na(previous_value),
      zero_transition = consecutive &
        xor(parsed_value == 0, previous_value == 0),
      abrupt_change_10x = consecutive &
        parsed_value > 0 &
        previous_value > 0 &
        pmax(parsed_value, previous_value) /
          pmin(parsed_value, previous_value) >=
          10
    )

  result <- series_flags |>
    dplyr::mutate(
      flag_reasons = collapse_pemob_flags(series_flags, flag_cols)
    ) |>
    dplyr::filter(nzchar(flag_reasons)) |>
    dplyr::mutate(treated_value = parsed_value, review_decision = "pending") |>
    dplyr::select(-dplyr::all_of(c(flag_cols, helper_cols)))

  return(result)
}


# Interpolation candidates -------------------------------------------------

build_pemob_interpolation_candidates <- function(dat) {
  required_cols <- c(
    "code_muni",
    "name_muni",
    "abbrev_state",
    "year",
    "code_variable",
    "raw_response",
    "participated",
    "review_decision",
    "review_evidence"
  )
  reason_cols <- c(
    "missing_reason_not_item_nonresponse",
    "participation_unknown",
    "nonparticipation",
    "endpoint_not_numeric",
    "endpoint_negative",
    "endpoint_unit_mismatch",
    "endpoint_not_accepted",
    "endpoint_evidence_missing",
    "invalid_reference_time"
  )
  endpoint_cols <- c(
    "year",
    "reference_time",
    "parse_status",
    "parsed_value",
    "parsed_unit",
    "review_decision",
    "review_evidence"
  )
  output_cols <- c(
    "code_muni",
    "name_muni",
    "abbrev_state",
    "year",
    "code_variable",
    "candidate_id",
    "raw_response",
    "missing_reason",
    "participated",
    "endpoint_left_id",
    "endpoint_left_year",
    "endpoint_left_value",
    "endpoint_left_review",
    "endpoint_left_evidence",
    "endpoint_right_id",
    "endpoint_right_year",
    "endpoint_right_value",
    "endpoint_right_review",
    "endpoint_right_evidence",
    "estimate_value",
    "method",
    "eligible",
    "eligibility_reason"
  )

  if (!"reference_time" %in% names(dat)) {
    dat$reference_time <- as.numeric(dat$year)
  }
  responses <- parse_pemob_target_responses(dat, required_cols, "Interpolation")
  if (!is.logical(responses$participated)) {
    cli::cli_abort(
      "{.field participated} must be recorded as TRUE, FALSE, or NA."
    )
  }
  if (!is.numeric(responses$year) || !is.numeric(responses$reference_time)) {
    cli::cli_abort("{.field year} and {.field reference_time} must be numeric.")
  }

  endpoints <- responses |>
    dplyr::select(code_muni, code_variable, dplyr::all_of(endpoint_cols))
  left_endpoints <- dplyr::rename_with(
    endpoints,
    \(col) paste0("left_", col),
    dplyr::all_of(endpoint_cols)
  )
  right_endpoints <- dplyr::rename_with(
    endpoints,
    \(col) paste0("right_", col),
    dplyr::all_of(endpoint_cols)
  )

  # A gap is a missing response whose previous and next years both exist.
  gaps <- responses |>
    dplyr::filter(parse_status == "missing") |>
    dplyr::mutate(left_year = year - 1, right_year = year + 1) |>
    dplyr::inner_join(
      left_endpoints,
      by = c("code_muni", "code_variable", "left_year"),
      na_matches = "never"
    ) |>
    dplyr::inner_join(
      right_endpoints,
      by = c("code_muni", "code_variable", "right_year"),
      na_matches = "never"
    )

  has_text <- function(x) !is.na(x) & nzchar(trimws(x))

  # Endpoints without a unit are assumed to use the expected unit.
  reasons <- gaps |>
    dplyr::mutate(
      left_unit = dplyr::coalesce(left_parsed_unit, expected_unit),
      right_unit = dplyr::coalesce(right_parsed_unit, expected_unit),
      missing_reason_not_item_nonresponse = !missing_reason %in% "NR",
      participation_unknown = is.na(participated),
      nonparticipation = participated %in% FALSE,
      endpoint_not_numeric = left_parse_status != "parsed" |
        right_parse_status != "parsed",
      endpoint_negative = dplyr::coalesce(left_parsed_value < 0, FALSE) |
        dplyr::coalesce(right_parsed_value < 0, FALSE),
      endpoint_unit_mismatch = left_unit != expected_unit |
        right_unit != expected_unit,
      endpoint_not_accepted = !left_review_decision %in% "accepted" |
        !right_review_decision %in% "accepted",
      endpoint_evidence_missing = !has_text(left_review_evidence) |
        !has_text(right_review_evidence),
      invalid_reference_time = !(is.finite(left_reference_time) &
        is.finite(reference_time) &
        is.finite(right_reference_time)) |
        left_reference_time >= reference_time |
        reference_time >= right_reference_time
    )

  result <- reasons |>
    dplyr::mutate(
      reason_list = collapse_pemob_flags(reasons, reason_cols),
      eligible = !nzchar(reason_list),
      estimate_value = dplyr::if_else(
        eligible,
        left_parsed_value +
          (right_parsed_value - left_parsed_value) *
            (reference_time - left_reference_time) /
            (right_reference_time - left_reference_time),
        NA_real_
      ),
      eligibility_reason = dplyr::if_else(
        eligible,
        "both adjacent endpoints reviewed; item nonresponse and participation confirmed",
        reason_list
      ),
      candidate_id = build_pemob_candidate_id(code_muni, code_variable, year),
      endpoint_left_id = build_pemob_candidate_id(
        code_muni,
        code_variable,
        left_year
      ),
      endpoint_right_id = build_pemob_candidate_id(
        code_muni,
        code_variable,
        right_year
      ),
      method = "linear_interpolation"
    ) |>
    dplyr::rename(
      endpoint_left_year = left_year,
      endpoint_left_value = left_parsed_value,
      endpoint_left_review = left_review_decision,
      endpoint_left_evidence = left_review_evidence,
      endpoint_right_year = right_year,
      endpoint_right_value = right_parsed_value,
      endpoint_right_review = right_review_decision,
      endpoint_right_evidence = right_review_evidence
    ) |>
    dplyr::arrange(code_muni, code_variable, year) |>
    dplyr::select(dplyr::all_of(output_cols))

  return(result)
}


# Scaling -------------------------------------------------------------------

scale_pemob_share <- function(value, total) {
  value_scaled <- rep(NA_real_, length(value))
  valid <- !is.na(value) & !is.na(total) & total != 0
  value_scaled[valid] <- value[valid] / total[valid] * 100

  return(value_scaled)
}

scale_pemob_max <- function(value) {
  value_scaled <- rep(NA_real_, length(value))
  observed <- !is.na(value)

  if (!any(observed)) {
    return(value_scaled)
  }

  maximum <- max(value[observed])
  if (maximum == 0) {
    value_scaled[observed] <- 0
  } else {
    value_scaled[observed] <- value[observed] / maximum * 100
  }

  return(value_scaled)
}
