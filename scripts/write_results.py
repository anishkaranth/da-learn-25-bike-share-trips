#!/usr/bin/env python3
"""Write results/RESULTS.md from results/metrics.json + results/tables/*.csv (every number comes from the full-data run)."""
import csv, json, pathlib

ROOT = pathlib.Path(__file__).resolve().parents[1]
RES = ROOT / "results"
T = RES / "tables"


def rd(name):
    with open(T / f"{name}.csv", newline="", encoding="utf-8") as fh:
        return list(csv.DictReader(fh))


def f(x):
    return float(x) if x not in ("", None) else 0.0


def i(x):
    return int(f(x))


def num(v):
    if v in ("", None):
        return ""
    try:
        x = float(v)
    except ValueError:
        return str(v).replace("|", "/")
    return f"{int(x):,}" if x.is_integer() and abs(x) >= 1000 else (str(int(x)) if x.is_integer() else f"{x:,.2f}".rstrip("0").rstrip("."))


YEARS = {"year", "year_month", "date", "hour", "rnk", "weekday_num"}


def table(rows, cols, heads=None):
    out = ["| " + " | ".join(heads or cols) + " |", "|" + "---|" * len(cols)]
    for r in rows:
        out.append("| " + " | ".join(str(r[c]) if c in YEARS else num(r[c]) for c in cols) + " |")
    return "\n".join(out)


m = json.loads((RES / "metrics.json").read_text())
k = m["kpis"]
P = {r["rider_type"]: r for r in rd("a_rider_profile")}
mo = sorted(rd("a_monthly"), key=lambda r: r["year_month"]); MO = {r["year_month"]: r for r in mo}
se = {r["season"]: r for r in rd("a_season")}
hr = rd("a_hourly"); HV = {(r["day_type"], i(r["hour"]), r["rider_type"]): f(r["rides_per_day"]) for r in hr}
hm = rd("a_heatmap")
hmin = min(hm, key=lambda r: f(r["casual_share_pct"]) if i(r["rides"]) >= 1000 else 999)
hmax = max(hm, key=lambda r: f(r["casual_share_pct"]) if i(r["rides"]) >= 1000 else -1)
DAYN = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]
dk = {r["day_kind"]: r for r in rd("a_day_kind")}
wf = {r["rider_type"]: r for r in rd("a_weather_fit")}
tb = sorted(rd("a_temp_bands"), key=lambda r: r["temp_band"])
rn = {(r["day_type"], r["rain_class"][0]): r for r in rd("a_rain_effect")}
ts = sorted([r for r in rd("a_top_stations") if r["rider_type"] == "casual"], key=lambda r: i(r["rnk"]))
tsm = sorted([r for r in rd("a_top_stations") if r["rider_type"] == "member"], key=lambda r: i(r["rnk"]))
ch = sorted(rd("a_casual_hotspots"), key=lambda r: i(r["rnk"]))
CH = {r["station_name"]: r for r in ch}
tr = sorted(rd("a_top_routes"), key=lambda r: (r["rider_type"], i(r["rnk"])))
trc = [r for r in tr if r["rider_type"] == "casual"]; trm = [r for r in tr if r["rider_type"] == "member"]
zn = {(r["rider_type"], r["zone"][0]): r for r in rd("a_zone")}
bm = {(r["rider_type"], r["bike_type"]): r for r in rd("a_bike_mix")}
cv = rd("a_conversion")[0]
db = {(r["rider_type"], r["duration_band"][:2]): r for r in rd("a_duration_bands")}
dq_i = rd("dq_issues"); dq_n = rd("dq_null_rates"); dq_r = rd("dq_row_counts"); asr = rd("dq_assertions")
npass = sum(1 for r in asr if r["status"] == "PASS")
DQ = {r["check_name"].split(",")[0].split(" (")[0]: i(r["affected_rows"]) for r in dq_i}
pk = lambda dt, rt: max(range(24), key=lambda h: HV.get((dt, h, rt), 0))
mpm, mpe = max(range(5, 11), key=lambda h: HV[("Weekday", h, "member")]), pk("Weekday", "member")
pch = lambda a, b: 100 * (f(b) / f(a) - 1)
eb0, eb1 = MO[mo[0]["year_month"]], MO[mo[-1]["year_month"]]
cmin = min(mo, key=lambda r: f(r["casual_share_pct"])); cmax = max(mo, key=lambda r: f(r["casual_share_pct"]))

