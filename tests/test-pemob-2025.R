source(here::here("R", "pemob_2025.R"))

# Source contracts ---------------------------------------------------------

codes_file <- here::here("data-raw", "pemob_códigos.xlsx")
municipal_codes <- readxl::read_excel(codes_file, sheet = "pemob_municipal")
metro_codes <- readxl::read_excel(codes_file, sheet = "pemob_metropolitana")

stopifnot(
  all(c("BLOCO", "SEÇÃO", "2024", "2019") %in% names(municipal_codes)),
  all(c("BLOCO", "SEÇÂO", "2024", "2019") %in% names(metro_codes)),
  nrow(municipal_codes) == 472L,
  nrow(metro_codes) == 342L
)

municipal_2025 <- read_pemob_2025(
  here::here("data-raw", "pemob_municipal_2025(pemob_municipal_25).csv")
)
metro_2025 <- read_pemob_2025(
  here::here(
    "data-raw",
    "pemob_metropolitana_2025(pemob_metropolitana_2025).csv"
  )
)

stopifnot(
  nrow(municipal_2025) == 82L,
  nrow(metro_2025) == 29L,
  !anyDuplicated(municipal_2025[["CÓDIGO IBGE"]]),
  !anyDuplicated(metro_2025[["Região Metropolitana"]]),
  all(municipal_2025[["1.3.1.A"]] %in% c("NA", "NR")),
  sum(municipal_2025[["1.3.1.A"]] == "NR") == 2L
)

missing_tokens_file <- tempfile(fileext = ".csv")
writeLines(
  c(
    "Question text",
    "id,na,nr,nd,hyphen,blank",
    "1,NA,NR,ND,-,"
  ),
  missing_tokens_file
)
missing_tokens <- read_pemob_2025(missing_tokens_file)
unlink(missing_tokens_file)

stopifnot(identical(
  unlist(missing_tokens[1, -1], use.names = FALSE),
  c("NA", "NR", "ND", "-", "")
))


# History reader -----------------------------------------------------------

history_file <- tempfile(fileext = ".csv")
readr::write_excel_csv2(
  tibble::tibble(
    code_muni = c(1100205, 1100205),
    name_muni = "Porto Velho",
    abbrev_state = "RO",
    year = c(2023, 2024),
    `1.1.1` = c("Ônibus", NA),
    `3.1.1.A` = c("4,50", "NR"),
    participated = c(TRUE, FALSE)
  ),
  history_file,
  na = ""
)
history_read <- read_pemob_history(history_file)
unlink(history_file)

stopifnot(
  is.numeric(history_read$code_muni),
  is.numeric(history_read$year),
  is.logical(history_read$participated),
  identical(history_read[["3.1.1.A"]], c("4,50", "NR")),
  identical(history_read[["1.1.1"]], c("Ônibus", NA))
)


# Municipal append ---------------------------------------------------------

municipal_history <- tibble::tibble(
  code_muni = c(1100205, 1100205, 2927408, 2927408),
  name_muni = c("Porto Velho", "Porto Velho", "Salvador", "Salvador"),
  abbrev_state = c("RO", "RO", "BA", "BA"),
  year = c(2023, 2024, 2023, 2024),
  `1.1.1` = c("Ônibus", "Ônibus", "Metrô", NA),
  `12.2.1` = c("Sim", "Não", "Sim", NA),
  participated = c(TRUE, TRUE, TRUE, FALSE)
)
municipal_survey <- data.frame(
  `CÓDIGO IBGE` = c("1100205", "2111300"),
  UF = c("RO", "MA"),
  `Município` = c("Porto Velho", "São Luís"),
  `1.1.1` = c("Ônibus", "Ônibus"),
  `12.1.1` = c("Sim", "NR"),
  `1.3.1.A` = c("NA", "NR"),
  check.names = FALSE
)

municipal <- harmonize_municipal_2025(municipal_survey, municipal_history)
municipal <- dplyr::arrange(municipal, code_muni, year)
new_place <- municipal[municipal$code_muni == 2111300, ]
skipped_2025 <- municipal[
  municipal$code_muni == 2927408 & municipal$year == 2025,
]

stopifnot(
  nrow(municipal) == 9L,
  !anyDuplicated(municipal[c("code_muni", "year")]),
  !"12.1.1" %in% names(municipal),
  identical(
    municipal[["12.2.1"]][municipal$year == 2025 & municipal$participated],
    c("Sim", "NR")
  ),
  all(is.na(municipal[["1.3.1.A"]][municipal$year < 2025])),
  identical(new_place$participated, c(FALSE, FALSE, TRUE)),
  identical(new_place$name_muni, rep("São Luís", 3)),
  identical(new_place$abbrev_state, rep("MA", 3)),
  isFALSE(skipped_2025$participated),
  is.na(skipped_2025[["1.1.1"]]),
  identical(
    dplyr::semi_join(
      municipal,
      municipal_history,
      by = c("code_muni", "year")
    )[["1.1.1"]],
    municipal_history[["1.1.1"]]
  )
)

unknown_survey <- municipal_survey
unknown_survey[["9.9.9"]] <- "x"
unknown_code <- tryCatch(
  harmonize_municipal_2025(unknown_survey, municipal_history),
  error = function(e) "error"
)
stopifnot(identical(unknown_code, "error"))

state_survey <- municipal_survey
state_survey$UF[1] <- "AC"
state_mismatch <- tryCatch(
  harmonize_municipal_2025(state_survey, municipal_history),
  error = function(e) "error"
)
stopifnot(identical(state_mismatch, "error"))


# Metropolitan append ------------------------------------------------------

metro_aliases <- data.frame(
  abbrev_state = "AL",
  source_name = "RM Maceió",
  canonical_name = "Região Metropolitana de Maceió"
)
metro_history <- tibble::tibble(
  metro_key = c(
    "AL::Região Metropolitana de Maceió",
    "AL::Região Metropolitana de Maceió",
    "SP::Região Metropolitana de São Paulo",
    "SP::Região Metropolitana de São Paulo"
  ),
  abbrev_state = c("AL", "AL", "SP", "SP"),
  name_metro = c(
    "Região Metropolitana de Maceió",
    "Região Metropolitana de Maceió",
    "Região Metropolitana de São Paulo",
    "Região Metropolitana de São Paulo"
  ),
  year = c(2019, 2021, 2019, 2021),
  `1.1.1` = c("Ônibus", "Ônibus", "Metrô", "Metrô"),
  participated = c(TRUE, TRUE, TRUE, TRUE)
)
metro_survey <- data.frame(
  UF = c("AL", "PE"),
  `Região Metropolitana` = c("RM Maceió", "RM Recife"),
  `1.1.1` = c("VLT", "Metrô"),
  check.names = FALSE
)

metro <- harmonize_metro_2025(metro_survey, metro_history, metro_aliases)
maceio_2025 <- metro[
  metro$metro_key == "AL::Região Metropolitana de Maceió" & metro$year == 2025,
]

stopifnot(
  nrow(metro) == 9L,
  !anyDuplicated(metro[c("metro_key", "year")]),
  identical(sort(unique(metro$year)), c(2019, 2021, 2025)),
  identical(maceio_2025[["1.1.1"]], "VLT"),
  identical(maceio_2025$name_metro_source, "RM Maceió"),
  all(is.na(metro$name_metro_source[metro$year < 2025])),
  isFALSE(metro$participated[
    metro$abbrev_state == "SP" & metro$year == 2025
  ]),
  identical(
    metro$participated[metro$abbrev_state == "PE"],
    c(FALSE, FALSE, TRUE)
  )
)
