# Changelog

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
