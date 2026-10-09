-- 05_quality_checks.sql  Data-quality evidence: before/after counts, issue counts, null rates, assertions (Spark SQL dialect)

CREATE OR REPLACE TABLE dq_row_counts AS
SELECT 'raw trip rows (12 monthly files)' AS entity, (SELECT COUNT(*) FROM stg_trips) AS raw_rows,
       (SELECT COUNT(*) FROM cln_trips_distinct) AS distinct_rows, (SELECT COUNT(*) FROM fact_ride) AS clean_rows,
       'ride (clean = valid rides in fact_ride)' AS grain
UNION ALL SELECT 'rides after dedupe (one row per ride_id)', NULL, NULL, (SELECT COUNT(*) FROM cln_trips), 'ride'
UNION ALL SELECT 'invalid rides (flagged, kept in cln_trips, not in fact_ride)', NULL, NULL, (SELECT COUNT(*) FROM cln_trips WHERE is_valid = 0), 'ride'
UNION ALL SELECT 'fact_ride', NULL, NULL, (SELECT COUNT(*) FROM fact_ride), 'valid ride'
UNION ALL SELECT 'agg_daily', NULL, NULL, (SELECT COUNT(*) FROM agg_daily), 'date x rider type x bike type'
UNION ALL SELECT 'agg_station_month', NULL, NULL, (SELECT COUNT(*) FROM agg_station_month), 'start station x month x rider type'
UNION ALL SELECT 'dim_station (incl. key 0 = dockless)', NULL, NULL, (SELECT COUNT(*) FROM dim_station), 'standardised station name'
UNION ALL SELECT 'dim_date', NULL, NULL, (SELECT COUNT(*) FROM dim_date), 'day (with weather + holiday)'
UNION ALL SELECT 'dim_hour / dim_rider_type / dim_bike_type', NULL, NULL,
       (SELECT COUNT(*) FROM dim_hour) + (SELECT COUNT(*) FROM dim_rider_type) + (SELECT COUNT(*) FROM dim_bike_type), '24 + 2 + 2';

CREATE OR REPLACE TABLE dq_null_rates AS
SELECT 'raw rides' AS entity, 'start_station_name' AS column_name,
       ROUND(100.0 * SUM(CASE WHEN NULLIF(trim(start_station_name), '') IS NULL THEN 1 ELSE 0 END) / COUNT(*), 2) AS null_pct,
       'e-bikes can start away from a dock: kept, start_station_key = 0 (dockless)' AS treatment FROM stg_trips
UNION ALL SELECT 'raw rides', 'end_station_name', ROUND(100.0 * SUM(CASE WHEN NULLIF(trim(end_station_name), '') IS NULL THEN 1 ELSE 0 END) / COUNT(*), 2),
       'dockless e-bike ends: kept, end_station_key = 0' FROM stg_trips
UNION ALL SELECT 'raw rides', 'start_station_id', ROUND(100.0 * SUM(CASE WHEN NULLIF(trim(start_station_id), '') IS NULL THEN 1 ELSE 0 END) / COUNT(*), 2),
       'id only used as an attribute; stations are keyed by clean name' FROM stg_trips
UNION ALL SELECT 'raw rides', 'end_lat / end_lng', ROUND(100.0 * SUM(CASE WHEN NULLIF(trim(end_lat), '') IS NULL THEN 1 ELSE 0 END) / COUNT(*), 2),
       'no end location = bike not returned / lost: invalid' FROM stg_trips
UNION ALL SELECT 'raw rides', 'start_lat (2-decimal, rounded)', ROUND(100.0 * SUM(CASE WHEN regexp_like(trim(start_lat), '^-?[0-9]+([.][0-9]{1,2})?$') THEN 1 ELSE 0 END) / COUNT(*), 2),
       'dockless coordinates are rounded to ~1 km: distance flagged approximate' FROM stg_trips
