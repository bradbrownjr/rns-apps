#!/usr/bin/env python3
"""
Antenna calculators, US band plan and a shared antenna database (port of
bpq-apps antenna.py). One page, switched by the `v` link variable:

    (none)   menu            calc   calculators (c=<name>)
    plan     US band plan    db     browse/search the database
    add      add an entry    formulas, popular

Database entries need an identified visitor, are labelled with their handle
(never a callsign), and are rate limited per identity.

Version: 1.1
Author: Brad Brown Jr (KC1JMH)
"""

import math
import os
import sys
import time

sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.realpath(__file__))), "lib"))
import rnsapps as ra  # noqa: E402

VERSION = "1.1"
DB_FILE = "antenna_db.json"
MAX_ENTRIES = 500
PER_PAGE = 5
ADD_INTERVAL = 60  # seconds between additions per identity
FT = 0.3048

HAM_BANDS = {
    "160m": 1.9, "80m": 3.75, "60m": 5.3545, "40m": 7.15, "30m": 10.125, "20m": 14.175,
    "17m": 18.118, "15m": 21.225, "12m": 24.94, "10m": 28.5, "6m": 52.0, "2m": 146.0, "70cm": 445.0,
}

CALCS = [
    ("dipole", "Dipole"),
    ("efhw", "End-fed half-wave"),
    ("ocf", "Off-center fed"),
    ("folded", "Folded dipole"),
    ("moxon", "Moxon rectangle"),
    ("vertical", "Vertical / J-pole"),
    ("nvis", "NVIS"),
    ("loop", "Loops"),
    ("longwire", "Random wire lengths"),
]

POPULAR = [
    ("Buddipole", "Modular dipole system with tapped coils"),
    ("Wolf River Coil", "Silver Bullet series loading coils"),
    ("Chameleon", "EMCOMM series, hybrid micro, etc"),
    ("MFJ-1899T", "Telescoping whip antenna"),
    ("EFHW-4010", "End-fed half-wave, 40-10m"),
    ("PAC-12", "Linked dipole/vertical system"),
    ("Elecraft AX1", "Ultra-compact 40/30/20m"),
    ("Super Antenna", "MP1 series portable"),
    ("AlexLoop", "Magnetic loop for QRP"),
    ("Ventenna", "HFp series portable"),
]

RANDOM_LENGTHS = [
    (29, "Good multiband starter"), (35.5, "Avoids 80/40m resonance"), (41, "Classic random length"),
    (58, "Popular EFRW length"), (71, "Extended multiband"), (84, "Good for 160-10m"),
    (107, "Very long wire"), (119, "Extended coverage"), (135, "160m capability"), (148, "Full 160m+"),
]

