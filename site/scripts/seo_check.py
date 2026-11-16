#!/usr/bin/env python3
"""SEO, AEO and base-path gates over the static export (site/out).

A smaller port of the sibling docs site's gate (nestjs-drizzle-crud/apps/docs/scripts/seo_check.py),
which follows avytrix.dev's. This site is served under a path prefix on avytrix.dev, so it also
checks that every link and asset carries that prefix and resolves to a file in out/.

Per page: a unique title of at most 60 characters ending in " | vela"; a unique description of 120
to 160 characters and at most 990px wide in Arial 14px; exactly one <h1> and no skipped heading
level; a self-referencing canonical of origin + base path + route, with no trailing slash; og:url
equal to the canonical; html lang="en"; images with alt, width and height; exactly one JSON-LD
block holding one @graph with no duplicate @id; no em or en dash in text, title or description.

Site wide: every internal href and src starts with the base path and resolves to a file in out/,
and every #anchor on a docs link exists on the target page; sitemap.xml lists exactly the
indexable pages at their canonicals; llms.txt links only to pages and has no dash; there is no
robots.txt (avytrix.dev serves its own).

Usage (from site/): python3 scripts/seo_check.py out   (exits 1 on any failure)
NEXT_PUBLIC_SITE_URL (origin) and NEXT_PUBLIC_BASE_PATH default to production, like the build.
"""
import json
import os
import re
import sys
from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import unquote, urlsplit

ORIGIN = (os.environ.get("NEXT_PUBLIC_SITE_URL") or "https://avytrix.dev").rstrip("/")
BASE = os.environ.get("NEXT_PUBLIC_BASE_PATH", "/opensource/gitlab-vela").rstrip("/")
ROOT = ORIGIN + BASE
SUFFIX = " | vela"
DASHES = re.compile("[\u2013\u2014]")  # en dash, em dash
GENERIC_ANCHORS = {"click here", "here", "read more", "link", "more", "learn more"}

# Arial 14px advance widths, as in the sibling gate. Unknown characters count as "M".
ARIAL14 = {' ': 3.89, '!': 3.89, '"': 4.97, '#': 7.78, '$': 7.78, '%': 12.45, '&': 9.34, "'": 2.67, '(': 4.66, ')': 4.66, '*': 5.45, '+': 8.17, ',': 3.89, '-': 4.66, '.': 3.89, '/': 3.89, '0': 7.78, '1': 7.78, '2': 7.78, '3': 7.78, '4': 7.78, '5': 7.78, '6': 7.78, '7': 7.78, '8': 7.78, '9': 7.78, ':': 3.89, ';': 3.89, '<': 8.17, '=': 8.17, '>': 8.17, '?': 7.78, '@': 14.22, 'A': 9.34, 'B': 9.34, 'C': 10.11, 'D': 10.11, 'E': 9.34, 'F': 8.55, 'G': 10.89, 'H': 10.11, 'I': 3.89, 'J': 7.0, 'K': 9.34, 'L': 7.78, 'M': 11.66, 'N': 10.11, 'O': 10.89, 'P': 9.34, 'Q': 10.89, 'R': 10.11, 'S': 9.34, 'T': 8.55, 'U': 10.11, 'V': 9.34, 'W': 13.22, 'X': 9.34, 'Y': 9.34, 'Z': 8.55, '[': 3.89, '\\': 3.89, ']': 3.89, '^': 6.56, '_': 7.78, '`': 4.66, 'a': 7.78, 'b': 7.78, 'c': 7.0, 'd': 7.78, 'e': 7.78, 'f': 3.89, 'g': 7.78, 'h': 7.78, 'i': 3.11, 'j': 3.11, 'k': 7.0, 'l': 3.11, 'm': 11.66, 'n': 7.78, 'o': 7.78, 'p': 7.78, 'q': 7.78, 'r': 4.66, 's': 7.0, 't': 3.89, 'u': 7.78, 'v': 7.0, 'w': 10.11, 'x': 7.0, 'y': 7.0, 'z': 7.0, '{': 4.67, '|': 3.64, '}': 4.67, '~': 8.17}


