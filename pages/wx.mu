#!/usr/bin/env python3
"""
Weather (port of bpq-apps wx.py), from the National Weather Service API.

Pick a place (ZIP, 'City ST', grid square, callsign or lat,lon), then read
conditions, the forecast, hourly outlook, alerts, the Area Forecast
Discussion, or the Hazardous Weather Outlook (SKYWARN status). Every report
is cached and served stale, clearly marked, when the NWS is unreachable.

Version: 1.0
Author: Brad Brown Jr (KC1JMH)
"""

import os
import re
import sys
from datetime import datetime

sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.realpath(__file__))), "lib"))
import rnsapps as ra  # noqa: E402

VERSION = "1.0"
NWS = "https://api.weather.gov"

REPORTS = [
    ("now", "Current conditions", 900),
    ("fcst", "7-day forecast", 1800),
    ("hourly", "Next 12 hours", 1800),
    ("alerts", "Active alerts", 300),
    ("afd", "Forecast discussion", 3600),
    ("hwo", "Hazardous weather outlook", 3600),
]
TITLES = {key: title for key, title, _ in REPORTS}
TTLS = {key: ttl for key, _, ttl in REPORTS}


def c_to_f(c):
    return None if c is None else c * 9 / 5 + 32


def val(obs, key):
    return (obs.get(key) or {}).get("value")


def fmt(x, unit="", digits=0):
    return "-" if x is None else "{:.{}f}{}".format(x, digits, unit)