# US amateur band plan (FCC Part 97). Access letters per segment, in the
# order E A G T N: Y = full, c = CW only, . = none.
US_PLAN = [
    {'band': '160m', 'range': '1.800-2.000', 'segments': [('1.800-2.000', 'All', 'YYY..')], 'key_freqs': [('1.800-1.810', 'Digital modes'), ('1.810', 'CW QRP calling'), ('1.838', 'PSK31'), ('1.840', 'FT8'), ('1.842', 'JS8Call'), ('1.845', 'SSTV'), ('1.850', 'CW/Phone boundary*'), ('1.885', 'AM calling'), ('1.900', 'SSB activity center')]},
    {'band': '80m', 'range': '3.500-4.000', 'segments': [('3.500-3.525', 'CW/D', 'Y....'), ('3.525-3.600', 'CW/D', 'YYYcc'), ('3.600-3.700', 'Ph/Im', 'Y....'), ('3.700-3.800', 'Ph/Im', 'YY...'), ('3.800-4.000', 'Ph/Im', 'YYY..')], 'notes': ['c=CW only, 200W max'], 'key_freqs': [('3.560', 'CW QRP calling'), ('3.573', 'FT8'), ('3.575', 'FT4'), ('3.578', 'JS8Call'), ('3.580', 'PSK31'), ('3.583-3.600', 'Winlink gateways'), ('3.585-3.600', 'RTTY'), ('3.790-3.800', 'DX window*'), ('3.845', 'SSTV'), ('3.860', 'ARES/Emerg nets'), ('3.880', 'AM calling'), ('3.985', 'SSB QRP calling')]},
    {'band': '60m', 'range': '5 MHz', 'channels': [('1', '5332.0', '5330.5'), ('2', '5348.0', '5346.5'), ('3', '5358.5', '5357.0'), ('4', '5373.0', '5371.5'), ('5', '5405.0', '5403.5')], 'notes': ['100W ERP max, USB/CW/Digital', '2.8 kHz bandwidth per channel'], 'key_freqs': [('5.357 (Ch3)', 'FT8'), ('5.371 (Ch4)', 'Winlink/SHARES')]},
    {'band': '40m', 'range': '7.000-7.300', 'segments': [('7.000-7.025', 'CW/D', 'Y....'), ('7.025-7.125', 'CW/D', 'YYYcc'), ('7.125-7.175', 'Ph/Im', 'Y....'), ('7.175-7.300', 'Ph/Im', 'YYY..')], 'notes': ['c=CW only, 200W max'], 'key_freqs': [('7.030', 'CW QRP calling'), ('7.040', 'RTTY DX'), ('7.047.5', 'FT4'), ('7.070', 'PSK31'), ('7.074', 'FT8'), ('7.078', 'JS8Call'), ('7.080-7.100', 'RTTY'), ('7.083-7.101', 'Winlink gateways'), ('7.171', 'SSTV'), ('7.285', 'SSB QRP calling'), ('7.290', 'AM calling')]},
    {'band': '30m', 'range': '10.10-10.15', 'segments': [('10.10-10.15', 'CW/D', 'YYY..')], 'notes': ['200W PEP all classes', 'No phone permitted'], 'key_freqs': [('10.106', 'CW QRP calling'), ('10.130', 'JS8Call'), ('10.136', 'FT8'), ('10.140', 'FT4'), ('10.141-10.145', 'Winlink gateways'), ('10.142', 'PSK31')]},
    {'band': '20m', 'range': '14.00-14.35', 'segments': [('14.00-14.025', 'CW/D', 'Y....'), ('14.025-14.15', 'CW/D', 'YYY..'), ('14.15-14.175', 'Ph/Im', 'Y....'), ('14.175-14.225', 'Ph/Im', 'YY...'), ('14.225-14.35', 'Ph/Im', 'YYY..')], 'key_freqs': [('14.060', 'CW QRP calling'), ('14.070', 'PSK31'), ('14.074', 'FT8'), ('14.078', 'JS8Call'), ('14.080', 'FT4'), ('14.085-14.099', 'RTTY'), ('14.095-14.101', 'Winlink gateways'), ('14.100', 'IARU Beacon [AVOID]'), ('14.230', 'SSTV calling'), ('14.285', 'SSB QRP calling'), ('14.286', 'AM calling'), ('14.300', 'Maritime/Emergency')]},
    {'band': '17m', 'range': '18.07-18.17', 'segments': [('18.068-18.11', 'CW/D', 'YYY..'), ('18.11-18.168', 'Ph/Im', 'YYY..')], 'notes': ['WARC band: no contests'], 'key_freqs': [('18.095', 'CW DX window'), ('18.100', 'FT8 / PSK31'), ('18.103-18.105', 'Winlink gateways'), ('18.104', 'FT4 / JS8Call'), ('18.110', 'IARU Beacon [AVOID]')]},
    {'band': '15m', 'range': '21.00-21.45', 'segments': [('21.00-21.025', 'CW/D', 'Y....'), ('21.025-21.20', 'CW/D', 'YYYcc'), ('21.20-21.225', 'Ph/Im', 'Y....'), ('21.225-21.275', 'Ph/Im', 'YY...'), ('21.275-21.45', 'Ph/Im', 'YYY..')], 'notes': ['c=CW only, 200W max'], 'key_freqs': [('21.060', 'CW QRP calling'), ('21.070', 'PSK31'), ('21.074', 'FT8'), ('21.078', 'JS8Call'), ('21.080-21.100', 'RTTY'), ('21.095-21.101', 'Winlink gateways'), ('21.140', 'FT4'), ('21.150', 'IARU Beacon [AVOID]'), ('21.285', 'SSB QRP calling'), ('21.340', 'SSTV')]},
    {'band': '12m', 'range': '24.89-24.99', 'segments': [('24.89-24.93', 'CW/D', 'YYY..'), ('24.93-24.99', 'Ph/Im', 'YYY..')], 'notes': ['WARC band: no contests'], 'key_freqs': [('24.910', 'CW QRP calling'), ('24.915', 'FT8'), ('24.919', 'FT4'), ('24.920', 'PSK31'), ('24.922', 'JS8Call'), ('24.925', 'Winlink gateways'), ('24.930', 'IARU Beacon [AVOID]')]},
    {'band': '10m', 'range': '28.00-29.70', 'segments': [('28.00-28.30', 'CW/D', 'YYYYY'), ('28.30-28.50', 'CW/Ph', 'YYYYY'), ('28.50-29.70', 'All', 'YYY..')], 'notes': ['T/N: 28.0-28.5 only, 200W'], 'key_freqs': [('28.060', 'CW QRP calling'), ('28.074', 'FT8'), ('28.078', 'JS8Call'), ('28.080-28.100', 'RTTY'), ('28.095-28.101', 'Winlink gateways'), ('28.120', 'PSK31'), ('28.180', 'FT4'), ('28.190-28.225', 'Beacon sub-band'), ('28.200', 'IARU Beacon [AVOID]'), ('28.360', 'SSB QRP calling'), ('28.680', 'SSTV'), ('29.00-29.20', 'AM sub-band*'), ('29.30-29.51', 'Satellite sub-band*'), ('29.52-29.58', 'FM repeater inputs'), ('29.600', 'FM simplex calling'), ('29.62-29.68', 'FM repeater outputs')]},
    {'band': '6m', 'range': '50.00-54.00', 'segments': [('50.00-50.10', 'CW', 'YYYY.'), ('50.10-50.30', 'SSB/CW', 'YYYY.'), ('50.30-50.60', 'All', 'YYYY.'), ('51.00-54.00', 'FM/Rpt', 'YYYY.')], 'key_freqs': [('50.060-50.080', 'Beacon sub-band'), ('50.090', 'CW calling'), ('50.110', 'DX CW/SSB calling'), ('50.125', 'SSB calling'), ('50.260', 'Meteor scatter MSK'), ('50.313', 'FT8'), ('50.318', 'FT4 / JS8Call'), ('50.680', 'SSTV'), ('52.525', 'FM simplex calling')]},
    {'band': '2m', 'range': '144.0-148.0', 'segments': [('144.00-144.10', 'CW/EME', 'YYYY.'), ('144.10-144.30', 'SSB/CW', 'YYYY.'), ('144.30-144.50', 'Sat/OSCAR', 'YYYY.'), ('144.50-145.50', 'Rpt/Digi', 'YYYY.'), ('145.50-146.00', 'Sat/Misc', 'YYYY.'), ('146.01-148.00', 'FM/Rpt', 'YYYY.')], 'key_freqs': [('144.174', 'FT8'), ('144.178', 'JS8Call'), ('144.200', 'SSB calling'), ('144.275-144.300', 'Beacons only'), ('144.390', 'APRS'), ('145.800', 'ISS voice downlink'), ('145.825', 'ISS packet/APRS'), ('146.520', 'FM simplex calling'), ('146.535', 'ARES simplex'), ('147.555', 'ARES backup simplex')]},
    {'band': '70cm', 'range': '420.0-450.0', 'segments': [('420.0-432.0', 'ATV', 'YYYY.'), ('432.0-432.10', 'EME/CW', 'YYYY.'), ('432.10-433.0', 'SSB/Digi', 'YYYY.'), ('435.0-438.0', 'Sat only*', 'YYYY.'), ('442.0-445.0', 'FM rptrs', 'YYYY.'), ('447.0-450.0', 'FM inputs', 'YYYY.')], 'notes': ['Shared w/ govt radiolocation'], 'key_freqs': [('432.100', 'SSB/CW calling'), ('432.174', 'FT8'), ('435.0-438.0', 'Satellite [AVOID]'), ('446.000', 'FM simplex calling')]},
]


