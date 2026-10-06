#!/usr/bin/env python3
"""
HF propagation estimator (port of bpq-apps predict.py).

Estimates the best HF bands and hours between two places from live solar
data (hamqsl.com, cached 1 h, stale copy if offline), the great-circle path
and a simplified F2-layer model. Roughly 70-80% right; for serious planning
use VOACAP. Locations: grid square, lat,lon, DMS, US state, country,
callsign, ZIP or place name.

Version: 1.0
Author: Brad Brown Jr (KC1JMH)
"""

import os
import sys
import xml.etree.ElementTree as ET
from datetime import datetime, timezone

sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.realpath(__file__))), "lib"))
import geo  # noqa: E402
import ionosphere  # noqa: E402
import rnsapps as ra  # noqa: E402

VERSION = "1.0"
SOLAR_TTL = 3600
SOLAR_URL = "https://www.hamqsl.com/solarxml.php"
DEFAULTS = {"ssn": 100, "sfi": 130, "kindex": 3, "aindex": 10}


def fetch_solar():
    root = ET.fromstring(ra.http_get(SOLAR_URL, timeout=6))
    node = root.find("solardata")
    out = {"updated": (node.findtext("updated") or "").strip()}
    for key, tag in (("ssn", "sunspots"), ("sfi", "solarflux"), ("kindex", "kindex"), ("aindex", "aindex")):
        try:
            out[key] = int(float(node.findtext(tag)))
        except (TypeError, ValueError):
            out[key] = DEFAULTS[key]
    return out


def locate(text):
    """(lat, lon, label) from any supported form, or raises ValueError."""
    text = text.strip()
    lat, lon, desc = geo.parse_location(text)
    if lat is not None:
        return lat, lon, desc
    return ra.resolve_location(text)


def clean(text):
    return text.replace("|", " ").replace("`", " ").replace("=", " ").strip()


def render():
    frm, to = clean(ra.arg("from")), clean(ra.arg("to"))
    ident = ra.identity()
    home = clean(ra.profile(ident).get("location", "")) if ident else ""
    out = [ra.heading("HF Predict"),
           "From (blank = your profile):" if home else "From:", ra.input_field("from", 24, frm),
           "To:", ra.input_field("to", 24, to),
           ra.submit("Predict", "predict", "from|to"), ""]
    if not to:
        out += [ra.dim("Places: grid (FN43), lat,lon, state, country,"),
                ra.dim("callsign, ZIP or town. Simplified model, ~70-80%."),
                ra.nav(("Band conditions", "hamqsl"))]
        return "\n".join(out)
    if not frm:
        frm = home
    if not frm:
        return "\n".join(out + [ra.color("Enter a From place (or register with a location).", ra.C_WARN), ra.nav()])

    try:
        lat1, lon1, from_label = locate(frm)
        lat2, lon2, to_label = locate(to)
    except ValueError as e:
        return "\n".join(out + [ra.color(str(e), ra.C_WARN), ra.nav()])
    except Exception:
        ra.log_error("predict locate {} -> {}".format(frm, to))
        return "\n".join(out + [ra.color("Location lookup is unreachable. Try grid squares.", ra.C_WARN), ra.nav()])

    solar, ts, stale = ra.cached("solar_predict", SOLAR_TTL, fetch_solar)
    solar = solar or dict(DEFAULTS, updated="defaults")

    dist = geo.great_circle_distance(lat1, lon1, lat2, lon2)
    brg = geo.bearing(lat1, lon1, lat2, lon2)
    mid_lat, _ = geo.midpoint(lat1, lon1, lat2, lon2)
    now = datetime.now(timezone.utc)
    shift = ra.int_var("h", 0)
    when = now.replace(minute=0) if shift == 0 else now.replace(minute=0).replace(hour=(now.hour + shift) % 24)
    preds = ionosphere.predict_bands(dist, mid_lat, solar["ssn"], solar["kindex"], when.hour, now.month)
    context, warnings = ionosphere.get_solar_context(solar["ssn"], solar["sfi"], solar["kindex"], solar["aindex"])

    out += [ra.bold("{} to {}".format(from_label, to_label)),
            "{} mi ({}), bearing {}".format(int(dist * 0.621371), geo.format_distance(dist), geo.format_bearing(brg)),
            ra.dim("At {:02d}:00 UTC{}".format(when.hour, " (now)" if shift == 0 else "")),
            ""]
    out += ra.paragraphs(context)
    for w in warnings:
        out.append(ra.color(w, ra.C_WARN))
    out += ["", ra.dim("Band  Reliab.  MUF   Best hours")]
    for p in preds:
        if p["usable"]:
            out.append("{:<5} {:<8} {:>3}%  {}".format(p["band"], p["rel_label"], p["muf_pct"], p["best_hours"]))
        else:
            out.append(ra.dim("{:<5} Closed".format(p["band"])))
    out += ["", ra.esc(ionosphere.get_recommendation(preds).split("\n")[0]), ra.freshness(ts, stale)]
    keep = {"from": frm, "to": to}
    out.append("Time: " + "  ".join(ra.bold("now") if s == 0 and shift == 0 else
                                    (ra.bold("+{}h".format(s)) if s == shift else
                                     ra.link("now" if s == 0 else "+{}h".format(s), "predict", h=s, **keep))
                                    for s in (0, 3, 6, 12)))
    return "\n".join(out + [ra.nav(("Band conditions", "hamqsl"))])


if __name__ == "__main__":
    ra.run(render)
