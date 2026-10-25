# Generated indicator review contracts ---------------------------------------

out_dir <- Sys.getenv("PEMOB_REVIEW_OUTPUT_DIR", unset = "review")
metro_path <- file.path(out_dir, "indicator_review_metropolitan.csv")
diagnostics_path <- file.path(out_dir, "indicator_diagnostics.csv")

stopifnot(file.exists(metro_path), file.exists(diagnostics_path))

metro <- readr::read_csv(metro_path, show_col_types = FALSE)
municipal <- readr::read_csv(
  file.path(out_dir, "indicator_review.csv"),
  show_col_types = FALSE
)
diagnostics <- readr::read_csv(diagnostics_path, show_col_types = FALSE)
codebook <- readr::read_csv(
  here::here("data", "dataverse_draft", "codebook.csv"),
  show_col_types = FALSE
)
long <- readr::read_csv(
  here::here("data", "dataverse_draft", "metropolitan_long.csv"),
  show_col_types = FALSE
)

stopifnot(
  !anyDuplicated(metro$code),
  !anyDuplicated(diagnostics[c("level", "code")]),
  all(metro$code %in% codebook$code_variable[codebook$level == "metropolitan"]),
  all(
    municipal$code %in% codebook$code_variable[codebook$level == "municipal"]
  ),
  !"places_2020" %in% names(metro),
  !2020 %in%
    readr::read_csv(
      file.path(out_dir, "participants_metropolitan.csv"),
      show_col_types = FALSE
    )$year,
  !any(
    c("subject", "type", "dashboard_pemob", "tabela_pemob") %in%
      names(metro)
  ),
  setequal(diagnostics$code[diagnostics$level == "metropolitan"], metro$code),
  setequal(diagnostics$code[diagnostics$level == "municipal"], municipal$code),
  !any(
    c("include_table", "include_dashboard", "notes") %in% names(diagnostics)
  )
)

participants <- long |>
  dplyr::filter(participated) |>
  dplyr::distinct(year, place_key) |>
  dplyr::count(year, name = "expected")
exported <- readr::read_csv(
  file.path(out_dir, "participants_metropolitan.csv"),
  show_col_types = FALSE
)
stopifnot(isTRUE(all.equal(
  exported$participants[match(participants$year, exported$year)],
  participants$expected
)))

code <- metro$code[which.max(metro$n_answers)]
editions <- codebook |>
  dplyr::filter(level == "metropolitan", code_variable == code) |>
  dplyr::pull(year)
valid <- long |>
  dplyr::filter(
    code_variable == code,
    participated,
    parse_status != "missing"
  ) |>
  dplyr::distinct(year, place_key) |>
  dplyr::count(year, name = "answers")
expected_rate <- mean(vapply(
  editions,
  function(year) {
    n <- valid$answers[match(year, valid$year)]
    if (is.na(n)) {
      n <- 0L
    }
    n / participants$expected[match(year, participants$year)]
  },
  numeric(1)
))
stopifnot(isTRUE(all.equal(
  metro$response_rate_mean[metro$code == code],
  expected_rate
)))

# Unparseable reported answers remain in the zero-share denominator.
municipal_long <- readr::read_csv(
  here::here("data", "dataverse_draft", "municipal_long.csv"),
  show_col_types = FALSE,
  guess_max = 1e6
)
zero_code <- "3.7.1.J"
zero_answers <- municipal_long |>
  dplyr::filter(
    code_variable == zero_code,
    participated,
    parse_status != "missing"
  )
zero_row <- municipal[municipal$code == zero_code, ]
stopifnot(
  nrow(zero_answers) == 26L,
  sum(zero_answers$value_num == 0, na.rm = TRUE) == 3L,
  isTRUE(all.equal(zero_row$zero_share, 3 / 26)),
  !grepl("muitos zeros", zero_row$quality_flags, fixed = TRUE)
)

# Reviewers decide on the Tabela and the Dashboard separately.
snapshot <- readr::read_csv(
  file.path(out_dir, "snapshot_long.csv"),
  show_col_types = FALSE
)
snapshot_codes <- readr::read_csv(
  file.path(out_dir, "snapshot_codes.csv"),
  show_col_types = FALSE
)$code_indicator
metro_snapshot_codes <- readr::read_csv(
  file.path(out_dir, "snapshot_codes_metropolitan.csv"),
  show_col_types = FALSE
)$code_indicator
metro_snapshot <- readr::read_csv(
  file.path(out_dir, "snapshot_long_metropolitan.csv"),
  show_col_types = FALSE
)
stopifnot(
  all(c("include_table", "include_dashboard") %in% names(municipal)),
  all(c("include_table", "include_dashboard") %in% names(metro)),
  !any(c("interest", "checklist") %in% c(names(municipal), names(metro))),
  !anyNA(municipal$short_question),
  !"Pesquisa Origem e Destino" %in% municipal$subject,
  "code_muni" %in% names(snapshot),
  !"place_key" %in% names(metro_snapshot),
  !anyDuplicated(metro_snapshot[c(
    "place_name",
    "abbrev_state",
    "year",
    "code_indicator"
  )]),
  identical(snapshot_codes, municipal$code),
  identical(metro_snapshot_codes, metro$code),
  all(snapshot$code_indicator %in% municipal$code),
  all(metro_snapshot$code_indicator %in% metro$code)
)