# ------------------------------------------------------------- helpers ---

def ft_m(feet, digits=1):
    return "{:.{d}f} ft ({:.{e}f} m)".format(feet, feet * FT, d=digits, e=digits + 1 if digits == 1 else digits)


def kv(label, value):
    return "{} {}".format(ra.dim("{:<10}".format(label)), ra.esc(value))


def parse_freq(text):
    """MHz from '7.15' or a band name like '40m'. Returns None if invalid."""
    text = text.strip().lower()
    if text in HAM_BANDS:
        return HAM_BANDS[text]
    try:
        f = float(text)
    except ValueError:
        return None
    return f if 0.1 < f < 3000 else None


def back_link(label, view, **kw):
    return ra.link(label, "antenna", v=view, **{k: v for k, v in kw.items() if v not in ("", None)})


# ---------------------------------------------------------- calculators ---

def calc_form(c, title, blurb, extra=None, **keep):
    freq = ra.arg("f")
    out = [ra.heading(title)] + [ra.esc(l) for l in blurb] + [""]
    if extra:
        out += extra + [""]
    out += ["MHz or band (40m):", ra.input_field("f", 12, freq),
            ra.submit("Calculate", "antenna", "f", v="calc", c=c, **keep)]
    return out, freq


def result_lines(c, freq):
    """The numbers for one calculator. Returns (title, [lines])."""
    half = 468.0 / freq
    quarter = half / 2
    wl = 984.0 / freq
    head = "{:.3f} MHz".format(freq)

    if c == "dipole":
        return "Dipole {}".format(head), [
            kv("Total", ft_m(half)), kv("Each leg", ft_m(half / 2)), "",
            ra.bold("Height above ground"),
            kv("Minimum", ft_m(wl * 0.25)), kv("Good", ft_m(wl * 0.5)), kv("Optimal", ft_m(wl)), "",
            "Feed at center, balun recommended. About 73 ohms at resonance.",
            ra.dim("Length (ft) = 468 / MHz. Height 0.25-1.0 wavelength."),
        ]

    if c == "efhw":
        ratio = ra.var("x") if ra.var("x") in ("49:1", "64:1", "9:1", "4:1") else "49:1"
        lines = [kv("Wire", ft_m(half)), ""]
        if ratio in ("49:1", "64:1"):
            lines += ["Resonant half-wave. Works on the fundamental and harmonic bands.",
                      "Example: a 40m EFHW works on 40/20/15/10m.", "", ra.bold("Harmonics of {:.3f} MHz".format(freq))]
            lines += ["{:.3f} MHz ({}x)".format(freq * m, m) for m in (1, 2, 3, 4) if freq * m <= 30]
        else:
            lines += ["Random wire with a {} unun. Needs a tuner on most bands.".format(ratio), "",
                      ra.bold("Suggested lengths (avoid 1/2 wave)")]
            lines += ["{} ft ({:.1f} m)".format(l, l * FT) for l, _ in RANDOM_LENGTHS if l < half * 1.5]
        return "EFHW {} {}".format(ratio, head), lines

    if c == "ocf":
        lines = [kv("Total", ft_m(half)), kv("Short leg", ft_m(half * 0.33)), kv("Long leg", ft_m(half * 0.67)), "",
                 "Feed at about 1/3 with a 4:1 balun. Feedpoint about 200-300 ohms.", "",
                 ra.bold("Multiband on even harmonics")]
        lines += ["{:.3f} MHz ({}x)".format(freq * m, m) for m in (1, 2, 4) if freq * m <= 54]
        return "OCF dipole {}".format(head), lines

    if c == "folded":
        spacing = half * 0.01
        return "Folded dipole {}".format(head), [
            kv("Total", ft_m(half)), kv("Spacing", "{:.1f} in ({:.1f} cm)".format(spacing * 12, spacing * 30.48)), "",
            "Feed with a 4:1 balun (300 to 75 ohm) or straight to 300 ohm line.",
            "About 288 ohms at resonance.",
        ]

    if c == "moxon":
        # L.B. Cebik / AC6LA MoxGen polynomials; dimensions in wavelengths.
        wire_mm = {"12": 2.053, "14": 1.628, "16": 1.291, "18": 1.024}.get(ra.var("x"), 1.628)
        lam_m = 299.792458 / freq
        x = math.log10(wire_mm / 1000.0 / lam_m)
        A = -0.0008571428571 * x * x - 0.009571428571 * x + 0.3398571429
        B = -0.002142857143 * x * x - 0.02035714286 * x + 0.008285714286
        C = 0.001809523381 * x * x + 0.01780952381 * x + 0.05164285714
        D = 0.001 * x + 0.07178571429
        E = B + C + D
        m = lambda frac: ft_m(frac * lam_m / 0.3048, 2)
        return "Moxon {}".format(head), [
            kv("A width", m(A)), kv("B drv tail", m(B)), kv("C gap", m(C)),
            kv("D ref tail", m(D)), kv("E depth", m(E)), "",
            kv("Driven wire", m(A + 2 * B)), kv("Reflector", m(A + 2 * D)), "",
            "Wire: #{} ({:.2f} mm). Gain about 6 dBi, front-to-back 25 dB or better.".format(
                {"12": "12", "16": "16", "18": "18"}.get(ra.var("x"), "14"), wire_mm),
            "Feed 50 ohm direct at the driven element's center.",
            "Dimensions: MoxGen (Cebik, W4RNL), valid for wire 1e-5 to 1e-2 wavelength.",
        ]

    if c == "vertical":
        kind = ra.var("x") if ra.var("x") in ("1", "2", "3") else "1"
        if kind == "1":
            return "1/4 wave ground plane {}".format(head), [
                kv("Vertical", ft_m(quarter)), kv("Radials", ft_m(quarter) + " x4 min"), "",
                "Radials sloped 45 deg: about 50 ohms.", "Radials horizontal: about 35 ohms."]
        if kind == "2":
            five = half * 0.625 * 2
            return "5/8 wave vertical {}".format(head), [
                kv("Vertical", ft_m(five)), kv("Radials", "{:.1f} ft min".format(quarter)), "",
                "Needs a matching network. About 1.5 dB gain over 1/4 wave."]
        matching = quarter * 0.05
        return "J-pole / Slim Jim {}".format(head), [
            kv("Total", ft_m(half * 1.25)), kv("Radiator", "{:.1f} ft (3/4 wave)".format(half * 0.75 * 2)),
            kv("Stub", "{:.1f} ft (1/4 wave)".format(quarter)), kv("Gap", "{:.1f} in".format(matching * 12)), "",
            "No radials needed. Feed tap about 5% up from the gap."]

    if c == "nvis":
        lines = []
        if freq > 10:
            lines += [ra.color("NVIS works best below 10 MHz (80m, 60m, 40m).", ra.C_WARN), ""]
        lines += [kv("Dipole", ft_m(half)), "", ra.bold("Height above ground"),
                  kv("Minimum", ft_m(wl * 0.10)), kv("Optimal", ft_m(wl * 0.15)), kv("Maximum", ft_m(wl * 0.25)), "",
                  "Takeoff angle 70-90 degrees. Lower height gives a higher angle.",
                  "A reflector wire below helps. Works well over poor ground."]
        return "NVIS {}".format(head), lines

    if c == "loop":
        circ = 1005.0 / freq
        kind = ra.var("x") if ra.var("x") in ("1", "2", "3") else "1"
        if kind in ("1", "2"):
            return ("Horizontal" if kind == "1" else "Vertical") + " loop {}".format(head), [
                kv("Total wire", ft_m(circ)), "",
                ra.bold("Square"), "Each side {:.1f} ft".format(circ / 4), "",
                ra.bold("Triangle"), "Each side {:.1f} ft".format(circ / 3), "",
                ra.bold("Delta"), "Base {:.1f} ft".format(circ * 0.36), "Sides {:.1f} ft each".format(circ * 0.32), "",
                "Feed about 100-120 ohms. Use a 4:1 balun or 75 ohm match."]
        lo, hi = circ * 0.08, circ * 0.25
        return "Magnetic loop {}".format(head), [
            "Small loop for limited space. Needs a high-voltage tuning cap.",
            "Circumference under 0.25 wavelength (typically 8-25 ft).", "",
            kv("Min circ", "{:.1f} ft".format(lo)), kv("Max circ", "{:.1f} ft".format(hi)),
            kv("Diameter", "{:.1f}-{:.1f} ft".format(lo / 3.14, hi / 3.14)), "",
            "Efficiency improves with larger diameter and thicker conductor."]
    return "", []


