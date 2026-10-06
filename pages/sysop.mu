#!/usr/bin/env python3
"""
Sysop tools: message boards, mutes, users.

Sysops are the identities listed under "sysops" in /data/apps/config.json.
RNS verifies an identity cryptographically (the client signs with its
private key when it identifies), so this check can't be spoofed by choosing
a handle or sending variables: only a holder of that identity's key passes.

Version: 1.0
Author: Brad Brown Jr (KC1JMH)
"""

import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.realpath(__file__))), "lib"))
import bbs  # noqa: E402
import rnsapps as ra  # noqa: E402

VERSION = "1.0"
USERS_PER_PAGE = 12


def menu(conn, note=""):
    count = lambda sql: conn.execute(sql).fetchone()[0]  # noqa: E731
    out = [ra.heading("Sysop")]
    if note:
        out += [ra.color(note, ra.C_OK), ""]
    out += [ra.dim("{} boards, {} threads, {} posts, {} mail, {} users, {} muted".format(
        count("SELECT COUNT(*) FROM boards"), count("SELECT COUNT(*) FROM threads"),
        count("SELECT COUNT(*) FROM posts WHERE deleted=0"), count("SELECT COUNT(*) FROM mail"),
        len(ra.users()), count("SELECT COUNT(*) FROM mutes"))), "",
        ra.link("Boards", "sysop", v="boards"), ra.link("Users", "sysop", v="users"), ra.link("Muted", "sysop", v="mutes"),
        "", ra.link("Forms submitted", "forms", a="outbox"), ra.nav()]
    return out


def boards_view(conn, note=""):
    out = [ra.heading("Boards")]
    if note:
        out += [ra.color(note, ra.C_OK)]
    out.append("")
    for b in conn.execute("SELECT * FROM boards ORDER BY sort, id"):
        flags = "".join([" ro" if b["readonly"] else "", " locked" if b["locked"] else "", " hidden" if b["hidden"] else ""])
        out.append("{} {}".format(ra.link(b["name"], "sysop", v="board", b=b["id"]), ra.dim(flags.strip())))
    out += ["", ra.heading("New board", 2), ra.dim("Name"), ra.input_field("name", 30, ""), ra.dim("Description"),
            ra.input_field("desc", 50, ""), ra.submit("Create board", "sysop", "name|desc", a="newboard", v="boards")]
    return out + [ra.nav(("Sysop", "sysop"))]


def board_view(conn, board_id, note=""):
    b = conn.execute("SELECT * FROM boards WHERE id=?", (board_id,)).fetchone()
    if not b:
        return boards_view(conn, "No such board.")
    threads = conn.execute("SELECT COUNT(*) FROM threads WHERE board_id=?", (board_id,)).fetchone()[0]
    out = [ra.heading(b["name"])]
    if note:
        out.append(ra.color(note, ra.C_OK))
    out += [ra.dim("{} threads. Order {}.".format(threads, b["sort"])), "",
            ra.dim("Name"), ra.input_field("name", 30, b["name"]), ra.dim("Description"), ra.input_field("desc", 50, b["description"]),
            ra.submit("Save", "sysop", "name|desc", a="rename", v="board", b=board_id), ""]
    for col, label in (("readonly", "Read-only (only sysops post)"), ("locked", "Locked (nobody posts)"), ("hidden", "Hidden from non-sysops")):
        out.append("{}  {}".format(ra.bold("[x]") if b[col] else "[ ]", ra.link(label, "sysop", a="toggle", col=col, v="board", b=board_id)))
    out += ["", ra.link("Move up", "sysop", a="up", v="boards", b=board_id), "  ", ra.link("Move down", "sysop", a="down", v="boards", b=board_id)]
    if threads == 0:
        out += ["", ra.link("Delete board", "sysop", a="delboard", v="boards", b=board_id)]
    else:
        out += ["", ra.dim("Only empty boards can be deleted. Hide it instead.")]
    return out + [ra.nav(ra.link("Boards", "sysop", v="boards"))]


