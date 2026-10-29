# GP and street map

One printed A1 map of Greater Manchester's ten boroughs. Each GP practice is a dot,
coloured by how many registered patients each qualified GP cares for, over a muted
map of neighbourhood deprivation (IMD 2025). Short annotations guide visitors to
the pattern.

## Run it

Requires R (4.5 or later) and Quarto.

```r
renv::restore()             # install the locked package versions
source("R/01_download.R")   # check raw files, fetch boundaries and coordinates
source("R/02_clean.R")      # filter, join, ratio, exclusions
```

```bash
quarto render gp-map.qmd --output-dir outputs    # checks, bands and callout facts
```

```r
source("R/03_map.R")        # build and export the map to outputs/
```

## Layout

```
├── README.md
├── data/
│   ├── raw/          untouched downloads (git-ignored; see MANIFEST.md)
│   └── processed/    cleaned files written by the scripts
├── R/
│   ├── 00_settings.R paths, area filter, thresholds, colours
│   ├── 01_download.R fetch each input, record the release date
│   ├── 02_clean.R    filter, join, ratio, exclusions, coordinates
│   └── 03_map.R      build the map, add annotations, export PDF
├── gp-map.qmd        annotated notebook: checks, bands, callout facts
└── outputs/          print PDF and preview PNG
```

## Sources

| Input | Publisher | Release |
|---|---|---|
| General Practice Workforce, practice-level CSV | NHS England | 30 September 2026 |
| Patients Registered at a GP Practice | NHS England | 1 October 2026 |
| English Indices of Deprivation 2025 | MHCLG | 17 November 2025 |
| ONS Postcode Directory (practice coordinates) | ONS | August 2026 |
| IoD 2025 LSOA geopackage (LSOA boundaries; boroughs dissolved from it) | MHCLG | 17 November 2025 |

Full file list and checksums: [data/raw/MANIFEST.md](data/raw/MANIFEST.md).

## Method in one line

Patients per GP = registered patients ÷ full-time-equivalent qualified GPs
(excluding trainees and locums; 1 FTE = 37.5 hours a week). It measures GP
capacity only; nurses, pharmacists and other practice staff are outside the count.
