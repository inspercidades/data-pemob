portal_code <- parse("R/pemob_portal_final.R")
metro_code <- parse("R/pemob_metropolitana.R")
source("R/pemob_helpers.R")

assignment <- function(code, name) {
  matches <- vapply(
    code,
    function(expr) {
      is.call(expr) &&
        identical(expr[[1]], as.name("<-")) &&
        identical(expr[[2]], as.name(name))
    },
    logical(1)
  )
  return(code[[which(matches)[1]]])
}

portal_env <- new.env()
portal_env$here <- here::here
eval(assignment(portal_code, "dict"), portal_env)
stopifnot("code_variable" %in% names(portal_env$dict))

metro_env <- new.env()
metro_env$tibble <- tibble::tibble
metro_env$all_years <- c(2019, 2021:2024)
complete <- data.frame(
  metro_key = "SP::Example",
  abbrev_state = "SP",
  name_metro = "Example",
  year = metro_env$all_years,
  answer = 1:5
)
metro_env$iter_pemob <- list(complete, complete[complete$year != 2021, ])
eval(assignment(metro_code, "error_inds"), metro_env)
eval(assignment(metro_code, "find_missing_years"), metro_env)
missing <- metro_env$find_missing_years(metro_env$iter_pemob[[2]])
stopifnot(
  identical(metro_env$error_inds, c(FALSE, TRUE)),
  missing$name_variable == "answer",
  missing$missing == "2021"
)

fare_series <- data.frame(
  code_muni = 1,
  name_muni = "Example",
  abbrev_state = "SP",
  year = 2019:2023,
  code_variable = "3.1.1.A",
  raw_response = c("5", "5", "50", "5", "NR")
)
cycle_outliers <- data.frame(
  code_muni = 100:107,
  name_muni = paste("City", 100:107),
  abbrev_state = "SP",
  year = 2024,
  code_variable = "1.6.1.G",
  raw_response = c("10", "12", "13", "14", "15", "16", "20", "17600")
)
other_candidates <- data.frame(
  code_muni = c(2, 2, 4, 5),
  name_muni = c("Zero City", "Zero City", "Unit City", "Text City"),
  abbrev_state = "SP",
  year = c(2023, 2024, 2024, 2024),
  code_variable = "1.6.1.H",
  raw_response = c("0", "10", "15 m", "texto sem número")
)
negative_fare <- data.frame(
  code_muni = 6,
  name_muni = "Negative City",
  abbrev_state = "SP",
  year = 2024,
  code_variable = "3.1.1.A",
  raw_response = "-1"
)
review_fixture <- rbind(
  fare_series,
  cycle_outliers,
  other_candidates,
  negative_fare
)
review_candidates <- build_pemob_review_candidates(review_fixture)
empty_candidates <- build_pemob_review_candidates(review_fixture[FALSE, ])

stopifnot(
  any(
    review_candidates$code_muni == 1 &
      review_candidates$year == 2021 &
      grepl("abrupt_change_10x", review_candidates$flag_reasons)
  ),
  any(
    review_candidates$code_muni == 107 &
      review_candidates$year == 2024 &
      grepl("cross_city_outlier", review_candidates$flag_reasons)
  ),
  any(
    review_candidates$code_muni == 2 &
      grepl("zero_transition", review_candidates$flag_reasons)
  ),
  any(
    review_candidates$code_muni == 4 &
      grepl("unit_mismatch", review_candidates$flag_reasons)
  ),
  any(
    review_candidates$code_muni == 5 &
      grepl("unparsed_response", review_candidates$flag_reasons)
  ),
  any(
    review_candidates$code_muni == 6 &
      grepl("negative_value", review_candidates$flag_reasons)
  ),
  !any(review_candidates$raw_response == "NR"),
  all(review_candidates$review_decision == "pending"),
  all(
    is.na(review_candidates$treated_value) ==
      is.na(review_candidates$parsed_value) &
      review_candidates$treated_value == review_candidates$parsed_value,
    na.rm = TRUE
  ),
  any(review_candidates$raw_response == "15 m"),
  nrow(empty_candidates) == 0L,
  all(c("flag_reasons", "review_decision") %in% names(empty_candidates))
)
