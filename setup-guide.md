# AI辅助督课工作台 - Supabase 数据库配置指南

## 一、注册 Supabase 账号并创建项目

1. 打开 [https://supabase.com](https://supabase.com)，点击 **Start your project**
2. 使用 GitHub 账号登录（或注册新账号）
3. 点击 **New Project**，填写：
   - **Name**：项目名称，例如 `dudao-workbench`
   - **Database Password**：设置一个数据库密码（请妥善保管）
   - **Region**：选择离你最近的区域（如 `Northeast Asia (Tokyo)` 或 `Southeast Asia (Singapore)`）
4. 点击 **Create new project**，等待约 2 分钟项目创建完成

## 二、创建数据表

项目创建完成后，需要执行建表 SQL：

1. 在左侧菜单点击 **SQL Editor**
2. 点击 **New Query**
3. 粘贴以下 SQL 并点击 **Run**：

```sql
-- courses 课程表
CREATE TABLE IF NOT EXISTS courses (
  course_id TEXT PRIMARY KEY,
  course_name TEXT,
  subject TEXT,
  teacher_name TEXT,
  teacher_id TEXT,
  class_name TEXT,
  school_name TEXT,
  lesson_time TEXT,
  duration INTEGER,
  ai_score NUMERIC,
  ai_report_url TEXT,
  replay_url TEXT,
  ai_layer TEXT,
  final_layer TEXT DEFAULT '',
  need_review BOOLEAN DEFAULT true,
  need_followup BOOLEAN DEFAULT false,
  assigned_reviewer TEXT DEFAULT '',
  reviewer_token TEXT DEFAULT '',
  review_status TEXT DEFAULT '未分配',
  teacher_feedback TEXT DEFAULT '',
  internal_notes TEXT DEFAULT '',
  created_at TEXT,
  updated_at TEXT
);

-- reviewers 督课官表
CREATE TABLE IF NOT EXISTS reviewers (
  reviewer_id TEXT PRIMARY KEY,
  reviewer_name TEXT,
  subject TEXT,
  token TEXT UNIQUE NOT NULL,
  max_tasks INTEGER DEFAULT 20,
  assigned_count INTEGER DEFAULT 0,
  completed_count INTEGER DEFAULT 0,
  status TEXT DEFAULT '启用'
);

-- review_logs 督课记录表
CREATE TABLE IF NOT EXISTS review_logs (
  log_id TEXT PRIMARY KEY,
  course_id TEXT,
  reviewer_name TEXT,
  final_layer TEXT,
  need_followup BOOLEAN DEFAULT false,
  has_risk BOOLEAN DEFAULT false,
  risk_type TEXT DEFAULT '',
  teacher_feedback TEXT DEFAULT '',
  internal_notes TEXT DEFAULT '',
  submitted_at TEXT
);

-- 启用 RLS（行级安全）并配置精细化策略
-- 管理员端（无 x-reviewer-token 头）：全量读写
-- 督课官端（携带 x-reviewer-token 头）：仅可访问自己的数据
ALTER TABLE courses ENABLE ROW LEVEL SECURITY;
ALTER TABLE reviewers ENABLE ROW LEVEL SECURITY;
ALTER TABLE review_logs ENABLE ROW LEVEL SECURITY;

-- 辅助函数：从请求头中提取督课官 token
CREATE OR REPLACE FUNCTION get_reviewer_token()
RETURNS TEXT AS $$
BEGIN
  RETURN current_setting('request.headers', true)::json->>'x-reviewer-token';
EXCEPTION
  WHEN OTHERS THEN
    RETURN NULL;
END;
$$ LANGUAGE plpgsql STABLE;

-- ===== courses 表策略 =====
-- 读：管理员全量；督课官仅自己的课程
CREATE POLICY "courses_select_policy" ON courses
  FOR SELECT
  USING (get_reviewer_token() IS NULL OR reviewer_token = get_reviewer_token());

-- 增：仅管理员
CREATE POLICY "courses_insert_policy" ON courses
  FOR INSERT
  WITH CHECK (get_reviewer_token() IS NULL);

-- 改：管理员全量；督课官仅改自己的且不能改 reviewer_token
CREATE POLICY "courses_update_policy" ON courses
  FOR UPDATE
  USING (get_reviewer_token() IS NULL OR reviewer_token = get_reviewer_token())
  WITH CHECK (get_reviewer_token() IS NULL OR (reviewer_token = get_reviewer_token() AND reviewer_token = OLD.reviewer_token));

-- 删：仅管理员
CREATE POLICY "courses_delete_policy" ON courses
  FOR DELETE
  USING (get_reviewer_token() IS NULL);

-- ===== reviewers 表策略 =====
-- 读：管理员全量；督课官仅自己
CREATE POLICY "reviewers_select_policy" ON reviewers
  FOR SELECT
  USING (get_reviewer_token() IS NULL OR token = get_reviewer_token());

-- 增：仅管理员
CREATE POLICY "reviewers_insert_policy" ON reviewers
  FOR INSERT
  WITH CHECK (get_reviewer_token() IS NULL);

-- 改：管理员全量；督课官仅改自己的且不能改 token
CREATE POLICY "reviewers_update_policy" ON reviewers
  FOR UPDATE
  USING (get_reviewer_token() IS NULL OR token = get_reviewer_token())
  WITH CHECK (get_reviewer_token() IS NULL OR (token = get_reviewer_token() AND token = OLD.token));

-- 删：仅管理员
CREATE POLICY "reviewers_delete_policy" ON reviewers
  FOR DELETE
  USING (get_reviewer_token() IS NULL);

-- ===== review_logs 表策略 =====
-- 读：仅管理员（督课官不能查看所有日志）
CREATE POLICY "review_logs_select_policy" ON review_logs
  FOR SELECT
  USING (get_reviewer_token() IS NULL);

-- 增：管理员全量；督课官仅能写自己的记录
CREATE POLICY "review_logs_insert_policy" ON review_logs
  FOR INSERT
  WITH CHECK (get_reviewer_token() IS NULL OR reviewer_name = (SELECT reviewer_name FROM reviewers WHERE token = get_reviewer_token() LIMIT 1));

-- 改：仅管理员
CREATE POLICY "review_logs_update_policy" ON review_logs
  FOR UPDATE
  USING (get_reviewer_token() IS NULL);

-- 删：仅管理员
CREATE POLICY "review_logs_delete_policy" ON review_logs
  FOR DELETE
  USING (get_reviewer_token() IS NULL);
```

4. 执行成功后，左侧 **Table Editor** 中应出现 `courses`、`reviewers`、`review_logs` 三张表

## 三、获取连接配置

1. 在 Supabase 项目页面，点击左侧 **Settings** → **API**
2. 复制以下两个值：
   - **Project URL**：形如 `https://xxxxx.supabase.co`
   - **anon public key**：以 `eyJ...` 开头的长字符串（Project API keys → anon public）

## 四、在工作台中配置

1. 打开 `index.html`
2. 首次打开会自动显示数据库配置页面
3. 将 **Project URL** 和 **anon public key** 填入对应输入框
4. 点击「测试连接」验证配置
5. 验证通过后点击「保存并进入」

## 五、导入示例数据

配置完成后，管理员可在「数据概览」页面点击「导入示例数据」按钮，快速导入 3 位督课官 + 10 条示例课程数据。

## 六、常见问题

### Q: 测试连接时提示"表不存在"？
A: 请确认已按第二步执行建表 SQL。在 Supabase 的 Table Editor 中检查是否存在三张表。

### Q: 提示"权限不足"或 RLS 相关错误？
A: 请确认已执行 SQL 中的全部 `CREATE POLICY` 语句。本系统采用精细化 RLS 策略：
- 管理员端：使用标准 anon key，请求不携带 `x-reviewer-token` 头 → 全量读写
- 督课官端：请求自动携带 `x-reviewer-token: <token>` 头 → RLS 仅放行匹配 token 的数据行
- 如督课官端报错"new row violates row-level security policy"，请检查 token 是否正确匹配

### Q: 如何从旧版本升级到新的 RLS 策略？
A: 如果已使用旧版建表 SQL（Allow all operations），可执行 `docs/rls-policy.sql` 中的迁移脚本进行升级。该脚本会先删除旧的全开放策略，再创建精细化策略。

### Q: 督课官链接打不开？
A: 督课官链接格式为 `你的域名/index.html#reviewer/xxx-token`。确保链接完整复制，且 token 部分没有被截断。

### Q: 数据没有同步？
A: 管理员端和督课官端使用同一份云端数据。每次页面加载和操作后会自动刷新数据。如果看不到最新数据，尝试刷新页面。

### Q: 免费额度够用吗？
A: Supabase 免费版提供 500MB 数据库空间和 5GB 带宽/月。对于督课工作台的使用场景（课程数通常在几百到几千条），完全够用。

### Q: 可以重新配置数据库吗？
A: 可以。管理员页面右上角有「数据库」按钮，点击后可重新配置。之前的浏览器本地配置会被覆盖。

### Q: 如何备份数据？
A: 可通过管理员页面的「导出中心」将数据导出为 Excel 文件进行备份。也可在 Supabase 控制台的 Table Editor 中导出数据。

## 七、安全说明

- `anon key`（或 publishable key）是公开的 API key，可以安全地在前端使用
- RLS（行级安全）策略已精细配置，确保数据访问隔离：
  - **管理员端**：使用标准请求 → 全量读写三张表
  - **督课官端**：请求自动携带 `x-reviewer-token` 自定义请求头 → RLS 强制隔离：
    - courses：仅能读取和修改 `reviewer_token` 等于自己 token 的课程，且不能修改 `reviewer_token` 字段
    - reviewers：仅能读取和修改自己的督课官资料（`token` 匹配），且不能修改 `token` 字段
    - review_logs：仅能新增自己名字的督课记录，不能读取或修改任何日志
- 管理员端的管理员口令（childhood2024）属于前端保护，管理员为可信角色
- 建议定期通过导出功能备份数据
- 如需更高强度的身份隔离，可引入 Supabase Auth 的 authenticated 角色或 Edge Functions 中转数据访问
