#!/usr/bin/env python3
"""
Message boards: topic boards with threaded conversations.

Anyone can read; posting needs a registered handle. Composing is a draft
(one paragraph at a time, since micron text boxes are single-line), and
Reply with quote seeds the draft with the parent's words. Boards are
managed on the sysop page.

Version: 1.0
Author: Brad Brown Jr (KC1JMH)
"""

import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.realpath(__file__))), "lib"))
import bbs  # noqa: E402
import rnsapps as ra  # noqa: E402

VERSION = "1.0"
KIND = "msg"
THREADS_PER_PAGE = 10
POSTS_PER_PAGE = 6


def need_register(note=""):
    out = [ra.heading("Message boards")]
    if note:
        out.append(ra.color(note, ra.C_WARN))
    return out + [ra.link("Register", "register"), ra.nav(("Boards", "msg"))]


def boards_view(conn, ident, note=""):
    out = [ra.heading("Message boards")]
    if note:
        out += [ra.color(note, ra.C_WARN), ""]
    draft = bbs.draft_get(conn, ident, KIND) if ident else None
    if draft:
        out += [ra.link("Resume your draft", "msg", v="compose"), ""]
    for b in bbs.boards(conn, ident):
        n, unread = bbs.board_counts(conn, b["id"], ident)
        flags = (" (read-only)" if b["readonly"] else "") + (" (locked)" if b["locked"] else "") + (" (hidden)" if b["hidden"] else "")
        out.append(ra.link(b["name"], "msg", b=b["id"]) + (ra.dim(flags) if flags else ""))
        out.append(ra.dim("{} thread{}{}  {}".format(n, "" if n == 1 else "s", ", {} new".format(unread) if unread else "",
                                                     b["description"][:60])))
    return out + [ra.nav()]


