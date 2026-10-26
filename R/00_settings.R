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
  workforce   = "3 General Practice – August 2026 Practice Level - High level.csv",
  definitions = "2 General Practice High-level Practice-Level CSV. Overall Definitions.xlsx",
  patients    = "gp-reg-pat-prac-all.csv",
  practice_map = "gp-reg-pat-prac-map.csv",
  patients_lsoa = "gp-reg-pat-prac-lsoa-all.csv",
  iod         = "IoD 2025 All Ranks Scores.csv"
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

# ---- Colours ----------------------------------------------------------------
deprivation_greys <- c("#f7f7f7", "#d9d9d9", "#bdbdbd", "#969696", "#737373")
band_colours <- c(
  busiest    = "#D55E00", # Okabe-Ito vermilion
  typical    = "#ffffff",
  least_busy = "#0072B2"  # Okabe-Ito blue
)
outline_colour <- "#4d4d4d"

# ---- Print ------------------------------------------------------------------
print_size_mm <- c(width = 594, height = 841) # A1 portrait
print_dpi     <- 300
