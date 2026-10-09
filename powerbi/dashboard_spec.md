# Dashboard spec · da-learn-25 Bike-share trips (Divvy Chicago)

Business question (Cyclistic / Google Data Analytics capstone): how do annual members and casual riders use the bikes differently, and where /
when should a membership campaign target casual riders? One report page, 16:9, plus a "Station" drill-through page.

| # | Visual | Fields | Matches repo chart |
|---|---|---|---|
| 1 | KPI cards | [Rides], [Casual Share %], [Mean Ride Min] by rider type, [Weekend Share %] by rider type, [Summer / Winter Ratio] (casual), [E-bike Share %] | dashboard.svg header |
| 2 | Clustered column: rides per month | Axis dim_date[year_month], legend dim_rider_type[rider_type], value [Rides] | monthly_rides.svg |
| 3 | Line: daily rides | Axis dim_date[date], legend rider_type, value [Rides] (7-day moving average via a visual calculation or `AVERAGEX(DATESINPERIOD(...))`) | daily_trend.svg |
| 4 | Line: rides per day by start hour | Axis dim_hour[hour], legend rider_type, small multiples dim_date[day_type], value `DIVIDE([Sample Rides] * 256, [Days])` (sample-based estimate; exact values in results/tables/a_hourly.csv) | hourly_profile.svg |
| 5 | Matrix heatmap: weekday x hour | Rows dim_date[day_name] (sort by weekday_num), columns dim_hour[hour], value casual share from the sample, conditional formatting | casual_share_heatmap.svg |
| 6 | Clustered column: ride length | Axis fact_ride_sample[duration_band], legend rider_type, value % of column total | duration_bands.svg |
| 7 | Scatter: daily rides vs temperature | Details dim_date[date], X [Avg Temp C], Y [Member Rides] and [Casual Rides] (two series) | weather_scatter.svg |
| 8 | Bar: top casual start stations | Axis dim_station[station_name], value CALCULATE([Station Starts], casual), Top N 15, tooltip [Station Casual Share %] | top_casual_stations.svg |
| 9 | Map: stations | Latitude dim_station[lat], longitude dim_station[lng], size [Station Starts], colour [Station Casual Share %] (diverging) | station_map.svg |
| 10 | Clustered column: rides per day by season / temperature band | Axis dim_date[season] or dim_date[temp_band], legend rider_type, value [Rides per Day] | seasonal_swing.svg, temp_bands.svg |

Slicers: dim_date[year_month], dim_date[day_type], dim_rider_type[rider_type], dim_bike_type[bike_type], dim_station[zone].
Drill-through page "Station": monthly starts by rider type, casual share, round-trip share, station type and zone for the selected station.