def users_view(conn, page, note=""):
    users = sorted(ra.users().items(), key=lambda kv: kv[1].get("handle", "").lower())
    muted = {r["identity"] for r in conn.execute("SELECT identity FROM mutes")}
    pages = max((len(users) + USERS_PER_PAGE - 1) // USERS_PER_PAGE, 1)
    page = min(max(page, 1), pages)
    out = [ra.heading("Users")]
    if note:
        out.append(ra.color(note, ra.C_OK))
    out.append("")
    for ident, rec in users[(page - 1) * USERS_PER_PAGE:page * USERS_PER_PAGE]:
        extra = " ".join(x for x in (rec.get("callsign"), rec.get("name"), rec.get("location")) if x)
        state = ra.color(" [muted]", ra.C_WARN) if ident in muted else ""
        out.append("{}{}{}".format(ra.esc(rec.get("handle", "?")), ra.sysop_badge(ident), state)
                   + "  " + (ra.link("unmute", "sysop", a="unmute", i=ident, v="users", p=page) if ident in muted
                              else ra.link("mute", "sysop", a="mute", i=ident, v="users", p=page)))
        out.append(ra.dim("{} {}".format(ident[:12], extra)[:100]))
    pager = []
    if page > 1:
        pager.append(ra.link("< Prev", "sysop", v="users", p=page - 1))
    if page < pages:
        pager.append(ra.link("Next >", "sysop", v="users", p=page + 1))
    return out + ["", ra.dim("Page {} of {}".format(page, pages)), ra.nav(*pager, ("Sysop", "sysop"))]


def mutes_view(conn, note=""):
    out = [ra.heading("Muted")]
    if note:
        out.append(ra.color(note, ra.C_OK))
    rows = conn.execute("SELECT * FROM mutes ORDER BY created DESC").fetchall()
    out.append("")
    for r in rows:
        out += ["{} {}".format(bbs.who(r["identity"]), ra.link("unmute", "sysop", a="unmute", i=r["identity"], v="mutes")),
                ra.dim((r["reason"] or "no reason")[:80])]
    if not rows:
        out.append("No one is muted.")
    out += ["", ra.dim("Mute by handle"), ra.input_field("handle", 20, ""), ra.dim("Reason"), ra.input_field("reason", 40, ""),
            ra.submit("Mute", "sysop", "handle|reason", a="mutehandle", v="mutes")]
    return out + [ra.nav(("Sysop", "sysop"))]


def render():
    ident = ra.identity()
    if not ra.is_sysop(ident):
        return "\n".join([ra.heading("Sysop"), "Sysops only. This node recognizes sysops by their verified Reticulum identity.", ra.nav()])
    conn = bbs.connect()
    a, v = ra.var("a"), ra.var("v")
    bid, note = ra.int_var("b", 0), ""

    if a == "newboard" and ra.field("name"):
        conn.execute("INSERT INTO boards (name, description, sort, created) VALUES (?,?,COALESCE((SELECT MAX(sort)+10 FROM boards),10),?)",
                     (ra.field("name")[:40], ra.field("desc")[:100], bbs.now()))
        note = "Board created."
    elif a == "rename" and bid and ra.field("name"):
        conn.execute("UPDATE boards SET name=?, description=? WHERE id=?", (ra.field("name")[:40], ra.field("desc")[:100], bid))
        note = "Saved."
    elif a == "toggle" and bid and ra.var("col") in ("readonly", "locked", "hidden"):
        conn.execute("UPDATE boards SET {0}=1-{0} WHERE id=?".format(ra.var("col")), (bid,))
        note = "Updated."
    elif a in ("up", "down") and bid:
        rows = conn.execute("SELECT id, sort FROM boards ORDER BY sort, id").fetchall()
        idx = next((n for n, r in enumerate(rows) if r["id"] == bid), None)
        swap = idx + (-1 if a == "up" else 1) if idx is not None else None
        if swap is not None and 0 <= swap < len(rows):
            order = [r["id"] for r in rows]
            order[idx], order[swap] = order[swap], order[idx]
            with bbs.tx(conn):
                for n, board_id in enumerate(order):
                    conn.execute("UPDATE boards SET sort=? WHERE id=?", ((n + 1) * 10, board_id))
        note = "Moved."
    elif a == "delboard" and bid and not ra.var("ok"):
        return "\n".join([ra.heading("Delete board?"), ra.link("Yes, delete it", "sysop", a="delboard", v="boards", b=bid, ok=1),
                          "  ", ra.link("No", "sysop", v="board", b=bid), ra.nav()])
    elif a == "delboard" and bid:
        if conn.execute("SELECT COUNT(*) FROM threads WHERE board_id=?", (bid,)).fetchone()[0] == 0:
            conn.execute("DELETE FROM boards WHERE id=?", (bid,))
            note = "Board deleted."
    elif a == "mute" and ra.var("i"):
        conn.execute("INSERT OR REPLACE INTO mutes VALUES (?,?,?)", (ra.var("i"), "", bbs.now()))
        note = "Muted."
    elif a == "unmute" and ra.var("i"):
        conn.execute("DELETE FROM mutes WHERE identity=?", (ra.var("i"),))
        note = "Unmuted."
    elif a == "mutehandle":
        target = bbs.find_handle(ra.field("handle"))
        if target and not ra.is_sysop(target):
            conn.execute("INSERT OR REPLACE INTO mutes VALUES (?,?,?)", (target, ra.field("reason")[:80], bbs.now()))
            note = "Muted."
        else:
            note = "No such handle (or that is a sysop)."

    if v == "boards":
        return "\n".join(boards_view(conn, note))
    if v == "board" and bid:
        return "\n".join(board_view(conn, bid, note))
    if v == "users":
        return "\n".join(users_view(conn, ra.int_var("p", 1), note))
    if v == "mutes":
        return "\n".join(mutes_view(conn, note))
    return "\n".join(menu(conn, note))


if __name__ == "__main__":
    ra.run(render)
