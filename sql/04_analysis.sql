-- 04_analysis.sql  KPIs and business questions on the star schema (valid rides only) (Spark SQL dialect)
-- Business task (Cyclistic / Google Data Analytics capstone): how do annual members and casual riders use the bikes differently,
-- and where / when should a membership campaign target casual riders?

-- rides joined to their dimensions once (view, so nothing is materialised twice)
CREATE OR REPLACE VIEW v_ride AS
SELECT f.*, r.rider_type, b.bike_type, d.date, d.year_month, d.weekday_num, d.day_name, d.is_weekend, d.is_holiday, d.day_type, d.season,
       d.temp_mean_c, d.precip_mm, d.temp_band, d.weather_type
FROM fact_ride f
JOIN dim_rider_type r ON f.rider_type_key = r.rider_type_key
JOIN dim_bike_type b ON f.bike_type_key = b.bike_type_key
JOIN dim_date d ON f.date_key = d.date_key;

-- Q1 rider-type profile: volume, duration, distance, speed, bike choice, round trips, weekends, dockless use
CREATE OR REPLACE TABLE a_rider_profile AS
SELECT rider_type,
       COUNT(*) AS rides,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS ride_share_pct,
       ROUND(SUM(duration_min) / 60.0, 0) AS ride_hours,
       ROUND(100.0 * SUM(duration_min) / SUM(SUM(duration_min)) OVER (), 2) AS ride_minutes_share_pct,
       ROUND(percentile_approx(duration_min, 0.5), 2) AS median_min,
       ROUND(AVG(duration_min), 2) AS mean_min,
       ROUND(percentile_approx(duration_min, 0.9), 2) AS p90_min,
       ROUND(percentile_approx(CASE WHEN is_round_trip = 0 AND distance_is_approx = 0 THEN distance_km END, 0.5), 3) AS median_km_station_to_station,
       ROUND(percentile_approx(CASE WHEN is_round_trip = 0 AND distance_is_approx = 0 AND duration_min >= 2
                                    THEN distance_km / (duration_min / 60.0) END, 0.5), 2) AS median_kmh_station_to_station,
       ROUND(100.0 * SUM(CASE WHEN bike_type = 'electric_bike' THEN 1 ELSE 0 END) / COUNT(*), 2) AS ebike_pct,
       ROUND(100.0 * SUM(is_round_trip) / COUNT(*), 2) AS round_trip_pct,
       ROUND(100.0 * SUM(CASE WHEN day_type = 'Weekend / holiday' THEN 1 ELSE 0 END) / COUNT(*), 2) AS weekend_holiday_pct,
       ROUND(100.0 * SUM(is_dockless_start) / COUNT(*), 2) AS dockless_start_pct,
       ROUND(100.0 * SUM(CASE WHEN duration_min > 45 THEN 1 ELSE 0 END) / COUNT(*), 2) AS over_45_min_pct,
       ROUND(100.0 * SUM(CASE WHEN day_type = 'Weekday' AND (start_hour BETWEEN 7 AND 9 OR start_hour BETWEEN 16 AND 18) THEN 1 ELSE 0 END)
             / COUNT(*), 2) AS weekday_commute_hours_pct
FROM v_ride GROUP BY rider_type;

-- Q2 seasonality: rides per month by rider type
CREATE OR REPLACE TABLE a_monthly AS
SELECT year_month,
       SUM(CASE WHEN rider_type = 'member' THEN 1 ELSE 0 END) AS member_rides,
       SUM(CASE WHEN rider_type = 'casual' THEN 1 ELSE 0 END) AS casual_rides,
       COUNT(*) AS rides,
       ROUND(100.0 * SUM(CASE WHEN rider_type = 'casual' THEN 1 ELSE 0 END) / COUNT(*), 2) AS casual_share_pct,
       ROUND(percentile_approx(CASE WHEN rider_type = 'member' THEN duration_min END, 0.5), 2) AS member_median_min,
       ROUND(percentile_approx(CASE WHEN rider_type = 'casual' THEN duration_min END, 0.5), 2) AS casual_median_min,
       ROUND(100.0 * SUM(CASE WHEN bike_type = 'electric_bike' THEN 1 ELSE 0 END) / COUNT(*), 2) AS ebike_pct,
       ROUND(AVG(temp_mean_c), 1) AS ride_weighted_temp_c
