# Step 3: filter, join, ratio, exclusions, coordinates.
# Writes one tidy row per practice to data/processed/, plus the exclusions log.

source(here::here("R", "00_settings.R"))
library(tidyverse)
library(janitor)

# TODO: follow the cleaning steps in the action plan
# TODO: add patient-weighted deprivation per practice from the LSOA patients file
#       (primary), alongside the surgery-LSOA decile (secondary)
