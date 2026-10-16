#!/usr/bin/env bash
set -euo pipefail

required=(ASTRUM_APP_ID ASTRUM_PLAY_STORE_URL ASTRUM_TEST_NAME)
for name in "${required[@]}"; do
  if [[ -z "${!name:-}" ]]; then
    echo "Required environment variable is missing: $name" >&2
    exit 2
  fi
done

# Convert the supplied public listing URL to Android's native Play Store URI.
store_package="$(python3 -c 'from urllib.parse import urlparse, parse_qs; import os; print(parse_qs(urlparse(os.environ["ASTRUM_PLAY_STORE_URL"]).query).get("id", [""])[0])')"
if [[ "$store_package" != "$ASTRUM_APP_ID" ]]; then
  echo "The Play Store URL package id does not match ASTRUM_APP_ID." >&2
  exit 2
fi
export ASTRUM_MARKET_LINK="market://details?id=${store_package}"

# Use synthetic, unique credentials for the signup flow. Neither value is printed.
run_token="$(date -u +%Y%m%dT%H%M%SZ)-${GITHUB_RUN_ID:-local}-$(openssl rand -hex 4)"
export ASTRUM_TEST_EMAIL="astrum-e2e+${run_token}@example.com"
export ASTRUM_TEST_PASSWORD="Astrum-$(openssl rand -hex 12)!"

mkdir -p artifacts
set +e
maestro test \
  -e ASTRUM_APP_ID="$ASTRUM_APP_ID" \
  -e ASTRUM_MARKET_LINK="$ASTRUM_MARKET_LINK" \
  -e ASTRUM_TEST_EMAIL="$ASTRUM_TEST_EMAIL" \
  -e ASTRUM_TEST_PASSWORD="$ASTRUM_TEST_PASSWORD" \
  -e ASTRUM_TEST_NAME="$ASTRUM_TEST_NAME" \
  --format junit --output artifacts/maestro-report.xml .maestro/flows/01-cadastro.yaml
result=$?
set -e
if [[ $result -ne 0 ]]; then
  echo "Maestro failed. Foreground Android activity at failure:" >&2
  adb shell dumpsys activity activities 2>/dev/null | grep -m 1 'mResumedActivity' >&2 || true
  adb shell dumpsys window 2>/dev/null | grep -m 1 'mCurrentFocus' >&2 || true
  echo "Maestro reported a failing flow (exit $result)." >&2
  exit "$result"
fi
