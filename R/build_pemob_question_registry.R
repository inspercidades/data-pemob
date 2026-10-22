# Regenerate the local Phase 5 question registry and evidence files.

source(here::here("R", "pemob_dataverse.R"))

build_pemob_registry_artifacts <- function(
  output_dir = here::here("data", "registry")
) {
  codebook <- build_pemob_codebook()
  seed <- readr::read_delim(
    here::here("data", "portal", "v1", "dict_portal_v1.csv"),
    delim = ";",
    col_types = readr::cols(.default = readr::col_character()),
    show_col_types = FALSE
  )
  legacy <- readr::read_csv(
    here::here("data", "dict_portal_pemob.csv"),
    col_types = readr::cols(.default = readr::col_character()),
    show_col_types = FALSE
  )
  review <- readr::read_csv(
    here::here("tabelas", "pemob_question_registry_review.csv"),
    col_types = readr::cols(.default = readr::col_character()),
    show_col_types = FALSE
  )
  live <- readr::read_csv(
    here::here("tabelas", "pemob_live_labels_2024.csv"),
    col_types = readr::cols(.default = readr::col_character()),
    show_col_types = FALSE
  )
  dim <- readr::read_csv(
    here::here("data", "portal", "v1", "dim_category.csv"),
    col_types = readr::cols(.default = readr::col_character()),
    show_col_types = FALSE
  )
  live_categories <- readr::read_csv(
    here::here("tabelas", "pemob_live_categories_2024.csv"),
    col_types = readr::cols(.default = readr::col_character()),
    show_col_types = FALSE
  )

  registry <- build_pemob_question_registry(codebook, seed, review, legacy)
  pairs <- registry |>
    dplyr::count(level)
  if (
    nrow(registry) != 815L ||
      pairs$n[pairs$level == "municipal"] != 473L ||
      pairs$n[pairs$level == "metropolitan"] != 342L
  ) {
    cli::cli_abort(
      "Current codebook does not have the reviewed 473/342 registry pairs."
    )
  }

  source_only <- list()
  for (level in c("municipal", "metropolitan")) {
    years <- if (level == "municipal") {
      c(2019, 2021:2024)
    } else {
      c(2019, 2021:2024)
    }
    for (year in years) {
      filename <- paste0(
        "dicionario_variaveis_pemob_",
        if (level == "metropolitan") "metro_" else "",
        year,
        ".csv"
      )
      dictionary <- readr::read_csv(
        here::here("data", filename),
        col_types = readr::cols(.default = readr::col_character()),
        show_col_types = FALSE
      )
      entries <- tibble::tibble(
        level = level,
        year = year,
        source_code = dictionary$code_variable,
        question_text = dictionary$name_variable
      )
      source_only[[length(source_only) + 1L]] <- entries
    }
  }
  source_only <- find_pemob_dictionary_evidence(
    codebook,
    dplyr::bind_rows(source_only)
  )
  evidence <- build_pemob_question_evidence(
    codebook,
    seed,
    source_only,
    legacy,
    live
  )
  evidence$question_text <- ifelse(
    is.na(evidence$question_text),
    NA_character_,
    encodeString(evidence$question_text, quote = "")
  )
  candidates <- build_pemob_concept_candidates(codebook, registry)
  category_evidence <- build_pemob_category_evidence(
    seed,
    dim,
    live_categories
  )

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
  participation <- build_pemob_participation_export(municipal, metro)
  long <- dplyr::bind_rows(
    build_pemob_long(municipal, "municipal", treated, registry = NULL),
    build_pemob_long(metro, "metropolitan", registry = NULL)
  ) |>
    dplyr::select(
      level,
      place_key,
      year,
      code_variable,
      value_raw,
      parse_status
    )
  eligibility <- score_pemob_question_eligibility(
    registry,
    list(long = long, participation = participation)
  )

  dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
  readr::write_csv(
    registry,
    file.path(output_dir, "pemob_questions.csv"),
    na = ""
  )
  readr::write_csv(
    evidence,
    file.path(output_dir, "pemob_question_evidence.csv"),
    na = ""
  )
  readr::write_csv(
    candidates,
    file.path(output_dir, "pemob_concept_candidates.csv"),
    na = ""
  )
  readr::write_csv(
    category_evidence,
    file.path(output_dir, "pemob_category_evidence.csv"),
    na = ""
  )
  readr::write_csv(
    eligibility,
    file.path(output_dir, "pemob_question_eligibility.csv"),
    na = ""
  )
  return(invisible(list(
    registry = registry,
    evidence = evidence,
    candidates = candidates,
    category_evidence = category_evidence,
    eligibility = eligibility
  )))
}

if (sys.nframe() == 0L) {
  build_pemob_registry_artifacts()
}
