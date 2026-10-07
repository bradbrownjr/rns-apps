#!/usr/bin/env python3
"""
Register a handle (and optional name, callsign, location) for the visitor's
Reticulum identity.

Most visitors are not hams and many want to stay anonymous, so only a handle
is required, and only the handle is shown to other visitors. Name, callsign
and location are optional, self-reported, unverified, and visible to sysops
only. Apps that need a callsign ask for one when it is missing.

Version: 1.1
Author: Brad Brown Jr (KC1JMH)
"""

import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.realpath(__file__))), "lib"))
import rnsapps as ra  # noqa: E402

VERSION = "1.1"


def not_identified():
    return "\n".join([
        ra.heading("Register"),
        "This node doesn't know who you are yet.",
        "",
        "Use your browser's `!Identify`! option for this node, then reload",
        "this page. In MeshChat it's in the page browser's menu; in",
        "NomadNet, enable identification for this node.",
        "",
        ra.dim("Identifying shares your public identity hash with this node."),
        ra.dim("Nothing else is sent."),
        ra.nav(),
    ])


def render():
    ident = ra.identity()
    if not ident:
        return not_identified()

    out = [ra.heading("Register")]
    action = ra.var("action")

    if action == "save":
        ok, note = ra.save_profile(ident, ra.field("handle"), ra.field("name"),
                                   ra.field("callsign"), ra.field("location"))
        out += [ra.color(note, ra.C_OK if ok else ra.C_WARN), ""]
    elif action == "clear":
        note = "Registration removed." if ra.clear_profile(ident) else "Nothing to remove."
        out += [ra.color(note, ra.C_OK), ""]

    rec = ra.profile(ident)
    if rec.get("handle"):
        out.append("Registered as {}.".format(ra.bold(rec["handle"])))
    else:
        out.append("Not registered yet.")
    out += [
        ra.dim("Identity: {}".format(ident)),
        ra.dim("Linked messenger: {}".format(", ".join(a[:12] for a in rec.get("lxmf", [])) or "none (send a file from Files to link one)")),
        "",
        "Handle (required, public)",
        ra.input_field("handle", 20, rec.get("handle", "")),
        "",
        "Name (optional)",
        ra.input_field("name", 30, rec.get("name", "")),
        "",
        "Callsign (optional)",
        ra.input_field("callsign", 10, rec.get("callsign", "")),
        "",
        "Location (optional)",
        ra.input_field("location", 30, rec.get("location", "")),
        "",
        ra.submit("Save", "register", "handle|name|callsign|location", action="save"),
    ]
    if rec:
        out += ["", ra.link("Remove my registration", "register", action="clear")]
    out += [
        "",
        ra.dim("Only your handle is shown to others. Name, callsign and"),
        ra.dim("location are visible to the sysop only. None is verified."),
        ra.nav(),
    ]
    return "\n".join(out)


if __name__ == "__main__":
    ra.run(render)
