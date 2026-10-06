#!/usr/bin/env python3
"""
News feeds (port of bpq-apps rss-news.py): RSS and Atom headlines grouped by
category, summaries, and an optional readable full article.

Feeds live in feeds.json (category -> [{name, url}]). Each feed is cached for
30 minutes and served stale, clearly marked, when it can't be fetched.

Version: 1.0
Author: Brad Brown Jr (KC1JMH)
"""

import json
import os
import sys
import xml.etree.ElementTree as ET
from email.utils import parsedate_to_datetime

sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.realpath(__file__))), "lib"))
import htmltext  # noqa: E402
import rnsapps as ra  # noqa: E402

VERSION = "1.0"
TTL = 1800
ARTICLE_TTL = 6 * 3600
PER_PAGE = 8
CHUNK = 2200
MAX_ITEMS = 40
MAX_BYTES = 600_000


def feed_list():
    data = ra.load_json(os.path.join(ra.APP_ROOT, "feeds.json"), {"categories": {}})
    flat = []
    for cat, feeds in data["categories"].items():
        for f in feeds:
            flat.append(dict(f, category=cat))
    return flat


def local(tag):
    return tag.rsplit("}", 1)[-1]


def child_text(el, *names):
    for c in el:
        if local(c.tag) in names and (c.text or "").strip():
            return c.text.strip()
    return ""


def parse_date(text):
    if not text:
        return None
    try:
        return parsedate_to_datetime(text).timestamp()
    except (TypeError, ValueError):
        pass
    try:
        from datetime import datetime
        return datetime.fromisoformat(text.replace("Z", "+00:00")).timestamp()
    except ValueError:
        return None


def parse_feed(raw):
    root = ET.fromstring(raw)
    items = []
    for el in root.iter():
        if local(el.tag) not in ("item", "entry"):
            continue
        link = child_text(el, "link")
        if not link:
            for c in el:
                if local(c.tag) == "link" and c.get("href"):
                    link = c.get("href")
                    break
        body = child_text(el, "encoded", "content", "description", "summary")
        items.append({
            "title": htmltext.strip_tags(child_text(el, "title")) or "(untitled)",
            "link": link,
            "ts": parse_date(child_text(el, "pubDate", "updated", "published", "date")),
            "summary": htmltext.strip_tags(body),
        })
        if len(items) >= MAX_ITEMS:
            break
    return items


def fetch_feed(url):
    return parse_feed(ra.http_get(url, timeout=12)[:MAX_BYTES])


def fetch_article(url):
    return htmltext.article_text(ra.http_get(url, timeout=12)[:MAX_BYTES * 2].decode("utf-8", "replace"))


def when(ts):
    return ra.age_text(ts) if ts else ""


def menu():
    out = [ra.heading("News"), ""]
    seen = []
    for f in feed_list():
        if f["category"] not in seen:
            seen.append(f["category"])
    out += [ra.link(c, "news", c=seen.index(c)) for c in seen]
    return out + [ra.nav()]


def feeds_in(cat_idx):
    cats = []
    for f in feed_list():
        if f["category"] not in cats:
            cats.append(f["category"])
    if not 0 <= cat_idx < len(cats):
        return None, []
    return cats[cat_idx], [(i, f) for i, f in enumerate(feed_list()) if f["category"] == cats[cat_idx]]


def render():
    feeds = feed_list()
    if not feeds:
        return "\n".join([ra.heading("News"), "No feeds are configured.", ra.nav()])
    fi = ra.var("f")
    if not fi:
        c = ra.var("c")
        if c == "":
            return "\n".join(menu())
        cat, rows = feeds_in(ra.int_var("c", -1))
        if not cat:
            return "\n".join(menu())
        return "\n".join([ra.heading(cat)] + [ra.link(f["name"], "news", f=i, c=c) for i, f in rows] + [ra.nav(("News", "news"))])

    idx = ra.int_var("f", -1)
    if not 0 <= idx < len(feeds):
        return "\n".join(menu())
    feed, c = feeds[idx], ra.var("c")
    items, ts, stale = ra.cached("news_{}".format(idx), TTL, lambda: fetch_feed(feed["url"]))
    back = ra.link("Headlines", "news", f=idx, c=c)
    out = [ra.heading(feed["name"]), ra.freshness(ts, stale), ""]
    if not items:
        return "\n".join(out + [ra.nav(ra.link("Feeds", "news", c=c))])

    i = ra.var("i")
    if i != "":
        n = ra.int_var("i", -1)
        if not 0 <= n < len(items):
            return "\n".join(out + ["That item has dropped off the feed.", ra.nav(back)])
        it = items[n]
        o = ra.int_var("o", 0)
        out = [ra.heading(it["title"]), ra.dim(when(it["ts"]))]
        if ra.var("full"):
            text, ats, astale = ra.cached("article_{}_{}".format(idx, n), ARTICLE_TTL, lambda: fetch_article(it["link"]))
            if not text:
                out += ["", ra.color("Couldn't load the full article.", ra.C_WARN)] + ra.paragraphs(it["summary"][:CHUNK])
            else:
                out += [""] + ra.paragraphs(text[o:o + CHUNK].rsplit(" ", 1)[0] if o + CHUNK < len(text) else text[o:])
                nav = []
                if o > 0:
                    nav.append(ra.link("< Back", "news", f=idx, i=n, c=c, full=1, o=max(o - CHUNK, 0)))
                if o + CHUNK < len(text):
                    nav.append(ra.link("More >", "news", f=idx, i=n, c=c, full=1, o=o + CHUNK))
                out += [""] + nav
        else:
            out += [""] + ra.paragraphs(it["summary"][:CHUNK] or "(no summary in this feed)")
            if it["link"]:
                out += ["", ra.link("Load full article", "news", f=idx, i=n, c=c, full=1), ra.dim(it["link"])]
        return "\n".join(out + [ra.nav(back)])

    pages = max((len(items) + PER_PAGE - 1) // PER_PAGE, 1)
    page = min(max(ra.int_var("p", 1), 1), pages)
    for n in range((page - 1) * PER_PAGE, min(page * PER_PAGE, len(items))):
        out += [ra.link(items[n]["title"][:90], "news", f=idx, i=n, c=c), ra.dim(when(items[n]["ts"])), ""]
    out.append(ra.dim("Page {} of {}".format(page, pages)))
    pager = []
    if page > 1:
        pager.append(ra.link("< Prev", "news", f=idx, c=c, p=page - 1))
    if page < pages:
        pager.append(ra.link("Next >", "news", f=idx, c=c, p=page + 1))
    pager.append(ra.link("Feeds", "news", c=c))
    return "\n".join(out + [ra.nav(*pager)])


if __name__ == "__main__":
    ra.run(render)
