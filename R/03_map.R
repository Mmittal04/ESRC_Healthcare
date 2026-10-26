# Steps 5 to 7: build the map, add annotations, export the A1 PDF and a preview PNG.

source(here::here("R", "00_settings.R"))
library(tidyverse)
library(sf)
library(tmap)

# TODO: base layer, practice dots, borough outlines, annotations
# Ancoats anchor (star linking to the 1851 street scene) is deferred until the
# link target is decided.
