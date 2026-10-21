source(here::here("R", "pemob_dataverse.R"))

codebook_fixture <- tibble::tibble(
  level = c("municipal", "municipal", "metropolitan", "metropolitan"),
  year = c(2024, 2025, 2024, 2025),
  code_variable = c("1.1", "1.1", "2.2", "2.2"),
  source_code = c("1.0", "1.1", "2.0", "2.2"),
  question_text = c(
    "Número de veículos",
    "Número de veículos",
    "Gestão",
    "Gestão"
  )
)
seed_fixture <- tibble::tibble(
  code_variable = "1.1",
  label = "Veículos",
  categoria = "Frota",
  subcategoria = "Ônibus",
  is_dashboard = "1",
  is_tabela = "1"
)
registry_fixture <- build_pemob_question_registry(
  codebook_fixture,
  seed_fixture
)
stopifnot(
  nrow(registry_fixture) == 2L,
  !anyDuplicated(registry_fixture[c("level", "code_variable")]),
  registry_fixture$label[registry_fixture$level == "municipal"] == "Veículos",
  is.na(registry_fixture$label[registry_fixture$level == "metropolitan"]),
  all(is.na(registry_fixture$concept_id)),
  all(is.na(registry_fixture$value_type)),
  all(is.na(registry_fixture$unit)),
  registry_fixture$valid_editions[registry_fixture$level == "municipal"] ==
    "2024;2025"
)

evidence_fixture <- build_pemob_question_evidence(
  codebook_fixture,
  seed_fixture,
  tibble::tibble(
    level = "municipal",
    year = 2025,
    source_code = "9.9",
    question_text = "Source-only question"
  )
)
stopifnot(
  nrow(evidence_fixture) == 5L,
  any(
    is.na(evidence_fixture$code_variable) &
      evidence_fixture$question_text == "Source-only question"
  ),
  evidence_fixture$source_code[
    evidence_fixture$year == 2024 &
      evidence_fixture$level == "municipal"
  ] ==
    "1.0"
)

review_fixture <- tibble::tibble(
  level = "municipal",
  code_variable = "1.1",
  label = NA_character_,
  category = NA_character_,
  subcategory = NA_character_,
  mode = NA_character_,
  unit = "vehicles",
  value_type = "numeric",
  reviewed_type_editions = "2024;2025",
  concept_id = NA_character_,
  evidence = "2025 source question text and documented unit",
  reviewer = "Phase 5 review"
)
reviewed_fixture <- build_pemob_question_registry(
  codebook_fixture,
  seed_fixture,
  review_fixture
)
stopifnot(
  reviewed_fixture$unit[reviewed_fixture$level == "municipal"] == "vehicles",
  reviewed_fixture$value_type[reviewed_fixture$level == "municipal"] ==
    "numeric"
)

duplicate_seed <- dplyr::bind_rows(
  seed_fixture,
  dplyr::mutate(seed_fixture, code_variable = "3.3")
)
duplicate_book <- dplyr::bind_rows(
  codebook_fixture,
  tibble::tibble(
    level = "municipal",
    year = 2025,
    code_variable = "3.3",
    source_code = "3.3",
    question_text = "Another question"
  )
)
stopifnot(inherits(
  try(
    build_pemob_question_registry(duplicate_book, duplicate_seed),
    silent = TRUE
  ),
  "try-error"
))
bad_review <- dplyr::mutate(review_fixture, evidence = NA_character_)
stopifnot(inherits(
  try(
    build_pemob_question_registry(codebook_fixture, seed_fixture, bad_review),
    silent = TRUE
  ),
  "try-error"
))

quality_fixture <- tidyr::expand_grid(
  level = "municipal",
  code_variable = "1.1",
  year = 2021:2025,
  place_key = as.character(1:10)
) |>
  dplyr::mutate(
    participated = TRUE,
    value_raw = ifelse(place_key == "1", "1", NA_character_),
    parse_status = ifelse(place_key == "1", "parsed", "missing")
  )
numeric_fixture <- dplyr::mutate(
  reviewed_fixture,
  valid_editions = ifelse(
    level == "municipal",
    "2021;2022;2023;2024;2025",
    valid_editions
  ),
  reviewed_type_editions = ifelse(
    level == "municipal",
    "2021;2022;2023;2024;2025",
    reviewed_type_editions
  )
)
quality_result <- score_pemob_question_eligibility(
  numeric_fixture,
  quality_fixture
)
stopifnot(
  quality_result$decision[
    quality_result$product == "table" &
      quality_result$level == "municipal"
  ] ==
    "eligible",
  quality_result$decision[
    quality_result$product == "dashboard" &
      quality_result$level == "municipal"
  ] ==
    "excluded"
)
restricted_type <- dplyr::mutate(
  numeric_fixture,
  reviewed_type_editions = ifelse(
    level == "municipal",
    "2024;2025",
    reviewed_type_editions
  )
)
restricted_result <- score_pemob_question_eligibility(
  restricted_type,
  quality_fixture
)
stopifnot(all(
  restricted_result$decision[restricted_result$level == "municipal"] ==
    "unresolved"
))
text_result <- score_pemob_question_eligibility(
  dplyr::mutate(numeric_fixture, value_type = "text"),
  quality_fixture
)
stopifnot(all(
  text_result$decision[text_result$level == "municipal"] == "unresolved"
))

documented_options <- tibble::tibble(
  level = "municipal",
  code_variable = "1.1",
  year = 2021:2025,
  value_raw = "1",
  source_ref = "Fixture questionnaire options",
  reviewer = "Phase 5 test"
)
documented_result <- score_pemob_question_eligibility(
  dplyr::mutate(numeric_fixture, value_type = "categorical"),
  quality_fixture,
  response_options = documented_options
)
stopifnot(
  documented_result$decision[
    documented_result$level == "municipal" &
      documented_result$product == "table"
  ] ==
    "eligible"
)
partial_result <- score_pemob_question_eligibility(
  dplyr::mutate(numeric_fixture, value_type = "categorical"),
  quality_fixture,
  response_options = documented_options[1, ]
)
stopifnot(all(
  partial_result$decision[
    partial_result$level == "municipal"
  ] ==
    "unresolved"
))

category_fixture <- build_pemob_category_evidence(
  tibble::tibble(
    label = c("Shared", "Seed only"),
    categoria = "Frota",
    subcategoria = "Ônibus"
  ),
  tibble::tibble(
    categoria = "Frota",
    subcategoria = "Ônibus",
    label = "Shared"
  ),
  tibble::tibble(
    category = "Frota",
    subcategory = "Ônibus",
    label = "Shared",
    source_commit = "test-commit",
    source_path = "filter-categories.ts"
  )
)
stopifnot(
  nrow(category_fixture) == 2L,
  all(category_fixture$in_seed[category_fixture$label == "Shared"]),
  all(category_fixture$in_dim[category_fixture$label == "Shared"]),
  all(category_fixture$in_live[category_fixture$label == "Shared"]),
  !category_fixture$in_live[category_fixture$label == "Seed only"]
)

real_codebook <- build_pemob_codebook()
real_pairs <- dplyr::distinct(real_codebook, level, code_variable)
stopifnot(
  nrow(real_pairs) == 815L,
  sum(real_pairs$level == "municipal") == 473L,
  sum(real_pairs$level == "metropolitan") == 342L
)
live_snapshot <- readr::read_csv(
  here::here("tabelas", "pemob_live_labels_2024.csv"),
  col_types = readr::cols(.default = readr::col_character()),
  show_col_types = FALSE
)
stopifnot(nrow(live_snapshot) == 160L, sum(is.na(live_snapshot$label)) == 8L)
