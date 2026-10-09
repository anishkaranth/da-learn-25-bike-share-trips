-- 00_duckdb_compat.sql  (DuckDB ONLY - do NOT run on Databricks)
-- Spark / Databricks SQL function shims so that 01-05 can be written in Spark SQL dialect and still run unchanged on DuckDB.
-- On Databricks these functions are built in (only the argument patterns used in this project are supported here).
CREATE OR REPLACE MACRO regexp_like(s, p) AS regexp_matches(s, p);
CREATE OR REPLACE MACRO percentile_approx(x, p) AS quantile_cont(x, p);
-- Spark unix_timestamp(ts) = whole seconds since epoch (milliseconds dropped), same here
CREATE OR REPLACE MACRO unix_timestamp(ts) AS CAST(floor(epoch(ts)) AS BIGINT);
-- Spark weekday(d) = 0 Monday .. 6 Sunday (DuckDB's own weekday() is 0 = Sunday, so it is overridden here)
CREATE OR REPLACE MACRO weekday(d) AS isodow(d) - 1;
-- Spark date_format(ts, 'yyyy-MM') / 'yyyy-MM-dd'
CREATE OR REPLACE MACRO date_format(d, f) AS strftime(d, replace(replace(replace(f, 'yyyy', '%Y'), 'MM', '%m'), 'dd', '%d'));
-- Project function: great-circle distance in km. On Databricks create the same SQL UDF once:
--   CREATE OR REPLACE TEMPORARY FUNCTION haversine_km(lat1 DOUBLE, lng1 DOUBLE, lat2 DOUBLE, lng2 DOUBLE) RETURNS DOUBLE
--   RETURN 2 * 6371.0088 * asin(sqrt(pow(sin(radians(lat2 - lat1) / 2), 2) + cos(radians(lat1)) * cos(radians(lat2)) * pow(sin(radians(lng2 - lng1) / 2), 2)));
CREATE OR REPLACE MACRO haversine_km(lat1, lng1, lat2, lng2) AS
  2 * 6371.0088 * asin(sqrt(pow(sin(radians(lat2 - lat1) / 2), 2) + cos(radians(lat1)) * cos(radians(lat2)) * pow(sin(radians(lng2 - lng1) / 2), 2)));
