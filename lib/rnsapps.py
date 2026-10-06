"""
Shared helpers for rns-apps NomadNet pages.

NomadNet runs an executable page once per request and serves its stdout as
micron. The page gets no stdin, and its environment holds only PATH plus:

    remote_identity   hex identity hash, only if the visitor identified
    link_id           hex link id
    field_<name>      submitted form fields
    var_<name>        link variables

Version: 1.6
Author: Brad Brown Jr (KC1JMH)
"""

import fcntl
import json
import math
import os
import re
import sys
import tempfile
import time
import traceback
import urllib.parse
import urllib.request
from contextlib import contextmanager
from datetime import datetime, timezone

VERSION = "1.6"

# NomadNet passes no environment beyond PATH, so these defaults are what the
# container uses. The env overrides exist for running pages locally.
APP_ROOT = os.environ.get("RNS_APPS_ROOT", os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
DATA_DIR = os.environ.get("RNS_APPS_DATA", "/data/apps")
CACHE_DIR = os.path.join(DATA_DIR, "cache")

HTTP_TIMEOUT = 8
USER_AGENT = "rns-apps/{} (+https://github.com/bradbrownjr/rns-apps)".format(VERSION)
CALLSIGN_RE = re.compile(r"^[A-Z]{1,2}\d[A-Z]{1,3}$")
HANDLE_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_.-]{1,19}$")

# Micron colors
C_HEAD = "fd8"
C_LINK = "7cf"
C_DIM = "888"
C_WARN = "f84"
C_OK = "8d8"


# ---------------------------------------------------------------- request ---

def identity():
    """Visitor's identity hash (hex), or None if they did not identify."""
    value = os.environ.get("remote_identity", "").strip().lower()
    return value if re.fullmatch(r"[0-9a-f]{32}", value) else None


def var(name, default=""):
    return os.environ.get("var_" + name, default).strip()


def field(name, default=""):
    return os.environ.get("field_" + name, default).strip()


def arg(name, default=""):
    """Form field if submitted, else link variable. Lets one page take both."""
    return field(name) or var(name, default)


def int_var(name, default=0):
    try:
        return int(var(name, str(default)))
    except ValueError:
        return default


# ----------------------------------------------------------------- micron ---

def esc(text):
    """Escape untrusted text for inline micron. Newlines become spaces."""
    text = str(text).replace("\r", " ").replace("\n", " ")
    return text.replace("\\", "\\\\").replace("`", "\\`")


def paragraphs(text):
    """Escape multi-line text for micron, keeping its line breaks."""
    return [esc(line) if line.strip() else "" for line in str(text).replace("\r", "").split("\n")]


def literal(text):
    """Wrap preformatted text (NWS products etc.) in a micron literal block."""
    body = str(text).replace("`", "'").rstrip()
    return "`=\n{}\n`=".format(body)


def link(label, page, **variables):
    """Link to a page on this node. page is a name like 'wall' or a full path."""
    path = page if page.startswith("/") else "/page/{}.mu".format(page)
    target = ":" + path
    extra = "|".join("{}={}".format(k, v) for k, v in variables.items())
    if extra:
        target += "`" + extra
    return "`F{}`_`[{}`{}]`_`f".format(C_LINK, esc(label), target)


def submit(label, page, fields="*", **variables):
    """Link that submits form fields (all by default) plus link variables."""
    path = page if page.startswith("/") else "/page/{}.mu".format(page)
    parts = [fields] if fields else []
    parts += ["{}={}".format(k, v) for k, v in variables.items()]
    return "`B357`F{}`[ {} `:{}`{}]`f`b".format("fff", esc(label), path, "|".join(parts))


def input_field(name, width=40, value=""):
    return "`B333`<{}|{}`{}>`b".format(width, name, esc(value))


def dim(text):
    return "`F{}{}`f".format(C_DIM, esc(text))


def color(text, rgb):
    return "`F{}{}`f".format(rgb, esc(text))


def bold(text):
    return "`!{}`!".format(esc(text))


def heading(title, level=1):
    return "{}{}".format(">" * level, esc(title))


def divider():
    return "-"


def nav(*extra):
    """Footer navigation. extra is a list of (label, page) or prebuilt links."""
    items = []
    for item in extra:
        items.append(link(*item) if isinstance(item, tuple) else item)
    items.append(link("Main menu", "index"))
    return "\n".join(["", divider(), "  ".join(items)])


