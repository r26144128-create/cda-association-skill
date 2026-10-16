# Plots built from a cda_result, shared by the website, slides and Skill.

# Conditional distribution of y within each level of x (§2.1), as 100% stacked bars.
plot_conditional_props <- function(result) {
  v <- result$notes$variables
  props <- as.data.frame(result$tables$row_proportions, responseName = "prop")
  names(props)[1:2] <- c("x", "y")
  ggplot2::ggplot(props, ggplot2::aes(x = x, y = prop, fill = y)) +
    ggplot2::geom_col(width = 0.65, colour = "white") +
    ggplot2::geom_text(ggplot2::aes(label = scales::percent(prop, accuracy = 1)),
                       position = ggplot2::position_stack(vjust = 0.5), colour = "white", size = 4) +
    ggplot2::scale_y_continuous(labels = scales::percent) +
    ggplot2::scale_fill_brewer(palette = "Set2") +
    ggplot2::labs(x = v$x, y = paste0("各組內 ", v$y, " 的比例"), fill = v$y) +
    ggplot2::theme_minimal(base_size = 13)
}

# Standardized residuals (§2.4.5): which cells drive the association. |value| > 2 is notable.
plot_residuals <- function(result) {
  v <- result$notes$variables
  res <- as.data.frame(result$tables$standardized_residuals, responseName = "residual")
  names(res)[1:2] <- c("x", "y")
  lim <- max(3, abs(res$residual))
  ggplot2::ggplot(res, ggplot2::aes(x = y, y = x, fill = residual)) +
    ggplot2::geom_tile(colour = "white") +
    ggplot2::geom_text(ggplot2::aes(label = formatC(residual, digits = 2, format = "f"),
                                    fontface = ifelse(abs(residual) > 2, "bold", "plain")), size = 5) +
    ggplot2::scale_fill_gradient2(low = "#2166ac", mid = "white", high = "#b2182b",
                                  limits = c(-lim, lim)) +
    ggplot2::labs(x = v$y, y = v$x, fill = "標準化殘差") +
    ggplot2::theme_minimal(base_size = 13) +
    ggplot2::theme(panel.grid = ggplot2::element_blank())
}

# Trend (§2.5): proportion of "success" across ordered x categories for an r x 2 table;
# for larger tables fall back to the conditional distributions.
plot_trend <- function(result) {
  v <- result$notes$variables
  tab <- result$tables$counts
  if (ncol(tab) != 2) return(plot_conditional_props(result))
  s <- colnames(tab)[result$notes$scores$y == 1]
  d <- data.frame(x = factor(rownames(tab), levels = rownames(tab)),
                  prop = tab[, s] / rowSums(tab), n = rowSums(tab))
  ggplot2::ggplot(d, ggplot2::aes(x = x, y = prop, group = 1)) +
    ggplot2::geom_line(colour = "grey60") +
    ggplot2::geom_point(ggplot2::aes(size = n), colour = "#1f3a5f") +
    ggplot2::geom_text(ggplot2::aes(label = scales::percent(prop, accuracy = 0.01)), vjust = -1.2, size = 4) +
    ggplot2::scale_y_continuous(labels = scales::percent, expand = ggplot2::expansion(mult = c(0.05, 0.25))) +
    ggplot2::scale_size(range = c(2.5, 8), guide = "none") +
    ggplot2::labs(x = v$x, y = paste0("「", s, "」的比例")) +
    ggplot2::theme_minimal(base_size = 13)
}

# Three-way table (§2.7, cf. Figure 2.5): success proportion by x within each stratum of z,
# next to the marginal comparison that ignores z. Makes Simpson's paradox visible.
plot_stratified <- function(result) {
  v <- result$notes$variables
  st <- result$tables$strata
  xl <- levels(result$tables$partial_tables[[v$x]])
  d <- rbind(data.frame(panel = st$stratum, x = xl[1], prop = st$p1),
             data.frame(panel = st$stratum, x = xl[2], prop = st$p2))
  d$panel <- factor(ifelse(d$panel == utils::tail(st$stratum, 1), d$panel, paste0(v$z, " = ", d$panel)),
                    levels = c(paste0(v$z, " = ", utils::head(st$stratum, -1)), utils::tail(st$stratum, 1)))
  d$x <- factor(d$x, levels = xl)
  ggplot2::ggplot(d, ggplot2::aes(x = x, y = prop, fill = x)) +
    ggplot2::geom_col(width = 0.6) +
    ggplot2::geom_text(ggplot2::aes(label = scales::percent(prop, accuracy = 0.1)), vjust = -0.4, size = 4) +
    ggplot2::facet_wrap(~ panel, nrow = 1) +
    ggplot2::scale_y_continuous(labels = scales::percent, expand = ggplot2::expansion(mult = c(0, 0.15))) +
    ggplot2::scale_fill_manual(values = c("#1f3a5f", "#e07b39"), guide = "none") +
    ggplot2::labs(x = v$x, y = paste0("「", result$notes$success, "」的比例")) +
    ggplot2::theme_minimal(base_size = 13)
}

# The plots that belong to each analysis, keyed by file name.
cda_plots <- function(result) {
  switch(result$method,
    crosstab = list(conditional_props = plot_conditional_props(result),
                    residuals = plot_residuals(result)),
    trend = list(trend = plot_trend(result)),
    stratified = list(stratified = plot_stratified(result)),
    list())
}
