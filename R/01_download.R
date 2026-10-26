# Step 2: fetch each input and record its release date.
# The NHS and IoD files are already in data/raw; this script checks them against
# the checksums in data/raw/MANIFEST.md and fetches the inputs still missing.

source(here::here("R", "00_settings.R"))

# TODO: verify checksums of existing raw files
# TODO: download the IoD 2025 LSOA geopackage (MHCLG) for the base layer;
#       check its geometry detail and that its LSOA codes match the IoD CSV.
#       Borough outlines are dissolved from it in 02_clean.R, not downloaded.
# TODO: download the ONS Postcode Directory and take coordinates, LSOA 2021 and
#       local authority code for each practice postcode (offline lookup)
