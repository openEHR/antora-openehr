#!/bin/bash
set -euo pipefail

# Step 2a: Copy hand-written class examples into the migrated repo
#
# The canonical JSON examples per class live here, in
# scripts/resources/class-examples/{COMPONENT}/<class filename>.adoc, because a
# re-run of the migration removes modules/ and with it anything written by hand
# on the development branch. This step copies them to
# modules/ROOT/partials/examples/, where step 3a passes them to bmm-publisher
# (--examples-dir) to get an Example tab on each class.
#
# Only the development branch gets them: the examples describe the current model
# and are not part of a published release. Set CLASS_EXAMPLES=1 to copy them on
# another branch, CLASS_EXAMPLES=0 to skip.
#
# Edit the examples here, not in the spec repo, until the migration is final;
# afterwards they live in the spec repo and this step goes.

COMPONENT_NAME="$1"
BRANCH="${2:-development}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SOURCE_DIR="$SCRIPT_DIR/../resources/class-examples/${COMPONENT_NAME}"
TARGET_DIR="modules/ROOT/partials/examples"

echo "Step 2a: Copying class examples..."

if [ ! -d "$SOURCE_DIR" ]; then
  echo "  No class examples for ${COMPONENT_NAME}; skipped"
  exit 0
fi

case "${CLASS_EXAMPLES:-}" in
  0) echo "  CLASS_EXAMPLES=0; skipped"; exit 0 ;;
  1) ;;
  *)
    if [ "$BRANCH" != "development" ]; then
      echo "  Branch ${BRANCH} is not development; skipped (CLASS_EXAMPLES=1 to copy anyway)"
      exit 0
    fi
    ;;
esac

mkdir -p "$TARGET_DIR"
count=0
for f in "$SOURCE_DIR"/*.adoc; do
  [ -e "$f" ] || continue
  cp "$f" "$TARGET_DIR/"
  count=$((count + 1))
done

echo "  ✓ ${count} example(s) copied to ${TARGET_DIR}"
