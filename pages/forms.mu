#!/usr/bin/env python3
"""
Fillable message forms (port of bpq-apps forms.py): ICS-213, ARRL radiogram,
net check-in, SKYWARN strips and more.

Forms are templates in data/forms/*.frm (JSON). Pages run once per request,
so filling a form is a wizard: one field per page, with the draft kept per
identity in forms_drafts.json. A finished form is formatted as plain text,
shown to the visitor to copy, saved in forms_outbox/, and queued for LXMF
delivery to the destinations in config.json "forms_deliver_to" (delivered by
tools/lxmf_sender.py running in the container).

Filling a form needs an identified visitor.

Version: 1.0
Author: Brad Brown Jr (KC1JMH)
"""

import glob
import json
import os
import sys
import uuid
from datetime import datetime, timezone

sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.realpath(__file__))), "lib"))
import formsfmt  # noqa: E402
import rnsapps as ra  # noqa: E402

VERSION = "1.0"
DRAFTS = "forms_drafts.json"
OUTBOX = "forms_outbox"
MAX_OUTBOX = 200
MAX_VALUE = 1500


# ---------------------------------------------------------------- templates ---

def load_forms():
    forms = {}
    for path in sorted(glob.glob(os.path.join(ra.APP_ROOT, "data", "forms", "*.frm"))):
        data = ra.load_json(path, None)
        if data and data.get("id"):
            forms[data["id"]] = data
    return forms


def fields_of(form, draft):
    """Field list for the draft: strip forms build theirs from the parsed strip."""
    if form.get("strip_mode"):
        return [{"name": "s{}".format(n), "label": label, "type": "text", "required": False,
                 "description": "Leave blank if not applicable. No '/' characters."}
                for n, label in enumerate(draft.get("strip_labels", []))]
    return form.get("fields", [])


# ------------------------------------------------------------------- drafts ---

def get_draft(ident):
    return ra.load_json(ra.data_path(DRAFTS), {}).get(ident)


def save_draft(ident, draft):
    with ra.locked("forms_drafts"):
        data = ra.load_json(ra.data_path(DRAFTS), {})
        if draft is None:
            data.pop(ident, None)
        else:
            data[ident] = draft
        ra.save_json(ra.data_path(DRAFTS), data)


def default_for(field, ident):
    if field.get("default_now"):
        return datetime.now(timezone.utc).strftime(field["default_now"])
    if field.get("auto_fill") == "callsign":
        return ra.callsign_for(ident) or ""
    return field.get("default", "")


# ------------------------------------------------------------------ outbox ---

def submit(ident, form, draft):
    fields = fields_of(form, draft)
    now = datetime.now(timezone.utc)
    form_data = {
        "form_title": form.get("title", ""), "form_id": form.get("id", ""),
        "output_format": form.get("format", "standard"),
        "submitted_by": ra.callsign_for(ident) or ra.display_name(ident),
        "submitted_date": now.strftime("%Y-%m-%d %H:%M UTC"),
        "fields": [{"name": f["name"], "label": f.get("label", f["name"]), "type": f.get("type", "text"),
                    "value": draft["values"].get(f["name"], "")} for f in fields],
    }
    if "nts_check" in draft:
        form_data["nts_check"] = draft["nts_check"]
    if form.get("strip_mode"):
        responses = [f["value"] or "   " for f in form_data["fields"]]
        title = draft.get("strip_title", "STRIP")
        form_data.update({"strip_title": title, "strip_request": draft.get("strip_request", ""),
                          "strip_response": title + "/" + "/".join(responses) + "//"})
    subject, body = formsfmt.subject_and_body(form_data)
    record = {
        "id": uuid.uuid4().hex[:8], "created": ra.utc_iso(), "form": form["id"],
        "from_identity": ident, "from": ra.display_name(ident), "subject": subject, "body": body,
        "deliver_to": ra.config().get("forms_deliver_to", []), "delivered": [], "attempts": 0,
    }
    folder = ra.data_path(OUTBOX)
    os.makedirs(folder, exist_ok=True)
    existing = sorted(glob.glob(os.path.join(folder, "*.json")))
    for old in existing[:max(len(existing) - MAX_OUTBOX + 1, 0)]:
        os.remove(old)
    ra.save_json(os.path.join(folder, "{}-{}.json".format(now.strftime("%Y%m%dT%H%M%S"), record["id"])), record)
    return record


