#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/_lib.sh"

COMPONENT_NAME="${1:-}"
REPO_NAME="$(basename "$(pwd)")"
MANIFEST_PATH="manifest.json"
OUTPUT_DIR="modules/ROOT/partials/classes"
STAGING_ROOT="modules/ROOT/partials/Adoc"
#
# Docker + host layout
# ---------------------
# Run bmm-publisher as **host UID:GID** (`docker run --user …`) so bind-mounted output is owned by you, not root.
# Mount **modules/ROOT/partials** → **/app/output**. The publisher writes Adoc/<BMM_ID>/{classes,definitions,…,images,plantUML,…}.
#
# Why not bind-mount each subtree straight onto modules/ROOT/partials/<dir> and modules/ROOT/images?
# Any nested Docker bind mount under /app/output/Adoc/… causes bmm-publisher (tested through 0.7.x) to abort with
# `Directory "/app/output/Adoc/" is not writable` (Java writability check). Only a single mount on /app/output works.
#
# So we **promote** output after each run: classes/definitions/effective/BMMs → modules/ROOT/partials/*;
# SVG tree → modules/ROOT/images/*. **plantUML/** and **images/** under Adoc are not copied into partials/plantUML
# (images/ is handled separately; plantUML/ is staging-only and removed with Adoc/).
#
# Pin default tag; override with BMM_PUBLISHER_IMAGE e.g. ghcr.io/openehr/bmm-publisher:0.12.0
# 0.8.0+ is required: dependencies are passed with `-d` (loaded for cross-refs, not exported).
# Set BMM_PUBLISHER_AS_ROOT=1 to omit --user (not recommended; leaves root-owned files on mounts).
DOCKER_IMAGE="${BMM_PUBLISHER_IMAGE:-ghcr.io/openehr/bmm-publisher:0.12.0}"
ROOT_IMAGES_DIR="modules/ROOT/images"

# Optional local BMM JSON overlays (merged on top of the image's /app/resources):
#   - Default directory next to manifest.json: ./computable/BMM/*.bmm.json
#   - Or explicit path: BMM_RESOURCES_OVERLAY=/path/to/dir
# Filenames must match publisher ids, e.g. openehr_lang_1.1.0.bmm.json
BMM_RESOURCES_MERGED_DIR=""

cleanup_bmm_resources_merged_dir() {
  if [[ -n "${BMM_RESOURCES_MERGED_DIR:-}" && -d "${BMM_RESOURCES_MERGED_DIR}" ]]; then
    rm -rf "${BMM_RESOURCES_MERGED_DIR}"
    BMM_RESOURCES_MERGED_DIR=""
  fi
}

bmm_resource_exists_locally() {
  local id="$1"

  if [[ -n "${BMM_RESOURCES_OVERLAY:-}" && -f "${BMM_RESOURCES_OVERLAY}/${id}.bmm.json" ]]; then
    return 0
  fi

  [[ -f "computable/BMM/${id}.bmm.json" ]]
}

bmm_resource_exists_in_image() {
  local id="$1"
  local cid tmp

  tmp="$(mktemp -d)"
  if ! cid="$(docker create --entrypoint /bin/true "$DOCKER_IMAGE" 2>/dev/null)"; then
    rm -rf "$tmp"
    return 1
  fi

  if docker cp "$cid:/app/resources/${id}.bmm.json" "$tmp/${id}.bmm.json" >/dev/null 2>&1; then
    docker rm "$cid" >/dev/null 2>&1 || true
    rm -rf "$tmp"
    return 0
  fi

  docker rm "$cid" >/dev/null 2>&1 || true
  rm -rf "$tmp"
  return 1
}

bmm_resource_available() {
  local id="$1"

  bmm_resource_exists_locally "$id" || bmm_resource_exists_in_image "$id"
}

bmm_resources_available() {
  local id missing=0

  for id in "$@"; do
    [ -n "$id" ] || continue
    if ! bmm_resource_available "$id"; then
      echo "  • no BMM resource available for ${id}; skipping this publisher input"
      missing=1
    fi
  done

  [ "$missing" -eq 0 ]
}

