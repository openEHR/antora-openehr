#!/usr/bin/env bash
# Derive the N → CP → track closure from the spec and emit traceability.tsv.
#
# Computes the forward and reverse mappings in one pass, so the two cannot
# disagree by construction: a requirement's reachability and the CP/track
# tables' claims about it come from a single source.
#
# Columns: n_id | direct_cps | tracks | reachability
#   reachability: direct     — at least one CP names this N
#                 track-only — no CP, but a Connectathon track asserts it
#                 orphan     — no CP and no track: cannot be conformance-tested
#
# Usage:
#   tools/traceability.sh [OUT.tsv]       report only (exit 0)
#   tools/traceability.sh --assert [OUT]  fail if any requirement is unreachable
#                                         and not allowlisted
#
# In --assert mode a requirement may be unreachable only if it is listed in
# tools/traceability-exceptions.txt with a reason. The allowlist is the point:
# "add a conformance point, or state that it is deliberately unscored and why"
# becomes mechanical rather than a matter of remembering.
#
# Originally written for the UNIO implementation review of v0.3 and vendored
# here so the check runs in this repository's CI.

set -euo pipefail

ASSERT=0
if [ "${1:-}" = "--assert" ]; then ASSERT=1; shift; fi

SPEC="${SPEC_REPO:-$(git rev-parse --show-toplevel)}"
PAGES="${SPEC_PAGES:-$SPEC/modules/ROOT/pages}"
OUT="${1:-$(dirname "$0")/traceability.tsv}"

# All N-anchors, in spec order, as the fixed denominator.
mapfile -t NS < <(grep -oE '\[\[n[0-9]+[a-z]?\]\]' "$PAGES/requirements.adoc" \
                  | sed 's/\[\[//;s/\]\]//')

# CP -> N edges. A CP's requirement cell holds xref:requirements.adoc#nX[NX].
cp_edges() {
    awk '
      match($0, /\[\[cp-[0-9]+[a-z]?\]\]/) {
          id = substr($0, RSTART+2, RLENGTH-4); next
      }
      /xref:requirements.adoc#n/ {
          if (id == "") next
          s = $0
          while (match(s, /#n[0-9]+[a-z]?\[/)) {
              print substr(s, RSTART+1, RLENGTH-2) "\t" id
              s = substr(s, RSTART+RLENGTH)
          }
          id = ""
      }' "$PAGES/conformance.adoc"
}

# TRACK -> N edges. Track rows open with a bare '| <n>' line in the §16.3 table.
track_edges() {
    awk '
      /^\| [0-9]+$/ { t = $2 }
      /xref:requirements.adoc#n/ {
          if (t == "") next
          s = $0
          while (match(s, /#n[0-9]+[a-z]?\[/)) {
              print substr(s, RSTART+1, RLENGTH-2) "\tTRACK-" t
              s = substr(s, RSTART+RLENGTH)
          }
      }' "$PAGES/testing.adoc"
}

CPE=$(cp_edges)
TRE=$(track_edges)

printf 'n_id\tdirect_cps\ttracks\treachability\n' >"$OUT"
for n in "${NS[@]}"; do
    cps=$(grep -P "^\Q$n\E\t" <<<"$CPE" | cut -f2 | sort -uV | paste -sd';' - || true)
    trs=$(grep -P "^\Q$n\E\t" <<<"$TRE" | cut -f2 | sort -uV | paste -sd';' - || true)
    if   [ -n "$cps" ]; then reach=direct
    elif [ -n "$trs" ]; then reach=track-only
    else                     reach=orphan
    fi
    printf '%s\t%s\t%s\t%s\n' "N${n#n}" "${cps:--}" "${trs:--}" "$reach" >>"$OUT"
done

echo "wrote $OUT"
echo "  direct:     $(awk -F'\t' '$4=="direct"'     "$OUT" | wc -l)"
echo "  track-only: $(awk -F'\t' '$4=="track-only"' "$OUT" | wc -l)  $(awk -F'\t' '$4=="track-only"{printf "%s ",$1}' "$OUT")"
echo "  orphan:     $(awk -F'\t' '$4=="orphan"'     "$OUT" | wc -l)  $(awk -F'\t' '$4=="orphan"{printf "%s ",$1}'     "$OUT")"

# Reverse check: every N a CP claims must exist as an anchor. A CP naming a
# non-existent N is table drift and is itself a finding.
drift=0
echo "=== reverse check: CP-claimed N with no anchor ==="
while read -r n; do
    [ -z "$n" ] && continue
    printf '%s\n' "${NS[@]}" | grep -qx "$n" \
        || { echo "  DRIFT: CP table claims $n, no such anchor"; drift=$((drift + 1)); }
done < <(cut -f1 <<<"$CPE" | sort -u)
echo "=== reverse check: track-claimed N with no anchor ==="
while read -r n; do
    [ -z "$n" ] && continue
    printf '%s\n' "${NS[@]}" | grep -qx "$n" \
        || { echo "  DRIFT: track table claims $n, no such anchor"; drift=$((drift + 1)); }
done < <(cut -f1 <<<"$TRE" | sort -u)

[ "$ASSERT" -eq 1 ] || exit 0

# --- assert mode ------------------------------------------------------------
# An unreachable requirement is a defect unless it is allowlisted with a reason.
EXCEPTIONS="$(dirname "$0")/traceability-exceptions.txt"
allowlisted() {
    [ -f "$EXCEPTIONS" ] || return 1
    grep -qE "^[[:space:]]*$1([[:space:]]|$|—|-)" "$EXCEPTIONS"
}

failures=0
while IFS=$'\t' read -r n _ _ reach; do
    [ "$reach" = "direct" ] && continue
    if allowlisted "$n"; then
        echo "  allowed: $n ($reach) — $(grep -E "^[[:space:]]*$n([[:space:]]|—|-)" "$EXCEPTIONS" | head -1 | sed -E 's/^[^—-]*[—-][[:space:]]*//')"
    else
        echo "  FAIL: $n is $reach and not in $(basename "$EXCEPTIONS")"
        failures=$((failures + 1))
    fi
done < <(tail -n +2 "$OUT")

echo "---"
if [ "$failures" -eq 0 ] && [ "$drift" -eq 0 ]; then
    echo "traceability closure clean (unreachable requirements are allowlisted with a reason)"
    exit 0
fi
echo "$failures unallowlisted unreachable requirement(s), $drift drift error(s)"
exit 1
