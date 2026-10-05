#!/usr/bin/env python3
"""
Register a callsign against the visitor's Reticulum identity.

The identity hash stands in for the BPQ callsign. Claims are not verified;
they label wall posts and personalize the menu, nothing more.

Version: 1.0
Author: Brad Brown Jr (KC1JMH)
"""

import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.realpath(__file__))), "lib"))
import rnsapps as ra  # noqa: E402

VERSION = "1.0"


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
    current = ra.callsign_for(ident)

    if ra.var("action") == "save":
        call = ra.field("callsign").upper()
        if not ra.CALLSIGN_RE.match(call):
            out.append(ra.color("'{}' doesn't look like a callsign (no SSID).".format(call), ra.C_WARN))
        else:
            ra.set_callsign(ident, call)
            current = call
            out.append(ra.color("Saved. You are now {} on this node.".format(call), ra.C_OK))
        out.append("")

    if current:
        out.append("Registered as {}.".format(ra.bold(current)))
    else:
        out.append("Not registered yet.")
    out += [
        ra.dim("Identity: {}".format(ident)),
        "",
        "Callsign: {}".format(ra.input_field("callsign", 10, current or "")),
        "",
        ra.submit("Save", "register", "callsign", action="save"),
        "",
        ra.dim("Callsigns are self-reported and not verified."),
        ra.nav(),
    ]
    return "\n".join(out)



if __name__ == "__main__":
    ra.run(render)
