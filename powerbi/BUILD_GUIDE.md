# Build guide · Power BI Desktop (Windows)

There is no `.pbix` in this repo: Power BI Desktop only runs on Windows and this project was built on Linux. Everything needed to build the
report in about 20 minutes is here.

1. **Get the data.** Either use the committed CSVs in `powerbi/data/`, or regenerate them: `python scripts/download_full_data.py` then
   `python run_pipeline.py --source full`.
2. **Load.** Home > Get data > Text/CSV, load the eight files from `powerbi/data/`. In Power Query check types: every `*_key`, `rides`,
   `round_trips`, `dockless_starts`, `start_hour`, `hour`, `year`, `month`, `weekday_num`, `n_ids` and the 0/1 flags as Whole number;
   `ride_minutes`, `distance_km`, `duration_min`, `lat`, `lng`, `dist_to_loop_km` and the weather columns as Decimal; `date`, `first_seen`,
   `last_seen` as Date; `started_at` / `ended_at` as Date/Time (local Chicago time, no time zone); names, types, bands and zones as Text.
   Empty cells are nulls (not zero). Close & Apply.
3. **Model.** In Model view create the relationships in `model.md` (many-to-one, single direction). Mark `dim_date` as the date table
   (column `date`). Sort `dim_date[day_name]` by `weekday_num`.
4. **Measures.** Create a blank table called `_Measures` and paste each measure from `measures.dax`. Format shares as percentages.
5. **Visuals.** Build the page in `dashboard_spec.md`.
6. **Check against the repo** (no slicers): [Rides] = 6,006,520, [Casual Share %] = 35.13%, [Mean Ride Min] = 12.16 (member) and
   18.13 (casual), [Casual Share of Minutes %] = 44.66%, [E-bike Share %] = 70.39%, [Summer / Winter Ratio] = 3.78 (member) and 10.52 (casual).
   From the sample: [Sample Rides] = 23,380 and [Median Ride Min (sample)] = 8.75 (member) / 11.15 (casual), close to the full-data medians
   8.68 / 11.13 in `results/RESULTS.md`.
