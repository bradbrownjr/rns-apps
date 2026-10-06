#!/usr/bin/env python3
"""
Deliver queued form submissions over LXMF.

The FORMS page writes each finished form to /data/apps/forms_outbox/*.json.
This daemon (started by the container entrypoint) attaches to the node's
shared Reticulum instance, and sends each submission as an LXMF message to
every destination in config.json "forms_deliver_to" (LXMF delivery hashes,
e.g. a Sideband address). Delivery state is written back into the JSON
file; undelivered messages are retried for 48 hours.

Version: 1.0
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
