# Changelog

## 2.1 - 2026-10-06

Files area and LXMF uploads (steps 3 and 4 of docs/BBS-PLAN.md).

- **files** 1.0: category tree with sub-areas, downloads served by NomadNet
  (`/file/a<area>/<name>`), size, uploader, SHA-256 prefix, LXMF upload address.
- **sysop** 1.1: file areas, import from the `incoming` folder, pending-upload
  queue (approve into an area, reject). Files flagged by the scan can't be approved.
- **lib/clam.py**: clamd INSTREAM scan, limited to executables and archives
  (`clamd_scan` = executables | all | off).
- **lxmf_sender** 1.1: also receives uploads over LXMF from verified, registered,
  unmuted senders; per-file, daily and queue limits (`upload_max_bytes`,
  `upload_daily_bytes`, `upload_pending_max`).
- **rns_fetch**: bare page names work (`files` = `/page/files.mu`); failures print the reason.
- **search** 1.0: searches thread titles, posts, and files; hidden boards/areas only for sysops.
- Approve/reject sends the uploader an LXMF notice (optional reject reason) via `lxmf_notify/`.
- **files/index** : "N new files" on the welcome line and NEW markers, counted from your last visit to the Files top page (DB migration 3, `prefs` table).
- **mail**: opt-in LXMF notice on new mail (sender and subject only, never the body).
- **Upload address hidden from guests**: the Files page shows the messenger name, an `lxmf@` link and address only to a registered user, with instructions to put their handle and description in the message.
- **Messenger linking**: a per-user link code (HMAC of a server secret, `secret.key`) in the first message ties that LXMF address to the profile (`lxmf` in users.json, last three kept). Unknown addresses without a valid code get a polite refusal. The Register page and sysop user list show the linked address.
- Image: `files_path` and `file_refresh_interval` set by the entrypoint.

## 2.0 - 2026-10-06

Message boards and mail (step 1 and 2 of docs/BBS-PLAN.md).

- **msg** 1.0: boards, threads, replies and reply-with-quote, compose drafts,
  unread markers, delete own post for 15 minutes, sysop lock/pin/delete.
- **mail** 1.0: private mail by handle, conversation threading, reply and
  quote, inbox/sent, block sender, mailbox cap.
- **sysop** 1.0: boards (create, rename, order, read-only/locked/hidden,
  delete if empty), users, mutes. Sysops are recognized only by the verified
  identity hash in `config.json` `sysops`.
- **lib/bbs.py**: SQLite (`/data/apps/bbs.db`, migrations) for all of it.
- **Handles hardened**: lookalikes collide (Brad/Bradl/Br4d), reserved words
  (sysop, admin, ...), `sysop_handles` in `config.json` reserves a handle for
  one identity, and sysops carry a `[sysop]` badge shown from their identity,
  not their handle.
- **index** 1.5: new-mail and new-thread counts in the welcome block.

## 1.9 - 2026-10-06

- **www** 1.0: text web browser (port of bpq-apps www.py): URL or search words
  (FrogFind, falling back to DuckDuckGo lite), links followable, gopher:// links
  open GOPHER. Public hosts only, redirects checked, 500 KB cap.
- **lib** `htmltext.to_micron()`: HTML to micron with inline links.

## 1.8 - 2026-10-06

- **qrz** 1.1: uses the QRZ.com XML API (all countries) when `qrz_user` and
  `qrz_password` are set in `config.json`; falls back to HamDB. Session key
  cached, password never logged.
- **news**: Maine Packet Network feed restored at `/feed` (the site moved CMS).
- **tools/announce.py**: re-announce the node now, for clients that show
  "Unknown Node" because they missed the last announce (every 6 h).
- FORMS LXMF delivery stays dormant until `forms_deliver_to` is configured.

## 1.7 - 2026-10-06

Ports from bpq-apps, batch 4. Every bpq-apps app is now ported.

- **gopher** 1.0: menus as links, paged text files, search items, bookmarks.
  Refuses non-public addresses so the node can't probe its own network.
- **forms** 1.0: 12 form templates (`data/forms/`). A wizard fills one field
  per page (draft kept per identity), reviews, then formats the result
  (standard, PACKET CHECK-IN, NTS radiogram with the NTS text rules, strip
  responses), shows it to copy, saves it in `forms_outbox/`, and queues it for
  LXMF delivery. Sysops browse submissions at `forms.mu?a=outbox`.
- **tools/lxmf_sender.py**: container daemon that delivers queued forms over
  LXMF to the addresses in `config.json` `forms_deliver_to`; retries for 48 h.
  Started by `docker/entrypoint.py` (new image).
- **lib/formsfmt.py**: form validation and output formatting.

## 1.6 - 2026-10-06

Ports from bpq-apps, batch 3 (tools).

