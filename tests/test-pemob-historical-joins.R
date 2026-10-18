source(here::here("R", "pemob_helpers.R"))

editions <- list(
  year_2024 = data.frame(code_muni = 2222222, year_2024 = 20),
  year_2019 = data.frame(code_muni = c(1111111, 2222222), year_2019 = c(10, 20))
)
joined <- join_pemob_editions(editions, by = "code_muni")

stopifnot(
  nrow(joined) == 2L,
  setequal(joined$code_muni, c(1111111, 2222222)),
  joined$year_2019[joined$code_muni == 1111111] == 10
)

participation <- build_pemob_participation(editions, by = "code_muni")
stopifnot(
  nrow(participation) == 3L,
  participation$participated[
    participation$code_muni == 1111111 & participation$year == 2019
  ],
  !any(
    participation$code_muni == 1111111 & participation$year == 2024
  )
)

duplicate_column_editions <- list(
  year_2019 = data.frame(
    code_muni = c(1111111, 2222222),
    answer = 1:2,
    answer = 3:4,
    check.names = FALSE
  )
)
duplicate_name_participation <- build_pemob_participation(
  duplicate_column_editions,
  by = "code_muni"
)
stopifnot(
  nrow(duplicate_name_participation) == 2L,
  all(duplicate_name_participation$participated)
)

dimension <- build_pemob_municipality_dimension(list(
  year_2024 = data.frame(
    code_muni = c(1111111, 2222222),
    name_muni = c("Current name", "Older only"),
    abbrev_state = c("SP", "RJ")
  ),
  year_2019 = data.frame(
    code_muni = c(1111111, 3333333),
    name_muni = c("Old name", "Another older municipality"),
    abbrev_state = c("SP", "MG")
  )
))
stopifnot(
  nrow(dimension) == 3L,
  dimension$name_muni[dimension$code_muni == 1111111] == "Current name",
  dimension$abbrev_state[dimension$code_muni == 3333333] == "MG"
)

municipal_source <- data.frame(
  code_muni = c(1111111, 1, NA, 2222222),
  name_muni = c("Respondent", "Footer note", "Missing code", NA_character_),
  value = 1:4
)
respondents <- filter_pemob_municipal_respondents(municipal_source)

stopifnot(
  nrow(respondents) == 1L,
  respondents$code_muni == 1111111,
  respondents$name_muni == "Respondent"
)
