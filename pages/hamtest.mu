#!/usr/bin/env python3
"""
Ham radio license practice exams (port of bpq-apps hamtest.py).

Technician and General: 35 questions, Extra: 50, one drawn from each
question-pool group (T1A, T1B, ...), pass at 74%. There is also a 10-question
practice mode with feedback after every answer.

Pages run per request with no session, so the exam is rebuilt each time from
a seed (var s) and the answers so far (var a, one letter per question). That
works for anonymous visitors. Identified visitors also get their best exam
score per class recorded under their handle.

Pools: NCVEC question pools, data/question_pools/*.json.

Version: 1.0
Author: Brad Brown Jr (KC1JMH)
"""

import os
import random
import sys
import time
from collections import defaultdict

sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.realpath(__file__))), "lib"))
import rnsapps as ra  # noqa: E402

VERSION = "1.0"
LOCATOR = "https://www.arrl.org/find-an-amateur-radio-license-exam-session"
SCORES = "hamtest_scores.json"
PRACTICE_N = 10
LETTERS = "ABCD"

LEVELS = {
    "t": {"name": "Technician", "file": "technician.json", "questions": 35, "pass": 26},
    "g": {"name": "General", "file": "general.json", "questions": 35, "pass": 26},
    "e": {"name": "Amateur Extra", "file": "extra.json", "questions": 50, "pass": 37},
}


def load_pool(level):
    path = os.path.join(ra.APP_ROOT, "data", "question_pools", LEVELS[level]["file"])
    return ra.load_json(path, [])


def build(level, mode, seed):
    """Deterministic question list for (level, mode, seed). Each item is a dict
    with 'q', 'answers' (shuffled) and 'right' (index into answers)."""
    pool = load_pool(level)
    rng = random.Random("{}{}{}".format(level, mode, seed))
    if mode == "p":
        picked = rng.sample(pool, min(PRACTICE_N, len(pool)))
    else:
        groups = defaultdict(list)
        for q in pool:
            groups[q["id"][:3]].append(q)
        picked = [rng.choice(groups[g]) for g in sorted(groups)][:LEVELS[level]["questions"]]
        rng.shuffle(picked)
    out = []
    for q in picked:
        order = list(range(len(q["answers"])))
        rng.shuffle(order)
        out.append({
            "id": q["id"],
            "q": q["question"],
            "answers": [q["answers"][i] for i in order],
            "right": order.index(q["correct"]),
        })
    return out


def menu():
    ident = ra.identity()
    scores = ra.load_json(ra.data_path(SCORES), {}).get(ident, {}) if ident else {}
    seed = int(time.time()) % 1000000
    out = [ra.heading("Ham Test"),
           "Practice exams from the current question pools. Pass mark is 74%.",
           ""]
    for key, spec in LEVELS.items():
        out.append(ra.bold(spec["name"]))
        out.append("{} questions, {} to pass".format(spec["questions"], spec["pass"]))
        out.append("{}   {}".format(ra.link("Take exam", "hamtest", x=key, m="e", s=seed),
                                    ra.link("Practice {}".format(PRACTICE_N), "hamtest", x=key, m="p", s=seed)))
        best = scores.get(spec["name"])
        if best:
            out.append(ra.dim("Your best: {}/{} ({} {})".format(best["best"], spec["questions"], best["attempts"], "try" if best["attempts"] == 1 else "tries")))
        out.append("")
    out += [ra.dim("Exam: no feedback until the end. Practice: answer shown after each question."),
            ra.dim("Nothing needs registering; sign in only to keep your best scores."),
            ra.nav()]
    return "\n".join(out)


def record(ident, level, seed, score):
    spec = LEVELS[level]
    with ra.locked("hamtest"):
        data = ra.load_json(ra.data_path(SCORES), {})
        rec = data.setdefault(ident, {}).setdefault(spec["name"], {"best": 0, "attempts": 0, "last_seed": None})
        if rec["last_seed"] == seed:  # page reload
            return
        rec["attempts"] += 1
        rec["best"] = max(rec["best"], score)
        rec["last_seed"] = seed
        ra.save_json(ra.data_path(SCORES), data)


