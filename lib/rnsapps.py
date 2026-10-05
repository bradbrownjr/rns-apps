"""
Shared helpers for rns-apps NomadNet pages.

NomadNet runs an executable page once per request and serves its stdout as
micron. The page gets no stdin, and its environment holds only PATH plus:

    remote_identity   hex identity hash, only if the visitor identified
    link_id           hex link id
    field_<name>      submitted form fields
    var_<name>        link variables

Version: 1.0
Author: Brad Brown Jr (KC1JMH)
"""

import fcntl
import json
import os
import re
import sys
import tempfile
import time
import traceback
import urllib.request
from contextlib import contextmanager
from datetime import datetime, timezone

VERSION = "1.0"

# NomadNet passes no environment beyond PATH, so these defaults are what the
# container uses. The env overrides exist for running pages locally.
APP_ROOT = os.environ.get("RNS_APPS_ROOT", os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
DATA_DIR = os.environ.get("RNS_APPS_DATA", "/data/apps")
CACHE_DIR = os.path.join(DATA_DIR, "cache")

HTTP_TIMEOUT = 8
USER_AGENT = "rns-apps/{} (+https://github.com/bradbrownjr/rns-apps)".format(VERSION)
CALLSIGN_RE = re.compile(r"^[A-Z]{1,2}\d[A-Z]{1,3}$")

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


def callsign_for(ident):
    if not ident:
        return None
    return users().get(ident, {}).get("callsign")


def set_callsign(ident, callsign):
    with locked("users"):
        data = users()
        data[ident] = {"callsign": callsign, "registered": utc_iso()}
        save_json(data_path("users.json"), data)


def is_sysop(ident):
    return bool(ident) and ident in config()["sysops"]


def display_name(ident):
    """Callsign if registered, else a short identity tag."""
    call = callsign_for(ident)
    if call:
        return call
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

def http_get(url, timeout=HTTP_TIMEOUT):
    req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        return resp.read()


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


def freshness(ts, stale):
    """One-line note on where the data came from."""
    if ts is None:
        return color("Source unavailable and nothing cached yet. Try again later.", C_WARN)
    stamp = datetime.fromtimestamp(ts, timezone.utc).strftime("%Y-%m-%d %H:%M UTC")
    if stale:
        return color("OFFLINE: showing cached copy from {} ({})".format(stamp, age_text(ts)), C_WARN)
    return dim("Updated {} ({})".format(stamp, age_text(ts)))


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
