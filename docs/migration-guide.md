# 迁移指南：v0.4 → v0.5（权限安全模型升级）

## 概述

v0.5 对权限安全模型进行了彻底重构，从「x-header + 无 header 即管理员」的弱隔离方案升级为「Supabase Auth + RPC 受控访问」的真正安全方案。

### 版本对比

| 维度 | v0.4 | v0.5 |
|------|------|------|
| 管理员认证 | 前端口令（纯前端） | Supabase Auth (email+密码) + 前端口令（双层） |
| 管理员数据访问 | anon key + 无 x-header → 全量 | authenticated + admin uid RLS → 全量 |
| 督课官数据访问 | anon key + x-header + RLS 过滤 | anon key + RPC 函数（SECURITY DEFINER） |
| anon 角色权限 | 可读写所有表（RLS 过滤） | 无任何表权限，仅可执行 3 个 RPC |
| 安全性 | 依赖前端正确设置 header | 数据库级强隔离 |
| 新增表 | - | admin_uids（管理员 uid 注册表） |
| 新增函数 | get_reviewer_token() | is_admin(), get_reviewer_info(), get_reviewer_courses(), submit_review() |

### 兼容性

- **数据完全兼容**：三张业务表结构不变，已有数据无需迁移
- **前端兼容**：管理员口令（childhood2024）保留为第二道验证
- **督课官链接兼容**：`#reviewer/xxx-token` 格式不变
- **功能兼容**：五科、双校验、需复审统计、危险操作提示、人工复核 6 分类全部保留

## 迁移步骤

### 第 0 步：备份数据（强烈建议）

在开始迁移前，先备份所有数据：

1. 管理员登录旧版工作台
2. 进入「导出中心」，导出课程、督课官、督课记录为 Excel/CSV
3. 或在 Supabase Table Editor 中分别导出三张表

### 第 1 步：更新前端文件

用 v0.5 的 `index.html` 替换原有文件。

### 第 2 步：执行 RLS 策略迁移 SQL

在 Supabase SQL Editor 中执行 `docs/rls-policy.sql` 的全部内容。

该脚本会：
1. 删除 v0.4 的所有旧策略（`DROP POLICY IF EXISTS`）
2. 删除旧的 `get_reviewer_token()` 辅助函数
3. 创建 `admin_uids` 表
4. 创建 `is_admin()` 辅助函数
5. 创建新的 RLS 策略（仅 authenticated admin 可操作）

> 注意：执行此步骤后，**管理员端立即无法通过旧的 anon key 访问数据**，需完成后续步骤才能恢复。

### 第 3 步：创建 RPC 函数

在 Supabase SQL Editor 中执行 `docs/rpc-functions.sql` 的全部内容。

该脚本会：
1. 创建 `get_reviewer_info(p_token)` 函数
2. 创建 `get_reviewer_courses(p_token)` 函数
3. 创建 `submit_review(...)` 函数
4. 授予 `anon` 和 `authenticated` 角色执行权限

> 注意：执行此步骤后，**督课官端恢复可用**（通过 RPC 访问数据）。

### 第 4 步：创建管理员 Auth 账号

参考 `docs/auth-setup.sql` 或以下步骤：

1. 打开 Supabase Dashboard
2. 左侧菜单 **Authentication → Users**
3. 点击 **Add user → Create new user**
4. 填写管理员邮箱和密码，点击 **Create user**
5. 复制生成的 **User UID**
6. 在 SQL Editor 中执行（替换为实际的 uid 和邮箱）：
   ```sql
   INSERT INTO admin_uids (uid, email, created_at)
   VALUES ('xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx'::uuid, 'admin@example.com', NOW());
   ```

### 第 5 步：验证管理员端

1. 打开 v0.5 的工作台
2. 用管理员邮箱和密码登录（第一层）
3. 输入管理员口令（第二层，默认 childhood2024）
4. 确认能看到全部课程、督课官、记录数据
5. 测试新增、编辑、删除、分配等操作是否正常

### 第 6 步：验证督课官端

1. 用管理员账号生成督课官分享链接
2. 打开链接（或使用旧链接）
3. 确认能看到督课官信息和分配的课程
4. 测试提交复核功能
5. 确认管理员端能看到复核结果

### 第 7 步：清理旧配置（可选）

- 旧的 `x-reviewer-token` header 机制不再使用
- 前端不再设置 `global.headers`
- 数据库中旧的策略和函数已被迁移脚本删除

## 常见问题

### Q: 迁移后督课官端立即不可用了？

A: 是的，执行第 2 步（RLS 策略迁移）后，anon 角色失去所有表权限，督课官端暂时不可用。
执行第 3 步（创建 RPC 函数）后，督课官端恢复可用。
建议在业务低谷期执行迁移，且第 2、3 步连续完成。

### Q: 旧的督课官分享链接还能用吗？

A: 可以。URL 格式 `#reviewer/xxx-token` 完全不变，只是前端内部从「带 header 直接 SELECT」改成了「调用 RPC」。

### Q: 管理员口令会变吗？

A: 不变。默认口令仍为 `childhood2024`，如果你自定义过，保存在 `localStorage` 中也不受影响。
v0.5 中管理员口令从「唯一认证手段」降级为「第二道前端保护」。

### Q: 可以回退到 v0.4 吗？

A: 可以。执行旧版 `docs/rls-policy.sql` (v1.0) 的 SQL 即可恢复旧的 RLS 策略，
前端换回 v0.4 的 `index.html`。数据完全兼容，无需变动。

### Q: 多个管理员怎么添加？

A: 在 Supabase Dashboard 中创建多个 Auth 用户，然后将每个 uid 都加入 `admin_uids` 表：
```sql
INSERT INTO admin_uids (uid, email, created_at)
VALUES 
  ('uid1'::uuid, 'admin1@example.com', NOW()),
  ('uid2'::uuid, 'admin2@example.com', NOW())
ON CONFLICT (uid) DO NOTHING;
```

### Q: RPC 函数的 SECURITY DEFINER 安全吗？

A: 安全。SECURITY DEFINER 函数以函数所有者（通常是 postgres/supabase_admin）的权限执行，绕过 RLS。
但是：
1. 函数内部做了严格的 token 校验，无效 token 返回空
2. 函数只暴露了督课官应该看到的数据范围
3. 设置了 `search_path = public`，防止 schema 注入
4. anon 角色只能执行这 3 个被授予权限的函数，无法执行其他函数或直接访问表

## 迁移检查清单

- [ ] 数据已备份
- [ ] 前端 index.html 已更新为 v0.5
- [ ] RLS 策略迁移 SQL 已执行
- [ ] RPC 函数 SQL 已执行
- [ ] 管理员 Auth 用户已创建
- [ ] 管理员 uid 已加入 admin_uids 表
- [ ] 管理员端登录正常（Auth + 口令）
- [ ] 管理员端数据加载正常
- [ ] 管理员端增删改查正常
- [ ] 督课官端链接可打开
- [ ] 督课官端课程列表正常
- [ ] 督课官提交复核正常
- [ ] 管理员端能看到复核结果
- [ ] 示例数据导入功能正常
- [ ] 导出功能正常
