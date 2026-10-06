#!/usr/bin/env python3
"""
Wikipedia browser (port of bpq-apps wiki.py): search and read Wikipedia and
its sister projects with the MediaWiki API. Articles are plain text, cached
for a day, paged by character count, and end with links to related articles.

Version: 1.0
Author: Brad Brown Jr (KC1JMH)
"""

import os
import re
import sys
import urllib.parse

sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.realpath(__file__))), "lib"))
import htmltext  # noqa: E402
import rnsapps as ra  # noqa: E402

VERSION = "1.0"
CHUNK = 2000
TTL = 86400
SITES = [
    ("wp", "Wikipedia", "en.wikipedia.org"),
    ("simple", "Simple English", "simple.wikipedia.org"),
    ("wikt", "Wiktionary", "en.wiktionary.org"),
    ("quote", "Wikiquote", "en.wikiquote.org"),
    ("news", "Wikinews", "en.wikinews.org"),
    ("voyage", "Wikivoyage", "en.wikivoyage.org"),
]
HOSTS = {key: host for key, _, host in SITES}
NAMES = {key: name for key, name, _ in SITES}


def enc(title):
    return urllib.parse.quote(title, safe=" ,()'-._~:")


def dec(text):
    return urllib.parse.unquote(text)


def api(host, **params):
    params["format"] = "json"
    return ra.http_json("https://{}/w/api.php?{}".format(host, urllib.parse.urlencode(params)), timeout=12)


def search(host, query):
    data = api(host, action="query", list="search", srsearch=query, srlimit=8, srprop="snippet")
    return [{"title": r["title"], "snippet": htmltext.strip_tags(r.get("snippet", ""))}
            for r in data.get("query", {}).get("search", [])]


def article(host, title):
    data = api(host, action="query", prop="extracts|links", titles=title, redirects=1, explaintext=1,
               exsectionformat="wiki", plnamespace=0, pllimit=40)
    pages = data.get("query", {}).get("pages", {})
    page = next(iter(pages.values()), {})
    if "missing" in page:
        return None
    return {"title": page.get("title", title), "text": page.get("extract", ""),
            "links": [l["title"] for l in page.get("links", [])]}


def random_title(host):
    data = api(host, action="query", list="random", rnnamespace=0, rnlimit=1)
    return data["query"]["random"][0]["title"]


def format_text(text):
    out = []
    for line in text.replace("\r", "").split("\n"):
        m = re.match(r"^(=+)\s*(.*?)\s*=+$", line)
        if m:
            out += ["", ra.heading(m.group(2), min(len(m.group(1)) - 1, 3) or 1)]
        else:
            out.append(ra.esc(line) if line.strip() else "")
    return out


def render():
    site = ra.var("s", "wp")
    if site not in HOSTS:
        site = "wp"
    host = HOSTS[site]
    query = ra.field("q") or dec(ra.var("q"))
    title = dec(ra.var("t"))
    out = [ra.heading("Wikipedia" if site == "wp" else NAMES[site]),
           "Search: {}".format(ra.input_field("q", 28, query)),
           "{}  {}".format(ra.submit("Search", "wiki", "q", s=site), ra.link("Random", "wiki", s=site, r=1)), ""]
    sites = [ra.bold(n) if k == site else ra.link(n, "wiki", s=k) for k, n, _ in SITES]
    out += [ra.dim("Source: ") + "  ".join(sites), ""]

    try:
        if ra.var("r"):
            title = random_title(host)
        if title:
            art, ts, stale = ra.cached("wiki_{}_{}".format(site, title.lower()), TTL, lambda: article(host, title))
            if art is None:
                return "\n".join(out + ["No such article: {}".format(ra.bold(title)), ra.nav()])
            text, o = art["text"], ra.int_var("o", 0)
            out += [ra.heading(art["title"]), ra.freshness(ts, stale), ""]
            piece = text[o:o + CHUNK]
            if o + CHUNK < len(text):
                piece = piece.rsplit("\n", 1)[0] if "\n" in piece[len(piece) // 2:] else piece.rsplit(" ", 1)[0]
            out += format_text(piece)
            end = o + len(piece)
            pager = []
            if o > 0:
                pager.append(ra.link("< Back", "wiki", s=site, t=enc(art["title"]), o=max(o - CHUNK, 0)))
            if end < len(text):
                pager.append(ra.link("More >", "wiki", s=site, t=enc(art["title"]), o=end))
            out += [""] + [" ".join(pager)] if pager else []
            if end >= len(text) and art["links"]:
                out += ["", ra.heading("Related", 2)]
                out += [ra.link(l[:60], "wiki", s=site, t=enc(l)) for l in art["links"][:20]]
            out.append(ra.dim("{} - text available under CC BY-SA".format(host)))
            return "\n".join(out + [ra.nav()])
        if query:
            results, ts, stale = ra.cached("wikisearch_{}_{}".format(site, query.lower()), 3600, lambda: search(host, query))
            if not results:
                return "\n".join(out + ["No results for {}.".format(ra.bold(query)), ra.nav()])
            for r in results:
                out += [ra.link(r["title"][:60], "wiki", s=site, t=enc(r["title"])), ra.dim(r["snippet"][:90]), ""]
            return "\n".join(out + [ra.nav()])
    except Exception:
        ra.log_error("wiki {} {} {}".format(site, query, title))
        return "\n".join(out + [ra.color("Wikipedia is unreachable right now and that page isn't cached.", ra.C_WARN), ra.nav()])
    return "\n".join(out + [ra.dim("Type a topic to search, or try Random."), ra.nav()])


if __name__ == "__main__":
    ra.run(render)
