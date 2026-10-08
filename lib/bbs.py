"""
Message boards, mail and compose drafts for rns-apps, on SQLite.

Every page request is its own process, so state lives in /data/apps/bbs.db
(WAL mode, writers serialized with BEGIN IMMEDIATE). Schema changes are
migrations keyed on PRAGMA user_version.

Identity (the verified remote_identity hash) is the key for everything;
handles are display names looked up from users.json at render time, so a
renamed handle shows everywhere. Sysops are recognized by identity only.

Version: 1.1
Author: Brad Brown Jr (KC1JMH)
"""

import json
import os
import re
import sqlite3
import time
from contextlib import contextmanager

import rnsapps as ra

VERSION = "1.1"

POST_INTERVAL = 30       # seconds between posts/mails per identity
MAX_POST = 1500          # characters of the author's own text per post
MAX_MAIL = 3000
MAX_PARA = 600           # characters added in one compose step
MAX_QUOTE = 320
EDIT_WINDOW = 15 * 60    # authors may delete their own post this long
MAILBOX_CAP = 100
MAIL_INTERVAL = 60

MIGRATIONS = [
    """
    CREATE TABLE boards (
        id INTEGER PRIMARY KEY, name TEXT NOT NULL, description TEXT DEFAULT '',
        sort INTEGER DEFAULT 100, readonly INTEGER DEFAULT 0, locked INTEGER DEFAULT 0,
        hidden INTEGER DEFAULT 0, created INTEGER);
    CREATE TABLE threads (
        id INTEGER PRIMARY KEY, board_id INTEGER NOT NULL REFERENCES boards(id),
        title TEXT NOT NULL, author TEXT NOT NULL, created INTEGER, last_post_id INTEGER DEFAULT 0,
        last_at INTEGER, post_count INTEGER DEFAULT 0, sticky INTEGER DEFAULT 0, locked INTEGER DEFAULT 0);
    CREATE INDEX threads_board ON threads(board_id, sticky DESC, last_at DESC);
    CREATE TABLE posts (
        id INTEGER PRIMARY KEY, thread_id INTEGER NOT NULL REFERENCES threads(id),
        parent_id INTEGER, author TEXT NOT NULL, body TEXT NOT NULL, created INTEGER,
        deleted INTEGER DEFAULT 0);
    CREATE INDEX posts_thread ON posts(thread_id, id);
    CREATE TABLE reads (
        identity TEXT NOT NULL, thread_id INTEGER NOT NULL, last_post_id INTEGER NOT NULL,
        PRIMARY KEY (identity, thread_id));
    CREATE TABLE drafts (
        identity TEXT NOT NULL, kind TEXT NOT NULL, data TEXT NOT NULL, updated INTEGER,
        PRIMARY KEY (identity, kind));
    CREATE TABLE mail (
        id INTEGER PRIMARY KEY, conv_id INTEGER NOT NULL, parent_id INTEGER,
        sender TEXT NOT NULL, recipient TEXT NOT NULL, subject TEXT, body TEXT NOT NULL,
        created INTEGER, read INTEGER DEFAULT 0, del_sender INTEGER DEFAULT 0, del_recipient INTEGER DEFAULT 0);
    CREATE INDEX mail_rcpt ON mail(recipient, del_recipient, id DESC);
    CREATE INDEX mail_send ON mail(sender, del_sender, id DESC);
    CREATE INDEX mail_conv ON mail(conv_id, id);
    CREATE TABLE blocks (identity TEXT NOT NULL, blocked TEXT NOT NULL, PRIMARY KEY (identity, blocked));
    CREATE TABLE mutes (identity TEXT PRIMARY KEY, reason TEXT, created INTEGER);
    INSERT INTO boards (name, description, sort, created)
        VALUES ('General', 'Anything goes. Be kind.', 10, strftime('%s','now'));
    """,
    """
    CREATE TABLE file_areas (
        id INTEGER PRIMARY KEY, parent_id INTEGER REFERENCES file_areas(id), name TEXT NOT NULL,
        description TEXT DEFAULT '', sort INTEGER DEFAULT 100, hidden INTEGER DEFAULT 0);
    CREATE TABLE files (
        id INTEGER PRIMARY KEY, area_id INTEGER NOT NULL REFERENCES file_areas(id), fname TEXT NOT NULL,
        title TEXT NOT NULL, description TEXT DEFAULT '', size INTEGER, sha256 TEXT, uploader TEXT,
        scan TEXT DEFAULT '', created INTEGER);
    CREATE INDEX files_area ON files(area_id, created DESC);
    CREATE TABLE uploads (
        id INTEGER PRIMARY KEY, fname TEXT NOT NULL, orig_name TEXT, size INTEGER, sha256 TEXT,
        sender TEXT, note TEXT DEFAULT '', created INTEGER, status TEXT DEFAULT 'pending', scan TEXT DEFAULT '');
    """,
    """
    CREATE TABLE prefs (identity TEXT PRIMARY KEY, mail_notify INTEGER DEFAULT 0, files_seen INTEGER DEFAULT 0);
    """,
]


