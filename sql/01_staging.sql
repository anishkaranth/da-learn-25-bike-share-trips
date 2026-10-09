-- 01_staging.sql  Land the raw files as all-text staging tables (no cleaning yet).
-- DuckDB: read_csv(..., all_varchar = true, filename = true). On Databricks use
--   SELECT *, regexp_extract(_metadata.file_name, '([0-9]{6})-divvy-tripdata', 1) AS source_month
--   FROM read_files('/Volumes/workspace/da_learn_25/raw/*-divvy-tripdata.csv', format => 'csv', header => true, inferSchema => false)
-- which gives the same 13 column names, all typed STRING, plus the month of the file each row came from.

-- 12 monthly files YYYYMM-divvy-tripdata.csv (Oct 2025 - Sep 2026): one row per ride, 13 columns
CREATE OR REPLACE TABLE stg_trips AS
SELECT * EXCLUDE (filename), regexp_extract(filename, '([0-9]{6})-divvy-tripdata', 1) AS source_month
FROM read_csv('{{RAW_DIR}}/*-divvy-tripdata.csv', header = true, all_varchar = true, filename = true, union_by_name = true);

-- references (data/reference/): Chicago daily weather (Open-Meteo historical archive, Loop grid cell, local days)
-- and US federal holidays in the window (hand-made, 12 rows)
CREATE OR REPLACE TABLE ref_weather AS
SELECT * FROM read_csv('{{REF_DIR}}/chicago_weather_daily.csv', header = true, all_varchar = true);
CREATE OR REPLACE TABLE ref_holidays AS
SELECT * FROM read_csv('{{REF_DIR}}/us_holidays.csv', header = true, all_varchar = true);
