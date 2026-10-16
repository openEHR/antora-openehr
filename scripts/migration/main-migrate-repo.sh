#!/bin/bash
set -euo pipefail

# Script to migrate openEHR specification repository to Antora structure
# Usage: ./main-migrate-repo.sh /path/to/repo

REPO_PATH="$1"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/_lib.sh"

if [ -z "$REPO_PATH" ]; then
    echo "Error: Repository path not provided"
    echo "Usage: $0 /path/to/repo"
    echo ""
    echo "Examples:"
    echo "  $0 /path/to/specifications-BASE"
    exit 1
fi

if [ ! -d "$REPO_PATH" ]; then
    echo "Error: Repository path does not exist: $REPO_PATH"
    exit 1
fi

REPO_NAME=$(basename "$REPO_PATH")
COMPONENT_NAME="${REPO_NAME#specifications-}"
MIGRATION_BRANCH="${MIGRATION_BRANCH:-development}"

echo "╔════════════════════════════════════════════════════════════╗"
echo "║  openEHR Antora Migration Script                          ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""
echo "Repository: $REPO_NAME"
echo "Component:  $COMPONENT_NAME"
echo "Path:       $REPO_PATH"
echo ""

cd "$REPO_PATH"

# Check if this is a git repository
if [ ! -d ".git" ]; then
    echo "Error: $REPO_PATH is not a git repository"
    exit 1
fi

# Run migration on the desired working branch (default: development), not master.
if ! git show-ref --verify --quiet "refs/heads/$MIGRATION_BRANCH"; then
    echo "Error: Branch '$MIGRATION_BRANCH' does not exist in $REPO_NAME"
    echo "Run branch creation first (e.g. make create-branches REPO=$REPO_NAME)"
    exit 1
fi
CURRENT_BRANCH="$(git rev-parse --abbrev-ref HEAD)"
if [ "$CURRENT_BRANCH" != "$MIGRATION_BRANCH" ]; then
    echo "→ Checking out migration branch: $MIGRATION_BRANCH"
    git checkout "$MIGRATION_BRANCH"
    echo "✓ On branch $MIGRATION_BRANCH"
    echo ""
fi

# Safety check: Create a backup branch
BACKUP_BRANCH="backup-pre-antora-$(date +%Y%m%d-%H%M%S)"
echo "→ Creating backup branch: $BACKUP_BRANCH"
git branch "$BACKUP_BRANCH" HEAD
echo "✓ Backup created"
echo ""

# Optional workflow checkpoints:
# AUTO_COMMIT_CHECKPOINTS=1 (default) enables git add/commit at key milestones.
# Set AUTO_COMMIT_CHECKPOINTS=0 to run migration without creating commits.
AUTO_COMMIT_CHECKPOINTS="${AUTO_COMMIT_CHECKPOINTS:-1}"

commit_checkpoint() {
    local title="$1"
    local body="$2"

    [ "$AUTO_COMMIT_CHECKPOINTS" = "1" ] || return 0

    git add -A
    if git diff --cached --quiet; then
        return 0
    fi

    echo "→ Commit checkpoint: $title"
    git commit -m "$(cat <<EOF
$title

$body
EOF
)"
    echo "✓ Checkpoint committed"
    echo ""
}

# Clean previous migration output so re-runs start fresh
if [ -d "modules" ]; then
    echo "→ Removing existing modules/ directory"
    rm_rf_repo_path "modules"
    if [ -d "modules" ]; then
        echo "Error: Could not remove modules/ (often root-owned files from Docker). Fix ownership then retry, e.g.:" >&2
        echo "  sudo rm -rf modules" >&2
        exit 1
    fi
    echo "✓ Cleaned"
    echo ""
fi

# Step 1: Analyze structure and get MODULES (stdout), logs go to stderr
MODULES="$("$SCRIPT_DIR/1-analyze-structure.sh")"

# Step 2: Create Antora directory structure
"$SCRIPT_DIR/2-create-antora-structure.sh" $MODULES

# Step 3: Move UML diagram assets into ROOT
"$SCRIPT_DIR/3-move-uml.sh"

# Step 3a: Generate Antora-ready UML class partials via bmm-publisher
"$SCRIPT_DIR/3a-generate-uml-classes.sh" "$COMPONENT_NAME"

# Step 3b: Class partials from legacy UML class tables when no BMM exists (SM, PROC, CDS)
"$SCRIPT_DIR/3b-legacy-classes-to-partials.sh"

# Checkpoint: generated class partials + legacy UML/class cleanup.
commit_checkpoint \
  "chore(migration): regenerate uml classes and retire legacy class files" \
  "Capture bmm-publisher class outputs and cleanup of legacy UML/classes artifacts as an isolated checkpoint for clearer rename lineage."

# Step 4: Migrating content files (your existing script)
"$SCRIPT_DIR/4-migrate-content-files.sh" $MODULES

# Step 4c: Fetch external grammar files and rewrite remote includes
"$SCRIPT_DIR/4a-fetch-external-grammars.sh" "$COMPONENT_NAME" $MODULES

# Checkpoint 1: structural migration, where git-moves are concentrated.
commit_checkpoint \
  "chore(migration): move legacy docs into antora modules" \
  "Capture file relocation and initial module shaping as an isolated migration checkpoint to preserve rename lineage."

# Step 5: Create antora.yml
"$SCRIPT_DIR/5-create-antora-yml.sh" "$COMPONENT_NAME" $MODULES

# Step 6: Create navigation files (your existing create_nav_files.sh)
"$SCRIPT_DIR/6-create-nav-files.sh" $MODULES

# Step 7: Create ROOT index page
"$SCRIPT_DIR/7-create-root-index.sh" "$COMPONENT_NAME" $MODULES

# Step 8: Apply manifest vars
"$SCRIPT_DIR/8-apply-manifest-vars.sh" "$COMPONENT_NAME" $MODULES

# Step 9: Rewrite UML diagram references
"$SCRIPT_DIR/9-rewrite-uml-class-includes.sh" "$COMPONENT_NAME" $MODULES

# Step 10: Rewrite internal class cross-references to Antora xrefs
"$SCRIPT_DIR/10-rewrite-class-xrefs.sh"

# Step 11: Tag untagged listing blocks in QUERY/AQL pages with [source, sql]
"$SCRIPT_DIR/11-tag-query-source-blocks.sh" "$COMPONENT_NAME"

# Step 12: Escape literal braces that AsciiDoc would misread as attributes
"$SCRIPT_DIR/12-escape-literal-braces.sh" "$COMPONENT_NAME" $MODULES

# Step 12b: class_definitions partial heading ladder (overview include vs ROOT === classes)
"$SCRIPT_DIR/12b-fix-class-definitions-heading-ladder.sh" "$COMPONENT_NAME" $MODULES

# Step 13: Finalise landing pages (appendix, abstracts, overview, feedback)
"$SCRIPT_DIR/13-finalise-landing-pages.sh" "$COMPONENT_NAME" $MODULES

# Step 14: Drop legacy docs/**/*.html publish artefacts and prune empty docs dirs
"$SCRIPT_DIR/14-remove-legacy-docs-html.sh"

# Checkpoint 2: content rewrites and finalization.
commit_checkpoint \
  "chore(migration): apply antora rewrites and finalisation" \
  "Capture include/xref rewrites, nav/index normalization, legacy docs HTML removal, and final migration polish after structure relocation."

git_force_push_current_branch "$MIGRATION_BRANCH"
