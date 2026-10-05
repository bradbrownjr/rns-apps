#!/usr/bin/env python3
"""
Community wall: one-line messages (port of bpq-apps wall.py).

Posting needs an identified visitor. Authors can delete their own posts and
sysops can delete any post.

Version: 1.0
Author: Brad Brown Jr (KC1JMH)
"""

import os
import sys
import time
import uuid

sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.realpath(__file__))), "lib"))
import rnsapps as ra  # noqa: E402

VERSION = "1.0"
WALL_FILE = "wall.json"
MAX_LEN = 200
MAX_POSTS = 500
PER_PAGE = 15
POST_INTERVAL = 30  # seconds between posts per identity


def load():
    return ra.load_json(ra.data_path(WALL_FILE), {"messages": []})


def save(data):
    ra.save_json(ra.data_path(WALL_FILE), data)


def post(ident, text):
    """Returns (ok, message)."""
    text = " ".join(text.split())
    if not text:
        return False, "Message is empty."
    if len(text) > MAX_LEN:
        return False, "Too long ({} chars). Max {}.".format(len(text), MAX_LEN)
    with ra.locked("wall"):
        data = load()
        msgs = data["messages"]
        last = max((m.get("epoch", 0) for m in msgs if m.get("identity") == ident), default=0)
        if time.time() - last < POST_INTERVAL:
            return False, "Slow down - one post per {} seconds.".format(POST_INTERVAL)
        msgs.append({
            "id": uuid.uuid4().hex[:8],
            "identity": ident,
            "callsign": ra.display_name(ident),
            "message": text,
            "timestamp": ra.utc_iso(),
            "epoch": time.time(),
        })
        data["messages"] = msgs[-MAX_POSTS:]
        save(data)
    return True, "Posted."


def delete(ident, msg_id):
    with ra.locked("wall"):
        data = load()
        for m in data["messages"]:
            if m.get("id") == msg_id:
                if m.get("identity") != ident and not ra.is_sysop(ident):
                    return False, "You can only delete your own posts."
                data["messages"].remove(m)
                save(data)
                return True, "Deleted."
    return False, "That post is already gone."


def render():
    ident = ra.identity()
    action = ra.var("action")
    out = [ra.heading("Wall")]

    if action in ("post", "del"):
        if not ident:
            ok, note = False, "Identify to this node to post or delete."
        elif action == "post":
            ok, note = post(ident, ra.field("message"))
        else:
            ok, note = delete(ident, ra.var("id"))
        out += [ra.color(note, ra.C_OK if ok else ra.C_WARN), ""]

    if ident:
        out += [
            "{} {}".format(ra.input_field("message", 60), ra.submit("Post", "wall", "message", action="post")),
            ra.dim("Posting as {}. Max {} characters.".format(ra.display_name(ident), MAX_LEN)),
        ]
    else:
        out.append(ra.dim("Identify to this node to post. Reading is open to all."))
    out += ["", ra.divider()]

    msgs = sorted(load()["messages"], key=lambda m: m.get("timestamp", ""), reverse=True)
    if not msgs:
        out.append("No messages yet. Be the first!")
        return "\n".join(out + [ra.nav()])

    pages = (len(msgs) + PER_PAGE - 1) // PER_PAGE
    page = min(max(ra.int_var("p", 1), 1), pages)
    sysop = ra.is_sysop(ident)
    for m in msgs[(page - 1) * PER_PAGE:page * PER_PAGE]:
        line = "{} {}: {}".format(
            ra.dim("[{}]".format(ra.fmt_ts(m.get("timestamp")))),
            ra.color(m.get("callsign", "?"), ra.C_HEAD),
            ra.esc(m.get("message", "")),
        )
        if ident and (m.get("identity") == ident or sysop):
            line += "  " + ra.link("x", "wall", action="del", id=m.get("id", ""), p=page)
        out.append(line)

    out += ["", ra.dim("{} message{}, page {} of {}  (UTC times)".format(len(msgs), "" if len(msgs) == 1 else "s", page, pages))]
    pager = []
    if page > 1:
        pager.append(ra.link("< Newer", "wall", p=page - 1))
    if page < pages:
        pager.append(ra.link("Older >", "wall", p=page + 1))
    pager.append(ra.link("Refresh", "wall"))
    return "\n".join(out + [ra.nav(*pager)])


if __name__ == "__main__":
    ra.run(render)
