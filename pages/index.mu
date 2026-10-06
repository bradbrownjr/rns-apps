#!/usr/bin/env python3
"""
rns-apps home page: categorized app menu (port of bpq-apps apps.py).

Version: 1.4
Author: Brad Brown Jr (KC1JMH)
"""

import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.realpath(__file__))), "lib"))
import rnsapps as ra  # noqa: E402

VERSION = "1.4"

# Left-aligned and pre-indented: centering (`c) would center every line of the
# block on its own and shear the art.
LOGO = r"""
     _
    / \  _ __  _ __  ___
   / _ \| '_ \| '_ \/ __|
  / ___ \ |_) | |_) \__ \
 /_/   \_\ .__/| .__/|__/
         |_|   |_|
"""


def welcome(ident):
    """Short lines: phone screens only fit about 36 columns."""
    now = ra.dim("{} UTC".format(ra.utc_now().strftime("%H:%M")))
    handle = ra.handle_for(ident)
    if handle:
        return "Welcome {}  {}".format(ra.link(handle, "register"), now)
    if ident:
        return "Welcome! {}\n{} to pick a handle".format(now, ra.link("Register", "register"))
    return "Welcome, guest. {}\n{}".format(now, ra.dim("Identify to post and register."))


def render():
    ident = ra.identity()
    cfg = ra.config()
    out = [
        "`a`F{}".format(ra.C_HEAD),
        ra.literal(LOGO.strip("\n")),
        "`f",
        "`c`!{}`!".format(ra.esc(cfg["node_name"])),
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

    if ra.is_sysop(ident):
        out += ["", "<", ra.divider(), ra.color("[sysop]", ra.C_OK)]
    return "\n".join(out)


if __name__ == "__main__":
    ra.run(render)
