-- 02_cleaning.sql  Cross-file dedupe, empty -> NULL, types, station-name standardisation, station dimension source, daylight-saving fix,
-- durations, distances, calendar + weather attributes, outlier / validity flags (Spark SQL dialect)

-- 1. exact duplicate rows: a ride that crosses midnight at a month boundary can be published in BOTH monthly files.
--    Collapse identical rows (all 13 raw columns equal) and keep the earliest file month.
CREATE OR REPLACE TABLE cln_trips_distinct AS
SELECT ride_id, rideable_type, started_at, ended_at, start_station_name, start_station_id, end_station_name, end_station_id,
       start_lat, start_lng, end_lat, end_lng, member_casual,
       min(source_month) AS source_month, COUNT(*) AS n_copies
FROM stg_trips
GROUP BY ride_id, rideable_type, started_at, ended_at, start_station_name, start_station_id, end_station_name, end_station_id,
         start_lat, start_lng, end_lat, end_lng, member_casual;

-- 2. typed + standardised rides, one row per ride_id (if the same ride_id ever came with different content the first file wins; 05 counts them)
--    station names: trim, drop the trailing '*' some stations carry (e.g. 'Morgan St & Lake St*'), collapse repeated spaces
--    station ids: trim + upper (' CHI02331' has a leading space); coordinates: DOUBLE, plus a flag for 2-decimal (rounded) coordinates
CREATE OR REPLACE TABLE cln_trips_typed AS
WITH r AS (
  SELECT d.*, ROW_NUMBER() OVER (PARTITION BY trim(ride_id) ORDER BY source_month, started_at) AS rn,
         COUNT(*) OVER (PARTITION BY trim(ride_id)) AS n_versions
  FROM cln_trips_distinct d
)
SELECT
  trim(ride_id) AS ride_id,
  lower(trim(rideable_type)) AS rideable_type,
  lower(trim(member_casual)) AS member_casual,
  TRY_CAST(trim(started_at) AS TIMESTAMP) AS started_at,
  TRY_CAST(trim(ended_at) AS TIMESTAMP) AS ended_at,
  NULLIF(trim(replace(replace(trim(regexp_replace(trim(start_station_name), '[*]+$', '')), '   ', ' '), '  ', ' ')), '') AS start_station,
  NULLIF(upper(trim(start_station_id)), '') AS start_station_id,
  NULLIF(trim(replace(replace(trim(regexp_replace(trim(end_station_name), '[*]+$', '')), '   ', ' '), '  ', ' ')), '') AS end_station,
  NULLIF(upper(trim(end_station_id)), '') AS end_station_id,
  TRY_CAST(NULLIF(trim(start_lat), '') AS DOUBLE) AS start_lat,
  TRY_CAST(NULLIF(trim(start_lng), '') AS DOUBLE) AS start_lng,
  TRY_CAST(NULLIF(trim(end_lat), '') AS DOUBLE) AS end_lat,
  TRY_CAST(NULLIF(trim(end_lng), '') AS DOUBLE) AS end_lng,
  CASE WHEN regexp_like(trim(start_lat), '^-?[0-9]+([.][0-9]{1,2})?$') THEN 1 ELSE 0 END AS start_coords_rounded,
  CASE WHEN regexp_like(trim(end_lat), '^-?[0-9]+([.][0-9]{1,2})?$') THEN 1 ELSE 0 END AS end_coords_rounded,
  CASE WHEN start_station_name <> trim(start_station_name) OR end_station_name <> trim(end_station_name)
         OR start_station_name LIKE '%*' OR end_station_name LIKE '%*' OR start_station_name LIKE '%  %' OR end_station_name LIKE '%  %'
       THEN 1 ELSE 0 END AS dq_station_name_fixed,
  CASE WHEN start_station_id <> trim(start_station_id) OR end_station_id <> trim(end_station_id) THEN 1 ELSE 0 END AS dq_station_id_fixed,
  source_month, n_copies, n_versions
FROM r
WHERE rn = 1;

-- 3. station source table: every (standardised) station name seen at the start or end of a ride.
--    Divvy re-uses / renames station ids, so the clean NAME is the station key; the id is the most frequent id seen with that name.
--    Coordinates = median of the precise (> 2-decimal) ride coordinates recorded at that station.
CREATE OR REPLACE TABLE cln_station_uses AS
SELECT start_station AS station_name, start_station_id AS station_id, CASE WHEN start_coords_rounded = 0 THEN start_lat END AS lat,
       CASE WHEN start_coords_rounded = 0 THEN start_lng END AS lng, started_at AS used_at, 1 AS is_start