def connect():
    """Open the database, migrating it to the current schema if needed."""
    conn = sqlite3.connect(ra.data_path("bbs.db"), timeout=15, isolation_level=None)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA journal_mode=WAL")
    conn.execute("PRAGMA foreign_keys=ON")
    version = conn.execute("PRAGMA user_version").fetchone()[0]
    if version < len(MIGRATIONS):
        conn.execute("BEGIN IMMEDIATE")
        version = conn.execute("PRAGMA user_version").fetchone()[0]
        for n in range(version, len(MIGRATIONS)):
            for stmt in [x for x in MIGRATIONS[n].split(";\n") if x.strip()]:
                conn.execute(stmt)
            conn.execute("PRAGMA user_version = {}".format(n + 1))
        conn.execute("COMMIT")
    return conn


@contextmanager
def tx(conn):
    conn.execute("BEGIN IMMEDIATE")
    try:
        yield conn
        conn.execute("COMMIT")
    except Exception:
        conn.execute("ROLLBACK")
        raise


def now():
    return int(time.time())


# ------------------------------------------------------------------ people ---

def who(ident):
    """Handle (or short id) plus a sysop badge, as micron."""
    return ra.esc(ra.display_name(ident)) + ra.sysop_badge(ident)


def find_handle(handle):
    """Identity for a handle (case-insensitive), or None."""
    handle = handle.strip().lower()
    for ident, rec in ra.users().items():
        if rec.get("handle", "").lower() == handle:
            return ident
    return None


def can_write(conn, ident):
    """(ok, message): registered, not muted."""
    if not ident:
        return False, "Identify to this node first."
    if not ra.handle_for(ident):
        return False, "Register a handle first."
    row = conn.execute("SELECT reason FROM mutes WHERE identity=?", (ident,)).fetchone()
    if row:
        return False, "You are muted{}.".format(": " + row["reason"] if row["reason"] else "")
    return True, ""


def rate_ok(conn, table, column, ident, interval):
    row = conn.execute("SELECT MAX(created) AS t FROM {} WHERE {}=?".format(table, column), (ident,)).fetchone()
    return not (row["t"] and now() - row["t"] < interval)


# ------------------------------------------------------------------ drafts ---

def draft_get(conn, ident, kind):
    row = conn.execute("SELECT data FROM drafts WHERE identity=? AND kind=?", (ident, kind)).fetchone()
    return json.loads(row["data"]) if row else None


def draft_put(conn, ident, kind, draft):
    conn.execute("INSERT OR REPLACE INTO drafts VALUES (?,?,?,?)", (ident, kind, json.dumps(draft), now()))


def draft_clear(conn, ident, kind):
    conn.execute("DELETE FROM drafts WHERE identity=? AND kind=?", (ident, kind))


def new_draft(target, quote="", **meta):
    return {"target": target, "quote": quote, "paras": [], "meta": meta}


def quote_text(handle, body):
    """'> handle wrote:' plus the first part of the parent's own words. Lines
    the parent itself quoted are dropped so quotes never nest."""
    own = [l.strip() for l in body.split("\n") if l.strip() and not l.lstrip().startswith(">")]
    text = " ".join(own)
    if len(text) > MAX_QUOTE:
        text = text[:MAX_QUOTE].rsplit(" ", 1)[0] + " ..."
    lines, line = ["> {} wrote:".format(handle)], ""
    for word in text.split():
        if len(line) + len(word) + 1 > 56:
            lines.append("> " + line)
            line = word
        else:
            line = (line + " " + word).strip()
    if line:
        lines.append("> " + line)
    return "\n".join(lines)


