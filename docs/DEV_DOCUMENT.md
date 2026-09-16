# zwz-blog 开发与运维文档

> 文档版本：v1.2 | 最后更新：2026-09-16 | 当前进度：CI/CD 仓库实现与生产初始化已完成，自动发布/回滚端到端验收待完成

## 一、项目概览

| 字段 | 内容 |
| --- | --- |
| 项目名称 | zwz-blog |
| 项目描述 | 郑文泽的轻量个人主页与技术博客 |
| 开发类型 | 纯前端静态网站 |
| 网站状态 | 已部署至阿里云 ECS |
| CI/CD 状态 | 仓库实现、GitHub `production` Environment 与服务器权限已配置；工作流尚未推送首跑，端到端演练待完成 |
| GitHub 仓库 | `https://github.com/zhengwenze/zwz-blog`（公开） |
| 线上地址 | `http://123.56.190.100` |

### 1.1 目标与边界

- 访客进入首页即可了解作者方向、近期项目主题并进入文章阅读。
- 首版只包含首页与一篇文章，不增加登录、评论、搜索、管理后台或数据库。
- 网站源码仅为 HTML/CSS；Node.js 只用于自动检查，不参与线上运行。
- 当前部署目标是公网 IP 的 HTTP 访问。域名、ICP 备案、HTTPS、CDN、staging 和消息通知不在本期范围内。

## 二、系统与 CI/CD 架构

### 2.1 运行时架构

```text
访客浏览器
    │ HTTP :80
    ▼
阿里云安全组 / 主机防火墙
    │
    ▼
Nginx 静态文件服务
    │ root=/var/www/zwz-blog/current
    ▼
index.html / articles/*.html / assets/styles.css / deploy-meta.json
```

| 层级 | 技术 | 用途 |
| --- | --- | --- |
| 页面结构 | HTML5 | 语义化首页与文章页 |
| 视觉样式 | CSS3 | 响应式布局、排版和动效降级 |
| 测试 | Node.js 22 内置 test runner | 静态入口、链接和元数据检查 |
| 流水线 | GitHub Actions | CI、制品打包、生产发布与手动回滚 |
| 托管 | Nginx | 生产环境静态文件服务 |

### 2.2 流水线

```text
pull_request ──┐
                ├─▶ ci：npm test + Shell 语法 + 发布脚本隔离测试
push main ───┘       │
                    ├── PR：结束
                    └── main / 手动触发
                              │
                              ▼
                   构建 release-<sha> 制品
                              │
                              ▼
                  GitHub production Environment
                              │ SSH
                              ▼
                  deploy 用户校验并原子切换
                              │
                    本机 + 公网健康检查
                       成功 ─┴─ 失败
                         │       │
                        完成   自动回滚
```

- `.github/workflows/pipeline.yml`：`pull_request`、`main` 分支 push 和 `workflow_dispatch` 的统一流水线。
- `.github/workflows/rollback.yml`：输入已存在 release 的完整 40 位小写提交 SHA，手动回滚。
- 全局 GitHub Token 权限只保留 `contents: read`。
- `production` 使用独立并发组，不取消进行中的发布，保证生产切换串行。
- CI 失败时不创建部署会话，也不连接生产服务器。

## 三、本地开发与页面契约

项目不使用数据库。内容以版本化静态文件存在 Git 仓库中。

```text
homepage
  ├── profile
  ├── focus areas
  ├── selected work
  └── article link ─────▶ article page
                              ├── metadata
                              ├── body sections
                              └── back link
```

新增文章时复制文章页结构，并在首页增加入口。对外 URL 及 `deploy-meta.json` 契约见 [ZWZ_BLOG_API.md](ZWZ_BLOG_API.md)。

### 本地要求

| 软件 | 版本 | 用途 |
| --- | --- | --- |
| Node.js | 22（与 CI 一致） | 自动检查 |
| Python | 3.9+ | 本地静态预览 |
| Git | 2.39+ | 版本管理 |

```bash
npm test
npm run serve
```

访问 `http://127.0.0.1:4173`；首页和文章页应返回 200。本地运行不需要生产密钥。

## 四、制品与发布契约

### 4.1 不可变制品

CI 对触发流水线的准确提交执行测试，在发布副本的根目录生成 `deploy-meta.json`，然后仅打包 `dist/` 内容。

```json
{
  "sha": "<40位Git提交SHA>",
  "run_id": "<GitHub Actions运行ID>",
  "deployed_at": "<UTC时间>"
}
```

制品名为 `release-<sha>.tar.gz`，同时生成 SHA-256 校验文件。Actions Artifact 名为 `release-<sha>`，只供本次流水线的部署任务下载。服务器不再执行 `git pull`，保证“通过测试的文件”就是“实际上线的文件”。

### 4.2 服务器目录

```text
/var/www/zwz-blog/
├── releases/
│   └── <commit-sha>/
├── .incoming-<commit-sha>/
└── current -> releases/<commit-sha>
```

