#!/usr/bin/env bash
set -euo pipefail

if [[ -z "${APP_STORE_APPLE_ID:-}" ]]; then
  echo "Missing APP_STORE_APPLE_ID Actions secret." >&2
  exit 1
fi

if [[ -z "${APP_STORE_APPLE_PASSWORD:-}" ]]; then
  echo "Missing APP_STORE_APPLE_PASSWORD Actions secret." >&2
  exit 1
fi

if [[ ! "$APP_STORE_APPLE_ID" =~ ^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$ ]]; then
  echo "APP_STORE_APPLE_ID must be a valid email address." >&2
  exit 1
fi

echo "App Store account secrets are configured (values are hidden)."
