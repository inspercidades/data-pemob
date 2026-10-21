source(here::here("R", "pemob_dataverse.R"))

status_bytes <- function(...) {
  records <- c(...)
  return(unlist(
    lapply(records, function(record) c(charToRaw(record), as.raw(0))),
    use.names = FALSE
  ))
}

stopifnot(
  !is_pemob_source_tree_dirty(raw(), "data/dataverse_draft"),
  !is_pemob_source_tree_dirty(
    status_bytes(" M data/dataverse_draft/municipal_long.csv"),
    "data/dataverse_draft"
  ),
  !is_pemob_source_tree_dirty(
    status_bytes("?? data/dataverse_draft/municipal_long.csv"),
    "data/dataverse_draft"
  ),
  !is_pemob_source_tree_dirty(
    status_bytes(
      ' M data/dataverse draft (v1)/a "quoted" file.csv',
      "?? data/dataverse draft (v1)/file with spaces.csv"
    ),
    "data/dataverse draft (v1)"
  ),
  is_pemob_source_tree_dirty(
    status_bytes(
      " M R/pemob_dataverse.R",
      " M data/dataverse_draft/manifest.csv"
    ),
    "data/dataverse_draft"
  ),
  is_pemob_source_tree_dirty(
    status_bytes(
      " D data/dataverse_draft/moved.csv",
      "?? data/source with spaces.csv"
    ),
    "data/dataverse_draft"
  ),
  is_pemob_source_tree_dirty(
    status_bytes(
      " D data/source with spaces.csv",
      "?? data/dataverse_draft/moved.csv"
    ),
    "data/dataverse_draft"
  ),
  is_pemob_source_tree_dirty(
    status_bytes(" M data/source with spaces.csv"),
    "data/dataverse_draft"
  ),
  is_pemob_source_tree_dirty(
    status_bytes("?? data/dataverse_draft_extra/source.csv"),
    "data/dataverse_draft"
  ),
  is_pemob_source_tree_dirty(
    status_bytes(" M data/dataverse_draft/municipal_long.csv"),
    NA_character_
  ),
  is_pemob_source_tree_dirty(
    charToRaw(" M data/dataverse_draft/municipal_long.csv"),
    "data/dataverse_draft"
  ),
  is_pemob_source_tree_dirty(
    status_bytes("invalid data/dataverse_draft/municipal_long.csv"),
    "data/dataverse_draft"
  ),
  is_pemob_source_tree_dirty(
    c(status_bytes(" M data/dataverse_draft/manifest.csv"), as.raw(0)),
    "data/dataverse_draft"
  )
)

local({
  git_root <- tempfile("pemob_git_status_")
  dir.create(git_root)
  on.exit(unlink(git_root, recursive = TRUE), add = TRUE)
  git <- function(...) {
    return(system2("git", c("-C", shQuote(git_root), ...), stdout = TRUE))
  }
  stopifnot(identical(git("init", "-q"), character()))
  dir.create(file.path(git_root, "data", "draft with spaces"), recursive = TRUE)
  generated <- file.path(git_root, "data", "draft with spaces", "saved.csv")
  source_path <- file.path(git_root, "data", "source with spaces.csv")
  writeLines("source", source_path)
  stopifnot(identical(git("add", "."), character()))
  git(
    "-c",
    "user.name=Test",
    "-c",
    "user.email=test@example.invalid",
    "commit",
    "-qm",
    "fixture"
  )
  file.rename(source_path, generated)
  status_file <- tempfile("pemob_git_status_bytes_")
  on.exit(unlink(status_file), add = TRUE)
  exit_status <- system2(
    "git",
    c(
      "-C",
      shQuote(git_root),
      "status",
      "--porcelain=v1",
      "-z",
      "--no-renames",
      "--untracked-files=all"
    ),
    stdout = status_file
  )
  status <- readBin(status_file, "raw", n = file.info(status_file)$size)
  ends <- which(status == as.raw(0))
  starts <- c(1L, head(ends, -1L) + 1L)
  records <- mapply(
    function(start, end) rawToChar(status[start:(end - 1L)]),
    starts,
    ends,
    USE.NAMES = FALSE
  )
  stopifnot(
    identical(exit_status, 0L),
    setequal(
      records,
      c(
        " D data/source with spaces.csv",
        "?? data/draft with spaces/saved.csv"
      )
    ),
    is_pemob_source_tree_dirty(status, "data/draft with spaces")
  )
})

