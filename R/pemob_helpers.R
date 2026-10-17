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
  # shortcut: readxl merges blank and Excel-error cells as NA; inspect XML if errors appear.
  result[] <- lapply(result, function(column) {
    column[is.na(column)] <- ""
    return(column)
  })

  return(result)
}

format_pemob_excel_dates <- function(response) {
  date_number <- suppressWarnings(as.numeric(response))
  is_excel_date <- !is.na(date_number)
  result <- as.character(response)
  result[is_excel_date] <- as.character(
    janitor::excel_numeric_to_date(date_number[is_excel_date])
  )

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
