# zwz-blog

郑文泽的个人博客，使用原生 HTML、CSS 与少量浏览器能力构建，不依赖前端框架、后端服务或数据库。

公开仓库：<https://github.com/zhengwenze/zwz-blog>

线上地址：<http://123.56.190.100>

## 本地查看

```bash
npm run serve
```

浏览器打开 `http://127.0.0.1:4173`。

## 运行验证

```bash
npm test
```

测试会检查首页、文章页、站内链接、静态资源引用、页面元数据和未清理占位符，并在隔离目录中验证原子发布与失败回滚。

## CI/CD 与部署

生产环境使用 Nginx 托管不可变的 `dist/` 发布制品。目标流水线在 Pull Request 上执行测试，在 `main` 通过测试后构建制品、通过低权限 `deploy` 用户发布，并在健康检查失败时自动回滚。

CI/CD 已完成生产验收：PR 只运行 CI，`main` 自动发布，失败版本在隔离测试中自动恢复，手动回滚与并发串行均已实际演练。变量、密钥、服务器初始化、自动/手动回滚和验收证据见 [docs/DEV_DOCUMENT.md](docs/DEV_DOCUMENT.md)；公开部署元数据契约见 [docs/ZWZ_BLOG_API.md](docs/ZWZ_BLOG_API.md)；视觉与代码约定见 [docs/ZWZ_BLOG_STYLE.md](docs/ZWZ_BLOG_STYLE.md)。

## 项目结构

```text
dist/                    可直接部署的静态网站
docs/                    开发、页面契约与设计规范
deploy/                  Nginx、服务器初始化与发布脚本
tests/                   静态站点与发布脚本测试
.github/workflows/       GitHub Actions CI/CD 与手动回滚
```