ins = [
    f"**Members ride more often, casual riders ride longer.** Of {i(k['valid_rides']):,} valid rides, annual members took "
    f"{f(k['member_share_pct']):.2f}% ({i(k['member_rides']):,}) and casual riders {f(k['casual_share_pct']):.2f}% ({i(k['casual_rides']):,}), but casual "
    f"riders used {f(k['casual_ride_minutes_share_pct']):.2f}% of all ride minutes. Median ride {f(k['member_median_min']):.2f} min vs "
    f"{f(k['casual_median_min']):.2f} min (mean {f(k['member_mean_min']):.2f} vs {f(k['casual_mean_min']):.2f}); {f(k['casual_over_45_min_pct']):.2f}% of "
    f"casual rides last over 45 minutes vs {f(k['member_over_45_min_pct']):.2f}% of member rides. Station-to-station distances are similar "
    f"(median {f(k['member_median_km']):.2f} vs {f(k['casual_median_km']):.2f} km), so casual riders are slower ({f(k['casual_median_kmh']):.1f} vs "
    f"{f(k['member_median_kmh']):.1f} km/h median straight-line speed) and make {f(k['casual_round_trip_pct']):.2f}% round trips vs {f(k['member_round_trip_pct']):.2f}%: "
    f"they meander, members go from A to B.",
    f"**Members commute, casual riders ride for leisure.** On weekdays member rides peak at {mpm}:00 ({HV[('Weekday', mpm, 'member')]:,.0f} rides per day) and "
    f"{mpe}:00 ({HV[('Weekday', mpe, 'member')]:,.0f}); {f(k['member_commute_hours_pct']):.2f}% of member rides start in weekday 7-9 / 16-18 h vs "
    f"{f(k['casual_commute_hours_pct']):.2f}% of casual rides. {f(k['casual_weekend_pct']):.2f}% of casual rides fall on weekends or holidays "
    f"(members {f(k['member_weekend_pct']):.2f}%); on an average weekend day casual riders take {f(dk['Weekend']['casual_rides_per_day']):,.0f} rides vs "
    f"{f(dk['Weekend']['member_rides_per_day']):,.0f} by members ({f(dk['Weekend']['casual_share_pct']):.1f}% casual, ordinary weekdays "
    f"{f(dk['Ordinary weekday']['casual_share_pct']):.1f}%). The casual share runs from {f(hmin['casual_share_pct']):.1f}% ({DAYN[i(hmin['weekday_num'])]} "
    f"{i(hmin['hour'])}:00) to {f(hmax['casual_share_pct']):.1f}% ({DAYN[i(hmax['weekday_num'])]} {i(hmax['hour'])}:00).",
    f"**Casual demand is far more seasonal and weather-driven.** Summer vs winter rides per day: members {f(se['Summer']['member_rides_per_day']):,.0f} vs "
    f"{f(se['Winter']['member_rides_per_day']):,.0f} (x{f(k['member_summer_winter_ratio']):.2f}), casual riders {f(se['Summer']['casual_rides_per_day']):,.0f} vs "
    f"{f(se['Winter']['casual_rides_per_day']):,.0f} (x{f(k['casual_summer_winter_ratio']):.2f}). The casual share of rides goes from "
    f"{f(cmin['casual_share_pct']):.2f}% ({cmin['year_month']}) to {f(cmax['casual_share_pct']):.2f}% ({cmax['year_month']}). Daily rides correlate with mean "
    f"temperature at {f(wf['member']['corr_temp']):.3f} (members) and {f(wf['casual']['corr_temp']):.3f} (casual); each +1 C adds about "
    f"{f(wf['member']['rides_per_deg_c']):.0f} member and {f(wf['casual']['rides_per_deg_c']):.0f} casual rides a day. Below -5 C ({i(tb[0]['n_days'])} days) "
    f"casual riders average {f(tb[0]['casual_rides_per_day']):,.0f} rides a day; at 20-25 C ({i(tb[6]['n_days'])} days) {f(tb[6]['casual_rides_per_day']):,.0f}. "
    f"In May-Sep, heavy-rain days (5 mm+) cut weekend casual rides from {f(rn[('Weekend / holiday', '1')]['casual_rides_per_day']):,.0f} to "
    f"{f(rn[('Weekend / holiday', '3')]['casual_rides_per_day']):,.0f} a day ({pch(rn[('Weekend / holiday', '1')]['casual_rides_per_day'], rn[('Weekend / holiday', '3')]['casual_rides_per_day']):.0f}%) "
    f"and weekday member rides from {f(rn[('Weekday', '1')]['member_rides_per_day']):,.0f} to {f(rn[('Weekday', '3')]['member_rides_per_day']):,.0f} "
    f"({pch(rn[('Weekday', '1')]['member_rides_per_day'], rn[('Weekday', '3')]['member_rides_per_day']):.0f}%).",
    f"**Casual riders cluster on the lakefront.** The top casual start station is {ts[0]['station_name']} ({i(ts[0]['rides']):,} casual starts, "
    f"{f(ts[0]['casual_share_pct']):.1f}% casual), then {ts[1]['station_name']} ({i(ts[1]['rides']):,}) and {ts[2]['station_name']} ({i(ts[2]['rides']):,}). "
    f"Among {len(ch)} stations with at least 5,000 starts the most casual are {ch[0]['station_name']} ({f(ch[0]['casual_share_pct']):.1f}%), "
    f"{ch[1]['station_name']} ({f(ch[1]['casual_share_pct']):.1f}%) and {ch[2]['station_name']} ({f(ch[2]['casual_share_pct']):.1f}%). The busiest casual route is "
    f"a {trc[0]['start_station']} round trip ({i(trc[0]['rides']):,} rides, median {f(trc[0]['median_min']):.0f} min); the busiest member routes are short hops "
    f"around the University of Chicago ({trm[0]['start_station']} -> {trm[0]['end_station']}, {i(trm[0]['rides']):,} rides, median {f(trm[0]['median_min']):.0f} min). "
    f"Distance from the Loop does not separate the groups: {f(zn[('member', '1')]['pct_of_rider_rides']):.1f}% of member and "
    f"{f(zn[('casual', '1')]['pct_of_rider_rides']):.1f}% of casual rides start within 3 km of State & Madison.",
    f"**A concrete membership target.** {i(cv['commute_like_rides']):,} casual rides ({f(cv['commute_like_pct']):.2f}% of casual rides) already look like member "
    f"rides: weekday 7-9 / 16-18 h, under 20 minutes, station to station. Those riders, plus summer-weekend visitors at the lakefront stations above, are the "
    f"natural audience for a commuter membership and a weekend / seasonal pass respectively; campaigns should run April-June, before the casual peak in "
    f"{cmax['year_month']}.",
    f"**E-bikes are now the default.** E-bikes carried {f(k['ebike_pct']):.2f}% of valid rides ({f(k['casual_ebike_pct']):.2f}% of casual, "
    f"{f(k['member_ebike_pct']):.2f}% of member rides), up from {f(eb0['ebike_pct']):.2f}% in {eb0['year_month']} to {f(eb1['ebike_pct']):.2f}% in "
    f"{eb1['year_month']}. {f(bm[('member', 'electric_bike')]['dockless_start_pct']):.1f}% of member and {f(bm[('casual', 'electric_bike')]['dockless_start_pct']):.1f}% "
    f"of casual e-bike rides start away from any dock ({f(k['dockless_start_pct']):.2f}% of all rides). Classic bikes are kept for longer casual rides "
    f"(median {f(bm[('casual', 'classic_bike')]['median_min']):.1f} min vs {f(bm[('casual', 'electric_bike')]['median_min']):.1f} on e-bikes).",
    f"**Cleaning mattered.** {i(k['raw_rows']):,} raw rows -> {i(k['distinct_rides']):,} distinct rides ({i(k['duplicate_rows_removed'])} rides were published "
    f"in both the April and May 2026 files) -> {i(k['valid_rides']):,} valid rides ({f(k['valid_pct']):.2f}%). The {i(k['invalid_rides']):,} invalid rides are "
    f"mostly false starts under 60 s ({DQ['rides under 60 s']:,}), plus rides over 24 h, rides with no end location, test/depot stations, the 30 Sep 2025 "
    f"spill-over, out-of-area and > 45 km/h rides. {DQ['negative durations in the repeated 1 AM hour of 2 Nov 2025']} rides had negative durations "
    f"only because clocks went back on 2 Nov 2025 and were fixed. {npass}/{len(asr)} assertions pass.",
]

