#!/usr/bin/env python3
"""
Gopher browser (port of bpq-apps gopher.py).

Browse gopherspace from Reticulum: menus become links, text files are paged,
search items get a query box. Only public hosts are reachable (private,
loopback and link-local addresses are refused so the node can't be used to
probe its own network). Responses are cached for 30 minutes and capped at
100 KB.

Optional config.json keys: "gopher_home" (default gopher.floodgap.com) and
"gopher_bookmarks" ([{"name": ..., "url": ...}]).

Version: 1.0
Author: Brad Brown Jr (KC1JMH)
"""

import ipaddress
import os
import re
import socket
import sys
import time
import urllib.parse

sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.realpath(__file__))), "lib"))
import rnsapps as ra  # noqa: E402

VERSION = "1.0"
TTL = 1800
MAX_BYTES = 100 * 1024
TIMEOUT = 12
ITEMS_PER_PAGE = 25
CHUNK = 2200
DEFAULT_HOME = "gopher.floodgap.com"
DEFAULT_BOOKMARKS = [
    {"name": "Floodgap", "url": "gopher://gopher.floodgap.com"},
    {"name": "SDF", "url": "gopher://sdf.org"},
    {"name": "Bitreich", "url": "gopher://bitreich.org"},
]
HOST_RE = re.compile(r"^[A-Za-z0-9.-]{1,253}$")


def parse_url(text):
    """gopher://host[:port][/type[selector]] or host[:port] -> (host, port, type, selector)."""
    text = text.strip()
    text = re.sub(r"^gopher://", "", text, flags=re.I)
    hostport, _, rest = text.partition("/")
    host, _, port = hostport.partition(":")
    if not HOST_RE.match(host) or (port and not port.isdigit()):
        raise ValueError("That doesn't look like a gopher address (try gopher.floodgap.com).")
    gtype = rest[:1] or "1"
    selector = urllib.parse.unquote(rest[1:]) if rest else ""
    return host.lower(), int(port or 70), gtype, selector


def public_address(host):
    """First public IP for host, or raises PermissionError."""
    infos = socket.getaddrinfo(host, None, type=socket.SOCK_STREAM)
    for info in infos:
        ip = ipaddress.ip_address(info[4][0])
        if ip.is_global:
            return str(ip), info[0]
    raise PermissionError("That host isn't on the public internet.")


def fetch(host, port, selector, query=None):
    ip, family = public_address(host)
    request = selector + ("\t" + query if query is not None else "") + "\r\n"
    sock = socket.socket(family, socket.SOCK_STREAM)
    sock.settimeout(TIMEOUT)
    deadline = time.time() + TIMEOUT * 2
    try:
        sock.connect((ip, port))
        sock.sendall(request.encode("utf-8", "replace"))
        chunks, size = [], 0
        while size < MAX_BYTES and time.time() < deadline:
            data = sock.recv(8192)
            if not data:
                break
            chunks.append(data)
            size += len(data)
    finally:
        sock.close()
    return b"".join(chunks)[:MAX_BYTES].decode("utf-8", "replace")


def parse_menu(text):
    items = []
    for line in text.replace("\r", "").split("\n"):
        if line == "." or not line:
            continue
        gtype, rest = line[0], line[1:]
        parts = rest.split("\t")
        label = parts[0]
        selector = parts[1] if len(parts) > 1 else ""
        host = parts[2].strip() if len(parts) > 2 else ""
        try:
            port = int(parts[3].strip()) if len(parts) > 3 else 70
        except ValueError:
            port = 70
        items.append({"t": gtype, "label": label, "sel": selector, "host": host, "port": port})
    return items


def addr(host, port, gtype="1", selector=""):
    return "gopher://{}{}/{}{}".format(host, "" if port == 70 else ":{}".format(port), gtype, urllib.parse.quote(selector, safe="/"))


def clean(value):
    return value.replace("|", " ").replace("`", " ").replace("=", " ").strip()


def go(label, host, port, gtype, selector, **extra):
    """Link to a gopher item through this page."""
    return ra.link(label[:70], "gopher", g=urllib.parse.quote(addr(host, port, gtype, selector), safe="/:"), **extra)


