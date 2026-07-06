#!/usr/bin/env bash
# Shared helpers for the dichotic-plugins hub scripts.
# Source this: `source "$(dirname "$0")/lib.sh"`

set -euo pipefail

HUB_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PLUGINS_JSON="$HUB_ROOT/plugins.json"

die() { echo "error: $*" >&2; exit 1; }

require() {
  command -v "$1" >/dev/null 2>&1 || die "'$1' is required but not installed"
}

require_tools() {
  require jq
  require git
}

# List every plugin name defined in plugins.json.
plugin_names() {
  jq -r 'keys[]' "$PLUGINS_JSON"
}

# True if the plugin exists in plugins.json.
plugin_exists() {
  jq -e --arg p "$1" 'has($p)' "$PLUGINS_JSON" >/dev/null 2>&1
}

# Read one field for a plugin: plugin_field <name> <jq-path-inside-entry>
# e.g. plugin_field pewpew '.repo'  ->  noahbaxter/pewpew
plugin_field() {
  jq -r --arg p "$1" ".[\$p]$2 // empty" "$PLUGINS_JSON"
}