FROM cln_trips_typed WHERE start_station IS NOT NULL
UNION ALL
SELECT end_station, end_station_id, CASE WHEN end_coords_rounded = 0 THEN end_lat END, CASE WHEN end_coords_rounded = 0 THEN end_lng END,
       ended_at, 0
FROM cln_trips_typed WHERE end_station IS NOT NULL;

CREATE OR REPLACE TABLE cln_station AS
WITH ids AS (
  SELECT station_name, station_id, COUNT(*) AS n,
         ROW_NUMBER() OVER (PARTITION BY station_name ORDER BY COUNT(*) DESC, station_id) AS rn
  FROM cln_station_uses WHERE station_id IS NOT NULL GROUP BY station_name, station_id
), agg AS (
  SELECT station_name,
         SUM(is_start) AS n_starts, SUM(1 - is_start) AS n_ends,
         COUNT(DISTINCT station_id) AS n_ids,
         percentile_approx(lat, 0.5) AS lat, percentile_approx(lng, 0.5) AS lng,
         CAST(min(used_at) AS DATE) AS first_seen, CAST(max(used_at) AS DATE) AS last_seen
  FROM cln_station_uses GROUP BY station_name
)
SELECT a.station_name, i.station_id, a.n_ids, a.n_starts, a.n_ends, a.lat, a.lng, a.first_seen, a.last_seen,
       CASE WHEN regexp_like(upper(a.station_name), 'TEST|DEPOT|WAREHOUSE|REPAIR|DIVVY ') THEN 'Test / depot'
            WHEN upper(a.station_name) LIKE '%PUBLIC RACK%' THEN 'Public rack'
            WHEN a.station_name LIKE '%(Temp)%' THEN 'Temporary dock'
            ELSE 'Dock' END AS station_type,
       -- distance from State & Madison (41.8819, -87.6278), the zero point of Chicago's street grid
       haversine_km(41.8819, -87.6278, a.lat, a.lng) AS dist_to_loop_km
FROM agg a LEFT JOIN ids i ON a.station_name = i.station_name AND i.rn = 1;

