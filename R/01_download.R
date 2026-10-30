# Step 2: fetch each input and record its release date.
# The NHS and IoD CSV files were downloaded by hand; this script checks them
# against the checksums in data/raw/MANIFEST.md, fetches the inputs still
# missing, and writes data/raw/download_log.csv. Files already present are not
# fetched again; delete one to refresh it.

source(here::here("R", "00_settings.R"))
library(tidyverse)
library(sf)

sha256_file <- function(path) {
  con <- file(path, "rb")
  on.exit(close(con))
  as.character(openssl::sha256(con))
}

# ---- 1. Check hand-downloaded files against the manifest --------------------
# The manifest is the record of which copy the map was built from; a mismatch
# means a file was replaced and the manifest needs updating.
manifest <- read_lines(file.path(paths$raw, "MANIFEST.md")) |>
  str_subset("^\\| `") |>
  str_match("^\\| `([^`]+)` .*`([0-9a-f]{64})` \\|$") |>
  as_tibble(.name_repair = ~ c("line", "file", "sha256_manifest")) |>
  # Rows of the "Fetched by" table carry no checksum; download_log.csv has them.
  filter(!is.na(file)) |>
  select(-line)

manifest_check <- manifest |>
  mutate(
    present = file.exists(file.path(paths$raw, file)),
    sha256_now = map_chr(file, \(f) {
      p <- file.path(paths$raw, f)
      if (file.exists(p)) sha256_file(p) else NA_character_
    }),
    ok = present & sha256_now == sha256_manifest
  )
print(select(manifest_check, file, present, ok))
if (!all(manifest_check$ok)) {
  stop("Raw files differ from MANIFEST.md: ",
       paste(manifest_check$file[!manifest_check$ok], collapse = ", "))
}

# ---- 2. Fetch the missing inputs --------------------------------------------
# The GeoPackage comes from the ArcGIS Hub export API, which answers with JSON
# naming the file to fetch; ONSPD is a direct item download.
fetch <- function(d) {
  dest <- file.path(paths$raw, d$file)
  if (file.exists(dest)) {
    message("Already present, skipping: ", d$file)
    return(invisible(dest))
  }
  url <- d$url
  if (str_detect(url, "hub.arcgis.com/api/download")) {
    reply <- jsonlite::fromJSON(url)
    if (!identical(reply$status, "Completed")) {
      stop("Hub export not ready (status: ", reply$status, "); run again later")
    }
    url <- reply$resultUrl
  }
  message("Downloading ", d$file, " ...")
  tmp <- paste0(dest, ".part")
  curl::curl_download(url, tmp, quiet = TRUE)
  file.rename(tmp, dest)
  invisible(dest)
}

options(timeout = 3600)
walk(downloads, fetch)

# ---- 3. Check what arrived ---------------------------------------------------
# LSOA layer: every English LSOA present, codes match the IoD CSV, British
# National Grid, and how detailed the boundaries are.
lsoa <- st_read(file.path(paths$raw, raw_files$lsoa_gpkg), quiet = TRUE)
iod <- read_csv(file.path(paths$raw, raw_files$iod),
                col_select = c(lsoa = 1, lad = 3), show_col_types = FALSE)

cat("LSOA polygons:", nrow(lsoa), "| CRS:", st_crs(lsoa)$input, "\n")
cat("In IoD CSV but not in GeoPackage:", length(setdiff(iod$lsoa, lsoa$LSOA21CD)), "\n")
cat("In GeoPackage but not in IoD CSV:", length(setdiff(lsoa$LSOA21CD, iod$lsoa)), "\n")
gm_lsoa <- filter(lsoa, LSOA21CD %in% iod$lsoa[iod$lad %in% names(boroughs)])
cat("GM LSOAs:", nrow(gm_lsoa), "| vertices:",
    nrow(st_coordinates(st_cast(st_geometry(gm_lsoa), "MULTIPOLYGON"))), "\n")

# ONSPD: list the archive so 02_clean.R knows which CSV to read.
onspd_files <- unzip(file.path(paths$raw, raw_files$onspd), list = TRUE)
print(filter(onspd_files, str_detect(Name, "(?i)\\.csv$"), Length > 1e8))

# ---- 4. Log each fetched file ------------------------------------------------
download_log <- map(downloads, \(d) {
  p <- file.path(paths$raw, d$file)
  tibble(
    file = d$file, item_id = d$item_id, release = d$release,
    downloaded = format(file.mtime(p), "%Y-%m-%d"),
    bytes = file.size(p), sha256 = sha256_file(p)
  )
}) |> list_rbind()
write_csv(download_log, file.path(paths$raw, "download_log.csv"))
print(download_log)
