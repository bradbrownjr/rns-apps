"""
Form output formatting for rns-apps FORMS, ported from bpq-apps forms.py.

Pure functions: validation, the standard text body, strip responses, the
PACKET CHECK-IN body and the ARRL NTS radiogram (with the NTS text rules).
form_data is {"form_id", "form_title", "submitted_by", "submitted_date",
"fields": [{"name", "label", "type", "value"}], ...}.

Version: 1.0
Author: Brad Brown Jr (KC1JMH)
"""

import re
from datetime import datetime, timezone

VERSION = "1.0"

_STATE_ABBR = {
    'alabama': 'AL', 'alaska': 'AK', 'arizona': 'AZ', 'arkansas': 'AR',
    'california': 'CA', 'colorado': 'CO', 'connecticut': 'CT', 'delaware': 'DE',
    'florida': 'FL', 'georgia': 'GA', 'hawaii': 'HI', 'idaho': 'ID',
    'illinois': 'IL', 'indiana': 'IN', 'iowa': 'IA', 'kansas': 'KS',
    'kentucky': 'KY', 'louisiana': 'LA', 'maine': 'ME', 'maryland': 'MD',
    'massachusetts': 'MA', 'michigan': 'MI', 'minnesota': 'MN', 'mississippi': 'MS',
    'missouri': 'MO', 'montana': 'MT', 'nebraska': 'NE', 'nevada': 'NV',
    'new hampshire': 'NH', 'new jersey': 'NJ', 'new mexico': 'NM', 'new york': 'NY',
    'north carolina': 'NC', 'north dakota': 'ND', 'ohio': 'OH', 'oklahoma': 'OK',
    'oregon': 'OR', 'pennsylvania': 'PA', 'rhode island': 'RI', 'south carolina': 'SC',
    'south dakota': 'SD', 'tennessee': 'TN', 'texas': 'TX', 'utah': 'UT',
    'vermont': 'VT', 'virginia': 'VA', 'washington': 'WA', 'west virginia': 'WV',
    'wisconsin': 'WI', 'wyoming': 'WY', 'district of columbia': 'DC',
    # common shorthands
    'mass': 'MA', 'conn': 'CT', 'penn': 'PA', 'penna': 'PA',
    'wash': 'WA', 'tenn': 'TN', 'mich': 'MI', 'minn': 'MN',
}
_VALID_STATE_ABBRS = set(_STATE_ABBR.values())


def format_pktnet_checkin(form_data):
    """Format body as PACKET CHECK-IN matching vden.org check_in.html output exactly"""
    fv = {f['name']: f['value'] for f in form_data['fields']}

    lines = []
    lines.append("PACKET CHECK-IN")
    lines.append("")

    agency = fv.get('agency', '').strip()
    if agency:
        lines.append(agency)
        lines.append("")

    lines.append("1. STATION")
    lines.append("")
    lines.append("a. Date/Time: {}".format(fv.get('datetime', '')))
    lines.append("")
    lines.append("b. To: {}".format(fv.get('to', '')))
    lines.append("")
    lines.append("c. From: {}    d. Station Contact Name: {}    e. Initial Operator(s): {}".format(
        fv.get('from_call', form_data.get('submitted_by', '')),
        fv.get('contact', ''),
        fv.get('operator', '')
    ))
    lines.append("")
    lines.append("")
    lines.append("2. SESSION")
    lines.append("")
    lines.append("a. Type: {}    b. Service: {}    c. Band: {}".format(
        fv.get('session_type', ''),
        fv.get('service_type', 'AMATEUR'),
        fv.get('band', '')
    ))
    lines.append("")
    lines.append("d. Session: {}".format(fv.get('mode', '')))
    lines.append("")
    lines.append("")
    lines.append("3. LOCATION")
    lines.append("")
    lines.append("a. Location: {}".format(fv.get('location', '')))
    lines.append("")
    lines.append("b. GRID SQUARE: {}".format(fv.get('gridsquare', '')))
    lines.append("")
    lines.append("")
    lines.append("4. COMMENTS: {}".format(fv.get('comments', '')))

    return '\n'.join(lines)

_NTS_SPELLED = [('.', 'X'), ('?', 'QUERY'), ('!', 'EXCLAMATION'), (',', 'COMMA'),
                (':', 'COLON'), (';', 'SEMICOLON'), ('-', 'DASH'), ('&', 'AND'),
                ('@', 'AT')]
_NTS_ONES = ('', 'ONE', 'TWO', 'THREE', 'FOUR', 'FIVE', 'SIX', 'SEVEN', 'EIGHT',
             'NINE', 'TEN', 'ELEVEN', 'TWELVE', 'THIRTEEN', 'FOURTEEN', 'FIFTEEN',
             'SIXTEEN', 'SEVENTEEN', 'EIGHTEEN', 'NINETEEN')
