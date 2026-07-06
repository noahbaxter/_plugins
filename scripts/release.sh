#!/usr/bin/env bash
# Trigger a release from the terminal via the hub's release.yml workflow.
#
# Usage: scripts/release.sh <plugin> [version]
#   scripts/release.sh pewpew 0.2.0
#   scripts/release.sh pewpew            # version omitted -> uses the plugin's VERSION file
#
# This dispatches the workflow on THIS hub repo. The workflow checks out the plugin's
# latest branch tip, builds every platform, signs+notarizes macOS, uploads to R2, cuts a
# draft GitHub release on the hub, and (by default) publishes the update manifest.

source "$(dirname "$0")/lib.sh"
require_tools
require gh

usage() { sed -n '2,12p' "$0"; exit "${1:-0}"; }
[ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ] && usage 0
[ $# -ge 1 ] || usage 1

PLUGIN="$1"
VERSION="${2:-}"

plugin_exists "$PLUGIN" || die "unknown plugin '$PLUGIN' (see: make list)"

cd "$HUB_ROOT" || die "cannot cd to $HUB_ROOT"

args=(-f "plugin=$PLUGIN")
if [ -n "$VERSION" ]; then
  args+=(-f "version=$VERSION")
  echo "dispatching release: $PLUGIN v$VERSION"
else
  echo "dispatching release: $PLUGIN (version from its VERSION file)"
fi

gh workflow run release.yml "${args[@]}"

echo "queued. Watching for the run to appear..."
sleep 4
gh run list --workflow=release.yml --limit 1
echo
echo "Follow it with:  gh run watch --exit-status \$(gh run list --workflow=release.yml --limit 1 --json databaseId --jq '.[0].databaseId')"