# ------------------------------------------------------------------ files ---

def data_path(name):
    os.makedirs(DATA_DIR, exist_ok=True)
    return os.path.join(DATA_DIR, name)


@contextmanager
def locked(name):
    """Exclusive lock for read-modify-write on a data file."""
    with open(data_path(name + ".lock"), "w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        try:
            yield
        finally:
            fcntl.flock(lock, fcntl.LOCK_UN)


def load_json(path, default):
    try:
        with open(path) as f:
            return json.load(f)
    except (OSError, ValueError):
        return default


def save_json(path, data):
    """Atomic write: temp file in the same directory, then rename."""
    folder = os.path.dirname(path)
    os.makedirs(folder, exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=folder, prefix=".tmp-")
    try:
        with os.fdopen(fd, "w") as f:
            json.dump(data, f, indent=2)
        os.replace(tmp, path)
    except Exception:
        if os.path.exists(tmp):
            os.remove(tmp)
        raise


def config():
    """Node config from DATA_DIR/config.json (see config.example.json)."""
    cfg = load_json(data_path("config.json"), {})
    cfg.setdefault("node_name", "rns-apps")
    cfg.setdefault("sysops", [])
    cfg["sysops"] = [s.lower() for s in cfg["sysops"]]
    return cfg


def load_apps():
    return load_json(os.path.join(APP_ROOT, "apps.json"), {"categories": {}})


# ------------------------------------------------------------------ users ---

def users():
    return load_json(data_path("users.json"), {})


def profile(ident):
    """Registered profile dict (handle, and optional name/callsign/location), or {}."""
    return users().get(ident, {}) if ident else {}


def handle_for(ident):
    return profile(ident).get("handle")


def callsign_for(ident):
    """Optional amateur callsign. Apps that need one should ask when this is None."""
    return profile(ident).get("callsign") or None


RESERVED_HANDLES = {"sysop", "admin", "administrator", "root", "moderator", "mod", "system", "staff",
                    "support", "postmaster", "guest", "anonymous", "node", "bbs"}


def handle_skeleton(handle):
    """Lookalike-proof form of a handle: case, separators and common
    substitutions (0/o, 1/l/i, 5/s, 3/e) are folded so 'Brad', 'BRAD',
    'Br4d'-style and 'Bradl'/'BradI' variants collide."""
    h = re.sub(r"[_.\-]", "", handle.lower())
    return h.translate(str.maketrans({"0": "o", "1": "l", "i": "l", "5": "s", "3": "e", "$": "s"}))


def handle_reserved_for(handle):
    """Identity that owns this handle by config, '' if reserved for nobody,
    None if free. config.json: "sysop_handles": {"<identity>": "Brad"} and
    optional "reserved_handles": ["..."]."""
    cfg = config()
    skel = handle_skeleton(handle)
    for ident, name in (cfg.get("sysop_handles") or {}).items():
        if handle_skeleton(name) == skel:
            return ident.lower()
    for name in RESERVED_HANDLES | set(h.lower() for h in cfg.get("reserved_handles", [])):
        if handle_skeleton(name) == skel:
            return ""
    return None


def sysop_badge(ident):
    return color(" [sysop]", C_OK) if is_sysop(ident) else ""


def save_profile(ident, handle, name="", callsign="", location=""):
    """
    Validate and store a profile. Only the handle is required and public;
    name, callsign and location are optional and visible to sysops only.
    Returns (ok, message).
    """
    handle, name, location = handle.strip(), " ".join(name.split()), " ".join(location.split())
    callsign = callsign.strip().upper()
    if not HANDLE_RE.match(handle):
        return False, "Handle must be 2-20 letters, digits, '_', '.' or '-'."
    if callsign and not CALLSIGN_RE.match(callsign):
        return False, "'{}' doesn't look like a callsign (no SSID). Leave it blank if you have none.".format(callsign)
    if len(name) > 40 or len(location) > 40:
        return False, "Name and location are limited to 40 characters."
    owner = handle_reserved_for(handle)
    if owner is not None and owner != ident and not is_sysop(ident):
        return False, "Handle '{}' is reserved.".format(handle)
    if owner == "" and not is_sysop(ident):
        return False, "Handle '{}' is reserved.".format(handle)
    with locked("users"):
        data = users()
        for other, rec in data.items():
            if other != ident and handle_skeleton(rec.get("handle", "")) == handle_skeleton(handle):
                return False, "Handle '{}' is too close to one already taken.".format(handle)
        rec = data.get(ident, {})
        rec.update({"handle": handle, "name": name, "callsign": callsign, "location": location,
                    "updated": utc_iso()})
        rec.setdefault("registered", rec["updated"])
        data[ident] = rec
        save_json(data_path("users.json"), data)
    return True, "Saved."


def clear_profile(ident):
    with locked("users"):
        data = users()
        removed = data.pop(ident, None) is not None
        save_json(data_path("users.json"), data)
    return removed


def is_sysop(ident):
    return bool(ident) and ident in config()["sysops"]


def display_name(ident):
    """Handle if registered, else a short identity tag."""
    handle = handle_for(ident)
    if handle:
        return handle
    return "<{}>".format(ident[:8]) if ident else "guest"


# ------------------------------------------------------------------- time ---

def utc_now():
    return datetime.now(timezone.utc)


def utc_iso():
    return utc_now().strftime("%Y-%m-%dT%H:%M:%SZ")


def fmt_ts(iso, fmt="%m/%d %H:%M"):
    try:
        return datetime.strptime(iso, "%Y-%m-%dT%H:%M:%SZ").strftime(fmt)
    except (TypeError, ValueError):
        return "--/-- --:--"


def age_text(epoch):
    minutes = int((time.time() - epoch) / 60)
    if minutes < 60:
        return "{} min ago".format(minutes)
    if minutes < 48 * 60:
        return "{} h ago".format(minutes // 60)
    return "{} days ago".format(minutes // 1440)


# ------------------------------------------------------------------ fetch ---

def http_get(url, timeout=HTTP_TIMEOUT, headers=None):
    hdrs = {"User-Agent": USER_AGENT}
    hdrs.update(headers or {})
    req = urllib.request.Request(url, headers=hdrs)
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        return resp.read()


def http_json(url, timeout=HTTP_TIMEOUT, headers=None):
    return json.loads(http_get(url, timeout, headers).decode("utf-8", "replace"))


def cached(key, ttl, fetch):
    """
    Return (data, fetched_epoch, stale) for a cache key.

    Serves the cache while it is younger than ttl seconds. Otherwise calls
    fetch(), stores the result, and falls back to the old cache if fetch()
    fails. Returns (None, None, True) when there is nothing at all.
    """
    os.makedirs(CACHE_DIR, exist_ok=True)
    path = os.path.join(CACHE_DIR, re.sub(r"[^A-Za-z0-9_.-]", "_", key) + ".json")
    entry = load_json(path, None)
    if entry and time.time() - entry.get("ts", 0) < ttl:
        return entry["data"], entry["ts"], False
    try:
        data = fetch()
        entry = {"ts": time.time(), "data": data}
        save_json(path, entry)
        return data, entry["ts"], False
    except Exception:
        log_error("fetch failed for {}".format(key))
        if entry:
            return entry["data"], entry["ts"], True
        return None, None, True


def cache_peek(key):
    """(data, ts) from the cache regardless of age, or (None, None). Never fetches."""
    path = os.path.join(CACHE_DIR, re.sub(r"[^A-Za-z0-9_.-]", "_", key) + ".json")
    entry = load_json(path, None)
    return (entry["data"], entry["ts"]) if entry else (None, None)


def freshness(ts, stale):
    """One-line note on where the data came from."""
    if ts is None:
        return color("Source unavailable and nothing cached yet. Try again later.", C_WARN)
    stamp = datetime.fromtimestamp(ts, timezone.utc).strftime("%Y-%m-%d %H:%M UTC")
    if stale:
        return color("OFFLINE: showing cached copy from {} ({})".format(stamp, age_text(ts)), C_WARN)
    return dim("Updated {} ({})".format(stamp, age_text(ts)))


# -------------------------------------------------------------------- geo ---

GRID_RE = re.compile(r"^[A-R]{2}\d{2}([A-X]{2})?$", re.I)
LATLON_RE = re.compile(r"^\s*(-?\d{1,2}(?:\.\d+)?)\s*[, ]\s*(-?\d{1,3}(?:\.\d+)?)\s*$")


def grid_to_latlon(grid):
    """Center of a 4 or 6 character Maidenhead locator -> (lat, lon)."""
    g = grid.strip().upper()
    lon = (ord(g[0]) - 65) * 20 - 180
    lat = (ord(g[1]) - 65) * 10 - 90
    lon += int(g[2]) * 2
    lat += int(g[3])
    if len(g) >= 6:
        lon += (ord(g[4]) - 65) * (2 / 24) + (1 / 24)
        lat += (ord(g[5]) - 65) * (1 / 24) + (1 / 48)
    else:
        lon += 1
        lat += 0.5
    return lat, lon


def distance_mi(lat1, lon1, lat2, lon2):
    """Great-circle distance in miles."""
    p1, p2 = math.radians(lat1), math.radians(lat2)
    dp, dl = p2 - p1, math.radians(lon2 - lon1)
    h = math.sin(dp / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) ** 2
    return 3958.8 * 2 * math.asin(math.sqrt(h))


def hamdb(call):
    """HamDB (US FCC data) record for a callsign, or None. Cached 24 h."""
    call = call.upper()
    data, _, _ = cached("hamdb_" + call, 86400,
                        lambda: http_json("https://api.hamdb.org/v1/{}/json".format(call)))
    rec = (data or {}).get("hamdb", {}).get("callsign", {})
    return rec if rec.get("call") and rec.get("call") != "NOT_FOUND" else None


def nws_point(lat, lon):
    """NWS /points metadata (grid, forecast URLs, nearest city/state). Cached 30 days."""
    key = "nwspoint_{:.4f}_{:.4f}".format(lat, lon)
    data, _, _ = cached(key, 30 * 86400,
                        lambda: http_json("https://api.weather.gov/points/{:.4f},{:.4f}".format(lat, lon)))
    return (data or {}).get("properties") or {}


def resolve_location(text):
    """
    Turn user input into (lat, lon, label). Accepts a callsign (HamDB),
    a Maidenhead grid, 'lat,lon', or a place name / ZIP (OpenStreetMap
    Nominatim, cached 30 days). Raises ValueError with a visitor-friendly
    message when it can't.
    """
    text = " ".join(text.split())
    if not text:
        raise ValueError("Enter a callsign, grid square, ZIP or place name.")
    if CALLSIGN_RE.match(text.upper()):
        rec = hamdb(text)
        if not rec or not rec.get("lat"):
            raise ValueError("No location found for callsign {}.".format(text.upper()))
        return float(rec["lat"]), float(rec["lon"]), text.upper()
    if GRID_RE.match(text):
        lat, lon = grid_to_latlon(text)
        return lat, lon, text.upper()
    m = LATLON_RE.match(text)
    if m:
        return float(m.group(1)), float(m.group(2)), "{}, {}".format(m.group(1), m.group(2))
    url = "https://nominatim.openstreetmap.org/search?format=json&limit=1&countrycodes=us&q=" + urllib.parse.quote(text)
    data, _, _ = cached("geo_" + text.lower(), 30 * 86400, lambda: http_json(url))
    if not data:
        raise ValueError("Couldn't find '{}'. Try a ZIP, 'City ST', or a grid square.".format(text))
    return float(data[0]["lat"]), float(data[0]["lon"]), text


# ------------------------------------------------------------------- run ---

def log_error(context):
    try:
        with open(data_path("errors.log"), "a") as f:
            f.write("[{}] {}\n{}\n".format(utc_iso(), context, traceback.format_exc()))
    except OSError:
        pass


def run(render, cache_seconds=0):
    """
    Entry point for every page. render() returns micron text.

    NomadNet discards stderr, so failures are logged to DATA_DIR/errors.log
    and the visitor gets a short error page instead of a blank one.
    """
    try:
        body = render()
    except Exception:
        log_error("page {} failed".format(os.path.basename(sys.argv[0])))
        body = "\n".join([
            heading("Error"),
            "Something went wrong building this page. It has been logged.",
            nav(),
        ])
    sys.stdout.write("#!c={}\n".format(cache_seconds))
    sys.stdout.write(body.rstrip() + "\n")
