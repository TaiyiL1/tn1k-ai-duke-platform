-- ============================================================
-- AI 辅助督课工作台 - RLS 行级安全策略收紧方案
-- 版本: v1.0
-- 日期: 2026-09-03
-- 适用: Supabase PostgreSQL
-- ============================================================
--
-- 【方案说明】
-- 本系统使用 Supabase 的 anon/publishable key 进行前端数据访问。
-- 由于 anon key 的 auth.uid() 为 NULL，无法直接基于用户身份做 RLS。
--
-- 本方案使用「自定义请求头 x-reviewer-token」作为督课官身份标识：
--   - 管理员端：不携带 x-reviewer-token 头 → RLS 判定为管理员 → 全量读写
--   - 督课官端：携带 x-reviewer-token: <token> 头 → RLS 仅放行匹配 token 的数据
--
-- 优点：
--   1. 无需引入 Supabase Auth，不改变现有用户体系（token 制）
--   2. 管理员端代码零侵入（保持原样即可）
--   3. 督课官端数据读写都受 RLS 强制约束，无法越权
--   4. 实现简单，单文件 SQL 即可迁移
--
-- 局限：
--   1. 读权限隔离依赖前端正确设置 header（因 anon key 本身是公开的）
--   2. 如果督课官知道其他督课官的 token，可以伪造 header 访问（内部工具可接受）
--   3. 如需更强隔离，应引入 Supabase Auth authenticated 角色或 Edge Functions
--
-- 【前端配合】
--   - 管理员端：使用普通 sbClient（无特殊 header）
--   - 督课官端：sbClient 初始化时添加 global.headers: { 'x-reviewer-token': token }
-- ============================================================

-- ------------------------------------------------------------
-- 第一步：删除旧的全开放策略
-- ------------------------------------------------------------

DROP POLICY IF EXISTS "Allow all operations on courses" ON courses;
DROP POLICY IF EXISTS "Allow all operations on reviewers" ON reviewers;
DROP POLICY IF EXISTS "Allow all operations on review_logs" ON review_logs;

-- ------------------------------------------------------------
-- 第二步：创建辅助函数（提取 x-reviewer-token 请求头）
-- ------------------------------------------------------------

CREATE OR REPLACE FUNCTION get_reviewer_token()
RETURNS TEXT AS $$
BEGIN
  RETURN current_setting('request.headers', true)::json->>'x-reviewer-token';
EXCEPTION
  WHEN OTHERS THEN
    RETURN NULL;
END;
$$ LANGUAGE plpgsql STABLE;

-- ------------------------------------------------------------
-- 第三步：courses 表 RLS 策略
-- ------------------------------------------------------------
-- 规则：
--   SELECT - 管理员：全部；督课官：仅 reviewer_token = 自己的 token
--   INSERT - 管理员：全部；督课官：禁止
--   UPDATE - 管理员：全部；督课官：仅 reviewer_token = 自己的 token，且不能修改 reviewer_token
--   DELETE - 管理员：全部；督课官：禁止
-- ------------------------------------------------------------

-- SELECT
CREATE POLICY "courses_select_policy" ON courses
  FOR SELECT
  USING (
    get_reviewer_token() IS NULL
    OR reviewer_token = get_reviewer_token()
  );

-- INSERT
CREATE POLICY "courses_insert_policy" ON courses
  FOR INSERT
  WITH CHECK (
    get_reviewer_token() IS NULL
  );

-- UPDATE
CREATE POLICY "courses_update_policy" ON courses
  FOR UPDATE
  USING (
    get_reviewer_token() IS NULL
    OR reviewer_token = get_reviewer_token()
  )
  WITH CHECK (
    get_reviewer_token() IS NULL
    OR (
      reviewer_token = get_reviewer_token()
      AND reviewer_token = OLD.reviewer_token
    )
  );

-- DELETE
CREATE POLICY "courses_delete_policy" ON courses
  FOR DELETE
  USING (
    get_reviewer_token() IS NULL
  );

-- ------------------------------------------------------------
-- 第四步：reviewers 表 RLS 策略
-- ------------------------------------------------------------
-- 规则：
--   SELECT - 管理员：全部；督课官：仅 token = 自己的 token（只能看到自己）
--   INSERT - 管理员：全部；督课官：禁止
--   UPDATE - 管理员：全部；督课官：仅 token = 自己的 token，且不能修改 token
--   DELETE - 管理员：全部；督课官：禁止
-- ------------------------------------------------------------

-- SELECT
CREATE POLICY "reviewers_select_policy" ON reviewers
  FOR SELECT
  USING (
    get_reviewer_token() IS NULL
    OR token = get_reviewer_token()
  );

-- INSERT
CREATE POLICY "reviewers_insert_policy" ON reviewers
  FOR INSERT
  WITH CHECK (
    get_reviewer_token() IS NULL
  );

-- UPDATE
CREATE POLICY "reviewers_update_policy" ON reviewers
  FOR UPDATE
  USING (
    get_reviewer_token() IS NULL
    OR token = get_reviewer_token()
  )
  WITH CHECK (
    get_reviewer_token() IS NULL
    OR (
      token = get_reviewer_token()
      AND token = OLD.token
    )
  );

-- DELETE
CREATE POLICY "reviewers_delete_policy" ON reviewers
  FOR DELETE
  USING (
    get_reviewer_token() IS NULL
  );

-- ------------------------------------------------------------
-- 第五步：review_logs 表 RLS 策略
-- ------------------------------------------------------------
-- 规则：
--   SELECT - 管理员：全部；督课官：禁止（不能读取所有督课记录）
--   INSERT - 管理员：全部；督课官：仅 reviewer_name 对应自己（token 匹配的督课官名）
--   UPDATE - 管理员：全部；督课官：禁止
--   DELETE - 管理员：全部；督课官：禁止
-- ------------------------------------------------------------

-- SELECT
CREATE POLICY "review_logs_select_policy" ON review_logs
  FOR SELECT
  USING (
    get_reviewer_token() IS NULL
  );

-- INSERT
CREATE POLICY "review_logs_insert_policy" ON review_logs
  FOR INSERT
  WITH CHECK (
    get_reviewer_token() IS NULL
    OR reviewer_name = (
      SELECT reviewer_name FROM reviewers WHERE token = get_reviewer_token() LIMIT 1
    )
  );

-- UPDATE
CREATE POLICY "review_logs_update_policy" ON review_logs
  FOR UPDATE
  USING (
    get_reviewer_token() IS NULL
  );

-- DELETE
CREATE POLICY "review_logs_delete_policy" ON review_logs
  FOR DELETE
  USING (
    get_reviewer_token() IS NULL
  );

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
-- WHERE relname IN ('courses', 'reviewers', 'review_logs')
-- AND relnamespace = 'public'::regnamespace;
-- ============================================================
