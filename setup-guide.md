# AI辅助督课工作台 - Supabase 数据库配置指南 v0.5

## 一、注册 Supabase 账号并创建项目

1. 打开 [https://supabase.com](https://supabase.com)，点击 **Start your project**
2. 使用 GitHub 账号登录（或注册新账号）
3. 点击 **New Project**，填写：
   - **Name**：项目名称，例如 `dudao-workbench`
   - **Database Password**：设置一个数据库密码（请妥善保管）
   - **Region**：选择离你最近的区域（如 `Northeast Asia (Tokyo)` 或 `Southeast Asia (Singapore)`）
4. 点击 **Create new project**，等待约 2 分钟项目创建完成

## 二、创建数据表 + RLS + RPC 函数

项目创建完成后，需要执行建表和权限配置 SQL：

1. 在左侧菜单点击 **SQL Editor**
2. 点击 **New Query**
3. 复制 `index.html` 配置页中的建表 SQL（或参考 `docs/rls-policy.sql` + `docs/rpc-functions.sql`）粘贴到编辑器
4. 点击 **Run** 执行

执行完成后将创建：
- `courses` - 课程表
- `reviewers` - 督课官表
- `review_logs` - 督课记录表
- `admin_uids` - 管理员 uid 注册表
- `is_admin()` - 管理员判断函数
- 三张表的 RLS 策略（仅管理员 authenticated 用户可操作）
- 三个 RPC 函数（督课官端通过 RPC 访问数据）

## 三、创建管理员 Auth 账号

管理员使用 Supabase Auth 登录（email + 密码），需要先创建管理员用户并授权。

### 方式 A：Dashboard 创建（推荐）

1. 左侧菜单 **Authentication → Users**
2. 点击 **Add user → Create new user**
3. 填写管理员邮箱和密码，点击 **Create user**
4. 复制该用户的 **User UID**
5. 打开 **SQL Editor**，执行以下 SQL 将 uid 加入管理员列表：
   ```sql
   INSERT INTO admin_uids (uid, email, created_at)
   VALUES ('你的用户UID'::uuid, '管理员邮箱', NOW());
   ```

### 方式 B：SQL 创建

参考 `docs/auth-setup.sql` 文件中的 SQL 脚本。

> **注意**：只有 `admin_uids` 表中的 uid 才被视为管理员，即使 Auth 登录成功也无法操作数据。

## 四、Auth 配置建议

1. **关闭邮箱确认**（内部工具建议）：
   - **Authentication → Providers → Email → Confirm email** → 关闭
2. **启用安全密码**：
   - **Authentication → Providers → Email → Secure password** → 开启
3. **配置站点 URL**：
   - **Authentication → URL Configuration → Site URL** → 设置你的前端地址

## 五、获取连接配置

1. 在 Supabase 项目页面，点击左侧 **Settings → API**
2. 复制以下两个值：
   - **Project URL**：形如 `https://xxxxx.supabase.co`
   - **anon public key**：以 `eyJ...` 开头的长字符串（Project API keys → anon public）

## 六、在工作台中配置

1. 打开 `index.html`
2. 首次打开会自动显示数据库配置页面
3. 将 **Project URL** 和 **anon public key** 填入对应输入框
4. 点击「测试连接」验证配置
5. 验证通过后点击「保存并进入」

## 七、管理员登录流程

v0.5 采用**双层验证**：

1. **第一层**：Supabase Auth 邮箱密码登录
   - 输入管理员邮箱和密码 → 调用 Supabase Auth API → 获得 authenticated 会话
2. **第二层**：管理员口令（前端额外保护）
   - 输入管理员口令（默认 `childhood2024`，可自定义）→ 前端验证通过
3. 登录成功后进入管理台，可进行增删改查操作

> 管理员口令为额外的前端保护层，即使 Supabase Auth 凭证泄露，也需要第二道口令才能进入管理台。

## 八、督课官端流程

1. 督课官通过分享链接访问：`你的域名/index.html#reviewer/xxx-token`
2. 前端从 URL 中解析 token
3. 通过 RPC 函数 `get_reviewer_info` 验证身份、`get_reviewer_courses` 获取课程
4. 提交复核时调用 `submit_review` RPC 函数
5. 督课官端**不直接 SELECT 任何表**，所有数据访问都通过 RPC

## 九、导入示例数据

配置完成并登录管理员账号后，可在「数据概览」页面点击「导入示例数据」按钮，快速导入 3 位督课官 + 10 条示例课程数据。

## 十、常见问题

### Q: 测试连接时提示"函数不存在"？
A: 请确认已执行完整的建表+RLS+RPC SQL。在 Supabase 的 SQL Editor 中检查是否创建了 `get_reviewer_info`、`get_reviewer_courses`、`submit_review` 三个函数。

### Q: 登录成功但看不到任何数据？
A: 可能是你的 Auth 用户 uid 没有加入 `admin_uids` 表。在 SQL Editor 中执行：
```sql
SELECT * FROM admin_uids;
```
如果没有你的邮箱，参考第三步添加管理员授权。

### Q: 督课官端报错"permission denied"？
A: 请确认已执行 RPC 函数创建 SQL，且函数已授予 `anon` 角色执行权限。
```sql
SELECT proname, proacl FROM pg_proc WHERE proname LIKE 'get_reviewer%' OR proname = 'submit_review';
```

### Q: 如何从 v0.4 升级到 v0.5？
A: 请参考 `docs/migration-guide.md` 中的详细迁移步骤。

### Q: 督课官链接打不开？
A: 督课官链接格式为 `你的域名/index.html#reviewer/xxx-token`。确保链接完整复制，且 token 部分没有被截断。

### Q: 数据没有同步？
A: 管理员端和督课官端使用同一份云端数据。每次页面加载和操作后会自动刷新数据。如果看不到最新数据，尝试刷新页面。

### Q: 免费额度够用吗？
A: Supabase 免费版提供 500MB 数据库空间和 5GB 带宽/月。对于督课工作台的使用场景（课程数通常在几百到几千条），完全够用。

### Q: 可以重新配置数据库吗？
A: 可以。登录后页面右上角有「数据库」按钮，点击后可重新配置。之前的浏览器本地配置和 Auth 会话会被清除。

### Q: 如何备份数据？
A: 可通过管理员页面的「导出中心」将数据导出为 Excel 文件进行备份。也可在 Supabase 控制台的 Table Editor 中导出数据。

## 十一、安全说明 v0.5

### 权限架构
```
┌─────────────────────────────────────────────────────┐
│  管理员端 (浏览器)                                   │
│  → Supabase Auth 登录 (email+密码)                   │
│  → authenticated 角色 + RLS (仅 admin uid 放行)     │
│  → 直接 SELECT/INSERT/UPDATE/DELETE 三张表          │
└─────────────────────────────────────────────────────┘
                        │
                        ▼
┌─────────────────────────────────────────────────────┐
│  督课官端 (浏览器)                                    │
│  → 从 URL 拿 token                                   │
│  → anon 角色 (RLS 拒绝所有表操作)                     │
│  → 只能调用 RPC 函数（SECURITY DEFINER 绕过 RLS）    │
│  → get_reviewer_info / get_reviewer_courses /        │
│    submit_review（函数内部校验 token）                │
└─────────────────────────────────────────────────────┘
```

### 安全特性
1. **真·RLS 隔离**：anon 角色对三张表无任何权限，即使 anon key 泄露也无法直接读取数据
2. **Auth 身份认证**：管理员通过 Supabase Auth 登录，uid 在 `admin_uids` 表中授权
3. **RPC 受控访问**：督课官只能通过三个预定义函数访问数据，函数内部严格校验 token
4. **双层管理员保护**：Supabase Auth + 自定义管理员口令，双保险
5. **SECURITY DEFINER**：RPC 函数以所有者权限执行，设置 `search_path = public` 防注入

### 建议
- 定期通过导出功能备份数据
- 管理员使用强密码，定期更换
- 不再使用的督课官及时将状态改为"停用"
- 管理员 uid 变更时及时更新 `admin_uids` 表