def outbox_view(ident):
    out = [ra.heading("Submitted forms")]
    if not ra.is_sysop(ident):
        return out + ["Sysops only.", ra.nav(("Forms", "forms"))]
    files = sorted(glob.glob(os.path.join(ra.data_path(OUTBOX), "*.json")), reverse=True)
    rid = ra.var("r")
    if rid:
        for path in files:
            rec = ra.load_json(path, {})
            if rec.get("id") == rid:
                out += [ra.bold(rec["subject"]), ra.dim("{} from {} ({})".format(rec["created"], rec["from"], rec["from_identity"][:8])),
                        ra.dim("Delivered to {} of {}".format(len(rec["delivered"]), len(rec["deliver_to"]))), ""]
                return out + ra.paragraphs(rec["body"]) + [ra.nav(("Submissions", "forms"))]
    if not files:
        out.append("No forms submitted yet.")
    for path in files[:20]:
        rec = ra.load_json(path, {})
        state = "sent" if rec.get("deliver_to") and len(rec.get("delivered", [])) >= len(rec["deliver_to"]) else (
            "queued" if rec.get("deliver_to") else "stored")
        out += [ra.link(rec.get("subject", "?")[:50], "forms", a="outbox", r=rec.get("id", "")),
                ra.dim("{} {} {}".format(ra.fmt_ts(rec.get("created")), rec.get("from", ""), state)), ""]
    return out + [ra.nav(("Forms", "forms"))]


# --------------------------------------------------------------------- views ---

def not_identified():
    return "\n".join([
        ra.heading("Forms"),
        "Filling in a form needs this node to know who you are.",
        "Use your page browser's Identify option for this node, then reload.",
        ra.nav(),
    ])


def menu(ident, forms, draft):
    out = [ra.heading("Forms"), "Fill in a form and get the formatted text back to send or copy.", ""]
    if draft and draft.get("form") in forms:
        out += [ra.link("Resume: {}".format(forms[draft["form"]]["title"]), "forms", a="step", f=draft["form"],
                        i=draft.get("i", 0)), ""]
    for fid, form in forms.items():
        out.append(ra.link(form["title"][:60], "forms", a="start", f=fid))
        out.append(ra.dim(form.get("description", "")[:100]))
    if ra.is_sysop(ident):
        out += ["", ra.link("Submitted forms (sysop)", "forms", a="outbox")]
    return out + [ra.nav()]


def strip_intro(form, draft, note=""):
    out = [ra.heading(form["title"])] + ra.paragraphs(form.get("description", "")[:300]) + [""]
    if note:
        out += [ra.color(note, ra.C_WARN), ""]
    template = form.get("template")
    if template:
        out += [ra.link("Use the standard template", "forms", a="strip", f=form["id"], t=1), ""]
    out += ["Or paste a request strip (TITLE/FIELD/FIELD//):", ra.input_field("strip", 60, ""),
            ra.submit("Use this strip", "forms", "strip", a="strip", f=form["id"])]
    return out + [ra.nav(("Forms", "forms"))]


def step_view(ident, form, draft, idx, note=""):
    fields = fields_of(form, draft)
    if idx >= len(fields):
        return review_view(form, draft)
    field = fields[idx]
    ftype = field.get("type", "text")
    value = draft["values"].get(field["name"], default_for(field, ident))
    req = field.get("required", False)
    out = [ra.dim("{}  {}/{}".format(form["title"], idx + 1, len(fields))),
           ra.bold(field.get("label", field["name"]) + (" *" if req else ""))]
    if field.get("description"):
        out += ra.paragraphs(field["description"][:300])
    if note:
        out += ["", ra.color(note, ra.C_WARN)]
    out.append("")
    base = {"f": form["id"], "i": idx}
    if ra.var("e"):
        base["e"] = 1
    if ftype == "choice":
        for n, choice in enumerate(field.get("choices", [])):
            out.append(ra.link(("> " if choice == value else "") + choice, "forms", a="set", v=n, **base))
    elif ftype == "yesno":
        options = ["Yes", "No"] + (["N/A"] if field.get("allow_na") else [])
        for n, choice in enumerate(options):
            out.append(ra.link(("> " if choice == value else "") + choice, "forms", a="set", v=n, **base))
    else:
        out += [ra.input_field("val", 60, value), ra.submit("Next", "forms", "val", a="set", **base)]
        if field.get("max_length"):
            out.append(ra.dim("Up to {} characters.".format(field["max_length"])))
    if not req and ftype in ("choice", "yesno"):
        out.append(ra.link("Skip", "forms", a="set", v="-", **base))
    nav = []
    if idx > 0:
        nav.append(ra.link("< Back", "forms", a="step", f=form["id"], i=idx - 1))
    nav.append(ra.link("Cancel form", "forms", a="cancel"))
    return out + ["", "  ".join(nav)]


