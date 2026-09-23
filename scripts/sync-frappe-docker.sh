#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
UPSTREAM_REPO=${FRAPPE_DOCKER_REPO:-https://github.com/frappe/frappe_docker.git}
PIN_FILE="${ROOT_DIR}/upstream/frappe_docker.commit"
PATCH_FILE="${ROOT_DIR}/patches/frappe-docker-loongarch.patch"
MODE=${1:-sync}

case "${MODE}" in
  sync|--check) ;;
  *) echo "Usage: $0 [sync|--check]" >&2; exit 2 ;;
esac

for command in git diff mktemp cp grep sed find; do
  command -v "${command}" >/dev/null 2>&1 || {
    echo "Required command is missing: ${command}" >&2
    exit 1
  }
done

COMMIT="$(tr -d '[:space:]' <"${PIN_FILE}")"
[[ "${COMMIT}" =~ ^[0-9a-f]{40}$ ]] || {
  echo "Invalid pinned commit in ${PIN_FILE}" >&2
  exit 1
}

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT
SOURCE_DIR="${TMP_DIR}/source"
GENERATED_DIR="${TMP_DIR}/generated"

git init -q "${SOURCE_DIR}"
git -C "${SOURCE_DIR}" config core.autocrlf false
git -C "${SOURCE_DIR}" remote add origin "${UPSTREAM_REPO}"
git -C "${SOURCE_DIR}" fetch -q --depth 1 origin "${COMMIT}"
git -C "${SOURCE_DIR}" checkout -q --detach FETCH_HEAD

mkdir -p "${GENERATED_DIR}/resources" "${GENERATED_DIR}/LICENSES"
cp "${SOURCE_DIR}/resources/core/main-entrypoint.sh" \
  "${GENERATED_DIR}/resources/main-entrypoint.sh"
cp "${SOURCE_DIR}/resources/core/start.sh" \
  "${GENERATED_DIR}/resources/start.sh"
cp "${SOURCE_DIR}/resources/core/nginx/nginx-entrypoint.sh" \
  "${GENERATED_DIR}/resources/nginx-entrypoint.sh"
cp "${SOURCE_DIR}/resources/core/nginx/nginx-template.conf" \
  "${GENERATED_DIR}/resources/nginx-template.conf"
cp "${SOURCE_DIR}/resources/core/nginx/security_headers.conf" \
  "${GENERATED_DIR}/resources/security_headers.conf"
cp "${SOURCE_DIR}/LICENSE" \
  "${GENERATED_DIR}/LICENSES/frappe_docker-MIT.txt"

# Keep generated resources stable even when the caller has core.autocrlf=true.
find "${GENERATED_DIR}" -type f -exec sed -i 's/\r$//' {} +

grep -q 'MIT License' "${GENERATED_DIR}/LICENSES/frappe_docker-MIT.txt" || {
  echo "Pinned upstream license is no longer the expected MIT license." >&2
  exit 1
}

git -C "${GENERATED_DIR}" apply --check "${PATCH_FILE}"
git -C "${GENERATED_DIR}" apply "${PATCH_FILE}"
find "${GENERATED_DIR}" -type f -exec sed -i 's/\r$//' {} +

if [[ "${MODE}" == "--check" ]]; then
  diff -ruN "${ROOT_DIR}/resources" "${GENERATED_DIR}/resources"
  diff -u \
    "${ROOT_DIR}/LICENSES/frappe_docker-MIT.txt" \
    "${GENERATED_DIR}/LICENSES/frappe_docker-MIT.txt"
  echo "frappe_docker-derived files match pinned commit ${COMMIT}."
  exit 0
fi

mkdir -p "${ROOT_DIR}/resources" "${ROOT_DIR}/LICENSES"
cp "${GENERATED_DIR}/resources/"* "${ROOT_DIR}/resources/"
cp "${GENERATED_DIR}/LICENSES/frappe_docker-MIT.txt" \
  "${ROOT_DIR}/LICENSES/frappe_docker-MIT.txt"

echo "Synchronized frappe_docker resources from ${COMMIT}."
echo "Applied patch: patches/frappe-docker-loongarch.patch"
