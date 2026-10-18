source(here::here("R", "pemob_helpers.R"))

scaled <- scale_pemob_max(c(0, 5, 10, NA_real_))
all_zero <- scale_pemob_max(c(0, 0, NA_real_))
constant <- scale_pemob_max(c(5, 5))
all_missing <- scale_pemob_max(c(NA_real_, NA_real_))

stopifnot(
  identical(scaled, c(0, 50, 100, NA_real_)),
  identical(all_zero, c(0, 0, NA_real_)),
  identical(constant, c(100, 100)),
  all(is.na(all_missing))
)
