# Settings shared by every script: paths, area filter, thresholds and colours.
# Change values here, never inside the scripts. Values marked TBD are open
# decisions from the action plan and are settled before the step that needs them.

library(here)

# ---- Paths ------------------------------------------------------------------
paths <- list(
  raw       = here("data", "raw"),
  processed = here("data", "processed"),
  outputs   = here("outputs")
)

raw_files <- list(
  workforce   = "3 General Practice – September 2026 Practice Level - High level.csv",
  definitions = "2 General Practice High-level Practice-Level CSV. Overall Definitions.xlsx",
  patients    = "gp-reg-pat-prac-all.csv",
  practice_map = "gp-reg-pat-prac-map.csv",
  patients_lsoa = "gp-reg-pat-prac-lsoa-all.csv",
  iod         = "IoD 2025 All Ranks Scores.csv",
  lsoa_gpkg   = "LSOA_IMD2025_OSGB1936.gpkg",
  onspd       = "ONSPD_AUG_2026.zip"
)

# Inputs fetched by 01_download.R. Both are ArcGIS Online items; the item id is
# the stable reference, the URL is how the file is fetched today.
downloads <- list(
  lsoa_gpkg = list(
    file    = raw_files$lsoa_gpkg,
    item_id = "4da63019f25546aa92a922a5ea682950", # MHCLG, LSOAs IMD2025 (OSGB1936)
    url     = "https://hub.arcgis.com/api/download/v1/items/4da63019f25546aa92a922a5ea682950/geoPackage?redirect=false&layers=0",
    release = "IoD 2025, item last modified 30 October 2025"
  ),
  onspd = list(
    file    = raw_files$onspd,
    item_id = "9e5a92a3cfb14dc7ad43d6ea7a7b8c7f", # ONS Postcode Directory (August 2026)
    url     = "https://www.arcgis.com/sharing/rest/content/items/9e5a92a3cfb14dc7ad43d6ea7a7b8c7f/data",
    release = "August 2026"
  )
)

# ---- Area filter ------------------------------------------------------------
icb_code <- "QOP" # NHS Greater Manchester ICB

boroughs <- c(
  E08000001 = "Bolton",   E08000002 = "Bury",     E08000003 = "Manchester",
  E08000004 = "Oldham",   E08000005 = "Rochdale", E08000006 = "Salford",
  E08000007 = "Stockport", E08000008 = "Tameside", E08000009 = "Trafford",
  E08000010 = "Wigan"
)

# ---- Workforce definition ---------------------------------------------------
# Roles summed into "qualified GP FTE". Trainees, locums and Retainers are left
# out (Retainer excluded by decision, 26 Oct 2026), so this is narrower than
# NHS England's "fully qualified GPs" headline figure.
qualified_gp_roles <- c(
  "Partner/Provider", "Senior Partner",
  "Salaried By Practice", "Salaried By Other"
)

# All GP counts use FTE, never headcount: headcount summed across roles can count
# one person twice.
gp_measure <- "FTE"

# ---- Exclusions -------------------------------------------------------------
# Each excluded practice is written to the exclusions log with its reason.
min_list_size   <- 1000 # practices with fewer registered patients are excluded
max_patients_gp <- 6000 # hard cap (decision, 26 Oct 2026); zero qualified FTE also excluded

# ---- Practice deprivation ---------------------------------------------------
# Callout facts use patient-weighted deprivation: the IMD of the LSOAs where a
# practice's registered patients live (gp-reg-pat-prac-lsoa-all.csv). The decile
# of the LSOA the surgery sits in is kept as a secondary column for comparison
# (decision, 26 Oct 2026).
practice_deprivation <- "patient_weighted"
# Mean national IMD rank of a practice's patients, mapped to national quintiles
# (rank cut-offs at fifths of all English LSOAs). Majority quintile was rejected:
# 184 of 378 practices have no quintile holding half their patients.
patient_weighted_method <- "mean_rank_quintile"

# ---- Colours ----------------------------------------------------------------
deprivation_greys <- c("#f7f7f7", "#d9d9d9", "#bdbdbd", "#969696", "#737373")
band_colours <- c(
  busiest    = "#D55E00", # Okabe-Ito vermilion
  typical    = "#ffffff",
  least_busy = "#0072B2"  # Okabe-Ito blue
)
outline_colour <- "#4d4d4d"

# ---- Footer -----------------------------------------------------------------
# Snapshot dates differ by a day (workforce moved to the September release,
# 26 Oct 2026); both are stated on the panel. Practices that merged or closed in between show up as join
# failures in 02_clean.R.
snapshot_dates <- c(
  workforce = "30 September 2026",
  patients  = "1 October 2026",
  iod       = "IoD 2025 (published 17 November 2025)"
)
# Exclusions line: counts are filled from the exclusions log, never typed in.
footer_exclusions <- function(n_total, n_capacity, n_data) {
  sprintf(
    "%d of %d practices are not shown: %d with no qualified GP or more than %s patients per GP, and %d with incomplete data.",
    n_capacity + n_data, n_total, n_capacity,
    format(max_patients_gp, big.mark = ","), n_data
  )
}

footer_dates <- sprintf(
  "GPs at %s; registered patients at %s; deprivation: %s.",
  snapshot_dates[["workforce"]], snapshot_dates[["patients"]], snapshot_dates[["iod"]]
)

# ---- Print ------------------------------------------------------------------
print_size_mm <- c(width = 594, height = 841) # A1 portrait
print_dpi     <- 300
