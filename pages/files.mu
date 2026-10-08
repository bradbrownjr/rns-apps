#!/usr/bin/env python3
"""
Files: downloadable files in categories and sub-categories.

Anyone can browse and download. Downloads are served by NomadNet itself
(/file/a<area>/<name>), so they work in NomadNet, MeshChat and Sideband.
Uploads arrive by LXMF and wait for sysop approval (see sysop page).

Version: 1.0
Author: Brad Brown Jr (KC1JMH)
"""

import json
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.realpath(__file__))), "lib"))
import bbs  # noqa: E402
import rnsapps as ra  # noqa: E402

VERSION = "1.0"
PER_PAGE = 8


def upload_help(ident, note=""):
    """Upload instructions for a registered user. The node messages the user
    first (their messenger can't copy text from a page), and they reply with
    the file attached."""
    if not ra.handle_for(ident):
        return [ra.heading("Upload", 2), ra.dim("Register a handle to upload files."), ra.link("Register", "register"), ""]
    if not os.path.exists(os.path.join(ra.DATA_DIR, "lxmf_address.txt")):
        return [ra.dim("Uploads are not open yet.")]
    name = (ra.config().get("node_name") or "this node") + " files"
    rec = ra.profile(ident)
    out = [ra.heading("Upload", 2)]
    if note:
        out += [ra.color(note, ra.C_OK), ""]
    out += [ra.link("Message me to start an upload", "files", a="invite"),
            ra.dim("The node sends you a message from '{}'.".format(name)),
            ra.dim("Reply to it with your file attached and a short"),
            ra.dim("description. Limit 2 MB. A sysop approves each file."), ""]
    if not rec.get("lxmf"):
        out += [ra.dim("No message arriving? Find '{}' under".format(name)), ra.dim("Announces and message it. Include your handle and"),
                ra.dim("this code the first time: ") + ra.color(ra.link_code(ident), ra.C_OK), ""]
    return out


def invite(ident):
    """Queue the 'reply with your file' message. One pending invite at a time."""
    spool = os.path.join(ra.DATA_DIR, "lxmf_notify")
    for path in (os.listdir(spool) if os.path.isdir(spool) else []):
        try:
            with open(os.path.join(spool, path)) as f:
                rec = json.load(f)
        except (OSError, ValueError):
            continue
        if rec.get("identity") == ident and rec.get("title") == "Upload to {}".format(ra.config().get("node_name", "the BBS")):
            return "An invite is already on its way. Check your messages."
    node = ra.config().get("node_name", "the BBS")
    bbs.notify(ident, "Upload to {}".format(node),
               "Reply to this message with your file attached, and put a short description in the text. "
               "Limit 2 MB. A sysop approves each file before it appears in Files.")
    return "Sent. A message from '{} files' should arrive in a minute; reply to it with your file.".format(node)


def render():
    conn = bbs.connect()
    note = ""
    if ra.var("a") == "invite" and ra.handle_for(ra.identity()):
        note = invite(ra.identity())
    area_id, page = ra.int_var("a", 0), ra.int_var("p", 1)
    area = conn.execute("SELECT * FROM file_areas WHERE id=?", (area_id,)).fetchone() if area_id else None
    if area and area["hidden"] and not ra.is_sysop(ra.identity()):
        area = None
    ident = ra.identity()
    seen = bbs.pref_get(conn, ident, "files_seen") if ident else 0
    if ident and not area:
        bbs.pref_set(conn, ident, "files_seen", bbs.now())
    out = [ra.heading(area["name"] if area else "Files")]
    if area:
        crumbs = [ra.link("Files", "files")] + [ra.link(n, "files", a=i) for i, n in bbs.area_path(conn, area["id"])[:-1]]
        out.append(ra.dim("in ") + ra.dim(" / ").join(crumbs))
        if area["description"]:
            out.append(ra.dim(area["description"][:100]))
    out.append("")
    subs = conn.execute("SELECT * FROM file_areas WHERE parent_id IS ? AND hidden=0 ORDER BY sort, id", (area["id"] if area else None,)).fetchall()
    for s in subs:
        n = bbs.area_file_count(conn, s["id"])
        out.append("{} {}".format(ra.link(s["name"], "files", a=s["id"]), ra.dim("{} file{}".format(n, "" if n == 1 else "s"))))
        if s["description"]:
            out.append(ra.dim("  " + s["description"][:70]))
    if area:
        total = conn.execute("SELECT COUNT(*) FROM files WHERE area_id=?", (area["id"],)).fetchone()[0]
        pages = max((total + PER_PAGE - 1) // PER_PAGE, 1)
        page = min(max(page, 1), pages)
        rows = conn.execute("SELECT * FROM files WHERE area_id=? ORDER BY created DESC LIMIT ? OFFSET ?",
                            (area["id"], PER_PAGE, (page - 1) * PER_PAGE)).fetchall()
        if subs and rows:
            out.append("")
        for f in rows:
            out.append(ra.link(f["title"], "/file/a{}/{}".format(f["area_id"], f["fname"])) + (ra.color(" NEW", ra.C_OK) if seen and f["created"] > seen else ""))
            out.append(ra.dim("{}  {}  by {}  {}".format(f["fname"], bbs.human_size(f["size"]),
                                                       ra.display_name(f["uploader"]) if f["uploader"] else "sysop", ra.age_text(f["created"]))))
            if f["description"]:
                out += ["  " + line for line in ra.paragraphs(f["description"])[:3]]
            if f["sha256"]:
                out.append(ra.dim("  sha256 " + f["sha256"][:16]))
        if not rows and not subs:
            out.append("Nothing here yet.")
        pager = []
        if page > 1:
            pager.append(ra.link("< Newer", "files", a=area["id"], p=page - 1))
        if page < pages:
            pager.append(ra.link("Older >", "files", a=area["id"], p=page + 1))
        if pager:
            out += ["", ra.dim("Page {} of {}".format(page, pages))]
        out.append(ra.nav(*pager, ("Files", "files")))
    else:
        if not subs:
            out.append("No file areas yet.")
        out += [""] + upload_help(ra.identity(), note) + [ra.nav()]
    return "\n".join(out)


if __name__ == "__main__":
    ra.run(render)
