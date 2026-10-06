#!/usr/bin/env python3
"""
Re-announce the node now (instead of waiting for the 6 hour interval), e.g.
when a client shows "Unknown Node" because it missed the last announce.

Attaches to the running node's shared Reticulum instance and announces the
nomadnetwork.node destination with the node's identity and name.

Usage (in the container):
  python3 /opt/rns-apps/tools/announce.py [--rnsconfig /data/reticulum] [--nomadnet /data/nomadnet]

Version: 1.0
Author: Brad Brown Jr (KC1JMH)
"""

import argparse
import os
import re
import time

import RNS


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--rnsconfig", default="/data/reticulum")
    ap.add_argument("--nomadnet", default="/data/nomadnet")
    args = ap.parse_args()

    name = os.environ.get("NODE_NAME", "")
    if not name:
        with open(os.path.join(args.nomadnet, "config")) as f:
            m = re.search(r"^\s*node_name\s*=\s*(.+)$", f.read(), re.M)
        name = m.group(1).strip() if m else "rns-apps"

    RNS.Reticulum(configdir=args.rnsconfig, loglevel=RNS.LOG_ERROR)
    identity = RNS.Identity.from_file(os.path.join(args.nomadnet, "storage", "identity"))
    dest = RNS.Destination(identity, RNS.Destination.IN, RNS.Destination.SINGLE, "nomadnetwork", "node")
    dest.announce(app_data=name.encode("utf-8"))
    print("announced {} as {}".format(RNS.prettyhexrep(dest.hash), name))
    time.sleep(3)


if __name__ == "__main__":
    main()
