# zwz-blog 页面与资源契约

> 版本：v1.0 | 更新时间：2026-09-16

## 一、为什么没有后端 API

本项目按要求采用纯前端技术栈，所有内容随 HTML 一起发布，不包含 `/api`、身份认证、数据库写入或后台管理。本文档记录对外 URL 与静态资源契约，避免后续维护时误以为存在后端能力。

## 二、页面清单

| 方法 | 路径 | 内容 | 预期状态 |
| --- | --- | --- | --- |
| GET | `/` | 个人主页 | 200 |
| GET | `/index.html` | 个人主页显式入口 | 200 |
| GET | `/articles/evidence-driven-ai-infra.html` | 首篇文章 | 200 |
| GET | `/assets/styles.css` | 全站样式 | 200 |
| GET | 其他不存在路径 | 无对应资源 | 404 |

## 三、HTML 契约

每个公开页面必须包含：

- UTF-8 编码声明与移动端 viewport；
- 唯一、具体的 `title` 和 description；
- 跳过导航链接、`header`、`main`、`footer` 等语义结构；
- 可见焦点状态与键盘可访问链接；
- 内嵌的站点 favicon；
- 指向 `/assets/styles.css` 的绝对站内路径。

## 四、缓存契约

- HTML 默认由 Nginx 协商缓存，便于文章更新后及时生效。
- CSS 等带扩展名静态资源缓存 7 天。
- 修改缓存资源内容时，如出现旧缓存，后续可通过文件名版本化解决。

## 五、兼容性

支持当前主流 Chrome、Safari、Edge 和 Firefox。关闭 JavaScript 不影响阅读，因为首版没有运行时 JavaScript 依赖。
