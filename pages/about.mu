#!/usr/bin/env python3
"""
About this node.

Version: 1.1
Author: Brad Brown Jr (KC1JMH)
"""

import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.realpath(__file__))), "lib"))
import rnsapps as ra  # noqa: E402

VERSION = "1.1"


def uptime():
    """
    Age of PID 1, i.e. the NomadNet node inside the container. /proc/uptime
    alone is the host kernel's uptime, since containers share the kernel.
    """
    try:
        with open("/proc/uptime") as f:
            host_up = float(f.read().split()[0])
        with open("/proc/1/stat") as f:
            # starttime is field 22; split after the "(comm)" field, which may contain spaces
            start_ticks = int(f.read().rsplit(")", 1)[1].split()[19])
        seconds = int(host_up - start_ticks / os.sysconf("SC_CLK_TCK"))
    except (OSError, ValueError, IndexError):
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
