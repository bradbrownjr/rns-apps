"""
Minimal iCalendar reader for rns-apps (stdlib only).

Handles what public Google/club calendars use: VEVENT with DTSTART/DTEND
(UTC, TZID or all-day), RRULE (DAILY, WEEKLY, MONTHLY, YEARLY with INTERVAL,
COUNT, UNTIL, BYDAY incl. ordinals like 2TH or -1FR, BYMONTHDAY, BYMONTH),
EXDATE, and RECURRENCE-ID overrides. Not a general RFC 5545 implementation.

Version: 1.0
Author: Brad Brown Jr (KC1JMH)
"""

import calendar
import hashlib
import re
from datetime import date, datetime, timedelta, timezone
from zoneinfo import ZoneInfo

VERSION = "1.0"
DAYS = {"MO": 0, "TU": 1, "WE": 2, "TH": 3, "FR": 4, "SA": 5, "SU": 6}


def _unfold(text):
    lines = []
    for raw in text.replace("\r\n", "\n").replace("\r", "\n").split("\n"):
        if raw[:1] in (" ", "\t") and lines:
            lines[-1] += raw[1:]
        else:
            lines.append(raw)
    return lines


def _unescape(value):
    return (value.replace("\\n", "\n").replace("\\N", "\n").replace("\\,", ",")
            .replace("\\;", ";").replace("\\\\", "\\"))


def _prop(line):
    head, _, value = line.partition(":")
    name, *params = head.split(";")
    return name.upper(), dict(p.split("=", 1) for p in params if "=" in p), value


def _parse_dt(value, params, default_tz):
    """-> (datetime, all_day). Aware datetimes in their own zone."""
    value = value.strip()
    if params.get("VALUE") == "DATE" or (len(value) == 8 and "T" not in value):
        d = datetime.strptime(value[:8], "%Y%m%d")
        return d.replace(tzinfo=default_tz), True
    if value.endswith("Z"):
        return datetime.strptime(value[:15], "%Y%m%dT%H%M%S").replace(tzinfo=timezone.utc), False
    d = datetime.strptime(value[:15], "%Y%m%dT%H%M%S")
    tz = default_tz
    if params.get("TZID"):
        try:
            tz = ZoneInfo(params["TZID"])
        except Exception:
            pass
    return d.replace(tzinfo=tz), False


def _events(text, default_tz):
    cur, out = None, []
    for line in _unfold(text):
        if line == "BEGIN:VEVENT":
            cur = {"exdates": [], "rrule": None}
        elif line == "END:VEVENT" and cur is not None:
            if cur.get("start"):
                out.append(cur)
            cur = None
        elif cur is not None:
            name, params, value = _prop(line)
            if name == "DTSTART":
                cur["start"], cur["allday"] = _parse_dt(value, params, default_tz)
            elif name == "DTEND":
                cur["end"], _ = _parse_dt(value, params, default_tz)
            elif name in ("SUMMARY", "LOCATION", "DESCRIPTION", "UID", "STATUS"):
                cur[name.lower()] = _unescape(value)
            elif name == "RRULE":
                cur["rrule"] = dict(p.split("=", 1) for p in value.split(";") if "=" in p)
            elif name == "EXDATE":
                for v in value.split(","):
                    cur["exdates"].append(_parse_dt(v, params, default_tz)[0])
            elif name == "RECURRENCE-ID":
                cur["recurrence_id"] = _parse_dt(value, params, default_tz)[0]
    return out


def _nth_weekday(year, month, weekday, n):
    """n-th (1-based, or -1 = last) weekday of a month, or None."""
    days = [d for d in range(1, calendar.monthrange(year, month)[1] + 1)
            if date(year, month, d).weekday() == weekday]
    try:
        return date(year, month, days[n - 1 if n > 0 else n])
    except IndexError:
        return None


def _byday(rule):
    out = []
    for item in rule.get("BYDAY", "").split(","):
        m = re.match(r"^([+-]?\d+)?(MO|TU|WE|TH|FR|SA|SU)$", item.strip())
        if m:
            out.append((int(m.group(1)) if m.group(1) else 0, DAYS[m.group(2)]))
    return out


