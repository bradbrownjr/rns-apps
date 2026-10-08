#!/usr/bin/env python3
"""
Sysop tools: message boards, mutes, users.

Sysops are the identities listed under "sysops" in /data/apps/config.json.
RNS verifies an identity cryptographically (the client signs with its
private key when it identifies), so this check can't be spoofed by choosing
a handle or sending variables: only a holder of that identity's key passes.

Version: 1.1
Author: Brad Brown Jr (KC1JMH)
"""

import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.realpath(__file__))), "lib"))
import bbs  # noqa: E402
import rnsapps as ra  # noqa: E402

VERSION = "1.1"
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
        ra.link("Boards", "sysop", v="boards"), ra.link("File areas", "sysop", v="areas"),
        ra.link("Pending uploads ({})".format(count("SELECT COUNT(*) FROM uploads WHERE status='pending'")), "sysop", v="pending"),
        ra.link("Import from incoming folder", "sysop", v="incoming"),
        ra.link("Users", "sysop", v="users"), ra.link("Muted", "sysop", v="mutes"),
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


def areas_view(conn, note=""):
    out = [ra.heading("File areas")]
    if note:
        out.append(ra.color(note, ra.C_OK))
    out.append("")
    for r, depth in bbs.area_tree(conn, True):
        out.append("  " * depth + ra.link(r["name"], "sysop", v="area", f=r["id"]) + ra.dim("  {} files{}".format(
            conn.execute("SELECT COUNT(*) FROM files WHERE area_id=?", (r["id"],)).fetchone()[0], " hidden" if r["hidden"] else "")))
    out += ["", ra.heading("New area", 2), ra.dim("Name"), ra.input_field("name", 30, ""), ra.dim("Description"), ra.input_field("desc", 50, ""),
            ra.dim("Parent area id (blank = top level)"), ra.input_field("parent", 6, ""),
            ra.submit("Create area", "sysop", "name|desc|parent", a="newarea", v="areas")]
    return out + [ra.nav(("Sysop", "sysop"))]


def area_view(conn, fid, note=""):
    r = conn.execute("SELECT * FROM file_areas WHERE id=?", (fid,)).fetchone()
    if not r:
        return areas_view(conn, "No such area.")
    out = [ra.heading(r["name"]), ra.dim("Area id {}".format(fid))]
    if note:
        out.append(ra.color(note, ra.C_OK))
    out += ["", ra.dim("Name"), ra.input_field("name", 30, r["name"]), ra.dim("Description"), ra.input_field("desc", 50, r["description"]),
            ra.submit("Save", "sysop", "name|desc", a="renamearea", v="area", f=fid), "",
            "{}  {}".format(ra.bold("[x]") if r["hidden"] else "[ ]", ra.link("Hidden from non-sysops", "sysop", a="togglearea", v="area", f=fid)), ""]
    for f in conn.execute("SELECT * FROM files WHERE area_id=? ORDER BY created DESC", (fid,)):
        out.append("{} {}".format(ra.esc(f["title"]), ra.link("remove", "sysop", a="rmfile", v="area", f=fid, x=f["id"])))
    empty = not conn.execute("SELECT 1 FROM files WHERE area_id=?", (fid,)).fetchone() and not conn.execute(
        "SELECT 1 FROM file_areas WHERE parent_id=?", (fid,)).fetchone()
    banned = {fid} | bbs.area_descendants(conn, fid)
    parent = r["parent_id"]
    out += ["", ra.heading("Move", 2), ra.dim("Now under: " + (" / ".join(n for _, n in bbs.area_path(conn, parent)) if parent else "top level"))]
    if parent:
        out.append(ra.link("Move to top level", "sysop", a="movearea", v="area", f=fid, to=0))
    for cand, depth in bbs.area_tree(conn, True):
        if cand["id"] not in banned and cand["id"] != parent:
            out.append("  " * depth + ra.link("Move under " + cand["name"], "sysop", a="movearea", v="area", f=fid, to=cand["id"]))
    out += ["", ra.link("Delete area", "sysop", a="delarea", v="areas", f=fid) if empty else ra.dim("Only empty areas (no files or sub-areas) can be deleted.")]
    return out + [ra.nav(("Areas", "sysop"))]