class Page(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.title, self.lang, self.canonical = "", None, None
        self.meta, self.ld, self.headings, self.imgs, self.anchors = {}, [], [], [], []
        self.links, self.ids, self.text = [], set(), []  # links: (attr, value)
        self._stack, self._buf = [], {}

    def handle_starttag(self, tag, attrs):
        a = dict(attrs)
        if a.get("id"):
            self.ids.add(a["id"])
        for attr in ("href", "src"):
            if a.get(attr) and not (tag == "link" and a.get("rel") == "canonical"):
                self.links.append((tag, a[attr]))
        if tag == "html":
            self.lang = a.get("lang")
        elif tag == "meta" and (a.get("name") or a.get("property")):
            self.meta[a.get("name") or a.get("property")] = a.get("content", "")
        elif tag == "link" and a.get("rel") == "canonical":
            self.canonical = a.get("href")
        elif tag == "img":
            self.imgs.append(a)
        elif tag == "script" and a.get("type") == "application/ld+json":
            self._stack.append("ld")
        elif tag in ("script", "style", "title", "template", "a") or re.fullmatch(r"h[1-6]", tag):
            self._stack.append(tag)
            if tag == "a":
                self._buf["a_label"] = a.get("aria-label", "")

    def handle_endtag(self, tag):
        if not self._stack:
            return
        top = self._stack[-1]
        if top == "ld" and tag == "script":
            self.ld.append(self._buf.pop("ld", ""))
        elif top != tag:
            return
        elif tag == "title":
            self.title = self._buf.pop("title", "").strip()
        elif tag == "a":
            self.anchors.append(self._buf.pop("a", "").strip() or self._buf.get("a_label", ""))
        elif tag.startswith("h"):
            self.headings.append(int(tag[1]))
        self._buf.pop(tag, None)
        self._stack.pop()

    def handle_data(self, data):
        top = self._stack[-1] if self._stack else None
        if top in ("script", "style", "template"):
            return
        if top:
            self._buf[top] = self._buf.get(top, "") + data
        if top not in ("ld", "title"):
            self.text.append(data)


def norm(s):
    return re.sub(r"\s+", " ", s).strip()


def url_for(out, f):
    rel = f.relative_to(out).as_posix()
    rel = "" if rel == "index.html" else "/" + rel.removesuffix(".html")
    return ROOT + rel


def resolve(out, path):
    """The file in out/ that the host would serve for a same-site path, or None."""
    if path != BASE and not path.startswith(BASE + "/"):
        return None
    rel = unquote(path[len(BASE):]).lstrip("/")
    candidates = [out / rel / "index.html"] if rel == "" else [out / rel, out / f"{rel}.html"]
    return next((c for c in candidates if c.is_file()), None)


def check(out):
    errors, pages = [], {}
    for f in sorted(out.rglob("*.html")):
        rel = f.relative_to(out).parts
        if f.name in ("404.html", "_not-found.html") or rel[0] in ("_next", "_not-found"):
            continue
        p = Page()
        p.feed(f.read_text(encoding="utf-8"))
        pages[url_for(out, f)] = (f, p)

    seen = {"title": {}, "description": {}}
    for url, (f, p) in pages.items():
        e = lambda msg: errors.append(f"{url}: {msg}")
        if not p.title or len(p.title) > 60:
            e(f"title length {len(p.title)} (max 60): {p.title!r}")
        if not p.title.endswith(SUFFIX):
            e(f"title does not end with {SUFFIX.strip()!r}: {p.title!r}")
        desc = p.meta.get("description", "")
        if not 120 <= len(desc) <= 160:
            e(f"description length {len(desc)} (120 to 160): {desc!r}")
        if (px := sum(ARIAL14.get(c, ARIAL14["M"]) for c in desc)) > 990:
            e(f"description {px:.0f}px wide (max 990, Arial 14px)")
        for key, val in (("title", p.title), ("description", desc)):
            seen[key].setdefault(val, []).append(url)
        if p.canonical != url:
            e(f"canonical {p.canonical!r}, expected {url!r}")
        if p.meta.get("og:url") != p.canonical:
            e(f"og:url {p.meta.get('og:url')!r} != canonical")
        if "noindex" in p.meta.get("robots", ""):
            e("indexable page marked noindex")
        if p.lang != "en":
            e(f"html lang={p.lang!r}")
        if p.headings.count(1) != 1:
            e(f"{p.headings.count(1)} <h1>")
        for prev, cur in zip(p.headings, p.headings[1:]):
            if cur > prev + 1:
                e(f"heading skips h{prev} to h{cur}")
                break
        for img in p.imgs:
            if not img.get("alt", "").strip() and img.get("aria-hidden") != "true":
                e(f"img without alt: {img.get('src', '')[:80]}")
            if not (img.get("width") and img.get("height")):
                e(f"img without width/height: {img.get('src', '')[:80]}")
        for label in p.anchors:
            if norm(label).lower() in GENERIC_ANCHORS:
                e(f"generic anchor text {label!r}")
        visible = norm(" ".join(p.text))
        for where, txt in (("text", visible), ("title", p.title), ("description", desc)):
            if m := DASHES.search(txt):
                e(f"dash in {where}: {txt[max(0, m.start() - 40):m.end() + 40]!r}")
        if len(p.ld) != 1:
            e(f"{len(p.ld)} ld+json blocks (expected 1)")
        for raw in p.ld:
            try:
                data = json.loads(raw)
            except json.JSONDecodeError as err:
                e(f"invalid JSON-LD: {err}")
                continue
            nodes = data.get("@graph")
            if not isinstance(nodes, list):
                e("JSON-LD has no @graph")
                continue
            ids = [n["@id"] for n in nodes if "@id" in n]
            if len(ids) != len(set(ids)):
                e(f"duplicate @id in graph: {ids}")
            for u in re.findall(r'"(?:url|item|@id)":"(https?://[^"#]+)', raw):
                if u.startswith(ROOT) and resolve(out, urlsplit(u).path) is None:
                    e(f"JSON-LD URL {u!r} does not resolve to a file in out/")

        # Every same-site href and src carries the base path and resolves to a file.
        for tag, link in p.links:
            if link == ROOT or link.startswith(ROOT + "/") or link.startswith(ROOT + "#"):
                link = link[len(ORIGIN):]  # an absolute link to this site: check it like a path
            parts = urlsplit(link)
            if not link.startswith("/") or link.startswith("//"):
                continue  # relative links are not used; nothing to resolve them against reliably
            target = resolve(out, parts.path)
            if target is None:
                e(f"{tag} {link!r} does not resolve under {BASE or '/'} in out/")
                continue
            if parts.fragment and target.suffix == ".html":
                tp = pages.get(url_for(out, target))
                if tp and unquote(parts.fragment) not in tp[1].ids:
                    e(f"link {link!r}: no #{parts.fragment} on the target page")

    for key, vals in seen.items():
        for val, urls in vals.items():
            if len(urls) > 1:
                errors.append(f"duplicate {key} {val[:60]!r} on {urls}")

    if (out / "robots.txt").exists():
        errors.append("robots.txt is emitted (avytrix.dev serves its own)")
    sm = out / "sitemap.xml"
    if not sm.exists():
        errors.append("missing sitemap.xml")
    else:
        locs = re.findall(r"<loc>(.*?)</loc>", sm.read_text())
        if len(locs) != len(set(locs)):
            errors.append("sitemap lists a URL twice")
        for loc in set(locs) - set(pages):
            errors.append(f"sitemap: {loc} is not a page")
        for url in set(pages) - set(locs):
            errors.append(f"sitemap: {url} missing")
    llms = out / "llms.txt"
    if not llms.exists():
        errors.append("missing llms.txt")
    else:
        text = llms.read_text()
        for link in re.findall(r"\]\((.*?)\)", text):
            if link not in pages:
                errors.append(f"llms.txt links to non-page {link}")
        if m := DASHES.search(text):
            errors.append(f"llms.txt has a dash: {text[max(0, m.start() - 40):m.end() + 40]!r}")
    return pages, errors


if __name__ == "__main__":
    out = Path(sys.argv[1] if len(sys.argv) > 1 else Path(__file__).resolve().parent.parent / "out")
    if not (out / "index.html").is_file():
        print(f"FAIL {out} has no index.html; run the build first")
        sys.exit(1)
    pages, errors = check(out)
    for err in errors:
        print("FAIL", err)
    print(f"{len(pages)} pages under {ROOT}, {len(errors)} failures")
    sys.exit(1 if errors else 0)