def _candidates(start, rule, horizon):
    """Yield local dates of occurrences in order, from dtstart to horizon."""
    freq = rule.get("FREQ", "")
    step = max(int(rule.get("INTERVAL", 1)), 1)
    byday = _byday(rule)
    bymonthday = [int(x) for x in rule.get("BYMONTHDAY", "").split(",") if x]
    bymonth = [int(x) for x in rule.get("BYMONTH", "").split(",") if x]
    d0 = start.date()

    if freq == "DAILY":
        d = d0
        while d <= horizon:
            if not byday or d.weekday() in {w for _, w in byday}:
                yield d
            d += timedelta(days=step)
    elif freq == "WEEKLY":
        weekdays = sorted({w for _, w in byday}) or [d0.weekday()]
        monday = d0 - timedelta(days=d0.weekday())
        while monday <= horizon:
            for w in weekdays:
                d = monday + timedelta(days=w)
                if d >= d0:
                    yield d
            monday += timedelta(weeks=step)
    elif freq in ("MONTHLY", "YEARLY"):
        year, month = d0.year, d0.month
        while date(year, month, 1) <= horizon:
            if freq == "MONTHLY" or not bymonth or month in bymonth:
                found = []
                if byday:
                    for n, w in byday:
                        if n:
                            d = _nth_weekday(year, month, w, n)
                            found += [d] if d else []
                        else:
                            found += [date(year, month, x) for x in range(1, calendar.monthrange(year, month)[1] + 1)
                                      if date(year, month, x).weekday() == w]
                elif bymonthday:
                    last = calendar.monthrange(year, month)[1]
                    found = [date(year, month, x if x > 0 else last + 1 + x) for x in bymonthday if 0 < abs(x) <= last]
                elif d0.day <= calendar.monthrange(year, month)[1]:
                    found = [date(year, month, d0.day)]
                for d in sorted(found):
                    if d >= d0:
                        yield d
            if freq == "MONTHLY":
                month += step
                year += (month - 1) // 12
                month = (month - 1) % 12 + 1
            else:
                if bymonth and month != bymonth[-1]:
                    # walk months within the year, then jump years
                    month += 1
                    if month > 12:
                        month, year = 1, year + 1
                    continue
                year, month = year + step, (bymonth[0] if bymonth else d0.month)
    else:
        yield d0


def _expand(ev, window_start, window_end, display_tz):
    start = ev["start"]
    duration = (ev["end"] - start) if ev.get("end") else (timedelta(days=1) if ev["allday"] else timedelta(hours=1))
    rule = ev["rrule"]
    if not rule:
        starts = [start]
    else:
        until = None
        if rule.get("UNTIL"):
            until = _parse_dt(rule["UNTIL"], {}, start.tzinfo)[0]
        count = int(rule["COUNT"]) if rule.get("COUNT") else None
        horizon = (window_end + timedelta(days=1)).astimezone(start.tzinfo).date()
        starts, n = [], 0
        for d in _candidates(start, rule, horizon):
            occ = datetime.combine(d, start.timetz().replace(tzinfo=None)).replace(tzinfo=start.tzinfo)
            if until and occ > until:
                break
            n += 1
            if count and n > count:
                break
            if occ + duration >= window_start:
                starts.append(occ)
    return [(s, s + duration) for s in starts if s not in ev["exdates"] and s <= window_end]


def upcoming(text, tz_name="America/New_York", days_back=0, days_ahead=120, now=None):
    """Events overlapping [now - days_back, now + days_ahead], sorted by start."""
    tz = ZoneInfo(tz_name)
    now = now or datetime.now(tz)
    w0, w1 = now - timedelta(days=days_back), now + timedelta(days=days_ahead)
    raw = _events(text, tz)
    overrides = {(e["uid"], e["recurrence_id"]) for e in raw if e.get("recurrence_id") and e.get("uid")}
    out = []
    for ev in raw:
        if ev.get("status", "").upper() == "CANCELLED":
            continue
        for s, e in _expand(ev, w0, w1, tz):
            if not ev.get("recurrence_id") and (ev.get("uid"), s) in overrides:
                continue
            if e < w0 or s > w1:
                continue
            ident = hashlib.sha1("{}{}".format(ev.get("uid", ev.get("summary", "")), s.isoformat()).encode()).hexdigest()[:8]
            out.append({"id": ident, "start": s.astimezone(tz), "end": e.astimezone(tz), "allday": ev["allday"],
                        "summary": ev.get("summary", "(no title)"), "location": ev.get("location", ""),
                        "description": ev.get("description", "")})
    out.sort(key=lambda x: x["start"])
    return out
