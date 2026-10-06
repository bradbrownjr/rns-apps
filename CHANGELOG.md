# Changelog

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
