#!/usr/bin/env python3
"""
Callsign lookup (port of bpq-apps qrz.py), using HamDB (US FCC data, no login).

Version: 1.0
Author: Brad Brown Jr (KC1JMH)
"""

import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.realpath(__file__))), "lib"))
import rnsapps as ra  # noqa: E402

VERSION = "1.0"

CLASSES = {"T": "Technician", "G": "General", "E": "Amateur Extra", "A": "Advanced",
           "N": "Novice", "P": "Technician Plus"}


def row(label, value):
    return "{} {}".format(ra.dim("{:<9}".format(label)), ra.esc(value)) if value else None


def record(rec):
    name = " ".join(x for x in (rec.get("fname"), rec.get("mi"), rec.get("name"), rec.get("suffix")) if x)
    city = ", ".join(x for x in (rec.get("addr2"), rec.get("state")) if x)
    status = {"A": "Active", "E": "Expired", "C": "Cancelled", "T": "Terminated"}.get(rec.get("status"), rec.get("status", ""))
    lines = [
        row("Call", rec.get("call")),
        row("Name", name),
        row("Class", CLASSES.get(rec.get("class"), rec.get("class", ""))),
        row("Status", status),
        row("Expires", rec.get("expires")),
        row("Address", rec.get("addr1")),
        row("City", "{} {}".format(city, rec.get("zip", "")).strip()),
        row("Grid", rec.get("grid")),
        row("Lat/Lon", "{}, {}".format(rec["lat"], rec["lon"]) if rec.get("lat") else ""),
    ]
    return [l for l in lines if l]


def render():
    call = ra.arg("call").upper()
    out = [
        ra.heading("Callsign Lookup"),
        "Callsign: {}".format(ra.input_field("call", 10, call)),
        ra.submit("Look up", "qrz", "call"),
        "",
    ]
    if not call:
        out += [ra.dim("US callsigns only (FCC data via hamdb.org)."), ra.nav()]
        return "\n".join(out)
    if not ra.CALLSIGN_RE.match(call):
        out.append(ra.color("'{}' doesn't look like a US callsign.".format(call), ra.C_WARN))
        return "\n".join(out + [ra.nav()])
    try:
        rec = ra.hamdb(call)
    except Exception:
        ra.log_error("hamdb lookup {}".format(call))
        out.append(ra.color("The lookup service is unreachable. Try again later.", ra.C_WARN))
        return "\n".join(out + [ra.nav()])
    if not rec:
        out.append("No record found for {}.".format(ra.bold(call)))
    else:
        out += record(rec)
    out += ["", ra.dim("Source: hamdb.org (FCC ULS), cached up to 24 h."), ra.nav()]
    return "\n".join(out)


if __name__ == "__main__":
    ra.run(render)
