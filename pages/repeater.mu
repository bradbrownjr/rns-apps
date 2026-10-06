#!/usr/bin/env python3
"""
Repeater directory (port of bpq-apps repeater.py), from RepeaterBook.

RepeaterBook's export API needs an approved app token. Put it in
/data/apps/config.json as "repeaterbook_token". Each state's list is cached
for 7 days, so one fetch serves every search and the page keeps working
offline.

Version: 1.0
Author: Brad Brown Jr (KC1JMH)
"""

import os
import sys
import urllib.parse

sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.realpath(__file__))), "lib"))
import rnsapps as ra  # noqa: E402

VERSION = "1.0"
TTL = 7 * 86400
PER_PAGE = 8
RADII = [10, 25, 50, 100]
API = "https://www.repeaterbook.com/api/export.php?country=United%20States&state="

STATES = {
    "AL": "Alabama", "AK": "Alaska", "AZ": "Arizona", "AR": "Arkansas", "CA": "California",
    "CO": "Colorado", "CT": "Connecticut", "DE": "Delaware", "FL": "Florida", "GA": "Georgia",
    "HI": "Hawaii", "ID": "Idaho", "IL": "Illinois", "IN": "Indiana", "IA": "Iowa",
    "KS": "Kansas", "KY": "Kentucky", "LA": "Louisiana", "ME": "Maine", "MD": "Maryland",
    "MA": "Massachusetts", "MI": "Michigan", "MN": "Minnesota", "MS": "Mississippi",
    "MO": "Missouri", "MT": "Montana", "NE": "Nebraska", "NV": "Nevada", "NH": "New Hampshire",
    "NJ": "New Jersey", "NM": "New Mexico", "NY": "New York", "NC": "North Carolina",
    "ND": "North Dakota", "OH": "Ohio", "OK": "Oklahoma", "OR": "Oregon", "PA": "Pennsylvania",
    "RI": "Rhode Island", "SC": "South Carolina", "SD": "South Dakota", "TN": "Tennessee",
    "TX": "Texas", "UT": "Utah", "VT": "Vermont", "VA": "Virginia", "WA": "Washington",
    "WV": "West Virginia", "WI": "Wisconsin", "WY": "Wyoming",
}
BANDS = [("10m", 28, 29.7), ("6m", 50, 54), ("2m", 144, 148), ("1.25m", 222, 225),
         ("70cm", 420, 450), ("33cm", 902, 928), ("23cm", 1240, 1300)]
MODES = [("FM", "FM Analog"), ("DMR", "DMR"), ("DStar", "D-Star"), ("YSF", "Fusion"), ("P25", "P25 Phase I")]


def band_of(mhz):
    for name, lo, hi in BANDS:
        if lo <= mhz <= hi:
            return name
    return ""


def num(value):
    try:
        return float(value)
    except (TypeError, ValueError):
        return None


def fetch_state(state_name, token):
    data = ra.http_json(API + urllib.parse.quote(state_name), timeout=20,
                        headers={"X-RB-App-Token": token})
    if isinstance(data, dict):
        if data.get("ok") is False or "error_code" in data:
            raise RuntimeError(data.get("message", "RepeaterBook error"))
        data = data.get("results", [])
    return data


def state_for(where):
    """Returns (state_abbr, lat, lon, label); lat/lon None for a plain state."""
    key = where.strip().upper()
    if key in STATES:
        return key, None, None, STATES[key]
    for abbr, name in STATES.items():
        if name.upper() == key:
            return abbr, None, None, name
    lat, lon, label = ra.resolve_location(where)
    abbr = (ra.nws_point(lat, lon).get("relativeLocation", {}).get("properties", {}).get("state") or "").upper()
    if abbr not in STATES:
        raise ValueError("Couldn't tell which US state that is in. Enter a state instead.")
    return abbr, lat, lon, label


def describe(rep, dist):
    out_mhz, in_mhz = num(rep.get("Frequency")), num(rep.get("Input Freq"))
    head = "{:.4f}".format(out_mhz) if out_mhz else str(rep.get("Frequency", "?"))
    if out_mhz and in_mhz and abs(out_mhz - in_mhz) > 0.001:
        head += " " + ("-" if in_mhz < out_mhz else "+")
    tone = (rep.get("PL") or "").strip()
    if tone and tone != "CSQ":
        head += "  " + tone
    modes = [label for label, key in MODES if str(rep.get(key, "")).strip().upper() == "YES"]
    place = " ".join(x for x in (rep.get("Nearest City"), rep.get("State")) if x)
    if dist is not None:
        place += "  {:.0f} mi".format(dist)
    trustee = rep.get("Callsign") or ""
    closed = "" if str(rep.get("Use", "OPEN")).upper() == "OPEN" else " (closed)"
    return [ra.bold(head), ra.esc(place), ra.dim("{} {}{}".format("/".join(modes) or "FM", trustee, closed))]


