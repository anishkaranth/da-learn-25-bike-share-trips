-- 03_model.sql  Star schema: fact_ride (valid rides) + dim_date / dim_station / dim_rider_type / dim_bike_type / dim_hour,
-- plus two pre-aggregated facts for BI tools (daily and station x month) (Spark SQL dialect)

CREATE OR REPLACE TABLE dim_date AS
SELECT CAST(date_format(day_date, 'yyyyMMdd') AS INT) AS date_key,
       day_date AS date,
       year(day_date) AS year, month(day_date) AS month, date_format(day_date, 'yyyy-MM') AS year_month,
       weekday(day_date) AS weekday_num,
       CASE weekday(day_date) WHEN 0 THEN 'Mon' WHEN 1 THEN 'Tue' WHEN 2 THEN 'Wed' WHEN 3 THEN 'Thu' WHEN 4 THEN 'Fri'
                              WHEN 5 THEN 'Sat' ELSE 'Sun' END AS day_name,
       CASE WHEN weekday(day_date) >= 5 THEN 1 ELSE 0 END AS is_weekend,
       CASE WHEN holiday IS NOT NULL THEN 1 ELSE 0 END AS is_holiday,
       holiday AS holiday_name,
       CASE WHEN weekday(day_date) >= 5 OR holiday IS NOT NULL THEN 'Weekend / holiday' ELSE 'Weekday' END AS day_type,
       CASE WHEN month(day_date) IN (12, 1, 2) THEN 'Winter' WHEN month(day_date) IN (3, 4, 5) THEN 'Spring'
            WHEN month(day_date) IN (6, 7, 8) THEN 'Summer' ELSE 'Autumn' END AS season,
       temp_mean_c, temp_max_c, temp_min_c, precip_mm, snowfall_cm, wind_max_kmh,
       CASE WHEN temp_mean_c < -5 THEN '01 below -5 C' WHEN temp_mean_c < 0 THEN '02 -5 to 0 C' WHEN temp_mean_c < 5 THEN '03 0-5 C'
            WHEN temp_mean_c < 10 THEN '04 5-10 C' WHEN temp_mean_c < 15 THEN '05 10-15 C' WHEN temp_mean_c < 20 THEN '06 15-20 C'
            WHEN temp_mean_c < 25 THEN '07 20-25 C' ELSE '08 25 C and above' END AS temp_band,
       CASE WHEN snowfall_cm >= 1 THEN 'Snow' WHEN precip_mm >= 5 THEN 'Heavy rain (5 mm+)' WHEN precip_mm >= 1 THEN 'Light rain (1-5 mm)'
            ELSE 'Dry (< 1 mm)' END AS weather_type
FROM cln_day;

-- station_key 0 = "no station" (dockless e-bike start / end)
CREATE OR REPLACE TABLE dim_station AS
SELECT ROW_NUMBER() OVER (ORDER BY station_name) AS station_key, station_name, station_id, station_type, n_ids,
       ROUND(lat, 6) AS lat, ROUND(lng, 6) AS lng, ROUND(dist_to_loop_km, 2) AS dist_to_loop_km,
       CASE WHEN dist_to_loop_km < 3 THEN '1 Loop + near downtown (< 3 km)' WHEN dist_to_loop_km < 8 THEN '2 Inner neighbourhoods (3-8 km)'
            WHEN dist_to_loop_km < 15 THEN '3 Outer neighbourhoods (8-15 km)' ELSE '4 Edge + suburbs (15 km+)' END AS zone,
       first_seen, last_seen
FROM cln_station
UNION ALL
SELECT 0, 'No station (dockless e-bike)', NULL, 'Dockless', 0, NULL, NULL, NULL, '0 Dockless (no station)', NULL, NULL;

CREATE OR REPLACE TABLE dim_rider_type AS
SELECT 1 AS rider_type_key, 'member' AS rider_type, 'Annual member' AS rider_label
UNION ALL SELECT 2, 'casual', 'Casual rider (single ride / day pass)';

CREATE OR REPLACE TABLE dim_bike_type AS
SELECT 1 AS bike_type_key, 'classic_bike' AS bike_type, 'Classic (pedal, docks only)' AS bike_label
UNION ALL SELECT 2, 'electric_bike', 'E-bike (pedal-assist, can park dockless)';

CREATE OR REPLACE TABLE dim_hour AS
SELECT h AS hour,
       CASE WHEN h BETWEEN 6 AND 9 THEN '1 Morning peak (6-9)' WHEN h BETWEEN 10 AND 15 THEN '2 Midday (10-15)'
            WHEN h BETWEEN 16 AND 19 THEN '3 Evening peak (16-19)' WHEN h BETWEEN 20 AND 23 THEN '4 Evening (20-23)'
            ELSE '5 Night (0-5)' END AS daypart
FROM (VALUES (0), (1), (2), (3), (4), (5), (6), (7), (8), (9), (10), (11), (12), (13), (14), (15), (16), (17), (18), (19), (20), (21), (22), (23)) AS x(h);

CREATE OR REPLACE TABLE fact_ride AS
SELECT t.ride_id,
       CAST(date_format(t.ride_date, 'yyyyMMdd') AS INT) AS date_key,
       t.start_hour,
       COALESCE(ss.station_key, 0) AS start_station_key,
       COALESCE(es.station_key, 0) AS end_station_key,
       CASE t.member_casual WHEN 'member' THEN 1 ELSE 2 END AS rider_type_key,
       CASE t.rideable_type WHEN 'classic_bike' THEN 1 ELSE 2 END AS bike_type_key,
       t.started_at, t.ended_at,
       ROUND(t.duration_min, 3) AS duration_min,
       ROUND(t.distance_km, 3) AS distance_km,
       t.distance_is_approx, t.is_round_trip, t.is_dockless_start, t.is_dockless_end, t.duration_band, t.dq_dst_fixed
FROM cln_trips t
LEFT JOIN dim_station ss ON t.start_station = ss.station_name AND ss.station_key > 0
LEFT JOIN dim_station es ON t.end_station = es.station_name AND es.station_key > 0
WHERE t.is_valid = 1;

-- daily aggregate (date x rider type x bike type): small enough for any BI tool, sums back to fact_ride
CREATE OR REPLACE TABLE agg_daily AS
SELECT date_key, rider_type_key, bike_type_key,
       COUNT(*) AS rides, ROUND(SUM(duration_min), 1) AS ride_minutes, ROUND(SUM(distance_km), 1) AS distance_km,
       SUM(is_round_trip) AS round_trips, SUM(is_dockless_start) AS dockless_starts
FROM fact_ride GROUP BY date_key, rider_type_key, bike_type_key;

-- station x month x rider type (starts at a known station)
CREATE OR REPLACE TABLE agg_station_month AS
SELECT start_station_key AS station_key, CAST(floor(date_key / 100) AS INT) AS year_month_key, rider_type_key,
       COUNT(*) AS rides, ROUND(SUM(duration_min), 1) AS ride_minutes, SUM(is_round_trip) AS round_trips
FROM fact_ride WHERE start_station_key > 0
GROUP BY start_station_key, CAST(floor(date_key / 100) AS INT), rider_type_key;
