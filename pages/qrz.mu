#!/usr/bin/env python3
"""
Callsign lookup (port of bpq-apps qrz.py).

With "qrz_user" and "qrz_password" in /data/apps/config.json (a QRZ.com XML
Data subscription) it queries the QRZ XML API, which covers every country.
Without them, or if QRZ fails, it falls back to HamDB (US FCC data, no login).

Version: 1.1
Author: Brad Brown Jr (KC1JMH)
"""

import os
import re
import sys
import urllib.parse
import xml.etree.ElementTree as ET

sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.realpath(__file__))), "lib"))
import rnsapps as ra  # noqa: E402

VERSION = "1.1"

CLASSES = {"T": "Technician", "G": "General", "E": "Amateur Extra", "A": "Advanced",
           "N": "Novice", "P": "Technician Plus"}


QRZ_URL = "https://xmldata.qrz.com/xml/current/"
ANY_CALL_RE = re.compile(r"^[A-Z0-9]{1,3}[0-9][A-Z0-9]{0,3}[A-Z](/[A-Z0-9]{1,4})?$")


def _qrz_get(**params):
    params["agent"] = "rns-apps" + ra.VERSION
    root = ET.fromstring(ra.http_get(QRZ_URL + "?" + urllib.parse.urlencode(params), timeout=10))
    ns = {"q": root.tag.split("}")[0].strip("{")} if root.tag.startswith("{") else {}
    q = (lambda tag: "q:" + tag) if ns else (lambda tag: tag)
    return root, ns, q


def qrz_session(user, password):
    root, ns, q = _qrz_get(username=user, password=password)
    key = root.findtext(q("Session") + "/" + q("Key"), namespaces=ns)
    if not key:
        err = root.findtext(q("Session") + "/" + q("Error"), namespaces=ns) or "login failed"
        raise RuntimeError("QRZ: " + err)
    return key


def qrz_fetch(call, user, password):
    """QRZ XML record as a dict, or {} when the callsign isn't found."""
    for attempt in (0, 1):
        key, _, _ = ra.cached("qrz_session", 12 * 3600, lambda: qrz_session(user, password))
        if not key:
            raise RuntimeError("QRZ login unavailable")
        root, ns, q = _qrz_get(s=key, callsign=call)
        err = root.findtext(q("Session") + "/" + q("Error"), namespaces=ns) or ""
        if err.lower().startswith("not found"):
            return {}
        if err and attempt == 0 and ("session" in err.lower() or "invalid" in err.lower()):
            try:
                os.remove(os.path.join(ra.CACHE_DIR, "qrz_session.json"))
            except OSError:
                pass
            continue
        if err:
            raise RuntimeError("QRZ: " + err)
        node = root.find(q("Callsign"), ns)
        return {c.tag.split("}")[-1]: (c.text or "").strip() for c in node} if node is not None else {}
    return {}


def qrz_record(rec):
    """Map a QRZ XML record onto the HamDB-style keys record() prints."""
    get = lambda key: rec.get(key) or ""  # noqa: E731
    klass = get("class")
    if len(klass) == 1 and get("country") == "United States":
        klass = CLASSES.get(klass, klass)
    return {"call": get("call"), "fname": get("fname"), "name": get("name"), "addr1": get("addr1"),
            "addr2": get("addr2"), "state": get("state"), "zip": get("zip"), "country": get("country"),
            "class": klass, "expires": get("expdate"), "grid": get("grid"), "lat": get("lat"),
            "lon": get("lon"), "_qrz": True}


def row(label, value):
    return "{} {}".format(ra.dim("{:<9}".format(label)), ra.esc(value)) if value else None


def record(rec):
    name = " ".join(x for x in (rec.get("fname"), rec.get("mi"), rec.get("name"), rec.get("suffix")) if x)
    city = ", ".join(x for x in (rec.get("addr2"), rec.get("state")) if x)
    status = "" if rec.get("_qrz") else {"A": "Active", "E": "Expired", "C": "Cancelled", "T": "Terminated"}.get(rec.get("status"), rec.get("status", ""))
    lines = [
        row("Call", rec.get("call")),
        row("Name", name),
        row("Class", rec.get("class") if rec.get("_qrz") else CLASSES.get(rec.get("class"), rec.get("class", ""))),
        row("Status", status),
        row("Expires", rec.get("expires")),
        row("Address", rec.get("addr1")),
        row("City", "{} {}".format(city, rec.get("zip", "")).strip()),
        row("Country", rec.get("country")),
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
        out += [ra.dim("QRZ.com when this node has an account, else US FCC data (hamdb.org)."), ra.nav()]
        return "\n".join(out)
    cfg = ra.config()
    user, password = cfg.get("qrz_user"), cfg.get("qrz_password")
    if not (ra.CALLSIGN_RE.match(call) or (user and ANY_CALL_RE.match(call))):
        out.append(ra.color("'{}' doesn't look like a callsign.".format(call), ra.C_WARN))
        return "\n".join(out + [ra.nav()])
    rec, source = None, "hamdb.org (FCC ULS)"
    if user and password:
        data, ts, stale = ra.cached("qrz_" + call.replace("/", "_"), 86400, lambda: qrz_fetch(call, user, password))
        if data:
            rec, source = qrz_record(data), "QRZ.com" + (" (cached copy)" if stale else "")
    if rec is None and ra.CALLSIGN_RE.match(call):
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
    out += ["", ra.dim("Source: {}, cached up to 24 h.".format(source)), ra.nav()]
    return "\n".join(out)


if __name__ == "__main__":
    ra.run(render)
