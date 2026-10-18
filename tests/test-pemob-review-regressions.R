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

interpolation_fixture <- data.frame(
  code_muni = c(
    10,
    10,
    10,
    11,
    11,
    11,
    12,
    12,
    12,
    13,
    13,
    13,
    14,
    14,
    14,
    14,
    15,
    15
  ),
  name_muni = paste(
    "City",
    c(
      rep(10, 3),
      rep(11, 3),
      rep(12, 3),
      rep(13, 3),
      rep(14, 4),
      rep(15, 2)
    )
  ),
  abbrev_state = "SP",
  year = c(
    2020:2022,
    2020:2022,
    2020:2022,
    2020:2022,
    2020:2023,
    2020,
    2022
  ),
  reference_time = c(
    1,
    2,
    5,
    1,
    2,
    3,
    1,
    2,
    3,
    1,
    2,
    3,
    1,
    2,
    3,
    4,
    1,
    3
  ),
  code_variable = c(
    rep("3.1.1.A", 3),
    rep("1.6.1.G", 3),
    rep("3.1.1.A", 3),
    rep("3.1.1.A", 3),
    rep("3.1.1.A", 4),
    rep("3.1.1.A", 2)
  ),
  raw_response = c(
    "5",
    "NR",
    "7",
    "0 km",
    "NR",
    "10 km",
    "5",
    "NR",
    "50",
    "5",
    "NA",
    "7",
    "2",
    "NR",
    "NR",
    "8",
    "2",
    "8"
  ),
  participated = c(
    rep(TRUE, 12),
    TRUE,
    FALSE,
    TRUE,
    TRUE,
    TRUE,
    TRUE
  ),
  review_decision = c(
    "accepted",
    "unreviewed",
    "accepted",
    "accepted",
    "unreviewed",
    "accepted",
    "accepted",
    "unreviewed",
    "pending",
    "accepted",
    "unreviewed",
    "accepted",
    "accepted",
    "unreviewed",
    "unreviewed",
    "accepted",
    "accepted",
    "accepted"
  ),
  stringsAsFactors = FALSE
)
interpolation_fixture$review_evidence <- ifelse(
  interpolation_fixture$review_decision == "accepted",
  "Synthetic endpoint review.",
  NA_character_
)
interpolation_before <- interpolation_fixture
interpolation_candidates <- build_pemob_interpolation_candidates(
  interpolation_fixture
)

stopifnot(
  interpolation_candidates$estimate_value[
    interpolation_candidates$code_muni == 10
  ] ==
    5.5,
  interpolation_candidates$estimate_value[
    interpolation_candidates$code_muni == 11
  ] ==
    5,
  interpolation_candidates$eligible[
    interpolation_candidates$code_muni == 10
  ],
  interpolation_candidates$endpoint_left_year[
    interpolation_candidates$code_muni == 10
  ] ==
    2020,
  interpolation_candidates$endpoint_right_year[
    interpolation_candidates$code_muni == 10
  ] ==
    2022,
  !interpolation_candidates$eligible[
    interpolation_candidates$code_muni == 12
  ],
  grepl(
    "endpoint_not_accepted",
    interpolation_candidates$eligibility_reason[
      interpolation_candidates$code_muni == 12
    ]
  ),
  !interpolation_candidates$eligible[
    interpolation_candidates$code_muni == 13
  ],
  grepl(
    "missing_reason_not_item_nonresponse",
    interpolation_candidates$eligibility_reason[
      interpolation_candidates$code_muni == 13
    ]
  ),
  !interpolation_candidates$eligible[
    interpolation_candidates$code_muni == 14
  ],
  any(grepl(
    "nonparticipation",
    interpolation_candidates$eligibility_reason[
      interpolation_candidates$code_muni == 14
    ]
  )),
  !15 %in% interpolation_candidates$code_muni,
  identical(interpolation_fixture, interpolation_before),
  all(interpolation_candidates$method == "linear_interpolation")
)

edge_fixture <- data.frame(
  code_muni = rep(c(16, 17), each = 3),
  name_muni = paste("City", rep(c(16, 17), each = 3)),
  abbrev_state = "SP",
  year = rep(2020:2022, 2),
  code_variable = "3.1.1.A",
  raw_response = c("2", "4", "NR", "NR", "2", "4"),
  participated = TRUE,
  review_decision = "accepted"
)
edge_fixture$review_evidence <- "Synthetic endpoint review."
unit_fixture <- data.frame(
  code_muni = 18,
  name_muni = "Unit City",
  abbrev_state = "SP",
  year = 2020:2022,
  code_variable = "1.6.1.G",
  raw_response = c("1 km", "NR", "10 m"),
  participated = TRUE,
  review_decision = c("accepted", "unreviewed", "accepted")
)
unit_fixture$review_evidence <- c(
  "Synthetic unit review.",
  NA_character_,
  "Synthetic unit review."
)
unit_candidate <- build_pemob_interpolation_candidates(unit_fixture)
equal_fixture <- data.frame(
  code_muni = 19,
  name_muni = "Equal City",
  abbrev_state = "SP",
  year = 2020:2022,
  code_variable = "3.1.1.A",
  raw_response = c("5", "NR", "5"),
  participated = TRUE,
  review_decision = c("accepted", "unreviewed", "accepted"),
  review_evidence = c(
    "Synthetic fare review.",
    NA_character_,
    "Synthetic fare review."
  )
)
equal_candidate <- build_pemob_interpolation_candidates(equal_fixture)
negative_endpoint_fixture <- equal_fixture
negative_endpoint_fixture$raw_response[1] <- "-1"
negative_endpoint_candidate <- build_pemob_interpolation_candidates(
  negative_endpoint_fixture
)
no_evidence_fixture <- interpolation_fixture[
  interpolation_fixture$code_muni == 10,
]
no_evidence_fixture$review_evidence[3] <- NA_character_
no_evidence_candidate <- build_pemob_interpolation_candidates(
  no_evidence_fixture
)
stopifnot(
  nrow(build_pemob_interpolation_candidates(edge_fixture)) == 0L,
  !unit_candidate$eligible,
  grepl("endpoint_unit_mismatch", unit_candidate$eligibility_reason),
  equal_candidate$eligible,
  equal_candidate$estimate_value == 5,
  !negative_endpoint_candidate$eligible,
  grepl(
    "endpoint_negative",
    negative_endpoint_candidate$eligibility_reason
  ),
  !no_evidence_candidate$eligible,
  grepl(
    "endpoint_evidence_missing",
    no_evidence_candidate$eligibility_reason
  )
)
