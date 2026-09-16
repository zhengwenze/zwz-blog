#!/usr/bin/env bash
set -euo pipefail

DEPLOY_USER="${DEPLOY_USER:-deploy}"
WEB_ROOT="${WEB_ROOT:-/var/www/zwz-blog}"
NGINX_CONFIG_SOURCE="${NGINX_CONFIG_SOURCE:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/nginx.conf}"
NGINX_CONFIG_TARGET="${NGINX_CONFIG_TARGET:-/etc/nginx/conf.d/zwz-blog.conf}"
PUBLIC_URL="${PUBLIC_URL:-http://123.56.190.100}"
HOST_HEADER="${HOST_HEADER:-123.56.190.100}"

fail() {
  printf '错误：%s\n' "$*" >&2
  exit 1
}

if [[ "${EUID}" -ne 0 ]]; then
  fail "请使用 root 用户执行一次性 CI/CD 初始化。"
fi

if [[ -z "${DEPLOY_PUBLIC_KEY:-}" ]]; then
  fail "必须通过 DEPLOY_PUBLIC_KEY 提供 GitHub Actions 专用 SSH 公钥。"
fi

if [[ ! "${DEPLOY_USER}" =~ ^[a-z_][a-z0-9_-]*$ ]]; then
  fail "DEPLOY_USER 格式无效。"
fi

if [[ ! "${DEPLOY_PUBLIC_KEY}" =~ ^ssh-(ed25519|rsa)[[:space:]]+[A-Za-z0-9+/=]+([[:space:]].*)?$ ]]; then
  fail "DEPLOY_PUBLIC_KEY 不是受支持的 OpenSSH 公钥。"
fi

if ! command -v nginx >/dev/null 2>&1; then
  fail "未安装 nginx，请先运行 deploy/install.sh。"
fi

if [[ ! -f "${NGINX_CONFIG_SOURCE}" ]]; then
  fail "找不到 Nginx 配置：${NGINX_CONFIG_SOURCE}"
fi

if ! id "${DEPLOY_USER}" >/dev/null 2>&1; then
  useradd --create-home --shell /bin/bash "${DEPLOY_USER}"
fi

usermod --lock "${DEPLOY_USER}" >/dev/null 2>&1 || true

DEPLOY_HOME="$(getent passwd "${DEPLOY_USER}" | cut -d: -f6)"
[[ -n "${DEPLOY_HOME}" ]] || fail "无法确定 ${DEPLOY_USER} 的主目录。"

install -d -m 0700 -o "${DEPLOY_USER}" -g "${DEPLOY_USER}" "${DEPLOY_HOME}/.ssh"
touch "${DEPLOY_HOME}/.ssh/authorized_keys"
chown "${DEPLOY_USER}:${DEPLOY_USER}" "${DEPLOY_HOME}/.ssh/authorized_keys"
chmod 0600 "${DEPLOY_HOME}/.ssh/authorized_keys"

AUTHORIZED_KEY="no-agent-forwarding,no-port-forwarding,no-X11-forwarding,no-pty ${DEPLOY_PUBLIC_KEY}"
if ! grep -qxF "${AUTHORIZED_KEY}" "${DEPLOY_HOME}/.ssh/authorized_keys"; then
  printf '%s\n' "${AUTHORIZED_KEY}" >> "${DEPLOY_HOME}/.ssh/authorized_keys"
fi

install -d -m 0755 -o "${DEPLOY_USER}" -g "${DEPLOY_USER}" "${WEB_ROOT}"
install -d -m 0755 -o "${DEPLOY_USER}" -g "${DEPLOY_USER}" "${WEB_ROOT}/releases"
install -d -m 0750 -o "${DEPLOY_USER}" -g "${DEPLOY_USER}" "${WEB_ROOT}/incoming"

install -m 0644 "${NGINX_CONFIG_SOURCE}" "${NGINX_CONFIG_TARGET}"

if command -v restorecon >/dev/null 2>&1; then
  restorecon -RF "${WEB_ROOT}" || true
fi

nginx -t
systemctl enable --now nginx
systemctl reload nginx

curl --fail --silent --show-error --head -H "Host: ${HOST_HEADER}" http://127.0.0.1/ >/dev/null
curl --fail --silent --show-error --head -H "Host: ${HOST_HEADER}" http://127.0.0.1/articles/evidence-driven-ai-infra.html >/dev/null

printf 'CI/CD 初始化完成。\n'
printf 'DEPLOY_USER=%s\n' "${DEPLOY_USER}"
printf 'WEB_ROOT=%s\n' "${WEB_ROOT}"
printf 'PUBLIC_URL=%s\n' "${PUBLIC_URL}"
