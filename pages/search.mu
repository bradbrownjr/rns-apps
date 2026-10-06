#!/usr/bin/env python3
"""
Search: message board threads and posts, and files.

Hidden boards and hidden file areas are searched only for sysops.

Version: 1.0
Author: Brad Brown Jr (KC1JMH)
"""

import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.realpath(__file__))), "lib"))
import bbs  # noqa: E402
import rnsapps as ra  # noqa: E402

VERSION = "1.0"
LIMIT = 10


def like(term):
    return "%" + term.replace("\\", "\\\\").replace("%", "\\%").replace("_", "\\_") + "%"


def render():
    term = ra.arg("q")[:60]
    out = [ra.heading("Search"), ra.input_field("q", 30, term), ra.submit("Search", "search", "q"), ""]
    if len(term) < 3:
        out.append(ra.dim("Type at least 3 characters: searches message boards and files."))
        return "\n".join(out + [ra.nav()])
    conn = bbs.connect()
    sysop = 1 if ra.is_sysop(ra.identity()) else 0
    pat = like(term)
    threads = conn.execute(
        "SELECT t.id, t.title, b.name, p.body, p.id AS pid FROM posts p JOIN threads t ON t.id=p.thread_id JOIN boards b ON b.id=t.board_id "
        "WHERE (b.hidden=0 OR ?=1) AND p.deleted=0 AND (t.title LIKE ? ESCAPE '\\' OR p.body LIKE ? ESCAPE '\\') "
        "GROUP BY t.id ORDER BY MAX(p.created) DESC LIMIT ?", (sysop, pat, pat, LIMIT)).fetchall()
    out.append(ra.heading("Boards", 2))
    for r in threads:
        out.append("{} {}".format(ra.link(r["title"], "msg", t=r["id"]), ra.dim("in " + r["name"])))
        idx = r["body"].lower().find(term.lower())
        if idx >= 0:
            out.append(ra.dim("  ..." + r["body"][max(idx - 20, 0):idx + 50].replace("\n", " ")))
    if not threads:
        out.append(ra.dim("No matches."))
    files = conn.execute(
        "SELECT f.* FROM files f JOIN file_areas a ON a.id=f.area_id WHERE (a.hidden=0 OR ?=1) AND "
        "(f.title LIKE ? ESCAPE '\\' OR f.description LIKE ? ESCAPE '\\' OR f.fname LIKE ? ESCAPE '\\') ORDER BY f.created DESC LIMIT ?",
        (sysop, pat, pat, pat, LIMIT)).fetchall()
    out += ["", ra.heading("Files", 2)]
    for f in files:
        path = " / ".join(n for _, n in bbs.area_path(conn, f["area_id"]))
        out.append("{} {}".format(ra.link(f["title"], "files", a=f["area_id"]), ra.dim("{}  {}".format(path, bbs.human_size(f["size"])))))
    if not files:
        out.append(ra.dim("No matches."))
    return "\n".join(out + [ra.nav()])


if __name__ == "__main__":
    ra.run(render)
