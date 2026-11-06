#!/bin/bash
set -euo pipefail

# Step 4a: Fetch external grammar files and copy local ones to partials
#
# Handles two cases:
#   1. Remote: pages include ANTLR g4 files via URL attributes
#      → rewrite to partial$ (actual files provided by `make update-grammars`)
#   2. Local: pages include grammar files (.g, .g4, .jj) via relative paths
#      → locate in docs/, copy to module partials, rewrite to partial$

COMPONENT_NAME="$1"
shift
MODULES="$@"

echo "Step 4a: Handling grammar file includes..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# -------------------------------------------------------------------
# Rewrite attribute-based remote grammar includes to partial$
# Each entry: COMPONENT|MODULE_FILTER|SED_PATTERN
# MODULE_FILTER is comma-separated module list, or "." for any module.
# -------------------------------------------------------------------

REMOTE_REWRITES=(
  "AM|ADL1.4,ADL2,OPT2|{openehr_adl_antlr_include}/adl/"
  "AM|ADL1.4,ADL2,OPT2|{grammar_dir}/adl/"
  "AM|ADL1.4,ADL2,OPT2|{grammar_dir}/"
  "PROC|.|{grammar_dir}/"
  "LANG|.|{openehr_adl_antlr_include}/adl/"
  "LANG|.|{openehr_openehr_antlr_include}/"
  "LANG|.|{grammar_dir}/"
  "BASE|.|{openehr_adl_antlr_include}/adl/"
)

for entry in "${REMOTE_REWRITES[@]}"; do
  IFS='|' read -r comp mod_filter pattern <<< "$entry"
  [[ "$COMPONENT_NAME" == "$comp" ]] || continue

  for module in $MODULES; do
    # Check module filter (pipe-separated list or . for any)
    if [[ "$mod_filter" != "." ]]; then
      match=false
      IFS=',' read -ra allowed <<< "$mod_filter"
      for a in "${allowed[@]}"; do
        [[ "$module" == "$a" ]] && match=true
      done
      $match || continue
    fi

    pages_dir="modules/$module/pages"
    [ -d "$pages_dir" ] || continue

    for page in "$pages_dir"/*.adoc; do
      [ -f "$page" ] || continue
      if grep -q "include::${pattern}" "$page" 2>/dev/null; then
        sed -i "s|include::${pattern}\([^]]*\)\[\]|include::partial\$\1[]|g" "$page"
      fi
    done
  done
done

# Report any rewrites
for module in $MODULES; do
  pages_dir="modules/$module/pages"
  [ -d "$pages_dir" ] || continue
  if grep -rl 'include::partial\$.*\.g4' "$pages_dir"/*.adoc 2>/dev/null | grep -q .; then
    echo "  ↻ Rewrote grammar includes in $module/pages/"
  fi
done

# -------------------------------------------------------------------
# Local grammars: find relative includes of .g/.g4/.jj files in any
# module, locate the file in docs/, copy to partials, rewrite include
# -------------------------------------------------------------------
for module in $MODULES; do
  pages_dir="modules/$module/pages"
  [ -d "$pages_dir" ] || continue

  for page in "$pages_dir"/*.adoc; do
    [ -f "$page" ] || continue

    # Find relative grammar includes (not remote attr/http and not already partial$)
    { grep -oP 'include::(?!http|\{|partial\$)[^\[]+\.(g4?|jj)\[\]' "$page" 2>/dev/null || true; } | \
    sed 's/include:://;s/\[\]//' | while read -r rel_path; do
      filename=$(basename "$rel_path")
      partials_dir="modules/$module/partials"

      # Search for the file in docs/ (case-insensitive)
      src=$(find docs -iname "$filename" 2>/dev/null | head -1)
      if [ -z "$src" ]; then
        echo "  ✗ Could not find $filename in docs/ — skipping"
        continue
      fi

      # Preserve subdirectory structure from the relative include path
      subdir=$(dirname "$rel_path")
      if [ "$subdir" = "." ]; then
        dest_dir="$partials_dir"
      else
        dest_dir="$partials_dir/$subdir"
      fi

      mkdir -p "$dest_dir"
      cp "$src" "$dest_dir/$filename"
      echo "  ↳ $src → $module/partials/$rel_path"

      # Rewrite include directive to use partial$
      sed -i "s|include::${rel_path}\[\]|include::partial\$${rel_path}[]|g" "$page"
    done
  done
done

echo ""
echo "✓ Grammar files fetched/copied and includes rewritten"
echo ""
