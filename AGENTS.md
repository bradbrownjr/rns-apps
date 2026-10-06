# Agent Instructions — rns-apps

Shared memory for any AI assistant working on rns-apps. Sister project of
[bpq-apps](https://github.com/bradbrownjr/bpq-apps): the same apps, served as
NomadNet pages over Reticulum instead of a BPQ terminal session.

---

## Always / Never Memory Protocol

- If the user says **"always"**, **"never"**, **"remember"**, or **"don't"**,
  add it here as a permanent rule.
- Remove or update rules that turn out to be wrong.

---

## How pages run (read this first)

NomadNet runs an **executable** file in `pages/` once per request and serves
its stdout as micron. This is request/response, not a terminal session:

- **No stdin, no `input()`.** Every interactive loop in a bpq-apps app becomes
  a page plus links/forms that call the page again with variables.
- **Environment is only `PATH`** plus `remote_identity` (if the visitor
  identified), `link_id`, `field_<name>` (submitted fields) and `var_<name>`
  (link variables). No `HOME`, no custom env. Paths are resolved from the
  script's own location (`lib/rnsapps.py` handles this).
- **stderr is discarded.** Always go through `ra.run(render)`, which logs
  exceptions to `/data/apps/errors.log` and shows a short error page.
- New page files are found on the next rescan (`PAGE_REFRESH_INTERVAL`,
  5 min). Edits to existing pages are live on the next request.
- MeshChat and NomadNet both pass `field_*` and `var_*`; test with both
  clients when changing forms.

## Architecture

```
apps.json           Menu registry (categories -> name/description/page; page null = "soon")
lib/rnsapps.py      Shared helpers: request vars, identity, micron, cache, locking, run()
pages/*.mu          Executable Python pages (index.mu = home menu)
tools/              rns_fetch.py (fetch pages over Reticulum), node_info.py (node address), lxmf_sender.py (delivers submitted forms over LXMF; started by the entrypoint)
data/               Static assets shipped with the code: forms/*.frm, question_pools/, regions.json (runtime data is /data/apps, not here)
feeds.json          RSS/Atom feeds for NEWS
docker/             Dockerfile, entrypoint.py (writes configs), Unraid template
.github/workflows/  docker.yml publishes ghcr.io/bradbrownjr/rns-apps (amd64+arm64) on docker/ changes
deploy.sh           tar-over-ssh sync to the Docker host (--build: local test image only)
/data (container)   nomadnet/, reticulum/, apps/ (config.json, users.json, wall.json, cache/)
```

Identity replaces the BPQ callsign: `remote_identity` is the key,
`users.json` maps it to a self-reported profile (register page): `handle`
(required, public) plus optional `name`, `callsign`, `location` (sysop-visible
only). Most visitors are not hams, so never require a callsign to use an app;
use `ra.callsign_for(ident)` and ask for one when an app needs it.
Sysops are identity hashes listed in `/data/apps/config.json`.

---

## Sysop and identity security

- A sysop is an identity hash in `config.json` `"sysops"`. RNS verifies the
  identity by signature when a client identifies, and pages only see it as the
  `remote_identity` environment variable; client-sent values arrive as
  `var_*`/`field_*` and can never set it. So a sysop can't be impersonated by
  choosing a handle or crafting a link.
- **NEVER** decide authority from a handle. Use `ra.is_sysop(ident)`.
- Show `ra.sysop_badge(ident)` (derived from identity) next to names.
- Reserve a sysop's handle with `config.json` `"sysop_handles": {"<id>": "Name"}`.
- Destructive sysop links ask for confirmation (`ok=1`).
- Keep the sysop's private identity file safe; whoever holds it is the sysop.

## ALWAYS / NEVER Rules

### Output
- **ALWAYS** escape untrusted text with `ra.esc()` (backtick and backslash are
  micron control characters). Wrap fetched preformatted text in `ra.literal()`.
- **ALWAYS** start pages with `#!c=0` (done by `ra.run`) so clients don't cache
  dynamic output.
- **ALWAYS** keep pages small; Reticulum also runs over LoRa and packet. No
  images, no giant tables, paginate long lists.
- **NEVER** rely on newer micron features (tables, collapsible sections,
  partials) without checking MeshChat renders them.
- **ALWAYS** end pages with `ra.nav()` so there's a way back to the menu.

### Code
- **ALWAYS** stdlib only in `pages/` and `lib/` (the image ships nomadnet/rns,
  but pages must not need them).
- **ALWAYS** fetch through `ra.cached()` with a TTL and offline fallback;
  network timeouts must never break a page.
- **ALWAYS** use `ra.locked(name)` around read-modify-write of data files.
- **ALWAYS** require `ra.identity()` for anything that writes data, and
  rate-limit per identity.
- **ALWAYS** keep `VERSION` and the docstring `Version:` in sync per file.
- Inside a container, `/proc/uptime` is the host's uptime. Use PID 1's start
  time for node uptime (see `about.mu`).
- **NEVER** center (`` `c ``) a literal block or ASCII art: clients center every line on its own and shear the art. Left-align and indent it by hand. `` `= `` is micron's `<pre>`.
- **NEVER** commit real IPs, hostnames, identity hashes or `config.json`;
  use placeholders (see `config.example.json`).
- **NEVER** put `--` inside an XML comment in `docker/unraid-template.xml` (e.g. a
  `--build` flag). It makes the XML invalid, and Unraid then silently skips the
  template: `rebuild_container` does nothing and the UI's Edit page breaks.
- Pin package versions in `docker/Dockerfile` and check them on OSV.dev
  before bumping.

## Release checklist

1. `python3 -m py_compile pages/*.mu lib/*.py` (deploy.sh does this too)
2. Run changed pages locally:
   `env -i PATH="$PATH" RNS_APPS_DATA=/tmp/rnsdata remote_identity=<hex> var_x=y pages/<page>.mu`
3. Bump the page's `VERSION`, update `CHANGELOG.md`
4. Commit, push, `RNS_APPS_HOST=root@<host> ./deploy.sh`
5. Verify over Reticulum: `docker exec rns-apps python3 /opt/rns-apps/tools/rns_fetch.py --rnsconfig /data/reticulum <node hash> /page/<page>.mu`
6. Changes under `docker/` publish a new image via Actions; then pull and recreate the container