- **antenna** 1.1: calculators (dipole, EFHW, OCF, folded, Moxon, vertical,
  NVIS, loops, random wire), US band plan, formulas, popular antennas, and a
  shared antenna database (identified visitors add entries, authors/sysops
  delete). The Moxon calculator uses the published MoxGen equations (Cebik);
  the bpq-apps version used wrong coefficients.
- **hamtest** 1.0: practice and full-length exams from the NCVEC pools
  (`data/question_pools/`), stateless (seed and answers travel in link
  variables), best scores per identified visitor.
- **predict** 1.0: HF propagation estimate (`lib/geo.py`, `lib/ionosphere.py`,
  `data/regions.json` from bpq-apps), hamqsl.com solar data, time-shift links.

## 1.5 - 2026-10-06

Ports from bpq-apps, batch 2 (feeds).

- **calendar** 1.0: events from a public iCal feed with recurrence rules
  (`lib/ical.py`), detail view, paging. Needs `ical_url` in `config.json`.
- **news** 1.0: RSS and Atom feeds from `feeds.json`, 30 min cache, summaries,
  optional readable full article. Dropped three bpq-apps feeds that no longer
  work (Maine Packet Radio, Space.com, NWS alerts atom).
- **wiki** 1.0: Wikipedia, Simple English, Wiktionary, Wikiquote, Wikinews and
  Wikivoyage: search, read in pages, related articles, random.
- **lib** 1.5: `htmltext.py` (HTML to text), `paragraphs()`, `cache_peek()`.

## 1.4 - 2026-10-06

Ports from bpq-apps, batch 1 (reference lookups).

- **qrz** 1.0: US callsign lookup via HamDB (no QRZ.com login needed).
- **dict** 1.0: dictionary over the DICT protocol (dict.org), one entry per
  source, "did you mean" suggestions.
- **wx** 1.0: NWS weather for any US place (ZIP, City ST, grid, callsign,
  lat/lon): conditions, 7-day, hourly, alerts, AFD, HWO. Profile location
  shortcut for registered users.
- **repeater** 1.0: RepeaterBook by state or near a location, band/mode/radius
  filters. RepeaterBook now requires an app token (`repeaterbook_token` in
  `config.json`); without one it serves whatever is cached.
- **lib** 1.3: `arg()`, `http_json()`, `resolve_location()`, `grid_to_latlon()`,
  `distance_mi()`, `hamdb()`, `nws_point()`.

## 1.3 - 2026-10-06

Most visitors won't be hams, and many want to stay anonymous.

- **register** 1.1: pick a **handle** (required, the only public field).
  Name, callsign and location are optional and visible to sysops only.
  Handles are unique (case-insensitive). "Remove my registration" added.
- **lib** 1.2: `profile()`, `handle_for()`, `save_profile()`, `clear_profile()`;
  `callsign_for()` now returns the optional callsign, or None (apps that need
  one should ask for it).
- **wall** 1.1: posts are labeled with the handle.
- **index** 1.4: one underscore shorter on the bottom of the logo's S.
- **index** 1.3: "Apps" logo restored and left-aligned (centering sheared it:
  clients center each line of a literal block separately);
  Register appears once (the welcome line, which links to your profile when
  registered); About moved into Main.

## 1.2 - 2026-10-06

- **index** 1.1: mobile-friendly. Smaller "Apps" logo, shorter welcome lines,
  menu rows fit about 36 columns, no "(soon)" suffix; greyed-out entries are
  apps not ported yet.

## 1.1 - 2026-10-05

- **about** 1.1: uptime now shows the node's own uptime; it was showing the
  host kernel's, since containers share the kernel.
- Image published to `ghcr.io/bradbrownjr/rns-apps` (amd64 + arm64) by a
  GitHub Actions workflow; Unraid template now uses it.
- **tools/rns_fetch.py**: fetch pages over Reticulum, optionally identified.
- **tools/node_info.py**: print the node's address and identity.

## 1.0 - 2026-10-05

Initial release.

- **index**: categorized BBS menu (port of bpq-apps `apps.py`), welcome line
  with registered callsign and UTC time, "soon" entries for apps not yet ported.
- **register**: map the visitor's Reticulum identity to a callsign.
- **wall**: one-line community messages; post, paginate, delete own posts,
  sysop delete, 30 s per-identity rate limit, 500-post cap.
- **hamqsl**: solar data and band conditions from hamqsl.com (1 h cache).
- **space**: NOAA SWPC text products (1 h cache).
- **wx-me**: NWS Gray/Caribou Maine and New Hampshire products (30 min cache).
- **about**: node info and links.
- Docker image (nomadnet 1.4.4, rns 1.5.7, lxmf 1.2.0), entrypoint that
  writes NomadNet/Reticulum configs, Unraid template, deploy script.