def view_calc():
    c = ra.var("c")
    names = dict(CALCS)
    if c not in names:
        out = [ra.heading("Calculators"), ""]
        out += [back_link(name, "calc", c=key) for key, name in CALCS]
        return out + [ra.nav(("Antenna menu", "antenna"))]

    if c == "longwire":
        out = [ra.heading("Random wire lengths"),
               "Lengths that avoid resonance on several bands. Use a 9:1 or 4:1 unun and a tuner.", ""]
        out += ["{:>5} ft ({:>5.1f} m)  {}".format(l, l * FT, ra.esc(d)) for l, d in RANDOM_LENGTHS]
        out += ["", ra.bold("Counterpoise"), "17 ft for 20m and up", "25 ft for 40m and up", "65 ft for 80m"]
        return out + [ra.nav(back_link("Calculators", "calc"))]

    blurbs = {
        "dipole": ["A classic half-wave dipole, fed at center with 50 ohm coax."],
        "efhw": ["End-fed half-wave with a matching transformer."],
        "ocf": ["Fed at about 1/3 point, multiband. Usually a 4:1 or 6:1 balun."],
        "folded": ["Higher impedance (about 300 ohms) and broader bandwidth than a plain dipole."],
        "moxon": ["Compact 2-element beam with good front-to-back. Single band."],
        "vertical": ["Ground plane, 5/8 wave or J-pole."],
        "nvis": ["Near Vertical Incidence Skywave, for short-range HF (0-400 miles)."],
        "loop": ["Full-wave wire loops and small magnetic loops."],
    }
    extra, keep = None, {}
    choice = ra.var("x")
    if c == "efhw":
        ratios = ["49:1", "64:1", "9:1", "4:1"]
        choice = choice if choice in ratios else "49:1"
        extra = [ra.dim("Transformer: ") + "  ".join(ra.bold(r) if r == choice else back_link(r, "calc", c=c, x=r, f=ra.arg("f")) for r in ratios)]
        keep = {"x": choice}
    elif c in ("vertical", "loop"):
        opts = {"vertical": [("1", "1/4 GP"), ("2", "5/8"), ("3", "J-pole")],
                "loop": [("1", "Horiz"), ("2", "Vert"), ("3", "Magnetic")]}[c]
        choice = choice if choice in dict(opts) else "1"
        extra = [ra.dim("Type: ") + "  ".join(ra.bold(n) if k == choice else back_link(n, "calc", c=c, x=k, f=ra.arg("f")) for k, n in opts)]
        keep = {"x": choice}

    out, raw = calc_form(c, names[c], blurbs[c], extra, **keep)
    if raw:
        freq = parse_freq(raw)
        if freq is None:
            out += ["", ra.color("Enter 0.1-3000 MHz or a band name like 40m.", ra.C_WARN)]
        else:
            title, lines = result_lines(c, freq)
            out += ["", ra.heading(title, 2)] + lines
    return out + [ra.nav(back_link("Calculators", "calc"))]


