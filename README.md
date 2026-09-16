# zwz-blog

郑文泽的个人博客，使用原生 HTML、CSS 与少量浏览器能力构建，不依赖前端框架、后端服务或数据库。

公开仓库：<https://github.com/zhengwenze/zwz-blog>

## 本地查看

```bash
npm run serve
```

浏览器打开 `http://127.0.0.1:4173`。

## 运行验证

```bash
npm test
```

测试会检查首页、文章页、站内链接、静态资源引用、页面元数据和未清理占位符。

## 部署

生产环境使用 Nginx 直接托管 `dist/`。完整部署步骤、目录约定和回滚方式见 [docs/DEV_DOCUMENT.md](docs/DEV_DOCUMENT.md)。

## 项目结构

```text
dist/                    可直接部署的静态网站
docs/                    开发、页面契约与设计规范
deploy/                  Nginx 配置
tests/                   Node.js 内置测试
.github/workflows/       GitHub Actions 验证
```
