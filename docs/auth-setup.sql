-- ============================================================
-- AI 辅助督课工作台 - 管理员 Auth 设置指南 v0.5
-- 版本: v0.5 (Supabase Auth + RPC 受控访问)
-- 日期: 2026-09-03
-- 适用: Supabase PostgreSQL
-- ============================================================
--
-- 【重要说明】
-- Supabase Auth 用户不能直接通过 SQL 插入 auth.users 表来创建（涉及加密、
-- 验证流程等）。正确的创建方式有三种：
--   方式 A：Supabase Dashboard 手动创建（推荐，最简单）
--   方式 B：使用 Supabase Auth Admin API（适合批量/自动化）
--   方式 C：使用 SQL 调用 auth 内置函数（需 superuser 权限）
--
-- 本文件提供方式 C 的 SQL 脚本，以及管理员 uid 授权 SQL。
-- ============================================================

-- ============================================================
-- 第一部分：创建管理员 Auth 用户（方式 C：SQL 函数方式）
-- ============================================================
--
-- 注意：此方式需要在 Supabase SQL Editor 中执行。
-- Supabase 的 auth schema 中提供了 sign_up 相关函数。
-- 如果 SQL 方式不生效，请使用方式 A（Dashboard）创建。

-- 方法 1：使用 auth.sign_up 函数
-- 注意：此方法可能因 Supabase 版本不同而有差异
DO $$
DECLARE
  v_email TEXT := 'admin@example.com';  -- 替换为你的管理员邮箱
  v_password TEXT := 'YourAdminPwd123';  -- 替换为强密码
  v_user_id UUID;
BEGIN
  -- 检查用户是否已存在
  IF EXISTS (SELECT 1 FROM auth.users WHERE email = v_email) THEN
    RAISE NOTICE '用户 % 已存在，跳过创建', v_email;
    RETURN;
  END IF;

  -- 调用 auth.sign_up 创建用户
  -- 注意：gen_random_uuid() 需要 pgcrypto 扩展（Supabase 默认已启用）
  v_user_id := gen_random_uuid();

  INSERT INTO auth.users (
    id,
    instance_id,
    email,
    encrypted_password,
    email_confirmed_at,
    created_at,
    updated_at,
    raw_user_meta_data,
    is_super_admin,
    raw_app_meta_data
  ) VALUES (
    v_user_id,
    '00000000-0000-0000-0000-000000000000',  -- default instance_id
    v_email,
    crypt(v_password, gen_salt('bf')),
    NOW(),
    NOW(),
    NOW(),
    '{}'::jsonb,
    false,
    '{"provider":"email","providers":["email"]}'::jsonb
  );

  RAISE NOTICE '管理员用户创建成功，uid: %', v_user_id;

  -- 将 uid 加入 admin_uids 表（授予管理员权限）
  INSERT INTO admin_uids (uid, email, created_at)
  VALUES (v_user_id, v_email, NOW())
  ON CONFLICT (uid) DO NOTHING;

  RAISE NOTICE '管理员权限已授予: %', v_email;
END $$;

-- ============================================================
-- 第二部分：管理员 uid 授权 SQL（推荐使用方式）
-- ============================================================
--
-- 无论使用哪种方式创建 Auth 用户，都需要将用户 uid 加入 admin_uids 表，
-- 才能获得数据的全量读写权限。
--
-- 步骤：
--   1. 先在 Supabase Dashboard 中创建 Auth 用户
--      Authentication → Users → Add user → Create new user
--   2. 复制该用户的 User UID
--   3. 执行以下 SQL 将 uid 加入 admin_uids 表

-- 单条添加管理员
-- 请将 '你的管理员uid' 替换为实际的 Auth 用户 uid
-- 将 'admin@example.com' 替换为管理员邮箱
INSERT INTO admin_uids (uid, email, created_at)
VALUES (
  '00000000-0000-0000-0000-000000000000'::uuid,  -- TODO: 替换为实际 uid
  'admin@example.com',                          -- TODO: 替换为实际邮箱
  NOW()
)
ON CONFLICT (uid) DO NOTHING;

-- ============================================================
-- 第三部分：管理管理员账号
-- ============================================================

-- 查看所有管理员
SELECT * FROM admin_uids ORDER BY created_at;

-- 添加管理员（先确保 Auth 用户已创建）
-- INSERT INTO admin_uids (uid, email, created_at)
-- VALUES ('另一个管理员的uid'::uuid, 'another@example.com', NOW())
-- ON CONFLICT (uid) DO NOTHING;

-- 移除管理员权限（不删除 Auth 用户，仅撤销管理员访问权限）
-- DELETE FROM admin_uids WHERE uid = '要移除的uid'::uuid;

-- 查看某用户是否具有管理员权限
-- SELECT is_admin();  -- 这个函数在 RLS 策略文件中定义

-- ============================================================
-- 第四部分：Auth 配置建议（在 Supabase Dashboard 中操作）
-- ============================================================
--
-- 1. 关闭邮箱确认（可选，内部工具建议关闭）
--    Authentication → Providers → Email → Confirm email → 关闭
--
-- 2. 密码策略
--    Authentication → Providers → Email → Secure password → 开启
--
-- 3. 站点 URL 配置
--    Authentication → URL Configuration → Site URL → 设置你的前端地址
--
-- 4. 禁用不需要的登录方式
--    仅保留 Email 登录，禁用 Phone、Magic Link 等不需要的方式
--
-- ============================================================

-- ============================================================
-- 第五部分：故障排查
-- ============================================================
--
-- Q: 登录成功但看不到任何数据？
-- A: 检查 admin_uids 表中是否有该用户的 uid。
--    SELECT * FROM admin_uids WHERE uid = auth.uid();
--    如果没有，执行第二部分的 INSERT 语句。
--
-- Q: 提示 "Invalid login credentials"？
-- A: 确保 Auth 用户已正确创建，邮箱和密码正确。
--    可以在 Dashboard 的 Authentication → Users 中重置密码。
--
-- Q: 督课官端报错 "permission denied"？
-- A: 确保已执行 rpc-functions.sql，且函数已授予 anon 角色执行权限。
--    检查：SELECT * FROM pg_proc WHERE proname = 'get_reviewer_courses';
--
-- Q: SQL 创建用户时报 "permission denied for schema auth"？
-- A: 可能你的数据库角色没有 auth schema 的写入权限。
--    建议改用 Dashboard 方式（方式 A）创建用户，再用 SQL 授权。
-- ============================================================