def compass(deg):
    if deg is None:
        return ""
    return "N NNE NE ENE E ESE SE SSE S SSW SW WSW W WNW NW NNW".split()[int((deg + 11.25) % 360 // 22.5)]


def product(point, code):
    cwa = point.get("cwa")
    index = ra.http_json("{}/products/types/{}/locations/{}".format(NWS, code, cwa))
    if not index.get("@graph"):
        return "No {} is currently issued for {}.".format(code, cwa)
    return ra.http_json(index["@graph"][0]["@id"]).get("productText", "")


def report_now(point, lat, lon):
    stations = ra.http_json(point["observationStations"])["features"][:3]
    for st in stations:
        obs = ra.http_json("{}/stations/{}/observations/latest".format(NWS, st["properties"]["stationIdentifier"]))["properties"]
        if val(obs, "temperature") is not None:
            obs["_station"] = st["properties"]["name"]
            return obs
    raise RuntimeError("no observations")


def show_now(obs):
    temp, dew = c_to_f(val(obs, "temperature")), c_to_f(val(obs, "dewpoint"))
    wind = val(obs, "windSpeed")
    gust = val(obs, "windGust")
    press = val(obs, "barometricPressure")
    vis = val(obs, "visibility")
    wind_text = "calm" if not wind else "{} {:.0f} mph".format(compass(val(obs, "windDirection")), wind / 1.609)
    if gust:
        wind_text += ", gusts {:.0f}".format(gust / 1.609)
    rows = [
        ("Sky", obs.get("textDescription") or "-"),
        ("Temp", fmt(temp, " F")),
        ("Dewpoint", fmt(dew, " F")),
        ("Humidity", fmt(val(obs, "relativeHumidity"), "%")),
        ("Wind", wind_text),
        ("Pressure", fmt(press / 3386.389 if press else None, " inHg", 2)),
        ("Visible", fmt(vis / 1609.34 if vis else None, " mi", 1)),
    ]
    out = [ra.dim("Station: {}".format(obs.get("_station", "?")))]
    out += ["{} {}".format(ra.dim("{:<9}".format(k)), ra.esc(v)) for k, v in rows if v != "-"]
    return out


def show_product(text):
    """NWS text products are hard-wrapped at ~68 columns. Rejoin paragraphs so
    the client wraps them to its own width; section headings (.NAME...) bold."""
    out = []
    for para in re.split(r"\n\s*\n", text.replace("\r", "")):
        flat = " ".join(para.split())
        if not flat or flat in ("&&", "$$"):
            continue
        if re.match(r"^\.[A-Z][A-Z /]+\.\.\.", flat):
            head, _, rest = flat.partition("...")
            out += [ra.heading(head.strip(". ").title(), 2)]
            flat = rest.strip()
        if flat:
            out += [ra.esc(flat), ""]
    return out


def show_forecast(data):
    out = []
    for p in data["periods"][:14]:
        out.append(ra.bold("{}: {} {}".format(p["name"], p["temperature"], p["temperatureUnit"])))
        out.append(ra.esc(p.get("detailedForecast", p.get("shortForecast", ""))))
        out.append("")
    return out


def show_hourly(data):
    out = []
    for p in data["periods"][:12]:
        hour = datetime.fromisoformat(p["startTime"]).strftime("%a %H:%M")
        out.append("{} {:>3}F {}".format(ra.dim(hour), p["temperature"], ra.esc(p["shortForecast"])))
    return out


def show_alerts(data):
    feats = data.get("features", [])
    if not feats:
        return [ra.color("No active alerts for this location.", ra.C_OK)]
    out = []
    for f in feats:
        p = f["properties"]
        out += [ra.color(p.get("event", "Alert"), ra.C_WARN), ra.esc(p.get("headline", ""))]
        out += [ra.esc(" ".join((p.get("description") or "").split())[:900]), ""]
    return out


def fetch(kind, point, lat, lon):
    if kind == "now":
        return report_now(point, lat, lon)
    if kind == "fcst":
        return ra.http_json(point["forecast"])["properties"]
    if kind == "hourly":
        return ra.http_json(point["forecastHourly"])["properties"]
    if kind == "alerts":
        return ra.http_json("{}/alerts/active?point={:.4f},{:.4f}".format(NWS, lat, lon))
    return product(point, kind.upper())


def render():
    where = ra.arg("where").replace("|", " ").replace("`", " ").replace("=", " ").strip()
    ll = ra.var("ll")
    report = ra.var("r")
    ident = ra.identity()

    out = [ra.heading("Weather"), "ZIP, City ST, grid, callsign or lat,lon:",
           ra.input_field("where", 24, where), ra.submit("Go", "wx", "where")]
    home = ra.profile(ident).get("location") if ident else ""
    if home and not where and not ll:
        out.append(ra.link("Use my profile location ({})".format(home), "wx", where=home.replace("|", " ").replace("=", " ")))
    out.append("")

    label = where
    if not ll:
        if not where:
            return "\n".join(out + [ra.dim("Data from the National Weather Service (US only)."), ra.nav()])
        try:
            lat, lon, label = ra.resolve_location(where)
        except ValueError as e:
            return "\n".join(out + [ra.color(str(e), ra.C_WARN), ra.nav()])
        except Exception:
            ra.log_error("wx geocode {}".format(where))
            return "\n".join(out + [ra.color("Location lookup is unreachable. Try a grid square or lat,lon.", ra.C_WARN), ra.nav()])
        ll = "{:.4f},{:.4f}".format(lat, lon)
    else:
        lat, lon = (float(x) for x in ll.split(",")[:2])
        label = ra.var("lb") or ll

    try:
        point = ra.nws_point(lat, lon)
    except Exception:
        point = {}
    if not point.get("forecast"):
        out.append(ra.color("The NWS has no data for that spot (US locations only).", ra.C_WARN))
        return "\n".join(out + [ra.nav()])
    rel = point.get("relativeLocation", {}).get("properties", {})
    place = "{}, {}".format(rel.get("city", label), rel.get("state", "")).strip(", ")
    base = {"ll": ll, "lb": label}

    if report not in TITLES:
        out.append(ra.bold(place))
        out += [ra.link(title, "wx", r=key, **base) for key, title, _ in REPORTS]
        return "\n".join(out + ["", ra.dim("NWS office: {}".format(point.get("cwa", "?"))), ra.nav()])

    data, ts, stale = ra.cached("wx_{}_{}".format(report, ll), TTLS[report],
                                lambda: fetch(report, point, lat, lon))
    out += [ra.heading("{} - {}".format(TITLES[report], place), 2), ra.freshness(ts, stale), ""]
    if data is None:
        pass
    elif report == "now":
        out += show_now(data)
    elif report == "fcst":
        out += show_forecast(data)
    elif report == "hourly":
        out += show_hourly(data)
    elif report == "alerts":
        out += show_alerts(data)
    else:
        out += show_product(data)
    return "\n".join(out + [ra.nav(ra.link("Reports", "wx", **base))])


if __name__ == "__main__":
    ra.run(render)
