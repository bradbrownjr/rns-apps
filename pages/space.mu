#!/usr/bin/env python3
"""
NOAA SWPC space weather text products (port of bpq-apps space.py).

Version: 1.0
Author: Brad Brown Jr (KC1JMH)
"""

import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.realpath(__file__))), "lib"))
import rnsapps as ra  # noqa: E402

VERSION = "1.0"
TTL = 60 * 60
BASE = "https://services.swpc.noaa.gov/text/"

REPORTS = [
    ("wwv", "Geophysical Alert Message", "wwv.txt"),
    ("outlook", "Advisory Outlook", "advisory-outlook.txt"),
    ("discussion", "Forecast Discussion", "discussion.txt"),
    ("weekly", "Weekly Highlights and Forecasts", "weekly.txt"),
    ("3day", "3-Day Forecast", "3-day-forecast.txt"),
    ("geomag", "3-Day Geomagnetic Forecast", "3-day-geomag-forecast.txt"),
    ("predict", "3-Day Space Weather Predictions", "3-day-solar-geomag-predictions.txt"),
]


def menu():
    out = [ra.heading("Space Weather"), "NOAA Space Weather Prediction Center reports.", ""]
    for key, name, _ in REPORTS:
        out.append(ra.link(name, "space", r=key))
    return "\n".join(out + ["", ra.dim("Source: services.swpc.noaa.gov"), ra.nav(("Band conditions", "hamqsl"))])


def render():
    report = next((r for r in REPORTS if r[0] == ra.var("r")), None)
    if not report:
        return menu()
    key, name, filename = report
    data, ts, stale = ra.cached("space_" + key, TTL,
                                lambda: ra.http_get(BASE + filename).decode("utf-8", "replace"))
    out = [ra.heading(name), ra.freshness(ts, stale), ""]
    if data is not None:
        out.append(ra.literal(data))
    return "\n".join(out + [ra.nav(("Space menu", "space"))])


if __name__ == "__main__":
    ra.run(render)