# ------------------------------------------------------------ band plan ---

def view_plan():
    band = ra.var("b")
    entry = next((b for b in US_PLAN if b["band"] == band), None)
    if not entry:
        out = [ra.heading("US band plan"), ra.dim("FCC Part 97. Pick a band."), ""]
        out += ["{}  {}".format(back_link(b["band"], "plan", b=b["band"]), ra.dim(b["range"])) for b in US_PLAN]
        out += ["", ra.dim("Access: E=Extra A=Adv G=General T=Tech N=Novice"),
                ra.dim("Y=full  c=CW only  .=none  (Tech/Novice HF: 200W)"),
                ra.dim("Power 1500W PEP. Always check current FCC rules.")]
        return out + [ra.nav(("Antenna menu", "antenna"))]

    out = [ra.heading("{} ({})".format(entry["band"], entry["range"]))]
    if entry.get("channels"):
        out += ["Channelized: 5 USB channels", ra.dim("Ch  Center kHz  Dial kHz")]
        out += ["{:<3} {:>10} {:>10}".format(*ch) for ch in entry["channels"]]
    elif entry.get("segments"):
        out += [ra.dim("{:<13} {:<5} {}".format("Segment", "Mode", "EAGTN"))]
        out += [ra.esc("{:<13} {:<5} {}".format(*seg)) for seg in entry["segments"]]
    if entry.get("notes"):
        out += [""] + [ra.esc(n) for n in entry["notes"]]
    if entry.get("key_freqs"):
        out += ["", ra.bold("Key frequencies (MHz)")]
        out += ["{} {}".format(ra.dim("{:<12}".format(f)), ra.esc(d)) for f, d in entry["key_freqs"]]
        out.append(ra.dim("* ARRL voluntary band plan"))
    idx = [b["band"] for b in US_PLAN].index(band)
    pager = []
    if idx > 0:
        pager.append(back_link("< " + US_PLAN[idx - 1]["band"], "plan", b=US_PLAN[idx - 1]["band"]))
    if idx < len(US_PLAN) - 1:
        pager.append(back_link(US_PLAN[idx + 1]["band"] + " >", "plan", b=US_PLAN[idx + 1]["band"]))
    return out + [ra.nav(*(pager + [back_link("All bands", "plan")]))]