_NTS_TENS = ('', '', 'TWENTY', 'THIRTY', 'FORTY', 'FIFTY', 'SIXTY', 'SEVENTY',
             'EIGHTY', 'NINETY')

def _nts_number_words(n):
    """46 -> FORTY SIX (ARL numbers are always spelled, MPG 1.3.3)."""
    if n < 20:
        return _NTS_ONES[n]
    return '{} {}'.format(_NTS_TENS[n // 10], _NTS_ONES[n % 10]).strip()

def normalize_nts_text(text):
    """The text as radiogram groups, punctuation spelled out (MPG 1.3.1;
    RRI 2026): . -> X (never the last group), ? -> QUERY, , -> COMMA,
    decimal point between digits -> R, "..." -> QUOTE ... UNQUOTE,
    (...) -> PAREN ... UNPAREN, apostrophe dropped, #5 -> NR 5,
    an email address -> ... ATSIGN ... DOT ..., ARL 46 -> ARL FORTY SIX.
    """
    t = text.upper().replace('\u2019', "'")
    t = re.sub(r'[\w.+-]+@[\w-]+(?:\.[\w-]+)+',
               lambda m: ' {} '.format(encode_nts_email(m.group(0))), t)
    t = re.sub(r'(\d)\.(\d)', r'\1R\2', t)
    t = re.sub(r'\b(\d{3})-(\d{3})-(\d{4})\b', r'\1 \2 \3', t)
    t = re.sub(r'\b(\d{3})-(\d{4})\b', r'\1 \2', t)
    t = re.sub(r'(^|\s)"', r'\1 QUOTE ', t).replace('"', ' UNQUOTE ')
    t = t.replace('(', ' PAREN ').replace(')', ' UNPAREN ')
    t = t.replace("'", '')
    t = re.sub(r'#\s*(?=\d)', ' NR ', t)
    for char, word in _NTS_SPELLED:
        t = t.replace(char, ' {} '.format(word))
    t = re.sub(r'[^A-Z0-9/\s]', ' ', t)
    groups = []
    words = t.split()
    for i, g in enumerate(words):
        if i and words[i - 1] == 'ARL' and g.isdigit() and 1 <= int(g) <= 99:
            groups.extend(_nts_number_words(int(g)).split())
        elif not (g == 'X' and groups and groups[-1] == 'X'):
            groups.append(g)
    while groups and groups[-1] == 'X':
        groups.pop()
    return ' '.join(groups)

def count_nts_check(text):
    """The check of normalized text: the number of groups, whatever
    their length (MPG 1.3.4), with ARL ahead of it when the text holds
    an ARL numbered radiogram (MPG 1.1.5): "9" or "ARL 9"."""
    groups = text.split()
    if 'ARL' in groups:
        return 'ARL {}'.format(len(groups))
    return str(len(groups))

def encode_nts_email(addr):
    """user@example.com -> USER ATSIGN EXAMPLE DOT COM (RRI 2026)."""
    if not addr:
        return ''
    t = addr.strip().upper()
    for char, word in (('@', 'ATSIGN'), ('.', 'DOT'), ('-', 'DASH'), ('_', 'UNDERSCORE')):
        t = t.replace(char, ' {} '.format(word))
    return ' '.join(t.split())

def format_nts_phone(ph):
    """(207) 555-1212 -> 207 555 1212, no dashes, no TEL (MPG 1.2.4;
    RRI's sample radiogram)."""
    if not ph:
        return ph
    digits = re.sub(r'[^\d]', '', ph)
    if len(digits) == 11 and digits[0] == '1':
        digits = digits[1:]
    if len(digits) == 10:
        return '{} {} {}'.format(digits[:3], digits[3:6], digits[6:])
    if len(digits) == 7:
        return '{} {}'.format(digits[:3], digits[3:])
    return ' '.join(re.sub(r'[^0-9\s]', ' ', ph).split())

def format_nts_zip(code):
    """21117-2345 -> 21117 DASH 2345 (MPG 1.2.3)."""
    digits = re.sub(r'[^\d]', '', code or '')
    if len(digits) == 9:
        return '{} DASH {}'.format(digits[:5], digits[5:])
    return digits

def _sanitize_nts_address(text):
    """An address line without punctuation (MPG 1.2.6): # -> NR (KY2D),
    a needed hyphen -> DASH, / may stay, anything else -> space."""
    t = re.sub(r'#\s*', ' NR ', (text or '').upper())
    t = re.sub(r'(\w)\s*-\s*(\w)', r'\1 DASH \2', t)
    t = re.sub(r'[^A-Z0-9/\s]', ' ', t)
    return ' '.join(t.split())

def _format_text_5words(text):
    """Format normalized NTS text in groups of 5 words per line."""
    words = text.split()
    chunks = []
    for i in range(0, len(words), 5):
        chunks.append(' '.join(words[i:i+5]))
    return '\n'.join(chunks)

def _compute_nts_subject(form_data):
    """Compute the BPQ message subject for an NTS radiogram.
    Returns: CITY CALLSIGN | CITY NXX NXX | CITY - -
    """
    fv = {f['name']: f['value'] for f in form_data['fields']}
    # Strip commas and collapse spaces (same as format_nts_radiogram)
    _cs_clean = re.sub(r' {2,}', ' ', re.sub(r',', ' ', fv.get('to_city_state', '').upper())).strip()
    _cs_parts = _cs_clean.split()
    city = ' '.join(_cs_parts[:-1]) if len(_cs_parts) > 1 else _cs_clean
    to_callsign_s = fv.get('to_callsign', '').upper().strip()
    to_phone_s = fv.get('to_phone', '').strip()
    if to_callsign_s:
        return '{} {}'.format(city, to_callsign_s)
    elif to_phone_s:
        _ph = re.sub(r'[^\d]', '', to_phone_s)
        if len(_ph) == 11 and _ph[0] == '1':
            _ph = _ph[1:]
        return '{} {} {}'.format(city, _ph[:3], _ph[3:6]) if len(_ph) == 10 else '{} - -'.format(city)
    else:
        return '{} - -'.format(city)

def format_nts_radiogram(form_data):
    """Format body as standard ARRL NTS radiogram.
    Two BT breaks only: after address block, after text.
    Phone and email are normalized per NTS punctuation rules.
    """
    fv = {f['name']: f['value'] for f in form_data['fields']}

    # Precedence: the letter from e.g. "R - Routine"; EMERGENCY is
    # always spelled out (MPG 1.1.2)
    prec = fv.get('precedence', 'R - Routine').split(' ')[0].upper()
    if prec == 'E':
        prec = 'EMERGENCY'
    handling = fv.get('handling', '').strip().upper()
    origin = fv.get('station_of_origin', form_data.get('submitted_by', '')).upper()

    # Check: use pre-computed value from fill_form (counts original words,
    # not prosign substitutions). Fall back to count_nts_check if not set.
    raw_text = fv.get('text', '')
    text = normalize_nts_text(raw_text)
    if 'nts_check' in form_data:
        check = str(form_data['nts_check'])
    else:
        check = count_nts_check(text)

    place = _sanitize_nts_address(fv.get('place_of_origin', ''))

    # Time filed carries its zone, 1830Z (MPG 1.1.7); the field is UTC.
    filed_time = fv.get('filed_time', '').strip().upper()
    if not filed_time:
        filed_time = datetime.now(timezone.utc).strftime('%H%M')
    if re.match(r'^\d{4}$', filed_time):
        filed_time += 'Z'
    # Month and day, no leading zero (MPG 1.1.9): SEP 5
    now = datetime.now(timezone.utc)
    filed_date = '{} {}'.format(now.strftime('%b').upper(), now.day)

    # No NR before the number: RRI 2026's sample and TPRFN's generator
    # (the 2002 MPG 6.2.1 had it)
    preamble_parts = [fv.get('number', ''), prec]
    if handling:
        preamble_parts.append(handling)
    preamble_parts.extend([origin, check, place, filed_time, filed_date])
    preamble = ' '.join(p for p in preamble_parts if p)

    lines = []
    lines.append(preamble)

    # Address block — no BT before address (only 2 BTs total in a radiogram)
    to_name = _sanitize_nts_address(fv.get('to_name', ''))
    to_callsign = fv.get('to_callsign', '').upper().strip()
    # Deduplicate: user may have typed "JIM KUTSCH KY2D" in the name field
    # and also entered KY2D in the callsign field — don't append it twice
    if to_callsign and to_name.upper().endswith(to_callsign):
        name_line = to_name
    else:
        name_line = '{} {}'.format(to_name, to_callsign).strip() if to_callsign else to_name
    lines.append(name_line)
    to_address = _sanitize_nts_address(fv.get('to_address', ''))
    if to_address:
        lines.append(to_address)
    to_cs = _sanitize_nts_address(fv.get('to_city_state', ''))
    to_zip = format_nts_zip(fv.get('to_zip', ''))
    lines.append("{} {}".format(to_cs, to_zip).strip())
    # Phone and email on lines of their own, no TEL/EMAIL labels
    # (RRI 2026 sample radiogram)
    to_phone = fv.get('to_phone', '').strip()
    if to_phone:
        lines.append(format_nts_phone(to_phone))
    to_email = fv.get('to_email', '').strip()
    if to_email:
        lines.append(encode_nts_email(to_email))
    lines.append('BT')

    # Text in groups of 5 words per line for easy check verification
    lines.append(_format_text_5words(text))
    lines.append('BT')

    lines.append(_sanitize_nts_address(fv.get('signature', '')))

    return '\n'.join(lines)


def validate(field, value):
    """None if the value passes the field's 'validate' rule, else an error string."""
    rule = field.get("validate")
    if not rule or not value:
        return None
    if rule == "nts_number":
        if not re.match(r"^\d{1,4}$", value):
            return "Message number must be 1-4 digits (e.g. 42)"
    elif rule == "callsign":
        if not re.match(r"^[A-Z]{1,2}[0-9][A-Z]{1,3}(/[A-Z0-9]+)?$", value.upper()):
            return "Must be a valid callsign (e.g. KC1JMH, W1AW)"
    elif rule == "city_state":
        parts = value.strip().replace(",", " ").split()
        if len(parts) < 2:
            return "Enter city and state (e.g. PORTLAND ME)"
        if parts[-1].upper() not in _VALID_STATE_ABBRS:
            return "Last word must be a 2-letter state abbreviation (e.g. ME)"
    elif rule == "us_zip":
        if not re.match(r"^\d{5}(-\d{4})?$", value):
            return "ZIP code must be 5 digits (e.g. 04543)"
    elif rule == "phone":
        if len(re.sub(r"[^\d]", "", value)) not in (7, 10, 11):
            return "Enter a valid phone number (e.g. 207-555-0100)"
    elif rule == "email":
        if not re.match(r"^[^@\s]+@[^@\s]+\.[^@\s]+$", value):
            return "Enter a valid email address (e.g. name@example.com)"
    elif rule == "hhmm":
        if not re.match(r"^\d{4}$", value):
            return "Time must be 4 digits HHMM (e.g. 1430)"
        if int(value[:2]) > 23 or int(value[2:]) > 59:
            return "Invalid time. Hours 00-23, minutes 00-59."
    elif rule == "hx_code":
        for code in value.upper().split():
            if not re.match(r"^HX[A-GI]+\d*$", code):
                return "HX code must be HXA-HXG or HXI, optionally numbered (e.g. HXA100)"
    return None


def split_strip(text):
    """TITLE/a (b/c)/d -> ['TITLE', 'a (b/c)', 'd']: / splits only outside parentheses."""
    segments, current, depth = [], [], 0
    for char in text:
        if char == "(":
            depth += 1
        elif char == ")":
            depth = max(depth - 1, 0)
        if char == "/" and depth == 0:
            segments.append("".join(current))
            current = []
        else:
            current.append(char)
    segments.append("".join(current))
    return segments


def subject_and_body(form_data):
    """(subject, body) for a finished form, by output format."""
    fmt = form_data.get("output_format", "standard")
    fv = {f["name"]: f["value"] for f in form_data["fields"]}
    if fmt == "pktnet_checkin":
        subject = "{}, {}, {}".format(fv.get("contact", form_data.get("submitted_by", "")),
                                      fv.get("from_call", form_data.get("submitted_by", "")), fv.get("location", ""))
        return subject, format_pktnet_checkin(form_data)
    if fmt == "nts_radiogram":
        return _compute_nts_subject(form_data), format_nts_radiogram(form_data)
    if "strip_response" in form_data:
        lines = ["Request Strip:", form_data["strip_request"], "", "Response Strip:", form_data["strip_response"], "",
                 "-" * 40, "", "Field Details:", ""]
        lines += ["{}: {}".format(f["label"], f["value"]) for f in form_data["fields"]]
        lines += ["", "-" * 40, "Submitted by: {}".format(form_data["submitted_by"]),
                  "Submitted on: {}".format(form_data["submitted_date"])]
        return "{} - {}".format(form_data.get("strip_title", "Strip Response"), form_data["form_id"]), "\n".join(lines)
    lines = ["Submitted by: {}".format(form_data["submitted_by"]), "Date: {}".format(form_data["submitted_date"]), ""]
    for f in form_data["fields"]:
        if f["type"] == "textarea":
            lines.append("{}:".format(f["label"]))
            lines += ["  {}".format(l) for l in f["value"].split("\n")]
            lines.append("")
        else:
            lines.append("{}: {}".format(f["label"], f["value"]))
    return "{} - {}".format(form_data["form_id"], form_data["form_title"]), "\n".join(lines)
