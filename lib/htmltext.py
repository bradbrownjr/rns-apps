"""
HTML to plain text for rns-apps (stdlib only): feed descriptions and
readable article text.

Version: 1.1
Author: Brad Brown Jr (KC1JMH)
"""

import html
import re
from html.parser import HTMLParser
from urllib.parse import urljoin

VERSION = "1.1"

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


class _Micron(HTMLParser):
    """HTML -> micron-ish lines with inline links, for the WWW browser."""

    SKIP_TAGS = {"script", "style", "noscript", "svg", "iframe", "button", "select", "textarea", "head", "template"}

    def __init__(self, base, link_fn, esc):
        super().__init__(convert_charrefs=True)
        self.base, self.link_fn, self.esc = base, link_fn, esc
        self.lines, self.cur, self.skip = [], [], 0
        self.href, self.label, self.heading, self.in_pre = None, [], 0, False

    def flush(self):
        text = "".join(self.cur)
        if text.strip():
            text = " ".join(text.split()) if not self.in_pre else text.rstrip()
            self.lines.append((">" * self.heading + text) if self.heading else text)
        self.cur = []

    def handle_starttag(self, tag, attrs):
        if tag in self.SKIP_TAGS:
            self.skip += 1
            return
        if self.skip:
            return
        if tag in ("p", "div", "br", "li", "tr", "ul", "ol", "blockquote", "table", "section", "article", "hr"):
            self.flush()
            if tag == "li":
                self.cur.append("* ")
            if tag == "hr":
                self.lines.append("-")
        elif tag in ("h1", "h2", "h3", "h4", "h5", "h6"):
            self.flush()
            self.heading = min(int(tag[1]), 3)
        elif tag == "pre":
            self.flush()
            self.in_pre = True
        elif tag == "a":
            href = dict(attrs).get("href")
            if href and not href.startswith(("#", "javascript:", "mailto:", "tel:")):
                self.href, self.label = urljoin(self.base, href), []

    def handle_endtag(self, tag):
        if tag in self.SKIP_TAGS:
            self.skip = max(self.skip - 1, 0)
            return
        if self.skip:
            return
        if tag in ("p", "div", "li", "tr", "blockquote", "table", "ul", "ol", "section", "article"):
            self.flush()
        elif tag in ("h1", "h2", "h3", "h4", "h5", "h6"):
            self.flush()
            self.heading = 0
        elif tag == "pre":
            self.flush()
            self.in_pre = False
        elif tag == "a" and self.href is not None:
            label = " ".join("".join(self.label).split())
            if label:
                self.cur.append(self.link_fn(label, self.href))
            self.href = None

    def handle_data(self, data):
        if self.skip:
            return
        if self.href is not None:
            self.label.append(data)
        else:
            self.cur.append(self.esc(data) if not self.in_pre else self.esc(data))


def to_micron(markup, base_url, link_fn, esc, max_lines=2000):
    """Render a page as micron lines. link_fn(label, absolute_url) -> micron link;
    esc escapes plain text."""
    p = _Micron(base_url, link_fn, esc)
    p.feed(markup or "")
    p.flush()
    lines, blank = [], False
    for line in p.lines:
        if not line.strip():
            if not blank:
                lines.append("")
            blank = True
        else:
            lines.append(line)
            blank = False
    return lines[:max_lines]
