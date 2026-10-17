source("R/pemob_helpers.R")

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