FROM v_ride GROUP BY year_month;

CREATE OR REPLACE TABLE a_season AS
WITH days AS (SELECT season, COUNT(*) AS n_days, ROUND(AVG(temp_mean_c), 1) AS avg_temp_c FROM dim_date GROUP BY season)
SELECT v.season, d.n_days, d.avg_temp_c,
       ROUND(SUM(CASE WHEN rider_type = 'member' THEN 1 ELSE 0 END) / d.n_days, 0) AS member_rides_per_day,
       ROUND(SUM(CASE WHEN rider_type = 'casual' THEN 1 ELSE 0 END) / d.n_days, 0) AS casual_rides_per_day,
       ROUND(100.0 * SUM(CASE WHEN rider_type = 'casual' THEN 1 ELSE 0 END) / COUNT(*), 2) AS casual_share_pct
FROM v_ride v JOIN days d ON v.season = d.season GROUP BY v.season, d.n_days, d.avg_temp_c;

-- Q3 weekly rhythm: average rides per calendar day of each weekday
CREATE OR REPLACE TABLE a_weekday AS
WITH days AS (SELECT weekday_num, COUNT(*) AS n_days FROM dim_date GROUP BY weekday_num)
SELECT v.weekday_num, v.day_name, v.rider_type, COUNT(*) AS rides, d.n_days,
       ROUND(COUNT(*) / d.n_days, 0) AS rides_per_day,
       ROUND(percentile_approx(duration_min, 0.5), 2) AS median_min
FROM v_ride v JOIN days d ON v.weekday_num = d.weekday_num GROUP BY v.weekday_num, v.day_name, v.rider_type, d.n_days;

-- Q3 daily rhythm: average rides per day by start hour, weekday vs weekend/holiday
CREATE OR REPLACE TABLE a_hourly AS
WITH days AS (SELECT day_type, COUNT(*) AS n_days FROM dim_date GROUP BY day_type)
SELECT v.day_type, v.start_hour AS hour, v.rider_type, COUNT(*) AS rides, d.n_days, ROUND(COUNT(*) / d.n_days, 1) AS rides_per_day
FROM v_ride v JOIN days d ON v.day_type = d.day_type GROUP BY v.day_type, v.start_hour, v.rider_type, d.n_days;

CREATE OR REPLACE TABLE a_heatmap AS
SELECT weekday_num, day_name, start_hour AS hour, COUNT(*) AS rides,
       ROUND(100.0 * SUM(CASE WHEN rider_type = 'casual' THEN 1 ELSE 0 END) / COUNT(*), 1) AS casual_share_pct
FROM v_ride GROUP BY weekday_num, day_name, start_hour;

-- Q4 ride length: duration bands
CREATE OR REPLACE TABLE a_duration_bands AS
SELECT rider_type, duration_band, COUNT(*) AS rides,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (PARTITION BY rider_type), 2) AS pct_of_rider_rides
FROM v_ride GROUP BY rider_type, duration_band;

-- Q5 bike choice
CREATE OR REPLACE TABLE a_bike_mix AS
SELECT rider_type, bike_type, COUNT(*) AS rides,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (PARTITION BY rider_type), 2) AS pct_of_rider_rides,
       ROUND(percentile_approx(duration_min, 0.5), 2) AS median_min,
       ROUND(100.0 * SUM(is_dockless_start) / COUNT(*), 2) AS dockless_start_pct,
       ROUND(100.0 * SUM(is_dockless_end) / COUNT(*), 2) AS dockless_end_pct