prepare_bmm_resources_overlay() {
  local overlay=""
  if [[ -n "${BMM_RESOURCES_OVERLAY:-}" && -d "${BMM_RESOURCES_OVERLAY}" ]]; then
    overlay="${BMM_RESOURCES_OVERLAY}"
  elif [[ -d "computable/BMM" ]] && compgen -G "computable/BMM/*.bmm.json" >/dev/null; then
    overlay="$(pwd)/computable/BMM"
  fi

  if [[ -z "$overlay" ]]; then
    return 1
  fi

  echo "→ BMM resources overlay: $overlay (merged onto image /app/resources)"

  BMM_RESOURCES_MERGED_DIR="$(mktemp -d)"
  local cid
  cid="$(docker create --entrypoint /bin/true "$DOCKER_IMAGE")"
  docker cp "$cid:/app/resources/." "${BMM_RESOURCES_MERGED_DIR}/"
  docker rm "$cid" >/dev/null
  # docker cp often leaves root-owned files; publisher runs as host UID and must read /app/resources.
  chmod -R a+rX "${BMM_RESOURCES_MERGED_DIR}" 2>/dev/null || true

  local f
  for f in "$overlay"/*.bmm.json; do
    [[ -f "$f" ]] || continue
    cp -f "$f" "${BMM_RESOURCES_MERGED_DIR}/"
    echo "  • overlay $(basename "$f")"
  done
  return 0
}

seed_missing_bmm_resources_from_image() {
  local -a ids=("$@")
  [ "${#ids[@]}" -gt 0 ] || return 0

  mkdir -p "computable/BMM"

  local id target copied=0
  local -a missing_ids=()
  for id in "${ids[@]}"; do
    target="computable/BMM/${id}.bmm.json"
    [ -f "$target" ] || missing_ids+=("$id")
  done

  [ "${#missing_ids[@]}" -gt 0 ] || return 0

  local cid tmp
  tmp="$(mktemp -d)"
  if ! cid="$(docker create --entrypoint /bin/true "$DOCKER_IMAGE" 2>/dev/null)"; then
    rm -rf "$tmp"
    echo "  • could not inspect publisher image for missing BMM resources; continuing without seeding"
    return 0
  fi
  trap 'docker rm "$cid" >/dev/null 2>&1 || true; rm -rf "$tmp"; cleanup_bmm_resources_merged_dir' EXIT

  for id in "${missing_ids[@]}"; do
    target="computable/BMM/${id}.bmm.json"
    if docker cp "$cid:/app/resources/${id}.bmm.json" "$tmp/${id}.bmm.json" >/dev/null 2>&1; then
      cp -f "$tmp/${id}.bmm.json" "$target"
      chmod u+rw,go+r "$target" 2>/dev/null || true
      echo "  • seeded BMM resource from publisher image: $target"
      copied=$((copied + 1))
    else
      echo "  • no publisher BMM resource found for ${id}; leaving computable/BMM unchanged"
    fi
  done

  docker rm "$cid" >/dev/null
  rm -rf "$tmp"
  trap cleanup_bmm_resources_merged_dir EXIT

  if [ "$copied" -gt 0 ]; then
    echo "→ Seeded $copied missing BMM resource file(s) under computable/BMM"
  fi
}

if [[ -z "$COMPONENT_NAME" ]]; then
  echo "Usage: $0 <COMPONENT_NAME>"
  exit 1
fi

pick_best_manifest_version() {
  local component="$1"
  local manifest="$2"
  shift 2
  local candidates=("$@")
  local candidate

  for candidate in "${candidates[@]}"; do
    if manifest_has_release "$manifest" "$candidate"; then
      echo "$candidate"
      return
    fi
  done

  latest_manifest_release "$manifest"
}

resolve_bmm_main() {
  local component="$1"
  local manifest="$2"

  case "$component" in
    BASE)
      pick_best_manifest_version "$component" "$manifest" "1.3.0" "1.2.0" "1.1.0"
      ;;
    AM)
      pick_best_manifest_version "$component" "$manifest" "2.4.0" "2.3.0" "2.2.0" "1.4.0"
      ;;
    RM)
      pick_best_manifest_version "$component" "$manifest" "1.2.0" "1.1.0" "1.0.4"
      ;;
    LANG)
      pick_best_manifest_version "$component" "$manifest" "1.1.0" "1.0.0"
      ;;
    *)
      latest_manifest_release "$manifest"
      ;;
  esac
}

resolve_bmm_dependencies() {
  local component="$1"
  local main_version="$2"

  case "$component:$main_version" in
    # AM 1.4.0 BMM declares includes openehr_base_1.3.0 (needed for CODE_PHRASE).
    AM:1.4.0) echo "openehr_base_1.3.0" ;;
    # AM 2.2.0/2.3.0 rules and archetype tables reference STATEMENT, ASSERTION, EXPR_*,
    # defined only in LANG 1.1.0 (and BASE 1.0.4); LANG 1.1.0 is loaded for link resolution.
    # AM 2.3.0+ also needs LANG 1.0.0 for EL_BOOLEAN_EXPRESSION (P_ARCHETYPE.rules).
    AM:2.2.0) echo "openehr_lang_1.1.0 openehr_base_1.1.0" ;;
    AM:2.3.0) echo "openehr_lang_1.0.0 openehr_lang_1.1.0 openehr_base_1.2.0" ;;
    AM:2.4.0) echo "openehr_lang_1.0.0 openehr_lang_1.1.0 openehr_base_1.3.0" ;;
    RM:1.0.4) echo "openehr_base_1.1.0" ;;
    RM:1.1.0) echo "openehr_base_1.2.0" ;;
    RM:1.2.0) echo "openehr_base_1.3.0" ;;
    LANG:1.1.0) echo "openehr_base_1.3.0" ;;
    # Older releases: their BMMs declare no `includes`. Use the BASE release current at
    # their release date; BASE 1.0.4 is the oldest BASE BMM available for RM 1.0.2/1.0.3.
    RM:1.0.2|RM:1.0.3) echo "openehr_base_1.0.4" ;;
    LANG:1.0.0) echo "openehr_base_1.1.0" ;;
    TERM:3.0.0) echo "openehr_base_1.2.0" ;;
    TERM:3.1.0) echo "openehr_base_1.3.0" ;;
    *) echo "" ;;
  esac
}

# bmm_includes_from_resource <bmm_id>
#   Prints the schema ids listed under `includes` in the BMM (local overlay first,
#   then the publisher image), space-separated; empty if none.
bmm_includes_from_resource() {
  local id="$1"
  local file="" tmp="" cid

  if [[ -n "${BMM_RESOURCES_OVERLAY:-}" && -f "${BMM_RESOURCES_OVERLAY}/${id}.bmm.json" ]]; then
    file="${BMM_RESOURCES_OVERLAY}/${id}.bmm.json"
  elif [[ -f "computable/BMM/${id}.bmm.json" ]]; then
    file="computable/BMM/${id}.bmm.json"
  else
    tmp="$(mktemp -d)"
    if cid="$(docker create --entrypoint /bin/true "$DOCKER_IMAGE" 2>/dev/null)"; then
      docker cp "$cid:/app/resources/${id}.bmm.json" "$tmp/${id}.bmm.json" >/dev/null 2>&1 \
        && file="$tmp/${id}.bmm.json"
      docker rm "$cid" >/dev/null 2>&1 || true
    fi
  fi

  if [[ -n "$file" ]]; then
    jq -r '[.includes // {} | .[] | .id] | join(" ")' "$file" 2>/dev/null || true
  fi
  [[ -z "$tmp" ]] || rm -rf "$tmp"
}

# known_unresolved_types <bmm_id>
#   Types a schema references that no schema loadable as its dependency defines.
known_unresolved_types() {
  case "$1" in
    # C_OBJECT is an AM class; LANG cannot depend on AM.
    openehr_lang_1.0.0) echo "C_OBJECT" ;;
    # P_BMM_SINGLE_PROPERTY_OPEN.bmm_property: BMM_PROPERTY<BMM_OPEN_TYPE>; BASE 1.0.4
    # never defined BMM_OPEN_TYPE (unlinked in the legacy UML table too).
    openehr_base_1.0.4) echo "BMM_OPEN_TYPE" ;;
    *) echo "" ;;
  esac
}

validate_generated_classes() {
  local output_dir="$1"
  if ! compgen -G "${output_dir}/*.adoc" >/dev/null; then
    echo "Error: bmm-publisher generated no class .adoc files in ${output_dir}"
    exit 1
  fi

  if grep -rqE "include::\\{uml_export_dir\\}/classes/|include::\\.\\./UML/.*/classes/" "$output_dir"; then
    echo "Error: Generated class files still contain legacy UML include paths"
    exit 1
  fi

  # bmm-publisher renders types no loaded schema defines as dead `link:/classes/<Type>`
  # links, usually because a dependency schema was not passed with -d. Types listed by
  # known_unresolved_types for the generated schemas are accepted.
  local unresolved allowed="" id
  for id in "${MAIN_IDS[@]}"; do
    allowed+=" $(known_unresolved_types "$id")"
  done
  unresolved="$(grep -rhoE 'link:/classes/[A-Za-z0-9_]*' modules/ROOT/partials/classes \
    modules/ROOT/partials/definitions modules/ROOT/partials/effective 2>/dev/null \
    | sed 's#link:/classes/##' \
    | grep -vxF -f <(printf '%s\n' $allowed | grep . || true) \
    | sort | uniq -c | sort -rn || true)"
  if [ -n "$unresolved" ]; then
    echo "Error: generated partials contain unresolved type links (link:/classes/<Type>):"
    echo "$unresolved" | head -20
    if [[ -z "${BMM_ALLOW_UNRESOLVED:-}" ]]; then
      echo "Pass the missing schema with BMM_DEP_FILES, or set BMM_ALLOW_UNRESOLVED=1 to continue."
      exit 1
    fi
    echo "  • BMM_ALLOW_UNRESOLVED is set; continuing"
  fi
}

