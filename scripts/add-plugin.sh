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
      gated: false,
      r2Bucket: "dichotic-plugins",
      cdnBaseUrl: "https://cdn.dichoticstudios.com/\($n)",
      windowsInstaller: "installer/windows/installer.iss",
      downloadBaseUrl: "https://dichoticstudios.com/download/\($n)",
      manifestPath: "static/updates/\($n).json",
      webBuild: null
    }' plugins.json > "$tmp" && mv "$tmp" plugins.json
fi

# Scaffold the plugin repo's trigger workflow (push main -> hub dry-run, tag -> publish).
# Written into the submodule working tree; commit + push it to the plugin repo, then
# set its HUB_DISPATCH_TOKEN secret (see the TODO below).
DISPATCH="$SUB_PATH/.github/workflows/release-dispatch.yml"
if [ -f "$DISPATCH" ]; then
  echo "$DISPATCH already exists — leaving it untouched"
else
  echo "scaffolding $DISPATCH"
  mkdir -p "$(dirname "$DISPATCH")"
  cat > "$DISPATCH" <<YAML
name: Dispatch release to hub

# The Dichotic plugins hub (noahbaxter/_plugins) does all the building, signing,
# CDN upload, GitHub release, and site publishing. This repo only tells it when:
#   - push to main -> hub dry-run (build all platforms, publish nothing)
#   - push a tag vX.Y.Z -> hub publish (build + release + CDN + site)
#
# Needs a HUB_DISPATCH_TOKEN secret: a fine-grained PAT with Actions: read/write
# on noahbaxter/_plugins.

on:
  push:
    branches: [main]
    tags: ['v*']

concurrency:
  group: hub-dispatch-\${{ github.ref }}
  cancel-in-progress: true

jobs:
  dispatch:
    runs-on: ubuntu-latest
    steps:
      - name: Fire the hub release workflow
        env:
          GH_TOKEN: \${{ secrets.HUB_DISPATCH_TOKEN }}
          PLUGIN: $NAME
        run: |
          set -euo pipefail
          if [ "\$GITHUB_REF_TYPE" = "tag" ]; then
            VERSION="\${GITHUB_REF_NAME#v}"
            echo "tag \$GITHUB_REF_NAME (\$GITHUB_SHA) -> publish \$PLUGIN v\$VERSION"
            gh workflow run release.yml -R noahbaxter/_plugins \\
              -f plugin="\$PLUGIN" -f version="\$VERSION" -f ref="\$GITHUB_SHA" -f dry_run=false
          else
            echo "push to \$GITHUB_REF_NAME (\$GITHUB_SHA) -> dry-run build \$PLUGIN"
            gh workflow run release.yml -R noahbaxter/_plugins \\
              -f plugin="\$PLUGIN" -f ref="\$GITHUB_SHA" -f dry_run=true
          fi
YAML
fi

cat <<EOF

Done. Still TODO for '$NAME':

1. Fill in plugins.json (read $SUB_PATH/CMakeLists.txt):
  - target            CMake target name (build/<target>_artefacts/...)
  - productName       bundle basename, e.g. "Guillotine Clip" (may differ from target)
  - bundleId          confirm com.dichoticstudios.<...>
  - gated             true for paid plugins (no public release binaries; CDN only)
  - windowsInstaller  path to the .iss (guillotine: installer/windows/installer.iss)
  - downloadBaseUrl   public URL for the update manifest's "url" field
  - webBuild          null, or { "dir": "web", "usesWebplugUi": true|false }
  (r2Bucket + cdnBaseUrl are seeded to the shared dichotic-plugins CDN.)

2. Add '$NAME' to the workflow_dispatch 'plugin' choice list in
   .github/workflows/release.yml so you can pick it from the Actions UI.

3. The plugin repo needs a CHANGELOG.md (the site changelog is generated from it,
   with '## [x.y.z] - date' or '## x.y.z' headings per release).

4. Commit + push the scaffolded $DISPATCH to $REPO, then give it the dispatch token:
     gh secret set HUB_DISPATCH_TOKEN -R $REPO < token.txt
   (the same fine-grained PAT used for PLUGINS_CI_TOKEN — Actions: read/write on _plugins).
EOF