FROM v_ride GROUP BY rider_type, bike_type;

-- Q6 where: busiest start stations for each rider type, and the stations where casual riders dominate
CREATE OR REPLACE TABLE a_station_stats AS
SELECT s.station_key, s.station_name, s.station_type, s.zone, s.lat, s.lng, s.dist_to_loop_km,
       COUNT(*) AS starts,
       SUM(CASE WHEN f.rider_type_key = 1 THEN 1 ELSE 0 END) AS member_starts,
       SUM(CASE WHEN f.rider_type_key = 2 THEN 1 ELSE 0 END) AS casual_starts,
       ROUND(100.0 * SUM(CASE WHEN f.rider_type_key = 2 THEN 1 ELSE 0 END) / COUNT(*), 2) AS casual_share_pct,
       ROUND(100.0 * SUM(f.is_round_trip) / COUNT(*), 2) AS round_trip_pct,
       ROUND(100.0 * SUM(CASE WHEN f.rider_type_key = 2 AND d.is_weekend = 0 AND d.is_holiday = 0 THEN 1 ELSE 0 END)
             / NULLIF(SUM(CASE WHEN f.rider_type_key = 2 THEN 1 ELSE 0 END), 0), 2) AS casual_weekday_pct
FROM fact_ride f JOIN dim_station s ON f.start_station_key = s.station_key JOIN dim_date d ON f.date_key = d.date_key
WHERE f.start_station_key > 0
GROUP BY s.station_key, s.station_name, s.station_type, s.zone, s.lat, s.lng, s.dist_to_loop_km;

CREATE OR REPLACE TABLE a_top_stations AS
SELECT * FROM (
  SELECT 'casual' AS rider_type, ROW_NUMBER() OVER (ORDER BY casual_starts DESC, station_name) AS rnk, station_name, zone,
         casual_starts AS rides, starts AS all_starts, casual_share_pct, round_trip_pct FROM a_station_stats
  UNION ALL
  SELECT 'member', ROW_NUMBER() OVER (ORDER BY member_starts DESC, station_name), station_name, zone,
         member_starts, starts, casual_share_pct, round_trip_pct FROM a_station_stats
) x WHERE rnk <= 15;

-- casual hot spots: stations with >= 5,000 starts ranked by casual share
CREATE OR REPLACE TABLE a_casual_hotspots AS
SELECT ROW_NUMBER() OVER (ORDER BY casual_share_pct DESC, station_name) AS rnk, station_name, zone, starts, casual_starts,
       casual_share_pct, round_trip_pct, casual_weekday_pct
FROM a_station_stats WHERE starts >= 5000;

-- station map (stations with >= 500 starts): position, volume and casual share
CREATE OR REPLACE TABLE a_station_map AS
SELECT station_name, station_type, zone, lat, lng, starts, casual_share_pct
FROM a_station_stats WHERE starts >= 500;

-- Q6 geography: where rides start, by distance from the Loop (dockless e-bike starts are their own group)
CREATE OR REPLACE TABLE a_zone AS
SELECT s.zone, r.rider_type, COUNT(*) AS rides,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (PARTITION BY r.rider_type), 2) AS pct_of_rider_rides
FROM fact_ride f JOIN dim_station s ON f.start_station_key = s.station_key JOIN dim_rider_type r ON f.rider_type_key = r.rider_type_key
GROUP BY s.zone, r.rider_type;

