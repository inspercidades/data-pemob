source(here::here("R", "pemob_helpers.R"))

# Repair table -------------------------------------------------------------

repairs <- read_pemob_code_repairs()

stopifnot(
  all(c("edition", "column", "source_code", "code_2024") %in% names(repairs)),
  !anyDuplicated(repairs[c("edition", "column")]),
  !anyDuplicated(repairs[c("edition", "code_2024")])
)


# Source columns -----------------------------------------------------------

source_dat <- data.frame(
  id = 1:2,
  a = c("x", "y"),
  b = c("10", "20"),
  b = c("30", "40"),
  check.names = FALSE
)
names(source_dat) <- c("id", "4.4.1...2", "4.4.1...3", "4.5.1")
synthetic_repairs <- data.frame(
  edition = 2020,
  column = 3L,
  source_code = "4.4.1",
  code_2024 = "4.5.1"
)

repaired <- repair_pemob_source_codes(source_dat, 2020, synthetic_repairs)
untouched <- repair_pemob_source_codes(source_dat, 2019, synthetic_repairs)

stopifnot(
  identical(names(repaired), c("id", "4.4.1...2", "repaired:4.5.1", "4.5.1")),
  identical(repaired[["repaired:4.5.1"]], c("10", "20")),
  identical(names(untouched), names(source_dat))
)

wrong_column <- synthetic_repairs
wrong_column$column <- 4L
wrong_column_result <- tryCatch(
  repair_pemob_source_codes(source_dat, 2020, wrong_column),
  error = function(e) "error"
)
stopifnot(identical(wrong_column_result, "error"))


# Crosswalk ----------------------------------------------------------------

crosswalk <- data.frame(
  x2024 = c("4.4.1", "4.5.1", "1.4.1.B"),
  x2020 = c("4.4.1", "4.4.1", "1.4.1.B"),
  x2019 = c("4.4.1", "4.6.1", "1.4.1.B")
)
repaired_crosswalk <- repair_pemob_municipal_crosswalk(
  crosswalk,
  synthetic_repairs
)

stopifnot(
  identical(repaired_crosswalk$x2020, c("4.4.1", "repaired:4.5.1", "1.4.1.B")),
  identical(repaired_crosswalk$x2019, c("4.4.1", "4.6.1", NA))
)

unknown_code <- synthetic_repairs
unknown_code$code_2024 <- "9.9.9"
unknown_code_result <- tryCatch(
  repair_pemob_municipal_crosswalk(crosswalk, unknown_code),
  error = function(e) "error"
)
stopifnot(identical(unknown_code_result, "error"))


# Source contracts ---------------------------------------------------------

header_2019 <- suppressMessages(readxl::read_excel(
  here::here("data-raw", "Pemob2019_Municipal.xlsx"),
  n_max = 2,
  col_names = FALSE,
  .name_repair = "minimal"
))
header_2020 <- suppressMessages(readxl::read_excel(
  here::here("data-raw", "BancodeDados_PemobMunicipal_2020.xlsx"),
  n_max = 1,
  col_names = FALSE,
  .name_repair = "minimal"
))
repairs_2019 <- repairs[repairs$edition == 2019, ]
repairs_2020 <- repairs[repairs$edition == 2020, ]

stopifnot(
  identical(
    unname(unlist(header_2019[2, repairs_2019$column])),
    repairs_2019$source_code
  ),
  identical(
    stringr::str_squish(unname(unlist(header_2019[1, repairs_2019$column]))),
    repairs_2019$source_text
  ),
  identical(
    unname(unlist(header_2020[1, repairs_2020$column])),
    repairs_2020$source_code
  )
)
