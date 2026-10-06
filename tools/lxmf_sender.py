#!/usr/bin/env python3
"""
LXMF daemon: delivers queued form submissions and receives file uploads.

The FORMS page writes each finished form to /data/apps/forms_outbox/*.json.
This daemon (started by the container entrypoint) attaches to the node's
shared Reticulum instance, and sends each submission as an LXMF message to
every destination in config.json "forms_deliver_to" (LXMF delivery hashes,
e.g. a Sideband address). Delivery state is written back into the JSON
file; undelivered messages are retried for 48 hours.

Uploads: a visitor attaches a file to an LXMF message and sends it to this
node's LXMF address (written to /data/apps/lxmf_address.txt for the Files
page). The sender must be a registered, unmuted handle and the message
signature must verify. Files over the size/quota limits are refused,
executables and archives are scanned with ClamAV, and what passes waits in
the pending queue for sysop approval. Config keys (config.json):
upload_max_bytes (2 MB), upload_daily_bytes (10 MB), upload_pending_max (50),
clamd_host, clamd_port, clamd_scan (executables|all|off).

Version: 1.1
Author: Brad Brown Jr (KC1JMH)
"""

import glob
import json
import os
import socket
import sys
import time

RNS_DIR = os.environ.get("RNS_DIR", "/data/reticulum")
LXMF_DIR = os.environ.get("LXMF_DIR", "/data/lxmf")
APPS_DIR = os.environ.get("APPS_DIR", "/data/apps")
INSTANCE = os.environ.get("RNS_INSTANCE", "rns-apps")
POLL = 10
GIVE_UP = 48 * 3600
RETRY = 300


def log(msg):
    print("[lxmf-sender] " + msg, flush=True)


def instance_up():
    """True once nomadnet's shared Reticulum instance accepts connections."""
    for family, addr in ((socket.AF_UNIX, "\0rns/" + INSTANCE), (socket.AF_INET, ("127.0.0.1", 37428))):
        s = socket.socket(family, socket.SOCK_STREAM)
        s.settimeout(2)
        try:
            s.connect(addr)
            return True
        except OSError:
            pass
        finally:
            s.close()
    return False


def load(path):
    try:
        with open(path) as f:
            return json.load(f)
    except (OSError, ValueError):
        return None


def save(path, data):
    tmp = path + ".tmp"
    with open(tmp, "w") as f:
        json.dump(data, f, indent=2)
    os.replace(tmp, path)


sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.realpath(__file__))), "lib"))