UNION ALL SELECT 'raw rides', 'ride_id / rideable_type / started_at / ended_at / member_casual',
       ROUND(100.0 * SUM(CASE WHEN NULLIF(trim(ride_id), '') IS NULL OR NULLIF(trim(rideable_type), '') IS NULL OR NULLIF(trim(started_at), '') IS NULL
                               OR NULLIF(trim(ended_at), '') IS NULL OR NULLIF(trim(member_casual), '') IS NULL THEN 1 ELSE 0 END) / COUNT(*), 2),
       'required: never empty' FROM stg_trips;

CREATE OR REPLACE TABLE dq_issues AS
SELECT 'duplicate rows: same ride published in two monthly files (Apr/May 2026 boundary), dropped' AS check_name,
       (SELECT COUNT(*) FROM stg_trips) - (SELECT COUNT(*) FROM cln_trips_distinct) AS affected_rows
UNION ALL SELECT 'ride_id repeated with different content (first file kept)', (SELECT COUNT(*) FROM cln_trips WHERE n_versions > 1)
UNION ALL SELECT 'rides under 60 s (false starts / re-docks), invalid', (SELECT SUM(dq_under_60s) FROM cln_trips)
UNION ALL SELECT 'rides over 24 h (lost / not returned), invalid', (SELECT SUM(dq_over_24h) FROM cln_trips)
UNION ALL SELECT 'rides with no end location, invalid', (SELECT SUM(dq_no_end_location) FROM cln_trips)
UNION ALL SELECT 'rides at test / depot / warehouse stations, invalid', (SELECT SUM(dq_test_station) FROM cln_trips)
UNION ALL SELECT 'rides started before 1 Oct 2025 (spill-over in the Oct file), invalid', (SELECT SUM(dq_out_of_window) FROM cln_trips)
UNION ALL SELECT 'rides outside the service-area box, invalid', (SELECT SUM(dq_out_of_area) FROM cln_trips)
UNION ALL SELECT 'implausible straight-line speed > 45 km/h, invalid', (SELECT SUM(dq_speed_outlier) FROM cln_trips)
UNION ALL SELECT 'negative durations left after the DST fix, invalid', (SELECT SUM(dq_negative_duration) FROM cln_trips)
UNION ALL SELECT 'negative durations in the repeated 1 AM hour of 2 Nov 2025 (DST end), fixed +60 min', (SELECT SUM(dq_dst_fixed) FROM cln_trips)
UNION ALL SELECT 'station names fixed (trailing space, trailing *, double space)', (SELECT SUM(dq_station_name_fixed) FROM cln_trips)
UNION ALL SELECT 'station ids with a leading space, trimmed', (SELECT SUM(dq_station_id_fixed) FROM cln_trips)
UNION ALL SELECT 'raw station-name variants merged by standardisation', (SELECT COUNT(DISTINCT start_station_name) FROM stg_trips)
       - (SELECT COUNT(DISTINCT start_station) FROM cln_trips_typed)
UNION ALL SELECT 'stations seen with more than one station id', (SELECT COUNT(*) FROM cln_station WHERE n_ids > 1)
UNION ALL SELECT 'dockless e-bike starts (no station), kept', (SELECT SUM(is_dockless_start) FROM cln_trips)
UNION ALL SELECT 'distances approximate (2-decimal dockless coordinates), kept + flagged', (SELECT SUM(distance_is_approx) FROM cln_trips WHERE is_valid = 1)
UNION ALL SELECT 'zip quirk: 202601 zip contains a file named 202501-divvy-tripdata.csv (renamed on download)', 1
UNION ALL SELECT 'RI: valid rides lost in dimension joins', (SELECT COUNT(*) FROM cln_trips WHERE is_valid = 1) - (SELECT COUNT(*) FROM fact_ride);

