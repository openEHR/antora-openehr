#!/usr/bin/env bash
# Resolve every *prose* section reference in the spec against the headings that
# actually exist.
#
# Antora already fails the build on a broken `xref:` macro (antora-playbook.yml
# runs with failure_level: warn). Nothing checks a bare prose reference like
# "§27" or "§B.7", nor a §number that appears only in an xref's *link text* —
# which is exactly why four such defects shipped in v0.3. This script is the
# missing half of that gate; run it before opening a PR (see CONTRIBUTING.md).
#
# Emits one line per unresolved reference and exits non-zero if any are found.
#
# Originally written for the UNIO implementation review of v0.3 and vendored
# here so the check runs in this repository's CI.

set -uo pipefail

SPEC="${SPEC_REPO:-$(git rev-parse --show-toplevel)}"
PAGES="${SPEC_PAGES:-$SPEC/modules/ROOT/pages}"

# --- the set of section numbers that actually exist -------------------------
# Headings look like "== 11.6.2 Offset" / "= 14. Localization" / "== B.5 ...".
existing=$(grep -hoE '^=+ (B\.)?[0-9]+[a-z]?(\.[0-9]+)*' "$PAGES"/*.adoc \
           | sed -E 's/^=+ //; s/\.$//' | sort -u)

exists() { grep -qxF "$1" <<<"$existing"; }

# --- every prose §-reference ------------------------------------------------
# Matches §11.2, §7a.2, §B.7, §12b.2, and ranges' individual members.
#
# Excluded as out-of-document by construction: a reference qualified by a named
# external source immediately before it — "advisory §3.1.2.1", "RFC 7523 §3.1",
# "MPI advisory §3". These are correct citations of another document, not
# dangling self-references. The exclusion is deliberately keyed on the
# qualifier word, because an *unqualified* "§4.5" in a document whose sections
# stop at §21 is precisely the defect being hunted.
unresolved=0
while IFS=: read -r file line ref; do
    num=${ref#§}
    num=${num%.}
    exists "$num" && continue
    printf '%s:%s  unresolved prose reference §%s\n' "$(basename "$file")" "$line" "$num"
    unresolved=$((unresolved + 1))
done < <(
    grep -onE '§[0-9B][0-9a-zA-Z.]*' "$PAGES"/*.adoc \
    | awk -F: '{
        # drop RFC-external refs: "RFC 7523 §3.1" and friends
        print $1":"$2":"$3
      }' \
    | while IFS=: read -r f l r; do
        ctx=$(sed -n "${l}p" "$f")
        # An external qualifier directly before the § makes it another
        # document's section number, not ours.
        if grep -qE "(advisory|RFC [0-9]+|IG|profile|standard|ISO|IHE)[^.]{0,12}${r//./\\.}" <<<"$ctx"; then
            continue
        fi
        printf '%s:%s:%s\n' "$f" "$l" "$r"
      done
)

echo "---"
if [ "$unresolved" -eq 0 ]; then
    echo "all prose § references resolve"
else
    echo "$unresolved unresolved prose § reference(s)"
fi
exit $(( unresolved > 0 ))