def render():
    where = ra.arg("where").replace("|", " ").replace("`", " ").replace("=", " ").strip()
    band, mode = ra.var("band"), ra.var("mode")
    radius = ra.int_var("d", 25)
    page = max(ra.int_var("p", 1), 1)
    out = [
        ra.heading("Repeaters"),
        "State, ZIP, grid or callsign:",
        ra.input_field("where", 24, where),
        ra.submit("Search", "repeater", "where"),
        "",
    ]
    token = ra.config().get("repeaterbook_token")
    if not where:
        out.append(ra.dim("Data from repeaterbook.com. Give a state for the whole state, or a"))
        out.append(ra.dim("ZIP, grid square or callsign for repeaters near that spot."))
        if not token:
            out += ["", ra.color("Sysop: set repeaterbook_token in config.json to enable searches.", ra.C_WARN)]
        return "\n".join(out + [ra.nav()])

    try:
        abbr, lat, lon, label = state_for(where)
    except ValueError as e:
        return "\n".join(out + [ra.color(str(e), ra.C_WARN), ra.nav()])
    except Exception:
        ra.log_error("repeater location {}".format(where))
        return "\n".join(out + [ra.color("Location lookup failed. Try a state name.", ra.C_WARN), ra.nav()])

    if not token:
        data, ts, stale = ra.cached("rb_" + abbr, TTL, lambda: (_ for _ in ()).throw(RuntimeError("no token")))
    else:
        data, ts, stale = ra.cached("rb_" + abbr, TTL, lambda: fetch_state(STATES[abbr], token))
    if not data:
        out.append(ra.color("Repeater data for {} isn't available right now.".format(STATES[abbr]), ra.C_WARN))
        if not token:
            out.append(ra.dim("(This node has no RepeaterBook token yet.)"))
        return "\n".join(out + [ra.nav()])

    rows = []
    for rep in data:
        if str(rep.get("Operational Status", "On-air")).lower() != "on-air":
            continue
        mhz = num(rep.get("Frequency"))
        if band and band_of(mhz or 0) != band:
            continue
        if mode:
            key = dict(MODES).get(mode)
            if not key or str(rep.get(key, "")).strip().upper() != "YES":
                continue
        dist = None
        if lat is not None:
            rlat, rlon = num(rep.get("Lat")), num(rep.get("Long"))
            if rlat is None or rlon is None:
                continue
            dist = ra.distance_mi(lat, lon, rlat, rlon)
            if dist > radius:
                continue
        rows.append((dist if dist is not None else 0, mhz or 0, rep))
    rows.sort(key=lambda r: (r[0], r[1]))

    def filt(**changes):
        base = {"where": where, "band": band, "mode": mode, "d": radius}
        base.update(changes)
        return {k: v for k, v in base.items() if v not in ("", None)}

    scope = "near {} ({} mi)".format(label, radius) if lat is not None else "in " + STATES[abbr]
    out.append(ra.bold("{} repeater{} {}".format(len(rows), "" if len(rows) == 1 else "s", scope)))
    bands = [ra.link(b[0], "repeater", **filt(band=b[0], p=1)) if b[0] != band else ra.bold(b[0]) for b in BANDS[1:6]]
    out.append(ra.dim("Band: ") + " ".join(bands) + "  " + ra.link("all", "repeater", **filt(band="", p=1)))
    modes = [ra.link(m[0], "repeater", **filt(mode=m[0], p=1)) if m[0] != mode else ra.bold(m[0]) for m in MODES]
    out.append(ra.dim("Mode: ") + " ".join(modes) + "  " + ra.link("all", "repeater", **filt(mode="", p=1)))
    if lat is not None:
        out.append(ra.dim("Radius: ") + " ".join(
            ra.link("{}".format(r), "repeater", **filt(d=r, p=1)) if r != radius else ra.bold(str(r)) for r in RADII))
    out += ["", ra.divider()]

    pages = max((len(rows) + PER_PAGE - 1) // PER_PAGE, 1)
    page = min(page, pages)
    for _, _, rep in rows[(page - 1) * PER_PAGE:page * PER_PAGE]:
        dist = ra.distance_mi(lat, lon, num(rep["Lat"]), num(rep["Long"])) if lat is not None else None
        out += describe(rep, dist) + [""]
    if not rows:
        out.append("Nothing matches. Widen the radius or clear a filter.")
    out += [ra.dim("Page {} of {}".format(page, pages)), ra.freshness(ts, stale)]
    pager = []
    if page > 1:
        pager.append(ra.link("< Prev", "repeater", **filt(p=page - 1)))
    if page < pages:
        pager.append(ra.link("Next >", "repeater", **filt(p=page + 1)))
    return "\n".join(out + [ra.nav(*pager)])


if __name__ == "__main__":
    ra.run(render)