-- Checks marked [full data only] need all 365 days / every month and report SKIP on the committed sample.
CREATE OR REPLACE TABLE dq_assertions AS
WITH fd AS (SELECT CASE WHEN COUNT(*) >= 1000000 THEN 1 ELSE 0 END AS full_data FROM stg_trips),
c AS (
  SELECT 'distinct rows = raw rows - exact cross-file duplicates' AS check_name,
         ABS((SELECT COUNT(*) FROM cln_trips_distinct) - (SELECT COUNT(*) FROM (SELECT DISTINCT ride_id, rideable_type, started_at, ended_at,
             start_station_name, start_station_id, end_station_name, end_station_id, start_lat, start_lng, end_lat, end_lng, member_casual FROM stg_trips) d)) AS failed_rows
  UNION ALL SELECT 'one row per ride_id in cln_trips', (SELECT COUNT(*) - COUNT(DISTINCT ride_id) FROM cln_trips)
  UNION ALL SELECT 'no ride_id with conflicting content', (SELECT COUNT(*) FROM cln_trips WHERE n_versions > 1)
  UNION ALL SELECT 'valid + invalid = all distinct rides', ABS((SELECT COUNT(*) FROM cln_trips) - (SELECT SUM(is_valid) + SUM(1 - is_valid) FROM cln_trips))
  UNION ALL SELECT 'every invalid ride has exactly one reported reason', (SELECT COUNT(*) FROM cln_trips WHERE (is_valid = 0 AND invalid_reason IS NULL)
         OR (is_valid = 1 AND invalid_reason IS NOT NULL))
  UNION ALL SELECT 'ride_id = 16 upper-case hex characters', (SELECT COUNT(*) FROM cln_trips WHERE NOT regexp_like(ride_id, '^[0-9A-F]{16}$'))
  UNION ALL SELECT 'all timestamps parsed', (SELECT SUM(dq_bad_timestamp) FROM cln_trips)
  UNION ALL SELECT 'rideable_type in (classic_bike, electric_bike) and member_casual in (member, casual)', (SELECT SUM(dq_bad_category) FROM cln_trips)
  UNION ALL SELECT 'valid rides: 60 s <= duration <= 24 h', (SELECT COUNT(*) FROM fact_ride WHERE duration_min < 1 OR duration_min > 1440)
  UNION ALL SELECT 'valid rides start inside 2025-10-01 .. 2026-09-30', (SELECT COUNT(*) FROM fact_ride WHERE date_key < 20251001 OR date_key > 20260930)
  UNION ALL SELECT 'DST fix only touches 2 Nov 2025 01:xx rides and leaves no negative valid duration', (SELECT COUNT(*) FROM cln_trips
         WHERE dq_dst_fixed = 1 AND (ride_date <> DATE'2025-11-02' OR start_hour <> 1 OR duration_sec < 0))
  UNION ALL SELECT 'valid rides inside the service-area box', (SELECT COUNT(*) FROM cln_trips WHERE is_valid = 1 AND (s_lat NOT BETWEEN 41.60 AND 42.10
         OR s_lng NOT BETWEEN -87.95 AND -87.50 OR e_lat NOT BETWEEN 41.60 AND 42.10 OR e_lng NOT BETWEEN -87.95 AND -87.50))
  UNION ALL SELECT 'classic bikes always start at a station', (SELECT COUNT(*) FROM fact_ride WHERE bike_type_key = 1 AND start_station_key = 0)
  UNION ALL SELECT 'distance >= 0 and round trips have 0 km', (SELECT COUNT(*) FROM fact_ride WHERE distance_km < 0 OR (is_round_trip = 1 AND distance_km <> 0))
  UNION ALL SELECT 'station names standardised (trimmed, no trailing *, no double spaces)', (SELECT COUNT(*) FROM dim_station
         WHERE station_name <> trim(station_name) OR station_name LIKE '%*' OR station_name LIKE '%  %')
  UNION ALL SELECT 'station_key and station_name unique in dim_station', (SELECT COUNT(*) - COUNT(DISTINCT station_key) FROM dim_station)
         + (SELECT COUNT(*) - COUNT(DISTINCT station_name) FROM dim_station)
  UNION ALL SELECT 'every station has coordinates inside the service area', (SELECT COUNT(*) FROM dim_station WHERE station_key > 0
         AND (lat IS NULL OR lat NOT BETWEEN 41.60 AND 42.10 OR lng NOT BETWEEN -87.95 AND -87.50))
  UNION ALL SELECT 'fact keys exist in every dimension (RI)', (SELECT COUNT(*) FROM fact_ride f
         LEFT JOIN dim_date d ON f.date_key = d.date_key LEFT JOIN dim_station s ON f.start_station_key = s.station_key
         LEFT JOIN dim_station e ON f.end_station_key = e.station_key LEFT JOIN dim_hour h ON f.start_hour = h.hour
         LEFT JOIN dim_rider_type r ON f.rider_type_key = r.rider_type_key LEFT JOIN dim_bike_type b ON f.bike_type_key = b.bike_type_key
         WHERE d.date_key IS NULL OR s.station_key IS NULL OR e.station_key IS NULL OR h.hour IS NULL OR r.rider_type_key IS NULL OR b.bike_type_key IS NULL)
  UNION ALL SELECT 'fact_ride = valid rides in cln_trips', ABS((SELECT COUNT(*) FROM fact_ride) - (SELECT SUM(is_valid) FROM cln_trips))
  UNION ALL SELECT 'agg_daily sums back to fact_ride (rides and minutes)', ABS((SELECT SUM(rides) FROM agg_daily) - (SELECT COUNT(*) FROM fact_ride))
         + CASE WHEN ABS((SELECT SUM(ride_minutes) FROM agg_daily) - (SELECT SUM(duration_min) FROM fact_ride)) > 100 THEN 1 ELSE 0 END
  UNION ALL SELECT 'agg_station_month sums back to station-start rides', ABS((SELECT SUM(rides) FROM agg_station_month)
         - (SELECT COUNT(*) FROM fact_ride WHERE start_station_key > 0))
  UNION ALL SELECT 'a_monthly totals = fact_ride and member + casual = rides', ABS((SELECT SUM(rides) FROM a_monthly) - (SELECT COUNT(*) FROM fact_ride))
         + (SELECT COUNT(*) FROM a_monthly WHERE member_rides + casual_rides <> rides)
  UNION ALL SELECT 'a_hourly rides sum back to fact_ride', ABS((SELECT SUM(rides) FROM a_hourly) - (SELECT COUNT(*) FROM fact_ride))
  UNION ALL SELECT 'member + casual ride shares = 100%', CASE WHEN ABS((SELECT SUM(ride_share_pct) FROM a_rider_profile) - 100) > 0.02 THEN 1 ELSE 0 END
  UNION ALL SELECT 'dim_date = 365 consecutive days with weather', ABS(365 - (SELECT COUNT(*) FROM dim_date))
         + (SELECT COUNT(*) FROM dim_date WHERE temp_mean_c IS NULL OR precip_mm IS NULL)
         + (SELECT COUNT(*) - COUNT(DISTINCT date) FROM dim_date)
         + (SELECT CASE WHEN min(date) = DATE'2025-10-01' AND max(date) = DATE'2026-09-30' THEN 0 ELSE 1 END FROM dim_date)
  UNION ALL SELECT 'every day of the window has rides [full data only]', (SELECT COUNT(*) FROM a_daily WHERE rides = 0)
  UNION ALL SELECT 'all 12 months present with >= 100,000 valid rides [full data only]', ABS(12 - (SELECT COUNT(*) FROM a_monthly WHERE rides >= 100000))
  UNION ALL SELECT 'invalid rides below 5% of all rides [full data only]', CASE WHEN (SELECT AVG(1.0 - is_valid) FROM cln_trips) >= 0.05 THEN 1 ELSE 0 END
)
SELECT check_name, COALESCE(failed_rows, 0) AS failed_rows,
       CASE WHEN check_name LIKE '%[full data only]' AND (SELECT full_data FROM fd) = 0 THEN 'SKIP'
            WHEN COALESCE(failed_rows, 0) = 0 THEN 'PASS' ELSE 'FAIL' END AS status
FROM c;
