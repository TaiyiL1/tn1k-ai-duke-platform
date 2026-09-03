-- ============================================================
-- AI 辅助督课工作台 - 督课官 RPC 函数集 v0.5
-- 版本: v0.5 (Supabase Auth + RPC 受控访问)
-- 日期: 2026-09-03
-- 适用: Supabase PostgreSQL
-- ============================================================
--
-- 【设计原则】
-- 1. 所有函数使用 SECURITY DEFINER 模式，以函数所有者权限执行（绕过 RLS）
-- 2. 函数内部严格校验 reviewer_token 有效性，无效 token 返回空
-- 3. 督课官端完全通过这些 RPC 函数访问数据，禁止直接 SELECT 表
-- 4. 设置 search_path = public，防止 schema 注入
--
-- 【函数列表】
--   1. get_reviewer_info(reviewer_token) -> 督课官基本信息
--   2. get_reviewer_courses(reviewer_token) -> 分配给该督课官的课程列表
--   3. submit_review(...) -> 提交复核结果，更新课程+插入日志+更新计数
-- ============================================================

-- ============================================================
-- 函数 1：get_reviewer_info
-- 功能：根据 token 获取督课官基本信息
-- 参数：p_token TEXT - 督课官 token
-- 返回：TABLE (reviewer_id, reviewer_name, subject, token, max_tasks,
--              assigned_count, completed_count, status)
-- 说明：token 无效或督课官已停用时返回空结果集
-- ============================================================

CREATE OR REPLACE FUNCTION get_reviewer_info(p_token TEXT)
RETURNS TABLE (
  reviewer_id TEXT,
  reviewer_name TEXT,
  subject TEXT,
  token TEXT,
  max_tasks INTEGER,
  assigned_count INTEGER,
  completed_count INTEGER,
  status TEXT
) AS $$
BEGIN
  -- 校验 token 非空
  IF p_token IS NULL OR p_token = '' THEN
    RETURN;
  END IF;

  -- 查询督课官信息（token 必须匹配且状态为启用）
  RETURN QUERY
    SELECT
      r.reviewer_id,
      r.reviewer_name,
      r.subject,
      r.token,
      r.max_tasks,
      r.assigned_count,
      r.completed_count,
      r.status
    FROM reviewers r
    WHERE r.token = p_token
      AND r.status = '启用'
    LIMIT 1;

  RETURN;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public;

-- ============================================================
-- 函数 2：get_reviewer_courses
-- 功能：根据 token 获取该督课官分配的全部课程列表
-- 参数：p_token TEXT - 督课官 token
-- 返回：courses 表的全部字段（该督课官的所有课程）
-- 说明：token 无效返回空结果集
-- ============================================================

CREATE OR REPLACE FUNCTION get_reviewer_courses(p_token TEXT)
RETURNS TABLE (
  course_id TEXT,
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
  final_layer TEXT,
  need_review BOOLEAN,
  need_followup BOOLEAN,
  assigned_reviewer TEXT,
  reviewer_token TEXT,
  review_status TEXT,
  teacher_feedback TEXT,
  internal_notes TEXT,
  created_at TEXT,
  updated_at TEXT
) AS $$
DECLARE
  v_valid BOOLEAN;
BEGIN
  -- 校验 token 非空
  IF p_token IS NULL OR p_token = '' THEN
    RETURN;
  END IF;

  -- 校验 token 有效性（督课官存在且启用）
  SELECT EXISTS (
    SELECT 1 FROM reviewers
    WHERE token = p_token AND status = '启用'
  ) INTO v_valid;

  IF NOT v_valid THEN
    RETURN;
  END IF;

  -- 返回该督课官的所有课程
  RETURN QUERY
    SELECT
      c.course_id,
      c.course_name,
      c.subject,
      c.teacher_name,
      c.teacher_id,
      c.class_name,
      c.school_name,
      c.lesson_time,
      c.duration,
      c.ai_score,
      c.ai_report_url,
      c.replay_url,
      c.ai_layer,
      c.final_layer,
      c.need_review,
      c.need_followup,
      c.assigned_reviewer,
      c.reviewer_token,
      c.review_status,
      c.teacher_feedback,
      c.internal_notes,
      c.created_at,
      c.updated_at
    FROM courses c
    WHERE c.reviewer_token = p_token
    ORDER BY c.created_at DESC;

  RETURN;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public;

-- ============================================================
-- 函数 3：submit_review
-- 功能：提交复核结果
-- 参数：
--   p_token          TEXT    - 督课官 token
--   p_course_id      TEXT    - 课程 ID
--   p_final_layer    TEXT    - 人工复核分层（6分类）
--   p_need_followup  BOOLEAN - 是否需要重点跟进
--   p_has_risk       BOOLEAN - 是否发现异常
--   p_risk_type      TEXT    - 异常类型
--   p_teacher_feedback TEXT  - 给老师的反馈建议
--   p_internal_notes TEXT    - 内部备注
-- 返回：BOOLEAN - 成功返回 true，失败返回 false
-- 说明：
--   1. 校验 token 有效性
--   2. 校验课程属于该督课官（双校验：course_id + reviewer_token）
--   3. 更新 courses 表的 final_layer、need_followup、review_status 等
--   4. 插入 review_logs 记录
--   5. 更新 reviewers 表的 completed_count
--   6. 暂停授课建议 / 清退复审建议 → review_status = '需负责人复审'
-- ============================================================

