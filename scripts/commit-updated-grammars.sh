#!/usr/bin/env bash
# Stage and commit vendored ANTLR grammar files (.g4) under modules/*/partials/
# after make update-grammars copies from adl-antlr / openEHR-antlr4.
# Usage: scripts/commit-updated-grammars.sh [repos_dir]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/migration/_lib.sh"

REPOS_DIR="${1:-repos}"

commit_g4_in_repo() {
  local repo_root="$1"
  [ -d "$repo_root" ] || return 0
  repo_root="$(cd "$repo_root" && pwd)"
  [ -d "$repo_root/.git" ] || return 0

  # release/* keep the grammar of their release; never commit or force-push them here
  local branch
  branch="$(git -C "$repo_root" rev-parse --abbrev-ref HEAD)"
  case " ${GRAMMAR_BRANCHES:-development} " in
    *" $branch "*) ;;
    *) echo "  • Skipping $repo_root: on $branch"; return 0 ;;
  esac

  local files=()
  local f rel
  while IFS= read -r -d '' f; do
    # Paths must be relative to the spec repo (modules/...), not
    # repos/specifications-XX/modules/... which git rejects under git -C.
    rel="${f#"$repo_root"/}"
    [ -n "$rel" ] && [ "$rel" != "$f" ] && files+=("$rel")
  done < <(find "$repo_root/modules" -type f -name '*.g4' -path '*/partials/*' -print0 2>/dev/null || true)

  [ "${#files[@]}" -eq 0 ] && return 0

  git -C "$repo_root" add -- "${files[@]}"

  if git -C "$repo_root" diff --cached --quiet; then
    return 0
  fi

  git -C "$repo_root" commit -m "chore: refresh vendored ADL ANTLR grammar (.g4)" \
    -m "Synced from make update-grammars (adl-antlr / openEHR-antlr4)."

  (
    cd "$repo_root"
    git_force_push_current_branch
  )
}

echo "→ Committing grammar updates in specification repos (if any)..."

for spec in specifications-AM specifications-LANG specifications-PROC; do
  r="$REPOS_DIR/$spec"
  [ -d "$r" ] || continue
  commit_g4_in_repo "$r"
done

echo "✓ Grammar commit step finished."