def final_body(draft):
    parts = [draft["quote"]] if draft.get("quote") else []
    parts.append("\n".join(draft["paras"]))
    return "\n\n".join(p for p in parts if p).strip()


def own_chars(draft):
    return sum(len(p) for p in draft["paras"])


def apply_add(draft):
    """Fold submitted compose fields into the draft. Returns an error or ''."""
    for name in draft.get("meta_fields", []):
        value = " ".join(ra.field(name).split())
        if value:
            draft["meta"][name] = value
    text = " ".join(ra.field("text").split())
    if text:
        if len(text) > MAX_PARA:
            text = text[:MAX_PARA]
        draft["paras"].append(text)
    return ""


def compose_lines(page, kind, draft, title, fields, limit, post_label="Post", **base):
    """Shared compose screen. fields: [(meta name, label, width)]. base:
    link variables that route back to this compose screen."""
    draft["meta_fields"] = [f[0] for f in fields]
    out = [ra.heading(title)]
    for name, label, width in fields:
        out += [ra.dim(label), ra.input_field(name, width, draft["meta"].get(name, ""))]
    if draft.get("quote"):
        out += ["", ra.dim("Quoting:")] + [ra.dim(l) for l in draft["quote"].split("\n")]
    out.append("")
    for n, para in enumerate(draft["paras"], 1):
        out.append("{} {}".format(ra.dim("{}.".format(n)), ra.esc(para)))
    used = own_chars(draft)
    out += ["", ra.dim("Add a paragraph ({} of {} characters used):".format(used, limit)),
            ra.input_field("text", 60, ""),
            ra.submit("Add", page, "|".join([f[0] for f in fields] + ["text"]), a="add", **base)]
    actions = []
    if draft["paras"]:
        actions += [ra.link("Undo last", page, a="undo", **base), ra.link(post_label, page, a="send", **base)]
    actions.append(ra.link("Cancel", page, a="cancel", **base))
    return out + ["", "  ".join(actions)]


def body_lines(body):
    """Post/mail body as micron lines; quoted lines dimmed."""
    out = []
    for line in body.replace("\r", "").split("\n"):
        if line.lstrip().startswith(">"):
            out.append(ra.dim(line))
        else:
            out.append(ra.esc(line) if line.strip() else "")
    return out


# ------------------------------------------------------------------ boards ---

def boards(conn, ident):
    return conn.execute("SELECT * FROM boards WHERE hidden=0 OR ?=1 ORDER BY sort, id",
                        (1 if ra.is_sysop(ident) else 0,)).fetchall()


def board_counts(conn, board_id, ident):
    """(threads, unread threads) for a board."""
    n = conn.execute("SELECT COUNT(*) FROM threads WHERE board_id=?", (board_id,)).fetchone()[0]
    if not ident:
        return n, 0
    unread = conn.execute(
        """SELECT COUNT(*) FROM threads t LEFT JOIN reads r ON r.thread_id=t.id AND r.identity=?
           WHERE t.board_id=? AND COALESCE(r.last_post_id,0) < t.last_post_id""", (ident, board_id)).fetchone()[0]
    return n, unread


def unread_total(conn, ident):
    if not ident:
        return 0
    return conn.execute(
        """SELECT COUNT(*) FROM threads t JOIN boards b ON b.id=t.board_id AND b.hidden=0
           LEFT JOIN reads r ON r.thread_id=t.id AND r.identity=?
           WHERE COALESCE(r.last_post_id,0) < t.last_post_id""", (ident,)).fetchone()[0]


def conn_threads(conn, ident, board_id, page, per_page):
    return conn.execute(
        """SELECT t.*, CASE WHEN COALESCE(r.last_post_id,0) < t.last_post_id THEN 1 ELSE 0 END AS unread
           FROM threads t LEFT JOIN reads r ON r.thread_id=t.id AND r.identity=?
           WHERE t.board_id=? ORDER BY t.sticky DESC, t.last_at DESC LIMIT ? OFFSET ?""",
        (ident or "", board_id, per_page, (page - 1) * per_page)).fetchall()


