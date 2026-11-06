#!/bin/bash
set -euo pipefail

# Rewrites legacy class cross-references in module pages to Antora xref macros
# using class_* attributes from global-vars.yml.
#
# Handles three patterns:
#
#   1. AsciiDoc internal refs:
#      <<_string_class,String>>  →  xref:{class_string}[String]
#
#   2. Hardcoded relative release URL links:
#      link:/releases/BASE/{base_release}/foundation_types.html#_string_class[String^]
#        →  xref:{class_string}[String]
#
#   3. Hardcoded absolute specification URLs:
#      https://specifications.openehr.org/releases/RM/latest/ehr.html#_composition_class[COMPOSITION]
#        →  xref:{class_composition}[COMPOSITION]
#
# Run from repo root (inside the target specification repo)

rewrite_xrefs_in_file() {
  local f="$1"

  # Pattern 1a: <<_foo_bar_class,Some Text>>  →  xref:{class_foo_bar}[Some Text]
  sed -i 's/<<_\([a-z0-9_]*\)_class,\([^>]*\)>>/xref:{class_\1}[\2]/g' "$f"

  # Pattern 1b: <<_foo_bar_class>>  →  xref:{class_foo_bar}[foo_bar]
  sed -i 's/<<_\([a-z0-9_]*\)_class>>/xref:{class_\1}[\1]/g' "$f"

  # Pattern 1c/1d: the same for enumerations (legacy UML class tables, step 3b)
  sed -i 's/<<_\([a-z0-9_]*\)_enumeration,\([^>]*\)>>/xref:{class_\1}[\2]/g' "$f"
  sed -i 's/<<_\([a-z0-9_]*\)_enumeration>>/xref:{class_\1}[\1]/g' "$f"

  # Pattern 2: link:/releases/.../spec.html#_foo_bar_class[Text^]  →  xref:{class_foo_bar}[Text]
  sed -i 's|link:/releases/[^#]*#_\([a-z0-9_]*\)_class\[\([^\^]*\)\^\]|xref:{class_\1}[\2]|g' "$f"

  # Pattern 2b: same but without the ^ marker
  sed -i 's|link:/releases/[^#]*#_\([a-z0-9_]*\)_class\[\([^]]*\)\]|xref:{class_\1}[\2]|g' "$f"

  # Pattern 2c: link:/releases/.../spec.html#_foo_bar_enumeration[Text^]  →  xref:{class_foo_bar}[Text]
  sed -i 's|link:/releases/[^#]*#_\([a-z0-9_]*\)_enumeration\[\([^\^]*\)\^\]|xref:{class_\1}[\2]|g' "$f"

  # Pattern 2d: same but without the ^ marker
  sed -i 's|link:/releases/[^#]*#_\([a-z0-9_]*\)_enumeration\[\([^]]*\)\]|xref:{class_\1}[\2]|g' "$f"

  # Pattern 3: https://specifications.openehr.org/releases/.../spec.html#_foo_bar_class[Text]
  sed -i 's|https://specifications\.openehr\.org/releases/[^#]*#_\([a-z0-9_]*\)_class\[\([^]]*\)\]|xref:{class_\1}[\2]|g' "$f"

  # Pattern 4: xref:...#_foo_bar_class[Text]
  sed -i 's|xref:[^#]*#_\([a-z0-9_]*\)_class\[\([^]]*\)\]|xref:{class_\1}[\2]|g' "$f"

  # Pattern 4b: xref:...#_foo_bar_enumeration[Text]
  sed -i 's|xref:[^#]*#_\([a-z0-9_]*\)_enumeration\[\([^]]*\)\]|xref:{class_\1}[\2]|g' "$f"
}

echo "Step 10: Rewriting class cross-references..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Process ROOT partials (except class partials)
ROOT_PARTIALS_DIR="modules/ROOT/partials"
if [ -d "$ROOT_PARTIALS_DIR" ]; then
  while IFS= read -r f; do
    [ -f "$f" ] || continue
    case "$f" in
      */classes/*) continue ;;
    esac
    rewrite_xrefs_in_file "$f"
  done < <(find "$ROOT_PARTIALS_DIR" -name "*.adoc" 2>/dev/null)
  echo "✓ Rewrote class cross-references in ROOT partials"
fi

# Process all pages in all modules
for pages_dir in modules/*/pages; do
  [ -d "$pages_dir" ] || continue
  for f in "$pages_dir"/*.adoc; do
    [ -f "$f" ] || continue
    rewrite_xrefs_in_file "$f"
  done
done
echo "✓ Rewrote class cross-references in module pages"

echo ""
