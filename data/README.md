# Data

| Folder | What | In git? |
|---|---|---|
| `raw/` | Deterministic sample of the 12 raw monthly files (`scripts/make_sample.py`): 25,287 of 6,171,785 rides (0.41%) = every ride whose `ride_id` ends in `00` (1/256) plus 1,238 edge-case rides (cross-file duplicates, DST negatives, test/depot stations, 30 Sep 2025 spill-over, out-of-area, station-name / id quirks, > 24 h and no-end rides). Same file names, header and quoting as the originals | yes (4.9 MB) |
| `raw_full/` | The full original files, downloaded with `python scripts/download_full_data.py` (12 zips from the Divvy S3 bucket, SHA-256 checked, unzipped to `YYYYMM-divvy-tripdata.csv`) | no (`.gitignore`) |
| `reference/` | `chicago_weather_daily.csv`: daily weather for the Loop grid cell (41.8781, -87.6298), 2025-09-30..2026-09-30, from the Open-Meteo historical archive (CC BY 4.0; mean/max/min temperature C, precipitation mm, snowfall cm, max wind km/h, America/Chicago days). `us_holidays.csv`: the 12 US federal holidays in the window (hand-made) | yes |
| `clean/star/` | Star schema from the full run: `dim_date` (365 days + weather + holidays), `dim_station` (2,029 standardised stations + key 0 = dockless), `dim_rider_type`, `dim_bike_type`, `dim_hour`, `agg_daily` (date x rider x bike, complete), `agg_station_month` (station x month x rider, complete) and `fact_ride_sample` (23,380 of 6,006,520 valid rides: `ride_id` ending in `00`) | yes |
| `clean/invalid_rides_summary.csv` | The 165,230 invalid rides by reason x bike type x rider type | yes |

**Raw layout.** One row per ride, 13 columns, all quoted text in the CSV:
`ride_id` (16 hex chars), `rideable_type` (`classic_bike` / `electric_bike`), `started_at`, `ended_at` (local Chicago time with milliseconds, e.g.
`2026-01-31 09:13:09.018`), `start_station_name`, `start_station_id`, `end_station_name`, `end_station_id`, `start_lat`, `start_lng`, `end_lat`,
`end_lng`, `member_casual` (`member` / `casual`). E-bikes can be parked away from a dock, so 20.9% of rides have no start station and their
coordinates are rounded to 2 decimals (about 1 km). A monthly file holds the rides that *ended* in that month (so a few rides started in the
previous month), and a ride ending on the boundary can appear in two files.

**Quirk:** `202601-divvy-tripdata.zip` contains a CSV named `202501-divvy-tripdata.csv`; its rides are from Dec 2025 / Jan 2026, so the download
script writes it as `202601-divvy-tripdata.csv`.

Rebuild the sample with `python scripts/make_sample.py` after downloading the full data.
