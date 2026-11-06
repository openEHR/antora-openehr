#!/usr/bin/env python3
"""Check class links in a built Antora site.

For every link to a class anchor (`#_<name>_class`, `_enumeration`, `_interface`) the
target page is resolved, the anchor must exist, and the heading carrying the anchor
must name the linked class (`EXPR_ITEM` -> `EXPR_ITEM Class`). htmltest only checks
that an anchor exists; this also catches links that land on a different class.

Also reported: xrefs Antora could not resolve (rendered as `#COMP:module:page.adoc#...`)
and dead `/classes/<Type>` links from bmm-publisher.

usage: scripts/check-class-links.py <site_dir> [path-prefix ...]
exit status 1 when any problem is found.
"""
import collections
import html
import os
import re
import sys
from urllib.parse import unquote, urlsplit

# Link text -> class it is meant to reach, where the two names differ on purpose.
ALIASES = {'BYTE': 'OCTET'}  # bmm-publisher links RM 1.0.x `Byte` to BASE `Octet`

A_RE = re.compile(r'<a\s+href="([^"]*)"[^>]*>(.*?)</a>', re.S)
CLASS_FRAGMENT = re.compile(r'#_[a-z0-9_]+_(?:class|enumeration|interface)$')
HEAD_RE = re.compile(r'<h[1-6][^>]*\bid="([^"]+)"[^>]*>(.*?)</h[1-6]>', re.S)
ID_RE = re.compile(r'\bid="([^"]+)"')
TAG_RE = re.compile(r'<[^>]+>')


def plain(fragment):
    return html.unescape(TAG_RE.sub('', fragment)).strip()


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        return 2
    site = sys.argv[1]
    only = tuple(sys.argv[2:])
    cache = {}

    def page_info(path):
        if path not in cache:
            try:
                s = open(path, encoding='utf-8').read()
            except OSError:
                cache[path] = None
            else:
                heads = {m.group(1): plain(m.group(2)) for m in HEAD_RE.finditer(s)}
                cache[path] = (set(ID_RE.findall(s)), heads)
        return cache[path]

    def resolve(page, href):
        u = urlsplit(href)
        if u.scheme or u.netloc:
            return None, u.fragment
        if not u.path:
            return page, u.fragment
        if u.path.startswith('/'):
            p = os.path.normpath(os.path.join(site, unquote(u.path).lstrip('/')))
        else:
            p = os.path.normpath(os.path.join(os.path.dirname(page), unquote(u.path)))
        if os.path.isdir(p) or u.path.endswith('/'):
            p = os.path.join(p, 'index.html')
        return p, u.fragment

    stats = collections.Counter()
    problems = collections.Counter()
    examples = {}
    for root, _, files in os.walk(site):
        for fn in files:
            if fn != 'index.html':
                continue
            page = os.path.join(root, fn)
            rel = os.path.relpath(page, site).replace(os.sep, '/')
            if only and not rel.startswith(only):
                continue
            s = open(page, encoding='utf-8').read()
            for m in A_RE.finditer(s):
                href, text = m.group(1), plain(m.group(2))
                if href.startswith('/classes/'):
                    kind = 'dead /classes/ link'
                elif not CLASS_FRAGMENT.search(href):
                    continue
                elif href.startswith('#') and ':' in href[1:].split('#')[0]:
                    kind = 'unresolved xref'
                else:
                    target, fragment = resolve(page, href)
                    if target is None:
                        continue
                    info = page_info(target)
                    if info is None:
                        kind = 'target page missing'
                    elif fragment not in info[0]:
                        kind = 'anchor missing'
                    else:
                        head = info[1].get(fragment)
                        name = re.sub(r'<.*', '', text).strip().upper()
                        name = ALIASES.get(name, name)
                        if head is None or ' ' in name or head.upper().split()[0] == name:
                            kind = 'OK'  # anchor not on a heading, or prose link text
                        else:
                            kind = 'wrong class'
                stats[kind] += 1
                if kind != 'OK':
                    comp = '/'.join(rel.split('/')[:2])
                    problems[(kind, comp)] += 1
                    examples.setdefault((kind, comp), (text, href))

    for kind, n in sorted(stats.items(), key=lambda x: -x[1]):
        print(f'{n:7} {kind}')
    if problems:
        print('--- problems by component (first example)')
        for (kind, comp), n in sorted(problems.items(), key=lambda x: -x[1]):
            text, href = examples[(kind, comp)]
            print(f'{n:6} {kind:20} {comp:24} {text} -> {href[:100]}')
    return 1 if problems else 0


if __name__ == '__main__':
    sys.exit(main())
