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

-- 启用 RLS（行级安全）并设置策略（允许 anon key 读写）
ALTER TABLE courses ENABLE ROW LEVEL SECURITY;
ALTER TABLE reviewers ENABLE ROW LEVEL SECURITY;
ALTER TABLE review_logs ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Allow all operations on courses" ON courses FOR ALL USING (true) WITH CHECK (true);
CREATE POLICY "Allow all operations on reviewers" ON reviewers FOR ALL USING (true) WITH CHECK (true);
CREATE POLICY "Allow all operations on review_logs" ON review_logs FOR ALL USING (true) WITH CHECK (true);
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
A: 请确认已执行 SQL 中的 `CREATE POLICY` 语句，允许 anon key 读写所有表。

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

- `anon key` 是公开的 API key，可以安全地在前端使用
- RLS 策略已配置为允许 anon key 完全读写，适合内部工具使用
- 如需更高安全性，可修改 RLS 策略限制特定操作
- 建议定期通过导出功能备份数据
