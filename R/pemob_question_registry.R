# Question registry -------------------------------------------------------

.pemob_blank <- function(x) {
  x <- as.character(x)
  x[is.na(x) | trimws(x) %in% c("", "NA", "missing")] <- NA_character_
  return(x)
}

.pemob_check_keys <- function(dat, keys, name) {
  if (!all(keys %in% names(dat))) {
    cli::cli_abort("{name} lacks required key columns: {keys}.")
  }
  if (anyNA(dat[keys]) || anyDuplicated(dat[keys])) {
    cli::cli_abort("{name} has missing or duplicate keys.")
  }
  return(invisible(TRUE))
}

build_pemob_question_registry <- function(
  codebook,
  seed,
  review = NULL,
  legacy = NULL
) {
  .pemob_check_keys(seed, "code_variable", "Seed dictionary")
  if (
    !all(
      c("level", "year", "code_variable", "question_text") %in% names(codebook)
    )
  ) {
    cli::cli_abort("The codebook lacks registry source columns.")
  }
  keys <- codebook |>
    dplyr::distinct(level, code_variable) |>
    dplyr::arrange(level, code_variable)
  .pemob_check_keys(keys, c("level", "code_variable"), "Codebook pairs")
  editions <- codebook |>
    dplyr::distinct(level, code_variable, year) |>
    dplyr::arrange(year) |>
    dplyr::summarise(
      valid_editions = paste(year, collapse = ";"),
      .by = c(level, code_variable)
    )
  latest <- codebook |>
    dplyr::filter(!is.na(question_text), nzchar(question_text)) |>
    dplyr::arrange(dplyr::desc(year)) |>
    dplyr::distinct(level, code_variable, .keep_all = TRUE) |>
    dplyr::select(level, code_variable, source_question = question_text)

  seed_cols <- intersect(
    c(
      "code_variable",
      "label",
      "label_pergunta",
      "categoria",
      "subcategoria",
      "modal",
      "is_dashboard",
      "is_tabela"
    ),
    names(seed)
  )
  seed <- seed[seed_cols]
  seed <- dplyr::rename(
    seed,
    category = dplyr::any_of("categoria"),
    subcategory = dplyr::any_of("subcategoria"),
    mode = dplyr::any_of("modal"),
    seed_dashboard = dplyr::any_of("is_dashboard"),
    seed_table = dplyr::any_of("is_tabela")
  )
  seed$level <- "municipal"
  for (col in setdiff(names(seed), c("level", "code_variable"))) {
    seed[[col]] <- .pemob_blank(seed[[col]])
  }
  registry <- keys |>
    dplyr::left_join(editions, by = c("level", "code_variable")) |>
    dplyr::left_join(latest, by = c("level", "code_variable")) |>
    dplyr::left_join(seed, by = c("level", "code_variable"))
  for (col in c(
    "label",
    "category",
    "subcategory",
    "mode",
    "seed_dashboard",
    "seed_table"
  )) {
    if (!col %in% names(registry)) registry[[col]] <- NA_character_
  }
  registry$unit <- NA_character_
  registry$value_type <- NA_character_
  registry$reviewed_type_editions <- NA_character_
  registry$concept_id <- NA_character_
  registry$valid_values <- NA_character_
  registry$valid_pattern <- NA_character_
  registry$validity_editions <- NA_character_
  registry$review_evidence <- NA_character_
  registry$reviewer <- NA_character_
  registry$screen_value_type <- NA_character_
  registry$type_review_status <- NA_character_
  registry$type_basis <- NA_character_
  registry$screen_valid_editions <- NA_character_

  if (!is.null(legacy)) {
    .pemob_check_keys(legacy, "code_variable", "Legacy dictionary")
    if (!all(c("name_variable", "tipo") %in% names(legacy))) {
      cli::cli_abort("Legacy dictionary lacks question text or type.")
    }
    v1_text <- if ("label_pergunta" %in% names(seed)) {
      seed$label_pergunta
    } else {
      rep(NA_character_, nrow(seed))
    }
    for (i in seq_len(nrow(registry))) {
      if (registry$level[[i]] != "municipal") {
        next
      }
      code <- registry$code_variable[[i]]
      legacy_row <- match(code, legacy$code_variable)
      seed_row <- match(code, seed$code_variable)
      if (
        is.na(legacy_row) ||
          is.na(seed_row) ||
          is.na(legacy$tipo[[legacy_row]]) ||
          legacy$tipo[[legacy_row]] != "numeric"
      ) {
        next
      }
      reference <- .pemob_blank(c(
        legacy$name_variable[[legacy_row]],
        v1_text[[seed_row]]
      ))
      if (anyNA(reference) || reference[[1]] != reference[[2]]) {
        next
      }
      source <- codebook[
        codebook$level == "municipal" &
          codebook$code_variable == code &
          !is.na(codebook$question_text),
      ]
      matching <- sort(unique(source$year[
        trimws(source$question_text) == trimws(reference[[1]])
      ]))
      if (length(matching) == 0L) {
        next
      }
      registry$screen_value_type[[i]] <- "numeric"
      registry$type_review_status[[i]] <- "provisional"
      registry$type_basis[[i]] <- paste0(
        "Exact source question text in editions ",
        paste(matching, collapse = ";"),
        " matches v1 label_pergunta and legacy name_variable; legacy tipo=numeric"
      )
      registry$screen_valid_editions[[i]] <- paste(matching, collapse = ";")
    }
  }

  if (!is.null(review) && nrow(review) > 0L) {
    .pemob_check_keys(review, c("level", "code_variable"), "Registry review")
    unknown <- dplyr::anti_join(review, keys, by = c("level", "code_variable"))
    if (nrow(unknown) > 0L) {
      cli::cli_abort("Registry review contains unknown keys.")
    }
    for (i in seq_len(nrow(review))) {
      row <- match(
        paste(review$level[[i]], review$code_variable[[i]]),
        paste(registry$level, registry$code_variable)
      )
      updates <- intersect(
        c(
          "label",
          "category",
          "subcategory",
          "mode",
          "unit",
          "value_type",
          "reviewed_type_editions",
          "concept_id",
          "valid_values",
          "valid_pattern",
          "validity_editions"
        ),
        names(review)
      )
      changed <- updates[
        !is.na(.pemob_blank(unlist(review[i, updates], use.names = FALSE)))
      ]
      if (length(changed) == 0L) {
        next
      }
      if (
        !all(c("evidence", "reviewer") %in% names(review)) ||
          anyNA(.pemob_blank(c(review$evidence[[i]], review$reviewer[[i]])))
      ) {
        cli::cli_abort("Registry review changes require evidence and reviewer.")
      }
      if (
        any(changed %in% c("valid_values", "valid_pattern")) &&
          (!"validity_editions" %in% names(review) ||
            is.na(.pemob_blank(review$validity_editions[[i]])))
      ) {
        cli::cli_abort(
          "Reviewed response formats need explicit validity_editions."
        )
      }
      if (
        any(changed %in% c("unit", "value_type")) &&
          (!"reviewed_type_editions" %in% names(review) ||
            is.na(.pemob_blank(review$reviewed_type_editions[[i]])))
      ) {
        cli::cli_abort(
          "Reviewed unit and type need explicit reviewed_type_editions."
        )
      }
      for (col in changed) {
        registry[[col]][[row]] <- as.character(review[[col]][[i]])
      }
      registry$review_evidence[[row]] <- as.character(review$evidence[[i]])
      registry$reviewer[[row]] <- as.character(review$reviewer[[i]])
    }
  }
  labels <- registry[!is.na(registry$label), c("level", "label")]
  if (anyDuplicated(labels)) {
    cli::cli_abort("Registry labels must be unique within each level.")
  }
  return(registry)
}

