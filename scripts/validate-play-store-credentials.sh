#!/usr/bin/env bash
set -euo pipefail

if [[ -z "${PLAY_STORE_EMAIL:-}" ]]; then
  echo "Missing GitHub Actions secret PLAY_STORE_EMAIL. Add it in Settings > Secrets and variables > Actions." >&2
  exit 2
fi

if [[ ! "$PLAY_STORE_EMAIL" =~ ^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$ ]]; then
  echo "PLAY_STORE_EMAIL is not a valid email address. Check the secret value; its contents are not printed." >&2
  exit 2
fi

if [[ -z "${PLAY_STORE_PASSWORD:-}" ]]; then
  echo "Missing GitHub Actions secret PLAY_STORE_PASSWORD. Add it in Settings > Secrets and variables > Actions." >&2
  exit 2
fi

echo "Play Store credentials are configured (email format valid; values hidden)."