panel_fixture <- tibble::tibble(
  code_muni = c(1, 2, 3),
  name_muni = c("A", "B", "C"),
  abbrev_state = "SP",
  year = 2024,
  participated = c(TRUE, TRUE, FALSE),
  `1.1.1` = c("NA", "", NA_character_),
  `3.1.1.A` = c("R$ 4,50", "texto", NA_character_),
  `9.9.9` = c(NA_character_, NA_character_, NA_character_)
)
treated_fixture <- tibble::tibble(
  code_muni = c(1, 3),
  year = 2024,
  code_variable = "3.1.1.A",
  raw_response = c("R$ 4,50", NA_character_),
  treated_value = c(5, 4),
  treatment_status = c("corrected", "interpolated"),
  treatment_method = c(NA_character_, "equal_endpoints"),
  review_evidence = c("Source record", NA_character_),
  reviewer = c("Reviewer", NA_character_)
)

long_fixture <- build_pemob_long(panel_fixture, "municipal", treated_fixture)
stopifnot(
  nrow(long_fixture) == 5L,
  !anyDuplicated(long_fixture[c("code_muni", "year", "code_variable")]),
  is.character(long_fixture$value_raw),
  all(is.na(long_fixture$value_type)),
  all(is.na(long_fixture$unit)),
  !"9.9.9" %in% long_fixture$code_variable,
  identical(
    long_fixture$missing_code[which(long_fixture$value_raw == "NA")],
    "NA"
  ),
  identical(
    long_fixture$missing_code[which(long_fixture$value_raw == "")],
    "blank"
  ),
  long_fixture$value_num[which(long_fixture$value_raw == "R$ 4,50")] == 4.5,
  long_fixture$value_treated[which(long_fixture$value_raw == "R$ 4,50")] == 5,
  long_fixture$treatment_status[which(long_fixture$value_raw == "R$ 4,50")] ==
    "corrected",
  is.na(long_fixture$value_num[which(long_fixture$value_raw == "texto")]),
  long_fixture$treatment_status[which(long_fixture$value_raw == "texto")] ==
    "reported",
  long_fixture$value_treated[
    long_fixture$place_key == "3"
  ] ==
    4,
  is.na(long_fixture$value_raw[long_fixture$place_key == "3"]),
  !long_fixture$participated[long_fixture$place_key == "3"]
)

stale_fixture <- treated_fixture
stale_fixture$raw_response <- "4,50"
stopifnot(inherits(
  try(
    build_pemob_long(panel_fixture, "municipal", stale_fixture),
    silent = TRUE
  ),
  "try-error"
))

duplicate_fixture <- panel_fixture[c(1, 1), ]
stopifnot(inherits(
  try(build_pemob_long(duplicate_fixture, "municipal"), silent = TRUE),
  "try-error"
))

metro_fixture <- tibble::tibble(
  metro_key = "SP::Metropole",
  abbrev_state = "SP",
  name_metro = "Metropole",
  year = 2024,
  participated = TRUE,
  `1.1.1` = "NR"
)
participation_fixture <- build_pemob_participation_export(
  panel_fixture,
  metro_fixture
)
stopifnot(
  nrow(participation_fixture) == 4L,
  !participation_fixture$participated[
    participation_fixture$place_key == "3"
  ],
  any(participation_fixture$level == "metropolitan")
)

coverage_fixture <- tidyr::expand_grid(
  panel_fixture[c("code_muni", "year")],
  code_variable = pemob_target_variables
)
stopifnot(
  isTRUE(check_pemob_treatment_coverage(panel_fixture, coverage_fixture)),
  inherits(
    try(
      check_pemob_treatment_coverage(
        panel_fixture,
        coverage_fixture[-1, ]
      ),
      silent = TRUE
    ),
    "try-error"
  )
)

