source(here::here("R", "pemob_helpers.R"))

# Option table -------------------------------------------------------------

options <- read_pemob_range_options()

stopifnot(
  all(
    c(
      "level",
      "edition",
      "source_range",
      "source_code",
      "code_2024",
      "option_label",
      "none_label"
    ) %in%
      names(options)
  ),
  !anyDuplicated(options[c("level", "edition", "source_code")]),
  !anyNA(options$option_label),
  all(options$level %in% c("municipal", "metropolitan"))
)

# Each range maps to one 2024 question and one none label.
range_targets <- unique(options[c(
  "level",
  "source_range",
  "code_2024",
  "none_label"
)])
stopifnot(!anyDuplicated(range_targets[c("level", "source_range")]))


# Combine columns ----------------------------------------------------------

synthetic_options <- data.frame(
  level = "municipal",
  edition = 2019,
  source_range = "1.1.1.A-C",
  source_code = c("1.1.1.A", "1.1.1.B", "1.1.1.C"),
  code_2024 = "1.1.1",
  option_label = c("Ônibus", "Metrô", "Bicicleta"),
  none_label = "Nenhuma"
)

source_dat <- data.frame(
  code_muni = 1:7,
  `1.1.1.A` = c("Sim", "Sim", "Não", "NR", "NA", NA, " sim "),
  `1.1.1.B` = c("Não", "NR", "Nâo", "NR", "NA", NA, "Não"),
  `1.1.1.C` = c("Sim", "Não", "Não", "NR", "NA", NA, "Sim"),
  check.names = FALSE
)

combined <- combine_pemob_range_options(
  source_dat,
  synthetic_options,
  level = "municipal",
  edition = 2019
)

stopifnot(
  identical(
    combined[["1.1.1.A-C"]],
    c(
      "Ônibus; Bicicleta",
      "Ônibus",
      "Nenhuma",
      "NR",
      "NA",
      NA,
      "Ônibus; Bicicleta"
    )
  ),
  all(synthetic_options$source_code %in% names(combined))
)

# Other levels and editions leave the data unchanged.
stopifnot(identical(
  combine_pemob_range_options(
    source_dat,
    synthetic_options,
    level = "metropolitan",
    edition = 2019
  ),
  source_dat
))

# Unlisted answers, missing columns, and an all-"Não" row without a none
# label stop the build.
odd_answer <- source_dat
odd_answer$`1.1.1.A`[1] <- "Talvez"
mixed_codes <- source_dat[4, ]
mixed_codes$`1.1.1.A` <- "NA"
no_none_label <- synthetic_options
no_none_label$none_label <- NA_character_

failures <- vapply(
  list(
    function() {
      combine_pemob_range_options(
        odd_answer,
        synthetic_options,
        "municipal",
        2019
      )
    },
    function() {
      combine_pemob_range_options(
        source_dat[c("code_muni", "1.1.1.A")],
        synthetic_options,
        "municipal",
        2019
      )
    },
    function() {
      combine_pemob_range_options(
        mixed_codes,
        synthetic_options,
        "municipal",
        2019
      )
    },
    function() {
      combine_pemob_range_options(
        source_dat,
        no_none_label,
        "municipal",
        2019
      )
    }
  ),
  function(f) {
    tryCatch(
      {
        f()
        "ok"
      },
      error = function(e) "error"
    )
  },
  character(1)
)
stopifnot(all(failures == "error"))
