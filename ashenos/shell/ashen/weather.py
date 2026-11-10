#!/usr/bin/env python3
"""Weather for the AshenOS shell (open-meteo, no key). Prints one JSON object.

  weather.py --geocode <город>   → [{city, lat, lon, where}] for the settings page

Location: ~/.config/ashen/config.json {"lat":..,"lon":..,"city":".."} if set,
otherwise found once by IP (ipapi.co) and cached in ~/.cache/ashen/location.json.
"""
import json
import os
import sys
import urllib.request

HOME = os.path.expanduser("~")
CFG = os.path.join(HOME, ".config/ashen/config.json")
CACHE = os.path.join(HOME, ".cache/ashen/location.json")


def get(url):
    req = urllib.request.Request(url, headers={"User-Agent": "ashenos-shell"})
    with urllib.request.urlopen(req, timeout=12) as r:
        return json.load(r)


def location():
    for path in (CFG, CACHE):
        try:
            with open(path, encoding="utf-8") as f:
                d = json.load(f)
            if d.get("lat") and d.get("lon"):
                return d
        except (OSError, ValueError):
            pass
    ip = get("https://ipapi.co/json/")
    d = {"lat": ip["latitude"], "lon": ip["longitude"], "city": ip.get("city", "")}
    os.makedirs(os.path.dirname(CACHE), exist_ok=True)
    with open(CACHE, "w", encoding="utf-8") as f:
        json.dump(d, f)
    return d


def main():
    loc = location()
    w = get(
        "https://api.open-meteo.com/v1/forecast?latitude=%s&longitude=%s"
        "&current=temperature_2m,apparent_temperature,weather_code,wind_speed_10m,relative_humidity_2m,is_day"
        "&hourly=temperature_2m,weather_code,precipitation_probability&forecast_days=2"
        "&wind_speed_unit=ms&timezone=auto"
        % (loc["lat"], loc["lon"]))
    c, h = w["current"], w["hourly"]
    rows = [{"time": t, "t": t[11:16], "temp": v, "code": k, "pp": p}
            for t, v, k, p in zip(h["time"], h["temperature_2m"], h["weather_code"], h["precipitation_probability"])]
    now_hour = c["time"][:13]                      # "YYYY-MM-DDTHH"
    i = next((n for n, r in enumerate(rows) if r["time"][:13] == now_hour), 0)
    today = c["time"][:10]
    print(json.dumps({
        "city": loc.get("city", ""),
        "temp": c["temperature_2m"], "feels": c["apparent_temperature"],
        "code": c["weather_code"], "wind": c["wind_speed_10m"], "humidity": c["relative_humidity_2m"],
        "day": bool(c.get("is_day", 1)),
        "precip": rows[i]["pp"] if rows else 0,
        # next 12 hours, every 2 h (bar panel); today at 00, 03 … 21 (calendar ring)
        "hours": [{k: r[k] for k in ("t", "temp", "code")} for r in rows[i:i + 12:2]],
        "ring": [{k: r[k] for k in ("t", "temp", "code")} for r in rows
                 if r["time"][:10] == today and int(r["t"][:2]) % 3 == 0],
    }, ensure_ascii=False))


def geocode(name):
    """City search for the settings page: up to 5 matches."""
    from urllib.parse import quote
    r = get("https://geocoding-api.open-meteo.com/v1/search?count=5&language=ru&name=" + quote(name))
    print(json.dumps([{"city": x["name"], "lat": x["latitude"], "lon": x["longitude"],
                       "where": ", ".join(v for v in (x.get("admin1"), x.get("country")) if v)}
                      for x in r.get("results", [])], ensure_ascii=False))


if __name__ == "__main__":
    if sys.argv[1:2] == ["--geocode"]:
        try:
            geocode(" ".join(sys.argv[2:]))
        except Exception:
            print("[]")
        sys.exit(0)
    try:
        main()
    except Exception as e:  # network down etc. — the shell keeps the last value
        print(json.dumps({"error": str(e)}))
        sys.exit(0)
