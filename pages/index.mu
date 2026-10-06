#!/usr/bin/env python3
"""
rns-apps home page: categorized app menu (port of bpq-apps apps.py).

Version: 1.1
Author: Brad Brown Jr (KC1JMH)
"""

import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.realpath(__file__))), "lib"))
import rnsapps as ra  # noqa: E402

VERSION = "1.1"

LOGO = r"""
    _
   / \  _ __  _ __  ___
  / _ \| '_ \| '_ \/ __|
 / ___ \ |_) | |_) \__ \
/_/   \_\ .__/| .__/|___/
        |_|   |_|
"""


def welcome(ident):
    """Short lines: phone screens only fit about 36 columns."""
    now = ra.utc_now().strftime("%H:%M")
    call = ra.callsign_for(ident)
    if call:
        return "Welcome {}\n{}".format(ra.bold(call), ra.dim("{} UTC".format(now)))
    if ident:
        return "Welcome! {}\n{} to set your callsign".format(ra.dim("{} UTC".format(now)), ra.link("Register", "register"))
    return "Welcome, guest. {}\n{}".format(ra.dim("{} UTC".format(now)), ra.dim("Identify to post and register."))


def render():
    ident = ra.identity()
    cfg = ra.config()
    out = [
        "`c`F{}".format(ra.C_HEAD),
        ra.literal(LOGO.strip("\n")),
        "`f",
        "`!{}`!".format(ra.esc(cfg["node_name"])),
        "`a",
        "",
        welcome(ident),
        ra.divider(),
    ]

    for category, apps in ra.load_apps().get("categories", {}).items():
        out.append("")
        out.append(ra.heading(category, 2))
        for app in apps:
            pad = " " * max(1, 9 - len(app["name"]))
            if app.get("page"):
                out.append("{}{}{}".format(ra.link(app["name"], app["page"]), pad, ra.esc(app["description"])))
            else:
                out.append(ra.dim("{}{}{}".format(app["name"], pad, app["description"])))

    out += ["", "<", ra.divider()]
    footer = [ra.link("About", "about")]
    if ident:
        footer.append(ra.link("Register", "register"))
    if ra.is_sysop(ident):
        footer.append(ra.color("[sysop]", ra.C_OK))
    out.append("  ".join(footer))
    return "\n".join(out)


if __name__ == "__main__":
    ra.run(render)
