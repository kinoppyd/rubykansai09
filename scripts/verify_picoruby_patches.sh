#!/usr/bin/env bash

set -euo pipefail

PINNED_PICORUBY_REVISION="b0c1c4828b82b267dab9cabf4a372c46c2a1075e"

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
profile="${1:-host}"
source_tree="${2:-${repo_root}/tmp/picoruby-latest-r2p2}"

ble_host_patches=(
  "patches/picoruby-ble-passive-scan.patch"
  "patches/picoruby-ble-notification-listeners.patch"
  "patches/picoruby-ble-central-event-delivery.patch"
  "patches/picoruby-ble-two-connections.patch"
)

case "${profile}" in
  sensor)
    patches=()
    ;;
  host)
    patches=("${ble_host_patches[@]}")
    ;;
  host-display)
    patches=(
      "${ble_host_patches[@]}"
      "patches/picoruby-gc9a01-speedometer.patch"
    )
    ;;
  *)
    echo "usage: $0 [sensor|host|host-display] [picoruby-source-tree]" >&2
    exit 64
    ;;
esac

if [[ ! -d "${source_tree}/.git" && ! -f "${source_tree}/.git" ]]; then
  echo "not a PicoRuby git tree: ${source_tree}" >&2
  exit 66
fi

source_revision="$(git -C "${source_tree}" rev-parse HEAD)"
if [[ "${source_revision}" != "${PINNED_PICORUBY_REVISION}" ]]; then
  echo "unexpected PicoRuby revision" >&2
  echo "expected: ${PINNED_PICORUBY_REVISION}" >&2
  echo "actual:   ${source_revision}" >&2
  exit 65
fi

temporary_root="$(mktemp -d "${TMPDIR:-/tmp}/picoruby-patch-verify.XXXXXX")"
work_tree="${temporary_root}/picoruby"

cleanup() {
  rm -rf "${temporary_root}"
}
trap cleanup EXIT

mkdir -p "${work_tree}"
git -C "${source_tree}" archive HEAD | tar -x -C "${work_tree}"
git -C "${work_tree}" init -q
git -C "${work_tree}" add .
git -C "${work_tree}" \
  -c user.name="Patch Verifier" \
  -c user.email="patch-verifier@example.invalid" \
  commit -q -m baseline

echo "profile: ${profile}"
echo "source_revision: ${source_revision}"

if [[ "${profile}" != "sensor" ]]; then
  for patch_path in "${patches[@]}"; do
    absolute_patch="${repo_root}/${patch_path}"
    if [[ ! -f "${absolute_patch}" ]]; then
      echo "missing patch: ${patch_path}" >&2
      exit 66
    fi
    echo "apply: ${patch_path}"
    git -C "${work_tree}" apply --check "${absolute_patch}"
    git -C "${work_tree}" apply "${absolute_patch}"
  done
fi

git -C "${work_tree}" diff --check

if [[ "${profile}" == "sensor" ]]; then
  echo "combined_diff_sha256: none"
else
  combined_sha="$(git -C "${work_tree}" diff --binary | shasum -a 256 | awk '{print $1}')"
  echo "combined_diff_sha256: ${combined_sha}"
fi

echo "result: ok"
