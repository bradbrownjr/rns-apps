#!/usr/bin/env python3
"""
Dictionary (port of bpq-apps dict.py), speaking the DICT protocol (RFC 2229)
to dict.org directly so the container needs no dict client.

Version: 1.0
Author: Brad Brown Jr (KC1JMH)
"""

import os
import re
import socket
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.realpath(__file__))), "lib"))
import rnsapps as ra  # noqa: E402

VERSION = "1.0"
HOST, PORT = "dict.org", 2628
TTL = 7 * 86400
MAX_DEFS = 3
MAX_CHARS = 1200
WORD_RE = re.compile(r"^[A-Za-z][A-Za-z '.-]{0,39}$")


def _command(sock_file, line):
    sock_file.write(line + "\r\n")
    sock_file.flush()


def _read_status(sock_file):
    return sock_file.readline().rstrip("\r\n")


def _read_text(sock_file):
    lines = []
    while True:
        line = sock_file.readline()
        if not line:
            break
        line = line.rstrip("\r\n")
        if line == ".":
            break
        lines.append(line[1:] if line.startswith("..") else line)
    return "\n".join(lines)


def lookup(word):
    """Return {'defs': [(database, text)], 'similar': [words]}."""
    sock = socket.create_connection((HOST, PORT), timeout=8)
    sock.settimeout(10)
    f = sock.makefile("rw", encoding="utf-8", errors="replace", newline="")
    try:
        _read_status(f)
        _command(f, "CLIENT rns-apps")
        _read_status(f)
        _command(f, 'DEFINE * "{}"'.format(word))
        status = _read_status(f)
        defs, similar = [], []
        if status.startswith("150"):
            count = int(status.split()[1])
            for _ in range(count):
                head = _read_status(f)  # 151 "word" db "description"
                m = re.match(r'151 "[^"]*" (\S+) "(.*)"', head)
                defs.append((m.group(1) if m else "?", m.group(2) if m else "dictionary", _read_text(f)))
            _read_status(f)  # 250 ok
        else:
            _command(f, 'MATCH * lev "{}"'.format(word))
            if _read_status(f).startswith("152"):
                for line in _read_text(f).split("\n"):
                    m = re.match(r'\S+ "(.*)"', line)
                    if m and m.group(1).lower() not in [s.lower() for s in similar]:
                        similar.append(m.group(1))
        _command(f, "QUIT")
        # One entry per dictionary, WordNet and GCIDE first.
        order = {"wn": 0, "gcide": 1}
        best = {}
        for key, name, text in defs:
            best.setdefault(key, (name, text))
        defs = [best[k] for k in sorted(best, key=lambda k: order.get(k, 2))]
        return {"defs": defs, "similar": similar[:8]}
    finally:
        sock.close()


def reflow(text):
    """Dictionary text is hard-wrapped at ~70 columns; rejoin it into lines
    the client can wrap itself. Numbered senses start new lines."""
    out = []
    for para in re.split(r"\n\s*\n", text):
        cur = ""
        for line in para.split("\n"):
            stripped = line.strip()
            if cur and re.match(r"^(\d+\.|[a-z]\.|--)\s", stripped):
                out.append(cur)
                cur = ""
            cur = (cur + " " + stripped).strip()
        if cur:
            out.append(cur)
        out.append("")
    return out


def render():
    word = " ".join(ra.arg("w").split())
    out = [
        ra.heading("Dictionary"),
        "Word: {}".format(ra.input_field("w", 24, word)),
        ra.submit("Define", "dict", "w"),
        "",
    ]
    if not word:
        return "\n".join(out + [ra.dim("Definitions from dict.org (WordNet, Webster's 1913, GCIDE, ...)."), ra.nav()])
    if not WORD_RE.match(word):
        return "\n".join(out + [ra.color("Enter a single word or short phrase (letters only).", ra.C_WARN), ra.nav()])

    result, ts, stale = ra.cached("dict_" + word.lower(), TTL, lambda: lookup(word))
    if result is None:
        return "\n".join(out + [ra.color("The dictionary server is unreachable and this word isn't cached.", ra.C_WARN), ra.nav()])
    if not result["defs"]:
        out.append("No definition for {}.".format(ra.bold(word)))
        if result["similar"]:
            out += ["", "Did you mean:"]
            out += [ra.link(w, "dict", w=w) for w in result["similar"]]
        return "\n".join(out + [ra.nav()])

    for db, text in result["defs"][:MAX_DEFS]:
        out.append(ra.heading(db, 2))
        shown = text if len(text) <= MAX_CHARS else text[:MAX_CHARS].rsplit(" ", 1)[0] + " ..."
        out += [ra.esc(l) if l else "" for l in reflow(shown)]
    extra = len(result["defs"]) - MAX_DEFS
    if extra > 0:
        out.append(ra.dim("{} more source{} not shown.".format(extra, "" if extra == 1 else "s")))
    out += [ra.freshness(ts, stale), ra.nav()]
    return "\n".join(out)


if __name__ == "__main__":
    ra.run(render)
