# Step 2: fetch each input and record its release date.
# The NHS and IoD files are already in data/raw; this script checks them against
# the checksums in data/raw/MANIFEST.md and fetches the inputs still missing.

source(here::here("R", "00_settings.R"))

# TODO: verify checksums of existing raw files
# TODO: download LSOA 2021 boundaries (source TBD)
# TODO: download borough boundaries (source TBD)
# TODO: look up coordinates for practice postcodes (source TBD)