def view_formulas():
    return [ra.heading("Formulas"),
            "Half wave (ft) = 468 / MHz", "Half wave (m) = 142.65 / MHz", "",
            "Quarter wave = half wave / 2", "Full wave = 468 x 2 / MHz", "Loop circumference = 1005 / MHz", "",
            ra.bold("Velocity factor"), "Bare wire 0.95", "Insulated 0.93-0.97", "Coax 0.66-0.82",
            ra.nav(("Antenna menu", "antenna"))]


def view_popular():
    out = [ra.heading("Popular portable antennas"), ""]
    for name, desc in POPULAR:
        out += [ra.bold(name), ra.esc(desc), ""]
    out.append(ra.dim("Share your own settings in the database."))
    return out + [ra.nav(back_link("Database", "db"))]


# ------------------------------------------------------------- database ---

def load_db():
    return ra.load_json(ra.data_path(DB_FILE), {"antennas": []})


def clip(text, n):
    return " ".join(text.split())[:n]


def add_entry(ident):
    """Returns (ok, message)."""
    brand = clip(ra.field("brand"), 40)
    if not brand:
        return False, "Brand/model is required."
    atype = clip(ra.field("type"), 12).capitalize()
    atype = atype if atype in ("Portable", "Base", "Mobile", "Qrp") else "Other"
    atype = "QRP" if atype == "Qrp" else atype
    entry = {
        "brand": brand, "type": atype, "band": clip(ra.field("band"), 12).lower() or "multi",
        "radiator": clip(ra.field("radiator"), 24), "tap": clip(ra.field("tap"), 24),
        "notes": clip(ra.field("notes"), 120), "author": ra.display_name(ident), "identity": ident,
        "timestamp": ra.utc_iso(), "epoch": time.time(),
    }
    with ra.locked("antenna_db"):
        db = load_db()
        items = db["antennas"]
        if time.time() - max((e.get("epoch", 0) for e in items if e.get("identity") == ident), default=0) < ADD_INTERVAL:
            return False, "Slow down - one entry per {} seconds.".format(ADD_INTERVAL)
        entry["id"] = max((e.get("id", 0) for e in items), default=0) + 1
        items.append(entry)
        db["antennas"] = items[-MAX_ENTRIES:]
        ra.save_json(ra.data_path(DB_FILE), db)
    return True, "Added as #{}.".format(entry["id"])


