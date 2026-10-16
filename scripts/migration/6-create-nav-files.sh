#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/_lib.sh"

MODULES="$@"

# -------------------------------------------------------------------
# Extract :spec_title: from modules/$module/partials/module_vars.adoc
# -------------------------------------------------------------------

get_spec_title_from_module_vars() {
  local module="$1"
  local file=""

  if [ -f "modules/$module/partials/module_vars.adoc" ]; then
    file="modules/$module/partials/module_vars.adoc"
  else
    echo ""
    return
  fi

  # Find line beginning with :spec_title:
  local line
  line="$(grep '^:spec_title:' "$file" | head -n1 || true)"

  [ -z "$line" ] && { echo ""; return; }

  # Remove prefix ":spec_title: "
  echo "${line#*:spec_title: }"
}

# -------------------------------------------------------------------
# ROOT nav
# -------------------------------------------------------------------

create_root_nav() {
  mkdir -p "modules/ROOT"

  cat > "modules/ROOT/nav.adoc" << EOF
* xref:index.adoc[Overview]
EOF

  echo "✓ Created modules/ROOT/nav.adoc"
}

# -------------------------------------------------------------------
# Module nav generation
# -------------------------------------------------------------------

generate_nav_entries_from_master() {
  local module="$1"
  local master_file
  master_file="$(resolve_module_master_source "$module")"

  [ -f "$master_file" ] || return 0

  declare -A seen_group

  list_chapter_includes "$master_file" | while read -r target; do
    # Attribute-only includes are partials, not pages (see is_attribute_include)
    is_attribute_include "$target" && continue
    if is_master_include "$target"; then
      local group
      group="$(chapter_group_key "$target")"
      if [ -n "$group" ] && [ -n "${seen_group[$group]:-}" ]; then
        continue
      fi
      [ -n "$group" ] && seen_group[$group]=1
    fi

    local base
    base="$(strip_master_prefix "${target%.adoc}")"

    local page_file="modules/$module/pages/${base}.adoc"
    local title

    title="$(get_title_from_page "$page_file")"
    if [ -z "$title" ]; then
      title="$(to_title_case "$base")"
    fi

    echo "** xref:${base}.adoc[${title}]"
  done
}


create_module_nav() {
  local module="$1"

  local nav_file="modules/$module/nav.adoc"
  local index_file="modules/$module/pages/index.adoc"

  mkdir -p "modules/$module"

  # ------------------------------------------------------------------
  # TITLE RESOLUTION PRIORITY:
  # 0) Title from manifest.json
  # 1) :spec_title: from module_vars.adoc
  # 2) First "= Heading" in index.adoc
  # 3) Prettified module name
  # ------------------------------------------------------------------
  local module_title=""
  local spec_title_literal="{spec_title}"

  if [ -f "manifest.json" ]; then
    module_title="$(jq -r --arg module_id "$module" '.specifications[]? | select(.id == $module_id) | .title // empty' manifest.json)"
  fi

  if [ -z "$module_title" ]; then
    module_title="$(get_spec_title_from_module_vars "$module")"
  fi

  if [ -z "$module_title" ]; then
    module_title="$(get_title_from_page "$index_file")"
  fi

  if [ -z "$module_title" ]; then
    module_title="$(to_title_case "$module")"
  fi

  {
    SPEC_TITLE_PLACEHOLDER="{spec_title}"
    if [ "${module_title}" = "${spec_title_literal}" ]; then
      echo "include::partial\$module_vars.adoc[]"
      echo
    fi
    echo "* xref:index.adoc[${module_title}]"
    generate_nav_entries_from_master "$module"
  } > "$nav_file"

  echo "✓ Created modules/$module/nav.adoc"
}

# -------------------------------------------------------------------
# Main
# -------------------------------------------------------------------

echo "→ Generating navigation files..."
create_root_nav

for module in $MODULES; do
  create_module_nav "$module"
done
