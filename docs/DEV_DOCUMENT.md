# zwz-blog 开发文档

> 文档版本：v1.0 | 最后更新：2026-09-16 | 当前进度：节点 3/4（等待公网部署）

## 一、项目概览

| 字段 | 内容 |
| --- | --- |
| 项目名称 | zwz-blog |
| 项目描述 | 郑文泽的轻量个人主页与技术博客 |
| 开发类型 | 纯前端静态网站 |
| 当前状态 | 本地实现与验证完成，等待服务器认证 |
| GitHub 仓库 | `https://github.com/zhengwenze/zwz-blog`（公开） |
| 线上地址 | 待部署至 `http://123.56.190.100` |

### 1.1 目标与边界

- 访客进入首页即可了解作者方向、近期项目主题并进入文章阅读。
- 首版只包含首页与一篇文章，不增加登录、评论、搜索、管理后台或数据库。
- 网站源码仅为 HTML/CSS；Node.js 只用于本地自动检查，不参与线上运行。
- 当前部署目标是公网 IP 的 HTTP 访问。域名、ICP备案和 HTTPS 不在本次范围内。

## 二、系统架构

```text
访客浏览器
    │ HTTP :80
    ▼
阿里云安全组 / 主机防火墙
    │
    ▼
Nginx 静态文件服务
    │ root=/var/www/zwz-blog
    ▼
index.html / articles/*.html / assets/styles.css
```

| 层级 | 技术 | 用途 |
| --- | --- | --- |
| 页面结构 | HTML5 | 语义化首页与文章页 |
| 视觉样式 | CSS3 | 响应式布局、排版和动效降级 |
| 测试 | Node.js 内置 test runner | 静态入口、链接和元数据检查 |
| 托管 | Nginx | 生产环境静态文件服务 |
| 版本管理 | Git + GitHub | 公开源码、历史记录与 CI |

## 三、数据与页面契约

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

文章字段约定：标题、摘要、发布日期、阅读时长、标签、正文和返回首页链接。新增文章时复制文章页结构，并在首页增加入口。

## 四、核心访问流程

```text
访问公网 IP
    │
    ▼
Nginx 返回首页
    │
    ├── 浏览作者简介和方向
    └── 点击文章卡片
            │
            ▼
       返回文章 HTML
            │
            └── 点击“返回首页”
```

### 静态请求时序

```text
浏览器              Nginx              文件系统
  │ GET /              │                    │
  │───────────────────▶│                    │
  │                    │ 读取 index.html    │
  │                    │───────────────────▶│
  │                    │◀───────────────────│
  │◀── 200 text/html ──│                    │
  │ GET /assets/styles.css                  │
  │───────────────────▶│──读取 CSS─────────▶│
  │◀── 200 text/css ───│◀───────────────────│
```

## 五、环境配置

### 本地要求

| 软件 | 最低版本 | 用途 |
| --- | --- | --- |
| Node.js | 20 | 自动检查 |
| Python | 3.9 | 本地静态预览 |
| Git | 2.39 | 版本管理 |

无环境变量、密钥、数据库或第三方服务依赖。

### 本地运行

```bash
npm test
npm run serve
```

访问 `http://127.0.0.1:4173`；首页和文章页应返回 200。

## 六、服务器部署

### 目录与配置

- 网站目录：`/var/www/zwz-blog`
- Nginx 配置：`/etc/nginx/conf.d/zwz-blog.conf`
- 对外端口：TCP 80
- 发布内容：仅同步 `dist/` 内文件

### 首次部署步骤

```bash
# 服务器侧安装 Nginx（根据系统选择 dnf/yum/apt）
dnf install -y nginx || yum install -y nginx

mkdir -p /var/www/zwz-blog
# 从本地把 dist/ 上传至 /var/www/zwz-blog/
# 把 deploy/nginx.conf 上传至 /etc/nginx/conf.d/zwz-blog.conf

nginx -t
systemctl enable --now nginx
curl -I http://127.0.0.1/
```

随后在阿里云安全组与系统防火墙中确认 TCP 80 已放行，再从外网访问 `http://123.56.190.100`。

### 更新与回滚

更新前保留 `/var/www/zwz-blog.previous`，将新 `dist/` 原子替换为正式目录并执行 `nginx -t`。若验证失败，恢复 previous 目录；Nginx 配置不通过时不得 reload。

## 七、HTTP 状态与故障定位

| 状态 | 含义 | 处理 |
| --- | --- | --- |
| 200 | 页面或资源正常返回 | 无需处理 |
| 304 | 浏览器使用缓存 | 正常行为 |
| 404 | 路径或资源不存在 | 检查 HTML 链接与同步目录 |
| 403 | Nginx 无读取权限 | 检查目录权限和 SELinux 上下文 |
| 502/503 | 当前配置异常或服务未启动 | 检查 `nginx -t` 与 systemd 状态 |

## 八、安全清单

- [x] 仓库不包含服务器密码、SSH 私钥、Token 或代理配置。
- [x] 页面没有表单、用户输入、脚本注入点和第三方追踪器。
- [x] 配置 `nosniff`、`SAMEORIGIN` 和严格 Referrer Policy。
- [x] 只开放静态目录，不暴露仓库、日志或 root 家目录。
- [ ] 服务器登录认证待完成后复核 root SSH 策略。
- [ ] 绑定域名后再配置 HTTPS 与 HSTS。

## 九、性能目标

- HTML 首屏无需 JavaScript 执行即可阅读。
- 首版总静态资源目标小于 100 KB（不含传输压缩收益）。
- 桌面与移动端均无横向溢出；正文基础字号不低于 16px。
- 生产验收以公网 `curl`、实际浏览器桌面/移动视口为准。

## 十、开发节点

- [x] 节点 1：范围、架构、页面契约与视觉规范
- [x] 节点 2：首页和文章页实现
- [x] 节点 3：自动测试、Nginx 配置与 GitHub CI
- [ ] 节点 4：GitHub 公开仓库、公网部署与外网验收

## 十一、问题记录

| 问题 | 状态 | 说明 |
| --- | --- | --- |
| 本机未安装 GitHub CLI | 已解决 | 使用 GitHub API 与系统已有 Git 凭据创建公开仓库 |
| 服务器免密 SSH 验证失败 | 阻塞公网部署 | 需要现有密码会话、SSH 密钥或云控制台授权 |
