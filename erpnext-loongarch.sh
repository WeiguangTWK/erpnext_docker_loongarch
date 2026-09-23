#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE_FILE="${ROOT_DIR}/compose.yaml"
ENV_FILE="${ROOT_DIR}/.env"
CONTAINERFILE="${ROOT_DIR}/Containerfile.production"
DEFAULT_IMAGE="erpnext-loong64:16.35.0"

DOCKER=()

ensure_docker() {
  if ((${#DOCKER[@]})); then
    return
  fi
  if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
    DOCKER=(docker)
  elif command -v sudo >/dev/null 2>&1 && command -v docker >/dev/null 2>&1; then
    DOCKER=(sudo docker)
  else
    echo "Docker CLI or Docker daemon is not accessible." >&2
    exit 1
  fi
}

docker_cmd() {
  ensure_docker
  "${DOCKER[@]}" "$@"
}

compose() {
  docker_cmd compose --env-file "${ENV_FILE}" -f "${COMPOSE_FILE}" "$@"
}

env_value() {
  local key="$1"
  if [[ -f "${ENV_FILE}" ]]; then
    sed -n "s/^${key}=//p" "${ENV_FILE}" | tail -n 1
  fi
}

random_secret() {
  if command -v python3 >/dev/null 2>&1; then
    python3 -c 'import secrets; print(secrets.token_urlsafe(32))'
  elif command -v openssl >/dev/null 2>&1; then
    openssl rand -base64 36 | tr -d '\n'
  else
    echo "python3 or openssl is required to generate secrets." >&2
    exit 1
  fi
}

require_loongarch() {
  local arch
  arch="$(uname -m)"
  case "${arch}" in
    loongarch64|loong64) ;;
    *)
      if [[ "${ALLOW_EMULATION:-0}" != "1" ]]; then
        echo "This build targets LoongArch; host architecture is ${arch}." >&2
        echo "Set ALLOW_EMULATION=1 only if binfmt emulation is intentionally configured." >&2
        exit 1
      fi
      ;;
  esac
}

init_env() {
  if [[ -e "${ENV_FILE}" ]]; then
    echo "Keeping existing ${ENV_FILE}"
    return
  fi

  umask 077
  cat >"${ENV_FILE}" <<EOF
ERP_IMAGE=${ERP_IMAGE:-${DEFAULT_IMAGE}}
SITE_NAME=${SITE_NAME:-frontend}
HTTP_PORT=${HTTP_PORT:-8080}
DB_PASSWORD=$(random_secret)
ADMIN_PASSWORD=$(random_secret)
GUNICORN_WORKERS=${GUNICORN_WORKERS:-2}
GUNICORN_THREADS=${GUNICORN_THREADS:-4}
EOF
  chmod 600 "${ENV_FILE}"
  echo "Created ${ENV_FILE} with random database and Administrator passwords."
}

build_image() {
  require_loongarch
  init_env

  local image
  image="$(env_value ERP_IMAGE)"
  image="${image:-${DEFAULT_IMAGE}}"

  docker_cmd build \
    --platform linux/loong64 \
    --progress "${BUILDKIT_PROGRESS:-plain}" \
    --build-arg "FRAPPE_VERSION=${FRAPPE_VERSION:-v16.34.0}" \
    --build-arg "ERPNEXT_VERSION=${ERPNEXT_VERSION:-v16.35.0}" \
    --build-arg "MYSQLCLIENT_VERSION=${MYSQLCLIENT_VERSION:-2.2.7}" \
    --build-arg "DUCKDB_VERSION=${DUCKDB_VERSION:-1.4.3}" \
    --build-arg "BANKING_VITE_VERSION=${BANKING_VITE_VERSION:-7.2.2}" \
    --build-arg "BANKING_REACT_PLUGIN_VERSION=${BANKING_REACT_PLUGIN_VERSION:-5.1.1}" \
    --build-arg "LIGHTNINGCSS_LOONG64_VERSION=${LIGHTNINGCSS_LOONG64_VERSION:-1.33.0}" \
    --build-arg "TAILWIND_OXIDE_LOONG64_VERSION=${TAILWIND_OXIDE_LOONG64_VERSION:-4.3.2}" \
    -f "${CONTAINERFILE}" \
    -t "${image}" \
    "${ROOT_DIR}"

  docker_cmd run --rm "${image}" bash -lc '
    set -e
    test "$(uname -m)" = loongarch64
    test -L sites/assets
    test -f sites/assets/assets.json
    command -v nginx-entrypoint.sh >/dev/null
    env/bin/python -c "import MySQLdb, duckdb, pyarrow, cryptography, orjson, PIL, frappe, erpnext"
    bench version
  '

  docker_cmd image inspect "${image}" \
    --format 'Built {{.RepoTags}} architecture={{.Architecture}} size={{.Size}} bytes'
}

up_stack() {
  require_loongarch
  init_env
  compose config --quiet

  local image
  image="$(env_value ERP_IMAGE)"
  image="${image:-${DEFAULT_IMAGE}}"
  if ! docker_cmd image inspect "${image}" >/dev/null 2>&1; then
    echo "Image ${image} is absent; building it first."
    build_image
  fi

  compose pull db redis-cache redis-queue
  compose up -d
  compose ps -a
}

verify_stack() {
  init_env
  compose ps -a
  compose exec -T backend bench --site "$(env_value SITE_NAME)" list-apps
  compose exec -T backend bench --site "$(env_value SITE_NAME)" doctor

  local port
  port="$(env_value HTTP_PORT)"
  port="${port:-8080}"
  if command -v curl >/dev/null 2>&1; then
    curl --fail --silent --show-error \
      --output /dev/null \
      --write-out 'HTTP %{http_code} in %{time_total}s\n' \
      "http://127.0.0.1:${port}/"
  fi
}

show_help() {
  cat <<'EOF'
Usage: ./erpnext-loongarch.sh COMMAND

Commands:
  init      Generate .env with random secrets without overwriting an existing file
  build     Build and smoke-test the native linux/loong64 ERPNext image
  up        Initialize configuration, build when needed, and start the full stack
  verify    Check containers, installed apps, scheduler, workers, and HTTP
  status    Show all Compose containers
  logs      Follow logs from the stack
  password  Print the generated ERPNext Administrator password
  down      Stop containers while preserving all persistent volumes
EOF
}

case "${1:-help}" in
  init) init_env ;;
  build) build_image ;;
  up) up_stack ;;
  verify) verify_stack ;;
  status) init_env; compose ps -a ;;
  logs) init_env; compose logs -f --tail=200 ;;
  password) init_env; env_value ADMIN_PASSWORD ;;
  down) init_env; compose down ;;
  help|-h|--help) show_help ;;
  *) echo "Unknown command: $1" >&2; show_help >&2; exit 2 ;;
esac
