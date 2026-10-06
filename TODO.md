# TODO

Open items, as of 2026-10-06. Done items move to CHANGELOG.md.

## For the sysop (needs you)

- [ ] Test an LXMF upload end to end: register a handle, attach a file in MeshChatX or Sideband, send it to the address on the Files page, approve it under Sysop > Pending uploads.
- [ ] Create file areas on the sysop page (Sysop > File areas) before approving the first upload.
- [ ] Create the rest of the message boards (only General exists).
- [ ] Pick a handle and reserve it: `config.json` `"sysop_handles": {"<identity>": "<handle>"}`.
- [ ] Apply for a RepeaterBook app token, then set `repeaterbook_token` (REPEATER shows no data until then).
- [ ] Optional: `qrz_user` / `qrz_password` for the QRZ XML API.
- [ ] Optional: `forms_deliver_to` (an LXMF address, e.g. Sideband) so submitted forms are delivered.
- [ ] Decide whether to port AI (chatbot) and BATTLESHIP from bpq-apps.

## Development

- [x] Tell the sender when an upload is approved or rejected (LXMF notice, with the reject reason).
- [x] Search across boards and files (SEARCH on the main menu).
- [x] Menu unread counts for files (new since last visit).
- [x] Optional LXMF notice for new mail (opt-in toggle on the Mail page).
- [ ] Update skills/README with the Files area screenshots/flow once tested on a phone.
