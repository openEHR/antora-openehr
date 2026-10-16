#!/bin/bash
# Shared helper functions for migration scripts.
# Source this file — do not execute directly.
#   source "$(dirname "$0")/_lib.sh"

# -------------------------------------------------------------------
# strip_master_prefix <filename>
#   masterNN-something.adoc     → something.adoc
#   masterNN.NN-something.adoc  → something.adoc
#   masterAppA-something.adoc   → something.adoc
#   anything_else.adoc          → anything_else.adoc
# -------------------------------------------------------------------
strip_master_prefix() {
  echo "$1" | sed -E 's/^master[0-9.]+-//; s/^masterApp[A-Z]-//'
}

# -------------------------------------------------------------------
# to_title_case <string>
#   "foo_bar" → "Foo Bar"
# -------------------------------------------------------------------
to_title_case() {
  echo "$1" \
    | sed 's/_/ /g' \
    | sed 's/\b\(.\)/\u\1/g'
}

# -------------------------------------------------------------------
# get_title_from_page <page_file>
#   Returns the first = heading from an .adoc file (empty if none).
# -------------------------------------------------------------------
get_title_from_page() {
  local page_file="$1"
  [ -f "$page_file" ] || { echo ""; return; }
  awk '/^[[:space:]]*= / { sub(/^[[:space:]]*= /,""); print; exit }' "$page_file"
}

# -------------------------------------------------------------------
# list_chapter_includes <master_file>
#   Prints the ordered list of chapter include targets from a
#   master.adoc file. Each line is the raw include target filename
#   (e.g. "master04-data_types.adoc"). Includes commented-out lines such as
#   // include::masterAppC-foo.adoc[leveloffset=+1] so optional chapters still migrate.
#   Filters out:
#     - paths containing / or { (cross-directory / attribute-based)
#     - manifest_vars.adoc
#     - amendment_record / preface files
# -------------------------------------------------------------------
list_chapter_includes() {
  local master_file="$1"
  [ -f "$master_file" ] || return 0

  # After -- CHAPTERS -- / :sectnums: / :sectanchors:, emit each chapter include target in order.
  # Include commented-out lines like "// include::masterAppC-foo.adoc[leveloffset=+1]" so optional
  # chapters still migrate when the .adoc file exists (authors often disable via comment).
  awk '
    BEGIN { found=0 }
    /:sectnums:|:sectanchors:|-- CHAPTERS --/ { found=1; next }
    found && /include::/ {
      line=$0
      sub(/^[[:space:]]*\/\/[[:space:]]*/, "", line)
      if (line ~ /^include::/) {
        sub(/^include::/, "", line)
        sub(/\[.*/, "", line)
        print line
      }
    }
  ' "$master_file" \
    | while read -r target; do
        [ -z "$target" ] && continue
        case "$target" in
          *"/"*|*"{"* )                          continue ;;
          manifest_vars.adoc)                     continue ;;
          *-amendment_record.adoc|amendment_record.adoc) continue ;;
          *-preface.adoc|preface.adoc)            continue ;;
        esac
        echo "$target"
      done
}

# -------------------------------------------------------------------
# is_master_include <target>
#   Returns success if target matches master chapter naming.
# -------------------------------------------------------------------
is_master_include() {
  local target="$1"
  case "$target" in
    master[0-9][0-9]-*.adoc)       return 0 ;;
    master[0-9][0-9].[0-9]-*.adoc) return 0 ;;
    master[0-9][0-9].[0-9][0-9]-*.adoc) return 0 ;;
    masterApp[A-Z]-*.adoc)         return 0 ;;
    *)                             return 1 ;;
  esac
}

# -------------------------------------------------------------------
# chapter_group_key <target>
#   master07-foo.adoc      -> 07
#   master07.01-foo.adoc   -> 07
#   masterAppA-foo.adoc    -> APP-A-foo.adoc (unique group per appendix)
#   non-master target      -> ""
#
# When a later include in the same group is migrated as a partial (included from
# the chapter root page with leveloffset=+1), section titles in that file are
# demoted one level via decrease_asciidoc_section_heading_one_level so e.g.
#   == Subsection  ->  = Subsection
# -------------------------------------------------------------------
chapter_group_key() {
  local target="$1"
  if [[ "$target" =~ ^master([0-9]{2})(\.[0-9]{1,2})?- ]]; then
    echo "${BASH_REMATCH[1]}"
    return 0
  fi
  if [[ "$target" =~ ^masterApp([A-Z])-(.+)\.adoc$ ]]; then
    echo "APP-${BASH_REMATCH[1]}-${BASH_REMATCH[2]}"
    return 0
  fi
  echo ""
}

# -------------------------------------------------------------------
# decrease_asciidoc_section_heading_one_level <file>
#   Demotes every atx-style section title by removing one leading '='.
#   Matches lines that start with two or more '=' followed by a space or
#   an anchor ('[['), so lone '= Document title' lines are left unchanged.
# -------------------------------------------------------------------
decrease_asciidoc_section_heading_one_level() {
  local file="$1"
  [ -f "$file" ] || return 0
  sed -E -i '/^={2,}(\[|[[:space:]])/s/^=//' "$file"
}

# -------------------------------------------------------------------
# git_move_preserve_history <src> <dst>
#   Move a tracked file with git mv so renames keep blame/history; fall back to
#   mv for untracked paths. Creates parent directories for dst as needed.
# -------------------------------------------------------------------
git_move_preserve_history() {
  local src="$1"
  local dst="$2"
  [ -e "$src" ] || return 1
  mkdir -p "$(dirname "$dst")"
  if git ls-files --error-unmatch "$src" >/dev/null 2>&1; then
    git mv -f -- "$src" "$dst"
  else
    mv -f -- "$src" "$dst"
  fi
}

