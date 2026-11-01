#!/usr/bin/env python3
"""
NODES: a shared directory of NomadNet node addresses.

Any registered, unmuted identity can add a node (or a page on one) under a
category. Starring an entry is both a vote and a bookmark: entries sort by
stars, and "My stars" lists what you starred. The LXMF daemon records node
announces it hears (bbs.db node_seen), which gives each entry a "last heard"
time and feeds the "Recently heard" list that new entries are added from.

Authors can delete their own entries; sysops can delete any.
Categories come from config.json "node_categories" (defaults below).

Version: 1.0
Author: Brad Brown Jr (KC1JMH)
"""

import os
import re
import sys
import time

sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.realpath(__file__))), "lib"))
import bbs  # noqa: E402
import rnsapps as ra  # noqa: E402

VERSION = "1.0"
PAGE = "nodes"
PER_PAGE = 10
ADD_INTERVAL = 60          # seconds between new entries per identity
HEARD_DAYS = 7
MAX_NAME = 40
MAX_DESC = 120
DEFAULT_PATH = "/page/index.mu"
DEFAULT_CATEGORIES = ["BBS", "Ham radio", "Chat", "News", "Info", "Files", "Personal", "Other"]

HASH_RE = re.compile(r"^[0-9a-f]{32}$")
PATH_RE = re.compile(r"^/(page|file)/[A-Za-z0-9_.\-/]{1,100}$")


def categories():
    cats = ra.config().get("node_categories") or DEFAULT_CATEGORIES
    return [str(c)[:20] for c in cats if str(c).strip()]


def find_cat(name):
    for c in categories():
        if c.lower() == name.strip().lower():
            return c
    return None


# ----------------------------------------------------------------- parsing ---

def parse_address(text, path_text=""):
    """
    Accepts '<hash>', 'hash', 'hash:/page/x.mu' or a pasted micron link target.
    Returns (hash, path) or raises ValueError with a visitor-friendly message.
    """
    text = text.strip().strip("<>").lower()
    path = path_text.strip()
    if ":" in text:
        text, _, tail = text.partition(":")
        if not path:
            path = tail
        text = text.strip("<>")
    if not HASH_RE.match(text):
        raise ValueError("The node address must be 32 hex characters.")
    path = path or DEFAULT_PATH
    if not path.startswith("/"):
        path = "/page/" + path
    if path.startswith("/page/") and not path.endswith(".mu") and "." not in path.rsplit("/", 1)[-1]:
        path += ".mu"
    if not PATH_RE.match(path) or ".." in path:
        raise ValueError("Page path should look like /page/index.mu.")
    return text, path


# ----------------------------------------------------------------- output ---

def remote_link(label, h, path):
    """Link to a page on another node. h and path are validated before storage."""
    return "`F{}`_`[{}`{}:{}]`_`f".format(ra.C_LINK, ra.esc(label), h, path)


def short_hash(h):
    return "<{}..{}>".format(h[:6], h[-4:])


def heard_text(ts):
    return "heard " + ra.age_text(ts) if ts else "not heard yet"


def entry_lines(r, ident, back):
    """Two short lines per entry (phone screens fit about 36 columns)."""
    star = ra.color("*{}".format(r["stars"]), ra.C_HEAD) if r["stars"] else ra.dim("*0")
    mine = ra.color(" (starred)", ra.C_OK) if ident and r["starred"] else ""
    line1 = "{} {}{}".format(remote_link(r["name"], r["hash"], r["path"]), star, mine)
    desc = r["description"] or ""
    if len(desc) > 60:
        desc = desc[:57] + "..."
    info = [ra.dim(desc)] if desc else []
    info.append(ra.dim(heard_text(r["last_seen"])))
    info.append(ra.link("info", PAGE, v="entry", id=r["id"], b=back))
    return [line1, "  " + "  ".join(info)]


def pager(view, page, pages, **extra):
    items = []
    if page > 1:
        items.append(ra.link("< Prev", PAGE, v=view, p=page - 1, **extra))
    if page < pages:
        items.append(ra.link("Next >", PAGE, v=view, p=page + 1, **extra))
    return items


# ---------------------------------------------------------------- queries ---

ENTRY_SQL = """
SELECT n.*, (SELECT COUNT(*) FROM node_stars s WHERE s.node_id = n.id) AS stars,
       (SELECT 1 FROM node_stars s WHERE s.node_id = n.id AND s.identity = ?) AS starred,
       (SELECT last_seen FROM node_seen w WHERE w.hash = n.hash) AS last_seen
FROM nodes n
"""


