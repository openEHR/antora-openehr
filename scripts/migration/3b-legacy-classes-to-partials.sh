#!/bin/bash
set -euo pipefail

# Step 3b: Class partials from the legacy UML class tables, for components without a BMM
#
# bmm-publisher (step 3a) only covers schemas it ships (BASE, RM, AM, LANG, TERM). For the
# others (SM, PROC, CDS) every `include::ROOT:partial$classes/<name>.adoc[]` failed. Their
# MagicDraw exports under docs/**/UML/classes/<name>.adoc hold one `=== X Class` heading
# and the class table. This step turns each into the layout step 3a produces:
#
#   partials/classes/<name>.adoc      heading + [tabs] with a single Definition tab
#   partials/definitions/<name>.adoc  the table (git mv from the legacy file)
#
# Links in the tables (`<<_x_class,X>>`, `link:/releases/...`) are rewritten by steps 10
# and 10b. Skipped when step 3a generated class partials.
#
# Run from repo root (inside the target specification repo)

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/_lib.sh"

CLASSES_DIR="modules/ROOT/partials/classes"
DEFINITIONS_DIR="modules/ROOT/partials/definitions"

echo "Step 3b: Class partials from legacy UML class tables..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if compgen -G "${CLASSES_DIR}/*.adoc" >/dev/null; then
  echo "Class partials already generated (step 3a); skipping."
  echo ""
  exit 0
fi

mapfile -t legacy_files < <(find docs -type f -ipath "*/uml/classes/*.adoc" 2>/dev/null | sort)
if [ "${#legacy_files[@]}" -eq 0 ]; then
  echo "No legacy docs/**/UML/classes/*.adoc; skipping."
  echo ""
  exit 0
fi

mkdir -p "$CLASSES_DIR" "$DEFINITIONS_DIR"
count=0
for src in "${legacy_files[@]}"; do
  name="$(basename "$src" .adoc)"
  def="${DEFINITIONS_DIR}/${name}.adoc"
  cls="${CLASSES_DIR}/${name}.adoc"
  [ -e "$def" ] && { echo "  • ${name}: already present, skipped"; continue; }

  heading="$(grep -m1 -E '^=+ ' "$src" | tr -d '\r' || true)"
  git_move_preserve_history "$src" "$def"
  if [ -n "$heading" ]; then
    # Drop the heading (and the blank lines after it) from the table partial.
    awk 'done { print; next } /^=+ / { skip = 1; next } skip && /^[[:space:]]*$/ { next } { done = 1; print }' \
      "$def" > "${def}.tmp" && mv -f "${def}.tmp" "$def"
  fi

  {
    [ -n "$heading" ] && printf '%s\n\n' "$heading"
    printf '[tabs]\n====\nDefinition::\n+\ninclude::ROOT:partial$definitions/%s.adoc[]\n\n====\n' "$name"
  } > "$cls"
  count=$((count + 1))
done

# Remove the emptied legacy directories.
find docs -depth -type d -ipath "*/uml/classes" -empty -delete 2>/dev/null || true

echo "✓ ${count} class partial(s) from legacy UML class tables"
echo ""