-- Q7 popular routes (station to station, round trips separately)
CREATE OR REPLACE TABLE a_top_routes AS
WITH r AS (
  SELECT r.rider_type, f.start_station_key, f.end_station_key, COUNT(*) AS rides, ROUND(percentile_approx(f.duration_min, 0.5), 1) AS median_min
  FROM fact_ride f JOIN dim_rider_type r ON f.rider_type_key = r.rider_type_key
  WHERE f.start_station_key > 0 AND f.end_station_key > 0
  GROUP BY r.rider_type, f.start_station_key, f.end_station_key
), k AS (
  SELECT r.*, ROW_NUMBER() OVER (PARTITION BY rider_type ORDER BY rides DESC, start_station_key, end_station_key) AS rnk FROM r
)
SELECT k.rider_type, k.rnk, s.station_name AS start_station, e.station_name AS end_station,
       CASE WHEN k.start_station_key = k.end_station_key THEN 1 ELSE 0 END AS is_round_trip, k.rides, k.median_min
FROM k JOIN dim_station s ON k.start_station_key = s.station_key JOIN dim_station e ON k.end_station_key = e.station_key
WHERE k.rnk <= 10;

-- Q8 weather: daily rides vs temperature and rain
CREATE OR REPLACE TABLE a_daily AS
SELECT d.date, d.day_name, d.day_type, d.season, d.temp_mean_c, d.precip_mm, d.snowfall_cm, d.weather_type, d.holiday_name,
       SUM(CASE WHEN f.rider_type_key = 1 THEN 1 ELSE 0 END) AS member_rides,
       SUM(CASE WHEN f.rider_type_key = 2 THEN 1 ELSE 0 END) AS casual_rides,
       COUNT(f.ride_id) AS rides
FROM dim_date d LEFT JOIN fact_ride f ON f.date_key = d.date_key
GROUP BY d.date, d.day_name, d.day_type, d.season, d.temp_mean_c, d.precip_mm, d.snowfall_cm, d.weather_type, d.holiday_name;

-- linear fit of daily rides on mean temperature (slope = extra rides per +1 C), and the correlation
CREATE OR REPLACE TABLE a_weather_fit AS
SELECT 'member' AS rider_type, COUNT(*) AS n_days, ROUND(corr(temp_mean_c, member_rides), 3) AS corr_temp,
       ROUND(covar_pop(temp_mean_c, member_rides) / var_pop(temp_mean_c), 1) AS rides_per_deg_c,
       ROUND(AVG(member_rides) - covar_pop(temp_mean_c, member_rides) / var_pop(temp_mean_c) * AVG(temp_mean_c), 1) AS intercept
FROM a_daily
UNION ALL
SELECT 'casual', COUNT(*), ROUND(corr(temp_mean_c, casual_rides), 3), ROUND(covar_pop(temp_mean_c, casual_rides) / var_pop(temp_mean_c), 1),
       ROUND(AVG(casual_rides) - covar_pop(temp_mean_c, casual_rides) / var_pop(temp_mean_c) * AVG(temp_mean_c), 1)
FROM a_daily;

CREATE OR REPLACE TABLE a_temp_bands AS
SELECT d.temp_band, COUNT(*) AS n_days,
       ROUND(AVG(a.member_rides), 0) AS member_rides_per_day, ROUND(AVG(a.casual_rides), 0) AS casual_rides_per_day,
       ROUND(100.0 * SUM(a.casual_rides) / SUM(a.rides), 2) AS casual_share_pct
FROM a_daily a JOIN dim_date d ON a.date = d.date GROUP BY d.temp_band;

-- rain effect within the warm season (May-Sep, so temperature and daylight are comparable): dry vs wet days, weekday vs weekend
CREATE OR REPLACE TABLE a_rain_effect AS
SELECT a.day_type, CASE WHEN a.precip_mm >= 5 THEN '3 heavy rain (5 mm+)' WHEN a.precip_mm >= 1 THEN '2 light rain (1-5 mm)' ELSE '1 dry (< 1 mm)' END AS rain_class,
       COUNT(*) AS n_days, ROUND(AVG(a.temp_mean_c), 1) AS avg_temp_c,
       ROUND(AVG(a.member_rides), 0) AS member_rides_per_day, ROUND(AVG(a.casual_rides), 0) AS casual_rides_per_day
