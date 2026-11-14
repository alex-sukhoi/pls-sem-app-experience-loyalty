# =============================================================================
# 02_pls_sem.R
# PLS-SEM following Hair et al. (2021), "PLS-SEM using R":
#   A. Common-method bias (Harman, full collinearity VIF)
#   B. Measurement model: indicator reliability, internal consistency,
#      convergent validity (AVE), discriminant validity (Fornell-Larcker, HTMT)
#   C. Structural model: collinearity (VIF), path coefficients with
#      bootstrapped CIs, R2, f2, out-of-sample prediction (PLSpredict)
#   D. Mediation (specific indirect effects)
#   E. Moderation by usage frequency: multigroup analysis (PLS-MGA)
# =============================================================================

suppressPackageStartupMessages({ library(seminr); library(psych); library(ggplot2) })
dir.create("results", showWarnings = FALSE); dir.create("figures", showWarnings = FALSE)
dat <- read.csv("data/app_user_survey.csv")
r3 <- function(x) round(x, 3)
save <- function(x, f) write.csv(x, file.path("results", f), row.names = TRUE)

mm <- constructs(
  composite("UX",    multi_items("ux", 1:4)),
  composite("SAT",   multi_items("sat", 1:3)),
  composite("TRUST", multi_items("tr", 1:3)),
  composite("LOY",   multi_items("loy", 1:3))
)
sm <- relationships(
  paths(from = "UX",    to = c("SAT", "TRUST")),
  paths(from = "SAT",   to = c("TRUST", "LOY")),
  paths(from = "TRUST", to = "LOY")
)
items <- unlist(lapply(c("ux", "sat", "tr", "loy"), function(p) grep(paste0("^", p, "\\d"), names(dat), value = TRUE)))

pls  <- estimate_pls(data = dat, measurement_model = mm, structural_model = sm)
boot <- bootstrap_model(pls, nboot = 1000, seed = 2026)
s    <- summary(pls)
sb   <- summary(boot)

# --- A. Common-method bias ---------------------------------------------------
harman <- psych::fa(dat[, items], nfactors = 1, rotate = "none", fm = "ml")$Vaccounted[2, 1]
scores <- as.data.frame(pls$construct_scores)
vif_fc <- sapply(names(scores), function(v)
  1 / (1 - summary(lm(scores[[v]] ~ ., data = scores[, setdiff(names(scores), v)]))$r.squared))
cmb <- data.frame(check = c("Harman single factor variance (< 0.50)",
                            paste("Full collinearity VIF", names(vif_fc), "(< 3.3)")),
                  value = r3(c(harman, vif_fc)))
write.csv(cmb, "results/01_common_method_bias.csv", row.names = FALSE)

# --- B. Measurement model ----------------------------------------------------
save(r3(s$loadings), "02_outer_loadings.csv")
save(r3(s$reliability), "03_reliability_alpha_rhoC_AVE_rhoA.csv")
save(r3(s$validity$fl_criteria), "04_fornell_larcker.csv")
save(r3(s$validity$htmt), "05_htmt.csv")
save(r3(sb$bootstrapped_HTMT), "05b_htmt_bootstrap_ci.csv")

# --- C. Structural model -----------------------------------------------------
save(r3(sb$bootstrapped_paths), "06_path_coefficients_bootstrap.csv")
save(r3(s$paths), "07_r_squared.csv")
save(r3(s$fSquare), "08_f_squared.csv")
vif_inner <- do.call(rbind, lapply(names(s$vif_antecedents), function(n)
  data.frame(outcome = n, predictor = names(s$vif_antecedents[[n]]), VIF = r3(unname(s$vif_antecedents[[n]])))))
write.csv(vif_inner, "results/09_inner_vif.csv", row.names = FALSE)

set.seed(2026)
pred <- predict_pls(model = pls, technique = predict_DA, noFolds = 10, reps = 10)
ps <- summary(pred)
pls_rmse <- ps$PLS_out_of_sample["RMSE", ]
lm_rmse  <- ps$LM_out_of_sample["RMSE", ]
plspredict <- data.frame(indicator = names(pls_rmse), PLS_RMSE = r3(pls_rmse), LM_RMSE = r3(lm_rmse),
                         PLS_better = pls_rmse < lm_rmse)
write.csv(plspredict, "results/10_plspredict.csv", row.names = FALSE)

# --- D. Mediation ------------------------------------------------------------
ind <- function(from, through, to) {
  e <- specific_effect_significance(boot, from = from, through = through, to = to, alpha = 0.05)
  data.frame(path = paste(c(from, through, to), collapse = " -> "),
             estimate = r3(e[1, "Original Est."]), ci_low = r3(e[1, "2.5% CI"]), ci_high = r3(e[1, "97.5% CI"]))
}
mediation <- rbind(ind("UX", "SAT", "TRUST"), ind("SAT", "TRUST", "LOY"),
                   ind("UX", c("SAT", "TRUST"), "LOY"), ind("UX", "TRUST", "LOY"))