CREATE OR REPLACE FUNCTION submit_review(
  p_token TEXT,
  p_course_id TEXT,
  p_final_layer TEXT,
  p_need_followup BOOLEAN,
  p_has_risk BOOLEAN,
  p_risk_type TEXT,
  p_teacher_feedback TEXT,
  p_internal_notes TEXT
)
RETURNS BOOLEAN AS $$
DECLARE
  v_reviewer_name TEXT;
  v_reviewer_token TEXT;
  v_status TEXT;
  v_completed_count INTEGER;
BEGIN
  -- 1. 参数校验
  IF p_token IS NULL OR p_token = '' THEN
    RETURN FALSE;
  END IF;
  IF p_course_id IS NULL OR p_course_id = '' THEN
    RETURN FALSE;
  END IF;
  IF p_final_layer IS NULL OR p_final_layer = '' THEN
    RETURN FALSE;
  END IF;

  -- 2. 校验 token 并获取督课官信息
  SELECT reviewer_name, token INTO v_reviewer_name, v_reviewer_token
  FROM reviewers
  WHERE token = p_token AND status = '启用'
  LIMIT 1;

  IF v_reviewer_name IS NULL THEN
    RETURN FALSE;
  END IF;

  -- 3. 校验课程属于该督课官（双校验：course_id + reviewer_token）
  IF NOT EXISTS (
    SELECT 1 FROM courses
    WHERE course_id = p_course_id
      AND reviewer_token = v_reviewer_token
  ) THEN
    RETURN FALSE;
  END IF;

  -- 4. 确定最终状态
  IF p_final_layer IN ('暂停授课建议', '清退复审建议') THEN
    v_status := '需负责人复审';
  ELSE
    v_status := '已完成';
  END IF;

  -- 5. 更新 courses 表
  UPDATE courses
  SET
    final_layer = p_final_layer,
    need_followup = p_need_followup,
    review_status = v_status,
    teacher_feedback = COALESCE(p_teacher_feedback, ''),
    internal_notes = COALESCE(p_internal_notes, ''),
    updated_at = NOW()::TEXT
  WHERE course_id = p_course_id
    AND reviewer_token = v_reviewer_token;

  -- 6. 插入 review_logs
  INSERT INTO review_logs (
    log_id, course_id, reviewer_name, final_layer,
    need_followup, has_risk, risk_type,
    teacher_feedback, internal_notes, submitted_at
  ) VALUES (
    'L' || EXTRACT(EPOCH FROM NOW())::BIGINT::TEXT || '_' || substr(md5(random()::TEXT), 1, 6),
    p_course_id,
    v_reviewer_name,
    p_final_layer,
    p_need_followup,
    p_has_risk,
    COALESCE(p_risk_type, ''),
    COALESCE(p_teacher_feedback, ''),
    COALESCE(p_internal_notes, ''),
    NOW()::TEXT
  );

  -- 7. 更新 reviewers 表的 completed_count
  -- 统计该督课官所有已完成或需复审的课程数
  SELECT COUNT(*) INTO v_completed_count
  FROM courses
  WHERE reviewer_token = v_reviewer_token
    AND review_status IN ('已完成', '需负责人复审');

  UPDATE reviewers
  SET completed_count = v_completed_count
  WHERE token = v_reviewer_token;

  RETURN TRUE;
EXCEPTION
  WHEN OTHERS THEN
    RAISE NOTICE 'submit_review error: %', SQLERRM;
    RETURN FALSE;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public;

-- ============================================================
-- 权限设置
-- ============================================================
-- 授予 anon 和 authenticated 角色执行 RPC 函数的权限
-- （函数内部自己做 token 校验，RLS 不限制函数调用）

GRANT EXECUTE ON FUNCTION get_reviewer_info(TEXT) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION get_reviewer_courses(TEXT) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION submit_review(TEXT, TEXT, TEXT, BOOLEAN, BOOLEAN, TEXT, TEXT, TEXT) TO anon, authenticated;

-- ============================================================
-- 验证测试 SQL（可选）
-- ============================================================
-- -- 测试获取督课官信息
-- SELECT * FROM get_reviewer_info('你的token');
--
-- -- 测试获取课程列表
-- SELECT * FROM get_reviewer_courses('你的token') LIMIT 5;
--
-- -- 测试提交复核
-- SELECT submit_review(
--   '你的token',
--   'C001',
--   '优秀课候选',
--   false,
--   false,
--   '',
--   '老师您好...',
--   '内部备注...'
-- );
-- ============================================================