build_pemob_question_evidence <- function(
  codebook,
  seed,
  source_only = NULL,
  legacy = NULL,
  live = NULL
) {
  required <- c(
    "level",
    "year",
    "code_variable",
    "source_code",
    "question_text"
  )
  if (!all(required %in% names(codebook))) {
    cli::cli_abort("The codebook lacks evidence columns.")
  }
  result <- codebook[required]
  if (!is.null(source_only)) {
    for (col in setdiff(required, names(source_only))) {
      source_only[[col]] <- NA
    }
    result <- dplyr::bind_rows(result, source_only[required])
  }
  seed_cols <- intersect(
    c(
      "code_variable",
      "label",
      "label_pergunta",
      "categoria",
      "subcategoria",
      "modal",
      "is_dashboard",
      "is_tabela"
    ),
    names(seed)
  )
  seed_evidence <- seed[seed_cols]
  names(seed_evidence)[names(seed_evidence) != "code_variable"] <- paste0(
    "seed_",
    names(seed_evidence)[names(seed_evidence) != "code_variable"]
  )
  seed_evidence$level <- "municipal"
  result <- dplyr::left_join(
    result,
    seed_evidence,
    by = c("level", "code_variable")
  )
  if (!is.null(legacy)) {
    .pemob_check_keys(legacy, "code_variable", "Legacy dictionary")
    keep <- intersect(
      c(
        "code_variable",
        "label",
        "name_variable",
        "categoria",
        "subcategoria",
        "modal",
        "tipo"
      ),
      names(legacy)
    )
    legacy <- legacy[keep]
    names(legacy)[names(legacy) != "code_variable"] <- paste0(
      "legacy_",
      names(legacy)[names(legacy) != "code_variable"]
    )
    legacy$level <- "municipal"
    result <- dplyr::left_join(result, legacy, by = c("level", "code_variable"))
  }
  result$evidence_kind <- ifelse(
    is.na(result$code_variable),
    "source_only",
    "edition_source"
  )
  if (!is.null(live)) {
    live_keys <- c(
      "label",
      "label_pergunta",
      "is_dashboard",
      "source_commit",
      "source_path"
    )
    if (!all(live_keys %in% names(live))) {
      cli::cli_abort("Live label snapshot lacks provenance fields.")
    }
    matchable <- codebook |>
      dplyr::filter(
        level == "municipal",
        year == 2024,
        !is.na(question_text)
      ) |>
      dplyr::add_count(question_text, name = "text_count") |>
      dplyr::filter(text_count == 1L) |>
      dplyr::select(question_text, code_variable, source_code)
    live_rows <- tibble::tibble(
      level = "municipal",
      year = 2024,
      question_text = live$label_pergunta,
      live_label = live$label,
      live_is_dashboard = live$is_dashboard,
      live_source_commit = live$source_commit,
      live_source_path = live$source_path,
      evidence_kind = "live_site"
    ) |>
      dplyr::left_join(matchable, by = "question_text")
    live_rows$live_mapping_status <- ifelse(
      is.na(live_rows$code_variable),
      "unresolved",
      "unique_exact_text"
    )
    result <- dplyr::bind_rows(result, live_rows)
  }
  return(dplyr::arrange(result, level, year, code_variable, source_code))
}

