#!/bin/bash
set -euo pipefail

# Points class links in generated class partials at the class's own page in this
# component version, where this repo documents the class.
#
# Step 10 turns every generated class xref into a global attribute, e.g.
#   xref:{class_expr_item}[EXPR_ITEM]
# and global-vars.yml resolves each attribute to one fixed page. That is wrong when
#   - the class is documented here and the global entry points elsewhere: AM AOM1.4
#     EXPR_ITEM is on AOM1.4/assertion_package, but class_expr_item points at LANG;
#   - this is an older release: the global entry points at the latest version.
#
# For every page that includes ROOT:partial$classes/<stem>.adoc, the class anchor is
# taken from the partial's heading (`=== EXPR_ITEM Class` -> _expr_item_class). In
# ROOT partials definitions/ and effective/, `xref:{class_<name>}[` becomes
# `xref:<module>:<page>.adoc#<anchor>[` when <name> is documented here, looked up with
# the file's own prefix first (aom14., aom2., bmm3.), then without a prefix. Classes
# not documented in this repo keep the global attribute.
#
# Run from repo root (inside the target specification repo), after step 10.

CLASSES_DIR="modules/ROOT/partials/classes"

echo "Step 10b: Localising class xrefs in generated partials..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [ ! -d "$CLASSES_DIR" ]; then
  echo "No $CLASSES_DIR; skipping."
  echo ""
  exit 0
fi

MAP_FILE="$(mktemp)"
trap 'rm -f "$MAP_FILE"' EXIT

# class_stems_of <file> <module> <depth>
#   Class partial stems a file includes, directly or through the module partials it
#   includes (PROC pages include partial$2-definition_plan.adoc, which includes the classes).
class_stems_of() {
  local file="$1" module="$2" depth="$3" p
  grep -oE 'include::ROOT:partial\$classes/[^[]+\.adoc' "$file" 2>/dev/null \
    | sed -E 's#^.*classes/##; s#\.adoc$##' || true
  [ "$depth" -gt 0 ] || return 0
  while IFS= read -r p; do
    [ -f "modules/${module}/partials/${p}" ] && class_stems_of "modules/${module}/partials/${p}" "$module" $((depth - 1))
  done < <(grep -oE 'include::partial\$[^[]+\.adoc' "$file" 2>/dev/null | sed -E 's#^include::partial\$##' || true)
}

# Map: <stem> TAB <module>:<page>.adoc#<anchor>
while IFS= read -r page; do
  module="${page#modules/}"
  module="${module%%/*}"
  rel="${page#modules/${module}/pages/}"
  while IFS= read -r stem; do
    partial="${CLASSES_DIR}/${stem}.adoc"
    [ -f "$partial" ] || continue
    anchor="$(awk '
      /^=+ .* (Class|Enumeration|Interface)[[:space:]]*$/ {
        sub(/^=+ /, ""); sub(/[[:space:]]+$/, "")
        id = tolower($0); gsub(/[^a-z0-9]+/, "_", id); sub(/_+$/, "", id)
        print "_" id; exit
      }' "$partial")"
    [ -n "$anchor" ] || continue
    printf '%s\t%s:%s#%s\n' "$stem" "$module" "$rel" "$anchor" >> "$MAP_FILE"
  done < <(class_stems_of "$page" "$module" 2)
done < <(find modules -path '*/pages/*' -name '*.adoc' 2>/dev/null | sort)

if [ ! -s "$MAP_FILE" ]; then
  echo "No pages include class partials; skipping."
  echo ""
  exit 0
fi

# First page wins when a class partial is included on several pages.
sort -t $'\t' -k1,1 -s -u -o "$MAP_FILE" "$MAP_FILE"

changed=0
for f in modules/ROOT/partials/definitions/*.adoc modules/ROOT/partials/effective/*.adoc; do
  [ -f "$f" ] || continue
  stem="$(basename "$f" .adoc)"
  prefix=""
  if [[ "$stem" == *.* ]]; then
    prefix="${stem%.*}."
  fi
  tmp="${f}.tmp"
  awk -v prefix="$prefix" -v mapfile="$MAP_FILE" '
    BEGIN {
      FS = "\t"
      while ((getline line < mapfile) > 0) {
        split(line, kv, "\t"); target[kv[1]] = kv[2]
      }
      FS = " "
    }
    {
      out = ""; rest = $0
      while (match(rest, /xref:\{class_[a-z0-9_]+\}\[/)) {
        name = substr(rest, RSTART + 12, RLENGTH - 14)
        key = (prefix != "" && ((prefix name) in target)) ? prefix name : name
        repl = (key in target) ? "xref:" target[key] "[" : substr(rest, RSTART, RLENGTH)
        out = out substr(rest, 1, RSTART - 1) repl
        rest = substr(rest, RSTART + RLENGTH)
      }
      print out rest
    }' "$f" > "$tmp"
  if cmp -s "$f" "$tmp"; then
    rm -f "$tmp"
  else
    mv -f "$tmp" "$f"
    changed=$((changed + 1))
  fi
done

echo "✓ Class map: $(wc -l < "$MAP_FILE") classes; localised xrefs in $changed partial(s)"
echo ""
