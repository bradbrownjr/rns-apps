# rns-apps

A BBS-style [NomadNet](https://github.com/markqvist/NomadNet) page node for
[Reticulum](https://reticulum.network): amateur radio and emergency
communications apps, browsable from MeshChat, NomadNet, or any Reticulum page
browser.

Sister project of [bpq-apps](https://github.com/bradbrownjr/bpq-apps), which
serves the same apps to packet radio users over a BPQ node. rns-apps ports them
to NomadNet's page model, using the visitor's Reticulum identity in place of a
login.

## Apps

| App | Page | Description |
|-----|------|-------------|
| Menu | `index.mu` | Categorized app menu, the node's home page |
| Register | `register.mu` | Pick a handle; optional name, callsign, location |
| WALL | `wall.mu` | Community one-liners: post, read, delete your own |
| HAMQSL | `hamqsl.mu` | Solar data and HF/VHF band conditions (hamqsl.com) |
| SPACE | `space.mu` | NOAA SWPC space weather reports |
| WX-ME | `wx-me.mu` | NWS Maine/New Hampshire text products |
| QRZ | `qrz.mu` | US callsign lookup (HamDB / FCC data) |
| DICT | `dict.mu` | Dictionary (dict.org: WordNet, GCIDE, ...) |
| WX | `wx.mu` | NWS weather for any US place: conditions, forecast, alerts, AFD, HWO |
| REPEATER | `repeater.mu` | RepeaterBook search by state or near a ZIP/grid/callsign (needs `repeaterbook_token`) |
| About | `about.mu` | Node info |

More bpq-apps are listed greyed-out on the menu and will be ported over time.

**Offline-first:** every app that pulls from the internet caches what it gets
and serves the cached copy, clearly marked, when the source is unreachable.

## Identity

Reticulum has no logins. When a visitor chooses to **identify** to the node,
pages receive their public identity hash. rns-apps uses that to:

- let them register a handle once, with optional name, callsign and location
  (self-reported, not verified; only the handle is public),
- attribute wall posts and allow deleting their own,
- recognize sysops (identity hashes listed in `config.json`).

Anonymous visitors can read everything; writing needs identification.

## Running it

rns-apps runs as a Docker container that connects to an existing Reticulum
node (for example a transport node with a `BackboneInterface` or
`TCPServerInterface`) over TCP.

The image is published to GHCR for amd64 and arm64 (Raspberry Pi):
`ghcr.io/bradbrownjr/rns-apps:latest`. It only contains NomadNet, RNS and the
entrypoint; the pages are bind-mounted, so you can edit them without a new image.

```bash
# Sync the app code to the Docker host
RNS_APPS_HOST=root@your-unraid ./deploy.sh

# Run it (or use docker/unraid-template.xml on Unraid)
docker run -d --name rns-apps --restart unless-stopped \
  -v /mnt/user/appdata/rns-apps/app:/opt/rns-apps:ro \
  -v /mnt/user/appdata/rns-apps/data:/data \
  -e NODE_NAME="Your Callsign BBS" \
  -e GATEWAY_HOST=your-reticulum-node -e GATEWAY_PORT=4242 \
  ghcr.io/bradbrownjr/rns-apps:latest
```

Then copy `config.example.json` to `data/apps/config.json`, and set the node
name and your identity hash as sysop. In MeshChat, your identity hash is shown
on the identity/settings page. The node's address, the hash you share with
others, comes from:

```bash
docker exec rns-apps python3 /opt/rns-apps/tools/node_info.py
```

Updating pages is just `./deploy.sh`. Code is bind-mounted read-only, so
changes are live on the next request.

| Variable | Default | Purpose |
|----------|---------|---------|
| `NODE_NAME` | `rns-apps` | Name in the node's announces |
| `GATEWAY_HOST` | (required on first run) | Reticulum node to connect through |
| `GATEWAY_PORT` | `4242` | Its TCP/Backbone port |
| `ANNOUNCE_INTERVAL` | `360` | Minutes between announces |
| `PAGE_REFRESH_INTERVAL` | `5` | Minutes between rescans for new page files |

## Writing a page

Pages are executable Python files in `pages/` that print
[micron](https://github.com/markqvist/NomadNet). Use the helpers in
`lib/rnsapps.py`:

```python
import rnsapps as ra

def render():
    name = ra.display_name(ra.identity())
    return "\n".join([ra.heading("Hello"), "Hi {}!".format(ra.esc(name)), ra.nav()])

if __name__ == "__main__":
    ra.run(render)
```

Test locally the way NomadNet runs it, with only `PATH` and request variables:

```bash
env -i PATH="$PATH" RNS_APPS_DATA=/tmp/rnsdata remote_identity=<32 hex> var_p=2 pages/wall.mu
```

Or fetch it over Reticulum from inside the container, exactly as a visitor would:

```bash
docker exec rns-apps python3 /opt/rns-apps/tools/rns_fetch.py \
  --rnsconfig /data/reticulum <node hash> /page/index.mu "/page/space.mu?var_r=wwv"
```

See [AGENTS.md](AGENTS.md) for the full conventions.

## License

CC0 1.0 Universal, same as bpq-apps.