build_pemob_category_evidence <- function(seed, dim, live) {
  seed_cols <- c("categoria", "subcategoria", "label")
  live_cols <- c(
    "category",
    "subcategory",
    "label",
    "source_commit",
    "source_path"
  )
  if (!all(seed_cols %in% names(seed)) || !all(seed_cols %in% names(dim))) {
    cli::cli_abort(
      "Seed and category dimension need category, subcategory, and label."
    )
  }
  if (!all(live_cols %in% names(live))) {
    cli::cli_abort(
      "Live category snapshot lacks category or provenance columns."
    )
  }
  seed_rows <- seed |>
    dplyr::rename(category = categoria, subcategory = subcategoria) |>
    dplyr::select(category, subcategory, label) |>
    dplyr::distinct() |>
    dplyr::mutate(in_seed = TRUE)
  dim_rows <- dim |>
    dplyr::rename(category = categoria, subcategory = subcategoria) |>
    dplyr::select(category, subcategory, label) |>
    dplyr::distinct() |>
    dplyr::mutate(in_dim = TRUE)
  live_rows <- live |>
    dplyr::select(dplyr::all_of(live_cols)) |>
    dplyr::distinct() |>
    dplyr::mutate(in_live = TRUE)
  keys <- c("category", "subcategory", "label")
  result <- dplyr::full_join(seed_rows, dim_rows, by = keys) |>
    dplyr::full_join(live_rows, by = keys) |>
    dplyr::mutate(
      in_seed = dplyr::coalesce(in_seed, FALSE),
      in_dim = dplyr::coalesce(in_dim, FALSE),
      in_live = dplyr::coalesce(in_live, FALSE),
      comparison_status = ifelse(
        in_seed & in_dim & in_live,
        "aligned",
        "discrepancy"
      ),
      seed_source = ifelse(
        in_seed,
        "data/portal/v1/dict_portal_v1.csv",
        NA_character_
      ),
      dim_source = ifelse(
        in_dim,
        "data/portal/v1/dim_category.csv",
        NA_character_
      )
    ) |>
    dplyr::arrange(category, subcategory, label)
  return(result)
}

