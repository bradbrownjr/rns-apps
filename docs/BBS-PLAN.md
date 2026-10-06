# Plan: message boards, mail, files

Status: planned, not built. Decisions made 2026-10-06:

- Guests can read boards and download files; a registered handle is needed to
  post, send mail, or upload.
- Uploads arrive over LXMF (a visitor sends the file to the node as an LXMF
  attachment) into a pending queue that the sysop approves.

## Storage

- `/data/apps/bbs.db`, SQLite (stdlib `sqlite3`, WAL mode). Every page request
  is its own process, so file-per-feature JSON with `flock` stops scaling once
  there are threads, read marks and search.
- Files live on disk under `/data/files/<area path>/`; the database holds the
  descriptions. Pending uploads under `/data/files/_pending/`.
- A schema version table; migrations run from `lib/bbsdb.py` on first use.

Tables (sketch): `boards`, `threads`, `posts` (parent_id for reply tree),
`reads` (identity, thread, last post seen), `mail` (conversation id, from, to,
parent_id, per-side deleted flags), `blocks`, `file_areas` (parent_id tree),
`files`, `uploads_pending`, `mutes`.

## Message boards (MSG)

- Boards are created by the sysop: name, description, order, flags
  (read-only, locked, hidden). Suggested seeds: General, Ham Radio,
  EmComm/ARES, Reticulum & Packet, Swap & Shop, Net Announcements (read-only),
  Test.
- Board page: threads by last activity with reply counts and a NEW marker.
- Thread page: posts in order, 8 per page, each showing "in reply to <handle>".
  Indent at most two levels; a tree any deeper is unreadable on a phone.
- Compose is a **draft** (like FORMS), because micron text boxes are
  single-line: add a paragraph at a time, preview, then Post.
- **Quote**: Reply-with-quote seeds the draft with
  `> <handle> wrote:` and `> ` lines from the parent, trimmed to a sane length
  and nested quotes collapsed to one level. Plain Reply starts empty.
- Rules: handle required; max length; one post per N seconds per identity;
  edit/delete own for 15 minutes; sysop delete, lock, move, mute.
- Unread counts per board via `reads`.

## Mail

- Addressed by handle. Inbox, Sent, Compose, conversation view (threaded by
  `conversation_id`), unread counts, delete your own copy.
- Reply and Reply-with-quote as on boards; same draft compose.
- Limits: mailbox size cap, per-sender rate limit, per-user block list.
- Welcome line on the home page: "2 unread mail".
- Only the sender and recipient can read a message. No sysop mail browsing
  built in.

## Files (FILES)

- Category tree with sub-areas (Software > Reticulum > Android ...). Each file:
  name, description, size, added by, date, area.
- Downloads use NomadNet's own file serving (`files_path`, subfolders
  included), so links work in NomadNet, MeshChat and MeshChatX. NomadNet
  serves the bytes, not a page, so downloads cannot be counted.
- Needs a Dockerfile/entrypoint change: `files_path = /data/files/public` in
  the NomadNet config, and approved files moved or linked under it.
- Sysop can also drop files into the share and describe them on the admin page.

### Upload over LXMF

- `tools/lxmf_sender.py` grows into `tools/lxmf_daemon.py`: it already runs in
  the container and attaches to the node's shared Reticulum instance. It adds
  an LXMF **receiver** (its own LXMF address, announced as "<node> files").
- A visitor attaches a file in MeshChat/Sideband and sends it to that address;
  the message text is the description and optionally `area: Software/Reticulum`.
- The daemon: identifies the sender (recall the source identity, match it to a
  registered handle; unregistered senders get a polite "register first" reply),
  enforces size/quota/rate limits and a pending-queue cap, stores the file in
  `_pending/`, and replies "received, awaiting approval".
- The Files page shows the node's LXMF address and the instructions.
- Optional hardening: scan pending files with the ClamAV container already on
  the Unraid host before they can be approved.

## Admin page (sysop only)

Boards and file areas (create, rename, reorder, flags); pending uploads
(approve to an area, reject with a reason that goes back by LXMF); moderation
queue; mute/ban a handle; counts.

## Build order (each step: test locally, deploy, commit)

1. `lib/bbsdb.py` + boards/threads/posts with draft compose, reply, quote.
2. Mail on the same compose and quote code.
3. Files: browse, download, sysop add, admin page; image update for `files_path`.
4. LXMF daemon: receiver, pending queue, acknowledgements.
5. Menu integration (unread counts), search, and optional LXMF new-mail notices.

## Open defaults (change on request)

- Post max 1,500 characters; mail max 3,000; 30 s between posts.
- Upload cap 2 MB per file, 10 MB per handle per day; pending queue 50.
- Boards and areas hidden from guests only if flagged.
