#!/usr/bin/env python3
"""Download the full 12 months of Divvy trip data (Oct 2025 - Sep 2026) into data/raw_full/ and verify SHA-256.

Dataset: Divvy (Chicago bike share) trip data, the data behind the Kaggle "Cyclistic bike-share" Google Data Analytics capstone datasets
(e.g. https://www.kaggle.com/datasets/tanjiropanjaitan/cyclistic-bike-share-ride-data-oct-2024-sep-2025 for the previous 12 months).
There is no Kaggle API key, so the original public bucket is used: https://divvy-tripdata.s3.amazonaws.com/index.html
Licence: Divvy Data License Agreement (https://divvybikes.com/data-license-agreement), Lyft Bikes and Scooters, LLC / City of Chicago.

Each monthly zip holds one CSV (plus a macOS `__MACOSX/` resource file that is skipped). Quirk: the January 2026 zip
(202601-divvy-tripdata.zip) contains a CSV named `202501-divvy-tripdata.csv` although its rides are from Dec 2025 / Jan 2026, so every
CSV is written under its zip's month: data/raw_full/YYYYMM-divvy-tripdata.csv. Zips are kept in data/raw_full/zips/ (delete to save space).
  python scripts/download_full_data.py            # 236.7 MB of zips -> 1,233.7 MB of CSV, SHA-256 checked
  python scripts/download_full_data.py --weather  # also re-fetch data/reference/chicago_weather_daily.csv from Open-Meteo (committed already)
"""
import hashlib, io, pathlib, sys, urllib.request, zipfile

BASE = "https://divvy-tripdata.s3.amazonaws.com"
# month: (zip bytes, zip sha256, csv bytes, csv sha256, csv rows)
FILES = {
    "202510": (24605753, "1b01969507fb7e136f56c8bf8b586564ed93f0a80ae6ae5f5dcfda3396ff4177", 128361274, "31b8d27cc183f1d2cc37a566a6ee4fbb88f7c995c5e0aac43c2412d406c0db8e", 646039),
    "202511": (13591801, "7d873352d710a2c4a4190cbf83c6a9ceb1c21319b02de339578ef71f11587704", 71109639, "c9df9c2b6ae28e98bdc075c38c067c0f98ccfc9aa8d963e2bb1b3b35b496549e", 356628),
    "202512": (5701852, "bd171dbffa690aec3024b3605b86ec5120706eebc9d9bff69358130c58faed9a", 28300500, "ee9f637c1678e509db46d1fd0d1bc0c09c8fcc9b8a7bf5da32e6c125e6124ec7", 140534),
    "202601": (5907269, "c72e49ced87ed20d4da4730c8905f007f78c771a68fbb5c2caf194fcaf5536ca", 27856985, "45727d18d0bd45f794651c8abccaf039483e540da8fcf8b1fcc7df9378e3b7e0", 137787),
    "202602": (8201530, "daaccc57e08033a35ead6d0d3c0092d2857ef788bbd7c137d457b56d35b12061", 41164802, "1c003b0efe70be10d61c0657a6be7071ad282b497c698fc5d05217e1792dea44", 201450),
    "202603": (13165409, "7553befd3f668bc37d40119984931f78fb870fe62cd1eb69479bb106b1d1038d", 64047548, "73a97e03a6dd62fd58e4415e87caae2c05ddeae4a7a90620378705798773e848", 317037),
    "202604": (17068744, "af16f7c43ddcce1383dee15e83c7daa01ecab2346bf856b5333f8e61b6ce7f04", 89771695, "603cca0e83a51d04e766121b9576149388843d2934f81da7f8454d75b76025dc", 448252),
    "202605": (24934348, "880e4ff17b03e206ef8f06e5815fc6b520172bd6f0298682823007be99ce34b2", 130660322, "ab4d140020c19e65ec2b0650c3d9ce6c1e6240030d77a4186c05e3aa03ecfe28", 653704),
    "202606": (28468364, "34bde1eddacef591664fa97495460fe33265078f4134f8b80f141f94d126cc01", 152640622, "77a1803f8f52f3d5bbc4fbf7987205747fe3c74edaee746713478c45bd9ea114", 762550),
    "202607": (32910286, "4e6bc8725a92f5e4cebb9b3592874b1cea85111f920f9db9cd607cf88ec1fd14", 173089330, "e66859bb72f85c789269c94e1e3a0108000fd097a1c6b4a1f51210b28c1d5231", 869051),
    "202608": (32611393, "3f4de338ee56b1bee76ea310a42f790a2e88e062c3635638cd382582615b827f", 172809981, "9a9b84a51441212730119276bca6a1ba6f3c36baa1ed3403f1053aa5d249b157", 868191),
    "202609": (29538516, "c4d77fa960becee43885addacd48f82c1ab803f925a079750bb46ffe52c798af", 153933196, "0a5667c53dcb3bca7724da3a2cae87f49657bcb8fc03bb1309ad93c2cdfe3abd", 770562),
}
WEATHER = ("https://archive-api.open-meteo.com/v1/archive?latitude=41.8781&longitude=-87.6298&start_date=2025-09-30&end_date=2026-09-30"
           "&daily=temperature_2m_max,temperature_2m_min,temperature_2m_mean,precipitation_sum,snowfall_sum,wind_speed_10m_max"
           "&timezone=America%2FChicago&format=csv")
ROOT = pathlib.Path(__file__).resolve().parents[1]
out = ROOT / "data" / "raw_full"; zdir = out / "zips"
zdir.mkdir(parents=True, exist_ok=True)
sha = lambda b: hashlib.sha256(b).hexdigest()
bad = 0
for month, (zsize, zsha, csize, csha, nrows) in FILES.items():
    csv = out / f"{month}-divvy-tripdata.csv"
    if csv.exists() and csv.stat().st_size == csize and sha(csv.read_bytes()) == csha:
        print(f"{csv.name:28s} {csize:>13,} bytes  OK (cached)"); continue
    zp = zdir / f"{month}-divvy-tripdata.zip"
    if not zp.exists() or zp.stat().st_size != zsize:
        url = f"{BASE}/{month}-divvy-tripdata.zip"
        print("downloading", url, f"({zsize / 1e6:.1f} MB)")
        tmp = zp.with_suffix(".part"); urllib.request.urlretrieve(url, tmp); tmp.replace(zp)
    zb = zp.read_bytes()
    if sha(zb) != zsha:
        print(f"{zp.name}: ZIP CHECKSUM MISMATCH (Divvy may have re-published the month)"); bad += 1; continue
    with zipfile.ZipFile(io.BytesIO(zb)) as z:
        inner = [n for n in z.namelist() if n.endswith(".csv") and not n.startswith("__MACOSX")]
        data = z.read(inner[0])
    csv.write_bytes(data)
    ok = sha(data) == csha
    note = f"  (inner file {inner[0]})" if inner[0] != csv.name else ""
    print(f"{csv.name:28s} {len(data):>13,} bytes  {nrows:>8,} rows  {'OK' if ok else 'CSV CHECKSUM MISMATCH'}{note}")
    bad += not ok
if "--weather" in sys.argv:
    lines = urllib.request.urlopen(WEATHER).read().decode().splitlines()[3:]
    lines[0] = "date,temp_max_c,temp_min_c,temp_mean_c,precip_mm,snowfall_cm,wind_max_kmh"
    (ROOT / "data/reference/chicago_weather_daily.csv").write_text("\n".join(lines) + "\n")
    print("weather: data/reference/chicago_weather_daily.csv", len(lines) - 1, "days (Open-Meteo values can be revised slightly)")
sys.exit(1 if bad else 0)