-- 4. clean rides with derived attributes and quality flags
--    * daylight saving: on 2 Nov 2025 clocks went back at 02:00, so a ride that started in the first 01:xx hour and ended in the repeated
--      01:xx hour has ended_at < started_at. Those rides get +3600 s (dq_dst_fixed); other negative durations stay invalid.
--    * distance: station coordinates when the station is known (precise), else the ride coordinates (2-decimal for dockless e-bikes -> approx)
--    * validity: inside the 12-month window, 60 s <= duration <= 24 h, end recorded, inside the service area, not a test/depot station,
--      straight-line speed <= 45 km/h (e-bikes are capped at 20 mph = 32 km/h)
CREATE OR REPLACE TABLE cln_trips AS
WITH b AS (
  SELECT t.*,
         unix_timestamp(t.ended_at) - unix_timestamp(t.started_at) AS duration_sec_raw,
         ss.station_type AS start_station_type, es.station_type AS end_station_type,
         COALESCE(ss.lat, t.start_lat) AS s_lat, COALESCE(ss.lng, t.start_lng) AS s_lng,
         COALESCE(es.lat, t.end_lat) AS e_lat, COALESCE(es.lng, t.end_lng) AS e_lng,
         CASE WHEN (ss.lat IS NULL AND t.start_coords_rounded = 1) OR (es.lat IS NULL AND t.end_coords_rounded = 1) THEN 1 ELSE 0 END AS distance_is_approx
  FROM cln_trips_typed t
  LEFT JOIN cln_station ss ON t.start_station = ss.station_name
  LEFT JOIN cln_station es ON t.end_station = es.station_name
), d AS (
  SELECT b.*,
         CASE WHEN duration_sec_raw < 0 AND CAST(started_at AS DATE) = DATE'2025-11-02' AND hour(started_at) = 1
                   AND hour(ended_at) = 1 AND duration_sec_raw + 3600 >= 0 THEN 1 ELSE 0 END AS dq_dst_fixed
  FROM b
), e AS (
  SELECT d.*,
         duration_sec_raw + 3600 * dq_dst_fixed AS duration_sec,
         CASE WHEN e_lat IS NULL OR s_lat IS NULL THEN NULL ELSE haversine_km(s_lat, s_lng, e_lat, e_lng) END AS distance_km
  FROM d
), f AS (
  SELECT e.*,
         CASE WHEN started_at IS NULL OR ended_at IS NULL THEN 1 ELSE 0 END AS dq_bad_timestamp,
         CASE WHEN started_at < TIMESTAMP'2025-10-01 00:00:00' OR started_at >= TIMESTAMP'2026-10-01 00:00:00' THEN 1 ELSE 0 END AS dq_out_of_window,
         CASE WHEN duration_sec < 0 THEN 1 ELSE 0 END AS dq_negative_duration,
         CASE WHEN duration_sec >= 0 AND duration_sec < 60 THEN 1 ELSE 0 END AS dq_under_60s,
         CASE WHEN duration_sec > 86400 THEN 1 ELSE 0 END AS dq_over_24h,
         CASE WHEN end_lat IS NULL OR end_lng IS NULL THEN 1 ELSE 0 END AS dq_no_end_location,
         CASE WHEN s_lat NOT BETWEEN 41.60 AND 42.10 OR s_lng NOT BETWEEN -87.95 AND -87.50
                OR e_lat NOT BETWEEN 41.60 AND 42.10 OR e_lng NOT BETWEEN -87.95 AND -87.50 THEN 1 ELSE 0 END AS dq_out_of_area,
         CASE WHEN start_station_type = 'Test / depot' OR end_station_type = 'Test / depot' THEN 1 ELSE 0 END AS dq_test_station,
         CASE WHEN distance_is_approx = 0 AND duration_sec >= 60 AND distance_km / (duration_sec / 3600.0) > 45 THEN 1 ELSE 0 END AS dq_speed_outlier,
         CASE WHEN rideable_type NOT IN ('classic_bike', 'electric_bike') OR member_casual NOT IN ('member', 'casual')
                OR rideable_type IS NULL OR member_casual IS NULL THEN 1 ELSE 0 END AS dq_bad_category
  FROM e
)
SELECT f.*,
       CASE WHEN dq_bad_timestamp + dq_out_of_window + dq_negative_duration + dq_under_60s + dq_over_24h + dq_no_end_location
                 + dq_out_of_area + dq_test_station + dq_speed_outlier + dq_bad_category = 0 THEN 1 ELSE 0 END AS is_valid,
       CASE WHEN dq_bad_timestamp = 1 THEN 'unparseable timestamp'
            WHEN dq_out_of_window = 1 THEN 'started before 1 Oct 2025 (previous month spill-over)'
            WHEN dq_negative_duration = 1 THEN 'negative duration'
            WHEN dq_under_60s = 1 THEN 'under 60 seconds (false start / re-dock)'
            WHEN dq_over_24h = 1 THEN 'over 24 hours (lost / not returned)'
            WHEN dq_no_end_location = 1 THEN 'no end location (bike not returned)'
            WHEN dq_test_station = 1 THEN 'test / depot station'
            WHEN dq_out_of_area = 1 THEN 'outside the service area'
            WHEN dq_speed_outlier = 1 THEN 'implausible speed (> 45 km/h)'
            WHEN dq_bad_category = 1 THEN 'unknown bike or rider type' END AS invalid_reason,
       CAST(started_at AS DATE) AS ride_date,
       hour(started_at) AS start_hour,
       weekday(started_at) AS weekday_num,
       date_format(started_at, 'yyyy-MM') AS ride_month,
       duration_sec / 60.0 AS duration_min,
       CASE WHEN start_station IS NOT NULL AND start_station = end_station THEN 1 ELSE 0 END AS is_round_trip,
       CASE WHEN start_station IS NULL THEN 1 ELSE 0 END AS is_dockless_start,
       CASE WHEN end_station IS NULL THEN 1 ELSE 0 END AS is_dockless_end,
       CASE WHEN duration_sec < 300 THEN '01 <5 min' WHEN duration_sec < 600 THEN '02 5-10 min' WHEN duration_sec < 1200 THEN '03 10-20 min'
            WHEN duration_sec < 1800 THEN '04 20-30 min' WHEN duration_sec < 3600 THEN '05 30-60 min' ELSE '06 60+ min' END AS duration_band
FROM f;

-- 5. calendar + weather for the 365 days of the window (Open-Meteo daily values for the Loop grid cell, local Chicago days)
CREATE OR REPLACE TABLE cln_day AS
SELECT CAST(trim(w.date) AS DATE) AS day_date,
       TRY_CAST(w.temp_mean_c AS DOUBLE) AS temp_mean_c, TRY_CAST(w.temp_max_c AS DOUBLE) AS temp_max_c,
       TRY_CAST(w.temp_min_c AS DOUBLE) AS temp_min_c, TRY_CAST(w.precip_mm AS DOUBLE) AS precip_mm,
       TRY_CAST(w.snowfall_cm AS DOUBLE) AS snowfall_cm, TRY_CAST(w.wind_max_kmh AS DOUBLE) AS wind_max_kmh,
       h.holiday
FROM ref_weather w
LEFT JOIN ref_holidays h ON CAST(trim(w.date) AS DATE) = CAST(trim(h.date) AS DATE)
WHERE CAST(trim(w.date) AS DATE) BETWEEN DATE'2025-10-01' AND DATE'2026-09-30';
