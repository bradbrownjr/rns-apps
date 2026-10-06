#!/usr/bin/env python3
"""
Text web browser (port of bpq-apps www.py): fetch a page, strip it to text,
and make its links followable. Type a URL, or words to search FrogFind (a
text-friendly search engine).

Only public http(s) hosts are fetched (private, loopback and link-local
addresses are refused, including via redirects), responses are capped at
500 KB and cached for 30 minutes. gopher:// links open in the GOPHER page.

Optional config.json key "www_bookmarks": [{"name": ..., "url": ...}].

Version: 1.0
Author: Brad Brown Jr (KC1JMH)
"""

import ipaddress
import os
import re
import socket
import sys
import urllib.error
import urllib.parse
import urllib.request

sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.realpath(__file__))), "lib"))
import htmltext  # noqa: E402
import rnsapps as ra  # noqa: E402

VERSION = "1.0"
TTL = 1800
MAX_BYTES = 500 * 1024
TIMEOUT = 12
LINES_PER_PAGE = 40
BOOKMARKS = [
    {"name": "FrogFind search", "url": "https://frogfind.com/"},
    {"name": "NPR text news", "url": "https://text.npr.org/"},
    {"name": "CNN lite", "url": "https://lite.cnn.com/"},
    {"name": "Wikipedia (see also WIKI)", "url": "https://en.m.wikipedia.org/"},
    {"name": "ARRL", "url": "https://www.arrl.org/"},
]


def check_public(url):
    """Raise PermissionError unless url is http(s) to a public host."""
    parts = urllib.parse.urlsplit(url)
    if parts.scheme not in ("http", "https") or not parts.hostname:
        raise PermissionError("Only http and https addresses work here.")
    if parts.port not in (None, 80, 443, 8080, 8443):
        raise PermissionError("That port isn't allowed.")
    for info in socket.getaddrinfo(parts.hostname, None, type=socket.SOCK_STREAM):
        if not ipaddress.ip_address(info[4][0]).is_global:
            raise PermissionError("That host isn't on the public internet.")


class SafeRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        check_public(newurl)
        return super().redirect_request(req, fp, code, msg, headers, newurl)


def fetch(url):
    check_public(url)
    opener = urllib.request.build_opener(SafeRedirect)
    req = urllib.request.Request(url, headers={"User-Agent": ra.USER_AGENT, "Accept": "text/html,text/plain;q=0.9"})
    with opener.open(req, timeout=TIMEOUT) as resp:
        ctype = resp.headers.get("Content-Type", "")
        raw = resp.read(MAX_BYTES)
        final = resp.geturl()
    if "html" not in ctype and "text" not in ctype and ctype:
        return {"url": final, "kind": "other", "type": ctype, "body": ""}
    charset = re.search(r"charset=([\w-]+)", ctype)
    body = raw.decode(charset.group(1) if charset else "utf-8", "replace")
    return {"url": final, "kind": "text" if "html" not in ctype else "html", "type": ctype, "body": body}


def enc(url):
    return urllib.parse.quote(url, safe="/:")


def clean(value):
    return value.replace("|", " ").replace("`", " ").replace("=", " ").strip()


def link_fn(label, url):
    m = re.match(r"^https?://duckduckgo\.com/l/\?(?:.*&)?uddg=([^&]+)", url)
    if m:
        url = urllib.parse.unquote(m.group(1))
    if url.startswith("gopher://"):
        return ra.link(label[:60], "gopher", g=enc(url))
    if url.startswith(("http://", "https://")):
        return ra.link(label[:60], "www", u=enc(url))
    return ra.esc(label)


def normalize(text):
    text = text.strip()
    if re.match(r"^https?://", text, re.I):
        return text
    if " " not in text and "." in text and not text.endswith("."):
        return "https://" + text
    return "https://frogfind.com/?q=" + urllib.parse.quote_plus(text)


def render():
    cfg = ra.config()
    target = urllib.parse.unquote(ra.var("u")) or (normalize(clean(ra.field("url"))) if clean(ra.field("url")) else "")
    out = [ra.heading("Web"), "URL or search words:", ra.input_field("url", 30, ""), ra.submit("Go", "www", "url"), ""]
    if not target:
        out.append(ra.heading("Bookmarks", 2))
        out += [ra.link(b["name"][:40], "www", u=enc(b["url"])) for b in cfg.get("www_bookmarks", BOOKMARKS)]
        out += ["", ra.dim("Text-only browsing: no images, scripts or forms.")]
        return "\n".join(out + [ra.nav()])

    try:
        check_public(target)
    except PermissionError as e:
        return "\n".join(out + [ra.color(str(e), ra.C_WARN), ra.nav(("Web home", "www"))])
    except OSError:
        return "\n".join(out + [ra.color("Can't resolve that address.", ra.C_WARN), ra.nav(("Web home", "www"))])

    page, ts, stale = ra.cached("www_" + target, TTL, lambda: fetch(target))
    if page is None and target.startswith("https://frogfind.com/?q="):
        # FrogFind is often down; DuckDuckGo's lite page is also plain text.
        target = "https://lite.duckduckgo.com/lite/?q=" + target.split("?q=", 1)[1]
        page, ts, stale = ra.cached("www_" + target, TTL, lambda: fetch(target))
    if page is None:
        return "\n".join(out + [ra.color("Couldn't load that page (and nothing is cached).", ra.C_WARN),
                                ra.dim(urllib.parse.urlsplit(target).netloc), ra.nav(("Web home", "www"))])
    host = urllib.parse.urlsplit(page["url"]).netloc
    out += [ra.bold(host), ra.freshness(ts, stale), ""]
    if page["kind"] == "other":
        out += ["That address is a {} file, which can't be shown here.".format(page["type"] or "binary"), ra.dim(page["url"][:120])]
        return "\n".join(out + [ra.nav(("Web home", "www"))])
    if page["kind"] == "text":
        lines = ra.paragraphs(page["body"])
    else:
        lines = htmltext.to_micron(page["body"], page["url"], link_fn, ra.esc)
    pages = max((len(lines) + LINES_PER_PAGE - 1) // LINES_PER_PAGE, 1)
    p = min(max(ra.int_var("p", 1), 1), pages)
    out += lines[(p - 1) * LINES_PER_PAGE:p * LINES_PER_PAGE] or ["(This page has no readable text.)"]
    out += ["", ra.dim("Page {} of {}".format(p, pages))]
    here = enc(page["url"])
    pager = []
    if p > 1:
        pager.append(ra.link("< Prev", "www", u=here, p=p - 1))
    if p < pages:
        pager.append(ra.link("Next >", "www", u=here, p=p + 1))
    pager.append(ra.link("Web home", "www"))
    return "\n".join(out + [ra.nav(*pager)])


if __name__ == "__main__":
    ra.run(render)