build_pemob_concept_candidates <- function(codebook, registry) {
  latest <- codebook |>
    dplyr::filter(!is.na(question_text), nzchar(question_text)) |>
    dplyr::arrange(dplyr::desc(year)) |>
    dplyr::distinct(level, code_variable, .keep_all = TRUE) |>
    dplyr::select(level, code_variable, question_text)
  normalized <- tolower(iconv(latest$question_text, to = "ASCII//TRANSLIT"))
  normalized <- gsub("municipio|regiao metropolitana", "place", normalized)
  normalized <- gsub("[^a-z0-9]+", " ", normalized)
  latest$match_text <- trimws(gsub(" +", " ", normalized))
  municipal <- latest[
    latest$level == "municipal",
    c("code_variable", "question_text", "match_text")
  ]
  metropolitan <- latest[
    latest$level == "metropolitan",
    c("code_variable", "question_text", "match_text")
  ]
  names(municipal)[1:2] <- c("municipal_code", "municipal_question")
  names(metropolitan)[1:2] <- c("metropolitan_code", "metropolitan_question")
  candidates <- dplyr::inner_join(metropolitan, municipal, by = "match_text")
  candidates <- candidates |>
    dplyr::select(
      metropolitan_code,
      municipal_code,
      metropolitan_question,
      municipal_question,
      match_text
    ) |>
    dplyr::distinct()
  metro_review <- registry[
    registry$level == "metropolitan",
    c("code_variable", "concept_id")
  ]
  municipal_review <- registry[
    registry$level == "municipal",
    c("code_variable", "concept_id")
  ]
  metro_id <- metro_review$concept_id[match(
    candidates$metropolitan_code,
    metro_review$code_variable
  )]
  municipal_id <- municipal_review$concept_id[match(
    candidates$municipal_code,
    municipal_review$code_variable
  )]
  candidates$status <- ifelse(
    !is.na(metro_id) & !is.na(municipal_id) & metro_id == municipal_id,
    "reviewed_link",
    "pending"
  )
  candidates$reason <- ifelse(
    candidates$status == "reviewed_link",
    "matching_reviewed_concept_id",
    "text_match_requires_scope_review"
  )
  return(dplyr::arrange(candidates, metropolitan_code, municipal_code))
}

read_pemob_question_registry <- function(
  path = here::here("data", "registry", "pemob_questions.csv")
) {
  if (!file.exists(path)) {
    cli::cli_abort("Registry file does not exist: {.path {path}}.")
  }
  registry <- readr::read_csv(
    path,
    col_types = readr::cols(.default = readr::col_character()),
    show_col_types = FALSE
  )
  .pemob_check_keys(registry, c("level", "code_variable"), "Question registry")
  if (!all(c("unit", "value_type") %in% names(registry))) {
    cli::cli_abort("Question registry lacks unit or value_type.")
  }
  return(registry)
}


# Product eligibility -----------------------------------------------------

.pemob_valid_years <- function(x) {
  if (is.na(x) || !nzchar(x)) {
    return(integer())
  }
  return(as.integer(strsplit(x, ";", fixed = TRUE)[[1]]))
}

.pemob_type_valid <- function(dat, value_type, valid_values, valid_pattern) {
  if (value_type == "numeric") {
    return(dat$parse_status == "parsed")
  }
  if (!value_type %in% c("categorical", "text", "binary")) {
    return(rep(NA, nrow(dat)))
  }
  if (!is.na(valid_values) && nzchar(valid_values)) {
    options <- trimws(strsplit(valid_values, ";", fixed = TRUE)[[1]])
    return(trimws(dat$value_raw) %in% options)
  }
  if (!is.na(valid_pattern) && nzchar(valid_pattern)) {
    return(grepl(valid_pattern, dat$value_raw, perl = TRUE))
  }
  return(rep(NA, nrow(dat)))
}

