# Step 3: filter, join, ratio, exclusions, coordinates.
# Reads data/raw without changing it and writes to data/processed/:
#   practices.csv / practices.gpkg  one row per GM practice, kept and excluded
#   exclusions_log.csv              every excluded practice with its reason
#   lsoa_gm.gpkg / boroughs.gpkg    simplified base layer and borough outlines

source(here::here("R", "00_settings.R"))
library(tidyverse)
library(janitor)
library(sf)

raw <- \(name) file.path(paths$raw, raw_files[[name]])
out <- \(name) file.path(paths$processed, name)

# Print rows in, rows out and unmatched codes for a join, as the plan asks.
report_join <- function(label, left, right, by) {
  only_left  <- setdiff(left[[by]], right[[by]])
  only_right <- setdiff(right[[by]], left[[by]])
  cat(sprintf("%s: %d left, %d right, %d matched; %d only left, %d only right\n",
              label, n_distinct(left[[by]]), n_distinct(right[[by]]),
              length(intersect(left[[by]], right[[by]])),
              length(only_left), length(only_right)))
  invisible(list(only_left = only_left, only_right = only_right))
}

# ---- 1. Practices in Greater Manchester -------------------------------------
# The practice map file carries the ICB; list sizes and postcodes come from the
# all-patients file. Both are the 1 October 2026 extract.
practice_map <- read_csv(raw("practice_map"), show_col_types = FALSE) |>
  clean_names() |>
  filter(icb_code == .env$icb_code) |>
  select(prac_code = practice_code, prac_name = practice_name,
         pcn_name, postcode = practice_postcode)

patients <- read_csv(raw("patients"), show_col_types = FALSE) |>
  clean_names() |>
  select(prac_code = code, patients = number_of_patients)

report_join("Practice map x patients", practice_map, patients, "prac_code")
gm <- left_join(practice_map, patients, by = "prac_code")
cat("GM practices:", nrow(gm), "| patients:", format(sum(gm$patients), big.mark = ","), "\n")

# ---- 2. GP FTE by role group -----------------------------------------------
# Long-format workforce file: one row per practice, role and measure. Only FTE
# rows for the GP staff group are used. A practice with no valid GP return has
# "NA" on the Total row and every non-trainee role; trainee rows still read 0
# because they come from a separate source, so NA is judged on the Total row.
# na = character() keeps the literal "NA" the file uses for a missing return.
workforce <- read_csv(raw("workforce"), na = character(),
                      col_types = cols(VALUE = col_character(), .default = col_character())) |>
  clean_names() |>
  filter(staff_group == "GP", measure == gp_measure)

gp_fte <- workforce |>
  mutate(
    role_group = case_when(
      detailed_staff_role == "Total"                 ~ "total",
      detailed_staff_role %in% qualified_gp_roles   ~ "qualified",
      detailed_staff_role == "Retainer"              ~ "retainer",
      str_starts(detailed_staff_role, "Locum")       ~ "locum",
      str_starts(detailed_staff_role, "GP in Training") ~ "trainee",
      .default = "other"
    ),
    value_num = suppressWarnings(as.numeric(value))
  ) |>
  group_by(prac_code) |>
  summarise(
    gp_na         = any(value[role_group == "total"] == "NA"),
    fte_qualified = sum(value_num[role_group == "qualified"], na.rm = TRUE),
    fte_retainer  = sum(value_num[role_group == "retainer"], na.rm = TRUE),
    fte_locum     = sum(value_num[role_group == "locum"], na.rm = TRUE),
    fte_trainee   = sum(value_num[role_group == "trainee"], na.rm = TRUE),
    unmapped_roles = sum(role_group == "other"),
    .groups = "drop"
  ) |>
  # An NA return has no GP figures, not zero GPs.
  mutate(across(starts_with("fte_"), \(x) if_else(gp_na, NA_real_, x)))
stopifnot("A GP role is not assigned to a group" = all(gp_fte$unmapped_roles == 0))

wf_join <- report_join("GM practices x workforce", gm, gp_fte, "prac_code")
gm <- left_join(gm, select(gp_fte, -unmapped_roles), by = "prac_code")

# ---- 2b. Returns unchanged since the prior release ------------------------------
# NWRS keeps a practice's last return until the practice updates it, so a
# return identical in every row to the previous month may be carried forward.
# It is flagged for the notebook, not excluded.
read_wf <- \(name) read_csv(raw(name), na = character(),
                            col_types = cols(.default = col_character())) |>
  clean_names() |>
  filter(prac_code %in% gm$prac_code)
wf_now <- read_wf("workforce")
wf_prev <- read_wf("workforce_prev")
unchanged <- inner_join(wf_prev, wf_now,
                        by = c("prac_code", "staff_group", "detailed_staff_role", "measure"),
                        suffix = c("_prev", "_now")) |>
  group_by(prac_code) |>
  summarise(workforce_unchanged = all(value_prev == value_now), .groups = "drop")
