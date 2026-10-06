#!/usr/bin/env python3
"""
Club calendar (port of bpq-apps eventcal.py), from a public iCal feed.

Set "ical_url" (and optionally "timezone", default America/New_York) in
/data/apps/config.json. The feed is cached for an hour and served stale,
clearly marked, if it can't be fetched.

Version: 1.0
Author: Brad Brown Jr (KC1JMH)
"""

import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.realpath(__file__))), "lib"))
import rnsapps as ra  # noqa: E402
import htmltext  # noqa: E402
import ical  # noqa: E402

VERSION = "1.0"
TTL = 3600
PER_PAGE = 8


def when(ev, long=False):
    s, e = ev["start"], ev["end"]
    if ev["allday"]:
        return s.strftime("%a %b %-d") + ("" if long else " (all day)")
    if long:
        return "{} {} - {}".format(s.strftime("%a %b %-d, %Y"), s.strftime("%-I:%M %p"), e.strftime("%-I:%M %p %Z"))
    return s.strftime("%a %b %-d  %-I:%M %p")


def detail(events, ev_id):
    ev = next((e for e in events if e["id"] == ev_id), None)
    if not ev:
        return [ra.heading("Event"), "That event is no longer on the calendar.", ra.nav(("Calendar", "calendar"))]
    out = [ra.heading(ev["summary"]), ra.bold(when(ev, True))]
    if ev["location"]:
        out.append(ra.esc(" ".join(ev["location"].split())))
    desc = htmltext.strip_tags(ev["description"])
    if desc:
        out += [""] + ra.paragraphs(desc[:1500])
    return out + [ra.nav(("Calendar", "calendar"))]


def render():
    cfg = ra.config()
    url = cfg.get("ical_url")
    if not url:
        return "\n".join([ra.heading("Calendar"), "No calendar is configured on this node yet.",
                          ra.dim("Sysop: set ical_url in config.json."), ra.nav()])
    text, ts, stale = ra.cached("ical", TTL, lambda: ra.http_get(url, timeout=15).decode("utf-8", "replace"))
    if text is None:
        return "\n".join([ra.heading("Calendar"), ra.freshness(ts, stale), ra.nav()])
    events = ical.upcoming(text, cfg.get("timezone", "America/New_York"), days_back=0, days_ahead=180)

    if ra.var("e"):
        return "\n".join(detail(events, ra.var("e")))

    out = [ra.heading("Calendar"), ra.freshness(ts, stale), ""]
    pages = max((len(events) + PER_PAGE - 1) // PER_PAGE, 1)
    page = min(max(ra.int_var("p", 1), 1), pages)
    if not events:
        out.append("No upcoming events in the next 6 months.")
    for ev in events[(page - 1) * PER_PAGE:page * PER_PAGE]:
        out.append(ra.dim(when(ev)))
        out.append(ra.link(ev["summary"][:60], "calendar", e=ev["id"]))
        out.append("")
    out.append(ra.dim("Page {} of {}  (times {})".format(page, pages, cfg.get("timezone", "America/New_York"))))
    pager = []
    if page > 1:
        pager.append(ra.link("< Prev", "calendar", p=page - 1))
    if page < pages:
        pager.append(ra.link("Next >", "calendar", p=page + 1))
    return "\n".join(out + [ra.nav(*pager)])


if __name__ == "__main__":
    ra.run(render)