def incoming_view(conn, fid, name, note=""):
    """Files dropped in <files>/incoming, filed into an area with a title."""
    out = [ra.heading("Import files")]
    if note:
        out.append(ra.color(note, ra.C_OK))
    folder = bbs.files_dir("incoming")
    names = sorted(n for n in os.listdir(folder) if os.path.isfile(os.path.join(folder, n)) and not n.startswith("."))
    if not names:
        return out + ["", "Nothing in the incoming folder.", ra.dim("Copy files into the incoming folder of the files directory."),
                      ra.nav(("Sysop", "sysop"))]
    if not name:
        out.append("")
        for n in names:
            out.append(ra.link(n, "sysop", v="incoming", n=ra.quote(n)) + ra.dim("  " + bbs.human_size(os.path.getsize(os.path.join(folder, n)))))
        return out + [ra.nav(("Sysop", "sysop"))]
    out += ["", ra.esc(name), ra.dim("Choose an area:")]
    for r, depth in bbs.area_tree(conn, True):
        out.append("  " * depth + ra.submit("Import into {}".format(r["name"]), "sysop", "title|desc", a="import", v="areas", n=ra.quote(name), f=r["id"]))
    out += ["", ra.dim("Title"), ra.input_field("title", 40, name), ra.dim("Description"), ra.input_field("desc", 60, ""),
            ra.dim("(fill in title and description, then pick the area)")]
    return out + [ra.nav(("Sysop", "sysop"))]


def pending_view(conn, note=""):
    out = [ra.heading("Pending uploads")]
    if note:
        out.append(ra.color(note, ra.C_OK))
    rows = conn.execute("SELECT * FROM uploads WHERE status='pending' ORDER BY created").fetchall()
    out.append("")
    for u in rows:
        out.append(ra.link("{} ({})".format(u["orig_name"] or u["fname"], bbs.human_size(u["size"])), "sysop", v="upload", u=u["id"]))
        out.append(ra.dim("from {}  {}  scan: {}".format(ra.display_name(u["sender"]), ra.age_text(u["created"]), u["scan"] or "not needed")))
    if not rows:
        out.append("Nothing waiting.")
    return out + [ra.nav(("Sysop", "sysop"))]