def entries(conn, ident, where="", params=(), order="stars DESC, n.name COLLATE NOCASE", limit=None, offset=0):
    sql = ENTRY_SQL + (" WHERE " + where if where else "") + " ORDER BY " + order
    if limit:
        sql += " LIMIT {} OFFSET {}".format(int(limit), int(offset))
    return conn.execute(sql, (ident or "",) + tuple(params)).fetchall()


def count(conn, where="", params=()):
    return conn.execute("SELECT COUNT(*) FROM nodes n" + (" WHERE " + where if where else ""), params).fetchone()[0]


# ---------------------------------------------------------------- actions ---

def add_entry(conn, ident, cat, addr, path, name, desc):
    ok, why = bbs.can_write(conn, ident)
    if not ok:
        return False, why, None
    cat = find_cat(cat)
    if not cat:
        return False, "Pick a category.", None
    try:
        h, path = parse_address(addr, path)
    except ValueError as e:
        return False, str(e), None
    name = " ".join(name.split())
    desc = " ".join(desc.split())
    if not name:
        row = conn.execute("SELECT name FROM node_seen WHERE hash=?", (h,)).fetchone()
        name = (row["name"] if row else "") or ""
    if len(name) < 2 or len(name) > MAX_NAME:
        return False, "Name must be 2-{} characters.".format(MAX_NAME), None
    if len(desc) > MAX_DESC:
        return False, "Description is limited to {} characters.".format(MAX_DESC), None
    with bbs.tx(conn):
        dup = conn.execute("SELECT id FROM nodes WHERE hash=? AND path=?", (h, path)).fetchone()
        if dup:
            return False, "That address is already listed.", dup["id"]
        if not ra.is_sysop(ident) and not bbs.rate_ok(conn, "nodes", "author", ident, ADD_INTERVAL):
            return False, "Slow down - one new entry per {} seconds.".format(ADD_INTERVAL), None
        cur = conn.execute(
            "INSERT INTO nodes (hash, path, name, description, category, author, created) VALUES (?,?,?,?,?,?,?)",
            (h, path, name, desc, cat, ident, bbs.now()))
        new_id = cur.lastrowid
        conn.execute("INSERT OR IGNORE INTO node_stars VALUES (?,?,?)", (ident, new_id, bbs.now()))
    return True, "Added.", new_id


def toggle_star(conn, ident, node_id, on):
    if not ident:
        return False, "Identify to this node to star entries."
    if not ra.handle_for(ident):
        return False, "Register a handle first."
    with bbs.tx(conn):
        if not conn.execute("SELECT 1 FROM nodes WHERE id=?", (node_id,)).fetchone():
            return False, "That entry is gone."
        if on:
            conn.execute("INSERT OR IGNORE INTO node_stars VALUES (?,?,?)", (ident, node_id, bbs.now()))
        else:
            conn.execute("DELETE FROM node_stars WHERE identity=? AND node_id=?", (ident, node_id))
    return True, "Starred." if on else "Star removed."


def delete_entry(conn, ident, node_id):
    row = conn.execute("SELECT author FROM nodes WHERE id=?", (node_id,)).fetchone()
    if not row:
        return False, "That entry is already gone."
    if row["author"] != ident and not ra.is_sysop(ident):
        return False, "You can only delete entries you added."
    with bbs.tx(conn):
        conn.execute("DELETE FROM nodes WHERE id=?", (node_id,))
    return True, "Deleted."


# ------------------------------------------------------------------ views ---

def note_line(ok, note):
    return [ra.color(note, ra.C_OK if ok else ra.C_WARN), ""] if note else []


def home_view(conn, ident, note=()):
    out = [ra.heading("Node directory")] + list(note)
    out.append(ra.dim("NomadNet nodes and pages, added by visitors. Star the ones you like."))
    out.append("")
    rows = {r["category"]: r["c"] for r in conn.execute("SELECT category, COUNT(*) AS c FROM nodes GROUP BY category")}
    for cat in categories():
        out.append("{} {}".format(ra.link(cat, PAGE, v="cat", c=ra.quote(cat)), ra.dim("({})".format(rows.get(cat, 0)))))
    stray = sorted(set(rows) - set(categories()))
    for cat in stray:
        out.append("{} {}".format(ra.link(cat, PAGE, v="cat", c=ra.quote(cat)), ra.dim("({})".format(rows[cat]))))
    out += ["", ra.heading("Most starred", 2)]
    top = entries(conn, ident, limit=5)
    if not top:
        out.append("Nothing listed yet. Add the first node!")
    for r in top:
        out += entry_lines(r, ident, "home")
    links = [ra.link("Add a node", PAGE, v="add"), ra.link("Recently heard", PAGE, v="heard")]
    if ident:
        links.insert(0, ra.link("My stars", PAGE, v="mine"))
    else:
        out += ["", ra.dim("Identify to this node to add or star entries.")]
    return "\n".join(out + ["", "  ".join(links), ra.nav()])


