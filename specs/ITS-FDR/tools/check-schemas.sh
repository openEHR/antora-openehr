#!/usr/bin/env bash
# Validate the specification's own JSON examples against the JSON Schemas it
# publishes.
#
# This is what makes the schemas load-bearing rather than decorative. Without
# it, modules/ROOT/attachments/*.schema.json is a third human-readable artifact
# that can disagree with the example beside it — which is exactly the defect
# that shipped in 0.3.1, where §9's example serialised `rows` as objects while
# the ITS-REST RESULT_SET it claimed conformance to defines them as arrays.
# That defect is mechanically detectable, and this script is what detects it.
#
# Strategy: extract each `[source,json]` block from the page, validate it
# against the schema that governs that page's structure. Only blocks that *are*
# a whole envelope / whole OPTIONS body are checked; fragments illustrating one
# field are skipped by the heuristic below and named in the output, so a
# silently-unchecked block is visible rather than invisible.
#
# Usage:  tools/check-schemas.sh
# Exits non-zero on the first schema failure; prints one line per block.

set -uo pipefail

SPEC="${SPEC_REPO:-$(git rev-parse --show-toplevel)}"
PAGES="${SPEC_PAGES:-$SPEC/modules/ROOT/pages}"
SCHEMAS="${SPEC_SCHEMAS:-$SPEC/modules/ROOT/attachments}"
AJV="${AJV:-$SPEC/node_modules/.bin/ajv}"

if [ ! -x "$AJV" ]; then
    echo "ajv-cli not found at $AJV — run 'npm ci' (it is a pinned devDependency)." >&2
    exit 2
fi

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# --- which page's examples validate against which schema --------------------
#
#   page.adoc : schema.json : jq-expression identifying a *whole* instance
#
# The third field is a discriminator, not a filter: a block is validated when
# the expression is true, and reported as skipped when it is false. §9's page
# carries only envelopes today, but the discriminator keeps that from being an
# assumption the next editor has to know about.
TARGETS=(
  "result-set.adoc:federated-result-set.schema.json:has(\"rows\")"
  "rest-facade.adoc:options-root.schema.json:has(\"federation\")"
)

checked=0
skipped=0
failed=0

for target in "${TARGETS[@]}"; do
    IFS=: read -r page schema discriminator <<<"$target"
    src="$PAGES/$page"

    [ -f "$src" ] || { echo "missing page: $src" >&2; exit 2; }
    [ -f "$SCHEMAS/$schema" ] || { echo "missing schema: $SCHEMAS/$schema" >&2; exit 2; }

    # Extract every [source,json] block. AsciiDoc delimits them with `----`.
    # awk state machine: 1 = saw [source,json], 2 = inside the block.
    block_count=0
    while IFS= read -r -d '' block; do
        block_count=$((block_count + 1))
        instance="$TMP/${page%.adoc}-$block_count.json"
        printf '%s' "$block" > "$instance"

        label="$page block #$block_count"

        if ! jq empty "$instance" 2>/dev/null; then
            echo "FAIL  $label — not well-formed JSON"
            failed=$((failed + 1))
            continue
        fi

        if [ "$(jq "$discriminator" "$instance")" != "true" ]; then
            echo "skip  $label — not a whole instance for $schema"
            skipped=$((skipped + 1))
            continue
        fi

        if out=$("$AJV" validate --spec=draft2020 --strict=false -c ajv-formats \
                     -s "$SCHEMAS/$schema" -d "$instance" 2>&1); then
            echo "ok    $label — validates against $schema"
            checked=$((checked + 1))
            # §9.5.1 obligations JSON Schema cannot express: row_endpoints has one
            # entry per row, and every value is an id listed in endpoints[].
            if [ "$schema" = "federated-result-set.schema.json" ] &&
               ! jq -e '(.meta.federation.row_endpoints | length) == (.rows | length)
                        and ([.meta.federation.endpoints[].id] as $ids
                             | all(.meta.federation.row_endpoints[][]; . as $v | $ids | index($v) != null))' \
                    "$instance" >/dev/null; then
                echo "FAIL  $label — row_endpoints is not aligned with rows, or names an endpoint missing from endpoints[] (§9.5.1)"
                failed=$((failed + 1))
            fi
        else
            echo "FAIL  $label — does not validate against $schema"
            printf '%s\n' "$out" | sed 's/^/        /'
            failed=$((failed + 1))
        fi
    done < <(
        awk '
            /^\[source,json\]/ { state = 1; next }
            state == 1 && /^----$/ { state = 2; buf = ""; next }
            state == 2 && /^----$/ { printf "%s%c", buf, 0; state = 0; next }
            state == 2 { buf = buf $0 "\n"; next }
            { state = 0 }
        ' "$src"
    )

    if [ "$block_count" -eq 0 ]; then
        echo "FAIL  $page — no [source,json] blocks found (extraction broken?)"
        failed=$((failed + 1))
    fi
done

# Every published schema must itself be a valid schema, not merely valid JSON.
for schema in "$SCHEMAS"/*.schema.json; do
    name=$(basename "$schema")
    if out=$("$AJV" compile --spec=draft2020 --strict=false -c ajv-formats -s "$schema" 2>&1); then
        echo "ok    $name — compiles as a draft 2020-12 schema"
    else
        echo "FAIL  $name — does not compile as a schema"
        printf '%s\n' "$out" | sed 's/^/        /'
        failed=$((failed + 1))
    fi
done

echo "---"
if [ "$failed" -eq 0 ]; then
    echo "$checked example(s) validated, $skipped skipped, 0 failures"
else
    echo "$checked example(s) validated, $skipped skipped, $failed failure(s)"
fi
exit $(( failed > 0 ))