collect_generated_artifacts() {
  local main_id="$1"
  local target_root="$2"
  local generated_root="${STAGING_ROOT}/${main_id}"

  # Promote Adoc/<id>/* into ROOT partials (except images/ → ROOT images; plantUML/ not kept under partials/).
  if [ -d "$generated_root" ]; then
    local item name rel dest
    for item in "$generated_root"/*; do
      [ -e "$item" ] || continue
      name="$(basename "$item")"
      if [[ "$name" == "images" || "$name" == "plantUML" ]]; then
        continue
      fi
      dest="${target_root}/${name}"
      mkdir -p "$dest"

      while IFS= read -r -d '' rel; do
        [[ "$rel" == *.puml ]] && continue
        if [ -d "$item/$rel" ]; then
          mkdir -p "$dest/$rel"
        else
          mkdir -p "$(dirname "$dest/$rel")"
          cp -f -- "$item/$rel" "$dest/$rel"
        fi
      done < <(cd "$item" && find . -mindepth 1 -print0)

      find "$dest" -type f -name '*.puml' -delete 2>/dev/null || true
    done
  fi
}

collect_generated_publisher_images() {
  local main_id="$1"
  local dest_images_root="$2"
  local src="${STAGING_ROOT}/${main_id}/images"

  [ -d "$src" ] || return 0

  local f rel copied=0
  while IFS= read -r -d '' f; do
    rel="${f#"${src}/"}"
    mkdir -p "$(dirname "${dest_images_root}/${rel}")"
    cp -f -- "$f" "${dest_images_root}/${rel}"
    copied=$((copied + 1))
  done < <(find "$src" -type f \( -name '*.svg' -o -name '*.SVG' \) -print0 2>/dev/null)

  if [ "$copied" -gt 0 ]; then
    echo "  • publisher SVGs ($copied files) → ${dest_images_root}/ (from Adoc/${main_id}/images/)"
  fi
}

cleanup_staging_output() {
  rm_rf_repo_path "modules/ROOT/partials/.bmm-output-scratch"
  rm_rf_repo_path "$STAGING_ROOT"
}

is_tracked_path() {
  local path="$1"
  git ls-files --error-unmatch "$path" >/dev/null 2>&1
}

remove_legacy_class_file() {
  local path="$1"
  [ -f "$path" ] || return 0
  if is_tracked_path "$path"; then
    git rm -f -- "$path" >/dev/null
  else
    rm -f -- "$path"
  fi
}

cleanup_empty_parent_dirs() {
  local dir="$1"
  while [ -n "$dir" ] && [ "$dir" != "." ] && [ "$dir" != "/" ]; do
    rmdir "$dir" 2>/dev/null || break
    dir="$(dirname "$dir")"
  done
}

reconcile_legacy_class_files() {
  local output_dir="$1"
  local mapped=0
  local removed=0

  # Legacy class files historically lived under docs/**/UML/classes/*.adoc.
  local -a legacy_files=()
  while IFS= read -r f; do
    legacy_files+=("$f")
  done < <(find docs -type f -path "*/[Uu][Mm][Ll]/classes/*.adoc" 2>/dev/null | sort)

  [ "${#legacy_files[@]}" -gt 0 ] || return 0

  declare -A legacy_for_name
  local lf base
  for lf in "${legacy_files[@]}"; do
    base="$(basename "$lf")"
    # Keep first match deterministically (sorted order).
    if [ -z "${legacy_for_name[$base]:-}" ]; then
      legacy_for_name[$base]="$lf"
    fi
  done

  local generated generated_tmp legacy
  for generated in "$output_dir"/*.adoc; do
    [ -f "$generated" ] || continue
    base="$(basename "$generated")"
    legacy="${legacy_for_name[$base]:-}"
    [ -n "$legacy" ] || continue
    [ -f "$legacy" ] || continue

    generated_tmp="${generated}.generated-tmp"
    mv -f -- "$generated" "$generated_tmp"
    git_move_preserve_history "$legacy" "$generated"
    mv -f -- "$generated_tmp" "$generated"
    cleanup_empty_parent_dirs "$(dirname "$legacy")"
    unset 'legacy_for_name[$base]'
    mapped=$((mapped + 1))
    echo "  • legacy class mapped via git mv: $legacy → $generated"
  done

  # Remove remaining legacy class files that do not map 1:1 to new outputs.
  for lf in "${legacy_files[@]}"; do
    [ -f "$lf" ] || continue
    remove_legacy_class_file "$lf"
    cleanup_empty_parent_dirs "$(dirname "$lf")"
    removed=$((removed + 1))
  done

  if [ "$mapped" -gt 0 ] || [ "$removed" -gt 0 ]; then
    echo "→ Legacy UML class cleanup: mapped=$mapped, removed=$removed"
  fi
}

echo "Step 3a: Generating UML class partials via bmm-publisher..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Old release branches (e.g. RM release/1.0.3, AM release/1.4.0) carry no manifest.json;
# take the version from the branch name instead.
BRANCH_VERSION=""
if [ ! -f "$MANIFEST_PATH" ] && [ -z "${BMM_MAIN_FILE:-}" ]; then
  BRANCH_NAME="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
  if [[ "$BRANCH_NAME" =~ ^release/([0-9]+\.[0-9]+\.[0-9]+)$ ]]; then
    BRANCH_VERSION="${BASH_REMATCH[1]}"
  else
    echo "No manifest.json found in $(pwd) and branch '${BRANCH_NAME}' is not release/X.Y.Z; skipping bmm-publisher generation."
    echo ""
    exit 0
  fi
fi

if [ -n "${BMM_MAIN_FILE:-}" ]; then
  MAIN_IDS=("$BMM_MAIN_FILE")
  RESOLUTION_MODE="external override"
else
  if [ -n "$BRANCH_VERSION" ]; then
    MAIN_VERSION="$BRANCH_VERSION"
  else
    MAIN_VERSION="$(resolve_bmm_main "$COMPONENT_NAME" "$MANIFEST_PATH")"
  fi
  if [ -z "$MAIN_VERSION" ]; then
    echo "No BMM version resolved for component $COMPONENT_NAME from $MANIFEST_PATH; skipping bmm-publisher generation."
    echo ""
    exit 0
  fi
  MAIN_ID="$(to_bmm_id "$COMPONENT_NAME" "$MAIN_VERSION")"
  MAIN_IDS=("$MAIN_ID")
  # AM content references both aom14.* and aom2.* class partial series.
  if [[ "$COMPONENT_NAME" == "AM" ]]; then
    if [[ "$MAIN_ID" == "openehr_am_1.4.0" ]]; then
      # AM release/1.4.0 also carries the AOM2 pages; 2.2.0 is the oldest AOM2 BMM.
      MAIN_IDS=("openehr_am_1.4.0" "openehr_am_2.2.0")
    else
      MAIN_IDS=("openehr_am_1.4.0" "$MAIN_ID")
    fi
  fi
  if [ -n "$BRANCH_VERSION" ]; then
    RESOLUTION_MODE="branch-name"
  else
    RESOLUTION_MODE="manifest-driven"
  fi
fi

echo "→ Repo: $REPO_NAME"
echo "→ Component: $COMPONENT_NAME"
echo "→ Output dir: $OUTPUT_DIR"

AVAILABLE_MAIN_IDS=()
for MAIN_ID in "${MAIN_IDS[@]}"; do
  if bmm_resource_available "$MAIN_ID"; then
    AVAILABLE_MAIN_IDS+=("$MAIN_ID")
  else
    echo "  • no BMM resource available for ${MAIN_ID}; skipping this publisher input"
  fi
done

if [ "${#AVAILABLE_MAIN_IDS[@]}" -eq 0 ]; then
  echo "No resolvable BMM resources for component $COMPONENT_NAME; skipping bmm-publisher generation."
  echo ""
  exit 0
fi

MAIN_IDS=("${AVAILABLE_MAIN_IDS[@]}")

mkdir -p "$OUTPUT_DIR" \
  modules/ROOT/partials/definitions \
  modules/ROOT/partials/effective \
  modules/ROOT/partials/BMMs \
  "$ROOT_IMAGES_DIR"
rm -f "$OUTPUT_DIR"/*.adoc
# Regenerated publisher SVG outputs only (do not remove other ROOT/images assets).
rm -rf "${ROOT_IMAGES_DIR}/uml/classes" "${ROOT_IMAGES_DIR}/uml/diagrams" 2>/dev/null || true

trap cleanup_bmm_resources_merged_dir EXIT
# Seed the component model(s) into the repo. Dependency models stay resolved from
# the publisher image unless the repo supplies an explicit computable/BMM overlay.
seed_missing_bmm_resources_from_image "${MAIN_IDS[@]}"
if prepare_bmm_resources_overlay; then
  :
fi

GENERATED_COUNT=0
for MAIN_ID in "${MAIN_IDS[@]}"; do
  if [ -n "${BMM_DEP_FILES:-}" ]; then
    DEP_IDS="${BMM_DEP_FILES}"
    DEP_MODE="external override"
  else
    MAIN_VERSION_NORMALIZED="$(echo "$MAIN_ID" | sed -E 's/^openehr_[a-z]+_//')"
    DEP_IDS="$(resolve_bmm_dependencies "$COMPONENT_NAME" "$MAIN_VERSION_NORMALIZED")"
    DEP_MODE="version map"
    if [ -z "$DEP_IDS" ]; then
      DEP_IDS="$(bmm_includes_from_resource "$MAIN_ID")"
      DEP_MODE="BMM includes"
    fi
  fi

  echo "→ Main BMM id ($RESOLUTION_MODE): $MAIN_ID"
  if [ -n "$DEP_IDS" ]; then
    echo "  Dependency ids ($DEP_MODE): $DEP_IDS"
  else
    echo "  Dependency ids: none"
  fi

  REQUIRED_IDS=("$MAIN_ID")
  if [ -n "$DEP_IDS" ]; then
    # shellcheck disable=SC2206
    DEP_ID_ARRAY=($DEP_IDS)
    REQUIRED_IDS+=("${DEP_ID_ARRAY[@]}")
  fi

  if ! bmm_resources_available "${REQUIRED_IDS[@]}"; then
    continue
  fi

  docker_run=(docker run --rm)
  if [[ -z "${BMM_PUBLISHER_AS_ROOT:-}" ]]; then
    docker_run+=(--user "$(id -u):$(id -g)" -e HOME=/tmp)
  fi
  docker_run+=(-v "$(pwd)/modules/ROOT/partials:/app/output")
  if [[ -n "${BMM_RESOURCES_MERGED_DIR:-}" ]]; then
    docker_run+=(-v "${BMM_RESOURCES_MERGED_DIR}:/app/resources")
  fi
  docker_run+=("$DOCKER_IMAGE" asciidoc "$MAIN_ID")
  for dep in $DEP_IDS; do
    docker_run+=(-d "$dep")
  done
  "${docker_run[@]}"

  collect_generated_artifacts "$MAIN_ID" "modules/ROOT/partials"
  collect_generated_publisher_images "$MAIN_ID" "$ROOT_IMAGES_DIR"
  GENERATED_COUNT=$((GENERATED_COUNT + 1))
done

if [ "$GENERATED_COUNT" -eq 0 ]; then
  cleanup_staging_output
  cleanup_bmm_resources_merged_dir
  trap - EXIT
  echo "No complete BMM input set available for component $COMPONENT_NAME; skipping bmm-publisher generation."
  echo ""
  exit 0
fi

validate_generated_classes "$OUTPUT_DIR"
reconcile_legacy_class_files "$OUTPUT_DIR"
cleanup_staging_output
cleanup_bmm_resources_merged_dir
trap - EXIT
echo "✓ Generated UML class partials in $OUTPUT_DIR"
if find "${ROOT_IMAGES_DIR}/uml" -type f -name '*.svg' 2>/dev/null | read -r _; then
  echo "✓ Publisher SVG assets under ${ROOT_IMAGES_DIR}/uml/"
fi
echo ""
