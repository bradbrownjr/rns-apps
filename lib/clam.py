"""
ClamAV (clamd) scanning for rns-apps uploads, stdlib only.

Only files that can carry something runnable are scanned: executables
(by magic bytes or extension) and archives that may hold them. Plain text,
images, PDFs and the like are stored without scanning. Set config.json
"clamd_scan" to "all" or "off" to change that, "clamd_host"/"clamd_port" to
point at clamd (default: the Docker host at 172.17.0.1:3310).

Version: 1.0
Author: Brad Brown Jr (KC1JMH)
"""

import os
import socket
import struct

VERSION = "1.0"

EXEC_EXT = {".exe", ".dll", ".msi", ".bat", ".cmd", ".com", ".scr", ".ps1", ".vbs", ".vbe", ".js", ".jse", ".wsf",
            ".lnk", ".jar", ".apk", ".aab", ".sh", ".run", ".bin", ".appimage", ".deb", ".rpm", ".pkg", ".dmg",
            ".pyc", ".so", ".elf", ".ko", ".hta", ".reg", ".cpl", ".sys"}
ARCHIVE_EXT = {".zip", ".7z", ".rar", ".gz", ".tgz", ".bz2", ".xz", ".tar", ".iso", ".cab", ".lz", ".zst", ".img"}
MAGIC = (b"MZ", b"\x7fELF", b"\xca\xfe\xba\xbe", b"\xfe\xed\xfa", b"\xcf\xfa\xed\xfe", b"#!")
ARCHIVE_MAGIC = (b"PK\x03\x04", b"7z\xbc\xaf", b"Rar!", b"\x1f\x8b", b"BZh", b"\xfd7zXZ")


def needs_scan(path, mode="executables"):
    """True when this file should go through clamd under the given mode."""
    if mode == "off":
        return False
    if mode == "all":
        return True
    ext = os.path.splitext(path)[1].lower()
    if ext in EXEC_EXT or ext in ARCHIVE_EXT:
        return True
    with open(path, "rb") as f:
        head = f.read(8)
    return head.startswith(MAGIC) or head.startswith(ARCHIVE_MAGIC)


def scan(path, host="172.17.0.1", port=3310, timeout=60):
    """Returns ('clean', '') | ('infected', signature) | ('error', reason)."""
    try:
        with socket.create_connection((host, port), timeout=10) as s:
            s.settimeout(timeout)
            s.sendall(b"zINSTREAM\0")
            with open(path, "rb") as f:
                while True:
                    chunk = f.read(65536)
                    if not chunk:
                        break
                    s.sendall(struct.pack("!I", len(chunk)) + chunk)
            s.sendall(struct.pack("!I", 0))
            reply = b""
            while not reply.endswith(b"\0") and len(reply) < 1024:
                data = s.recv(1024)
                if not data:
                    break
                reply += data
    except OSError as e:
        return "error", "clamd unreachable ({})".format(e.__class__.__name__)
    text = reply.decode("utf-8", "replace").strip("\0\n ")
    if text.endswith("OK"):
        return "clean", ""
    if text.endswith("FOUND"):
        return "infected", text.split(":", 1)[-1].replace("FOUND", "").strip()
    return "error", text[:100] or "no reply from clamd"
