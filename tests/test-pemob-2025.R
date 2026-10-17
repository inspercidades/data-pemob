source("R/pemob_2025.R")

codes_file <- "data-raw/pemob_códigos.xlsx"
municipal_codes <- readxl::read_excel(codes_file, sheet = "pemob_municipal")
metro_codes <- readxl::read_excel(codes_file, sheet = "pemob_metropolitana")

stopifnot(
  all(c("BLOCO", "SEÇÃO", "2024", "2019") %in% names(municipal_codes)),
  all(c("BLOCO", "SEÇÂO", "2024", "2019") %in% names(metro_codes)),
  nrow(municipal_codes) == 472L,
  nrow(metro_codes) == 342L
)

municipal_2025 <- read_pemob_2025(
  "data-raw/pemob_municipal_2025(pemob_municipal_25).csv"
)
metro_2025 <- read_pemob_2025(
  "data-raw/pemob_metropolitana_2025(pemob_metropolitana_2025).csv"
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

municipal <- harmonize_municipal_2025(municipal_2025)
metro <- harmonize_metro_2025(metro_2025)

stopifnot(
  nrow(municipal) == 502L,
  nrow(metro) == 174L,
  sum(municipal$year == 2025) == 82L,
  sum(metro$year == 2025) == 29L,
  !anyDuplicated(municipal[c("code_muni", "year")]),
  !anyDuplicated(metro[c("name_metro", "year")]),
  !"12.1.1" %in% names(municipal),
  "1.3.1.A" %in% names(municipal),
  all(municipal[["1.3.1.A"]][municipal$year == 2025] %in% c("NA", "NR")),
  all(is.na(municipal[["1.3.1.A"]][municipal$year < 2025])),
  all(!is.na(municipal$code_state[municipal$year == 2025])),
  all(!is.na(municipal$name_state[municipal$year == 2025]))
)

fund_2025 <- municipal[["12.2.1"]][municipal$year == 2025]
source_fund <- municipal_2025[["12.1.1"]]
source_fund <- source_fund[match(
  municipal$code_muni[municipal$year == 2025],
  as.numeric(municipal_2025[["CÓDIGO IBGE"]])
)]
stopifnot(identical(fund_2025, source_fund))

new_municipalities <- setdiff(
  municipal$code_muni[municipal$year == 2025],
  municipal$code_muni[municipal$year == 2024]
)
stopifnot(length(new_municipalities) == 25L)

new_metros <- setdiff(
  metro$name_metro[metro$year == 2025],
  metro$name_metro[metro$year == 2024]
)
stopifnot(length(new_metros) == 2L)

stopifnot(identical(
  unique(municipal$name_state[
    municipal$year == 2025 & municipal$abbrev_state == "MA"
  ]),
  "Maranhão"
))

baseline_municipal <- readxl::read_excel(
  "tabelas/PEMOB Harmonizada 2024.xlsx",
  sheet = "PEMOB Muni Harmonizada 24"
)
baseline_metro <- readxl::read_excel(
  "tabelas/PEMOB Harmonizada 2024.xlsx",
  sheet = "PEMOB Metro Harmonizada 24"
)
stopifnot(
  identical(
    municipal$code_muni[municipal$year < 2025],
    baseline_municipal$code_muni
  ),
  identical(metro$name_metro[metro$year < 2025], baseline_metro$name_metro),
  identical(
    municipal[["1.1.1"]][municipal$year < 2025],
    as.character(baseline_municipal[["1.1.1"]])
  )
)