write.csv(mediation, "results/11_indirect_effects.csv", row.names = FALSE)

# --- E. Multigroup analysis by usage frequency ---------------------------------
mga <- estimate_pls_mga(pls, dat$usage == "frequent", nboot = 1000, seed = 2026)
mga_tab <- data.frame(path = paste(mga$source, "->", mga$target),
                      frequent = r3(mga$group1_beta), occasional = r3(mga$group2_beta),
                      difference = r3(mga$group1_beta - mga$group2_beta),
                      # seminr reports a one-sided PLS-MGA p; convert to two-sided
                      p_value = r3(2 * pmin(mga$pls_mga_p, 1 - mga$pls_mga_p)))
write.csv(mga_tab, "results/12_mga_usage_frequency.csv", row.names = FALSE)

# --- Console summary -----------------------------------------------------------
cat("\nCMB:\n"); print(cmb, row.names = FALSE)
cat("\nReliability:\n"); print(r3(s$reliability))
cat("\nLoadings range:", paste(range(r3(s$loadings[s$loadings > 0])), collapse = " - "), "\n")
cat("\nHTMT:\n"); print(r3(s$validity$htmt))
cat("\nPaths:\n"); print(r3(sb$bootstrapped_paths))
cat("\nR2:\n"); print(r3(s$paths))
cat("\nf2:\n"); print(r3(s$fSquare))
cat("\nPLSpredict: PLS beats LM benchmark on", sum(plspredict$PLS_better), "of", nrow(plspredict), "indicators\n")
cat("\nIndirect effects:\n"); print(mediation, row.names = FALSE)
cat("\nMGA:\n"); print(mga_tab, row.names = FALSE)

# --- Figures -----------------------------------------------------------------
bp <- as.data.frame(sb$bootstrapped_paths)
bp$from <- sub("  ->.*", "", rownames(bp)); bp$to <- sub(".*->  ", "", rownames(bp))
pos <- data.frame(node = c("UX", "SAT", "TRUST", "LOY"), x = c(0, 1, 1, 2), y = c(0, 0.8, -0.8, 0))
r2 <- s$paths["R^2", ]
pos$label <- ifelse(pos$node %in% names(r2), sprintf("%s\nR2 = %.2f", pos$node, r2[pos$node]), pos$node)
bp <- merge(merge(bp, setNames(pos[, 1:3], c("from", "x", "y"))), setNames(pos[, 1:3], c("to", "xend", "yend")))
shrink <- function(a, b, k = 0.2) a + (b - a) * k
bp$sig <- bp[["2.5% CI"]] * bp[["97.5% CI"]] > 0
g <- ggplot() +
  geom_segment(data = bp, aes(x = shrink(x, xend), y = shrink(y, yend), xend = shrink(xend, x), yend = shrink(yend, y),
                              linewidth = abs(`Original Est.`), linetype = sig),
               colour = "#2b6cb0", arrow = arrow(length = unit(3, "mm"), type = "closed")) +
  geom_label(data = bp, aes((x + xend) / 2, (y + yend) / 2,
                            label = sprintf("%.2f%s", `Original Est.`, ifelse(sig, "*", ""))), size = 4) +
  geom_point(data = pos, aes(x, y), size = 30, shape = 21, fill = "#e8f1fb", colour = "#2b6cb0") +
  geom_text(data = pos, aes(x, y, label = label), size = 4) +
  scale_linewidth(range = c(0.5, 2), guide = "none") +
  scale_linetype_manual(values = c(`TRUE` = "solid", `FALSE` = "dashed"), guide = "none") +
  coord_cartesian(xlim = c(-0.35, 2.35), ylim = c(-1.15, 1.15)) +
  labs(title = "PLS-SEM structural model", subtitle = "Path coefficients (* = 95% bootstrap CI excludes 0)") +
  theme_void(base_size = 13)
ggsave("figures/structural_model.png", g, width = 8, height = 5, dpi = 110)

ml <- rbind(data.frame(path = mga_tab$path, group = "Frequent users", beta = mga_tab$frequent),
            data.frame(path = mga_tab$path, group = "Occasional users", beta = mga_tab$occasional))
ml$path <- factor(ml$path, levels = rev(mga_tab$path))
g2 <- ggplot(ml, aes(beta, path, fill = group)) +
  geom_col(position = position_dodge(0.7), width = 0.65) +
  geom_text(data = mga_tab, inherit.aes = FALSE,
            aes(x = pmax(frequent, occasional) + 0.06, y = path, label = sprintf("p = %.3f", p_value)), size = 3.6) +
  scale_fill_manual(values = c("#2b6cb0", "#a3bffa")) +
  labs(title = "Multigroup analysis: frequent vs occasional users",
       subtitle = "Two-sided PLS-MGA p-values for the difference in each path", x = "Path coefficient", y = NULL, fill = NULL) +
  theme_minimal(base_size = 12) + theme(legend.position = "top")
ggsave("figures/mga_usage_frequency.png", g2, width = 8, height = 4.5, dpi = 110)
