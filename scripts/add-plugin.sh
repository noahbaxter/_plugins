#!/usr/bin/env bash
# Add a plugin to the hub: register it as a submodule and seed a plugins.json entry.
#
# Usage: scripts/add-plugin.sh <name> <owner/repo> [branch]
#   scripts/add-plugin.sh guillotine noahbaxter/guillotine main
#
# Idempotent: re-running for an existing plugin re-checks the submodule and leaves
# the plugins.json entry alone. Fill in the printed TODO fields by hand afterwards.

source "$(dirname "$0")/lib.sh"
require_tools

usage() { sed -n '2,11p' "$0"; exit "${1:-0}"; }
[ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ] && usage 0
[ $# -ge 2 ] || usage 1

NAME="$1"
REPO="$2"
BRANCH="${3:-main}"
SUB_PATH="plugins/$NAME"

cd "$HUB_ROOT" || die "cannot cd to $HUB_ROOT"

if [ -d "$SUB_PATH/.git" ] || git config -f .gitmodules --get "submodule.$SUB_PATH.url" >/dev/null 2>&1; then
  echo "submodule $SUB_PATH already registered; ensuring it is checked out"
  git submodule update --init "$SUB_PATH"
else
  echo "adding submodule $REPO at $SUB_PATH (branch $BRANCH)"
  git submodule add -b "$BRANCH" "https://github.com/$REPO.git" "$SUB_PATH"
  # Pin the branch so `git submodule update --remote` tracks the plugin's latest.
  git config -f .gitmodules "submodule.$SUB_PATH.branch" "$BRANCH"
fi

if plugin_exists "$NAME"; then
  echo "plugins.json already has an entry for '$NAME' — leaving it untouched"
else
  echo "seeding plugins.json entry for '$NAME'"
  tmp="$(mktemp)"
  jq --arg n "$NAME" --arg r "$REPO" --arg b "$BRANCH" '
    .[$n] = {
      repo: $r,
      branch: $b,
      target: "TODO_CMAKE_TARGET",
      productName: "TODO_PRODUCT_NAME",
      bundleId: "com.dichoticstudios.\($n)",
      r2Bucket: "vst-\($n)",
      windowsInstaller: "scripts/installer/windows/installer.iss",
      downloadBaseUrl: "https://dichoticstudios.com",
      manifestPath: "static/updates/\($n).json",
      webBuild: null
    }' plugins.json > "$tmp" && mv "$tmp" plugins.json
fi

cat <<EOF

Done. Still TODO for '$NAME' (read $SUB_PATH/CMakeLists.txt):
  - target            CMake target name (build/<target>_artefacts/...)
  - productName       bundle basename, e.g. "Guillotine Clip" (may differ from target)
  - bundleId          confirm com.dichoticstudios.<...>
  - r2Bucket          confirm the R2 bucket exists
  - windowsInstaller  path to the .iss (pewpew: scripts/installer/windows, guillotine: installer/windows)
  - downloadBaseUrl   public URL for the update manifest's "url" field
  - webBuild          null, or { "dir": "web", "usesWebplugUi": true|false }

Also add '$NAME' to the workflow_dispatch 'plugin' choice list in
.github/workflows/release.yml so you can pick it from the Actions UI.
EOF
