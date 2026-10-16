#!/usr/bin/env bash
set -euo pipefail

required=(ASTRUM_APP_ID ASTRUM_PLAY_STORE_URL ASTRUM_TEST_NAME)
for name in "${required[@]}"; do
  if [[ -z "${!name:-}" ]]; then
    echo "Required environment variable is missing: $name" >&2
    exit 2
  fi
done

# Use synthetic, unique credentials for the signup flow. Neither value is printed.
run_token="$(date -u +%Y%m%dT%H%M%SZ)-${GITHUB_RUN_ID:-local}-$(openssl rand -hex 4)"
export ASTRUM_TEST_EMAIL="astrum-e2e+${run_token}@example.com"
export ASTRUM_TEST_PASSWORD="Astrum-$(openssl rand -hex 12)!"

mkdir -p artifacts
set +e
maestro test \
  -e ASTRUM_APP_ID="$ASTRUM_APP_ID" \
  -e ASTRUM_PLAY_STORE_URL="$ASTRUM_PLAY_STORE_URL" \
  -e ASTRUM_TEST_EMAIL="$ASTRUM_TEST_EMAIL" \
  -e ASTRUM_TEST_PASSWORD="$ASTRUM_TEST_PASSWORD" \
  -e ASTRUM_TEST_NAME="$ASTRUM_TEST_NAME" \
  --format junit --output artifacts/maestro-report.xml .maestro/flows/01-cadastro.yaml
result=$?
set -e
if [[ $result -ne 0 ]]; then
  echo "Maestro reported a failing flow (exit $result)." >&2
  exit "$result"
fi
