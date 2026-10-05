FROM python:3.12-slim

# Pinned and checked against OSV.dev 2026-10-05
RUN pip install --no-cache-dir nomadnet==1.4.4 rns==1.5.7 lxmf==1.2.0

ENV PYTHONUNBUFFERED=1 \
    NODE_NAME="rns-apps" \
    GATEWAY_HOST="" \
    GATEWAY_PORT="4242" \
    ANNOUNCE_INTERVAL="360" \
    PAGE_REFRESH_INTERVAL="5"

# App code (pages/, lib/, apps.json) is bind-mounted read-only at
# /opt/rns-apps so a deploy is a file sync, not an image rebuild.
# All state (identities, configs, wall, caches) lives under /data.
COPY entrypoint.py /usr/local/bin/rns-apps-entrypoint
RUN chmod 755 /usr/local/bin/rns-apps-entrypoint

VOLUME ["/data"]
ENTRYPOINT ["rns-apps-entrypoint"]
