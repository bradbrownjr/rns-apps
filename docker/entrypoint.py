#!/usr/bin/env python3
"""
Container entrypoint: write NomadNet and Reticulum configs, then run the
NomadNet node in the foreground.

Settings come from environment variables (see Dockerfile). The NomadNet
config is generated from NomadNet's own default on first run; the [node]
keys this project depends on are re-applied on every start, so the env vars
stay authoritative. The Reticulum config is written once and then left alone,
so hand edits survive restarts.
"""

import importlib
import os
import subprocess
import sys

from RNS.vendor.configobj import ConfigObj

# The nomadnet package re-exports the NomadNetworkApp class under the module's
# own name, so "import nomadnet.NomadNetworkApp" yields the class. Fetch the
# module itself, which holds the default config (a list of lines once the
# module has been imported).
nna = importlib.import_module("nomadnet.NomadNetworkApp")

NOMAD_DIR = "/data/nomadnet"
RNS_DIR = "/data/reticulum"
APPS_DATA = "/data/apps"
PAGES = "/opt/rns-apps/pages"

RNS_CONFIG = """# Reticulum config for the rns-apps container (written by entrypoint).
# Edit freely; it is only generated when missing.

[reticulum]
  enable_transport = No
  share_instance = Yes
  instance_name = rns-apps

[logging]
  loglevel = 4

[interfaces]
  [[Upstream Gateway]]
    type = TCPClientInterface
    enabled = Yes
    target_host = {host}
    target_port = {port}
"""


def env(name, default=""):
    return os.environ.get(name, default).strip()


def write_rns_config():
    path = os.path.join(RNS_DIR, "config")
    if os.path.exists(path):
        return
    host = env("GATEWAY_HOST")
    if not host:
        sys.exit("GATEWAY_HOST is not set and {} does not exist.".format(path))
    os.makedirs(RNS_DIR, exist_ok=True)
    with open(path, "w") as f:
        f.write(RNS_CONFIG.format(host=host, port=env("GATEWAY_PORT", "4242")))
    print("Wrote {} (gateway {}:{})".format(path, host, env("GATEWAY_PORT", "4242")))


def write_nomad_config():
    path = os.path.join(NOMAD_DIR, "config")
    os.makedirs(NOMAD_DIR, exist_ok=True)
    if os.path.exists(path):
        cfg = ConfigObj(path)
    else:
        default = nna.__default_nomadnet_config__
        if isinstance(default, str):
            default = default.splitlines()
        cfg = ConfigObj(default)
        cfg.filename = path
    node = cfg.setdefault("node", {})
    node["enable_node"] = "yes"
    node["node_name"] = env("NODE_NAME", "rns-apps")
    node["announce_interval"] = env("ANNOUNCE_INTERVAL", "360")
    node["announce_at_start"] = "yes"
    node["pages_path"] = PAGES
    node["page_refresh_interval"] = env("PAGE_REFRESH_INTERVAL", "5")
    node["disable_propagation"] = "yes"
    cfg.write()


def start_form_sender():
    """LXMF delivery of submitted forms. Waits for nomadnet's shared Reticulum
    instance, idles when no destinations are configured, and is restarted if
    it ever exits. Lives in the app mount, so deploys update it."""
    script = "/opt/rns-apps/tools/lxmf_sender.py"
    if not os.path.exists(script):
        return
    subprocess.Popen(["sh", "-c", "while true; do python3 '{}'; sleep 15; done".format(script)])


def main():
    os.makedirs(APPS_DATA, exist_ok=True)
    write_rns_config()
    write_nomad_config()
    start_form_sender()
    os.execvp("nomadnet", ["nomadnet", "--daemon", "--console",
                           "--config", NOMAD_DIR, "--rnsconfig", RNS_DIR])


if __name__ == "__main__":
    main()
