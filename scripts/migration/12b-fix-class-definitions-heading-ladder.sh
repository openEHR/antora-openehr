#!/usr/bin/env bash
# Step 12b: Fix AsciiDoc heading ladder for *class_definitions partials that embed
# ROOT partial$classes includes (e.g. constraint_model-class_definitions.adoc).
#
# Problem: partial opens with "= Class Definitions" and is included from an *overview
# page with [leveloffset=+1], while nested class fragments use "=== …". AsciiDoctor then
# warns "section title out of sequence: expected level 2, got level 3".
#
# Fix: promote the partial top heading to "== Class Definitions" and include it without
# leveloffset so "===" class sections nest under "= Constraint Model Package" correctly.
#
# Usage: 12b-fix-class-definitions-heading-ladder.sh <COMPONENT_NAME> <module> ...
set -euo pipefail

COMPONENT_NAME="$1"
shift
MODULES="$@"

echo "Step 12b: Fixing class_definitions partial / overview include heading ladder..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

fix_module() {
  local module="$1"
  local partials_dir="modules/$module/partials"
  local pages_dir="modules/$module/pages"

  [ -d "$partials_dir" ] || return 0

  local p base f
  shopt -s nullglob
  for p in "$partials_dir"/*class_definitions.adoc; do
    [ -f "$p" ] || continue
    grep -q 'include::ROOT:partial\$classes/' "$p" 2>/dev/null || continue
    if ! grep -q '^= Class Definitions[[:space:]]*$' "$p"; then
      continue
    fi

    echo "  • $module: $(basename "$p") — promote '= Class Definitions' to '=='"
    sed -i 's/^= Class Definitions$/== Class Definitions/' "$p"

    base=$(basename "$p" .adoc)
    [ -d "$pages_dir" ] || continue
    for f in "$pages_dir"/*.adoc; do
      [ -f "$f" ] || continue
      if grep -qF "include::partial\$${base}.adoc[leveloffset=+1]" "$f"; then
        echo "  • $module: $(basename "$f") — strip [leveloffset=+1] for ${base} include"
        sed -i 's|include::partial\$'"${base}"'\.adoc\[leveloffset=+1\]|include::partial\$'"${base}"'.adoc[]|g' "$f"
      fi
    done
  done
  shopt -u nullglob
}

# fix_class_include_offsets <file>
#   Lowers the leveloffset of an `include::ROOT:partial$classes/X.adoc[...]` whose class heading
#   would land more than one level below the section it is included in, within the same file. PROC module
#   partials (= Plan Structure / == Lifecycle State) included class partials (=== X Class)
#   with [leveloffset=+1], one level too deep ("expected level 3, got level 4").
fix_class_include_offsets() {
  local f="$1"
  grep -q 'include::ROOT:partial\$classes/' "$f" 2>/dev/null || return 0
  awk -v classes_dir="modules/ROOT/partials/classes" '
    function class_level(name,   file, line, n) {
      file = classes_dir "/" name
      while ((getline line < file) > 0) {
        sub(/\r$/, "", line)
        if (line ~ /^=+ /) { close(file); match(line, /^=+/); return RLENGTH - 1 }
      }
      close(file); return -1
    }
    {
      raw = $0; sub(/\r$/, "", raw); cr = ($0 ~ /\r$/) ? "\r" : ""
      if (raw ~ /^(----|\.\.\.\.|````)/) { inblock = !inblock }
      if (!inblock && raw ~ /^=+ [^=]/) { match(raw, /^=+/); section = RLENGTH - 1 }
      if (!inblock && section != "" && match(raw, /^include::ROOT:partial\$classes\/[^[]+\[[^]]*\]$/)) {
        name = raw; sub(/^include::ROOT:partial\$classes\//, "", name); sub(/\[.*$/, "", name)
        attrs = raw; sub(/^[^[]*\[/, "", attrs); sub(/\]$/, "", attrs)
        lvl = class_level(name)
        cur = 0
        if (match(attrs, /leveloffset=[+-]?[0-9]+/)) { cur = substr(attrs, RSTART + 12, RLENGTH - 12) + 0 }
        # Only a class that lands more than one level below its section is moved up.
        if (lvl >= 0 && lvl + cur > section + 1) {
          off = section + 1 - lvl
          gsub(/(^|,)[[:space:]]*leveloffset=[^,]*/, "", attrs); sub(/^,/, "", attrs)
          if (off != 0) attrs = "leveloffset=" (off > 0 ? "+" : "") off (attrs != "" ? "," attrs : "")
          new = "include::ROOT:partial$classes/" name "[" attrs "]"
          if (new != raw) changed = 1
          print new cr
          next
        }
      }
      print
    }
    END { exit changed ? 0 : 3 }' "$f" > "${f}.tmp" && mv -f "${f}.tmp" "$f" || rm -f "${f}.tmp"
}

for module in $MODULES; do
  fix_module "$module"
  for f in modules/"$module"/pages/*.adoc modules/"$module"/partials/*.adoc; do
    [ -f "$f" ] && fix_class_include_offsets "$f"
  done
done

echo ""
echo "✓ Class definitions heading ladder step finished"