codebook <- build_pemob_codebook()
stopifnot(
  all(
    c("level", "year", "code_variable", "source_code", "question_text") %in%
      names(codebook)
  ),
  any(
    codebook$level == "municipal" &
      codebook$year == 2025 &
      !is.na(codebook$question_text)
  ),
  any(
    codebook$level == "municipal" &
      codebook$year == 2020 &
      is.na(codebook$question_text)
  ),
  any(
    codebook$level == "municipal" &
      codebook$year == 2019 &
      codebook$code_variable == "1.4.1.B" &
      codebook$source_code == "1.4.1.C"
  ),
  !anyDuplicated(codebook[c("level", "year", "code_variable", "source_code")])
)

export_fixture <- list(
  municipal_long = long_fixture,
  metropolitan_long = build_pemob_long(metro_fixture, "metropolitan"),
  codebook = tibble::tibble(
    level = c("municipal", "municipal", "metropolitan"),
    year = 2024,
    code_variable = c("1.1.1", "3.1.1.A", "1.1.1")
  )
)
stopifnot(
  isTRUE(check_pemob_export_coverage(export_fixture, treated_fixture)),
  inherits(
    try(
      check_pemob_export_coverage(
        within(export_fixture, codebook <- codebook[-1, ]),
        treated_fixture
      ),
      silent = TRUE
    ),
    "try-error"
  )
)

# Draft installation ------------------------------------------------------

