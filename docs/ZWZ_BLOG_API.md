# zwz-blog 页面与资源契约

> 版本：v1.1 | 更新时间：2026-09-16

## 一、为什么没有后端 API

本项目按要求采用纯前端技术栈，所有内容随 HTML 一起发布，不包含 `/api`、身份认证、数据库写入或后台管理。本文档记录对外 URL 与静态资源契约，避免后续维护时误以为存在后端能力。

## 二、页面清单

| 方法 | 路径 | 内容 | 预期状态 |
| --- | --- | --- | --- |
| GET | `/` | 个人主页 | 200 |
| GET | `/index.html` | 个人主页显式入口 | 200 |
| GET | `/articles/evidence-driven-ai-infra.html` | 首篇文章 | 200 |
| GET | `/assets/styles.css` | 全站样式 | 200 |
| GET | `/deploy-meta.json` | 当前生产发布的公开元数据 | 200 |
| GET | 其他不存在路径 | 无对应资源 | 404 |

## 三、HTML 契约

每个公开页面必须包含：

- UTF-8 编码声明与移动端 viewport；
- 唯一、具体的 `title` 和 description；
- 跳过导航链接、`header`、`main`、`footer` 等语义结构；
- 可见焦点状态与键盘可访问链接；
- 内嵌的站点 favicon；
- 指向 `/assets/styles.css` 的绝对站内路径。

## 四、部署元数据契约

`/deploy-meta.json` 是公开静态资源，用于确认线上文件对应的 Git 提交与 GitHub Actions 运行。它不是管理 API，不接收输入，不得包含密钥、用户名、主机内部路径或其他敏感信息。

```json
{
  "sha": "0123456789abcdef0123456789abcdef01234567",
  "run_id": "1234567890",
  "deployed_at": "2026-09-16T08:00:00Z"
}
```

| 字段 | 类型 | 约束 |
| --- | --- | --- |
| `sha` | string | 必填；40 位小写十六进制 Git 提交 SHA，必须与 release 目录及当前发布目标一致 |
| `run_id` | string | 必填；生成该制品的 GitHub Actions 运行 ID |
| `deployed_at` | string | 必填；UTC 的 ISO 8601 时间，使用 `Z` 后缀 |

字段是制品在 CI 中生成时的快照；手动回滚不修改旧 release 内的元数据。生产健康检查必须验证 HTTP 200 及 `sha` 精确匹配。

> 状态：已完成公网验收；`/deploy-meta.json` 返回 200、`no-cache` 与当前 release 的完整 Git SHA。

## 五、缓存契约

- HTML 与 `/deploy-meta.json` 使用 `Cache-Control: no-cache`，允许缓存但每次使用前必须向服务器重验证。
- `/assets/styles.css` 当前没有内容哈希文件名，使用协商缓存，不声明 `immutable`。
- 后续如采用内容哈希文件名，可为对应资源启用长期 `immutable` 缓存。

## 六、兼容性

支持当前主流 Chrome、Safari、Edge 和 Firefox。关闭 JavaScript 不影响阅读，因为首版没有运行时 JavaScript 依赖。
