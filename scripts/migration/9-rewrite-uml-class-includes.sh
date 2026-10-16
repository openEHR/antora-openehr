#!/bin/bash
set -euo pipefail

# Rewrites UML class include references and diagram references
# to Antora-compatible locations.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
COMPONENT_NAME="$1"
shift

MODULES="$@"

remove_missing_class_includes() {
  local file="$1"
  local tmp
  tmp="$(mktemp)"

  # `|| [ -n "$line" ]` keeps a last line without a trailing newline (it was dropped
  # before, e.g. the closing `--------` of a listing block); printf keeps lines like `-n`.
  while IFS= read -r line || [ -n "$line" ]; do
    if [[ "$line" =~ include::ROOT:partial\$classes/([^[]+)\[ ]]; then
      local class_partial="modules/ROOT/partials/classes/${BASH_REMATCH[1]}"
      [ -f "$class_partial" ] || continue
    fi
    printf '%s\n' "$line"
  done < "$file" > "$tmp"

  mv "$tmp" "$file"
}

rewrite_uml_refs_for_module() {
  local module="$1"
  local pages_dir="modules/$module/pages"
  local partials_dir="modules/$module/partials"
  local class_prefix=""

  # AM class files are generated with series prefixes.
  if [[ "$COMPONENT_NAME" == "AM" ]]; then
    case "$module" in
      AOM2|OPT2|ADL2) class_prefix="aom2." ;;
      *)              class_prefix="aom14." ;;
    esac
  fi

  [ -d "$pages_dir" ] && echo "→ Rewriting UML refs in $pages_dir"
  [ -d "$partials_dir" ] && echo "→ Rewriting UML refs in $partials_dir"

  # Process both pages and partials
  for f in "$pages_dir"/*.adoc "$partials_dir"/*.adoc; do
    [ -f "$f" ] || continue

    #
    # UML CLASS INCLUDES — normalize legacy include patterns to ROOT partials
    # Generated bmm class files are now promoted under ROOT/partials/classes.
    #
    sed -i "s|include::{uml_export_dir}/classes/|include::ROOT:partial\$classes/${class_prefix}|g" "$f"
    sed -i "s|include::../UML/classes/|include::ROOT:partial\$classes/${class_prefix}|g" "$f"
    # Handle optional nested UML export paths, with optional {pkg} prefix.
    perl -i -pe "s!include::(?:\\{uml_export_dir\\}|\\.\\./UML)(?:/[^/\\[]+)?/classes/(?:\\{pkg\\})?([^/\\[]+)!include::ROOT:partial\\\$classes/${class_prefix}\$1!g" "$f"
    # If simple replacement matched, remove any remaining {pkg} token,
    # including the AM-prefixed form (e.g. aom2.{pkg}class.adoc).
    sed -i "s|include::ROOT:partial\$classes/{pkg}|include::ROOT:partial\$classes/|g" "$f"
    sed -i "s|partial\$classes/aom14.{pkg}|partial\$classes/aom14.|g" "$f"
    sed -i "s|partial\$classes/aom2.{pkg}|partial\$classes/aom2.|g" "$f"
    perl -i -pe 's|(include::ROOT:partial\$classes/[^[]*)\{pkg\}|$1|g' "$f"

    # AM: generated class partials start at "===" so they nest under sections such as
    # "== Class Descriptions" or under partials like "= Class Definitions" included with
    # leveloffset=+1 from an overview page. Do NOT add leveloffset=-1 here: demoting
    # === to == makes class titles collide with their parent section level and breaks
    # heading sequences (e.g. "expected level 2, got level 3" before ==== blocks).

    #
    # UML DIAGRAMS — all known diagram URI attributes → ROOT:uml/
    #
    sed -i 's|image::{uml_diagrams_uri}/|image::ROOT:uml/|g' "$f"
    # {uml_aom14_diagrams_uri} / {uml_aom2_diagrams_uri} are UML/AOM1.4|AOM2/diagrams; use the
    # uml/<SUBDIR>/ copy step 3 kept on a name clash, else the flat file.
    perl -i -pe 's{image::\{uml_aom(14|2)_diagrams_uri\}/([^\[]+)}{my $d = $1 eq "14" ? "AOM1.4" : "AOM2"; -e "modules/ROOT/images/uml/$d/$2" ? "image::ROOT:uml/$d/$2" : "image::ROOT:uml/$2"}ge' "$f"
    # AM release/1.4.0 writes the export dir directly: image::{uml_export_dir}/diagrams/X.svg
    sed -i 's|image::{uml_export_dir}/diagrams/|image::ROOT:uml/|g' "$f"

    #
    # UML DIAGRAMS — bare paths: UML/diagrams/X.svg and UML/AOM*/diagrams/X.svg → ROOT:uml/
    # A UML/<SUBDIR>/diagrams/X that step 3 kept under uml/<SUBDIR>/ (name clash) links there.
    #
    sed -i 's|image::UML/diagrams/|image::ROOT:uml/|g' "$f"
    sed -i 's|image::../UML/diagrams/|image::ROOT:uml/|g' "$f"
    perl -i -pe 's{image::(?:\{uml_export_dir\}|\.\./UML|UML)/([^/\[]+)/diagrams/([^\[]+)}{-e "modules/ROOT/images/uml/$1/$2" ? "image::ROOT:uml/$1/$2" : "image::ROOT:uml/$2"}ge' "$f"

    #
    # Module images written with an images/ prefix: image::images/X.png → image::X.png
    #
    sed -i 's|image::images/|image::|g' "$f"

    #
    # LEGACY diagrams_uri — image::{diagrams_uri}/X.png → image::diagrams/X.png
    # Files are copied to modules/<module>/images/diagrams/ by migration step 4
    #
    sed -i 's|image::{diagrams_uri}/|image::diagrams/|g' "$f"

    #
    # FIX wrong image extension: image::ROOT:uml/X.png → image::ROOT:uml/X.svg
    # when X.svg exists in ROOT/images/uml/ but X.png does not
    #
    while IFS= read -r line || [ -n "$line" ]; do
      if [[ "$line" =~ image::ROOT:uml/([^[]+)\.png ]]; then
        base="${BASH_REMATCH[1]}"
        if [ -f "modules/ROOT/images/uml/${base}.svg" ] && [ ! -f "modules/ROOT/images/uml/${base}.png" ]; then
          sed -i "s|image::ROOT:uml/${base}\.png|image::ROOT:uml/${base}.svg|g" "$f"
        fi
      fi
    done < "$f"

    remove_missing_class_includes "$f"
  done
}

echo "Step 9: Rewriting UML class + diagram references..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

for module in $MODULES; do
  rewrite_uml_refs_for_module "$module"
done

echo ""
