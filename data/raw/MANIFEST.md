# Raw data manifest

Files in this folder are never edited. They are git-ignored because of their size;
this manifest records where each came from and its SHA-256, so a fresh download
can be checked against the copy used for the map.

| File | Source | Release | SHA-256 |
|---|---|---|---|
| `3 General Practice – August 2026 Practice Level - High level.csv` | [General Practice Workforce](https://www.gov.uk/government/statistics/general-practice-workforce-31-august-2026), NHS England | 31 August 2026 | `7faee23ec987157bd216d19f1a2870a1996c1880e8d680fa8ff7e3b2eedc8ad7` |
| `2 General Practice High-level Practice-Level CSV. Overall Definitions.xlsx` | Same publication, field definitions | 31 August 2026 | `5564370c308f1525fe1ca1f625b75edbfe8f04faca6a9be3413d5bef6048d7cd` |
| `gp-reg-pat-prac-all.csv` | [Patients Registered at a GP Practice](https://digital.nhs.uk/data-and-information/publications/statistical/patients-registered-at-a-gp-practice/october-2026), NHS England | 1 October 2026 | `abeeed44eafe55c23a2515d21d3f63b93d99b43f3a613aaf792709ec5c1e59da` |
| `gp-reg-pat-prac-map.csv` | Same publication, practice to PCN / ICB mapping | 1 October 2026 | `c1bd57716b426bb8e25ba4928470bac3e02b73fe9b7f8943973f1f2466855aa9` |
| `gp-reg-pat-prac-lsoa-all.csv` | Same publication, patients by practice and LSOA | 1 October 2026 | `28fd06e72e383b4078dbb6a159e326ed2023d447ab25a5b5a7f04d03f1f58af4` |
| `IoD 2025 All Ranks Scores.csv` | [English Indices of Deprivation 2025](https://www.gov.uk/government/statistics/english-indices-of-deprivation-2025), MHCLG | 17 November 2025 | `b1b716aa2e476449f987b9de3e08255b4794eabfd270626de5de18b2f5eff3ef` |

## Still to download

- LSOA 2021 boundaries: IoD 2025 LSOA geopackage, MHCLG (base layer)
- Borough outlines: dissolved from the geopackage LSOAs by local authority
  code, so outlines and base layer line up exactly (no separate download)
- Coordinates for practice postcodes: ONS Postcode Directory (ONSPD), latest
  release at download time; also supplies each postcode's LSOA 2021 and local
  authority code for the borough cross-check