def board_view(conn, ident, board, page, note=""):
    n, _ = bbs.board_counts(conn, board["id"], ident)
    pages = max((n + THREADS_PER_PAGE - 1) // THREADS_PER_PAGE, 1)
    page = min(max(page, 1), pages)
    out = [ra.heading(board["name"]), ra.dim(board["description"][:100])]
    if note:
        out += [ra.color(note, ra.C_WARN)]
    ok, _ = bbs.can_post_in(board, ident)
    out += ["", ra.link("New thread", "msg", v="compose", a="new", b=board["id"]) if ok else ra.dim("No new threads here."), ""]
    rows = bbs.conn_threads(conn, ident, board["id"], page, THREADS_PER_PAGE)
    for t in rows:
        mark = ra.color(" NEW", ra.C_OK) if ident and t["unread"] else ""
        sticky = ra.dim("[pinned] ") if t["sticky"] else ""
        out.append("{}{}{}".format(sticky, ra.link(t["title"], "msg", t=t["id"]), mark))
        out.append(ra.dim("{} replies, last {}".format(max(t["post_count"] - 1, 0), ra.age_text(t["last_at"]))))
    if not rows:
        out.append("No threads yet.")
    pager = []
    if page > 1:
        pager.append(ra.link("< Newer", "msg", b=board["id"], p=page - 1))
    if page < pages:
        pager.append(ra.link("Older >", "msg", b=board["id"], p=page + 1))
    return out + ["", ra.dim("Page {} of {}".format(page, pages)), ra.nav(*pager, ("Boards", "msg"))]


def thread_view(conn, ident, thread, page, note=""):
    board = conn.execute("SELECT * FROM boards WHERE id=?", (thread["board_id"],)).fetchone()
    posts = conn.execute("SELECT * FROM posts WHERE thread_id=? ORDER BY id", (thread["id"],)).fetchall()
    position = {p["id"]: n for n, p in enumerate(posts, 1)}
    pages = max((len(posts) + POSTS_PER_PAGE - 1) // POSTS_PER_PAGE, 1)
    page = pages if page == 0 else min(max(page, 1), pages)
    chunk = posts[(page - 1) * POSTS_PER_PAGE:page * POSTS_PER_PAGE]
    out = [ra.heading(thread["title"]), ra.dim("in ") + ra.link(board["name"], "msg", b=board["id"])
           + ra.dim("  page {} of {}".format(page, pages))]
    if thread["locked"] or board["locked"]:
        out.append(ra.color("Locked.", ra.C_WARN))
    if note:
        out.append(ra.color(note, ra.C_WARN))
    can_reply, _ = bbs.can_post_in(board, ident)
    can_reply = bool(ident) and can_reply and not thread["locked"]
    sysop = ra.is_sysop(ident)
    for p in chunk:
        out += ["", ra.divider()]
        head = "{} {}  {}".format(ra.dim("#{}".format(position[p["id"]])), bbs.who(p["author"]), ra.dim(ra.age_text(p["created"])))
        if p["parent_id"] in position:
            parent = next(x for x in posts if x["id"] == p["parent_id"])
            head += ra.dim("  re #{} ".format(position[p["parent_id"]])) + ra.esc(ra.display_name(parent["author"]))
        out.append(head)
        if p["deleted"]:
            out.append(ra.dim("[deleted]"))
        else:
            out += bbs.body_lines(p["body"])
            acts = []
            if can_reply:
                acts += [ra.link("Reply", "msg", v="compose", a="reply", t=thread["id"], r=p["id"]),
                         ra.link("Quote", "msg", v="compose", a="reply", t=thread["id"], r=p["id"], q=1)]
            mine = ident and p["author"] == ident and bbs.now() - p["created"] <= bbs.EDIT_WINDOW
            if sysop or mine:
                acts.append(ra.link("Delete", "msg", a="del", t=thread["id"], r=p["id"], p=page))
            if acts:
                out.append("  ".join(acts))
    if chunk:
        bbs.mark_read(conn, ident, thread["id"], chunk[-1]["id"])
    pager = []
    if page > 1:
        pager.append(ra.link("< Prev", "msg", t=thread["id"], p=page - 1))
    if page < pages:
        pager.append(ra.link("Next >", "msg", t=thread["id"], p=page + 1))
        pager.append(ra.link("Last", "msg", t=thread["id"], p=0))
    if sysop:
        out += ["", ra.dim("Sysop: ") + "  ".join([
            ra.link("Unlock" if thread["locked"] else "Lock", "msg", t=thread["id"], a="lock"),
            ra.link("Unpin" if thread["sticky"] else "Pin", "msg", t=thread["id"], a="pin"),
            ra.link("Delete thread", "msg", t=thread["id"], a="delthread")])]
    tail = ["", ra.link("Reply to thread", "msg", v="compose", a="reply", t=thread["id"], r=0)] if can_reply else []
    return out + tail + [ra.nav(*pager, ("Boards", "msg"))]


def compose_view(conn, ident, draft, note=""):
    target = draft["target"].split(":")
    if target[0] == "new":
        board = conn.execute("SELECT name FROM boards WHERE id=?", (int(target[1]),)).fetchone()
        title, fields = "New thread in {}".format(board["name"] if board else "?"), [("title", "Thread title", 50)]
        base = {"v": "compose"}
    else:
        thread = conn.execute("SELECT title FROM threads WHERE id=?", (int(target[1]),)).fetchone()
        title, fields = "Reply: {}".format(thread["title"][:40] if thread else "?"), []
        base = {"v": "compose"}
    out = bbs.compose_lines("msg", KIND, draft, title, fields, bbs.MAX_POST, "Post", **base)
    if note:
        out.insert(1, ra.color(note, ra.C_WARN))
    return out + [ra.nav(("Boards", "msg"))]


def render():
    ident = ra.identity()
    conn = bbs.connect()
    a, v = ra.var("a"), ra.var("v")
    page = ra.int_var("p", 1)
    board_id, thread_id = ra.int_var("b", 0), ra.int_var("t", 0)

    # ---- compose flow
    if v == "compose" or a in ("add", "undo", "send", "cancel"):
        if not ident:
            return "\n".join(need_register("Identify to this node to post."))
        ok, msg = bbs.can_write(conn, ident)
        if not ok:
            return "\n".join(need_register(msg))
        draft = bbs.draft_get(conn, ident, KIND)
        if a == "new":
            draft = bbs.new_draft("new:{}".format(board_id))
        elif a == "reply":
            parent = conn.execute("SELECT * FROM posts WHERE id=? AND thread_id=?", (ra.int_var("r", 0), thread_id)).fetchone()
            quote = bbs.quote_text(ra.display_name(parent["author"]), parent["body"]) if parent and ra.var("q") and not parent["deleted"] else ""
            draft = bbs.new_draft("reply:{}:{}".format(thread_id, parent["id"] if parent else 0), quote)
        if a in ("new", "reply"):
            bbs.draft_put(conn, ident, KIND, draft)
        if not draft:
            return "\n".join(boards_view(conn, ident, "No draft in progress."))
        target = draft["target"].split(":")

        if a == "cancel":
            bbs.draft_clear(conn, ident, KIND)
            return "\n".join(boards_view(conn, ident, "Draft discarded."))
        if a == "undo" and draft["paras"]:
            draft["paras"].pop()
            bbs.draft_put(conn, ident, KIND, draft)
        if a == "add":
            draft["meta_fields"] = ["title"] if target[0] == "new" else []
            bbs.apply_add(draft)
            if bbs.own_chars(draft) > bbs.MAX_POST:
                draft["paras"].pop()
                bbs.draft_put(conn, ident, KIND, draft)
                return "\n".join(compose_view(conn, ident, draft, "That would pass {} characters.".format(bbs.MAX_POST)))
            bbs.draft_put(conn, ident, KIND, draft)
        if a == "send":
            if not draft["paras"]:
                return "\n".join(compose_view(conn, ident, draft, "Add some text first."))
            body = bbs.final_body(draft)
            if target[0] == "new":
                ok, msg, tid = bbs.create_thread(conn, ident, int(target[1]), draft["meta"].get("title", ""), body)
            else:
                ok, msg, pid = bbs.add_post(conn, ident, int(target[1]), int(target[2]) or None, body)
                tid = int(target[1])
            if not ok:
                return "\n".join(compose_view(conn, ident, draft, msg))
            bbs.draft_clear(conn, ident, KIND)
            thread = conn.execute("SELECT * FROM threads WHERE id=?", (tid,)).fetchone()
            return "\n".join(thread_view(conn, ident, thread, 0, ""))
        return "\n".join(compose_view(conn, ident, draft))

    # ---- sysop thread controls
    note = ""
    if a == "delthread" and ra.is_sysop(ident) and thread_id and not ra.var("ok"):
        return "\n".join([ra.heading("Delete thread?"), "This removes the whole thread and every reply.", "",
                          ra.link("Yes, delete it", "msg", t=thread_id, a="delthread", ok=1), "  ", ra.link("No", "msg", t=thread_id),
                          ra.nav()])
    if a in ("lock", "pin", "delthread") and ra.is_sysop(ident) and thread_id:
        if a == "delthread":
            with bbs.tx(conn):
                board = conn.execute("SELECT board_id FROM threads WHERE id=?", (thread_id,)).fetchone()
                conn.execute("DELETE FROM posts WHERE thread_id=?", (thread_id,))
                conn.execute("DELETE FROM reads WHERE thread_id=?", (thread_id,))
                conn.execute("DELETE FROM threads WHERE id=?", (thread_id,))
            board_id, thread_id = (board["board_id"] if board else 0), 0
        else:
            conn.execute("UPDATE threads SET {0}=1-{0} WHERE id=?".format("locked" if a == "lock" else "sticky"), (thread_id,))

    # ---- delete
    if a == "del" and ident:
        ok, note = bbs.delete_post(conn, ident, ra.int_var("r", 0))
        note = "" if ok else note

    # ---- read views
    if thread_id:
        thread = conn.execute("SELECT * FROM threads WHERE id=?", (thread_id,)).fetchone()
        if thread:
            return "\n".join(thread_view(conn, ident, thread, page, note))
    if board_id:
        board = conn.execute("SELECT * FROM boards WHERE id=?", (board_id,)).fetchone()
        if board and (not board["hidden"] or ra.is_sysop(ident)):
            return "\n".join(board_view(conn, ident, board, page, note))
    return "\n".join(boards_view(conn, ident, note))


if __name__ == "__main__":
    ra.run(render)
