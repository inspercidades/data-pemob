source("R/pemob_helpers.R")
source("R/pemob_2025.R")

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
  all(parsed$parse_status[7:12] == c(rep("missing", 5), "review")),
  parsed$missing_reason[7:11] == c("NA", "NR", "ND", "-", "blank"),
  parsed$parsed_value[13] == 0,
  parsed$parse_status[13] == "parsed",
  identical(parsed$parsed_value[14:18], c(0.5, 0.5, 0, 1, 0)),
  all(parsed$parse_status[14:20] == "parsed"),
  identical(parsed$parsed_unit[19:20], c("m", "km")),
  parsed$parse_status[21] == "missing",
  parsed$missing_reason[21] == "NA",
  is.na(parsed$raw_response[21])
)

municipal_2025 <- read_pemob_2025(
  "data-raw/pemob_municipal_2025(pemob_municipal_25).csv"
)
fares_2025 <- parse_pemob_response(municipal_2025[["3.1.1.A"]])

stopifnot(
  sum(fares_2025$parse_status == "parsed") == 81L,
  sum(fares_2025$parse_status == "missing") == 1L,
  all(fares_2025$parsed_unit[fares_2025$parse_status == "parsed"] == "BRL")
)

fare_2019 <- readxl::read_excel(
  "data-raw/Pemob2019_Municipal.xlsx",
  skip = 1,
  col_types = "text"
)[["3.1.1.A"]]
parsed_fare_2019 <- parse_pemob_response(fare_2019)

stopifnot(any(
  fare_2019 == "RS3,45" & parsed_fare_2019$parsed_value == 3.45
))

shares <- scale_pemob_share(
  value = c(0, 2, NA_real_, 4),
  total = c(10, 4, 4, NA_real_)
)
stopifnot(identical(shares, c(0, 50, NA_real_, NA_real_)))
