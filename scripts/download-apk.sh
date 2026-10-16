#!/usr/bin/env bash
set -euo pipefail

APK_URL="${APK_URL:-${ASTRUM_APK_URL:-}}"
APK_SHA256="${APK_SHA256:-${ASTRUM_APK_SHA256:-}}"

if [[ -z "$APK_URL" || -z "$APK_SHA256" ]]; then
  echo "Set APK_URL and APK_SHA256 (or ASTRUM_APK_URL and ASTRUM_APK_SHA256)." >&2
  exit 2
fi
if [[ "$APK_URL" != https://* ]]; then
  echo "APK_URL must use HTTPS." >&2
  exit 2
fi
if [[ ! "$APK_SHA256" =~ ^[[:xdigit:]]{64}$ ]]; then
  echo "APK_SHA256 must be a 64-character SHA-256 hex digest." >&2
  exit 2
fi

mkdir -p artifacts
tmp="artifacts/astrum.apk.part"
trap 'rm -f "$tmp"' EXIT
curl --fail --location --silent --show-error --retry 2 "$APK_URL" --output "$tmp"
printf '%s  %s\n' "$APK_SHA256" "$tmp" | sha256sum --check --status || {
  echo "Downloaded APK SHA-256 does not match the expected digest." >&2
  exit 1
}
mv "$tmp" artifacts/astrum.apk
trap - EXIT
echo "APK downloaded and SHA-256 verified."