def review_view(form, draft):
    out = [ra.heading("Review: {}".format(form["title"])), ""]
    for idx, field in enumerate(fields_of(form, draft)):
        value = draft["values"].get(field["name"], "")
        out.append("{} {}  {}".format(ra.dim(field.get("label", field["name"])[:40] + ":"),
                                      ra.esc(value or "-")[:160], ra.link("edit", "forms", a="step", f=form["id"], i=idx, e=1)))
    out += ["", ra.link("SEND", "forms", a="send", f=form["id"]), "  ", ra.link("Cancel form", "forms", a="cancel")]
    return out


def sent_view(record):
    delivery = ""
    if record["deliver_to"]:
        delivery = "It has also been queued for delivery over LXMF."
    out = [ra.heading("Form sent"), ra.color("Saved on this node. " + delivery, ra.C_OK), "",
           ra.dim("Copy this text into your own app:"), "", ra.bold(record["subject"]), ""]
    out += ra.paragraphs(record["body"])
    return out + [ra.nav(("More forms", "forms"))]


def render():
    ident = ra.identity()
    forms = load_forms()
    action = ra.var("a")
    if not ident:
        return not_identified()
    if action == "outbox":
        return "\n".join(outbox_view(ident))
    draft = get_draft(ident)
    fid = ra.var("f")
    form = forms.get(fid) or (forms.get(draft["form"]) if draft else None)

    if action == "cancel":
        save_draft(ident, None)
        return "\n".join(menu(ident, forms, None))
    if not action or not form:
        return "\n".join(menu(ident, forms, draft))

    if action == "start":
        draft = {"form": form["id"], "values": {}, "i": 0, "started": ra.utc_iso()}
        save_draft(ident, draft)
        if form.get("strip_mode"):
            return "\n".join(strip_intro(form, draft))
        return "\n".join(step_view(ident, form, draft, 0))

    if not draft or draft.get("form") != form["id"]:
        return "\n".join(menu(ident, forms, draft))

    if action == "strip":
        text = (form.get("template") if ra.var("t") else ra.field("strip")).strip()
        text = text[:-2] if text.endswith("//") else text
        parts = [p.strip() for p in formsfmt.split_strip(text)]
        if len(parts) < 3:
            return "\n".join(strip_intro(form, draft, "A strip needs a title and at least one field, e.g. ROSTER/CALL/NAME//"))
        draft.update({"strip_title": parts[0], "strip_labels": [p for p in parts[1:] if p],
                      "strip_request": text + "//", "values": {}, "i": 0})
        save_draft(ident, draft)
        return "\n".join(step_view(ident, form, draft, 0))

    fields = fields_of(form, draft)
    idx = max(min(ra.int_var("i", 0), len(fields)), 0)

    if action == "set" and idx < len(fields):
        field = fields[idx]
        ftype = field.get("type", "text")
        if ftype == "choice":
            choices = field.get("choices", [])
            v = ra.var("v")
            value = choices[int(v)] if v.isdigit() and int(v) < len(choices) else ""
        elif ftype == "yesno":
            options = ["Yes", "No"] + (["N/A"] if field.get("allow_na") else [])
            v = ra.var("v")
            value = options[int(v)] if v.isdigit() and int(v) < len(options) else ""
        else:
            value = " ".join(ra.field("val").split())[:MAX_VALUE]
            if form.get("strip_mode") and "/" in value:
                return "\n".join(step_view(ident, form, draft, idx, "An answer can't contain '/'."))
            if field.get("max_length") and len(value) > field["max_length"]:
                return "\n".join(step_view(ident, form, draft, idx, "Too long: {} of {} characters.".format(len(value), field["max_length"])))
            bad = formsfmt.validate(field, value)
            if bad:
                return "\n".join(step_view(ident, form, draft, idx, bad))
        if field.get("required") and not value:
            return "\n".join(step_view(ident, form, draft, idx, "This field is required."))
        if value and field.get("nts_normalize"):
            value = formsfmt.normalize_nts_text(value)
            draft["nts_check"] = formsfmt.count_nts_check(value)
        draft["values"][field["name"]] = value
        draft["i"] = idx + 1
        save_draft(ident, draft)
        nxt = len(fields) if ra.var("e") else idx + 1
        return "\n".join(step_view(ident, form, draft, nxt))

    if action == "step":
        return "\n".join(step_view(ident, form, draft, idx))

    if action == "send":
        missing = [f.get("label", f["name"]) for f in fields if f.get("required") and not draft["values"].get(f["name"])]
        if missing:
            return "\n".join([ra.color("Still needed: " + ", ".join(missing), ra.C_WARN), ""] + review_view(form, draft))
        record = submit(ident, form, draft)
        save_draft(ident, None)
        return "\n".join(sent_view(record))

    return "\n".join(menu(ident, forms, draft))


if __name__ == "__main__":
    ra.run(render)