def list_view(conn, ident, title, view, where, params, extra, empty, note=()):
    total = count(conn, where, params)
    pages = max((total + PER_PAGE - 1) // PER_PAGE, 1)
    page = min(max(ra.int_var("p", 1), 1), pages)
    out = [ra.heading(title)] + list(note)
    rows = entries(conn, ident, where, params, limit=PER_PAGE, offset=(page - 1) * PER_PAGE)
    if not rows:
        out.append(empty)
    back = "{}:{}".format(view, extra.get("c", ""))
    for r in rows:
        out += entry_lines(r, ident, back)
    out += ["", ra.dim("{} entr{}, page {} of {}".format(total, "y" if total == 1 else "ies", page, pages))]
    nav = pager(view, page, pages, **extra) + [("Directory", PAGE)]
    return "\n".join(out + [ra.nav(*nav)])


def entry_view(conn, ident, node_id, note=()):
    rows = entries(conn, ident, "n.id=?", (node_id,))
    if not rows:
        return "\n".join([ra.heading("Node directory")] + list(note) + ["That entry is gone.", ra.nav(("Directory", PAGE))])
    r = rows[0]
    seen = conn.execute("SELECT name FROM node_seen WHERE hash=?", (r["hash"],)).fetchone()
    out = [ra.heading(r["name"])] + list(note)
    out.append(remote_link("Open " + r["path"], r["hash"], r["path"]))
    out.append("")
    if r["description"]:
        out += [ra.esc(r["description"]), ""]
    out.append("Address  : {}".format(ra.esc(r["hash"])))
    out.append("Category : {}".format(ra.link(r["category"], PAGE, v="cat", c=ra.quote(r["category"]))))
    out.append("Stars    : {}".format(r["stars"]))
    out.append("Heard    : {}".format(ra.esc(heard_text(r["last_seen"]))))
    if seen and seen["name"] and seen["name"] != r["name"]:
        out.append("Announces as: {}".format(ra.esc(seen["name"])))
    out.append("Added by : {} {}".format(bbs.who(r["author"]),
                                         ra.dim(time.strftime("%Y-%m-%d", time.gmtime(r["created"] or 0)))))
    actions = []
    back = ra.var("b")
    can_delete = bool(ident) and (r["author"] == ident or ra.is_sysop(ident))
    if ident:
        if r["starred"]:
            actions.append(ra.link("Unstar", PAGE, v="entry", a="unstar", id=r["id"], b=back))
        else:
            actions.append(ra.link("Star it", PAGE, v="entry", a="star", id=r["id"], b=back))
        if can_delete:
            actions.append(ra.link("Delete", PAGE, v="entry", a="del", id=r["id"], b=back))
    if actions:
        out += ["", "  ".join(actions)]
    if can_delete and ra.var("a") == "del" and not ra.var("ok"):
        out += ["", ra.color("Delete this entry? ", ra.C_WARN)
                + ra.link("Yes, delete", PAGE, v="entry", a="del", id=r["id"], ok=1)]
    return "\n".join(out + [ra.nav(*back_nav())])


def back_nav():
    back = ra.var("b")
    view, _, cat = back.partition(":")
    items = []
    if view == "cat" and cat:
        items.append(ra.link(ra.unquote(cat), PAGE, v="cat", c=cat))
    elif view in ("mine", "heard"):
        items.append(ra.link("My stars" if view == "mine" else "Recently heard", PAGE, v=view))
    items.append(ra.link("Directory", PAGE))
    return items


def heard_view(conn, ident):
    since = bbs.now() - HEARD_DAYS * 86400
    total = conn.execute("SELECT COUNT(*) FROM node_seen WHERE last_seen >= ?", (since,)).fetchone()[0]
    pages = max((total + PER_PAGE - 1) // PER_PAGE, 1)
    page = min(max(ra.int_var("p", 1), 1), pages)
    rows = conn.execute(
        "SELECT w.*, (SELECT MIN(id) FROM nodes n WHERE n.hash = w.hash) AS listed "
        "FROM node_seen w WHERE last_seen >= ? ORDER BY last_seen DESC LIMIT ? OFFSET ?",
        (since, PER_PAGE, (page - 1) * PER_PAGE)).fetchall()
    out = [ra.heading("Recently heard"),
           ra.dim("Nodes this node heard announce in the last {} days.".format(HEARD_DAYS)), ""]
    if not rows:
        out.append("No announces recorded yet.")
    for r in rows:
        name = r["name"] or short_hash(r["hash"])
        line = "{} {}".format(remote_link(name, r["hash"], DEFAULT_PATH), ra.dim(ra.age_text(r["last_seen"])))
        if r["listed"]:
            line += "  " + ra.link("listed", PAGE, v="entry", id=r["listed"], b="heard:")
        elif ident:
            line += "  " + ra.link("add", PAGE, v="add", h=r["hash"])
        out.append(line)
    out += ["", ra.dim("{} node{}, page {} of {}".format(total, "" if total == 1 else "s", page, pages))]
    return "\n".join(out + [ra.nav(*(pager("heard", page, pages) + [("Directory", PAGE)]))])


def add_view(conn, ident, note=()):
    out = [ra.heading("Add a node")] + list(note)
    ok, why = bbs.can_write(conn, ident)
    if not ok:
        reg = ["", ra.link("Register", "register")] if ident and not ra.handle_for(ident) else []
        return "\n".join(out + [ra.color(why, ra.C_WARN)] + reg + [ra.nav(("Directory", PAGE))])
    h = ra.var("h").lower()
    h = h if HASH_RE.match(h) else ""
    cat = find_cat(ra.unquote(ra.var("c")))
    if not cat:
        out.append("Pick a category:")
        out.append("")
        for c in categories():
            out.append("  " + ra.link(c, PAGE, v="add", c=ra.quote(c), h=h))
        return "\n".join(out + [ra.nav(("Directory", PAGE))])
    seen = conn.execute("SELECT name FROM node_seen WHERE hash=?", (h,)).fetchone() if h else None
    name = ra.field("name") or (seen["name"] if seen else "")
    out += [
        "Category: {}  {}".format(ra.bold(cat), ra.link("change", PAGE, v="add", h=h)),
        "",
        "Node address (32 hex):",
        ra.input_field("addr", 34, ra.field("addr") or h),
        "Page (blank = {}):".format(DEFAULT_PATH),
        ra.input_field("path", 34, ra.field("path")),
        "Name (max {}):".format(MAX_NAME),
        ra.input_field("name", 34, name[:MAX_NAME]),
        "Description (optional, max {}):".format(MAX_DESC),
        ra.input_field("desc", 34, ra.field("desc")),
        "",
        ra.submit("Add to directory", PAGE, "addr|path|name|desc", v="add", a="save", c=ra.quote(cat)),
        "",
        ra.dim("Tip: the address is the node's destination hash, e.g. from your"),
        ra.dim("client's announce list. Blank name uses the announced name."),
    ]
    return "\n".join(out + [ra.nav(("Directory", PAGE))])


# ----------------------------------------------------------------- render ---

def render():
    ident = ra.identity()
    view, action = ra.var("v"), ra.var("a")
    conn = bbs.connect()

    if view == "add":
        if action == "save":
            ok, msg, new_id = add_entry(conn, ident, ra.unquote(ra.var("c")), ra.field("addr"),
                                        ra.field("path"), ra.field("name"), ra.field("desc"))
            if new_id:
                return entry_view(conn, ident, new_id, note_line(ok, msg))
            return add_view(conn, ident, note_line(ok, msg))
        return add_view(conn, ident)

    if view == "entry":
        node_id = ra.int_var("id")
        note = []
        if action in ("star", "unstar"):
            note = note_line(*toggle_star(conn, ident, node_id, action == "star"))
        elif action == "del" and ra.var("ok"):
            ok, msg = delete_entry(conn, ident, node_id) if ident else (False, "Identify first.")
            if ok:
                return home_view(conn, ident, note_line(ok, msg))
            note = note_line(ok, msg)
        return entry_view(conn, ident, node_id, note)

    if view == "cat":
        cat = ra.unquote(ra.var("c"))
        return list_view(conn, ident, cat, "cat", "n.category=?", (cat,), {"c": ra.quote(cat)},
                         "Nothing in this category yet. " + ra.link("Add one", PAGE, v="add", c=ra.quote(cat)))

    if view == "mine":
        if not ident:
            return "\n".join([ra.heading("My stars"), "Identify to this node to see your stars.", ra.nav(("Directory", PAGE))])
        return list_view(conn, ident, "My stars", "mine",
                         "n.id IN (SELECT node_id FROM node_stars WHERE identity=?)", (ident,), {},
                         "You haven't starred anything yet.")

    if view == "heard":
        return heard_view(conn, ident)

    return home_view(conn, ident)


if __name__ == "__main__":
    ra.run(render)