md = f"""# RESULTS · da-learn-25 · Bike-share trips (Divvy Chicago, Oct 2025 - Sep 2026)

All numbers below come from the **full** dataset ({i(k['raw_rows']):,} raw rides in 12 monthly files) run through `sql/01`-`sql/05` on DuckDB
({m['engine']['duckdb']}); nothing is estimated or hand-typed. Databricks was skipped because the workspace hit its resource quota, so there is no
live Lakeview dashboard; the SQL stays Databricks-compatible. Charts: `results/images/` (SVG + PNG).

![Dashboard](images/dashboard.png)

## Headline KPIs
| KPI | Value |
|---|---|
| Raw rows / distinct rides / valid rides | {i(k['raw_rows']):,} / {i(k['distinct_rides']):,} / {i(k['valid_rides']):,} ({f(k['valid_pct']):.2f}%) |
| Window | {k['first_date']} to {k['last_date']} ({i(k['days'])} days), Chicago local time |
| Average / busiest / quietest day | {i(k['avg_rides_per_day']):,} / {k['busiest_date']} ({i(k['busiest_date_rides']):,}) / {k['quietest_date']} ({i(k['quietest_date_rides']):,}) |
| Member / casual rides | {i(k['member_rides']):,} ({f(k['member_share_pct']):.2f}%) / {i(k['casual_rides']):,} ({f(k['casual_share_pct']):.2f}%) |
| Casual share of ride minutes | {f(k['casual_ride_minutes_share_pct']):.2f}% |
| Median / mean ride, member vs casual | {f(k['member_median_min']):.2f} / {f(k['member_mean_min']):.2f} min vs {f(k['casual_median_min']):.2f} / {f(k['casual_mean_min']):.2f} min |
| Rides over 45 min, member vs casual | {f(k['member_over_45_min_pct']):.2f}% vs {f(k['casual_over_45_min_pct']):.2f}% |
| Weekend / holiday share, member vs casual | {f(k['member_weekend_pct']):.2f}% vs {f(k['casual_weekend_pct']):.2f}% |
| Weekday commute-hour share (7-9, 16-18 h), member vs casual | {f(k['member_commute_hours_pct']):.2f}% vs {f(k['casual_commute_hours_pct']):.2f}% |
| Round trips, member vs casual | {f(k['member_round_trip_pct']):.2f}% vs {f(k['casual_round_trip_pct']):.2f}% |
| E-bike share (all / member / casual) | {f(k['ebike_pct']):.2f}% / {f(k['member_ebike_pct']):.2f}% / {f(k['casual_ebike_pct']):.2f}% |
| Dockless e-bike starts | {f(k['dockless_start_pct']):.2f}% of valid rides |
| Stations with starts / docks / public racks | {i(k['stations_with_starts']):,} / {i(k['docking_stations']):,} / {i(k['public_racks']):,} |
| Summer / winter rides per day: member, casual | {i(k['summer_member_per_day']):,} / {i(k['winter_member_per_day']):,} (x{f(k['member_summer_winter_ratio']):.2f}); {i(k['summer_casual_per_day']):,} / {i(k['winter_casual_per_day']):,} (x{f(k['casual_summer_winter_ratio']):.2f}) |
| Daily rides vs temperature: corr, rides per +1 C | member {f(k['member_corr_temp']):.3f}, +{f(k['member_rides_per_deg_c']):.0f}; casual {f(k['casual_corr_temp']):.3f}, +{f(k['casual_rides_per_deg_c']):.0f} |
| Commute-like casual rides (conversion target) | {i(k['casual_commute_like_rides']):,} ({f(k['casual_commute_like_pct']):.2f}% of casual rides) |
| Assertions | {npass}/{len(asr)} PASS |

## Insights
""" + "\n".join(f"{n}. {t}" for n, t in enumerate(ins, 1)) + f"""

## Members vs casual riders
![Rider profile](images/rider_profile.png)
![Ride length](images/duration_bands.png)
![Bike mix](images/bike_mix.png)

{table(sorted(rd('a_rider_profile'), key=lambda r: r['rider_type'], reverse=True), ['rider_type', 'rides', 'ride_share_pct', 'ride_hours', 'ride_minutes_share_pct',
       'median_min', 'mean_min', 'p90_min', 'median_km_station_to_station', 'median_kmh_station_to_station', 'ebike_pct', 'round_trip_pct', 'weekend_holiday_pct',
       'dockless_start_pct', 'over_45_min_pct'],
       ['Rider', 'Rides', '% rides', 'Ride hours', '% minutes', 'Median min', 'Mean min', 'P90 min', 'Median km', 'Median km/h', 'E-bike %', 'Round trip %',
        'Weekend %', 'Dockless start %', '> 45 min %'])}

{table(sorted(rd('a_duration_bands'), key=lambda r: (r['rider_type'], r['duration_band'])), ['rider_type', 'duration_band', 'rides', 'pct_of_rider_rides'],
       ['Rider', 'Duration band', 'Rides', '% of rider rides'])}

{table(sorted(rd('a_bike_mix'), key=lambda r: (r['rider_type'], r['bike_type'])), ['rider_type', 'bike_type', 'rides', 'pct_of_rider_rides', 'median_min',
       'dockless_start_pct', 'dockless_end_pct'], ['Rider', 'Bike', 'Rides', '% of rider rides', 'Median min', 'Dockless start %', 'Dockless end %'])}

## Seasonality and weather
![Monthly rides](images/monthly_rides.png)
![Daily trend](images/daily_trend.png)
![Seasonal swing](images/seasonal_swing.png)
![Daily rides vs temperature](images/weather_scatter.png)
![Temperature bands](images/temp_bands.png)
![Rain effect](images/rain_effect.png)

{table(mo, ['year_month', 'member_rides', 'casual_rides', 'rides', 'casual_share_pct', 'member_median_min', 'casual_median_min', 'ebike_pct', 'ride_weighted_temp_c'],
       ['Month', 'Member rides', 'Casual rides', 'Rides', 'Casual %', 'Member median min', 'Casual median min', 'E-bike %', 'Ride-weighted temp C'])}

{table(sorted(rd('a_season'), key=lambda r: f(r['avg_temp_c'])), ['season', 'n_days', 'avg_temp_c', 'member_rides_per_day', 'casual_rides_per_day', 'casual_share_pct'],
       ['Season', 'Days', 'Avg temp C', 'Member rides/day', 'Casual rides/day', 'Casual %'])}

{table(tb, ['temp_band', 'n_days', 'member_rides_per_day', 'casual_rides_per_day', 'casual_share_pct'], ['Temperature band', 'Days', 'Member rides/day', 'Casual rides/day', 'Casual %'])}

{table(sorted(rd('a_rain_effect'), key=lambda r: (r['day_type'], r['rain_class'])), ['day_type', 'rain_class', 'n_days', 'avg_temp_c', 'member_rides_per_day', 'casual_rides_per_day'],
       ['Day type (May-Sep)', 'Rain', 'Days', 'Avg temp C', 'Member rides/day', 'Casual rides/day'])}

{table(rd('a_weather_fit'), ['rider_type', 'n_days', 'corr_temp', 'rides_per_deg_c', 'intercept'], ['Rider', 'Days', 'corr(temp, rides)', 'Rides per +1 C', 'Rides at 0 C (fit)'])}

## Weekly and daily rhythm
![Hourly profile](images/hourly_profile.png)
![Weekday rides](images/weekday_rides.png)
![Demand heatmap](images/demand_heatmap.png)
![Casual share heatmap](images/casual_share_heatmap.png)

{table(sorted(rd('a_weekday'), key=lambda r: (i(r['weekday_num']), r['rider_type'])), ['day_name', 'rider_type', 'rides', 'n_days', 'rides_per_day', 'median_min'],
       ['Day', 'Rider', 'Rides', 'Days', 'Rides/day', 'Median min'])}

{table(sorted(rd('a_day_kind'), key=lambda r: r['day_kind']), ['day_kind', 'n_days', 'member_rides_per_day', 'casual_rides_per_day', 'casual_share_pct'],
       ['Day kind', 'Days', 'Member rides/day', 'Casual rides/day', 'Casual %'])}

## Stations and routes
![Station map](images/station_map.png)
![Top casual stations](images/top_casual_stations.png)
![Casual hotspots](images/casual_hotspots.png)
![Top routes](images/top_routes.png)

{table(ts, ['rnk', 'station_name', 'zone', 'rides', 'all_starts', 'casual_share_pct', 'round_trip_pct'], ['#', 'Station (casual top 15)', 'Zone', 'Casual starts', 'All starts', 'Casual %', 'Round trip %'])}

{table(tsm, ['rnk', 'station_name', 'zone', 'rides', 'all_starts', 'casual_share_pct', 'round_trip_pct'], ['#', 'Station (member top 15)', 'Zone', 'Member starts', 'All starts', 'Casual %', 'Round trip %'])}

{table(ch[:12], ['rnk', 'station_name', 'zone', 'starts', 'casual_starts', 'casual_share_pct', 'round_trip_pct', 'casual_weekday_pct'],
       ['#', 'Station (>= 5,000 starts)', 'Zone', 'Starts', 'Casual starts', 'Casual %', 'Round trip %', 'Casual rides on weekdays %'])}

{table(tr, ['rider_type', 'rnk', 'start_station', 'end_station', 'rides', 'median_min'], ['Rider', '#', 'From', 'To', 'Rides', 'Median min'])}

{table(sorted(rd('a_zone'), key=lambda r: (r['rider_type'], r['zone'])), ['rider_type', 'zone', 'rides', 'pct_of_rider_rides'], ['Rider', 'Start zone (distance from State & Madison)', 'Rides', '% of rider rides'])}

## Conversion target
{table([cv], ['casual_rides', 'weekday_commute_hour_rides', 'commute_like_rides', 'commute_like_pct', 'rides_over_45_min', 'over_45_min_pct'],
       ['Casual rides', 'Weekday commute-hour rides', 'Commute-like (< 20 min, A to B)', '% of casual', 'Rides > 45 min', '% > 45 min'])}

## Data quality
![Data quality](images/data_quality.png)

**Row counts**

{table(dq_r, ['entity', 'raw_rows', 'distinct_rows', 'clean_rows', 'grain'])}

**Issues found and how they were handled** (flags can overlap; `invalid_reason` in `cln_trips` keeps the first one)

{table(dq_i, ['check_name', 'affected_rows'])}

**Null / format rates (raw)**

{table(dq_n, ['entity', 'column_name', 'null_pct', 'treatment'])}

**Assertions ({npass}/{len(asr)} PASS)**

{table(asr, ['check_name', 'failed_rows', 'status'])}

## How the images were made
`scripts/make_charts.py` reads the DuckDB query results exported to `results/tables/*.csv` and writes every chart as a plain-vector SVG with the
small custom writer `scripts/svgcharts.py` (rect, line, polyline, polygon, circle and text only; no plotting library, no embedded raster).
`scripts/render_png.py` then rasterises each SVG to a PNG at 2x with headless Google Chrome. Both versions are committed in `results/images/`.
The station map is a plain longitude/latitude scatter of station coordinates (no basemap tiles).

## Files
`metrics.json` (KPIs, data-quality evidence, engine, SQL timings), `JSON.shot` (headline snapshot + run config), `tables/` (every `a_*` and
`dq_*` table as CSV), `images/` (SVG + PNG), `sample/` (the same pipeline on the committed raw sample).
"""
(RES / "RESULTS.md").write_text(md)
print("wrote", RES / "RESULTS.md")