FROM a_daily a WHERE month(a.date) BETWEEN 5 AND 9
GROUP BY a.day_type, CASE WHEN a.precip_mm >= 5 THEN '3 heavy rain (5 mm+)' WHEN a.precip_mm >= 1 THEN '2 light rain (1-5 mm)' ELSE '1 dry (< 1 mm)' END;

-- holidays vs ordinary weekdays and weekends (avg rides per day)
CREATE OR REPLACE TABLE a_day_kind AS
SELECT CASE WHEN d.is_holiday = 1 THEN 'Federal holiday' WHEN d.is_weekend = 1 THEN 'Weekend' ELSE 'Ordinary weekday' END AS day_kind,
       COUNT(*) AS n_days, ROUND(AVG(a.member_rides), 0) AS member_rides_per_day, ROUND(AVG(a.casual_rides), 0) AS casual_rides_per_day,
       ROUND(100.0 * SUM(a.casual_rides) / SUM(a.rides), 2) AS casual_share_pct
FROM a_daily a JOIN dim_date d ON a.date = d.date
GROUP BY CASE WHEN d.is_holiday = 1 THEN 'Federal holiday' WHEN d.is_weekend = 1 THEN 'Weekend' ELSE 'Ordinary weekday' END;

-- Q9 conversion targets: casual riders whose rides look like member rides (weekday commute hours, under 20 minutes, station to station)
CREATE OR REPLACE TABLE a_conversion AS
SELECT COUNT(*) AS casual_rides,
       SUM(CASE WHEN day_type = 'Weekday' AND (start_hour BETWEEN 7 AND 9 OR start_hour BETWEEN 16 AND 18) THEN 1 ELSE 0 END) AS weekday_commute_hour_rides,
       SUM(CASE WHEN day_type = 'Weekday' AND (start_hour BETWEEN 7 AND 9 OR start_hour BETWEEN 16 AND 18)
                 AND duration_min < 20 AND is_round_trip = 0 THEN 1 ELSE 0 END) AS commute_like_rides,
       ROUND(100.0 * SUM(CASE WHEN day_type = 'Weekday' AND (start_hour BETWEEN 7 AND 9 OR start_hour BETWEEN 16 AND 18)
                 AND duration_min < 20 AND is_round_trip = 0 THEN 1 ELSE 0 END) / COUNT(*), 2) AS commute_like_pct,
       SUM(CASE WHEN duration_min > 45 THEN 1 ELSE 0 END) AS rides_over_45_min,
       ROUND(100.0 * SUM(CASE WHEN duration_min > 45 THEN 1 ELSE 0 END) / COUNT(*), 2) AS over_45_min_pct
FROM v_ride WHERE rider_type = 'casual';

