#!/usr/bin/env bash
set -euo pipefail

REPO_URL="https://github.com/zhengwenze/zwz-blog.git"
REPO_DIR="/opt/zwz-blog"
WEB_ROOT="/var/www/zwz-blog"
NGINX_CONFIG="/etc/nginx/conf.d/zwz-blog.conf"

if [[ "${EUID}" -ne 0 ]]; then
  printf '请使用 root 用户运行此脚本。\n' >&2
  exit 1
fi

install_packages() {
  if command -v dnf >/dev/null 2>&1; then
    dnf install -y git nginx
  elif command -v yum >/dev/null 2>&1; then
    yum install -y git nginx
  elif command -v apt-get >/dev/null 2>&1; then
    apt-get update
    DEBIAN_FRONTEND=noninteractive apt-get install -y git nginx
  else
    printf '未找到受支持的包管理器（dnf/yum/apt-get）。\n' >&2
    exit 1
  fi
}

if ! command -v git >/dev/null 2>&1 || ! command -v nginx >/dev/null 2>&1; then
  install_packages
fi

if [[ -d "${REPO_DIR}/.git" ]]; then
  git -C "${REPO_DIR}" pull --ff-only origin main
elif [[ -e "${REPO_DIR}" ]]; then
  printf '%s 已存在但不是 Git 仓库，请先人工检查。\n' "${REPO_DIR}" >&2
  exit 1
else
  git clone --branch main --depth 1 "${REPO_URL}" "${REPO_DIR}"
fi

DEPLOY_SHA="$(git -C "${REPO_DIR}" rev-parse --verify HEAD)"
RELEASE_DIR="${WEB_ROOT}/releases/${DEPLOY_SHA}"

if [[ ! -d "${RELEASE_DIR}" ]]; then
  install -d -m 0755 "${RELEASE_DIR}"
  cp -a "${REPO_DIR}/dist/." "${RELEASE_DIR}/"
fi

if [[ ! -f "${RELEASE_DIR}/deploy-meta.json" ]]; then
  DEPLOYED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  printf '{\n  "sha": "%s",\n  "run_id": "manual-install",\n  "deployed_at": "%s"\n}\n' \
    "${DEPLOY_SHA}" "${DEPLOYED_AT}" > "${RELEASE_DIR}/deploy-meta.json"
fi

ln -sfn "${RELEASE_DIR}" "${WEB_ROOT}/current.next"
mv -Tf "${WEB_ROOT}/current.next" "${WEB_ROOT}/current"
install -m 0644 "${REPO_DIR}/deploy/nginx.conf" "${NGINX_CONFIG}"

if command -v restorecon >/dev/null 2>&1; then
  restorecon -RF "${WEB_ROOT}" || true
fi

nginx -t
systemctl enable nginx
if systemctl is-active --quiet nginx; then
  systemctl reload nginx
else
  systemctl start nginx
fi

if command -v firewall-cmd >/dev/null 2>&1 && firewall-cmd --state >/dev/null 2>&1; then
  firewall-cmd --permanent --add-service=http
  firewall-cmd --reload
fi

curl --fail --silent --show-error --head -H 'Host: 123.56.190.100' http://127.0.0.1/ >/dev/null
curl --fail --silent --show-error --head -H 'Host: 123.56.190.100' http://127.0.0.1/articles/evidence-driven-ai-infra.html >/dev/null
curl --fail --silent --show-error -H 'Host: 123.56.190.100' http://127.0.0.1/deploy-meta.json \
  | grep -Fq "${DEPLOY_SHA}"

printf 'DEPLOYED_SHA=%s\n' "${DEPLOY_SHA}"
printf 'PUBLIC_URL=http://123.56.190.100\n'
