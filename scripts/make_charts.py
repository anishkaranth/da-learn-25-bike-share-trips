#!/usr/bin/env python3
"""Render SVG charts (pure vector shapes, no raster) from the KPI tables exported by run_pipeline.py."""
import csv, pathlib, sys
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import svgcharts as S

BLUE, ORANGE, GREEN, SAND, NAVY, BROWN, PURPLE, ROSE, TEAL, GOLD = S.PALETTE[:10]
MEM, CAS = BLUE, ORANGE
DAYS = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
MON = {"01": "Jan", "02": "Feb", "03": "Mar", "04": "Apr", "05": "May", "06": "Jun", "07": "Jul", "08": "Aug", "09": "Sep", "10": "Oct",
       "11": "Nov", "12": "Dec"}


def rd(t, name):
    with open(pathlib.Path(t) / f"{name}.csv", newline="", encoding="utf-8") as fh:
        return list(csv.DictReader(fh))


def f(x):
    return float(x) if x not in ("", None) else 0.0


def i(x):
    return int(f(x))


def short(s, n=24):
    s = s.replace("DuSable Lake Shore Dr", "DuSable LSD").replace(" Ave &", " Av &").replace(" Blvd", " Bl")
    s = s[:-4] + " Av" if s.endswith(" Ave") else s
    return s if len(s) <= n else s[: n - 1] + "."


def mlab(ym):
    return f"{MON[ym[5:7]]} {ym[2:4]}"


