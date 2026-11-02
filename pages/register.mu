#!/usr/bin/env python3
"""
Register a handle (and optional name, callsign, location) for the visitor's
Reticulum identity.

Most visitors are not hams and many want to stay anonymous, so only a handle
is required, and only the handle is shown to other visitors. Name, callsign
and location are optional, self-reported, unverified, and visible to sysops
only. Apps that need a callsign ask for one when it is missing.

Several devices can share one account: the account shows a three-word link
code, and entering it on another identified device links that device.

Version: 1.3
Author: Brad Brown Jr (KC1JMH)
"""

import os
import re
import sys
import time

sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.realpath(__file__))), "lib"))
import rnsapps as ra  # noqa: E402

VERSION = "1.3"


def not_identified():
    return "\n".join([
        ra.heading("Register"),
        "This node doesn't know who you are yet. Your client has to",
        "identify to it; a page can't do that for you.",
        "",
        ra.bold("MeshChat"),
        "With this node open, tap the identify (fingerprint) icon in",
        "the bar beside the node name, confirm, and the page reloads.",
        "Do it each time you open the node.",
        "",
        ra.bold("MeshChatX"),
        "With this node open, tap the fingerprint icon (Identify when",
        "connecting) and confirm; it turns highlighted and stays on for",
        "this node. Not available in private browsing.",
        "",
        ra.bold("NomadNet"),
        "Network > Known Nodes > this node > Node Info: tick",
        "Identify when connecting. Then reload this page.",
        "",
        ra.dim("Identifying shares your public identity hash with this node."),
        ra.dim("Nothing else is sent."),
        ra.nav(),
    ])


def minutes_left(expires):
    return max(1, int((expires - time.time() + 59) // 60))


def devices_section(ident, device, rec):
    """Link-a-device controls for a registered account."""
    out = ["", ra.divider(), ra.heading("Devices", 2)]
    linked = ra.linked_devices(ident)
    rows = [(ident, "main")] + [(d, "linked") for d in linked]
    for d, kind in rows:
        here = " (this device)" if d == device else ""
        line = "{} {}{}".format(d[:12], ra.dim(kind), ra.dim(here))
        if kind == "linked":
            line += "  " + ra.link("Unlink", "register", action="unlink", dev=d)
        out.append(line)
    code, expires = ra.pending_link_code(ident)
    out.append("")
    if code:
        out += [
            "On your other device, identify, open Register, and enter:",
            "",
            "  " + ra.bold(code),
            "",
            ra.dim("Valid {} more minute(s), once.".format(minutes_left(expires))),
            ra.link("New code", "register", action="code") + "  " + ra.link("Cancel", "register", action="nocode"),
        ]
    else:
        out += [
            ra.link("Link another device", "register", action="code"),
            ra.dim("Gives a three-word code to enter on the other device."),
        ]
    return out


def link_form():
    return [
        "",
        ra.divider(),
        ra.heading("Already registered on another device?", 2),
        "On that device open Register > Link another device, then",
        "enter the three words here:",
        ra.input_field("code", 30),
        ra.submit("Link this device", "register", "code", action="link"),
    ]


def render():
    device = ra.device_identity()
    if not device:
        return not_identified()
    ident = ra.identity()

    out = [ra.heading("Register")]
    action = ra.var("action")

    if action == "save":
        ok, note = ra.save_profile(ident, ra.field("handle"), ra.field("name"),
                                   ra.field("callsign"), ra.field("location"))
        out += [ra.color(note, ra.C_OK if ok else ra.C_WARN), ""]
    elif action == "clear":
        if ident != device:
            note = "Remove the registration from your main device, or unlink this one."
        else:
            for d in ra.linked_devices(ident):
                ra.unlink_device(ident, d)
            ra.cancel_link_code(ident)
            note = "Registration removed." if ra.clear_profile(ident) else "Nothing to remove."
        out += [ra.color(note, ra.C_OK), ""]
    elif action == "link":
        ok, note = ra.link_device(device, ra.arg("code"))
        ident = ra.identity()
        out += [ra.color(note, ra.C_OK if ok else ra.C_WARN), ""]
    elif action == "unlink":
        dev = ra.var("dev").lower()
        if not re.fullmatch(r"[0-9a-f]{32}", dev):
            dev = ""
        if dev and ra.var("ok") != "1":
            self_note = " This device will go back to being a guest." if dev == device else ""
            return "\n".join([
                ra.heading("Unlink device"),
                "Unlink {} from {}?{}".format(dev[:12], ra.esc(ra.handle_for(ident) or "this account"), self_note),
                "",
                ra.link("Yes, unlink", "register", action="unlink", dev=dev, ok="1") + "  " + ra.link("No", "register"),
                ra.nav(),
            ])
        note = "Unlinked." if ra.unlink_device(ident, dev) else "That device isn't linked here."
        ident = ra.identity()
        out += [ra.color(note, ra.C_OK), ""]

    rec = ra.profile(ident)
    if action == "code" and rec.get("handle"):
        ra.new_link_code(ident)
    elif action == "nocode":
        ra.cancel_link_code(ident)

    if rec.get("handle"):
        out.append("Registered as {}.".format(ra.bold(ra.esc(rec["handle"]))))
    else:
        out.append("Not registered yet.")
    out += [
        ra.dim("Identity: {}".format(ident)),
    ]
    if device != ident:
        out.append(ra.dim("This device: {} (linked)".format(device)))
    out += [
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
    if rec and ident == device:
        out += ["", ra.link("Remove my registration", "register", action="clear")]
    out += [
        "",
        ra.dim("Only your handle is shown to others. Name, callsign and"),
        ra.dim("location are visible to the sysop only. None is verified."),
    ]
    if rec.get("handle"):
        out += devices_section(ident, device, rec)
    elif ident == device:
        out += link_form()
    out.append(ra.nav())
    return "\n".join(out)


if __name__ == "__main__":
    ra.run(render)