def handle_upload(message, router, source, RNS, LXMF):
    """LXMF delivery callback: validate an uploaded file and queue it."""
    import hashlib
    import secrets

    import bbs
    import clam
    import rnsapps as ra

    cfg = ra.config()
    sender = RNS.Identity.recall(message.source_hash)

    def reply(text):
        if sender is None:
            return
        dest = RNS.Destination(sender, RNS.Destination.OUT, RNS.Destination.SINGLE, "lxmf", "delivery")
        router.handle_outbound(LXMF.LXMessage(dest, source, text, title="Upload",
                                              desired_method=LXMF.LXMessage.DIRECT))

    if sender is None or not message.signature_validated:
        log("upload from unverifiable sender {}".format(RNS.prettyhexrep(message.source_hash)))
        return reply("Could not verify your identity. Try again after your client announces.") if sender else None
    ident = sender.hash.hex()
    files = (message.fields or {}).get(LXMF.FIELD_FILE_ATTACHMENTS) or []
    if not files:
        return reply("No file attached. Attach a file and put a description in the message text.")
    conn = bbs.connect()
    ok, why = bbs.can_write(conn, ident)
    if not ok:
        return reply("Upload refused: {}".format(why))
    max_bytes = int(cfg.get("upload_max_bytes", 2 * 1024 * 1024))
    daily = int(cfg.get("upload_daily_bytes", 10 * 1024 * 1024))
    pending_max = int(cfg.get("upload_pending_max", 50))
    note = message.content_as_string().strip()[:300] if message.content else ""
    results = []
    for entry in files[:3]:
        try:
            orig, data = str(entry[0]), bytes(entry[1])
        except (TypeError, IndexError, ValueError):
            continue
        if not data or len(data) > max_bytes:
            results.append("{}: refused, limit is {} KB.".format(bbs.safe_filename(orig), max_bytes // 1024))
            continue
        used = conn.execute("SELECT COALESCE(SUM(size),0) FROM uploads WHERE sender=? AND created>? AND status!='rejected'",
                            (ident, bbs.now() - 86400)).fetchone()[0]
        if used + len(data) > daily:
            results.append("{}: refused, daily upload quota reached.".format(bbs.safe_filename(orig)))
            continue
        if conn.execute("SELECT COUNT(*) FROM uploads WHERE status='pending'").fetchone()[0] >= pending_max:
            results.append("{}: refused, the approval queue is full. Try later.".format(bbs.safe_filename(orig)))
            continue
        stored = "{}-{}".format(secrets.token_hex(6), bbs.safe_filename(orig))
        path = os.path.join(bbs.files_dir("pending"), stored)
        with open(path, "wb") as f:
            f.write(data)
        scan = ""
        mode = cfg.get("clamd_scan", "executables")
        if clam.needs_scan(path, mode):
            state, sig = clam.scan(path, cfg.get("clamd_host", "172.17.0.1"), int(cfg.get("clamd_port", 3310)))
            if state == "infected":
                os.remove(path)
                log("upload from {} rejected: {}".format(ident[:12], sig))
                results.append("{}: rejected, the virus scan flagged it.".format(bbs.safe_filename(orig)))
                continue
            if state == "error":
                os.remove(path)
                log("clamd: " + sig)
                results.append("{}: the virus scanner is unavailable, try again later.".format(bbs.safe_filename(orig)))
                continue
            scan = "clean"
        with bbs.tx(conn):
            conn.execute("INSERT INTO uploads (fname, orig_name, size, sha256, sender, note, created, status, scan) "
                         "VALUES (?,?,?,?,?,?,?,'pending',?)",
                         (stored, bbs.safe_filename(orig), len(data), hashlib.sha256(data).hexdigest(), ident, note, bbs.now(), scan))
        log("queued upload {} from {}".format(stored, ident[:12]))
        results.append("{}: received, waiting for sysop approval.".format(bbs.safe_filename(orig)))
    reply("\n".join(results) or "Nothing usable in that message.")


def main():
    while not instance_up():
        time.sleep(5)
    import LXMF
    import RNS

    RNS.Reticulum(configdir=RNS_DIR, loglevel=RNS.LOG_ERROR)
    os.makedirs(LXMF_DIR, exist_ok=True)
    id_path = os.path.join(LXMF_DIR, "identity")
    if os.path.exists(id_path):
        identity = RNS.Identity.from_file(id_path)
    else:
        identity = RNS.Identity()
        identity.to_file(id_path)
    router = LXMF.LXMRouter(identity=identity, storagepath=LXMF_DIR)
    source = router.register_delivery_identity(identity, display_name="rns-apps forms")
    log("up, sending as {}".format(RNS.prettyhexrep(source.hash)))
    router.register_delivery_callback(lambda m: handle_upload(m, router, source, RNS, LXMF))
    with open(os.path.join(APPS_DIR, "lxmf_address.txt"), "w") as f:
        f.write(source.hash.hex() + "\n")
    announced = 0

    inflight = {}  # (file, dest) -> (message, started)

    def finish(path, dest, ok):
        rec = load(path)
        if rec is None:
            return
        if ok and dest not in rec.setdefault("delivered", []):
            rec["delivered"].append(dest)
            log("delivered {} to {}".format(rec.get("id"), dest))
        save(path, rec)
        inflight.pop((path, dest), None)

    while True:
        if time.time() - announced > 6 * 3600:
            router.announce(source.hash)
            announced = time.time()
        cfg = load(os.path.join(APPS_DIR, "config.json")) or {}
        for path in sorted(glob.glob(os.path.join(APPS_DIR, "forms_outbox", "*.json"))):
            rec = load(path)
            if not rec:
                continue
            created = os.path.getctime(path)
            if time.time() - created > GIVE_UP:
                continue
            for dest in rec.get("deliver_to", []):
                if dest in rec.get("delivered", []):
                    continue
                key = (path, dest)
                if key in inflight:
                    msg, started = inflight[key]
                    if msg.state == LXMF.LXMessage.DELIVERED:
                        finish(path, dest, True)
                    elif msg.state == LXMF.LXMessage.FAILED or time.time() - started > RETRY:
                        inflight.pop(key, None)
                    continue
                try:
                    dest_hash = bytes.fromhex(dest)
                except ValueError:
                    continue
                recipient_identity = RNS.Identity.recall(dest_hash)
                if recipient_identity is None:
                    RNS.Transport.request_path(dest_hash)
                    continue
                recipient = RNS.Destination(recipient_identity, RNS.Destination.OUT,
                                            RNS.Destination.SINGLE, "lxmf", "delivery")
                msg = LXMF.LXMessage(recipient, source, rec["body"], title=rec["subject"],
                                     desired_method=LXMF.LXMessage.DIRECT)
                msg.register_delivery_callback(lambda m, p=path, d=dest: finish(p, d, True))
                router.handle_outbound(msg)
                inflight[key] = (msg, time.time())
                rec["attempts"] = rec.get("attempts", 0) + 1
                save(path, rec)
                log("sending {} to {} (attempt {})".format(rec.get("id"), dest, rec["attempts"]))
        time.sleep(POLL)


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        sys.exit(0)
