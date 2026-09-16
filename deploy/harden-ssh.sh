#!/usr/bin/env bash
set -euo pipefail

SSHD_CONFIG="${SSHD_CONFIG:-/etc/ssh/sshd_config}"
SSHD_BACKUP="${SSHD_BACKUP:-${SSHD_CONFIG}.before-zwz-blog-hardening}"

fail() {
  printf '错误：%s\n' "$*" >&2
  exit 1
}

if [[ "${EUID}" -ne 0 ]]; then
  fail "请使用 root 用户执行 SSH 加固。"
fi

if [[ "${CONFIRM_KEY_LOGIN:-}" != "yes" ]]; then
  fail "请先在第二个终端验证管理员密钥登录，再设置 CONFIRM_KEY_LOGIN=yes。"
fi

[[ -f "${SSHD_CONFIG}" ]] || fail "找不到 sshd 配置：${SSHD_CONFIG}"
command -v sshd >/dev/null 2>&1 || fail "找不到 sshd。"

CONFIG_DIR="$(dirname "${SSHD_CONFIG}")"
TEMP_FILE="$(mktemp "${CONFIG_DIR}/.sshd_config.zwz.XXXXXX")"
ROLLBACK_FILE="$(mktemp "${CONFIG_DIR}/.sshd_config.rollback.XXXXXX")"

cleanup() {
  [[ ! -e "${TEMP_FILE}" ]] || unlink "${TEMP_FILE}"
  [[ ! -e "${ROLLBACK_FILE}" ]] || unlink "${ROLLBACK_FILE}"
}
trap cleanup EXIT

cp -p "${SSHD_CONFIG}" "${ROLLBACK_FILE}"
if [[ ! -f "${SSHD_BACKUP}" ]]; then
  cp -p "${SSHD_CONFIG}" "${SSHD_BACKUP}"
fi

awk '
  function emit_missing() {
    if (!seen_password) print "PasswordAuthentication no"
    if (!seen_keyboard) print "KbdInteractiveAuthentication no"
    if (!seen_root) print "PermitRootLogin prohibit-password"
  }
  /^[[:space:]]*Match[[:space:]]/ && !in_match {
    emit_missing()
    in_match = 1
  }
  !in_match && /^[[:space:]]*PasswordAuthentication[[:space:]]+/ {
    if (!seen_password) print "PasswordAuthentication no"
    seen_password = 1
    next
  }
  !in_match && /^[[:space:]]*KbdInteractiveAuthentication[[:space:]]+/ {
    if (!seen_keyboard) print "KbdInteractiveAuthentication no"
    seen_keyboard = 1
    next
  }
  !in_match && /^[[:space:]]*PermitRootLogin[[:space:]]+/ {
    if (!seen_root) print "PermitRootLogin prohibit-password"
    seen_root = 1
    next
  }
  { print }
  END {
    if (!in_match) emit_missing()
  }
' "${SSHD_CONFIG}" > "${TEMP_FILE}"

chmod --reference="${SSHD_CONFIG}" "${TEMP_FILE}" 2>/dev/null || chmod 0600 "${TEMP_FILE}"
chown --reference="${SSHD_CONFIG}" "${TEMP_FILE}" 2>/dev/null || chown root:root "${TEMP_FILE}"

sshd -t -f "${TEMP_FILE}" || fail "候选 sshd 配置验证失败，未修改现有配置。"
install -m 0600 "${TEMP_FILE}" "${SSHD_CONFIG}"

restore_current_config() {
  install -m 0600 "${ROLLBACK_FILE}" "${SSHD_CONFIG}"
  sshd -t
}

if ! sshd -t; then
  restore_current_config
  fail "安装后的 sshd 配置验证失败，已恢复原配置。"
fi

if systemctl reload sshd 2>/dev/null; then
  SSH_SERVICE="sshd"
elif systemctl reload ssh 2>/dev/null; then
  SSH_SERVICE="ssh"
else
  restore_current_config
  fail "SSH 服务 reload 失败，已恢复原配置。"
fi

printf 'SSH 加固完成，服务：%s\n' "${SSH_SERVICE}"
sshd -T | grep -E '^(passwordauthentication|kbdinteractiveauthentication|permitrootlogin) '