-- headline KPIs (one row)
CREATE OR REPLACE TABLE a_kpi_headline AS
WITH m AS (SELECT * FROM a_rider_profile WHERE rider_type = 'member'), c AS (SELECT * FROM a_rider_profile WHERE rider_type = 'casual'),
dmax AS (SELECT date, rides FROM a_daily ORDER BY rides DESC, date LIMIT 1),
dmin AS (SELECT date, rides FROM a_daily ORDER BY rides, date LIMIT 1),
sm AS (SELECT * FROM a_season WHERE season = 'Summer'), sw AS (SELECT * FROM a_season WHERE season = 'Winter'),
wfm AS (SELECT * FROM a_weather_fit WHERE rider_type = 'member'), wfc AS (SELECT * FROM a_weather_fit WHERE rider_type = 'casual')
SELECT
  (SELECT COUNT(*) FROM stg_trips) AS raw_rows,
  (SELECT COUNT(*) FROM cln_trips) AS distinct_rides,
  (SELECT COUNT(*) FROM stg_trips) - (SELECT COUNT(*) FROM cln_trips) AS duplicate_rows_removed,
  (SELECT COUNT(*) FROM fact_ride) AS valid_rides,
  (SELECT COUNT(*) FROM cln_trips WHERE is_valid = 0) AS invalid_rides,
  ROUND(100.0 * (SELECT COUNT(*) FROM fact_ride) / (SELECT COUNT(*) FROM cln_trips), 2) AS valid_pct,
  (SELECT min(date) FROM dim_date) AS first_date, (SELECT max(date) FROM dim_date) AS last_date,
  (SELECT COUNT(*) FROM dim_date) AS days,
  ROUND((SELECT COUNT(*) FROM fact_ride) / (SELECT COUNT(*) FROM dim_date), 0) AS avg_rides_per_day,
  (SELECT date FROM dmax) AS busiest_date, (SELECT rides FROM dmax) AS busiest_date_rides,
  (SELECT date FROM dmin) AS quietest_date, (SELECT rides FROM dmin) AS quietest_date_rides,
  m.rides AS member_rides, c.rides AS casual_rides, m.ride_share_pct AS member_share_pct, c.ride_share_pct AS casual_share_pct,
  c.ride_minutes_share_pct AS casual_ride_minutes_share_pct,
  m.median_min AS member_median_min, c.median_min AS casual_median_min, m.mean_min AS member_mean_min, c.mean_min AS casual_mean_min,
  m.median_km_station_to_station AS member_median_km, c.median_km_station_to_station AS casual_median_km,
  m.median_kmh_station_to_station AS member_median_kmh, c.median_kmh_station_to_station AS casual_median_kmh,
  m.ebike_pct AS member_ebike_pct, c.ebike_pct AS casual_ebike_pct,
  ROUND(100.0 * (SELECT COUNT(*) FROM fact_ride WHERE bike_type_key = 2) / (SELECT COUNT(*) FROM fact_ride), 2) AS ebike_pct,
  m.round_trip_pct AS member_round_trip_pct, c.round_trip_pct AS casual_round_trip_pct,
  m.weekend_holiday_pct AS member_weekend_pct, c.weekend_holiday_pct AS casual_weekend_pct,
  m.over_45_min_pct AS member_over_45_min_pct, c.over_45_min_pct AS casual_over_45_min_pct,
  m.weekday_commute_hours_pct AS member_commute_hours_pct, c.weekday_commute_hours_pct AS casual_commute_hours_pct,
  ROUND(100.0 * (SELECT SUM(is_dockless_start) FROM fact_ride) / (SELECT COUNT(*) FROM fact_ride), 2) AS dockless_start_pct,
  (SELECT COUNT(*) FROM a_station_stats) AS stations_with_starts,
  (SELECT COUNT(*) FROM dim_station WHERE station_type = 'Dock') AS docking_stations,
  (SELECT COUNT(*) FROM dim_station WHERE station_type = 'Public rack') AS public_racks,
  sm.member_rides_per_day AS summer_member_per_day, sw.member_rides_per_day AS winter_member_per_day,
  sm.casual_rides_per_day AS summer_casual_per_day, sw.casual_rides_per_day AS winter_casual_per_day,
  ROUND(sm.member_rides_per_day / sw.member_rides_per_day, 2) AS member_summer_winter_ratio,
  ROUND(sm.casual_rides_per_day / sw.casual_rides_per_day, 2) AS casual_summer_winter_ratio,
  wfm.corr_temp AS member_corr_temp, wfc.corr_temp AS casual_corr_temp,
  wfm.rides_per_deg_c AS member_rides_per_deg_c, wfc.rides_per_deg_c AS casual_rides_per_deg_c,
  (SELECT commute_like_rides FROM a_conversion) AS casual_commute_like_rides,
  (SELECT commute_like_pct FROM a_conversion) AS casual_commute_like_pct
FROM m CROSS JOIN c CROSS JOIN sm CROSS JOIN sw CROSS JOIN wfm CROSS JOIN wfc;