def mark_read(conn, ident, thread_id, last_post_id):
    if ident:
        conn.execute("""INSERT INTO reads VALUES (?,?,?) ON CONFLICT(identity, thread_id)
                        DO UPDATE SET last_post_id=MAX(last_post_id, excluded.last_post_id)""",
                     (ident, thread_id, last_post_id))


def can_post_in(board, ident):
    if board["locked"]:
        return False, "This board is locked."
    if board["readonly"] and not ra.is_sysop(ident):
        return False, "Only the sysop posts here."
    return True, ""


def create_thread(conn, ident, board_id, title, body):
    """Returns (ok, message, thread_id)."""
    ok, msg = can_write(conn, ident)
    if not ok:
        return False, msg, None
    title = " ".join(title.split())
    if not 3 <= len(title) <= 60:
        return False, "Give the thread a title of 3 to 60 characters.", None
    with tx(conn):
        board = conn.execute("SELECT * FROM boards WHERE id=?", (board_id,)).fetchone()
        if not board:
            return False, "That board is gone.", None
        ok, msg = can_post_in(board, ident)
        if not ok:
            return False, msg, None
        if not rate_ok(conn, "posts", "author", ident, POST_INTERVAL):
            return False, "Slow down: one post per {} seconds.".format(POST_INTERVAL), None
        t = now()
        cur = conn.execute("INSERT INTO threads (board_id,title,author,created,last_at) VALUES (?,?,?,?,?)",
                           (board_id, title, ident, t, t))
        tid = cur.lastrowid
        pid = conn.execute("INSERT INTO posts (thread_id,parent_id,author,body,created) VALUES (?,?,?,?,?)",
                           (tid, None, ident, body, t)).lastrowid
        conn.execute("UPDATE threads SET last_post_id=?, post_count=1 WHERE id=?", (pid, tid))
        mark_read(conn, ident, tid, pid)
    return True, "Posted.", tid


def add_post(conn, ident, thread_id, parent_id, body):
    """Returns (ok, message, post_id)."""
    ok, msg = can_write(conn, ident)
    if not ok:
        return False, msg, None
    with tx(conn):
        thread = conn.execute("SELECT t.*, b.locked AS blocked, b.readonly AS bro FROM threads t "
                              "JOIN boards b ON b.id=t.board_id WHERE t.id=?", (thread_id,)).fetchone()
        if not thread:
            return False, "That thread is gone.", None
        if thread["locked"] or thread["blocked"]:
            return False, "This thread is locked.", None
        if thread["bro"] and not ra.is_sysop(ident):
            return False, "Only the sysop posts here.", None
        if not rate_ok(conn, "posts", "author", ident, POST_INTERVAL):
            return False, "Slow down: one post per {} seconds.".format(POST_INTERVAL), None
        t = now()
        pid = conn.execute("INSERT INTO posts (thread_id,parent_id,author,body,created) VALUES (?,?,?,?,?)",
                           (thread_id, parent_id, ident, body, t)).lastrowid
        conn.execute("UPDATE threads SET last_post_id=?, last_at=?, post_count=post_count+1 WHERE id=?",
                     (pid, t, thread_id))
        mark_read(conn, ident, thread_id, pid)
    return True, "Posted.", pid


