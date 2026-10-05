#!/usr/bin/env python3
"""
Solar data and HF/VHF band conditions from hamqsl.com (port of bpq-apps
hamqsl.py).

Version: 1.0
Author: Brad Brown Jr (KC1JMH)
"""

import os
import sys
import xml.etree.ElementTree as ET

sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.realpath(__file__))), "lib"))
import rnsapps as ra  # noqa: E402

VERSION = "1.0"
URL = "https://www.hamqsl.com/solarxml.php?nwra=north&muf=grnlnd"
TTL = 60 * 60

BANDS = ["80m-40m", "30m-20m", "17m-15m", "12m-10m"]
ESKIP = [("6m ESkip EU", "europe_6m"), ("4m ESkip EU", "europe_4m"),
         ("2m ESkip EU", "europe"), ("2m ESkip NA", "north_america")]
FIELDS = ["updated", "solarflux", "sunspots", "aindex", "kindex", "kindexnt", "xray",
          "heliumline", "protonflux", "aurora", "normalization", "solarwind",
          "magneticfield", "latdegree", "geomagfield", "signalnoise", "muf",
          "muffactor", "fof2"]


def text(node):
    value = (node.text or "").strip() if node is not None else ""
    return value or "-"


def fetch():
    root = ET.fromstring(ra.http_get(URL))
    sd = root.find("solardata")
    data = {f: text(sd.find(f)) for f in FIELDS}
    data["electronflux"] = text(sd.find("electonflux"))  # misspelled in the source XML
    for band in BANDS:
        for tod in ("day", "night"):
            data["{}_{}".format(band, tod)] = text(sd.find(".//band[@name='{}'][@time='{}']".format(band, tod)))
    for _, loc in ESKIP:
        data["eskip_" + loc] = text(sd.find(".//phenomenon[@name='E-Skip'][@location='{}']".format(loc)))
    data["vhf_aurora"] = text(sd.find(".//phenomenon[@name='vhf-aurora'][@location='northern_hemi']"))
    return data


def cond(value):
    """Color band conditions the way most propagation widgets do."""
    rgb = {"Good": ra.C_OK, "Fair": "fd5", "Poor": ra.C_WARN}.get(value)
    return ra.color(value, rgb) if rgb else ra.esc(value)


def render():
    data, ts, stale = ra.cached("hamqsl", TTL, fetch)
    out = [ra.heading("HamQSL - Solar and Band Conditions"), ra.freshness(ts, stale)]
    if data is None:
        return "\n".join(out + [ra.nav()])

    def row(*pairs):
        return "  ".join("{} {}".format(ra.dim(k + ":"), ra.esc(v)) for k, v in pairs)

    out += [
        ra.dim("Source report: {}".format(data["updated"])),
        "",
        ra.heading("Solar-Terrestrial", 2),
        row(("Solar Flux", data["solarflux"]), ("Sunspots", data["sunspots"])),
        row(("A-Index", data["aindex"]), ("K-Index", data["kindex"]), ("K nt", data["kindexnt"])),
        row(("X-Ray", data["xray"]), ("Helium", data["heliumline"])),
        row(("Proton Flux", data["protonflux"]), ("Electron Flux", data["electronflux"])),
        row(("Solar Wind", data["solarwind"]), ("Mag Field", data["magneticfield"])),
        row(("Aurora", "{} / {}".format(data["aurora"], data["normalization"]))),
        "",
        ra.heading("HF Conditions", 2),
        ra.dim("{:<10}{:<8}{}".format("Band", "Day", "Night")),
    ]
    for band in BANDS:
        day, night = data[band + "_day"], data[band + "_night"]
        out.append("{:<10}{}{}{}".format(band, cond(day), " " * max(1, 8 - len(day)), cond(night)))
    out += ["", ra.heading("VHF Conditions", 2)]
    for label, loc in ESKIP:
        out.append(row((label, data["eskip_" + loc])))
    out += [
        row(("VHF Aurora", data["vhf_aurora"]), ("Aurora Lat", data["latdegree"])),
        "",
        ra.heading("Ionosphere", 2),
        row(("Geomag Field", data["geomagfield"]), ("Noise", data["signalnoise"])),
        row(("MUF", data["muf"]), ("MUF Factor", data["muffactor"]), ("foF2", data["fof2"])),
        "",
        "<",
        ra.dim("Data courtesy of hamqsl.com (N0NBH)."),
    ]
    return "\n".join(out + [ra.nav(("Space weather", "space"))])


if __name__ == "__main__":
    ra.run(render)
