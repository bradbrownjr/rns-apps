"""
HTML to plain text for rns-apps (stdlib only): feed descriptions and
readable article text.

Version: 1.0
Author: Brad Brown Jr (KC1JMH)
"""

import html
import re
from html.parser import HTMLParser

VERSION = "1.0"

SKIP = {"script", "style", "noscript", "nav", "footer", "aside", "header", "form", "svg", "iframe", "button", "figure"}
BLOCK = {"p", "div", "br", "li", "h1", "h2", "h3", "h4", "tr", "blockquote", "pre", "section", "article"}


class _Text(HTMLParser):
    def __init__(self, article_only):
        super().__init__(convert_charrefs=True)
        self.parts, self.skip, self.in_article, self.article_only = [], 0, False, article_only
        self.saw_article = False

    def handle_starttag(self, tag, attrs):
        if tag in SKIP:
            self.skip += 1
        if tag == "article":
            self.in_article = True
            self.saw_article = True
        if tag in BLOCK:
            self.parts.append("\n")
        if tag == "li":
            self.parts.append("* ")

    def handle_endtag(self, tag):
        if tag in SKIP and self.skip:
            self.skip -= 1
        if tag in BLOCK:
            self.parts.append("\n")

    def handle_data(self, data):
        if not self.skip:
            self.parts.append(data)


def _clean(text):
    text = html.unescape(text).replace("\xa0", " ")
    lines = [" ".join(l.split()) for l in text.split("\n")]
    out = []
    for line in lines:
        if line or (out and out[-1]):
            out.append(line)
    return "\n".join(out).strip()


def strip_tags(markup):
    """Feed descriptions: drop tags, keep paragraph breaks."""
    p = _Text(False)
    p.feed(markup or "")
    return _clean("".join(p.parts))


class _Paras(HTMLParser):
    """Collects paragraph and heading text, ignoring page chrome."""

    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.out, self.cur, self.skip, self.depth = [], [], 0, 0

    def handle_starttag(self, tag, attrs):
        if tag in SKIP:
            self.skip += 1
        if tag in ("p", "h2", "h3", "li", "blockquote") and not self.skip:
            self.flush()
            self.depth = 1
            self.kind = tag

    def handle_endtag(self, tag):
        if tag in SKIP and self.skip:
            self.skip -= 1
        if tag in ("p", "h2", "h3", "li", "blockquote"):
            self.flush()

    def handle_data(self, data):
        if self.depth and not self.skip:
            self.cur.append(data)

    def flush(self):
        text = " ".join("".join(self.cur).split())
        if text and not ("<" in text and ">" in text) and (len(text.split()) >= 8 or getattr(self, "kind", "") in ("h2", "h3")):
            self.out.append(text)
        self.cur, self.depth = [], 0


def article_text(markup):
    """Readable text of a web page: its paragraphs and sub-headings."""
    markup = markup or ""
    m = re.search(r"<article\b.*?</article>", markup, re.S | re.I)
    best = ""
    for chunk in ([m.group(0)] if m else []) + [markup]:
        p = _Paras()
        p.feed(chunk)
        p.flush()
        text = "\n\n".join(p.out)
        if len(text) > 400:
            return text
        best = best or text
    return best
