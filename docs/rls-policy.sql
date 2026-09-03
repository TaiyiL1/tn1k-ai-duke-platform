-- ============================================================
-- AI 辅助督课工作台 - RLS 行级安全策略 v0.5
-- 版本: v0.5 (Supabase Auth + RPC 受控访问)
-- 日期: 2026-09-03
-- 适用: Supabase PostgreSQL
-- ============================================================
--
-- 【方案说明】
-- 本系统采用真正安全的两级权限模型：
--   1. 管理员端：Supabase Auth (email + 密码登录)，authenticated 角色
--      RLS 通过 auth.uid() 判断是否为管理员 uid，管理员获得全量读写权限
--   2. 督课官端：完全通过 PostgreSQL Functions (RPC) 访问数据，禁止直接 SELECT 表
--      RPC 函数使用 SECURITY DEFINER 模式，在函数内部校验 token 有效性
--
-- 【RLS 策略总则】
--   - anon 角色：三张表均无任何权限（拒绝所有操作）
--   - authenticated 角色：仅管理员 uid 有全量读写权限
--   - 督课官：通过 RPC 函数间接访问，RPC 绕过 RLS（SECURITY DEFINER）
--
-- 【管理员 uid 配置】
--   管理员 Auth 用户的 uid 需要在 admin_uids 表中注册。
--   只有 uid 在 admin_uids 表中的 authenticated 用户才能操作数据。
-- ============================================================

-- ------------------------------------------------------------
-- 第一步：确保 RLS 已启用
-- ------------------------------------------------------------

ALTER TABLE courses ENABLE ROW LEVEL SECURITY;
ALTER TABLE reviewers ENABLE ROW LEVEL SECURITY;
ALTER TABLE review_logs ENABLE ROW LEVEL SECURITY;

-- ------------------------------------------------------------
-- 第二步：删除旧策略（兼容 v0.4 及更早版本）
-- ------------------------------------------------------------

DROP POLICY IF EXISTS "Allow all operations on courses" ON courses;
DROP POLICY IF EXISTS "Allow all operations on reviewers" ON reviewers;
DROP POLICY IF EXISTS "Allow all operations on review_logs" ON review_logs;

DROP POLICY IF EXISTS "courses_select_policy" ON courses;
DROP POLICY IF EXISTS "courses_insert_policy" ON courses;
DROP POLICY IF EXISTS "courses_update_policy" ON courses;
DROP POLICY IF EXISTS "courses_delete_policy" ON courses;

DROP POLICY IF EXISTS "reviewers_select_policy" ON reviewers;
DROP POLICY IF EXISTS "reviewers_insert_policy" ON reviewers;
DROP POLICY IF EXISTS "reviewers_update_policy" ON reviewers;
DROP POLICY IF EXISTS "reviewers_delete_policy" ON reviewers;

DROP POLICY IF EXISTS "review_logs_select_policy" ON review_logs;
DROP POLICY IF EXISTS "review_logs_insert_policy" ON review_logs;
DROP POLICY IF EXISTS "review_logs_update_policy" ON review_logs;
DROP POLICY IF EXISTS "review_logs_delete_policy" ON review_logs;

-- 删除旧的辅助函数
DROP FUNCTION IF EXISTS get_reviewer_token();

-- ------------------------------------------------------------
-- 第三步：创建管理员 uid 表
-- ------------------------------------------------------------
-- 用于存储被授权的管理员 Auth 用户 uid
-- 只有在此表中的 uid 才能通过 RLS 获得全量读写权限

