#!/usr/bin/env bash
# Pull every plugin submodule to its latest branch tip and show which pointers moved.
#
# Usage: scripts/update-plugins.sh
#
# The hub builds releases from each submodule's REMOTE branch, so you rarely need to
# commit moved pointers just to release. This is here for local inspection / pinning.

source "$(dirname "$0")/lib.sh"
require_tools

[ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ] && { sed -n '2,9p' "$0"; exit 0; }

cd "$HUB_ROOT" || die "cannot cd to $HUB_ROOT"

before="$(git submodule status | awk '{print $2" "$1}')"
git submodule update --remote --init --recursive
after="$(git submodule status | awk '{print $2" "$1}')"

if [ "$before" = "$after" ]; then
  echo "no submodule pointers moved."
else
  echo "moved submodule pointers:"
  diff <(echo "$before") <(echo "$after") | grep -E '^[<>]' || true
  echo
  echo "commit the bump with:  git add plugins && git commit -m 'Bump plugin submodules'"
fi
