portal_code <- parse("R/pemob_portal_final.R")
metro_code <- parse("R/pemob_metropolitana.R")

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