CREATE TABLE IF NOT EXISTS admin_uids (
  uid UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  email TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE admin_uids ENABLE ROW LEVEL SECURITY;

-- admin_uids 表策略：authenticated 管理员可读，写入只能由服务端/owner 操作
-- （管理员 uid 推荐通过 SQL Editor 或 Dashboard 手动添加）
DROP POLICY IF EXISTS "admin_uids_select_policy" ON admin_uids;
CREATE POLICY "admin_uids_select_policy" ON admin_uids
  FOR SELECT
  TO authenticated
  USING (uid = auth.uid());

-- ------------------------------------------------------------
-- 第四步：辅助函数 - 判断当前用户是否为管理员
-- ------------------------------------------------------------

CREATE OR REPLACE FUNCTION is_admin()
RETURNS BOOLEAN AS $$
BEGIN
  -- 仅 authenticated 角色且 uid 在 admin_uids 表中才算管理员
  RETURN EXISTS (
    SELECT 1 FROM admin_uids WHERE uid = auth.uid()
  );
EXCEPTION
  WHEN OTHERS THEN
    RETURN FALSE;
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = public;

-- ------------------------------------------------------------
-- 第五步：courses 表 RLS 策略
-- ------------------------------------------------------------
-- 规则：
--   anon: 无任何权限
--   authenticated (管理员): 全量读写
--   authenticated (非管理员): 无权限
-- ------------------------------------------------------------

-- SELECT - 仅管理员可读全部
DROP POLICY IF EXISTS "courses_select_admin" ON courses;
CREATE POLICY "courses_select_admin" ON courses
  FOR SELECT
  TO authenticated
  USING (is_admin());

-- INSERT - 仅管理员可插入
DROP POLICY IF EXISTS "courses_insert_admin" ON courses;
CREATE POLICY "courses_insert_admin" ON courses
  FOR INSERT
  TO authenticated
  WITH CHECK (is_admin());

-- UPDATE - 仅管理员可更新
DROP POLICY IF EXISTS "courses_update_admin" ON courses;
CREATE POLICY "courses_update_admin" ON courses
  FOR UPDATE
  TO authenticated
  USING (is_admin())
  WITH CHECK (is_admin());

-- DELETE - 仅管理员可删除
DROP POLICY IF EXISTS "courses_delete_admin" ON courses;
CREATE POLICY "courses_delete_admin" ON courses
  FOR DELETE
  TO authenticated
  USING (is_admin());

-- ------------------------------------------------------------
-- 第六步：reviewers 表 RLS 策略
-- ------------------------------------------------------------

-- SELECT - 仅管理员可读全部
DROP POLICY IF EXISTS "reviewers_select_admin" ON reviewers;
CREATE POLICY "reviewers_select_admin" ON reviewers
  FOR SELECT
  TO authenticated
  USING (is_admin());

-- INSERT - 仅管理员可插入
DROP POLICY IF EXISTS "reviewers_insert_admin" ON reviewers;
CREATE POLICY "reviewers_insert_admin" ON reviewers
  FOR INSERT
  TO authenticated
  WITH CHECK (is_admin());

-- UPDATE - 仅管理员可更新
DROP POLICY IF EXISTS "reviewers_update_admin" ON reviewers;
CREATE POLICY "reviewers_update_admin" ON reviewers
  FOR UPDATE
  TO authenticated
  USING (is_admin())
  WITH CHECK (is_admin());

-- DELETE - 仅管理员可删除
DROP POLICY IF EXISTS "reviewers_delete_admin" ON reviewers;
CREATE POLICY "reviewers_delete_admin" ON reviewers
  FOR DELETE
  TO authenticated
  USING (is_admin());

-- ------------------------------------------------------------
-- 第七步：review_logs 表 RLS 策略
-- ------------------------------------------------------------

-- SELECT - 仅管理员可读全部
DROP POLICY IF EXISTS "review_logs_select_admin" ON review_logs;
CREATE POLICY "review_logs_select_admin" ON review_logs
  FOR SELECT
  TO authenticated
  USING (is_admin());

-- INSERT - 仅管理员可插入
DROP POLICY IF EXISTS "review_logs_insert_admin" ON review_logs;
CREATE POLICY "review_logs_insert_admin" ON review_logs
  FOR INSERT
  TO authenticated
  WITH CHECK (is_admin());

-- UPDATE - 仅管理员可更新
DROP POLICY IF EXISTS "review_logs_update_admin" ON review_logs;
CREATE POLICY "review_logs_update_admin" ON review_logs
  FOR UPDATE
  TO authenticated
  USING (is_admin())
  WITH CHECK (is_admin());

-- DELETE - 仅管理员可删除
DROP POLICY IF EXISTS "review_logs_delete_admin" ON review_logs;
CREATE POLICY "review_logs_delete_admin" ON review_logs
  FOR DELETE
  TO authenticated
  USING (is_admin());

-- ============================================================
-- 迁移完成验证 SQL（可选）
-- ============================================================
-- -- 查看所有策略
-- SELECT tablename, policyname, permissive, roles, cmd, qual, with_check
-- FROM pg_policies
-- WHERE schemaname = 'public'
-- ORDER BY tablename, cmd;
--
-- -- 验证 RLS 已启用
-- SELECT relname, rowsecurity
-- FROM pg_class
-- WHERE relname IN ('courses', 'reviewers', 'review_logs', 'admin_uids')
-- AND relnamespace = 'public'::regnamespace;
--
-- -- 查看管理员 uid 列表
-- SELECT * FROM admin_uids;
-- ============================================================