gm <- left_join(gm, unchanged, by = "prac_code")
cat("Workforce returns identical to the prior release:",
    sum(gm$workforce_unchanged, na.rm = TRUE), "of", sum(!is.na(gm$workforce_unchanged)), "\n")

# ---- 3. Patients per GP and exclusions --------------------------------------
# Data-quality reasons come first, so each practice carries one reason only.
gm <- gm |>
  mutate(
    patients_per_gp = if_else(fte_qualified > 0, patients / fte_qualified, NA_real_),
    exclusion = case_when(
      is.na(gp_na)                       ~ "No workforce record",
      gp_na                              ~ "GP staff group recorded as NA",
      patients < min_list_size           ~ sprintf("List under %s patients", format(min_list_size, big.mark = ",")),
      fte_qualified == 0                 ~ "No qualified GP FTE",
      patients_per_gp > max_patients_gp  ~ sprintf("Over %s patients per GP", format(max_patients_gp, big.mark = ",")),
      .default = NA_character_
    ),
    exclusion_type = case_when(
      is.na(exclusion) ~ NA_character_,
      exclusion %in% c("No qualified GP FTE") | str_starts(exclusion, "Over") ~ "capacity",
      .default = "data"
    ),
    kept = is.na(exclusion)
  )

exclusions_log <- gm |>
  filter(!kept) |>
  select(prac_code, prac_name, exclusion_type, exclusion, patients,
         fte_qualified, fte_retainer, fte_locum, fte_trainee, patients_per_gp) |>
  arrange(exclusion_type, desc(patients_per_gp))
print(count(exclusions_log, exclusion_type, exclusion))

# ---- 4. Coordinates, LSOA and borough from the ONS Postcode Directory -------
# Read only the needed columns straight from the zip, and only GM practice
# postcodes. east1m / north1m are already British National Grid metres.
# The archive is zip64 (4.1 GB unpacked), which R's unzip() cannot open, so the
# system unzip streams the one CSV needed.
onspd_csv <- system2("unzip", c("-Z1", shQuote(raw("onspd"))), stdout = TRUE) |>
  str_subset("^Data/ONSPD_.*_UK\\.csv$")
onspd <- read_csv(pipe(paste("unzip -p", shQuote(raw("onspd")), shQuote(onspd_csv))),
                  show_col_types = FALSE,
                  col_select = c(pcds, doterm, east1m, north1m, lsoa21cd, lad26cd),
                  col_types = cols(east1m = col_double(), north1m = col_double(),
                                   .default = col_character())) |>
  mutate(pc_key = str_remove_all(pcds, " ")) |>
  filter(pc_key %in% str_remove_all(gm$postcode, " "))

gm <- gm |>
  mutate(pc_key = str_remove_all(postcode, " ")) |>
  left_join(select(onspd, pc_key, doterm, east = east1m, north = north1m,
                   surgery_lsoa = lsoa21cd, lad_code = lad26cd),
            by = "pc_key") |>
  mutate(borough = unname(boroughs[lad_code]))

cat("Practices without coordinates:", sum(is.na(gm$east)), "\n")
cat("Practice postcodes terminated:", sum(!is.na(gm$doterm)), "\n")
cat("Practices outside the ten boroughs:", sum(is.na(gm$borough)), "\n")

# Several practices can share one health centre; their dots would stack.
gm <- gm |>
  add_count(pc_key, name = "practices_at_site") |>
  select(-pc_key)
cat("Postcodes shared by more than one practice:",
    n_distinct(gm$postcode[gm$practices_at_site > 1]), "\n")

# ---- 5. Deprivation ---------------------------------------------------------
# National IMD ranks for every English LSOA; quintile cut-offs are fifths of all
# LSOAs, so practice groups match the five greys on the base map.
iod <- read_csv(raw("iod"), show_col_types = FALSE) |>
  clean_names() |>
  select(lsoa = lsoa_code_2021, lad_code = local_authority_district_code_2024,
         imd_rank = starts_with("index_of_multiple_deprivation_imd_rank"),
         imd_decile = starts_with("index_of_multiple_deprivation_imd_decile"))
n_lsoa <- nrow(iod)
rank_to_quintile <- \(rank) pmin(5L, as.integer(ceiling(rank / (n_lsoa / 5))))
iod <- mutate(iod, imd_quintile = rank_to_quintile(imd_rank))

# Patient-weighted: mean national IMD rank of the LSOAs a practice's patients
# live in. Patients in Wales, Scotland or with no LSOA ("CLOSED", "NO2011")
# have no English rank and are left out of the mean, but counted.
patients_lsoa <- read_csv(raw("patients_lsoa"), show_col_types = FALSE) |>
  clean_names() |>
  filter(practice_code %in% gm$prac_code) |>
  select(prac_code = practice_code, lsoa = lsoa_code, n = number_of_patients) |>
  left_join(select(iod, lsoa, imd_rank), by = "lsoa")