- 上传包先在 `.incoming-<sha>` 中校验和解压，未完成的目录不会成为 `current`。
- `deploy/release.sh deploy <sha> <archive.tar.gz> <archive.tar.gz.sha256>` 检查 SHA 格式、校验和、必需文件以及元数据 SHA，然后原子切换 `current`。
- 必需文件为首页、文章页、CSS 和 `deploy-meta.json`。
- 日常发布不修改 Nginx，不重启 Nginx，不使用 sudo。
- v1 不自动清理旧 release，便于保留可追溯回滚点。

### 4.3 健康检查与自动回滚

1. 切换前记录原 `current` 目标。
2. 切换后在服务器 localhost 检查首页、文章页、CSS 和元数据 SHA。
3. GitHub Runner 再从 `PUBLIC_URL` 检查三个静态入口均为 200，并验证 `/deploy-meta.json` 的 `sha` 等于当前 `github.sha`。
4. 本机或公网检查失败时，将 `current` 原子恢复至上一 release，再次检查并令工作流失败。
5. 如果首次发布没有上一 release，检查失败时不保留故障版本为 `current`，并以非零状态退出。

### 4.4 手动回滚

在 GitHub Actions 中运行 `Rollback production`，输入服务器上已存在的完整 `release_sha`。工作流调用：

```bash
deploy/release.sh rollback <release_sha>
```

脚本拒绝非 40 位小写十六进制 SHA、不存在的 release、结构不完整的 release 或元数据不匹配的 release。切换后仍执行本机和公网检查；回滚目标不健康时恢复回滚前的 `current` 并标记工作流失败。

## 五、GitHub `production` Environment

在仓库 Settings → Environments 中创建 `production`，限制只有 `main` 可使用。本期不设置人工审批，`main` CI 通过后自动部署。

### Variables

| 名称 | 值 | 用途 |
| --- | --- | --- |
| `DEPLOY_HOST` | `123.56.190.100` | SSH 目标主机 |
| `DEPLOY_PORT` | `22` | SSH 端口 |
| `DEPLOY_USER` | `deploy` | 低权限发布用户 |
| `PUBLIC_URL` | `http://123.56.190.100` | 公网健康检查基址 |

### Secrets

| 名称 | 内容 | 要求 |
| --- | --- | --- |
| `DEPLOY_SSH_PRIVATE_KEY` | 仅对应 `deploy` 用户的流水线专用私钥 | 不得使用 root/管理员私钥，不得复用个人密钥 |
| `DEPLOY_KNOWN_HOSTS` | 经管理员独立核对的 SSH 主机公钥行 | 不使用 `StrictHostKeyChecking=no` |

密钥安全规则：

- 仓库、文档、Artifact、终端输出和 Actions 日志不得包含私钥、密码或 Token。
- 不输出 Secret 值，不在 shell 调试中开启可暴露参数的 `set -x`。
- 管理员私钥只保存在管理员设备，不写入 GitHub Secrets。
- 主机重装或 SSH Host Key 轮换后，先从可信渠道核对新指纹，再更新 `DEPLOY_KNOWN_HOSTS`。

## 六、服务器一次性配置

`deploy/bootstrap-cicd.sh` 用于一次性创建发布账户、目录与 Nginx 配置；`deploy/harden-ssh.sh` 在管理员确认新密钥登录后关闭密码和交互式认证。两个脚本均只供管理员一次性或恢复配置时使用，不属于日常发布流程。

### 6.1 `deploy` 用户

这些操作由管理员人工完成，不在日常 Actions 中执行：

- 创建密码锁定的 `deploy` 用户，不加入 `wheel`/`sudo`。
- 仅赋予 `/var/www/zwz-blog` 及其 release 目录的写权限。
- 在 `authorized_keys` 的公钥前禁用端口转发、Agent 转发、X11 和 PTY。
- 验证 `deploy` 无法修改 `/etc/nginx`、systemd、SSH 配置或其他网站目录。
- 让 Nginx 继续只读 `current`，日常发布只改变软链接指向。

2026-09-16 已在生产机验证：`deploy` 用户为 uid 1002，无 sudo 权限，可写 `/var/www/zwz-blog`，不可写 `/etc/nginx`。

### 6.2 管理员 SSH 加固顺序

关闭密码登录前必须按以下顺序执行，避免把自己锁在服务器外：

1. 为管理员生成独立 SSH 密钥，不覆盖已有密钥。
2. 将公钥加入管理员的 `authorized_keys`。
3. 保持当前密码会话打开，不要提前断开。
4. 在第二个终端验证新密钥可登录。
5. 运行 `sshd -t`，只有语法检查通过才能继续。
6. 设置 `PasswordAuthentication no` 和 `PermitRootLogin prohibit-password`。
7. reload SSH 服务，不停止当前会话。
8. 在新终端再次验证管理员密钥和 `deploy` 密钥登录，然后才结束旧会话。

2026-09-16 已完成上述加固：关闭密码认证后，管理员与 `deploy` 均已从新连接验证；`sshd -T` 生效值为 `passwordauthentication no` 与 `permitrootlogin without-password`。