def render():
    cfg = ra.config()
    home = cfg.get("gopher_home", DEFAULT_HOME)
    marks = cfg.get("gopher_bookmarks", DEFAULT_BOOKMARKS)
    target = urllib.parse.unquote(ra.var("g")) or clean(ra.field("url"))
    out = [ra.heading("Gopher"),
           "Address: {}".format(ra.input_field("url", 28, "")),
           ra.submit("Go", "gopher", "url"), ""]
    if not target:
        out.append(ra.heading("Bookmarks", 2))
        out += [ra.link(m["name"][:40], "gopher", g=urllib.parse.quote(m["url"], safe="/:")) for m in marks]
        out += ["", ra.link("Home ({})".format(home), "gopher", g=urllib.parse.quote("gopher://" + home, safe="/:")),
                "", ra.dim("Pre-web text internet. Try Floodgap's menus.")]
        return "\n".join(out + [ra.nav()])

    try:
        host, port, gtype, selector = parse_url(target)
    except ValueError as e:
        return "\n".join(out + [ra.color(str(e), ra.C_WARN), ra.nav()])

    query = ra.field("q") or None
    if gtype == "7" and query is None:
        out += [ra.bold(host), "Search: {}".format(ra.input_field("q", 24, "")),
                ra.submit("Search", "gopher", "q", g=urllib.parse.quote(addr(host, port, "7", selector), safe="/:"))]
        return "\n".join(out + [ra.nav(("Gopher home", "gopher"))])
    if gtype not in ("0", "1", "7"):
        out += ["This item is a type '{}' file (binary, image or web page) which can't be shown here.".format(gtype),
                ra.dim(addr(host, port, gtype, selector))]
        return "\n".join(out + [ra.nav(("Gopher home", "gopher"))])

    key = "gopher_{}_{}_{}_{}".format(host, port, selector, query or "")
    try:
        public_address(host)
    except PermissionError as e:
        return "\n".join(out + [ra.color(str(e), ra.C_WARN), ra.nav(("Gopher home", "gopher"))])
    except OSError:
        return "\n".join(out + [ra.color("Can't resolve {}.".format(host), ra.C_WARN), ra.nav(("Gopher home", "gopher"))])
    body, ts, stale = ra.cached(key, TTL, lambda: fetch(host, port, selector, query))
    if body is None:
        return "\n".join(out + [ra.color("Couldn't reach {} (and nothing is cached).".format(host), ra.C_WARN),
                                ra.nav(("Gopher home", "gopher"))])

    out += [ra.bold(host), ra.freshness(ts, stale), ""]
    here = urllib.parse.quote(addr(host, port, gtype, selector), safe="/:")

    if gtype == "0":
        o = ra.int_var("o", 0)
        piece = body[o:o + CHUNK]
        if o + CHUNK < len(body):
            piece = piece.rsplit("\n", 1)[0] if "\n" in piece[len(piece) // 2:] else piece.rsplit(" ", 1)[0]
        out += ra.paragraphs(piece)
        end = o + len(piece)
        pager = []
        if o > 0:
            pager.append(ra.link("< Back", "gopher", g=here, o=max(o - CHUNK, 0)))
        if end < len(body):
            pager.append(ra.link("More >", "gopher", g=here, o=end))
        if pager:
            out += ["", "  ".join(pager)]
        return "\n".join(out + [ra.nav(("Gopher home", "gopher"))])

    items = parse_menu(body)
    page = max(ra.int_var("p", 1), 1)
    pages = max((len(items) + ITEMS_PER_PAGE - 1) // ITEMS_PER_PAGE, 1)
    page = min(page, pages)
    for it in items[(page - 1) * ITEMS_PER_PAGE:page * ITEMS_PER_PAGE]:
        t = it["t"]
        if t == "i" or t == "3":
            out.append(ra.esc(it["label"]) if it["label"].strip() else "")
        elif t in ("0", "1", "7") and it["host"]:
            mark = {"0": "", "1": "/", "7": " ?"}[t]
            out.append(go(it["label"] + mark, it["host"], it["port"], t, it["sel"]))
        elif t == "h" and it["sel"].upper().startswith("URL:"):
            out.append(ra.dim("[web] {}".format(it["label"][:50])))
            out.append(ra.dim(it["sel"][4:][:120]))
        else:
            out.append(ra.dim("[{}] {}".format(t, it["label"][:60])))
    out += ["", ra.dim("Page {} of {}".format(page, pages))]
    pager = []
    if page > 1:
        pager.append(ra.link("< Prev", "gopher", g=here, p=page - 1))
    if page < pages:
        pager.append(ra.link("Next >", "gopher", g=here, p=page + 1))
    pager.append(ra.link("Gopher home", "gopher"))
    return "\n".join(out + [ra.nav(*pager)])


if __name__ == "__main__":
    ra.run(render)
