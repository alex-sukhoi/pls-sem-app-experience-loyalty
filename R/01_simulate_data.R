# =============================================================================
# 01_simulate_data.R
# Synthetic survey of 220 users of a service provider's mobile app.
# Constructs (7-point Likert):
#   UX    user experience with the app      (4 items)
#   SAT   satisfaction with the provider    (3 items)
#   TRUST trust in the provider             (3 items)
#   LOY   loyalty / intention to stay       (3 items)
# The effect of UX on trust is stronger for frequent users, so the
# multigroup analysis (PLS-MGA) has a real difference to detect.
# =============================================================================

suppressPackageStartupMessages(library(lavaan))
set.seed(1907)
RNGkind(sample.kind = "Rejection")

make_group <- function(n, ux_trust) {
  m <- sprintf('
    UX    =~ 0.82*ux1 + 0.80*ux2 + 0.78*ux3 + 0.74*ux4
    SAT   =~ 0.78*sat1 + 0.74*sat2 + 0.70*sat3
    TRUST =~ 0.84*tr1 + 0.81*tr2 + 0.77*tr3
    LOY   =~ 0.85*loy1 + 0.82*loy2 + 0.75*loy3
    SAT   ~ 0.55*UX
    TRUST ~ %.2f*UX + 0.35*SAT
    LOY   ~ 0.45*TRUST + 0.25*SAT
  ', ux_trust)
  simulateData(m, sample.nobs = n, standardized = TRUE)
}
to7 <- function(x) cut(x, c(-Inf, -1.8, -1.0, -0.35, 0.3, 0.95, 1.7, Inf), labels = FALSE)

frequent   <- make_group(120, ux_trust = 0.55)   # daily / weekly users
occasional <- make_group(100, ux_trust = -0.05)   # monthly or less
dat <- rbind(frequent, occasional)
dat <- as.data.frame(lapply(dat, to7))
dat$usage  <- rep(c("frequent", "occasional"), c(120, 100))
dat$gender <- sample(c("female", "male"), nrow(dat), replace = TRUE, prob = c(0.55, 0.45))
dat$age_group <- sample(c("18-24", "25-34", "35-44", "45-54", "55+"), nrow(dat), replace = TRUE,
                        prob = c(0.18, 0.30, 0.25, 0.17, 0.10))
dat <- dat[sample(nrow(dat)), ]                   # shuffle rows
dat <- cbind(id = sprintf("U%03d", seq_len(nrow(dat))), dat)

dir.create("data", showWarnings = FALSE)
write.csv(dat, "data/app_user_survey.csv", row.names = FALSE)
cat("Saved data/app_user_survey.csv:", nrow(dat), "respondents\n")