def delete_post(conn, ident, post_id):
    with tx(conn):
        post = conn.execute("SELECT * FROM posts WHERE id=?", (post_id,)).fetchone()
        if not post or post["deleted"]:
            return False, "That post is already gone."
        if not ra.is_sysop(ident):
            if post["author"] != ident or now() - post["created"] > EDIT_WINDOW:
                return False, "You can delete your own post for {} minutes.".format(EDIT_WINDOW // 60)
        conn.execute("UPDATE posts SET deleted=1, body='' WHERE id=?", (post_id,))
    return True, "Deleted."


# ------------------------------------------------------------------- files ---

def area_tree(conn, include_hidden=False):
    """[(area row, depth)] depth-first, siblings by sort order."""
    rows = conn.execute("SELECT * FROM file_areas WHERE hidden=0 OR ?=1 ORDER BY sort, id", (1 if include_hidden else 0,)).fetchall()
    kids = {}
    for r in rows:
        kids.setdefault(r["parent_id"], []).append(r)
    out = []

    def walk(parent, depth):
        for r in kids.get(parent, []):
            out.append((r, depth))
            walk(r["id"], depth + 1)
    walk(None, 0)
    return out


def area_path(conn, area_id):
    """[(id, name)] from the top-level area down to area_id."""
    path = []
    while area_id:
        row = conn.execute("SELECT id, parent_id, name FROM file_areas WHERE id=?", (area_id,)).fetchone()
        if not row:
            break
        path.append((row["id"], row["name"]))
        area_id = row["parent_id"]
    return path[::-1]


def area_descendants(conn, area_id):
    """Ids of every area below area_id."""
    found, todo = set(), [area_id]
    while todo:
        cur = todo.pop()
        for r in conn.execute("SELECT id FROM file_areas WHERE parent_id=?", (cur,)):
            if r["id"] not in found:
                found.add(r["id"])
                todo.append(r["id"])
    return found


def area_file_count(conn, area_id):
    """Files in this area and everything below it."""
    ids, todo = [], [area_id]
    while todo:
        cur = todo.pop()
        ids.append(cur)
        todo += [r["id"] for r in conn.execute("SELECT id FROM file_areas WHERE parent_id=?", (cur,))]
    return conn.execute("SELECT COUNT(*) FROM files WHERE area_id IN ({})".format(",".join("?" * len(ids))), ids).fetchone()[0]


def human_size(n):
    n = float(n or 0)
    for unit in ("B", "KB", "MB", "GB"):
        if n < 1024 or unit == "GB":
            return "{:.0f} {}".format(n, unit) if unit == "B" else "{:.1f} {}".format(n, unit)
        n /= 1024


def safe_filename(name):
    """A file name that is safe on disk and in a NomadNet path."""
    name = re.sub(r"[^A-Za-z0-9._() +-]", "_", os.path.basename(name or "")).strip(" .")[:80]
    name = name.replace(" ", "_") or "file"
    if name.lower().endswith(".allowed"):
        name += ".file"
    return name


# -------------------------------------------------------------------- mail ---

def mail_unread(conn, ident):
    if not ident:
        return 0
    return conn.execute("SELECT COUNT(*) FROM mail WHERE recipient=? AND read=0 AND del_recipient=0", (ident,)).fetchone()[0]


def send_mail(conn, ident, to_handle, subject, body, parent_id=None):
    """Returns (ok, message, mail_id)."""
    ok, msg = can_write(conn, ident)
    if not ok:
        return False, msg, None
    recipient = find_handle(to_handle)
    if not recipient or recipient == ident:
        return False, "No one can receive mail as '{}'.".format(to_handle) if not recipient else "You can't mail yourself.", None
    subject = " ".join(subject.split())[:60] or "(no subject)"
    with tx(conn):
        if conn.execute("SELECT 1 FROM blocks WHERE identity=? AND blocked=?", (recipient, ident)).fetchone():
            return False, "Could not deliver to {}.".format(to_handle), None
        if not rate_ok(conn, "mail", "sender", ident, MAIL_INTERVAL):
            return False, "Slow down: one message per {} seconds.".format(MAIL_INTERVAL), None
        held = conn.execute("SELECT COUNT(*) FROM mail WHERE recipient=? AND del_recipient=0", (recipient,)).fetchone()[0]
        if held >= MAILBOX_CAP:
            return False, "{}'s mailbox is full.".format(to_handle), None
        conv = conn.execute("SELECT conv_id FROM mail WHERE id=?", (parent_id,)).fetchone() if parent_id else None
        t = now()
        cur = conn.execute("INSERT INTO mail (conv_id,parent_id,sender,recipient,subject,body,created) VALUES (0,?,?,?,?,?,?)",
                           (parent_id, ident, recipient, subject, body, t))
        conn.execute("UPDATE mail SET conv_id=? WHERE id=?", (conv["conv_id"] if conv else cur.lastrowid, cur.lastrowid))
    if pref_get(conn, recipient, "mail_notify"):
        notify(recipient, "New mail", "New mail from {} on this node: {}".format(ra.display_name(ident), subject))
    return True, "Sent.", cur.lastrowid


def pref_get(conn, ident, col):
    row = conn.execute("SELECT {} FROM prefs WHERE identity=?".format(col), (ident,)).fetchone()
    return row[0] if row else 0


def pref_set(conn, ident, col, value):
    assert col in ("mail_notify", "files_seen")
    conn.execute("INSERT OR IGNORE INTO prefs (identity) VALUES (?)", (ident,))
    conn.execute("UPDATE prefs SET {}=? WHERE identity=?".format(col), (value, ident))


def new_files(conn, ident):
    """Files added since this identity last opened the Files page."""
    if not ident:
        return 0
    seen = pref_get(conn, ident, "files_seen")
    if not seen:
        return 0
    return conn.execute("SELECT COUNT(*) FROM files f JOIN file_areas a ON a.id=f.area_id WHERE a.hidden=0 AND f.created>?", (seen,)).fetchone()[0]


def mail_visible(row, ident):
    return (row["recipient"] == ident and not row["del_recipient"]) or (row["sender"] == ident and not row["del_sender"])


def delete_mail(conn, ident, mail_id):
    with tx(conn):
        row = conn.execute("SELECT * FROM mail WHERE id=?", (mail_id,)).fetchone()
        if not row or not mail_visible(row, ident):
            return False
        if row["recipient"] == ident:
            conn.execute("UPDATE mail SET del_recipient=1, read=1 WHERE id=?", (mail_id,))
        if row["sender"] == ident:
            conn.execute("UPDATE mail SET del_sender=1 WHERE id=?", (mail_id,))
        # purge once both sides have deleted
        conn.execute("DELETE FROM mail WHERE id=? AND del_sender=1 AND del_recipient=1", (mail_id,))
    return True


# --------------------------------------------------------------- file paths ---

def files_root():
    """Root of the file store: public/ (served by NomadNet), incoming/ (sysop
    drop box), pending/ (uploads awaiting approval)."""
    return os.environ.get("RNS_APPS_FILES") or ra.config().get("files_dir") or os.path.join(os.path.dirname(ra.DATA_DIR.rstrip("/")), "files")


def files_dir(kind):
    path = os.path.join(files_root(), kind)
    os.makedirs(path, exist_ok=True)
    return path


def publish_file(conn, area_id, src, fname, title, description="", uploader="", scan=""):
    """Move src into the public store under the area and record it.
    Returns (ok, message). The file name is made unique within the area."""
    import hashlib
    import shutil
    if not conn.execute("SELECT 1 FROM file_areas WHERE id=?", (area_id,)).fetchone():
        return False, "No such area."
    dest_dir = os.path.join(files_dir("public"), "a{}".format(int(area_id)))
    os.makedirs(dest_dir, exist_ok=True)
    fname = safe_filename(fname)
    stem, ext = os.path.splitext(fname)
    n = 1
    while os.path.exists(os.path.join(dest_dir, fname)):
        n += 1
        fname = "{}-{}{}".format(stem, n, ext)
    digest = hashlib.sha256()
    with open(src, "rb") as f:
        for chunk in iter(lambda: f.read(65536), b""):
            digest.update(chunk)
    size = os.path.getsize(src)
    shutil.move(src, os.path.join(dest_dir, fname))
    with tx(conn):
        conn.execute("INSERT INTO files (area_id, fname, title, description, size, sha256, uploader, scan, created) VALUES (?,?,?,?,?,?,?,?,?)",
                     (area_id, fname, (title or fname)[:80], (description or "")[:300], size, digest.hexdigest(), uploader, scan, now()))
    return True, "Added {}.".format(fname)


def remove_file(conn, file_id):
    row = conn.execute("SELECT * FROM files WHERE id=?", (file_id,)).fetchone()
    if not row:
        return
    path = os.path.join(files_dir("public"), "a{}".format(row["area_id"]), row["fname"])
    if os.path.exists(path):
        os.remove(path)
    with tx(conn):
        conn.execute("DELETE FROM files WHERE id=?", (file_id,))


def notify(ident, title, body):
    """Queue an LXMF notice to an identity; tools/lxmf_sender.py delivers it."""
    import secrets
    spool = os.path.join(ra.DATA_DIR, "lxmf_notify")
    os.makedirs(spool, exist_ok=True)
    path = os.path.join(spool, "{}-{}.json".format(now(), secrets.token_hex(3)))
    with open(path + ".tmp", "w") as f:
        json.dump({"identity": ident, "title": title, "body": body}, f)
    os.replace(path + ".tmp", path)
