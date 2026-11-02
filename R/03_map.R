# Steps 5 to 7: build the map, add annotations, export the A1 PDF and a preview PNG.
# The map is drawn at true A1 size; the sheet adds the headline, how-to-read
# line, legends, numbered callouts and footer around it. ggplot2 and grid are
# used rather than tmap because they set dot sizes in mm and text in points
# exactly, which the print specification needs.
# Ancoats anchor (star linking to the 1851 street scene) is deferred until the
# link target is decided.

source(here::here("R", "00_settings.R"))
source(here::here("R", "callout_facts.R"))
library(tidyverse)
library(sf)
library(grid)

lsoa <- st_read(file.path(paths$processed, "lsoa_gm.gpkg"), quiet = TRUE)
boroughs_sf <- st_read(file.path(paths$processed, "boroughs.gpkg"), quiet = TRUE)
practices <- read_csv(file.path(paths$processed, "practices.csv"), show_col_types = FALSE) |>
  filter(kept)
facts <- callout_facts(practices)
exclusions_log <- read_csv(file.path(paths$processed, "exclusions_log.csv"), show_col_types = FALSE)

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
  mutate(
    band = factor(band, dot_spec$band),
    size_group = cut(patients, size_breaks, names(dot_size_mm), right = FALSE)
  ) |>
  # Large dots first, small ones on top so they are never hidden; within a
  # size, busiest last.
  arrange(desc(size_group), band)

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
    theme_void(base_size = 24, base_family = font_family) +
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
    bg.colour = "white", bg.r = 0.12, fontface = "bold", family = font_family,
    nudge_y = 1800
  )
}

# Colour by busy band, diameter by practice size.
map_final <- base_map() +
  ggnewscale::new_scale_fill() +
  geom_point(data = practices,
             aes(x, y, fill = band, size = size_group, colour = band),
             shape = 21, stroke = 0.9) +
  scale_fill_manual(values = set_names(dot_spec$fill, dot_spec$band),
                    labels = c("Least busy quarter", "Typical", "Busiest quarter of practices"),
                    name = "Patients per GP",
                    guide = guide_legend(order = 1, override.aes = list(
                      size = dot_size_mm[["medium"]], colour = dot_spec$outline, stroke = 0.9))) +
  scale_colour_manual(values = set_names(dot_spec$outline, dot_spec$band), guide = "none") +
  scale_size_manual(values = dot_size_mm, labels = size_labels,
                    name = "Practice size (registered patients)",
                    guide = guide_legend(order = 2, override.aes = list(
                      fill = "white", colour = band_colours[["busiest"]], stroke = 0.9))) +
  borough_labels()

# ---- Callout markers -------------------------------------------------------------
# A numbered circle sits off each cluster, joined to its centre by a short line.
markers <- facts$clusters |>
  left_join(callout_marker_offset_m, by = "id") |>
  mutate(mx = x + dx, my = y + dy)

map_sheet <- map_final +
  geom_segment(data = markers, aes(x = mx, y = my, xend = x, yend = y),
               linewidth = 1, colour = text_colour) +
  geom_point(data = markers, aes(x, y), shape = 21, size = 3, fill = text_colour,
             colour = "white", stroke = 0.6) +
  geom_point(data = markers, aes(mx, my), shape = 21, size = callout_marker_mm,
             fill = "white", colour = text_colour, stroke = 1.6) +
  geom_text(data = markers, aes(mx, my, label = id), size = text_pt[["callout_title"]] / .pt,
            fontface = "bold", family = font_family, colour = text_colour)

# ---- Sheet ---------------------------------------------------------------------------
# Everything is placed in mm from the sheet's top-left corner.
W <- print_size_mm[["width"]]; H <- print_size_mm[["height"]]; M <- page_margin_mm
at <- \(top_mm) unit(H - top_mm, "mm")

text_box <- function(text, top_mm, left_mm, width_mm, pt, face = "plain", lineheight = 1.15) {
  gridtext::textbox_grob(
    text, x = unit(left_mm, "mm"), y = at(top_mm), width = unit(width_mm, "mm"),
    hjust = 0, vjust = 1, halign = 0, valign = 1,
    gp = gpar(fontsize = pt, fontface = face, fontfamily = font_family,
              col = text_colour, lineheight = lineheight)
  )
}

legends_of <- function(plot) {
  g <- ggplotGrob(plot + theme(legend.text = element_text(size = text_pt[["legend"]]),
                               legend.title = element_text(size = text_pt[["legend"]] + 2, face = "bold")))
  g$grobs[[which(startsWith(g$layout$name, "guide-box-bottom"))]]
}

