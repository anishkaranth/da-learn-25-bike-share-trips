#!/usr/bin/env python3
"""Build the git-sized raw sample data/raw/ from data/raw_full/ (deterministic, no randomness).

Rows kept (lines copied byte-for-byte in the original order, same header and quoting, same 12 file names):
  * every ride whose ride_id ends in '00' (1/256 of rides, ~0.4%)
  * every edge case the cleaning rules handle, so the sample exercises them: rides published in two monthly files (both copies),
    negative durations (2 Nov 2025 DST end), test / depot / warehouse stations, rides that started before 1 Oct 2025, rides outside
    the service-area box, rides with a trailing '*' / double space in a station name or a leading space in a station id,
    and the first 40 (by ride_id) rides over 24 h and rides with no end location."""
import csv, pathlib, sys
import duckdb

ROOT = pathlib.Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))
import project
SRC, OUT = ROOT / "data/raw_full", ROOT / "data/raw"
OUT.mkdir(parents=True, exist_ok=True)
con = duckdb.connect()
con.execute(f"CREATE TABLE t AS SELECT * FROM read_csv('{SRC.as_posix()}/*-divvy-tripdata.csv', header = true, all_varchar = true)")
lat_bad = "(TRY_CAST({c}_lat AS DOUBLE) NOT BETWEEN 41.60 AND 42.10 OR TRY_CAST({c}_lng AS DOUBLE) NOT BETWEEN -87.95 AND -87.50)"
special = set(r[0] for r in con.execute(f"""
  SELECT ride_id FROM t GROUP BY ride_id HAVING COUNT(*) > 1
  UNION SELECT ride_id FROM t WHERE CAST(ended_at AS TIMESTAMP) < CAST(started_at AS TIMESTAMP)
  UNION SELECT ride_id FROM t WHERE regexp_matches(upper(COALESCE(start_station_name, '') || '|' || COALESCE(end_station_name, '')), 'TEST|DEPOT|WAREHOUSE|REPAIR')
  UNION SELECT ride_id FROM t WHERE CAST(started_at AS TIMESTAMP) < TIMESTAMP '2025-10-01'
  UNION SELECT ride_id FROM t WHERE {lat_bad.format(c='start')} OR {lat_bad.format(c='end')}
  UNION SELECT ride_id FROM (SELECT ride_id FROM t WHERE start_station_name LIKE '%*' OR start_station_name LIKE '%  %' OR start_station_id LIKE ' %'
                             ORDER BY ride_id LIMIT 60)
  UNION SELECT ride_id FROM (SELECT ride_id FROM t WHERE epoch(CAST(ended_at AS TIMESTAMP) - CAST(started_at AS TIMESTAMP)) > 86400 ORDER BY ride_id LIMIT 40)
  UNION SELECT ride_id FROM (SELECT ride_id FROM t WHERE end_lat IS NULL ORDER BY ride_id LIMIT 40)
""").fetchall())
tot = kept = 0
for name in project.RAW_FILES:
    lines = (SRC / name).read_text(encoding="utf-8").splitlines(keepends=True)
    n = 0
    with open(OUT / name, "w", encoding="utf-8", newline="") as fo:
        fo.write(lines[0])
        for ln in lines[1:]:
            rid = ln[1:17] if ln.startswith('"') else ln.split(",", 1)[0]
            if rid.endswith("00") or rid in special:
                fo.write(ln); n += 1
    tot += len(lines) - 1; kept += n
    print(f"{name}: {n:,} of {len(lines) - 1:,} rows, {(OUT / name).stat().st_size:,} B")
print(f"sample: {kept:,} of {tot:,} rows ({100 * kept / tot:.2f}%), {len(special):,} edge-case ride_ids")
