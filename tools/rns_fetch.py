#!/usr/bin/env python3
"""
Fetch NomadNet pages over Reticulum and print the raw micron.

Runs anywhere RNS is installed and a Reticulum instance is reachable, e.g.
inside the rns-apps container:

    docker exec rns-apps python3 /opt/rns-apps/tools/rns_fetch.py \
        --rnsconfig /data/reticulum <node hash> /page/index.mu

Request variables go after "?" like a query string; prefix field_ or var_:

    /page/wall.mu?var_action=post&field_message=hello

--identity <file> identifies to the node with that RNS identity file first,
so pages see a remote_identity.

Version: 1.0
Author: Brad Brown Jr (KC1JMH)
"""

import argparse
import sys
import time

import RNS

VERSION = "1.0"


def wait(predicate, timeout):
    end = time.time() + timeout
    while not predicate() and time.time() < end:
        time.sleep(0.1)
    return predicate()


def main():
    ap = argparse.ArgumentParser(description="Fetch NomadNet pages over Reticulum.")
    ap.add_argument("node", help="node destination hash (32 hex)")
    ap.add_argument("pages", nargs="*", default=["/page/index.mu"])
    ap.add_argument("--rnsconfig", help="Reticulum config directory")
    ap.add_argument("--identity", help="identity file to identify with")
    ap.add_argument("--timeout", type=float, default=30)
    args = ap.parse_args()

    RNS.Reticulum(configdir=args.rnsconfig, loglevel=RNS.LOG_ERROR)
    dest_hash = bytes.fromhex(args.node)

    if not RNS.Transport.has_path(dest_hash):
        RNS.Transport.request_path(dest_hash)
    if not wait(lambda: RNS.Transport.has_path(dest_hash), args.timeout):
        sys.exit("No path to {}".format(args.node))
    print("path: {} hops".format(RNS.Transport.hops_to(dest_hash)))

    remote = RNS.Identity.recall(dest_hash)
    dest = RNS.Destination(remote, RNS.Destination.OUT, RNS.Destination.SINGLE, "nomadnetwork", "node")
    state = {}
    started = time.time()
    link = RNS.Link(dest,
                    established_callback=lambda l: state.setdefault("up", True),
                    closed_callback=lambda l: state.setdefault("closed", l.teardown_reason))
    if not wait(lambda: state, args.timeout) or "up" not in state:
        sys.exit("Link failed: {}".format(state or "timeout"))
    print("link: up in {:.2f}s".format(time.time() - started))

    if args.identity:
        link.identify(RNS.Identity.from_file(args.identity))
        time.sleep(1)

    failed = False
    for spec in args.pages:
        path, _, query = spec.partition("?")
        data = {}
        for pair in filter(None, query.split("&")):
            key, _, value = pair.partition("=")
            data[key] = value
        result = {}
        started = time.time()
        link.request(path, data or None,
                     response_callback=lambda r: result.setdefault("ok", r.response),
                     failed_callback=lambda r: result.setdefault("fail", r.status))
        wait(lambda: result, args.timeout)
        body = result.get("ok")
        print("=== {} ({:.2f}s{})".format(spec, time.time() - started, "" if body else ", FAILED"))
        if body:
            print(body.decode("utf-8", "replace") if isinstance(body, bytes) else body)
        else:
            failed = True
    link.teardown()
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
