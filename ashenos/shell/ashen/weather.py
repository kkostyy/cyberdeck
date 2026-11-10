#!/usr/bin/env python3
"""Weather for the AshenOS shell (open-meteo, no key). Prints one JSON object.

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
            if "lat" in d and "lon" in d:
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
        "&hourly=temperature_2m,weather_code&forecast_hours=12&wind_speed_unit=ms&timezone=auto"
        % (loc["lat"], loc["lon"]))
    c, h = w["current"], w["hourly"]
    print(json.dumps({
        "city": loc.get("city", ""),
        "temp": c["temperature_2m"], "feels": c["apparent_temperature"],
        "code": c["weather_code"], "wind": c["wind_speed_10m"], "humidity": c["relative_humidity_2m"],
        "day": bool(c.get("is_day", 1)),
        "hours": [{"t": t[11:16], "temp": v, "code": k}
                  for t, v, k in zip(h["time"], h["temperature_2m"], h["weather_code"])][::2],
    }, ensure_ascii=False))


if __name__ == "__main__":
    try:
        main()
    except Exception as e:  # network down etc. — the shell keeps the last value
        print(json.dumps({"error": str(e)}))
        sys.exit(0)
