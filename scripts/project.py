"""Project-specific settings used by run_pipeline.py (raw files, exports, JSON.shot content)."""
NAME = "da-learn-25-bike-share-trips"
DATASET = ("Divvy (Chicago bike share) trip data, Oct 2025 - Sep 2026, the data behind the Kaggle 'Cyclistic bike-share' Google Data Analytics "
           "capstone datasets; Divvy Data License Agreement (Lyft Bikes and Scooters, LLC / City of Chicago). 12 monthly CSVs from "
           "https://divvy-tripdata.s3.amazonaws.com (6,171,785 rows x 13 columns, 1,233,745,894 B unzipped, 236,705,265 B zipped) "
           "+ Open-Meteo daily Chicago weather (CC BY 4.0) + US federal holidays")
RAW_FILES = [f"{m}-divvy-tripdata.csv" for m in ["202510", "202511", "202512", "202601", "202602", "202603", "202604", "202605",
                                                  "202606", "202607", "202608", "202609"]]
STAR = ["dim_date", "dim_station", "dim_rider_type", "dim_bike_type", "dim_hour", "agg_daily", "agg_station_month"]
METRIC_TABLES = ["a_kpi_headline", "a_rider_profile", "a_monthly", "a_season", "a_weekday", "a_hourly", "a_heatmap", "a_duration_bands",
                 "a_bike_mix", "a_top_stations", "a_casual_hotspots", "a_station_map", "a_zone", "a_top_routes", "a_daily", "a_weather_fit",
                 "a_temp_bands", "a_rain_effect", "a_day_kind", "a_conversion"]
# fact_ride has ~6.0 million rows: only a deterministic sample is exported (ride_id ending in '00' = 1/256 of rides, ~0.4%)
FACT_SAMPLE = "(SELECT * FROM fact_ride WHERE ride_id LIKE '%00') fs"


def export_full(con, export, root):
    """Full run: dimensions + the two aggregate facts are exported complete; fact_ride as a 1/256 deterministic sample.
    The same files go to data/clean/star/ and powerbi/data/."""
    for t in STAR:
        export(con, t, root / "data/clean/star" / f"{t}.csv")
        export(con, t, root / "powerbi/data" / f"{t}.csv")
    export(con, FACT_SAMPLE, root / "data/clean/star" / "fact_ride_sample.csv")
    export(con, FACT_SAMPLE, root / "powerbi/data" / "fact_ride_sample.csv")
    export(con, "(SELECT invalid_reason, rideable_type, member_casual, COUNT(*) AS rides FROM cln_trips WHERE is_valid = 0 "
                "GROUP BY invalid_reason, rideable_type, member_casual) x", root / "data/clean/invalid_rides_summary.csv")


def build_shot(q, kpi):
    """Headline snapshot written to results/JSON.shot."""
    return {
        "config": {"sql_dialect": "Spark SQL style (+ DuckDB shims in sql/00), run on DuckDB; Databricks skipped (workspace quota)",
                   "window": "rides started 2025-10-01 00:00 to 2026-09-30 23:59 Chicago local time (12 monthly Divvy files 202510-202609)",
                   "grain": "fact_ride = one valid ride; agg_daily = date x rider type x bike type; agg_station_month = start station x month x rider type",
                   "dedupe_rule": "identical rows across monthly files collapsed (35 rides at the Apr/May 2026 boundary), then one row per ride_id",
                   "validity_rule": "60 s <= duration <= 24 h, end location recorded, inside the service-area box (lat 41.60-42.10, lng -87.95..-87.50), "
                                    "not a test/depot station, straight-line speed <= 45 km/h, started inside the window",
                   "dst_rule": "29 rides in the repeated 01:xx hour of 2025-11-02 (DST end) had ended_at < started_at: +3600 s",
                   "station_rule": "stations keyed by standardised name (trim, drop trailing '*', collapse spaces); coordinates = median precise "
                                   "ride coordinates; station_key 0 = dockless e-bike start/end",
                   "weather": "Open-Meteo historical archive, daily, Loop grid cell (41.8781, -87.6298), America/Chicago days",
                   "sample_rule": "data/raw: ride_id ending in '00' (1/256) + every edge-case ride (duplicates, DST, test stations, spill-over, "
                                  "out-of-area, speed); scripts/make_sample.py"},
        "headline": kpi,
        "rider_profile": q("SELECT * FROM a_rider_profile ORDER BY rider_type DESC"),
        "monthly": q("SELECT year_month, member_rides, casual_rides, casual_share_pct FROM a_monthly ORDER BY year_month"),
        "season": q("SELECT season, member_rides_per_day, casual_rides_per_day, casual_share_pct, avg_temp_c FROM a_season ORDER BY avg_temp_c"),
        "weather_fit": q("SELECT * FROM a_weather_fit"),
        "top_casual_stations_top5": q("SELECT rnk, station_name, rides, casual_share_pct FROM a_top_stations WHERE rider_type = 'casual' AND rnk <= 5 ORDER BY rnk"),
        "casual_hotspots_top5": q("SELECT rnk, station_name, starts, casual_share_pct FROM a_casual_hotspots WHERE rnk <= 5 ORDER BY rnk"),
        "conversion": q("SELECT * FROM a_conversion"),
    }