score_pemob_question_eligibility <- function(
  registry,
  long_or_quality,
  response_options = NULL
) {
  .pemob_check_keys(registry, c("level", "code_variable"), "Question registry")
  if (!is.null(response_options)) {
    option_cols <- c(
      "level",
      "code_variable",
      "year",
      "value_raw",
      "source_ref",
      "reviewer"
    )
    if (
      !all(option_cols %in% names(response_options)) ||
        anyNA(response_options[option_cols])
    ) {
      cli::cli_abort(
        "Response options need complete keys, source_ref, and reviewer."
      )
    }
    .pemob_check_keys(response_options, option_cols[1:4], "Response options")
  }
  quality <- if (is.list(long_or_quality) && !is.data.frame(long_or_quality)) {
    if (!all(c("long", "participation") %in% names(long_or_quality))) {
      cli::cli_abort("Quality input needs long and participation tables.")
    }
    long <- long_or_quality$long
    participation <- long_or_quality$participation
    required <- c("level", "place_key", "year", "participated")
    if (!all(required %in% names(participation))) {
      cli::cli_abort(
        "Participation input lacks place, year, or participation fields."
      )
    }
    if (anyDuplicated(participation[c("level", "place_key", "year")])) {
      cli::cli_abort("Participation input has duplicate place-year keys.")
    }
    questions <- registry |>
      dplyr::select(level, code_variable, valid_editions) |>
      tidyr::separate_longer_delim(valid_editions, delim = ";") |>
      dplyr::mutate(year = as.integer(valid_editions)) |>
      dplyr::select(level, code_variable, year)
    grid <- dplyr::inner_join(
      participation,
      questions,
      by = c("level", "year"),
      relationship = "many-to-many"
    )
    join_keys <- c("level", "place_key", "year", "code_variable")
    if (anyDuplicated(long[join_keys])) {
      cli::cli_abort("Long quality input has duplicate response keys.")
    }
    dplyr::left_join(
      grid,
      long[c(join_keys, "value_raw", "parse_status")],
      by = join_keys
    )
  } else {
    long_or_quality
  }
  required <- c(
    "level",
    "code_variable",
    "year",
    "place_key",
    "participated",
    "value_raw",
    "parse_status"
  )
  if (!all(required %in% names(quality))) {
    cli::cli_abort("Quality input lacks required fields.")
  }
  if (
    anyDuplicated(quality[c("level", "code_variable", "year", "place_key")])
  ) {
    cli::cli_abort("Quality input has duplicate response keys.")
  }
  if (!is.logical(quality$participated) || anyNA(quality$participated)) {
    cli::cli_abort("Quality participation flag must be complete and logical.")
  }
  quality$year <- as.integer(quality$year)
  output <- vector("list", nrow(registry) * 2L)
  index <- 0L
  for (i in seq_len(nrow(registry))) {
    item <- registry[i, ]
    years <- .pemob_valid_years(item$valid_editions)
    reviewed_type <- !is.na(item$value_type)
    screen_type <- if ("screen_value_type" %in% names(item)) {
      item$screen_value_type
    } else {
      NA_character_
    }
    value_type <- if (reviewed_type) item$value_type else screen_type
    type_years <- if (reviewed_type) {
      if ("reviewed_type_editions" %in% names(item)) {
        intersect(years, .pemob_valid_years(item$reviewed_type_editions))
      } else {
        integer()
      }
    } else if ("screen_valid_editions" %in% names(item)) {
      .pemob_valid_years(item$screen_valid_editions)
    } else {
      integer()
    }
    dat <- quality[
      quality$level == item$level &
        quality$code_variable == item$code_variable &
        quality$year %in% years &
        quality$participated,
    ]
    dat$covered <- !is.na(dat$value_raw) &
      nzchar(trimws(dat$value_raw)) &
      !is.na(dat$parse_status) &
      dat$parse_status != "missing"
    dat$type_valid <- NA
    covered <- which(dat$covered)
    if (length(covered) > 0L && !is.na(value_type)) {
      valid_values <- if ("valid_values" %in% names(item)) {
        item$valid_values
      } else {
        NA_character_
      }
      valid_pattern <- if ("valid_pattern" %in% names(item)) {
        item$valid_pattern
      } else {
        NA_character_
      }
      dat$type_valid[covered] <- .pemob_type_valid(
        dat[covered, ],
        value_type,
        valid_values,
        valid_pattern
      )
      validity_editions <- if ("validity_editions" %in% names(item)) {
        .pemob_valid_years(item$validity_editions)
      } else {
        integer()
      }
      if (value_type %in% c("categorical", "text", "binary")) {
        dat$type_valid[covered[!dat$year[covered] %in% validity_editions]] <- NA
      }
      if (
        !is.null(response_options) &&
          value_type %in% c("categorical", "text", "binary")
      ) {
        options <- response_options[
          response_options$level == item$level &
            response_options$code_variable == item$code_variable,
        ]
        documented <- dat$year[covered] %in% options$year
        if (any(documented)) {
          response_key <- paste(
            dat$year[covered[documented]],
            trimws(dat$value_raw[covered[documented]])
          )
          option_key <- paste(options$year, trimws(options$value_raw))
          dat$type_valid[covered[documented]] <- response_key %in% option_key
        }
      }
      dat$type_valid[covered[!dat$year[covered] %in% type_years]] <- NA
    }
    editions <- tibble::tibble(year = years)
    if (nrow(dat) > 0L) {
      counts <- dat |>
        dplyr::summarise(
          participating = dplyr::n(),
          covered = sum(covered),
          .by = year
        )
      editions <- dplyr::left_join(editions, counts, by = "year")
    } else {
      editions$participating <- NA_integer_
      editions$covered <- NA_integer_
    }
    editions$coverage <- editions$covered / editions$participating
    for (product in c("table", "dashboard")) {
      min_editions <- if (product == "table") 4L else 5L
      min_coverage <- if (product == "table") 0.10 else 0.20
      min_validity <- if (product == "table") 0.90 else 0.98
      screened <- editions$year %in% type_years
      qualified <- sum(
        editions$coverage[screened] >= min_coverage,
        na.rm = TRUE
      )
      typed <- covered[dat$year[covered] %in% type_years]
      validity <- if (length(typed) > 0L && !anyNA(dat$type_valid[typed])) {
        mean(dat$type_valid[typed])
      } else {
        NA_real_
      }
      reason <- if (is.na(validity)) {
        "type_validity_undocumented"
      } else if (length(type_years) < min_editions) {
        "insufficient_type_evidence_editions"
      } else if (length(years) < min_editions) {
        "insufficient_valid_editions"
      } else if (anyNA(editions$coverage[screened])) {
        "missing_participation_or_coverage"
      } else if (qualified < min_editions) {
        "insufficient_coverage_editions"
      } else if (validity < min_validity) {
        "insufficient_type_validity"
      } else {
        "meets_thresholds"
      }
      decision <- if (reason == "meets_thresholds") {
        "eligible"
      } else if (
        reason %in%
          c(
            "missing_participation_or_coverage",
            "type_validity_undocumented",
            "insufficient_type_evidence_editions"
          )
      ) {
        "unresolved"
      } else {
        "excluded"
      }
      index <- index + 1L
      output[[index]] <- tibble::tibble(
        level = item$level,
        code_variable = item$code_variable,
        product = product,
        valid_editions = length(years),
        editions_meeting_coverage = qualified,
        required_editions = min_editions,
        required_coverage = min_coverage,
        type_validity = validity,
        required_type_validity = min_validity,
        type_review_status = if (reviewed_type) {
          "reviewed"
        } else if (!is.na(screen_type)) {
          "provisional"
        } else {
          "unresolved"
        },
        type_basis = if (reviewed_type) {
          item$review_evidence
        } else if ("type_basis" %in% names(item)) {
          item$type_basis
        } else {
          NA_character_
        },
        coverage_by_edition = paste(
          paste0(
            editions$year,
            ":",
            ifelse(
              is.na(editions$coverage),
              "NA",
              format(round(editions$coverage, 4), trim = TRUE)
            )
          ),
          collapse = ";"
        ),
        decision = decision,
        reason = reason
      )
    }
  }
  return(dplyr::bind_rows(output))
}