def make_all(tables, out):
    out = pathlib.Path(out); out.mkdir(parents=True, exist_ok=True)
    P = {}
    k = rd(tables, "a_kpi_headline")[0]
    prof = {r["rider_type"]: r for r in rd(tables, "a_rider_profile")}

    # 1 monthly rides by rider type
    mo = sorted(rd(tables, "a_monthly"), key=lambda r: r["year_month"])
    P["monthly_rides"] = S.grouped_vbar(
        "Rides per month: members vs casual riders", [mlab(r["year_month"]) for r in mo],
        [("member", [i(r["member_rides"]) / 1000 for r in mo]), ("casual", [i(r["casual_rides"]) / 1000 for r in mo])], fmt="{:.0f}k",
        w=900, h=360, ylabel="valid rides (thousands)",
        subtitle=f"{i(k['valid_rides']):,} valid rides Oct 2025 - Sep 2026; casual share {f(mo[2]['casual_share_pct']):.0f}% in "
                 f"{mlab(mo[2]['year_month'])} vs {max(f(r['casual_share_pct']) for r in mo):.0f}% at the summer peak")
    # 2 daily trend, 7-day rolling mean
    dy = sorted(rd(tables, "a_daily"), key=lambda r: r["date"])
    def roll(col):
        v = [i(r[col]) for r in dy]
        return [sum(v[max(0, j - 6): j + 1]) / len(v[max(0, j - 6): j + 1]) for j in range(len(v))]
    xs = [mlab(r["date"][:7]) if r["date"].endswith("-01") else "" for r in dy]
    P["daily_trend"] = S.line("Daily rides, 7-day rolling average", xs, [("member", roll("member_rides")), ("casual", roll("casual_rides"))],
                              fmt="{:,.0f}", every=1, colors=[MEM, CAS], w=900, h=340, ylabel="rides per day",
                              subtitle=f"busiest day {k['busiest_date']} ({i(k['busiest_date_rides']):,} rides), quietest {k['quietest_date']} "
                                       f"({i(k['quietest_date_rides']):,}); average {i(k['avg_rides_per_day']):,} per day")
    # 3 hourly profile
    hr = rd(tables, "a_hourly")
    hv = {(r["day_type"], i(r["hour"]), r["rider_type"]): f(r["rides_per_day"]) for r in hr}
    hrs = list(range(24))
    P["hourly_profile"] = S.line(
        "When people ride: average rides per day by start hour", [f"{h:02d}" for h in hrs],
        [("member, weekday", [hv.get(("Weekday", h, "member"), 0) for h in hrs]),
         ("casual, weekday", [hv.get(("Weekday", h, "casual"), 0) for h in hrs]),
         ("member, weekend/holiday", [hv.get(("Weekend / holiday", h, "member"), 0) for h in hrs]),
         ("casual, weekend/holiday", [hv.get(("Weekend / holiday", h, "casual"), 0) for h in hrs])],
        fmt="{:,.0f}", every=2, colors=[MEM, CAS, NAVY, GOLD], w=760, h=360, ylabel="rides per day",
        subtitle="members show 8 am and 5 pm commute peaks on weekdays; casual riders build to a late-afternoon peak")
    # 4 weekday
    wd = rd(tables, "a_weekday")
    wv = {(i(r["weekday_num"]), r["rider_type"]): f(r["rides_per_day"]) for r in wd}
    P["weekday_rides"] = S.grouped_vbar("Average rides per day by weekday", DAYS,
                                        [("member", [wv[(d, "member")] for d in range(7)]), ("casual", [wv[(d, "casual")] for d in range(7)])],
                                        fmt="{:,.0f}", w=640, h=340, ylabel="rides per day",
                                        subtitle=f"casual riders peak on Saturday; {f(prof['casual']['weekend_holiday_pct']):.1f}% of casual rides "
                                                 f"vs {f(prof['member']['weekend_holiday_pct']):.1f}% of member rides fall on weekends/holidays")
    # 5/6 heatmaps
    hm = rd(tables, "a_heatmap")
    hmv = {(i(r["weekday_num"]), i(r["hour"])): r for r in hm}
    P["demand_heatmap"] = S.heatmap("Ride demand by weekday and start hour", DAYS, [f"{h}" for h in hrs],
                                    [[f(hmv[(d, h)]["rides"]) / 1000 if (d, h) in hmv else None for h in hrs] for d in range(7)],
                                    fmt="{:.0f}", w=900, h=270, xlabel="start hour (Chicago local time)",
                                    subtitle="thousands of valid rides in the year per cell (darker = busier)")
    P["casual_share_heatmap"] = S.heatmap("Casual-rider share by weekday and start hour (%)", DAYS, [f"{h}" for h in hrs],
                                          [[f(hmv[(d, h)]["casual_share_pct"]) if (d, h) in hmv else None for h in hrs] for d in range(7)],
                                          fmt="{:.0f}", w=900, h=270, hi_color="#c4552f", lo_color="#fbf3ef", xlabel="start hour (Chicago local time)",
                                          subtitle="share of rides by casual riders: lowest at weekday commute hours, highest on weekend afternoons and late nights")
    # 7 duration bands
    db = rd(tables, "a_duration_bands")
    bands = sorted({r["duration_band"] for r in db})
    dv = {(r["rider_type"], r["duration_band"]): f(r["pct_of_rider_rides"]) for r in db}
    P["duration_bands"] = S.grouped_vbar("Ride length: share of each rider type's rides", [b[3:] for b in bands],
                                         [("member", [dv[("member", b)] for b in bands]), ("casual", [dv[("casual", b)] for b in bands])],
                                         fmt="{:.1f}%", w=640, h=340, ylabel="% of rides",
                                         subtitle=f"median ride {f(k['member_median_min']):.1f} min (member) vs {f(k['casual_median_min']):.1f} min (casual); "
                                                  f"mean {f(k['member_mean_min']):.1f} vs {f(k['casual_mean_min']):.1f}")
    # 8 rider profile
    metrics = [("weekend / holiday rides", "weekend_holiday_pct"), ("weekday 7-9 / 16-18 h", "weekday_commute_hours_pct"),
               ("e-bike rides", "ebike_pct"), ("dockless starts", "dockless_start_pct"), ("rides > 45 min", "over_45_min_pct"),
               ("round trips", "round_trip_pct")]
    P["rider_profile"] = S.grouped_vbar("How members and casual riders differ (% of their rides)", [m[0] for m in metrics],
                                        [("member", [f(prof["member"][c]) for _, c in metrics]), ("casual", [f(prof["casual"][c]) for _, c in metrics])],
                                        fmt="{:.1f}", w=760, h=340, ylabel="% of the rider type's rides",
                                        subtitle=f"casual riders: {f(k['casual_share_pct']):.1f}% of rides but {f(k['casual_ride_minutes_share_pct']):.1f}% "
                                                 f"of ride minutes; median speed {f(k['casual_median_kmh']):.1f} vs {f(k['member_median_kmh']):.1f} km/h (members)")
    # 9 bike mix
    bm = {(r["rider_type"], r["bike_type"]): r for r in rd(tables, "a_bike_mix")}
    P["bike_mix"] = S.stacked_hbar("Bike choice: classic vs e-bike", ["member", "casual"],
                                   [[f(bm[(rt, "classic_bike")]["pct_of_rider_rides"]), f(bm[(rt, "electric_bike")]["pct_of_rider_rides"])] for rt in ["member", "casual"]],
                                   ["classic bike", "e-bike"], colors=[TEAL, GOLD], fmt="{:.1f}%", w=640, h=190,
                                   notes=[f"{f(bm[(rt, 'electric_bike')]['dockless_start_pct']):.0f}% dockless" for rt in ["member", "casual"]],
                                   subtitle=f"% of each rider type's rides; e-bikes are {f(k['ebike_pct']):.1f}% of all valid rides; right: e-bike trips starting away from a dock")
    # 10 top casual stations
    ts = sorted([r for r in rd(tables, "a_top_stations") if r["rider_type"] == "casual"], key=lambda r: i(r["rnk"]))
    P["top_casual_stations"] = S.hbar("Top 15 start stations for casual riders", [short(r["station_name"], 30) for r in ts],
                                      [i(r["rides"]) for r in ts], fmt="{:,.0f}", color=CAS, w=720,
                                      vmax=S._nice_max(1.25 * max(i(r["rides"]) for r in ts)),
                                      notes=[f"({f(r['casual_share_pct']):.0f}% casual)" for r in ts],
                                      subtitle="casual starts in the year; lakefront and museum-campus stations dominate")
    # 11 casual hotspots
    ch = sorted(rd(tables, "a_casual_hotspots"), key=lambda r: i(r["rnk"]))[:12]
    P["casual_hotspots"] = S.hbar("Stations where casual riders dominate", [short(r["station_name"], 30) for r in ch],
                                  [f(r["casual_share_pct"]) for r in ch], fmt="{:.1f}%", color=ROSE, w=720, vmax=100,
                                  notes=[f"of {i(r['starts']):,} starts" for r in ch],
                                  subtitle=f"casual share of starts, stations with >= 5,000 starts ({len(rd(tables, 'a_casual_hotspots'))} stations); "
                                           f"system average {f(k['casual_share_pct']):.1f}%")
    # 12 station map
    sm = rd(tables, "a_station_map")
    grp = lambda s: 0 if s < 25 else (1 if s < 40 else (2 if s < 55 else 3))
    pts = [(f(r["lng"]), f(r["lat"]), grp(f(r["casual_share_pct"]))) for r in sm]
    pts.sort(key=lambda p: p[2])   # casual-heavy stations drawn on top
    P["station_map"] = S.scatter("Station map: casual share of starts", pts, w=520, h=780, r=2.6, opacity=0.85,
                                 colors=[BLUE, "#9ccfd8", "#f0a07f", "#b2341b"],
                                 groups=["< 25% casual", "25-40%", "40-55%", ">= 55% casual"],
                                 xmin=-87.83, xmax=-87.52, ymin=41.76, ymax=42.08, yticks=[41.8, 41.85, 41.9, 41.95, 42.0, 42.05], ytick_fmt="{:.2f}",
                                 xticks=[-87.8, -87.75, -87.7, -87.65, -87.6, -87.55], xtick_fmt="{:.2f}", xlabel="longitude", ylabel="latitude",
                                 subtitle=f"{len(sm):,} stations with >= 500 starts (lat/lng, Lake Michigan to the right); casual-heavy = lakefront + museums")
    # 13 weather scatter
    pts = [(f(r["temp_mean_c"]), i(r["member_rides"]), 0) for r in dy] + [(f(r["temp_mean_c"]), i(r["casual_rides"]), 1) for r in dy]
    wf = {r["rider_type"]: r for r in rd(tables, "a_weather_fit")}
    P["weather_scatter"] = S.scatter("Daily rides vs mean temperature", pts, w=640, h=380, r=2.6, opacity=0.6, colors=[MEM, CAS],
                                     groups=["member", "casual"], ymin=0, ymax=24000, yticks=[0, 4000, 8000, 12000, 16000, 20000, 24000], ytick_fmt="{:,.0f}",
                                     xticks=[-20, -10, 0, 10, 20, 30], xtick_fmt="{:.0f} C",
                                     xlabel="daily mean temperature (C, Open-Meteo)", ylabel="rides that day",
                                     subtitle=f"365 days; corr {f(wf['member']['corr_temp']):.2f} member / {f(wf['casual']['corr_temp']):.2f} casual; "
                                              f"+1 C ~ +{f(wf['member']['rides_per_deg_c']):.0f} member and +{f(wf['casual']['rides_per_deg_c']):.0f} casual rides/day")
    # 14 temperature bands
    tb = sorted(rd(tables, "a_temp_bands"), key=lambda r: r["temp_band"])
    P["temp_bands"] = S.grouped_vbar("Average rides per day by temperature band", [r["temp_band"][3:].replace(" and above", "+") for r in tb],
                                     [("member", [f(r["member_rides_per_day"]) for r in tb]), ("casual", [f(r["casual_rides_per_day"]) for r in tb])],
                                     fmt="{:,.0f}", w=760, h=340, ylabel="rides per day",
                                     subtitle="days grouped by daily mean temperature; casual share climbs from "
                                              f"{f(tb[0]['casual_share_pct']):.0f}% below -5 C to {max(f(r['casual_share_pct']) for r in tb):.0f}% on warm days")
    # 15 rain effect (May-Sep)
    re_ = sorted(rd(tables, "a_rain_effect"), key=lambda r: (r["day_type"], r["rain_class"]))
    P["rain_effect"] = S.grouped_vbar("Rain effect, May-Sep: average rides per day",
                                      [f"{'Wkday' if r['day_type'] == 'Weekday' else 'Wkend'} {r['rain_class'][2:].split(' (')[0]} ({i(r['n_days'])} d)" for r in re_],
                                      [("member", [f(r["member_rides_per_day"]) for r in re_]), ("casual", [f(r["casual_rides_per_day"]) for r in re_])],
                                      fmt="{:,.0f}", w=760, h=340, ylabel="rides per day",
                                      subtitle="warm-season days only, by daily precipitation: dry < 1 mm, light 1-5 mm, heavy 5 mm+")
    # 16 top routes
    tr = sorted(rd(tables, "a_top_routes"), key=lambda r: (r["rider_type"] != "casual", i(r["rnk"])))
    lab = [("C: " if r["rider_type"] == "casual" else "M: ") + (f"{short(r['start_station'], 22)} (round trip)" if i(r["is_round_trip"])
            else f"{short(r['start_station'], 18)} > {short(r['end_station'], 18)}") for r in tr]
    P["top_routes"] = S.hbar("Most popular routes: casual (C) vs member (M)", lab, [i(r["rides"]) for r in tr], fmt="{:,.0f}",
                             color=[CAS if r["rider_type"] == "casual" else MEM for r in tr], w=760,
                             notes=[f"median {f(r['median_min']):.0f} min" for r in tr],
                             subtitle="top 10 station pairs per rider type: casual = lakefront loops, member = short University of Chicago / UIC hops")
    # 17 seasonal swing
    se = {r["season"]: r for r in rd(tables, "a_season")}
    order = ["Autumn", "Winter", "Spring", "Summer"]
    P["seasonal_swing"] = S.grouped_vbar("Seasonal swing: average rides per day by season",
                                         [f"{z} ({f(se[z]['avg_temp_c']):.0f} C, {f(se[z]['casual_share_pct']):.0f}% casual)" for z in order],
                                         [("member", [f(se[z]["member_rides_per_day"]) for z in order]), ("casual", [f(se[z]["casual_rides_per_day"]) for z in order])],
                                         fmt="{:,.0f}", w=760, h=340, ylabel="rides per day",
                                         subtitle=f"summer vs winter: members x{f(k['member_summer_winter_ratio']):.2f}, casual riders x{f(k['casual_summer_winter_ratio']):.2f} "
                                                  "(Autumn = Oct-Nov 2025 + Sep 2026)")
    # 18 data quality
    dq = sorted([r for r in rd(tables, "dq_issues") if i(r["affected_rows"]) > 1 and not r["check_name"].startswith("RI")
                 and "variants" not in r["check_name"]], key=lambda r: -i(r["affected_rows"]))
    def dql(c):
        for key, lab in [("distances approximate", "distance approximate (kept)"), ("dockless", "dockless e-bike start (kept)"),
                         ("under 60", "under 60 s (invalid)"), ("station names", "station name fixed"), ("no end", "no end location (invalid)"),
                         ("over 24", "over 24 h (invalid)"), ("leading space", "station id trimmed"), ("test / depot", "test / depot station (invalid)"),
                         ("before 1 Oct", "started 30 Sep 2025 (invalid)"), ("more than one station id", "stations with > 1 id"),
                         ("duplicate rows", "duplicate across monthly files"), ("service-area", "outside service area (invalid)"),
                         ("DST", "DST end, fixed +60 min"), ("speed", "speed > 45 km/h (invalid)")]:
            if key in c:
                return lab
        return c[:40]
    P["data_quality"] = S.hbar("Data-quality issues found and handled", [dql(r["check_name"]) for r in dq], [i(r["affected_rows"]) for r in dq],
                               fmt="{:,.0f}", color=[ROSE if "invalid" in r["check_name"] else TEAL for r in dq], w=760,
                               subtitle=f"rides affected; {i(k['invalid_rides']):,} invalid rides ({100 - f(k['valid_pct']):.2f}%) excluded, "
                                        "red = invalid, teal = fixed or kept + flagged; see sql/05")
    for name, p in P.items():
        S.save(p, out / f"{name}.svg")
    cards = [("valid rides (Oct 25 - Sep 26)", f"{i(k['valid_rides']) / 1e6:.2f} M"), ("casual share of rides", f"{f(k['casual_share_pct']):.1f}%"),
             ("median ride member / casual", f"{f(k['member_median_min']):.1f} / {f(k['casual_median_min']):.1f} min"),
             ("weekend share member / casual", f"{f(k['member_weekend_pct']):.0f}% / {f(k['casual_weekend_pct']):.0f}%"),
             ("summer / winter rides: casual", f"{f(k['casual_summer_winter_ratio']):.1f}x"),
             ("e-bike share of rides", f"{f(k['ebike_pct']):.1f}%")]
    small = dict(w=640, h=360)
    S.dashboard(out / "dashboard.svg", "da-learn-25 · Bike-share trips (Divvy Chicago, Oct 2025 - Sep 2026)",
                f"{i(k['raw_rows']):,} raw rides -> {i(k['valid_rides']):,} valid ({f(k['valid_pct']):.2f}%); members vs casual riders; "
                "DuckDB SQL pipeline on the full data; Databricks skipped (quota)", cards, [
                    S.grouped_vbar("Rides per month (thousands)", [mlab(r["year_month"])[:3] for r in mo],
                                   [("member", [i(r["member_rides"]) / 1000 for r in mo]), ("casual", [i(r["casual_rides"]) / 1000 for r in mo])],
                                   fmt="{:.0f}", **small),
                    S.line("Average rides per day by start hour", [f"{h:02d}" for h in hrs],
                           [("member, weekday", [hv.get(("Weekday", h, "member"), 0) for h in hrs]),
                            ("casual, weekday", [hv.get(("Weekday", h, "casual"), 0) for h in hrs]),
                            ("member, wkend/hol", [hv.get(("Weekend / holiday", h, "member"), 0) for h in hrs]),
                            ("casual, wkend/hol", [hv.get(("Weekend / holiday", h, "casual"), 0) for h in hrs])],
                           fmt="{:,.0f}", every=3, colors=[MEM, CAS, NAVY, GOLD], **small),
                    S.grouped_vbar("Ride length (% of rider type's rides)", [b[3:].replace(" min", "") + "m" for b in bands],
                                   [("member", [dv[("member", b)] for b in bands]), ("casual", [dv[("casual", b)] for b in bands])], fmt="{:.0f}", **small),
                    S.scatter("Daily rides vs mean temperature (C)", [(f(r["temp_mean_c"]), i(r["member_rides"]), 0) for r in dy]
                              + [(f(r["temp_mean_c"]), i(r["casual_rides"]), 1) for r in dy], r=2.4, opacity=0.6, colors=[MEM, CAS],
                              groups=["member", "casual"], ymin=0, ymax=24000, yticks=[0, 6000, 12000, 18000, 24000], ytick_fmt="{:,.0f}",
                              xticks=[-20, -10, 0, 10, 20, 30], xtick_fmt="{:.0f}", **small),
                    S.hbar("Top casual start stations", [short(r["station_name"], 26) for r in ts[:10]], [i(r["rides"]) for r in ts[:10]],
                           fmt="{:,.0f}", color=CAS, notes=[f"({f(r['casual_share_pct']):.0f}% casual)" for r in ts[:10]],
                           vmax=S._nice_max(1.3 * max(i(r["rides"]) for r in ts)), **small),
                    S.heatmap("Casual share by weekday x hour (%)", DAYS, [f"{h}" for h in hrs],
                              [[f(hmv[(d, h)]["casual_share_pct"]) if (d, h) in hmv else None for h in hrs] for d in range(7)],
                              fmt="{:.0f}", hi_color="#c4552f", lo_color="#fbf3ef", cell_text=False, **small),
                ], cols=2)
    print(f"wrote {len(P) + 1} SVG charts to {out}")


if __name__ == "__main__":
    root = pathlib.Path(__file__).resolve().parents[1]
    make_all(root / "results/tables", root / "results/images")
