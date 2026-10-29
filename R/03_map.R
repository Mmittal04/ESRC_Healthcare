# Steps 5 to 7: build the map, add annotations, export the A1 PDF and a preview PNG.
# This draft builds the map itself (base, dots, borough outlines) at true A1
# size, in two dot styles for comparison. Headline, callouts and footer are
# step 6. ggplot2 is used rather than tmap because it sets dot sizes in mm
# and text in points exactly, which the print specification needs.
# Ancoats anchor (star linking to the 1851 street scene) is deferred until the
# link target is decided.

source(here::here("R", "00_settings.R"))
library(tidyverse)
library(sf)

lsoa <- st_read(file.path(paths$processed, "lsoa_gm.gpkg"), quiet = TRUE)
boroughs_sf <- st_read(file.path(paths$processed, "boroughs.gpkg"), quiet = TRUE)
practices <- read_csv(file.path(paths$processed, "practices.csv"), show_col_types = FALSE) |>
  filter(kept)

# ---- Spread practices that share a site ----------------------------------------
# Each practice at a shared postcode moves to an evenly spaced point on a ring
# around the site, so every practice keeps its own visible dot.
practices <- practices |>
  group_by(postcode) |>
  mutate(
    k = row_number(), n_site = n(),
    angle = 2 * pi * (k - 1) / n_site + pi / 2,
    x = east  + if_else(n_site > 1, site_ring_m * cos(angle), 0),
    y = north + if_else(n_site > 1, site_ring_m * sin(angle), 0)
  ) |>
  ungroup() |>
  left_join(dot_spec, by = "band") |>
  mutate(band = factor(band, dot_spec$band)) |>
  # Busiest dots are drawn last so they sit on top.
  arrange(band)

# ---- Scale: fit the map to the sheet width ---------------------------------------
bbox <- st_bbox(boroughs_sf)
map_width_mm <- print_size_mm[["width"]] - 2 * page_margin_mm
metres_per_mm <- (bbox[["xmax"]] - bbox[["xmin"]]) / map_width_mm
map_height_mm <- (bbox[["ymax"]] - bbox[["ymin"]]) / metres_per_mm
cat(sprintf("Map: %.0f x %.0f mm at 1:%s\n", map_width_mm, map_height_mm,
            format(round(metres_per_mm * 1000, -3), big.mark = ",")))

# For shape 21, ggplot's point size is close to the circle's diameter in mm
# (size * .pt points, and .pt points is 1 mm), so diameters are used directly.

# ---- Map layers ------------------------------------------------------------------
quintile_labels <- c("Most deprived fifth of England", "2", "3", "4",
                     "Least deprived fifth of England")

base_map <- function() {
  ggplot() +
    geom_sf(data = lsoa, aes(fill = factor(imd_quintile)), colour = NA) +
    scale_fill_manual(values = deprivation_colours, labels = quintile_labels,
                      name = "Neighbourhood deprivation (IMD 2025)",
                      guide = guide_legend(order = 3)) +
    geom_sf(data = boroughs_sf, fill = NA, colour = outline_colour, linewidth = 0.5) +
    coord_sf(crs = crs_bng, datum = NA, expand = FALSE,
             xlim = bbox[c("xmin", "xmax")], ylim = bbox[c("ymin", "ymax")]) +
    theme_void(base_size = 24) +
    theme(legend.position = "bottom", legend.direction = "vertical",
          legend.title = element_text(face = "bold"),
          legend.title.position = "top",
          legend.spacing.x = unit(25, "mm"),
          legend.key.spacing.y = unit(2, "mm"))
}

# Borough names go on top of the dots, with a white halo so they read over
# dark neighbourhoods and dot clusters.
label_points <- st_point_on_surface(st_geometry(boroughs_sf)) |>
  st_coordinates() |>
  as_tibble() |>
  mutate(borough = toupper(boroughs_sf$borough))
borough_labels <- function() {
  shadowtext::geom_shadowtext(
    data = label_points, aes(X, Y, label = borough),
    size = borough_label_pt / ggplot2::.pt, colour = outline_colour,
    bg.colour = "white", bg.r = 0.12, fontface = "bold", nudge_y = 1800
  )
}

# Plan design: colour and size by band.
map_by_band <- base_map() +
  ggnewscale::new_scale_fill() +
  geom_point(data = practices,
             aes(x, y, fill = band, size = band, colour = band),
             shape = 21, stroke = 0.8) +
  scale_fill_manual(values = set_names(dot_spec$fill, dot_spec$band),
                    labels = c("Least busy quarter", "Typical", "Busiest quarter of practices"),
                    name = "Patients per GP",
                    guide = guide_legend(order = 1, override.aes = list(
                      size = dot_spec$diameter_mm, colour = dot_spec$outline, stroke = 0.8))) +
  scale_colour_manual(values = set_names(dot_spec$outline, dot_spec$band), guide = "none") +
  scale_size_manual(values = set_names(dot_spec$diameter_mm, dot_spec$band),
                    guide = "none") +
  borough_labels()

# Size story: the same dots, with an open ring around small practices.
small <- filter(practices, patients < size_breaks[2])
map_by_band_small <- map_by_band +
  geom_point(data = small, aes(x, y, shape = "small"),
             size = small$diameter_mm + small_ring_extra_mm,
             colour = small_ring_colour, stroke = 1.1) +
  scale_shape_manual(values = c(small = 1),
                     labels = sprintf("Small practice (under %s patients)",
                                      format(size_breaks[2], big.mark = ",")),
                     name = "Practice size",
                     guide = guide_legend(order = 2, override.aes = list(size = 9, stroke = 1.1))) +
  borough_labels()

# ---- Export ------------------------------------------------------------------------
# Drafts are the map alone at its A1 print size; the full sheet is assembled in
# step 6 once the annotations are written.
save_draft <- function(plot, name) {
  w <- map_width_mm; h <- map_height_mm + 120 # room for the legend under the map
  ggsave(file.path(paths$outputs, paste0(name, ".pdf")), plot,
         width = w, height = h, units = "mm", device = "pdf", useDingbats = FALSE)
  ggsave(file.path(paths$outputs, paste0(name, ".png")), plot,
         width = w, height = h, units = "mm", dpi = 72, bg = "white")
}
save_draft(map_by_band, "draft-map-by-band")
save_draft(map_by_band_small, "draft-map-by-band-small")
cat("Wrote draft maps to outputs/\n")
