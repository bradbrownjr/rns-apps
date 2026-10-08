#!/usr/bin/env python3
"""
Nightly backup of the BBS state: a consistent snapshot of bbs.db (SQLite
backup API, safe while pages are running), profiles, config, secrets and
uploaded files, as one tar.gz in /data/backups. Keeps the newest N.

Run by tools/lxmf_sender.py once a day, or by hand:
  python3 /opt/rns-apps/tools/backup.py [--keep 7]

config.json: backup_keep (default 7), backup_dir (default /data/backups).
Backups live next to the data, so they protect against corruption and
mistakes, not disk loss; copy the directory elsewhere for that.

Version: 1.0
Author: Brad Brown Jr (KC1JMH)
"""

import argparse
import glob
import json
import os
import sqlite3
import tarfile
import tempfile
import time

APPS = os.environ.get("APPS_DIR", "/data/apps")
FILES = os.environ.get("RNS_APPS_FILES", "/data/files")
SKIP = ("cache", "lxmf_notify", "bbs.db", "bbs.db-wal", "bbs.db-shm", "errors.log")


def backup(dest, keep):
    os.makedirs(dest, exist_ok=True)
    stamp = time.strftime("%Y%m%d-%H%M%S")
    out = os.path.join(dest, "bbs-{}.tar.gz".format(stamp))
    with tempfile.TemporaryDirectory() as tmp:
        snap = os.path.join(tmp, "bbs.db")
        db = os.path.join(APPS, "bbs.db")
        if os.path.exists(db):
            src, dst = sqlite3.connect(db), sqlite3.connect(snap)
            src.backup(dst)
            src.close()
            dst.close()
        with tarfile.open(out + ".part", "w:gz") as tar:
            if os.path.exists(snap):
                tar.add(snap, arcname="apps/bbs.db")
            for name in sorted(os.listdir(APPS)):
                if name not in SKIP:
                    tar.add(os.path.join(APPS, name), arcname="apps/" + name)
            if os.path.isdir(FILES):
                tar.add(FILES, arcname="files")
    os.replace(out + ".part", out)
    os.chmod(out, 0o600)
    old = sorted(glob.glob(os.path.join(dest, "bbs-*.tar.gz")))[:-keep]
    for path in old:
        os.remove(path)
    return out, len(old)


def due(dest, hours=24):
    newest = max(glob.glob(os.path.join(dest, "bbs-*.tar.gz")), key=os.path.getmtime, default=None)
    return newest is None or time.time() - os.path.getmtime(newest) > hours * 3600


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--keep", type=int)
    args = ap.parse_args()
    try:
        with open(os.path.join(APPS, "config.json")) as f:
            cfg = json.load(f)
    except (OSError, ValueError):
        cfg = {}
    out, pruned = backup(cfg.get("backup_dir", "/data/backups"), args.keep or int(cfg.get("backup_keep", 7)))
    print("backup {} ({} KB), pruned {}".format(out, os.path.getsize(out) // 1024, pruned))


if __name__ == "__main__":
    main()
