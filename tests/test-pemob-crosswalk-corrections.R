source(here::here("R", "pemob_helpers.R"))

# Correction table ---------------------------------------------------------

corrections <- read_pemob_crosswalk_corrections()

stopifnot(
  all(
    c(
      "level",
      "edition",
      "code_2024",
      "crosswalk_code",
      "source_code",
      "reason"
    ) %in%
      names(corrections)
  ),
  !anyDuplicated(corrections[c("level", "edition", "code_2024")]),
  all(corrections$level %in% c("municipal", "metropolitan")),
  !anyNA(corrections$reason)
)


# Apply corrections --------------------------------------------------------

crosswalk <- data.frame(
  x2024 = c("1.1.1.A", "1.1.1.B", "1.1.1.C", "2.1.1"),
  x2020 = c("1.1.1.B", "1.1.1.A", "1.1.1.C", "2.1.1"),
  x2019 = c("1.1.1.A", "1.1.1.B", "1.1.1.C", "2.1.1")
)
synthetic_corrections <- data.frame(
  level = c("municipal", "municipal", "municipal", "metropolitan"),
  edition = c(2020, 2020, 2020, 2019),
  code_2024 = c("1.1.1.A", "1.1.1.B", "1.1.1.C", "2.1.1"),
  crosswalk_code = c("1.1.1.B", "1.1.1.A", "1.1.1.C", "2.1.1"),
  source_code = c("1.1.1.A", "1.1.1.B", NA, NA),
  reason = "test"
)

corrected <- correct_pemob_crosswalk(
  crosswalk,
  synthetic_corrections,
  level = "municipal"
)

stopifnot(
  identical(corrected$x2020, c("1.1.1.A", "1.1.1.B", NA, "2.1.1")),
  identical(corrected$x2019, crosswalk$x2019)
)

# A stale correction, an unknown code, or a source column linked twice stops
# the build.
stale <- synthetic_corrections
stale$crosswalk_code[1] <- "1.1.1.C"
unknown <- synthetic_corrections
unknown$code_2024[1] <- "9.9.9"
linked_twice <- synthetic_corrections[1, ]

failures <- vapply(
  list(stale, unknown, linked_twice),
  function(x) {
    tryCatch(
      {
        correct_pemob_crosswalk(crosswalk, x, level = "municipal")
        "ok"
      },
      error = function(e) "error"
    )
  },
  character(1)
)
stopifnot(all(failures == "error"))


# Split list cells ---------------------------------------------------------

flows <- data.frame(
  id = 1:6,
  `3.1.2.A` = c(
    "A - B; C - D; E - F",
    "R$ 4,50\r\nR$ 4,00\r\nR$ 4,55",
    "R$ 3,95;\r\nR$ 1,80;\r\n",
    "NR",
    "3.45",
    NA
  ),
  check.names = FALSE
)

split <- split_pemob_list_cells(flows, "3.1.2.A", parts = 3L)

stopifnot(
  identical(
    split[["3.1.2.A[1]"]],
    c("A - B", "R$ 4,50", "R$ 3,95", "NR", "3.45", NA)
  ),
  identical(
    split[["3.1.2.A[2]"]],
    c("C - D", "R$ 4,00", "R$ 1,80", "NR", NA, NA)
  ),
  identical(split[["3.1.2.A[3]"]], c("E - F", "R$ 4,55", NA, "NR", NA, NA)),
  identical(split[["3.1.2.A"]], flows[["3.1.2.A"]])
)

too_many <- flows
too_many$`3.1.2.A`[1] <- "a; b; c; d"
stopifnot(identical(
  tryCatch(
    split_pemob_list_cells(too_many, "3.1.2.A", parts = 3L),
    error = function(e) "error"
  ),
  "error"
))