draw_sheet <- function() {
  grid.newpage()
  grid.rect(gp = gpar(fill = "white", col = NA))

  # Headline on one line: the largest size up to text_pt that fits the width.
  r <- sheet_rows_mm
  headline_gp <- \(pt) gpar(fontsize = pt, fontface = "bold", fontfamily = font_family)
  width_at_max <- convertWidth(grobWidth(textGrob(panel_headline, gp = headline_gp(text_pt[["headline"]]))),
                               "mm", valueOnly = TRUE)
  headline_pt <- floor(min(text_pt[["headline"]], text_pt[["headline"]] * (W - 2 * M) / width_at_max))
  if (headline_pt < headline_min_pt) warning("Headline only fits at ", headline_pt, " pt")
  message("Headline set at ", headline_pt, " pt")
  writeLines(as.character(headline_pt), file.path(paths$outputs, "headline_pt.txt"))
  headline_mm <- headline_pt * 0.3528
  grid.text(panel_headline, x = unit(M, "mm"), y = at(r[["headline_top"]]), just = c("left", "top"),
            gp = headline_gp(headline_pt))

  # Subheadline and how-to-read line stack under it; the map must start below.
  sub <- text_box(sprintf(panel_subheadline, facts$headline$pct_small_busy,
                          facts$headline$pct_large_busy),
                  r[["headline_top"]] + headline_mm + 10, M, W - 2 * M, text_pt[["subheadline"]])
  sub_bottom <- r[["headline_top"]] + headline_mm + 10 + convertHeight(grobHeight(sub), "mm", valueOnly = TRUE)
  how <- text_box(panel_how_to_read, sub_bottom + 8, M, W - 2 * M, text_pt[["how_to_read"]])
  how_bottom <- sub_bottom + 8 + convertHeight(grobHeight(how), "mm", valueOnly = TRUE)
  if (how_bottom + 8 > r[["map_top"]]) warning("Intro text runs into the map by ", round(how_bottom + 8 - r[["map_top"]]), " mm")
  grid.draw(sub)
  grid.draw(how)

  # Map at its exact print size.
  pushViewport(viewport(x = unit(M, "mm"), y = at(r[["map_top"]]), just = c("left", "top"),
                        width = unit(map_width_mm, "mm"), height = unit(map_height_mm, "mm")))
  grid.draw(ggplotGrob(map_sheet + theme(legend.position = "none",
                                          plot.margin = margin(0, 0, 0, 0))))
  popViewport()

  # Legends in a row under the map.
  pushViewport(viewport(x = unit(M, "mm"), y = at(r[["legend_top"]]), just = c("left", "top"),
                        width = unit(W - 2 * M, "mm"), height = unit(r[["callout_top"]] - r[["legend_top"]], "mm")))
  grid.draw(legends_of(map_final + theme(legend.justification = c(0, 1))))
  popViewport()

  # Numbered callouts in three columns.
  col_w <- (W - 2 * M - 2 * 12) / 3
  for (i in seq_len(nrow(facts$clusters))) {
    left <- M + (i - 1) * (col_w + 12)
    top <- r[["callout_top"]]
    grid.circle(x = unit(left + callout_marker_mm / 2, "mm"), y = at(top + callout_marker_mm / 2),
                r = unit(callout_marker_mm / 2, "mm"),
                gp = gpar(fill = "white", col = text_colour, lwd = 4.5))
    grid.text(i, x = unit(left + callout_marker_mm / 2, "mm"), y = at(top + callout_marker_mm / 2),
              gp = gpar(fontsize = text_pt[["callout_title"]], fontface = "bold",
                        fontfamily = font_family, col = text_colour))
    grid.draw(text_box(facts$clusters$title[i], top + 1, left + callout_marker_mm + 5,
                       col_w - callout_marker_mm - 5, text_pt[["callout_title"]], "bold"))
    grid.draw(text_box(facts$clusters$body[i], top + callout_marker_mm + 6, left, col_w,
                       text_pt[["callout_body"]]))
  }

  # Footer: method, exclusions, sources and dates in small type.
  n_capacity <- sum(exclusions_log$exclusion_type == "capacity")
  n_data <- sum(exclusions_log$exclusion_type == "data")
  footer <- paste(
    panel_method,
    footer_exclusions(nrow(practices) + nrow(exclusions_log), n_capacity, n_data),
    "<br><br>", panel_sources, footer_dates
  )
  grid.lines(x = unit(c(M, W - M), "mm"), y = at(r[["footer_top"]] - 4),
             gp = gpar(col = "#999999", lwd = 1))
  grid.draw(text_box(footer, r[["footer_top"]], M, W - 2 * M, text_pt[["footer"]]))
}

# ---- Blank map -------------------------------------------------------------------------
# Borough outlines and names only: no shading, dots, callouts or text panels.
# The page is cropped to the map at the same scale as the A1 sheet (1:98,000),
# with a small white margin so outlines are not clipped at the edges.
blank_margin_mm <- 10
map_blank <- ggplot() +
  geom_sf(data = boroughs_sf, fill = "white", colour = outline_colour, linewidth = 0.5) +
  coord_sf(crs = crs_bng, datum = NA, expand = FALSE,
           xlim = bbox[c("xmin", "xmax")], ylim = bbox[c("ymin", "ymax")]) +
  theme_void(base_family = font_family) +
  theme(plot.margin = margin(blank_margin_mm, blank_margin_mm, blank_margin_mm,
                             blank_margin_mm, unit = "mm")) +
  borough_labels()
blank_size_mm <- c(map_width_mm, map_height_mm) + 2 * blank_margin_mm

# ---- Export ------------------------------------------------------------------------
# The macOS Quartz device draws system fonts such as Georgia and embeds them
# in the PDF, which printers need. R's pdf() device can only use its own fonts.
quartz(type = "pdf", file = file.path(paths$outputs, "gp-map-a1.pdf"),
       width = W / 25.4, height = H / 25.4, bg = "white")
draw_sheet()
invisible(dev.off())
quartz(type = "png", file = file.path(paths$outputs, "gp-map-a1-preview.png"),
       width = W / 25.4, height = H / 25.4, dpi = 72, bg = "white")
draw_sheet()
invisible(dev.off())
for (type in c("pdf", "png")) {
  file <- file.path(paths$outputs, if (type == "pdf") "gp-map-blank.pdf" else "gp-map-blank-preview.png")
  quartz(type = type, file = file, width = blank_size_mm[1] / 25.4,
         height = blank_size_mm[2] / 25.4, dpi = 72, bg = "white")
  print(map_blank)
  invisible(dev.off())
}
cat("Wrote outputs/gp-map-a1.pdf, outputs/gp-map-blank.pdf and their preview PNGs\n")
