#!/usr/bin/env python3
"""
Private mail between registered handles, threaded by conversation.

Addressed by handle. Reply and Reply-with-quote work as on the boards; the
draft is composed a paragraph at a time. Only the sender and the recipient
can read a message.

Version: 1.0
Author: Brad Brown Jr (KC1JMH)
"""

import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.realpath(__file__))), "lib"))
import bbs  # noqa: E402
import rnsapps as ra  # noqa: E402

VERSION = "1.0"
KIND = "mail"
PER_PAGE = 10


def not_ready(note):
    return "\n".join([ra.heading("Mail"), ra.color(note, ra.C_WARN), ra.link("Register", "register"), ra.nav()])


def tabs(box):
    return "  ".join([ra.bold("Inbox") if box == "in" else ra.link("Inbox", "mail"),
                      ra.bold("Sent") if box == "out" else ra.link("Sent", "mail", box="out"),
                      ra.link("Write", "mail", v="compose", a="new")])


def list_view(conn, ident, box, page, note=""):
    col, flag = ("recipient", "del_recipient") if box == "in" else ("sender", "del_sender")
    total = conn.execute("SELECT COUNT(*) FROM mail WHERE {}=? AND {}=0".format(col, flag), (ident,)).fetchone()[0]
    pages = max((total + PER_PAGE - 1) // PER_PAGE, 1)
    page = min(max(page, 1), pages)
    rows = conn.execute("SELECT * FROM mail WHERE {}=? AND {}=0 ORDER BY id DESC LIMIT ? OFFSET ?".format(col, flag),
                        (ident, PER_PAGE, (page - 1) * PER_PAGE)).fetchall()
    out = [ra.heading("Mail: " + ("Inbox" if box == "in" else "Sent")), tabs(box)]
    if note:
        out.append(ra.color(note, ra.C_OK))
    out.append("")
    for m in rows:
        other = m["sender"] if box == "in" else m["recipient"]
        new = ra.color(" NEW", ra.C_OK) if box == "in" and not m["read"] else ""
        out.append("{}{}".format(ra.link(m["subject"][:50], "mail", m=m["id"], box=box), new))
        out.append(ra.dim("{} ".format("from" if box == "in" else "to")) + bbs.who(other) + ra.dim("  " + ra.age_text(m["created"])))
    if not rows:
        out.append("Nothing here.")
    pager = []
    if page > 1:
        pager.append(ra.link("< Newer", "mail", box=box, p=page - 1))
    if page < pages:
        pager.append(ra.link("Older >", "mail", box=box, p=page + 1))
    on = bbs.pref_get(conn, ident, "mail_notify")
    return out + ["", ra.dim("Page {} of {}".format(page, pages)),
                  ra.dim("LXMF notice on new mail: {} ".format("on" if on else "off")) + ra.link("turn " + ("off" if on else "on"), "mail", a="notify"),
                  ra.nav(*pager)]


def message_view(conn, ident, mail_id, box, note=""):
    m = conn.execute("SELECT * FROM mail WHERE id=?", (mail_id,)).fetchone()
    if not m or not bbs.mail_visible(m, ident):
        return list_view(conn, ident, box, 1, "That message is gone.")
    if m["recipient"] == ident and not m["read"]:
        conn.execute("UPDATE mail SET read=1 WHERE id=?", (mail_id,))
    conv = conn.execute("SELECT * FROM mail WHERE conv_id=? ORDER BY id", (m["conv_id"],)).fetchall()
    conv = [c for c in conv if bbs.mail_visible(c, ident)]
    out = [ra.heading(m["subject"]), ra.dim("Conversation of {}".format(len(conv))) if len(conv) > 1 else ""]
    if note:
        out.append(ra.color(note, ra.C_OK))
    for c in conv:
        out += ["", ra.divider(), "{} {} {} {}".format(ra.dim("from"), bbs.who(c["sender"]), ra.dim("to"), bbs.who(c["recipient"]))
                + ra.dim("  " + ra.age_text(c["created"])) + (ra.bold("  <") if c["id"] == mail_id else "")]
        out += bbs.body_lines(c["body"])
    acts = []
    if m["sender"] != ident:
        acts += [ra.link("Reply", "mail", v="compose", a="reply", m=mail_id), ra.link("Quote", "mail", v="compose", a="reply", m=mail_id, q=1),
                 ra.link("Block sender", "mail", a="block", m=mail_id)]
    acts.append(ra.link("Delete", "mail", a="del", m=mail_id, box=box))
    return out + ["", "  ".join(acts), ra.nav(ra.link("Mail", "mail", box=box))]


def compose_view(conn, ident, draft, note=""):
    target = draft["target"]
    if target == "new":
        title, fields = "Write mail", [("to", "To (handle)", 20), ("subject", "Subject", 40)]
    else:
        fields = []
        title = "Reply: {}".format(draft["meta"].get("subject", "")[:40])
    out = bbs.compose_lines("mail", KIND, draft, title, fields, bbs.MAX_MAIL, "Send", v="compose")
    if note:
        out.insert(1, ra.color(note, ra.C_WARN))
    return out + [ra.nav(("Mail", "mail"))]


def render():
    ident = ra.identity()
    if not ident:
        return not_ready("Mail needs this node to know who you are. Identify, then register a handle.")
    conn = bbs.connect()
    ok, msg = bbs.can_write(conn, ident)
    if not ok and not ra.handle_for(ident):
        return not_ready(msg)
    a, v, box = ra.var("a"), ra.var("v"), ra.var("box", "in")
    mail_id, page = ra.int_var("m", 0), ra.int_var("p", 1)

    if v == "compose" or a in ("add", "undo", "send", "cancel"):
        draft = bbs.draft_get(conn, ident, KIND)
        if a == "new":
            draft = bbs.new_draft("new")
            bbs.draft_put(conn, ident, KIND, draft)
        elif a == "reply":
            parent = conn.execute("SELECT * FROM mail WHERE id=?", (mail_id,)).fetchone()
            if not parent or parent["recipient"] != ident:
                return "\n".join(list_view(conn, ident, "in", 1, "You can only reply to mail you received."))
            subject = parent["subject"] if parent["subject"].lower().startswith("re:") else "Re: " + parent["subject"]
            quote = bbs.quote_text(ra.display_name(parent["sender"]), parent["body"]) if ra.var("q") else ""
            draft = bbs.new_draft("reply:{}".format(parent["id"]), quote, to=ra.display_name(parent["sender"]), subject=subject)
            bbs.draft_put(conn, ident, KIND, draft)
        if not draft:
            return "\n".join(list_view(conn, ident, "in", 1, "No draft in progress."))
        if a == "cancel":
            bbs.draft_clear(conn, ident, KIND)
            return "\n".join(list_view(conn, ident, "in", 1, "Draft discarded."))
        if a == "undo" and draft["paras"]:
            draft["paras"].pop()
            bbs.draft_put(conn, ident, KIND, draft)
        if a == "add":
            draft["meta_fields"] = ["to", "subject"] if draft["target"] == "new" else []
            bbs.apply_add(draft)
            if bbs.own_chars(draft) > bbs.MAX_MAIL:
                draft["paras"].pop()
                bbs.draft_put(conn, ident, KIND, draft)
                return "\n".join(compose_view(conn, ident, draft, "That would pass {} characters.".format(bbs.MAX_MAIL)))
            bbs.draft_put(conn, ident, KIND, draft)
        if a == "send":
            if not draft["paras"]:
                return "\n".join(compose_view(conn, ident, draft, "Add some text first."))
            parent_id = int(draft["target"].split(":")[1]) if draft["target"].startswith("reply:") else None
            to = draft["meta"].get("to", "")
            if not to:
                return "\n".join(compose_view(conn, ident, draft, "Who is it for? Fill in To."))
            ok, msg, _ = bbs.send_mail(conn, ident, to, draft["meta"].get("subject", ""), bbs.final_body(draft), parent_id)
            if not ok:
                return "\n".join(compose_view(conn, ident, draft, msg))
            bbs.draft_clear(conn, ident, KIND)
            return "\n".join(list_view(conn, ident, "out", 1, "Sent."))
        return "\n".join(compose_view(conn, ident, draft))

    if a == "notify":
        bbs.pref_set(conn, ident, "mail_notify", 1 - bbs.pref_get(conn, ident, "mail_notify"))
        return "\n".join(list_view(conn, ident, "in", 1, "Notices {}.".format("on" if bbs.pref_get(conn, ident, "mail_notify") else "off")))
    if a == "del" and mail_id:
        bbs.delete_mail(conn, ident, mail_id)
        return "\n".join(list_view(conn, ident, box, 1, "Deleted."))
    if a == "block" and mail_id:
        m = conn.execute("SELECT sender, recipient FROM mail WHERE id=?", (mail_id,)).fetchone()
        if m and m["recipient"] == ident:
            conn.execute("INSERT OR IGNORE INTO blocks VALUES (?,?)", (ident, m["sender"]))
            return "\n".join(list_view(conn, ident, "in", 1, "{} is blocked.".format(ra.display_name(m["sender"]))))
    if mail_id:
        return "\n".join(message_view(conn, ident, mail_id, box))
    return "\n".join(list_view(conn, ident, "out" if box == "out" else "in", page))


if __name__ == "__main__":
    ra.run(render)
