# ClassIn 报告读取后端部署指南

本项目提供两种后端方案，用于替代前端直接 CORS 代理抓取 ClassIn 报告：

- **方案一（推荐）：Supabase Edge Function** — 与现有 Supabase 生态一致，无需额外账号
- **方案二（备选）：Cloudflare Worker** — 独立部署，适合已有 Cloudflare 账号的场景

两种方案对前端提供完全一致的 API 接口。

---

## 方案一：Supabase Edge Function 部署

### 1. 安装 Supabase CLI

```bash
# macOS (Homebrew)
brew install supabase/tap/supabase

# 或使用 npm
npm install -g supabase

# 其他系统参考官方文档
# https://supabase.com/docs/guides/cli/getting-started
```

### 2. 登录 Supabase

```bash
supabase login
```

浏览器会打开授权页面，使用你的 Supabase 账号登录即可。

### 3. 关联项目

当前项目引用 ID（project-ref）：`nkrgknrkzkiipzeovafi`

```bash
supabase link --project-ref nkrgknrkzkiipzeovafi
```

按提示输入数据库密码（即 Supabase Dashboard → Settings → Database 中的密码）。

### 4. 部署 Edge Function

在仓库根目录下执行：

```bash
supabase functions deploy fetch-classin-report --project-ref nkrgknrkzkiipzeovafi
```

首次部署会自动创建函数，后续部署会覆盖更新。

### 5. 获取函数 Endpoint URL

部署成功后，函数 URL 格式为：

```
https://nkrgknrkzkiipzeovafi.supabase.co/functions/v1/fetch-classin-report
```

也可以在 Supabase Dashboard 中查看：
Edge Functions → 选择 fetch-classin-report → 复制 URL

### 6. 配置前端

打开督课平台 → 点击右上角「AI设置」→「报告读取后端 API URL」填入上面的 URL → 点击「测试连接」验证。

### 7. 本地开发调试（可选）

```bash
# 启动本地 Supabase 环境
supabase start

# 本地运行函数
supabase functions serve fetch-classin-report

# 测试调用
curl -X POST http://localhost:54321/functions/v1/fetch-classin-report \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer <anon-key>" \
  -d '{"report_url":"https://share.eeo.cn/xxx"}'
```

### 8. 查看日志

```bash
supabase functions logs fetch-classin-report --project-ref nkrgknrkzkiipzeovafi
```

或在 Supabase Dashboard → Edge Functions → 选择函数 → Logs 中查看。

---

## 方案二：Cloudflare Worker 部署

代码位于：`cloudflare-worker/fetch-classin-report.js`

### 方式 A：通过 Cloudflare Dashboard 手动部署

1. 登录 [Cloudflare Dashboard](https://dash.cloudflare.com/)
2. 进入 Workers & Pages → Create → Create Worker
3. 命名为 `fetch-classin-report`，点击 Deploy
4. 点击「Edit Code」，用 `cloudflare-worker/fetch-classin-report.js` 的全部内容替换默认代码
5. 点击「Deploy」保存
6. 复制 Worker URL（形如 `https://fetch-classin-report.xxx.workers.dev`）

### 方式 B：通过 Wrangler CLI 部署

```bash
# 安装 Wrangler
npm install -g wrangler

# 登录
wrangler login

# 进入 worker 目录
cd cloudflare-worker

# 初始化项目（首次）
wrangler init fetch-classin-report

# 用 fetch-classin-report.js 替换 src/index.js 内容

# 部署
wrangler deploy
```

部署后将 Worker URL 配置到前端 AI 设置中即可。

---

## API 接口规范

### 请求

```
POST /fetch-classin-report
Content-Type: application/json

{
  "report_url": "https://share.eeo.cn/xxx/yyy"
}
```

### 成功响应

```json
{
  "success": true,
  "raw_text": "……报告正文纯文本……",
  "structured": {
    "score": 85.5,
    "issue_summary": "……需关注问题摘要……",
    "interaction_summary": "……互动摘要……",
    "teacher_behavior": "……教师行为描述……",
    "student_participation": "……学生参与描述……",
    "raw_sections": ["课堂概况", "课堂互动", "教师表现", "……"]
  }
}
```

### 失败响应

```json
{
  "success": false,
  "error_type": "timeout | forbidden | auth_required | parse_failed | unsupported_domain | network_error",
  "message": "明确的失败原因描述"
}
```

| error_type | 含义 |
|------------|------|
| `unsupported_domain` | 报告链接域名不在白名单（仅允许 eeo.cn 子域） |
| `auth_required` | 报告页面需要登录（HTTP 401/403） |
| `timeout` | 请求超时（30 秒） |
| `parse_failed` | 页面不存在、内容过短或解析失败 |
| `network_error` | 前端无法连接后端（仅前端返回） |
| `no_backend` | 未配置后端 API URL（仅前端返回） |

---

## 安全说明

- 后端仅允许抓取 `eeo.cn` 域名下的页面，防止被用作通用代理
- 函数无鉴权要求（公开可调用），但因有域名白名单，滥用风险较低
- 如需增加鉴权，可在后端校验请求头中的自定义 token，前端配置时一并传入
