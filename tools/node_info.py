#!/usr/bin/env python3
"""
Print this node's NomadNet address (the hash visitors open) and identity.

    docker exec rns-apps python3 /opt/rns-apps/tools/node_info.py

Version: 1.0
Author: Brad Brown Jr (KC1JMH)
"""

import sys

import RNS
from RNS.vendor.configobj import ConfigObj

VERSION = "1.0"
NOMAD_DIR = sys.argv[1] if len(sys.argv) > 1 else "/data/nomadnet"

identity = RNS.Identity.from_file(NOMAD_DIR + "/storage/identity")
if identity is None:
    sys.exit("No identity in {}/storage yet - has the node started?".format(NOMAD_DIR))
node = ConfigObj(NOMAD_DIR + "/config").get("node", {})

print("Node name:     {}".format(node.get("node_name", "?")))
print("Node address:  {}".format(RNS.Destination.hash(identity, "nomadnetwork", "node").hex()))
print("Identity:      {}".format(identity.hash.hex()))
print("LXMF address:  {}".format(RNS.Destination.hash(identity, "lxmf", "delivery").hex()))
