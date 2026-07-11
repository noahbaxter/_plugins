#!/usr/bin/env bash
# Set every hub secret on noahbaxter/_plugins from a local .secrets.env.
#
# Usage: scripts/secrets-sync.sh [--dry-run]
#
# This is the one-time provisioning tool AND the "I rotated a key" tool. It reads
# .secrets.env (gitignored; copy from .secrets.env.example) and runs `gh secret set`
# for each non-empty value. Network-mutating: it prompts before doing anything.
#
# Apple signing secrets are easier to provision with Noah's helper instead:
#   ~/.claude/scripts/setup-apple-signing.sh noahbaxter/_plugins
# That fills the six APPLE_* secrets directly. This script will still set any APPLE_*
# values you put in .secrets.env, so use whichever path you prefer (don't double-set).

source "$(dirname "$0")/lib.sh"
require gh

DRY=0
[ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ] && { sed -n '2,15p' "$0"; exit 0; }
[ "${1:-}" = "--dry-run" ] && DRY=1

REPO="noahbaxter/_plugins"
ENV_FILE="$HUB_ROOT/.secrets.env"
[ -f "$ENV_FILE" ] || die "no $ENV_FILE (copy .secrets.env.example and fill it in)"

# Every secret the pipeline may read. Optional ones are simply skipped if blank.
KNOWN=(
  APPLE_CERTIFICATE_APPLICATION APPLE_CERTIFICATE_INSTALLER APPLE_CERTIFICATE_PASSWORD
  APPLE_ID APPLE_TEAM_ID APPLE_APP_PASSWORD
  R2_ACCESS_KEY_ID R2_SECRET_ACCESS_KEY
  PLUGINS_CI_TOKEN
  SITE_DEPLOY_SSH_KEY
)

# Load the env file without leaking values into the shell's argv.
set -a
# shellcheck disable=SC1090
source "$ENV_FILE"
set +a

to_set=()
for name in "${KNOWN[@]}"; do
  val="${!name:-}"
  [ -n "$val" ] && to_set+=("$name")
done

[ ${#to_set[@]} -gt 0 ] || die "no non-empty secrets found in $ENV_FILE"

echo "Repo:    $REPO"
echo "Secrets: ${to_set[*]}"
echo

if [ "$DRY" = 1 ]; then
  echo "(dry run) would run 'gh secret set <name>' for each of the above."
  exit 0
fi

read -r -p "Set these ${#to_set[@]} secrets on $REPO now? [y/N] " ans
[ "$ans" = "y" ] || [ "$ans" = "Y" ] || die "aborted"

for name in "${to_set[@]}"; do
  printf '%s' "${!name}" | gh secret set "$name" --repo "$REPO"
  echo "  set $name"
done
echo "done."