patient_weighted <- patients_lsoa |>
  group_by(prac_code) |>
  summarise(
    patients_lsoa_total = sum(n),
    patients_unranked = sum(n[is.na(imd_rank)]),
    mean_patient_rank = weighted.mean(imd_rank, n, na.rm = TRUE),
    .groups = "drop"
  ) |>
  mutate(patient_quintile = rank_to_quintile(mean_patient_rank))

report_join("GM practices x patients by LSOA", gm, patient_weighted, "prac_code")
cat(sprintf("Patients without an English LSOA rank: %.2f%%\n",
            100 * sum(patient_weighted$patients_unranked) / sum(patient_weighted$patients_lsoa_total)))

gm <- gm |>
  left_join(patient_weighted, by = "prac_code") |>
  left_join(select(iod, surgery_lsoa = lsoa, surgery_decile = imd_decile,
                   surgery_quintile = imd_quintile),
            by = "surgery_lsoa")

# ---- 6. Colour bands among kept practices ------------------------------------
# Quartiles of patients per GP across kept GM practices only.
cuts <- quantile(gm$patients_per_gp[gm$kept], c(0.25, 0.75), names = FALSE)
gm <- gm |>
  mutate(band = case_when(
    !kept                    ~ NA_character_,
    patients_per_gp >  cuts[2] ~ "busiest",
    patients_per_gp <  cuts[1] ~ "least_busy",
    .default = "typical"
  ))
cat(sprintf("Band cut-offs: least busy < %.0f, busiest > %.0f patients per GP\n", cuts[1], cuts[2]))
print(count(filter(gm, kept), band))

# ---- 7. Base layer and borough outlines --------------------------------------
# The GeoPackage is in Web Mercator: transform to British National Grid, keep
# GM LSOAs, simplify with shared edges preserved, then dissolve boroughs from
# the same simplified LSOAs so outlines and base line up exactly.
lsoa_gm <- st_read(raw("lsoa_gpkg"), quiet = TRUE) |>
  select(lsoa = LSOA21CD) |>
  inner_join(filter(iod, lad_code %in% names(boroughs)), by = "lsoa") |>
  st_transform(crs_bng)
outline_before <- st_boundary(st_union(lsoa_gm))
vertices_before <- nrow(st_coordinates(lsoa_gm))
lsoa_gm <- rmapshaper::ms_simplify(lsoa_gm, keep = simplify_keep, keep_shapes = TRUE)
st_crs(lsoa_gm) <- crs_bng
max_shift <- as.numeric(st_distance(outline_before, st_boundary(st_union(lsoa_gm)),
                                    which = "Hausdorff"))
cat(sprintf("GM LSOAs: %d | vertices %s -> %s | max outline shift %.1f m | invalid %d\n",
            nrow(lsoa_gm), format(vertices_before, big.mark = ","),
            format(nrow(st_coordinates(lsoa_gm)), big.mark = ","),
            max_shift, sum(!st_is_valid(lsoa_gm))))
if (max_shift > simplify_max_m) warning("Simplification moved the outline more than ", simplify_max_m, " m")

boroughs_sf <- lsoa_gm |>
  group_by(lad_code) |>
  summarise(.groups = "drop") |>
  mutate(borough = unname(boroughs[lad_code]))

# Every practice point should sit inside the borough its postcode names.
practices_sf <- gm |>
  filter(!is.na(east)) |>
  st_as_sf(coords = c("east", "north"), crs = crs_bng, remove = FALSE)
in_borough <- st_join(practices_sf, select(boroughs_sf, borough_poly = borough),
                      join = st_within)
cat("Practices whose point and postcode borough disagree:",
    sum(in_borough$borough != in_borough$borough_poly, na.rm = TRUE),
    "| outside every borough polygon:", sum(is.na(in_borough$borough_poly)), "\n")

# ---- 8. Write -----------------------------------------------------------------
practices <- gm |>
  select(prac_code, prac_name, pcn_name, borough, postcode, practices_at_site,
         east, north, patients, fte_qualified, fte_retainer, fte_locum,
         fte_trainee, patients_per_gp, workforce_unchanged, kept, exclusion_type, exclusion, band,
         mean_patient_rank, patient_quintile, surgery_lsoa, surgery_decile,
         surgery_quintile) |>
  arrange(prac_code)

write_csv(practices, out("practices.csv"))
write_csv(exclusions_log, out("exclusions_log.csv"))
st_write(st_as_sf(filter(practices, !is.na(east)), coords = c("east", "north"),
                  crs = crs_bng, remove = FALSE),
         out("practices.gpkg"), delete_dsn = TRUE, quiet = TRUE)
st_write(lsoa_gm, out("lsoa_gm.gpkg"), delete_dsn = TRUE, quiet = TRUE)
st_write(boroughs_sf, out("boroughs.gpkg"), delete_dsn = TRUE, quiet = TRUE)

cat(sprintf("\nWrote %d practices (%d kept, %d excluded) to data/processed/\n",
            nrow(practices), sum(practices$kept), sum(!practices$kept)))
