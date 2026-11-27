#!/usr/bin/env bash
# Resolve every in-page anchor link in the *built* site.
#
# The third gap in the reference gate. Antora fails the build when an `xref:`
# names a page that does not exist, and tools/check-refs.sh catches a prose
# "§n.n" with no matching heading - but neither checks that the *fragment* of
# an xref resolves to an anchor that exists. `xref:conformance.adoc#cp-99[]`
# builds clean today and lands the reader at the top of the page.
#
# Runs against build/site, so `npm run build` must have run first.

set -uo pipefail

SPEC="${SPEC_REPO:-$(git rev-parse --show-toplevel)}"
SITE="${1:-$SPEC/build/site}"

if [ ! -d "$SITE" ]; then
    echo "no built site at $SITE - run 'npm run build' first" >&2
    exit 2
fi

python3 - "$SITE" <<'PY'
import re, sys, glob, os

site = sys.argv[1]
pages = glob.glob(os.path.join(site, '**', '*.html'), recursive=True)

ids = {p: set(re.findall(r'id="([^"]+)"', open(p, encoding='utf-8').read())) for p in pages}

bad = 0
for p in pages:
    src = open(p, encoding='utf-8').read()
    for href in re.findall(r'href="([^"]*#[^"]+)"', src):
        if href.startswith(('http://', 'https://', 'mailto:')):
            continue
        page, _, frag = href.partition('#')
        target = os.path.normpath(os.path.join(os.path.dirname(p), page)) if page else p
        # html_extension_style: indexify links a page as its directory ("../foo/").
        if os.path.isdir(target):
            target = os.path.join(target, 'index.html')
        if target not in ids:
            # A link to a page outside the built component (or a generated UI
            # page) is not this check's business.
            continue
        if frag not in ids[target]:
            print(f"{os.path.relpath(p, site)}  ->  {href}  (no such anchor)")
            bad += 1

print("---")
print("all in-page anchors resolve" if not bad else f"{bad} dangling anchor link(s)")
sys.exit(1 if bad else 0)
PY
