source(here::here("R", "pemob_helpers.R"))
source(here::here("R", "pemob_2025.R"))

municipal_2019 <- read_pemob_source(
  here::here("data-raw", "Pemob2019_Municipal.xlsx"),
  skip = 1
)
raw_fare_2019 <- municipal_2019[["3.1.1.A"]]
parsed_fare_2019 <- parse_pemob_response(raw_fare_2019)

stopifnot(
  is.character(raw_fare_2019),
  any(raw_fare_2019 == "NR", na.rm = TRUE),
  any(parsed_fare_2019$missing_reason == "NR", na.rm = TRUE),
  any(raw_fare_2019 == "", na.rm = TRUE),
  any(parsed_fare_2019$missing_reason == "blank", na.rm = TRUE),
  any(raw_fare_2019 == "RS3,45", na.rm = TRUE),
  any(parsed_fare_2019$parsed_value == 3.45, na.rm = TRUE)
)

municipal_2024 <- read_pemob_source(
  here::here("data-raw", "pemob_municipal_2024.xlsx"),
  skip = 1
)
metro_2024 <- read_pemob_source(
  here::here("data-raw", "pemob_metropolitana_2024.xlsx"),
  skip = 1
)
stopifnot(
  municipal_2024[["3.1.1.C"]][1] == "2022-10-01",
  municipal_2024[["11.2.2.B"]][2] == "2030-12-01",
  municipal_2024[["11.2.2.B"]][1] == "NA",
  metro_2024[["3.1.1.J"]][1] == "2023-05-01",
  metro_2024[["3.1.1.C"]][1] == "8.1"
)

numeric_cells_file <- tempfile(fileext = ".xlsx")
writexl::write_xlsx(
  list(
    data = data.frame(
      measured = c(76.1, 0.07, 9935487.59, 2429753, 0.23816, 100000),
      typed = c("1.320", "76.099999999999994", "15,24 km", "", "NR", "0")
    )
  ),
  numeric_cells_file
)
numeric_cells <- read_pemob_source(numeric_cells_file)
comma_locale_cells <- withr::with_options(
  list(OutDec = ","),
  read_pemob_source(numeric_cells_file)
)
unlink(numeric_cells_file)

stopifnot(
  identical(
    numeric_cells$measured,
    c("76.1", "0.07", "9935487.59", "2429753", "0.23816", "100000")
  ),
  identical(comma_locale_cells$measured, numeric_cells$measured),
  identical(
    numeric_cells$typed,
    c("1.320", "76.099999999999994", "15,24 km", "", "NR", "0")
  )
)

missing_variants <- c(
  "N/D",
  "N/A",
  "Não disponível",
  "NAO DISPONIVEL",
  "Sem informação",
  "Sem informacao",
  "Não se aplica",
  "Não respondeu",
  "NÃO INFORMADO"
)
parsed_missing_variants <- parse_pemob_response(missing_variants)
stopifnot(
  all(parsed_missing_variants$parse_status == "missing"),
  identical(
    parsed_missing_variants$missing_reason,
    c(
      "N/D",
      "N/A",
      "not_available",
      "not_available",
      "no_information",
      "no_information",
      "not_applicable",
      "NR",
      "not_reported"
    )
  ),
  identical(parsed_missing_variants$raw_response, missing_variants)
)

excel_error_tokens <- c(
  "#N/A",
  "#VALUE!",
  "#DIV/0!",
  "#REF!",
  "#NAME?",
  "#NUM!",
  "#NULL!"
)
parsed_excel_errors <- parse_pemob_response(excel_error_tokens)
stopifnot(
  all(parsed_excel_errors$parse_status == "missing"),
  identical(parsed_excel_errors$missing_reason, excel_error_tokens)
)

responses <- c(
  "R$ 5.50",
  "R$ 5,50",
  "RS3,45",
  "15,24 km",
  "18 m",
  "1.320",
  "NA",
  "NR",
  "ND",
  "#REF!",
  "-",
  "",
  "Texto livre",
  "0",
  "0,500",
  "5,0000e-01",
  "FALSE",
  "Sim",
  "Não",
  "12 metros",
  "10,5 quilômetros",
  NA_character_
)
parsed <- parse_pemob_response(responses)

stopifnot(
  identical(parsed$raw_response, responses),
  identical(parsed$parsed_value[1:5], c(5.5, 5.5, 3.45, 15.24, 18)),
  identical(parsed$parsed_unit[1:5], c("BRL", "BRL", "BRL", "km", "m")),
  parsed$parse_status[6] == "review",
  all(parsed$parse_status[7:13] == c(rep("missing", 6), "review")),
  parsed$missing_reason[7:12] == c("NA", "NR", "ND", "#REF!", "-", "blank"),
  parsed$parsed_value[14] == 0,
  parsed$parse_status[14] == "parsed",
  identical(parsed$parsed_value[15:19], c(0.5, 0.5, 0, 1, 0)),
  all(parsed$parse_status[15:21] == "parsed"),
  identical(parsed$parsed_unit[20:21], c("m", "km")),
  parsed$parse_status[22] == "missing",
  parsed$missing_reason[22] == "NA",
  is.na(parsed$raw_response[22])
)

municipal_2025 <- read_pemob_2025(
  here::here("data-raw", "pemob_municipal_2025(pemob_municipal_25).csv")
)
fares_2025 <- parse_pemob_response(municipal_2025[["3.1.1.A"]])

stopifnot(
  sum(fares_2025$parse_status == "parsed") == 81L,
  sum(fares_2025$parse_status == "missing") == 1L,
  all(fares_2025$parsed_unit[fares_2025$parse_status == "parsed"] == "BRL")
)

shares <- scale_pemob_share(
  value = c(0, 2, NA_real_, 4),
  total = c(10, 4, 4, NA_real_)
)
stopifnot(identical(shares, c(0, 50, NA_real_, NA_real_)))