def upload_view(conn, uid, note=""):
    u = conn.execute("SELECT * FROM uploads WHERE id=?", (uid,)).fetchone()
    if not u or u["status"] != "pending":
        return pending_view(conn, "No such pending upload.")
    out = [ra.heading(u["orig_name"] or u["fname"])]
    if note:
        out.append(ra.color(note, ra.C_WARN))
    out += [ra.dim("{}  from {}  scan: {}".format(bbs.human_size(u["size"]), ra.display_name(u["sender"]), u["scan"] or "not needed")),
            ra.dim("sha256 " + (u["sha256"] or "")[:32]), ""] + ra.paragraphs(u["note"]) + ["", ra.dim("Title"),
            ra.input_field("title", 40, u["orig_name"] or u["fname"]), ra.dim("Approve into area:")]
    for r, depth in bbs.area_tree(conn, True):
        out.append("  " * depth + ra.submit("Approve into {}".format(r["name"]), "sysop", "title", a="approve", v="pending", u=uid, f=r["id"]))
    out += ["", ra.dim("Reject reason (optional, sent to the uploader)"), ra.input_field("reason", 50, ""),
            ra.submit("Reject and delete", "sysop", "reason", a="reject", v="pending", u=uid)]
    return out + [ra.nav(("Pending", "sysop"))]


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
        extra = " ".join(x for x in (rec.get("callsign"), rec.get("name"), rec.get("location"),
                                     "msgr " + rec["lxmf"][-1][:8] if rec.get("lxmf") else "") if x)
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
    fid, uid = ra.int_var("f", 0), ra.int_var("u", 0)

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
    elif a == "newarea" and ra.field("name"):
        parent = int(ra.field("parent")) if ra.field("parent").isdigit() else None
        if parent and not conn.execute("SELECT 1 FROM file_areas WHERE id=?", (parent,)).fetchone():
            note = "No area with that parent id."
        else:
            conn.execute("INSERT INTO file_areas (parent_id, name, description, sort) VALUES (?,?,?,COALESCE((SELECT MAX(sort)+10 FROM file_areas),10))",
                         (parent, ra.field("name")[:40], ra.field("desc")[:100]))
            note = "Area created."
    elif a == "renamearea" and fid and ra.field("name"):
        conn.execute("UPDATE file_areas SET name=?, description=? WHERE id=?", (ra.field("name")[:40], ra.field("desc")[:100], fid))
        note = "Saved."
    elif a == "togglearea" and fid:
        conn.execute("UPDATE file_areas SET hidden=1-hidden WHERE id=?", (fid,))
        note = "Updated."
    elif a == "movearea" and fid:
        to = ra.int_var("to", 0)
        if to and (to == fid or to in bbs.area_descendants(conn, fid) or not conn.execute("SELECT 1 FROM file_areas WHERE id=?", (to,)).fetchone()):
            note = "Can't move it there."
        else:
            conn.execute("UPDATE file_areas SET parent_id=? WHERE id=?", (to or None, fid))
            note = "Moved."
    elif a == "rmfile" and ra.int_var("x", 0):
        bbs.remove_file(conn, ra.int_var("x", 0))
        note = "File removed."
    elif a == "delarea" and fid:
        if not conn.execute("SELECT 1 FROM files WHERE area_id=?", (fid,)).fetchone() and not conn.execute(
                "SELECT 1 FROM file_areas WHERE parent_id=?", (fid,)).fetchone():
            conn.execute("DELETE FROM file_areas WHERE id=?", (fid,))
            note = "Area deleted."
    elif a == "import" and fid and ra.var("n"):
        name = os.path.basename(ra.unquote(ra.var("n")))
        src = os.path.join(bbs.files_dir("incoming"), name)
        if os.path.isfile(src) and not name.startswith("."):
            ok, note = bbs.publish_file(conn, fid, src, name, ra.field("title") or name, ra.field("desc"), "", "")
        else:
            note = "That file is gone."
    elif a in ("approve", "reject") and uid:
        u = conn.execute("SELECT * FROM uploads WHERE id=? AND status='pending'", (uid,)).fetchone()
        src = os.path.join(bbs.files_dir("pending"), u["fname"]) if u else ""
        if not u:
            note = "Already handled."
        elif a == "reject":
            if os.path.exists(src):
                os.remove(src)
            conn.execute("UPDATE uploads SET status='rejected' WHERE id=?", (uid,))
            bbs.notify(u["sender"], "Upload rejected", "Your upload {} was not accepted.{}".format(
                u["orig_name"], " Reason: " + ra.field("reason") if ra.field("reason") else ""))
            note = "Rejected."
        elif u["scan"].startswith("infected"):
            note = "Scan flagged this file; reject it."
        elif fid and os.path.exists(src):
            ok, note = bbs.publish_file(conn, fid, src, u["orig_name"] or u["fname"], ra.field("title") or u["orig_name"],
                                        u["note"], u["sender"], u["scan"])
            if ok:
                conn.execute("UPDATE uploads SET status='approved' WHERE id=?", (uid,))
                bbs.notify(u["sender"], "Upload approved", "Your upload {} is now in Files.".format(u["orig_name"]))
                note = "Approved."
        else:
            note = "Pick an area."
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
    if v == "areas" or a == "import":
        return "\n".join(areas_view(conn, note))
    if v == "area" and fid:
        return "\n".join(area_view(conn, fid, note))
    if v == "incoming":
        return "\n".join(incoming_view(conn, fid, ra.unquote(ra.var("n")) if ra.var("n") else "", note))
    if v == "upload" or (a in ("approve", "reject") and note not in ("Approved.", "Rejected.", "Already handled.")):
        return "\n".join(upload_view(conn, uid, note))
    if v == "pending":
        return "\n".join(pending_view(conn, note))
    if v == "users":
        return "\n".join(users_view(conn, ra.int_var("p", 1), note))
    if v == "mutes":
        return "\n".join(mutes_view(conn, note))
    return "\n".join(menu(conn, note))


if __name__ == "__main__":
    ra.run(render)
