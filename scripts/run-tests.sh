#!/usr/bin/env bash
set -euo pipefail

required=(ASTRUM_APP_ID ASTRUM_TEST_EMAIL_DOMAIN ASTRUM_TEST_PASSWORD ASTRUM_TEST_NAME)
for name in "${required[@]}"; do
  if [[ -z "${!name:-}" ]]; then
    echo "Required environment variable is missing: $name" >&2
    exit 2
  fi
done

# Each run gets a fresh address; configure this domain as a QA catch-all or
# use a mail provider that accepts plus-addressing for your controlled mailbox.
run_token="$(date -u +%Y%m%dT%H%M%SZ)-${GITHUB_RUN_ID:-local}-$(openssl rand -hex 4)"
export ASTRUM_TEST_EMAIL="astrum-e2e+${run_token}@${ASTRUM_TEST_EMAIL_DOMAIN}"

mkdir -p artifacts
set +e
maestro test --format junit --output artifacts/maestro-report.xml .maestro/flows
result=$?
set -e
if [[ $result -ne 0 ]]; then
  echo "Maestro reported a failing flow (exit $result)." >&2
  exit "$result"
fi
