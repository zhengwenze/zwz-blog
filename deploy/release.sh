#!/usr/bin/env bash
set -euo pipefail

WEB_ROOT="${WEB_ROOT:-/var/www/zwz-blog}"
HOST_HEADER="${HOST_HEADER:-123.56.190.100}"
HEALTHCHECK_URL="${HEALTHCHECK_URL:-http://127.0.0.1}"

RELEASES_DIR="${WEB_ROOT}/releases"
CURRENT_LINK="${WEB_ROOT}/current"
INCOMING_DIR=""
NEXT_LINK=""

log() {
  printf '%s\n' "$*"
}

fail() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

cleanup() {
  if [[ -n "${NEXT_LINK}" && -L "${NEXT_LINK}" ]]; then
    rm -f -- "${NEXT_LINK}"
  fi
  if [[ -n "${INCOMING_DIR}" && -d "${INCOMING_DIR}" ]]; then
    rm -rf -- "${INCOMING_DIR}"
  fi
}

trap cleanup EXIT

usage() {
  cat >&2 <<'EOF'
Usage:
  release.sh deploy <40-char-sha> <release.tar.gz> <release.tar.gz.sha256>
  release.sh rollback <40-char-release-sha>

Optional environment variables:
  WEB_ROOT        Site root (default: /var/www/zwz-blog)
  HOST_HEADER     Host header for local checks (default: 123.56.190.100)
  HEALTHCHECK_URL Local origin URL (default: http://127.0.0.1)
EOF
}

validate_configuration() {
  [[ "${WEB_ROOT}" == /* ]] || fail "WEB_ROOT must be an absolute path"
  [[ "${WEB_ROOT}" != "/" ]] || fail "WEB_ROOT must not be /"
  [[ -n "${HOST_HEADER}" ]] || fail "HOST_HEADER must not be empty"
  [[ -n "${HEALTHCHECK_URL}" ]] || fail "HEALTHCHECK_URL must not be empty"
  command -v curl >/dev/null 2>&1 || fail "curl is required"
  command -v tar >/dev/null 2>&1 || fail "tar is required"
}

validate_sha() {
  local sha="$1"
  [[ "${sha}" =~ ^[0-9a-f]{40}$ ]] || fail "SHA must contain exactly 40 lowercase hexadecimal characters"
}

hash_file() {
  local file="$1"
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "${file}" | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "${file}" | awk '{print $1}'
  else
    fail "sha256sum or shasum is required"
  fi
}

verify_checksum() {
  local archive="$1"
  local checksum_file="$2"
  local nonempty_count checksum_line expected listed extra actual archive_name listed_name

  [[ "${archive}" == *.tar.gz ]] || fail "release archive must use the .tar.gz extension"
  [[ "${checksum_file}" == *.sha256 ]] || fail "checksum file must use the .sha256 extension"
  [[ -f "${archive}" ]] || fail "release archive does not exist: ${archive}"
  [[ -f "${checksum_file}" ]] || fail "checksum file does not exist: ${checksum_file}"

  nonempty_count="$(awk 'NF { count += 1 } END { print count + 0 }' "${checksum_file}")"
  [[ "${nonempty_count}" == "1" ]] || fail "checksum file must contain exactly one non-empty line"

  checksum_line="$(awk 'NF { print; exit }' "${checksum_file}")"
  read -r expected listed extra <<<"${checksum_line}"
  [[ -z "${extra:-}" ]] || fail "checksum entry must not contain extra fields"
  [[ "${expected:-}" =~ ^[0-9a-fA-F]{64}$ ]] || fail "checksum must be a 64-character SHA-256 digest"

  if [[ -n "${listed:-}" ]]; then
    listed="${listed#\*}"
    archive_name="$(basename -- "${archive}")"
    listed_name="$(basename -- "${listed}")"
    [[ "${listed_name}" == "${archive_name}" ]] || fail "checksum entry names a different archive"
  fi

  actual="$(hash_file "${archive}")"
  expected="$(printf '%s' "${expected}" | tr '[:upper:]' '[:lower:]')"
  [[ "${actual}" == "${expected}" ]] || fail "release archive checksum mismatch"
}

validate_archive_entries() {
  local archive="$1"
  local names details name normalized line_type

  names="$(tar -tzf "${archive}")" || fail "release archive cannot be listed"
  [[ -n "${names}" ]] || fail "release archive is empty"

  while IFS= read -r name; do
    normalized="${name}"
    while [[ "${normalized}" == ./* ]]; do
      normalized="${normalized#./}"
    done
    [[ -z "${normalized}" || "${normalized}" == "." ]] && continue
    [[ "${normalized}" != /* ]] || fail "release archive contains an absolute path"
    case "/${normalized}/" in
      */../*) fail "release archive contains a parent-directory path" ;;
    esac
  done <<<"${names}"

  details="$(tar -tvzf "${archive}")" || fail "release archive details cannot be listed"
  while IFS= read -r name; do
    [[ -z "${name}" ]] && continue
    line_type="${name:0:1}"
    case "${line_type}" in
      -|d) ;;
      *) fail "release archive may contain only regular files and directories" ;;
    esac
  done <<<"${details}"
}

extract_metadata_sha() {
  sed -nE 's/.*"sha"[[:space:]]*:[[:space:]]*"([0-9a-f]{40})".*/\1/p' "$1"
}

validate_release_tree() {
  local release_dir="$1"
  local expected_sha="$2"
  local relative_path metadata_sha
  local required_files=(
    "index.html"
    "articles/evidence-driven-ai-infra.html"
    "assets/styles.css"
    "deploy-meta.json"
  )

  [[ -d "${release_dir}" && ! -L "${release_dir}" ]] || fail "release directory is missing or is a symbolic link"
  for relative_path in "${required_files[@]}"; do
    [[ -f "${release_dir}/${relative_path}" && ! -L "${release_dir}/${relative_path}" ]] \
      || fail "release is missing required regular file: ${relative_path}"
  done

  metadata_sha="$(extract_metadata_sha "${release_dir}/deploy-meta.json")"
  [[ "${metadata_sha}" == "${expected_sha}" ]] || fail "deploy-meta.json SHA does not match the requested release"
}

current_target() {
  local target current_sha
  if [[ -L "${CURRENT_LINK}" ]]; then
    target="$(readlink "${CURRENT_LINK}")"
    current_sha="$(basename -- "${target}")"
    validate_sha "${current_sha}"
    [[ "${target}" == "${RELEASES_DIR}/${current_sha}" ]] \
      || fail "current must point to a release under ${RELEASES_DIR}"
    printf '%s\n' "${target}"
  elif [[ -e "${CURRENT_LINK}" ]]; then
    fail "current exists but is not a symbolic link"
  fi
}

atomic_switch() {
  local target="$1"
  NEXT_LINK="${WEB_ROOT}/.current.$$.next"
  rm -f -- "${NEXT_LINK}"
  ln -s "${target}" "${NEXT_LINK}"

  if mv --version >/dev/null 2>&1; then
    mv -Tf "${NEXT_LINK}" "${CURRENT_LINK}"
  else
    mv -hf "${NEXT_LINK}" "${CURRENT_LINK}"
  fi
  NEXT_LINK=""
}

health_check() {
  local expected_sha="$1"
  local base_url path response metadata_sha
  local paths=(
    "/"
    "/articles/evidence-driven-ai-infra.html"
    "/assets/styles.css"
  )

  base_url="${HEALTHCHECK_URL%/}"
  for path in "${paths[@]}"; do
    curl --fail --silent --show-error \
      --connect-timeout 5 --max-time 10 \
      -H "Host: ${HOST_HEADER}" \
      -o /dev/null "${base_url}${path}" || return 1
  done

  response="$(curl --fail --silent --show-error \
    --connect-timeout 5 --max-time 10 \
    -H "Host: ${HOST_HEADER}" \
    "${base_url}/deploy-meta.json")" || return 1
  metadata_sha="$(printf '%s\n' "${response}" \
    | sed -nE 's/.*"sha"[[:space:]]*:[[:space:]]*"([0-9a-f]{40})".*/\1/p')"
  [[ "${metadata_sha}" == "${expected_sha}" ]]
}

restore_previous() {
  local previous_target="$1"
  local previous_sha="$2"
  if [[ -n "${previous_target}" ]]; then
    atomic_switch "${previous_target}"
    health_check "${previous_sha}" || return 1
  else
    rm -f -- "${CURRENT_LINK}"
  fi
}

switch_and_check() {
  local target_dir="$1"
  local target_sha="$2"
  local previous_target="$3"
  local previous_sha="$4"

  atomic_switch "${target_dir}"
  if ! health_check "${target_sha}"; then
    printf 'ERROR: health check failed for %s; restoring previous release\n' "${target_sha}" >&2
    if ! restore_previous "${previous_target}" "${previous_sha}"; then
      fail "health check failed and the previous release could not be restored cleanly"
    fi
    fail "health check failed; previous release restored"
  fi
}

deploy_release() {
  local sha="$1"
  local archive="$2"
  local checksum_file="$3"
  local release_dir previous_target previous_sha

  validate_sha "${sha}"
  verify_checksum "${archive}" "${checksum_file}"
  validate_archive_entries "${archive}"

  mkdir -p -- "${RELEASES_DIR}"
  INCOMING_DIR="${WEB_ROOT}/.incoming-${sha}"
  rm -rf -- "${INCOMING_DIR}"
  mkdir -- "${INCOMING_DIR}"
  tar -xzf "${archive}" -C "${INCOMING_DIR}"
  validate_release_tree "${INCOMING_DIR}" "${sha}"

  release_dir="${RELEASES_DIR}/${sha}"
  if [[ -e "${release_dir}" || -L "${release_dir}" ]]; then
    validate_release_tree "${release_dir}" "${sha}"
    rm -rf -- "${INCOMING_DIR}"
    INCOMING_DIR=""
  else
    mv -- "${INCOMING_DIR}" "${release_dir}"
    INCOMING_DIR=""
  fi

  previous_target="$(current_target)"
  if [[ -n "${previous_target}" ]]; then
    previous_sha="$(basename -- "${previous_target}")"
  else
    previous_sha="none"
  fi

  switch_and_check "${release_dir}" "${sha}" "${previous_target}" "${previous_sha}"
  log "PREVIOUS_RELEASE_SHA=${previous_sha}"
  log "DEPLOYED_SHA=${sha}"
}

rollback_release() {
  local sha="$1"
  local release_dir previous_target previous_sha

  validate_sha "${sha}"
  release_dir="${RELEASES_DIR}/${sha}"
  validate_release_tree "${release_dir}" "${sha}"

  previous_target="$(current_target)"
  if [[ -n "${previous_target}" ]]; then
    previous_sha="$(basename -- "${previous_target}")"
  else
    previous_sha="none"
  fi

  switch_and_check "${release_dir}" "${sha}" "${previous_target}" "${previous_sha}"
  log "PREVIOUS_RELEASE_SHA=${previous_sha}"
  log "DEPLOYED_SHA=${sha}"
}

main() {
  local command="${1:-}"
  validate_configuration

  case "${command}" in
    deploy)
      [[ "$#" -eq 4 ]] || { usage; exit 2; }
      deploy_release "$2" "$3" "$4"
      ;;
    rollback)
      [[ "$#" -eq 2 ]] || { usage; exit 2; }
      rollback_release "$2"
      ;;
    *)
      usage
      exit 2
      ;;
  esac
}

main "$@"