def feedback(prev, letter):
    ok = LETTERS.index(letter) == prev["right"]
    if ok:
        return [ra.color("Correct!", ra.C_OK), ""]
    return [ra.color("Wrong. You chose {}.".format(letter), ra.C_WARN),
            "Answer: {}) {}".format(LETTERS[prev["right"]], ra.esc(prev["answers"][prev["right"]])), ""]


def finish(level, mode, seed, qs, picks):
    spec = LEVELS[level]
    score = sum(1 for q, p in zip(qs, picks) if LETTERS.index(p) == q["right"])
    total = len(qs)
    out = [ra.heading("Results - {}".format(spec["name"]))]
    if mode == "p":
        out += ["Practice score: {}".format(ra.bold("{}/{}".format(score, total))), ""]
    else:
        passed = score >= spec["pass"]
        pct = 100 * score // total
        out += ["Score: {} ({}%)".format(ra.bold("{}/{}".format(score, total)), pct),
                "Need {} to pass.".format(spec["pass"])]
        if passed:
            out += [ra.color("PASSED!", ra.C_OK), "",
                    "Ready for the real thing? Find an exam session:", LOCATOR, ""]
        else:
            out += [ra.color("Not yet - {} more correct needed.".format(spec["pass"] - score), ra.C_WARN), ""]
        ident = ra.identity()
        if ident:
            record(ident, level, seed, score)
    missed = [(q, p) for q, p in zip(qs, picks) if LETTERS.index(p) != q["right"]]
    if missed:
        out.append(ra.heading("Missed", 2))
        for q, p in missed[:12]:
            out += [ra.dim(q["id"]), ra.esc(q["q"]),
                    "You: {}) {}".format(p, ra.esc(q["answers"][LETTERS.index(p)])),
                    "Right: {}) {}".format(LETTERS[q["right"]], ra.esc(q["answers"][q["right"]])), ""]
        if len(missed) > 12:
            out += [ra.dim("...and {} more missed.".format(len(missed) - 12)), ""]
    out.append("   ".join([ra.link("Try again", "hamtest", x=level, m=mode, s=(seed + 1) % 1000000),
                           ra.link("Ham Test menu", "hamtest")]))
    return "\n".join(out + [ra.nav()])


def render():
    level, mode = ra.var("x"), ra.var("m", "e")
    if level not in LEVELS or mode not in ("e", "p"):
        return menu()
    seed = ra.int_var("s", 0)
    picks = "".join(c for c in ra.var("a").upper() if c in LETTERS)
    qs = build(level, mode, seed)
    if not qs:
        return "\n".join([ra.heading("Ham Test"), ra.color("Question pool is missing on this node.", ra.C_WARN), ra.nav()])
    picks = picks[:len(qs)]
    if len(picks) >= len(qs):
        return finish(level, mode, seed, qs, picks)

    n = len(picks)
    q = qs[n]
    out = [ra.heading("{} - {}".format(LEVELS[level]["name"], "Practice" if mode == "p" else "Exam")),
           ra.dim("Question {} of {}".format(n + 1, len(qs))), ""]
    if mode == "p" and n:
        out += feedback(qs[n - 1], picks[-1])
    out += [ra.esc(q["q"]), ""]
    for i, text in enumerate(q["answers"]):
        out.append("{}) {}".format(LETTERS[i], ra.esc(text)))
    out += ["", "Answer: " + "  ".join(
        ra.link(LETTERS[i], "hamtest", x=level, m=mode, s=seed, a=picks + LETTERS[i]) for i in range(len(q["answers"])))]
    if n:
        out.append(ra.link("< Previous question", "hamtest", x=level, m=mode, s=seed, a=picks[:-1]))
    return "\n".join(out + [ra.nav(("Quit", "hamtest"))])


if __name__ == "__main__":
    ra.run(render)
