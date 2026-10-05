#!/usr/bin/env python3
"""
Maine / New Hampshire text products from the NWS (port of bpq-apps
wx-me.py).

Version: 1.0
Author: Brad Brown Jr (KC1JMH)
"""

import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.realpath(__file__))), "lib"))
import rnsapps as ra  # noqa: E402

VERSION = "1.0"
TTL = 30 * 60
BASE = "https://tgftp.nws.noaa.gov/data/"

PRODUCTS = [
    ("summary", "Maine/New Hampshire Weather Summary", "raw/aw/awus81.kgyx.rws.gyx.txt"),
    ("roundup", "Maine/New Hampshire Weather Roundup", "raw/as/asus41.kgyx.rwr.gyx.txt"),
    ("west", "Western Maine/New Hampshire Forecast", "forecasts/state/nh/nhz010.txt"),
    ("north", "Northern and Eastern Maine Forecast", "raw/fp/fpus61.kcar.sft.car.txt"),
    ("maxmin", "Max/Min Temperature and Precipitation", "raw/as/asus61.kgyx.rtp.gyx.txt"),
]


def menu():
    out = [ra.heading("WX-ME - Maine/NH Weather"),
           "Text products from the National Weather Service in Gray, ME.", ""]
    for key, name, _ in PRODUCTS:
        out.append(ra.link(name, "wx-me", r=key))
    return "\n".join(out + ["", ra.dim("Source: tgftp.nws.noaa.gov"), ra.nav()])


def render():
    product = next((p for p in PRODUCTS if p[0] == ra.var("r")), None)
    if not product:
        return menu()
    key, name, path = product
    data, ts, stale = ra.cached("wxme_" + key, TTL,
                                lambda: ra.http_get(BASE + path).decode("utf-8", "replace"))
    out = [ra.heading(name), ra.freshness(ts, stale), ""]
    if data is not None:
        out.append(ra.literal(data))
    return "\n".join(out + [ra.nav(("WX-ME menu", "wx-me"))])


if __name__ == "__main__":
    ra.run(render)
