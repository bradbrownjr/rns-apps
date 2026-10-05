#!/usr/bin/env python3
"""
About this node.

Version: 1.0
Author: Brad Brown Jr (KC1JMH)
"""

import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.realpath(__file__))), "lib"))
import rnsapps as ra  # noqa: E402

VERSION = "1.0"


def uptime():
    try:
        with open("/proc/uptime") as f:
            seconds = int(float(f.read().split()[0]))
    except (OSError, ValueError):
        return "unknown"
    days, rem = divmod(seconds, 86400)
    return "{}d {}h {}m".format(days, rem // 3600, rem % 3600 // 60)


def render():
    cfg = ra.config()
    ident = ra.identity()
    out = [
        ra.heading("About {}".format(cfg["node_name"])),
        "rns-apps is a BBS-style collection of amateur radio and emergency",
        "communications apps served over Reticulum. It is a sister project to",
        "bpq-apps, which serves the same apps to packet radio users over BPQ.",
        "",
        ra.heading("Features", 2),
        "* Offline-first: data is cached on the node and served even when",
        "  the internet is down.",
        "* Identity instead of login: identify to this node and register your",
        "  callsign once.",
        "* Small pages for slow links: LoRa, packet and other low-bandwidth",
        "  Reticulum interfaces.",
        "",
        ra.heading("Node", 2),
        "{} {}".format(ra.dim("Version:"), ra.VERSION),
        "{} {}".format(ra.dim("Uptime:"), uptime()),
        "{} {}".format(ra.dim("Registered users:"), len(ra.users())),
        "{} {}".format(ra.dim("You:"), ra.display_name(ident)),
        "",
        ra.heading("Source", 2),
        "https://github.com/bradbrownjr/rns-apps",
        "https://github.com/bradbrownjr/bpq-apps",
        "",
        ra.heading("Operator", 2),
        "Brad Brown Jr, KC1JMH",
        "Wireless Society of Southern Maine - Emergency Communications Team",
        "<",
    ]
    return "\n".join(out + [ra.nav()])


if __name__ == "__main__":
    ra.run(render)
