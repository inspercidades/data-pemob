source(here::here("R", "pemob_helpers.R"))

crosswalk <- data.frame(
  x2024 = c("1.1.1", "1.2.1", "1.3.1"),
  x2020 = c("1.1.1", "1.2.1", NA),
  x2019 = c("1.1.1", "1.2.1.A-C", "1.3.1")
)
editions <- list(
  year_2024 = data.frame(
    code_muni = 1,
    `1.1.1` = "a",
    `1.2.1` = "b",
    `1.3.1` = "c",
    check.names = FALSE
  ),
  year_2020 = data.frame(code_muni = 1, `1.1.1` = "a", check.names = FALSE),
  year_2019 = data.frame(
    code_muni = 1,
    `1.1.1` = "a",
    `1.3.1` = "c",
    check.names = FALSE
  )
)

gaps <- find_pemob_crosswalk_gaps(crosswalk, editions)

stopifnot(
  identical(gaps$edition, c(2019, 2020)),
  identical(gaps$source_code, c("1.2.1.A-C", "1.2.1")),
  identical(gaps$code_2024, c("1.2.1", "1.2.1"))
)

expected <- data.frame(
  level = "municipal",
  edition = c(2019, 2020),
  source_code = c("1.2.1.A-C", "1.2.1"),
  reason = c("range", "not asked")
)
stopifnot(isTRUE(check_pemob_crosswalk_gaps(gaps, expected, "municipal")))

unexpected <- tryCatch(
  check_pemob_crosswalk_gaps(gaps, expected[1, ], "municipal"),
  error = function(e) "error"
)
stale <- tryCatch(
  check_pemob_crosswalk_gaps(gaps[1, ], expected, "municipal"),
  error = function(e) "error"
)
stopifnot(identical(unexpected, "error"), identical(stale, "error"))

listed <- read_pemob_crosswalk_gaps()
stopifnot(
  all(c("level", "edition", "source_code", "reason") %in% names(listed)),
  all(listed$level %in% c("municipal", "metropolitan")),
  !anyDuplicated(listed[c("level", "edition", "source_code")])
)
