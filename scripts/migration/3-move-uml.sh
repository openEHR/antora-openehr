#!/bin/bash
set -euo pipefail

# Usage: step3-move-uml.sh
# Run from repo root
#
# Moves diagram assets into modules/ROOT/images/uml/, then removes legacy
# docs/**/UML/class_index.adoc (superseded by generated ROOT partials) and
# prunes empty docs/**/UML/diagrams and docs/**/UML directories.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/_lib.sh"

echo "Step 3: Moving UML content..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

move_diagram_to_root() {
  local src="$1"
  local subname="${2:-}"
  local base dst
  base="$(basename "$src")"
  dst="modules/ROOT/images/uml/$base"
  # A nested UML/<SUBDIR>/diagrams/ file whose name is already taken by a different
  # flat diagram (AM: AOM1.4 and AOM2 both have AOM-archetype.svg) keeps its subdir,
  # so neither version overwrites the other; step 9 links to it.
  if [ -n "$subname" ] && [ -e "$dst" ] && ! cmp -s "$src" "$dst"; then
    dst="modules/ROOT/images/uml/$subname/$base"
  fi
  git_move_preserve_history "$src" "$dst"
}

# Handle UML directory if it exists
if [ -d "docs/UML" ] || [ -d "docs/uml" ]; then
  UML_DIR=$(find docs -iname "UML" -type d | head -n 1)

  mkdir -p modules/ROOT/images/uml

  # Flat layout: UML/diagrams/
  if [ -d "$UML_DIR/diagrams" ]; then
    echo "→ Moving UML diagrams (flat) to ROOT/images/uml/"
    find "$UML_DIR/diagrams" \( -name "*.svg" -o -name "*.png" -o -name "*.jpg" \) -type f | while read -r f; do
      move_diagram_to_root "$f"
    done
    echo "✓ Moved UML diagrams"
  fi

  # Nested layout: UML/<SUBDIR>/diagrams/
  for subdir in "$UML_DIR"/*/; do
    [ -d "$subdir" ] || continue
    subname=$(basename "$subdir")
    if [ -d "$subdir/diagrams" ]; then
      echo "→ Moving UML diagrams from $subname to ROOT/images/uml/"
      find "$subdir/diagrams" \( -name "*.svg" -o -name "*.png" -o -name "*.jpg" \) -type f | while read -r f; do
        move_diagram_to_root "$f" "$subname"
      done
    fi
  done
else
  echo "No UML directory found, skipping UML move."
fi

# -------------------------------------------------------------------
# Legacy class index + empty UML/diagrams cleanup
# -------------------------------------------------------------------
remove_legacy_uml_class_index_and_prune_empty_dirs() {
  [ -d docs ] || return 0

  echo "→ Removing legacy docs/**/UML/class_index.adoc (and empty diagrams/ siblings)..."

  local f
  while IFS= read -r -d '' f; do
    echo "  • rm $f"
    if git ls-files --error-unmatch "$f" >/dev/null 2>&1; then
      git rm -f "$f"
    else
      rm -f "$f"
    fi
  done < <(find docs \( -path '*/UML/class_index.adoc' -o -path '*/uml/class_index.adoc' \) -type f -print0 2>/dev/null)

  local d
  while IFS= read -r -d '' d; do
    if [ ! -d "$d" ]; then
      continue
    fi
    if [ -z "$(find "$d" -mindepth 1 -maxdepth 1 2>/dev/null)" ]; then
      echo "  • rmdir $d"
      rmdir "$d" 2>/dev/null || true
    fi
  done < <(find docs \( -path '*/UML/diagrams' -o -path '*/uml/diagrams' \) -type d -print0 2>/dev/null)

  # Deepest first so nested empties collapse (e.g. diagrams/ then UML/)
  while IFS= read -r d; do
    if [ ! -d "$d" ]; then
      continue
    fi
    if [ -z "$(find "$d" -mindepth 1 -maxdepth 1 2>/dev/null)" ]; then
      echo "  • rmdir $d"
      rmdir "$d" 2>/dev/null || true
    fi
  done < <(find docs -depth -type d \( -name UML -o -name uml \) ! -path docs 2>/dev/null)
}

remove_legacy_uml_class_index_and_prune_empty_dirs

echo ""