# -------------------------------------------------------------------
# resolve_module_master_source <module>
#   Path for chapter list / pkg injection: docs master, else a snapshot taken
#   right after master → index (before includes are stripped), else live index.
# -------------------------------------------------------------------
resolve_module_master_source() {
  local module="$1"
  if [ -f "docs/$module/master.adoc" ]; then
    echo "docs/$module/master.adoc"
  elif [ -f "modules/$module/partials/.migration_master_snapshot.adoc" ]; then
    echo "modules/$module/partials/.migration_master_snapshot.adoc"
  elif [ -f "modules/$module/pages/index.adoc" ]; then
    echo "modules/$module/pages/index.adoc"
  else
    echo ""
  fi
}

# -------------------------------------------------------------------
# strip_legacy_master_index_lines <index.adoc>
#   Remove include lines and sectnums from a migrated module index (was master.adoc).
# -------------------------------------------------------------------
strip_legacy_master_index_lines() {
  local f="$1"
  [ -f "$f" ] || return 0
  # The logo comes as {openehr_logo} or, in older releases (AM 1.4.0), as a hard-coded URL;
  # left in place it pushes the title below it, which then renders as a part, not the title.
  sed -i '/^include::/d;/^image::{openehr_logo}/d;/^image::https\?:\/\/[^[]*openehr_logo/d' "$f"
  sed -i '/^:sectnums:/d' "$f"
}

# -------------------------------------------------------------------
# normalize_semver3 <version>
#   "1.4" -> "1.4.0"
#   "v1.2.0" -> "1.2.0"
# -------------------------------------------------------------------
normalize_semver3() {
  local raw="${1:-}"
  raw="${raw#v}"
  raw="${raw//[^0-9.]/}"
  IFS='.' read -r major minor patch <<< "$raw"
  major="${major:-0}"
  minor="${minor:-0}"
  patch="${patch:-0}"
  echo "${major}.${minor}.${patch}"
}

# -------------------------------------------------------------------
# latest_manifest_release <manifest_json>
#   Returns first releases[].id in manifest.json (or empty)
# -------------------------------------------------------------------
latest_manifest_release() {
  local manifest_json="$1"
  [ -f "$manifest_json" ] || { echo ""; return; }
  jq -r '.releases[0].id // empty' "$manifest_json" 2>/dev/null || true
}

# -------------------------------------------------------------------
# manifest_has_release <manifest_json> <version>
#   Returns success if releases[].id contains version
# -------------------------------------------------------------------
manifest_has_release() {
  local manifest_json="$1"
  local version="$2"
  [ -f "$manifest_json" ] || return 1
  jq -e --arg version "$version" '.releases[]? | select(.id == $version)' "$manifest_json" >/dev/null 2>&1
}

# -------------------------------------------------------------------
# to_bmm_id <component> <version>
#   BASE + 1.3.0 -> openehr_base_1.3.0
# -------------------------------------------------------------------
to_bmm_id() {
  local component="$1"
  local version="$2"
  local lc
  lc="$(echo "$component" | tr '[:upper:]' '[:lower:]')"
  echo "openehr_${lc}_$(normalize_semver3 "$version")"
}

# -------------------------------------------------------------------
# rm_rf_repo_path <path>
#   Remove path relative to current working directory. Docker bind mounts often
#   leave root-owned files (e.g. under partials/.bmm-output-scratch); plain rm -rf
#   then fails from migrate-repo's "Removing existing modules/". Retry removal
#   from a root-owned Alpine container on the same workspace bind mount.
# -------------------------------------------------------------------
rm_rf_repo_path() {
  local target="$1"
  [ -n "$target" ] || return 0
  [ -e "$target" ] || return 0

  chmod -R u+w "$target" 2>/dev/null || true
  if rm -rf "$target" 2>/dev/null; then
    return 0
  fi

  if command -v docker >/dev/null 2>&1; then
    local repo_root
    repo_root="$(pwd)"
    docker run --rm \
      -v "${repo_root}:/work" \
      -w /work \
      -e TARGET="$target" \
      alpine:3.20 \
      sh -c 'chmod -R u+w "/work/${TARGET}" 2>/dev/null; rm -rf "/work/${TARGET}"' 2>/dev/null || true
  fi

  chmod -R u+w "$target" 2>/dev/null || true
  rm -rf "$target" 2>/dev/null || true
}

# -------------------------------------------------------------------
# git_force_push_current_branch [branch]
#   Force-push current branch to origin after generated migration commits.
#   Uses --force-with-lease by default so remote changes made by someone else
#   are not overwritten silently. Override flags with GIT_FORCE_PUSH_FLAGS.
# -------------------------------------------------------------------
git_force_push_current_branch() {
  local branch="${1:-}"
  local flags="${GIT_FORCE_PUSH_FLAGS:---force-with-lease}"

  if [ -z "$branch" ]; then
    branch="$(git rev-parse --abbrev-ref HEAD)"
  fi

  if [ -z "$branch" ] || [ "$branch" = "HEAD" ]; then
    echo "Error: cannot force-push detached HEAD" >&2
    return 1
  fi

  echo "→ Force-pushing $branch to origin ($flags)"
  git push $flags origin "$branch"
  echo "✓ Force-pushed $branch"
  echo ""
}
