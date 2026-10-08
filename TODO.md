# TODO

Open items, as of 2026-10-08. Done items move to CHANGELOG.md.

## For the sysop (needs you)

- [x] Test an LXMF upload end to end (done 2026-10-08 with MeshChatX).
- [x] Create file areas on the sysop page (EMCOMM exists; areas can be moved under others).
- [ ] Create the rest of the message boards (only General exists).
- [x] Pick a handle and reserve it (Brad).
- [ ] (Parked) Apply for a RepeaterBook app token, then set `repeaterbook_token` (REPEATER shows no data until then).
- [ ] Optional: `qrz_user` / `qrz_password` for the QRZ XML API.
- [ ] Optional: `forms_deliver_to` (an LXMF address, e.g. Sideband) so submitted forms are delivered.
- [ ] Copy `/mnt/user/appdata/rns-apps/data/backups` somewhere off the server if it isn't already covered.

## Development

- [x] Tell the sender when an upload is approved or rejected (LXMF notice, with the reject reason).
- [x] Search across boards and files (SEARCH on the main menu).
- [x] Menu unread counts for files (new since last visit).
- [x] Optional LXMF notice for new mail (opt-in toggle on the Mail page).
- [x] Update README and skills with the BBS and Files flow.
- [x] Nightly backup of bbs.db, profiles, config and files (`tools/backup.py`).
- [x] Sysop: move a thread to another board.

## Roadmap (parked, consider later)

- AI chatbot port from bpq-apps (needs a model endpoint, e.g. Ollama).
- BATTLESHIP port (turn-based game on the SQLite store).
- REPEATER: needs the RepeaterBook token.
- Downloads can't be counted (NomadNet serves files directly); a download page that logs would change how links work.