### 6.3 Nginx 约定

- `root` 固定指向 `/var/www/zwz-blog/current`。
- 保留 `nosniff`、`SAMEORIGIN` 和严格 Referrer Policy 安全响应头。
- HTML 与 `/deploy-meta.json` 使用 `no-cache`，保证可重验证最新版本。
- CSS 当前没有内容哈希文件名，使用协商缓存，不声明 `immutable`。
- Nginx 变更由管理员人工执行；先运行 `nginx -t`，通过后才 reload。

2026-09-16 已验证生产 Nginx 新缓存策略生效，首页和文章页均返回 200。CI/CD 发布后的元数据响应头仍需在首跑中验收。

## 七、验收计划与证据边界

原有网站的公网首页、文章页与响应式视图已完成人工验收。下列项目专属于新 CI/CD，在实际 Actions 和生产服务器上留下证据前不得标记完成：

- [ ] Pull Request 只运行 CI，不连接生产服务器。
- [ ] `main` push 自动部署准确提交，线上 `deploy-meta.json.sha` 等于 GitHub 提交 SHA。
- [ ] 首页、文章页、CSS 和元数据的本机/公网检查全部通过。
- [ ] 在隔离测试中制造健康检查失败，证明自动回滚保留上一健康版本。
- [ ] 手动回滚到上一 release，验证后再重新部署最新 SHA。
- [ ] 同时触发两个生产任务，证明它们串行执行且不中断正在进行的切换。
- [x] 验证流水线使用的 `deploy` 无 sudo 权限且无法写入 `/etc/nginx`。
- [x] 验证管理员密钥登录、密码登录关闭以及 `deploy` 密钥重新连接。

验收证据至少包含 Actions 运行链接/运行 ID、对应提交 SHA、线上元数据、回滚前后 `current` 指向和健康检查结果。不得把本地 Shell 测试记录成生产验收。

## 八、故障定位

| 现象 | 优先检查 | 处理原则 |
| --- | --- | --- |
| CI 失败 | `npm test`、`bash -n`、发布脚本隔离测试 | 先修复仓库；不得跳过 CI 直接部署 |
| Artifact 缺失或校验失败 | artifact 名、本次 run 下载来源、`.sha256` | 重新构建制品；不绕过校验和 |
| SSH 拒绝连接 | host/port/user、安全组、`known_hosts` 指纹 | 区分网络问题、主机指纹变化和密钥权限；不关闭主机校验 |
| 发布脚本拒绝 SHA | 是否为 40 位小写十六进制、元数据是否一致 | 不修改服务器 release，从正确提交重新运行 |
| localhost 失败 | `current` 软链接、release 文件与权限、Nginx 日志 | 确认自动回滚后的 `current`，不盲目重启 Nginx |
| 本机成功、公网失败 | `PUBLIC_URL`、安全组、防火墙、外网缓存 | 保留失败 run 证据，确认自动回滚结果 |
| 页面 404 | URL 契约与 release 必需文件 | 修复制品源文件，不在 release 目录中手改 |
| 页面 403 | 目录执行权限、文件读权限和 SELinux 上下文 | 由管理员修正，不提升 `deploy` 为 root |
| 页面 502/503 | `nginx -t`、systemd 状态与 Nginx 日志 | 使用管理员通道处理；日常发布用户不管理服务 |
| 线上 SHA 不匹配 | `/deploy-meta.json`、Actions run SHA、`readlink current` | 视为发布失败，先回滚再重新部署 |

## 九、安全与缓存清单

- [x] 仓库不包含服务器密码、SSH 私钥、Token 或代理配置。
- [x] 页面没有表单、用户输入、脚本注入点和第三方追踪器。
- [x] 只开放静态目录，不暴露仓库、日志或 root 家目录。
- [x] 完成 `deploy` 低权限账户、GitHub `production` Environment 及专用密钥配置。
- [x] 验证管理员密钥后关闭密码登录。
- [x] 完成 HTML `no-cache` 与 CSS 协商缓存的线上响应头验收。
- [ ] 完成 `deploy-meta.json` `no-cache` 的线上响应头验收。
- [ ] 绑定域名后再配置 HTTPS 与 HSTS。

## 十、历史验收与问题记录

2026-09-16 已完成原有静态站点的公网验收：首页、文章页和 CSS 返回 200，375×812、768×1024、1280×720 三种视口通过视觉检查。这些结果不代表新 CI/CD 已完成验收。

| 问题 | 状态 | 说明 |
| --- | --- | --- |
| 服务器免密 SSH 验证失败 | 已解决 | 已改用专用 `deploy` 密钥和固定 host key，并在关闭密码登录后重新连接验证 |
| TCP 80 被旧 Python 静态服务占用 | 已解决 | 终止 `/usr/bin/python3 -m http.server 80` 后启动 Nginx |
| CI/CD 生产演练 | 待验收 | 需在 Actions 与 ECS 上完成正常发布、失败自动回滚、手动回滚和并发串行测试 |
