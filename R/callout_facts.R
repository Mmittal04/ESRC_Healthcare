# Callout facts shared by gp-map.qmd and 03_map.R, so every number printed on
# the panel is computed once, from data/processed/practices.csv.
# Clusters were chosen on 29 Oct 2026 from the PCNs with the most practices in
# the busiest band, plus Stockport as the contrast.

library(dplyr)

callout_clusters <- tibble::tribble(
  ~id, ~title,             ~filter_by, ~value,
  1,   "Central Bolton",   "pcn",      "BOLTON CENTRAL PCN",
  2,   "North Manchester", "pcn",      "H-BLACKLEY HARPURHEY & CHARLESTOWN PCN",
  3,   "Stockport",        "borough",  "Stockport"
)

# kept: kept practices from practices.csv (band and patient_quintile present).
callout_facts <- function(kept) {
  kept <- mutate(kept,
                 is_small = patients < size_breaks[2],
                 is_large = patients >= size_breaks[3],
                 is_busy  = band == "busiest")

  headline <- list(
    pct_small_busy = round(100 * mean(kept$is_busy[kept$is_small])),
    pct_large_busy = round(100 * mean(kept$is_busy[kept$is_large])),
    n_practices    = nrow(kept)
  )

  clusters <- callout_clusters |>
    rowwise() |>
    mutate(members = list(
      if (filter_by == "pcn") filter(kept, pcn_name == value) else filter(kept, borough == value)
    )) |>
    mutate(
      n         = nrow(members),
      n_small   = sum(members$is_small),
      n_busy    = sum(members$is_busy),
      n_group_1 = sum(members$patient_quintile == 1),
      median_list = median(members$patients),
      x = mean(members$east), y = mean(members$north)
    ) |>
    ungroup() |>
    select(-members)

  c1 <- clusters[1, ]; c2 <- clusters[2, ]; c3 <- clusters[3, ]
  clusters$body <- c(
    sprintf("%d of the %d practices here are small, and %d are in the busiest quarter for patients per GP.",
            c1$n_small, c1$n, c1$n_busy),
    sprintf("%d of the %d practices here are in the busiest quarter. %s serve patients from some of England's most deprived neighbourhoods.",
            c2$n_busy, c2$n,
            if (c2$n_group_1 == c2$n) "All of them" else sprintf("%d of them", c2$n_group_1)),
    sprintf("Practices here tend to be larger, and only %d of Stockport's %d practices are in the busiest quarter.",
            c3$n_busy, c3$n)
  )

  list(headline = headline, clusters = clusters)
}