def delete_entry(ident, entry_id):
    with ra.locked("antenna_db"):
        db = load_db()
        for e in db["antennas"]:
            if str(e.get("id")) == entry_id:
                if e.get("identity") != ident and not ra.is_sysop(ident):
                    return False, "You can only delete your own entries."
                db["antennas"].remove(e)
                ra.save_json(ra.data_path(DB_FILE), db)
                return True, "Deleted."
    return False, "That entry is already gone."


def show_entry(e, ident, page, q):
    out = ["{} {} - {}".format(ra.dim("#{}".format(e.get("id", "?"))), ra.bold(e.get("brand", "?")), ra.esc(e.get("band", "?")))]
    out.append(kv("Type", e.get("type", "?")))
    for key, label in (("radiator", "Radiator"), ("tap", "Tap"), ("notes", "Notes")):
        if e.get(key):
            out.append(kv(label, e[key]))
    line = kv("By", e.get("author", e.get("submitter", "?")))
    if ident and (e.get("identity") == ident or ra.is_sysop(ident)):
        line += "  " + back_link("delete", "db", act="del", id=e.get("id", ""), p=page, q=q)
    return out + [line, ""]


def view_db(ident):
    q = ra.field("q") or ra.var("q")
    q = q.replace("|", " ").replace("`", " ").replace("=", " ").strip()
    out = [ra.heading("Antenna database")]
    if ra.var("act") == "del":
        ok, note = delete_entry(ident, ra.var("id")) if ident else (False, "Identify to this node to delete.")
        out += [ra.color(note, ra.C_OK if ok else ra.C_WARN), ""]
    out += ["Search: {}".format(ra.input_field("q", 20, q)), ra.submit("Search", "antenna", "q", v="db"), ""]

    items = sorted(load_db()["antennas"], key=lambda e: e.get("id", 0), reverse=True)
    if q:
        ql = q.lower()
        items = [e for e in items if ql in " ".join(str(e.get(k, "")) for k in ("brand", "type", "band", "notes", "radiator")).lower()]
        out.append(ra.dim("{} match{} for '{}'".format(len(items), "" if len(items) == 1 else "es", q)))
    out += [back_link("Add an entry", "add"), back_link("Popular antennas", "popular"), ""]
    if not items:
        out.append("Nothing here yet." if not q else "No matches.")
        return out + [ra.nav(("Antenna menu", "antenna"))]

    pages = (len(items) + PER_PAGE - 1) // PER_PAGE
    page = min(max(ra.int_var("p", 1), 1), pages)
    for e in items[(page - 1) * PER_PAGE:page * PER_PAGE]:
        out += show_entry(e, ident, page, q)
    out.append(ra.dim("Page {} of {}".format(page, pages)))
    pager = []
    if page > 1:
        pager.append(back_link("< Newer", "db", p=page - 1, q=q))
    if page < pages:
        pager.append(back_link("Older >", "db", p=page + 1, q=q))
    return out + [ra.nav(*(pager + [("Antenna menu", "antenna")]))]


