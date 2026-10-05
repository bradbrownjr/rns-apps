# Changelog

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
