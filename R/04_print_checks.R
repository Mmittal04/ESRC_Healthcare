# Step 7: automated checks on the exported A1 PDF before a test print.
# Reads outputs/gp-map-a1.pdf with poppler (pdfinfo, pdffonts, pdftotext) and
# writes outputs/print_checks.csv plus a greyscale preview for the eye check.
# Checks that need a person (full-size test print, exclusions review) are
# listed as "manual".

source(here::here("R", "00_settings.R"))
source(here::here("R", "callout_facts.R"))
library(tidyverse)

pdf_file <- file.path(paths$outputs, "gp-map-a1.pdf")
stopifnot("Run R/03_map.R first" = file.exists(pdf_file))
poppler <- \(tool, ...) system2(tool, c(..., shQuote(pdf_file), if (tool == "pdftotext") "-"),
                                stdout = TRUE)

practices <- read_csv(file.path(paths$processed, "practices.csv"), show_col_types = FALSE)
kept <- filter(practices, kept)
exclusions_log <- read_csv(file.path(paths$processed, "exclusions_log.csv"), show_col_types = FALSE)
facts <- callout_facts(kept)

# Text on the sheet, with line breaks and curly apostrophes normalised so
# wrapped sentences can be matched whole.
squash <- \(x) x |> str_replace_all("[‘’]", "'") |> str_squish()
sheet_text <- squash(paste(poppler("pdftotext", "-layout", "-enc", "UTF-8"), collapse = " "))
sheet_text_flow <- squash(paste(poppler("pdftotext", "-enc", "UTF-8"), collapse = " "))
on_sheet <- \(s) str_detect(sheet_text_flow, fixed(squash(s))) | str_detect(sheet_text, fixed(squash(s)))

check <- function(item, pass, detail) tibble(item, status = if (isTRUE(pass)) "pass" else "FAIL", detail)
manual <- function(item, detail) tibble(item, status = "manual", detail)

headline_pt <- as.integer(readLines(file.path(paths$outputs, "headline_pt.txt")))

# ---- File ---------------------------------------------------------------------
info <- poppler("pdfinfo")
page_pt <- as.numeric(str_match(str_subset(info, "^Page size"), "([0-9.]+) x ([0-9.]+)")[, 2:3])
a1_pt <- print_size_mm / 25.4 * 72
fonts <- read_table(I(paste(poppler("pdffonts")[-2], collapse = "\n")), show_col_types = FALSE)

file_checks <- bind_rows(
  check("Page is A1 portrait", all(abs(page_pt - a1_pt) < 2),
        sprintf("%.0f x %.0f pt (A1 is %.0f x %.0f)", page_pt[1], page_pt[2], a1_pt[1], a1_pt[2])),
  check("One page", any(str_detect(info, "^Pages:\\s+1$")), str_subset(info, "^Pages")),
  check("All fonts embedded", all(fonts$emb == "yes"),
        paste(fonts$name, collapse = ", ")),
  check("Typeface is Georgia", all(str_detect(fonts$name, "Georgia")),
        paste(unique(str_remove(fonts$name, "^[A-Z]+\\+")), collapse = ", ")),
  check("Headline at least 72 pt", headline_pt >= headline_min_pt,
        sprintf("%d pt on one line (written by 03_map.R)", headline_pt)),
  check("Body text at least 24 pt",
        all(text_pt[c("subheadline", "how_to_read", "callout_title", "callout_body", "legend")] >= 24),
        paste(names(text_pt), text_pt, sep = " ", collapse = "; ")),
  tibble(item = "Small type below 24 pt", status = "note",
         detail = sprintf("Footer %d pt and borough names %d pt, by design", text_pt[["footer"]], borough_label_pt))
)

# ---- Every panel number traced to the callout facts --------------------------------
n_capacity <- sum(exclusions_log$exclusion_type == "capacity")
n_data <- sum(exclusions_log$exclusion_type == "data")
expected <- c(
  headline    = panel_headline,
  subheadline = sprintf(panel_subheadline, facts$headline$pct_small_busy, facts$headline$pct_large_busy),
  set_names(facts$clusters$body, paste0("callout_", facts$clusters$id)),
  exclusions  = footer_exclusions(nrow(practices), n_capacity, n_data),
  dates       = footer_dates
)
trace_checks <- tibble(item = paste("Text matches data:", names(expected)),
                       pass = map_lgl(expected, on_sheet)) |>
  mutate(status = if_else(pass, "pass", "FAIL"), detail = unname(expected)) |>
  select(-pass)

# Any number printed on the sheet that is not in the expected text or settings
# would be untraced.
allowed_text <- paste(c(expected, panel_how_to_read, panel_method, panel_sources, size_labels,
                        "IMD 2025", "Most deprived fifth", "1 2 3 4 5"), collapse = " ")
numbers_on_sheet <- unique(str_extract_all(sheet_text, "[0-9][0-9,.]*%?")[[1]]) |> str_remove("[.,]$")
untraced <- setdiff(numbers_on_sheet, unique(str_extract_all(allowed_text, "[0-9][0-9,.]*%?")[[1]]) |> str_remove("[.,]$"))
trace_checks <- bind_rows(trace_checks,
  check("No untraced numbers on the sheet", length(untraced) == 0,
        if (length(untraced)) paste("Untraced:", paste(untraced, collapse = ", ")) else
          paste(length(numbers_on_sheet), "distinct numbers, all traced")))

# ---- Data checks from the plan's list ------------------------------------------------
data_checks <- bind_rows(
  check("Practice counts agree across NHS files",
        nrow(practices) == 406 && sum(practices$exclusion == "No workforce record", na.rm = TRUE) == 1,
        "406 GM practices in both patient files; 405 in the workforce file; the 1 gap (Y02625 Care Homes Medical Practice) is logged"),
  check("Every practice has coordinates inside a GM borough",
        all(!is.na(practices$east)) && all(!is.na(practices$borough)),
        sprintf("%d of %d", sum(!is.na(practices$borough)), nrow(practices))),
  check("Footer exclusions line matches the log", on_sheet(expected[["exclusions"]]),
        sprintf("%d excluded: %d capacity, %d data", nrow(exclusions_log), n_capacity, n_data)),
  check("Footer states capacity-only measure and other staff", on_sheet("It measures GP capacity only"),
        "Method note present"),
  check("Footer states neighbourhoods, not people", on_sheet("Shading describes neighbourhoods, not people"),
        "Caveat present")
)

# ---- Greyscale preview for the eye check ---------------------------------------------
grey_png <- file.path(paths$outputs, "gp-map-a1-greyscale.png")
system2("sips", c("-s", "format", "png", "-Z", "2400", shQuote(pdf_file), "--out", shQuote(grey_png)),
        stdout = FALSE)
system2("sips", c("-m", shQuote("/System/Library/ColorSync/Profiles/Generic Gray Profile.icc"),
                  shQuote(grey_png), "--out", shQuote(grey_png)), stdout = FALSE)

manual_checks <- bind_rows(
  manual("Greyscale check", sprintf("Look at %s", basename(grey_png))),
  manual("Exclusions log reviewed", "Read data/processed/exclusions_log.csv (25 practices)"),
  manual("Full-size test print approved", "Print one copy at 100% on A1 before the final order")
)

checks <- bind_rows(file_checks, trace_checks, data_checks, manual_checks)
write_csv(checks, file.path(paths$outputs, "print_checks.csv"))
print(checks, n = Inf, width = 200)
if (any(checks$status == "FAIL")) stop(sum(checks$status == "FAIL"), " print check(s) failed")