def view_add(ident):
    out = [ra.heading("Add an antenna")]
    if not ident:
        return out + ["Identify to this node to add entries.", ra.dim("Reading is open to everyone."),
                      ra.nav(back_link("Database", "db"))]
    if ra.var("act") == "save":
        ok, note = add_entry(ident)
        out += [ra.color(note, ra.C_OK if ok else ra.C_WARN), ""]
        if ok:
            return out + [ra.nav(back_link("Database", "db"))]
    out += [ra.dim("Posting as {}".format(ra.display_name(ident))), "",
            "Brand/model (required)", ra.input_field("brand", 30, ra.field("brand")), "",
            "Type: Portable, Base, Mobile or QRP", ra.input_field("type", 10, ra.field("type")), "",
            "Band (40m, 20m, multi)", ra.input_field("band", 10, ra.field("band")), "",
            "Radiator length (16.5 ft, 5.1 m)", ra.input_field("radiator", 16, ra.field("radiator")), "",
            "Tap/coil position (tap 3, 75%)", ra.input_field("tap", 16, ra.field("tap")), "",
            "Notes (optional)", ra.input_field("notes", 40, ra.field("notes")), "",
            ra.submit("Add", "antenna", "brand|type|band|radiator|tap|notes", v="add", act="save")]
    return out + [ra.nav(back_link("Database", "db"))]


# ----------------------------------------------------------------- main ---

def render():
    ident = ra.identity()
    view = ra.var("v")
    if view == "calc":
        out = view_calc()
    elif view == "plan":
        out = view_plan()
    elif view == "formulas":
        out = view_formulas()
    elif view == "popular":
        out = view_popular()
    elif view == "db":
        out = view_db(ident)
    elif view == "add":
        out = view_add(ident)
    else:
        out = [ra.heading("Antennas"), "Calculators, band plan and a shared antenna database.", "",
               back_link("Calculators", "calc"), back_link("US band plan", "plan"),
               back_link("Formulas", "formulas"), back_link("Antenna database", "db"),
               back_link("Popular portable antennas", "popular"), ra.nav()]
    return "\n".join(out)


if __name__ == "__main__":
    ra.run(render)