local({
  writer_exports <- list(
    municipal_long = long_fixture,
    metropolitan_long = build_pemob_long(metro_fixture, "metropolitan"),
    participation = participation_fixture,
    codebook = codebook[seq_len(2), ],
    treatment_ledger = build_pemob_treatment_ledger_export(
      dplyr::mutate(
        treated_fixture,
        name_muni = c("A", "C"),
        abbrev_state = "SP",
        parsed_value = c(4.5, NA_real_)
      )
    )
  )
  writer_root <- tempfile("pemob_writer_test_")
  dir.create(writer_root)
  on.exit(unlink(writer_root, recursive = TRUE), add = TRUE)
  writer_output <- file.path(writer_root, "draft")
  .write_pemob_dataverse_draft(
    writer_exports,
    writer_output,
    commit = "test-commit",
    dirty = TRUE
  )
  written <- list.files(writer_output, all.files = TRUE, no.. = TRUE)
  stopifnot(
    setequal(
      written,
      c(
        ".pemob_dataverse_draft",
        "manifest.csv",
        paste0(names(writer_exports), ".csv")
      )
    )
  )
  round_trip <- readr::read_csv(
    file.path(writer_output, "municipal_long.csv"),
    col_types = readr::cols(.default = readr::col_character()),
    na = character(),
    show_col_types = FALSE
  )
  na_row <- round_trip[
    round_trip$place_key == "1" &
      round_trip$code_variable == "1.1.1",
  ]
  blank_row <- round_trip[
    round_trip$place_key == "2" &
      round_trip$code_variable == "1.1.1",
  ]
  absent_row <- round_trip[round_trip$place_key == "3", ]
  stopifnot(
    identical(na_row$value_raw, "NA"),
    identical(na_row$missing_code, "NA"),
    identical(blank_row$value_raw, ""),
    identical(blank_row$missing_code, "blank"),
    identical(absent_row$value_raw, ""),
    identical(absent_row$missing_code, ""),
    identical(absent_row$participated, "FALSE")
  )
  manifest <- readr::read_csv(
    file.path(writer_output, "manifest.csv"),
    show_col_types = FALSE
  )
  stopifnot(
    setequal(manifest$file, paste0(names(writer_exports), ".csv")),
    identical(
      as.integer(manifest$rows),
      unname(vapply(writer_exports, nrow, integer(1)))
    ),
    identical(
      manifest$md5,
      unname(tools::md5sum(file.path(writer_output, manifest$file)))
    ),
    all(manifest$git_commit == "test-commit"),
    all(manifest$working_tree_dirty)
  )

  unrelated <- file.path(writer_root, "unrelated")
  dir.create(unrelated)
  writeLines("keep", file.path(unrelated, "notes.txt"))
  stopifnot(inherits(
    try(
      .write_pemob_dataverse_draft(
        writer_exports,
        unrelated,
        "test-commit",
        TRUE
      ),
      silent = TRUE
    ),
    "try-error"
  ))
  stopifnot(identical(readLines(file.path(unrelated, "notes.txt")), "keep"))

  unlink(file.path(writer_output, ".pemob_dataverse_draft"))
  stopifnot(inherits(
    try(
      .write_pemob_dataverse_draft(
        writer_exports,
        writer_output,
        "test-commit",
        TRUE
      ),
      silent = TRUE
    ),
    "try-error"
  ))
  stopifnot(file.exists(file.path(writer_output, "manifest.csv")))
  writeLines(
    "pemob_dataverse_draft_v1",
    file.path(writer_output, ".pemob_dataverse_draft")
  )

  writeLines("keep", file.path(writer_output, "notes.txt"))
  stopifnot(inherits(
    try(
      .write_pemob_dataverse_draft(
        writer_exports,
        writer_output,
        "test-commit",
        TRUE
      ),
      silent = TRUE
    ),
    "try-error"
  ))
  stopifnot(identical(readLines(file.path(writer_output, "notes.txt")), "keep"))
  unlink(file.path(writer_output, "notes.txt"))

  stopifnot(inherits(
    try(
      build_pemob_dataverse(here::here()),
      silent = TRUE
    ),
    "try-error"
  ))
  stopifnot(file.exists(here::here("README.md")))

  stopifnot(inherits(
    try(
      build_pemob_dataverse(here::here("data")),
      silent = TRUE
    ),
    "try-error"
  ))
  stopifnot(file.exists(here::here("data", "pemob_harmonizada_2025.csv")))

  for (input_dir in c("data-raw", "tabelas")) {
    stopifnot(inherits(
      try(build_pemob_dataverse(here::here(input_dir)), silent = TRUE),
      "try-error"
    ))
  }

  replacement_exports <- writer_exports
  replacement_exports$municipal_long$value_raw[1] <- "replaced"
  .write_pemob_dataverse_draft(
    replacement_exports,
    writer_output,
    "second-commit",
    FALSE
  )
  stopifnot(
    identical(
      readr::read_csv(
        file.path(writer_output, "municipal_long.csv"),
        show_col_types = FALSE
      )$value_raw[1],
      "replaced"
    ),
    all(
      readr::read_csv(
        file.path(writer_output, "manifest.csv"),
        show_col_types = FALSE
      )$git_commit ==
        "second-commit"
    )
  )

  writer_output_path <- normalizePath(writer_output, winslash = "/")
  previous_md5 <- tools::md5sum(file.path(writer_output, written))
  rename_fail_install <- function(from, to) {
    if (identical(to, writer_output_path)) {
      return(FALSE)
    }
    return(file.rename(from, to))
  }
  stopifnot(inherits(
    try(
      .write_pemob_dataverse_draft(
        writer_exports,
        writer_output,
        "test-commit",
        TRUE,
        rename = rename_fail_install
      ),
      silent = TRUE
    ),
    "try-error"
  ))
  stopifnot(
    dir.exists(writer_output),
    identical(
      readLines(file.path(writer_output, ".pemob_dataverse_draft")),
      "pemob_dataverse_draft_v1"
    ),
    identical(tools::md5sum(file.path(writer_output, written)), previous_md5)
  )

  full_output <- file.path(writer_root, "full_draft")
  build_pemob_dataverse(full_output)
  stopifnot(
    identical(
      .check_pemob_draft_target(full_output),
      normalizePath(full_output, winslash = "/")
    ),
    nrow(readr::read_csv(
      file.path(full_output, "manifest.csv"),
      show_col_types = FALSE
    )) ==
      5L
  )
})
