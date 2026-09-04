-- ============================================================
-- AI 辅助督课深度分析平台 v1.0 数据库迁移 SQL（All-in-One）
-- 版本: v1.0 (2026-09)
-- 适用场景:
--   1. 全新 Supabase 项目直接完整执行
--   2. v0.5 已建项目可安全重跑（幂等）
-- 执行方式: 在 Supabase SQL Editor 中完整执行
-- 说明: 全部使用 CREATE OR REPLACE / CREATE TABLE IF NOT EXISTS /
--       IF NOT EXISTS 保证幂等安全，重复执行不会报错。
-- ============================================================

-- ============================================================
-- 第一步：admin_uids 管理员表
-- ============================================================

CREATE TABLE IF NOT EXISTS admin_uids (
  uid UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  email TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE admin_uids ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "admin_uids_select_policy" ON admin_uids;
CREATE POLICY "admin_uids_select_policy" ON admin_uids
  FOR SELECT
  TO authenticated
  USING (uid = auth.uid());

-- ============================================================
-- 第二步：is_admin() 辅助函数
-- ============================================================

CREATE OR REPLACE FUNCTION is_admin()
RETURNS BOOLEAN AS $$
BEGIN
  RETURN EXISTS (
    SELECT 1 FROM admin_uids WHERE uid = auth.uid()
  );
EXCEPTION
  WHEN OTHERS THEN
    RETURN FALSE;
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = public;

-- ============================================================
-- 第三步：courses 课程表
-- ============================================================

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
  updated_at TEXT,
  -- v1.0 新增：报告读取相关
  report_fetch_status TEXT DEFAULT 'pending',
  report_fetch_error TEXT DEFAULT '',
  report_raw_text TEXT DEFAULT '',
  report_structured_json JSONB DEFAULT '{}'::jsonb,
  -- v1.0 新增：AI 深度分析相关
  ai_deep_analysis TEXT DEFAULT '',
  ai_action_suggestions TEXT DEFAULT '',
  analysis_depth TEXT DEFAULT 'basic_report_only',
  ai_analysis_status TEXT DEFAULT 'pending',
  ai_analysis_error TEXT DEFAULT '',
  risk_level TEXT DEFAULT '',
  needs_video_review BOOLEAN DEFAULT false,
  needs_audio_transcript BOOLEAN DEFAULT false,
  needs_leader_review BOOLEAN DEFAULT false,
  subject_detected_from TEXT DEFAULT '',
  import_batch_id TEXT DEFAULT '',
  -- v1.0 新增：ClassIn 原始字段
  classin_class_id TEXT DEFAULT '',
  classin_class_name TEXT DEFAULT '',
  classin_class_label TEXT DEFAULT '',
  classin_ai_score NUMERIC,
  classin_ai_issues TEXT DEFAULT '',
  classin_report_url TEXT DEFAULT '',
  classin_replay_url TEXT DEFAULT ''
);

ALTER TABLE courses ENABLE ROW LEVEL SECURITY;

-- courses RLS 策略
DROP POLICY IF EXISTS "courses_select_admin" ON courses;
CREATE POLICY "courses_select_admin" ON courses
  FOR SELECT TO authenticated USING (is_admin());

DROP POLICY IF EXISTS "courses_insert_admin" ON courses;
CREATE POLICY "courses_insert_admin" ON courses
  FOR INSERT TO authenticated WITH CHECK (is_admin());

DROP POLICY IF EXISTS "courses_update_admin" ON courses;
CREATE POLICY "courses_update_admin" ON courses
  FOR UPDATE TO authenticated USING (is_admin()) WITH CHECK (is_admin());

DROP POLICY IF EXISTS "courses_delete_admin" ON courses;
CREATE POLICY "courses_delete_admin" ON courses
  FOR DELETE TO authenticated USING (is_admin());

-- ============================================================
-- 第四步：reviewers 督课官表
-- ============================================================

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

ALTER TABLE reviewers ENABLE ROW LEVEL SECURITY;

-- reviewers RLS 策略
DROP POLICY IF EXISTS "reviewers_select_admin" ON reviewers;
CREATE POLICY "reviewers_select_admin" ON reviewers
  FOR SELECT TO authenticated USING (is_admin());

DROP POLICY IF EXISTS "reviewers_insert_admin" ON reviewers;
CREATE POLICY "reviewers_insert_admin" ON reviewers
  FOR INSERT TO authenticated WITH CHECK (is_admin());

DROP POLICY IF EXISTS "reviewers_update_admin" ON reviewers;
CREATE POLICY "reviewers_update_admin" ON reviewers
  FOR UPDATE TO authenticated USING (is_admin()) WITH CHECK (is_admin());

DROP POLICY IF EXISTS "reviewers_delete_admin" ON reviewers;
CREATE POLICY "reviewers_delete_admin" ON reviewers
  FOR DELETE TO authenticated USING (is_admin());

-- ============================================================
-- 第五步：review_logs 督课记录表
-- ============================================================

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

ALTER TABLE review_logs ENABLE ROW LEVEL SECURITY;

-- review_logs RLS 策略
DROP POLICY IF EXISTS "review_logs_select_admin" ON review_logs;
CREATE POLICY "review_logs_select_admin" ON review_logs
  FOR SELECT TO authenticated USING (is_admin());

DROP POLICY IF EXISTS "review_logs_insert_admin" ON review_logs;
CREATE POLICY "review_logs_insert_admin" ON review_logs
  FOR INSERT TO authenticated WITH CHECK (is_admin());

DROP POLICY IF EXISTS "review_logs_update_admin" ON review_logs;
CREATE POLICY "review_logs_update_admin" ON review_logs
  FOR UPDATE TO authenticated USING (is_admin()) WITH CHECK (is_admin());

DROP POLICY IF EXISTS "review_logs_delete_admin" ON review_logs;
CREATE POLICY "review_logs_delete_admin" ON review_logs
  FOR DELETE TO authenticated USING (is_admin());

-- ============================================================
-- 第六步：import_batches 导入批次表 (v1.0 新增)
-- ============================================================

CREATE TABLE IF NOT EXISTS import_batches (
  id TEXT PRIMARY KEY,
  file_name TEXT,
  imported_at TEXT,
  total_rows INTEGER DEFAULT 0,
  valid_course_rows INTEGER DEFAULT 0,
  rows_with_report_link INTEGER DEFAULT 0,
  rows_without_report_link INTEGER DEFAULT 0,
  fetch_success_count INTEGER DEFAULT 0,
  fetch_failed_count INTEGER DEFAULT 0,
  subject_distribution TEXT DEFAULT '',
  ai_analysis_pending INTEGER DEFAULT 0,
  ai_analysis_done INTEGER DEFAULT 0,
  ai_analysis_failed INTEGER DEFAULT 0
);

ALTER TABLE import_batches ENABLE ROW LEVEL SECURITY;

-- import_batches RLS 策略
DROP POLICY IF EXISTS "import_batches_select_admin" ON import_batches;
CREATE POLICY "import_batches_select_admin" ON import_batches
  FOR SELECT TO authenticated USING (is_admin());

DROP POLICY IF EXISTS "import_batches_insert_admin" ON import_batches;
CREATE POLICY "import_batches_insert_admin" ON import_batches
  FOR INSERT TO authenticated WITH CHECK (is_admin());

DROP POLICY IF EXISTS "import_batches_update_admin" ON import_batches;
CREATE POLICY "import_batches_update_admin" ON import_batches
  FOR UPDATE TO authenticated USING (is_admin()) WITH CHECK (is_admin());

DROP POLICY IF EXISTS "import_batches_delete_admin" ON import_batches;
CREATE POLICY "import_batches_delete_admin" ON import_batches
  FOR DELETE TO authenticated USING (is_admin());

-- ============================================================
-- 第七步：courses 表新字段迁移（v0.5 升级兼容）
-- ============================================================
-- v0.5 已建 courses 表但缺少 v1.0 字段时，自动补齐

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='courses' AND column_name='report_fetch_status') THEN
    ALTER TABLE courses ADD COLUMN report_fetch_status TEXT DEFAULT 'pending';
  END IF;
EXCEPTION WHEN OTHERS THEN NULL;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='courses' AND column_name='report_fetch_error') THEN
    ALTER TABLE courses ADD COLUMN report_fetch_error TEXT DEFAULT '';
  END IF;
EXCEPTION WHEN OTHERS THEN NULL;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='courses' AND column_name='report_raw_text') THEN
    ALTER TABLE courses ADD COLUMN report_raw_text TEXT DEFAULT '';
  END IF;
EXCEPTION WHEN OTHERS THEN NULL;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='courses' AND column_name='report_structured_json') THEN
    ALTER TABLE courses ADD COLUMN report_structured_json JSONB DEFAULT '{}'::jsonb;
  ELSE
    -- 如果已有列且类型为 TEXT，安全转换为 JSONB
    IF EXISTS (
      SELECT 1 FROM information_schema.columns
      WHERE table_name='courses' AND column_name='report_structured_json' AND data_type='text'
    ) THEN
      ALTER TABLE courses ALTER COLUMN report_structured_json
        TYPE JSONB USING
        CASE
          WHEN report_structured_json IS NULL OR report_structured_json = '' THEN '{}'::jsonb
          ELSE report_structured_json::jsonb
        END;
      ALTER TABLE courses ALTER COLUMN report_structured_json SET DEFAULT '{}'::jsonb;
    END IF;
  END IF;
EXCEPTION WHEN OTHERS THEN NULL;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='courses' AND column_name='ai_deep_analysis') THEN
    ALTER TABLE courses ADD COLUMN ai_deep_analysis TEXT DEFAULT '';
  END IF;
EXCEPTION WHEN OTHERS THEN NULL;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='courses' AND column_name='ai_action_suggestions') THEN
    ALTER TABLE courses ADD COLUMN ai_action_suggestions TEXT DEFAULT '';
  END IF;
EXCEPTION WHEN OTHERS THEN NULL;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='courses' AND column_name='analysis_depth') THEN
    ALTER TABLE courses ADD COLUMN analysis_depth TEXT DEFAULT 'basic_report_only';
  END IF;
EXCEPTION WHEN OTHERS THEN NULL;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='courses' AND column_name='ai_analysis_status') THEN
    ALTER TABLE courses ADD COLUMN ai_analysis_status TEXT DEFAULT 'pending';
  END IF;
EXCEPTION WHEN OTHERS THEN NULL;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='courses' AND column_name='ai_analysis_error') THEN
    ALTER TABLE courses ADD COLUMN ai_analysis_error TEXT DEFAULT '';
  END IF;
EXCEPTION WHEN OTHERS THEN NULL;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='courses' AND column_name='risk_level') THEN
    ALTER TABLE courses ADD COLUMN risk_level TEXT DEFAULT '';
  END IF;
EXCEPTION WHEN OTHERS THEN NULL;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='courses' AND column_name='needs_video_review') THEN
    ALTER TABLE courses ADD COLUMN needs_video_review BOOLEAN DEFAULT false;
  END IF;
EXCEPTION WHEN OTHERS THEN NULL;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='courses' AND column_name='needs_audio_transcript') THEN
    ALTER TABLE courses ADD COLUMN needs_audio_transcript BOOLEAN DEFAULT false;
  END IF;
EXCEPTION WHEN OTHERS THEN NULL;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='courses' AND column_name='needs_leader_review') THEN
    ALTER TABLE courses ADD COLUMN needs_leader_review BOOLEAN DEFAULT false;
  END IF;
EXCEPTION WHEN OTHERS THEN NULL;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='courses' AND column_name='subject_detected_from') THEN
    ALTER TABLE courses ADD COLUMN subject_detected_from TEXT DEFAULT '';
  END IF;
EXCEPTION WHEN OTHERS THEN NULL;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='courses' AND column_name='import_batch_id') THEN
    ALTER TABLE courses ADD COLUMN import_batch_id TEXT DEFAULT '';
  END IF;
EXCEPTION WHEN OTHERS THEN NULL;
END $$;

-- ClassIn 原始字段（v1.0 新增，逐个补齐）
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='courses' AND column_name='classin_class_id') THEN
    ALTER TABLE courses ADD COLUMN classin_class_id TEXT DEFAULT '';
  END IF;
EXCEPTION WHEN OTHERS THEN NULL;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='courses' AND column_name='classin_class_name') THEN
    ALTER TABLE courses ADD COLUMN classin_class_name TEXT DEFAULT '';
  END IF;
EXCEPTION WHEN OTHERS THEN NULL;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='courses' AND column_name='classin_class_label') THEN
    ALTER TABLE courses ADD COLUMN classin_class_label TEXT DEFAULT '';
  END IF;
EXCEPTION WHEN OTHERS THEN NULL;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='courses' AND column_name='classin_ai_score') THEN
    ALTER TABLE courses ADD COLUMN classin_ai_score NUMERIC;
  END IF;
EXCEPTION WHEN OTHERS THEN NULL;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='courses' AND column_name='classin_ai_issues') THEN
    ALTER TABLE courses ADD COLUMN classin_ai_issues TEXT DEFAULT '';
  END IF;
EXCEPTION WHEN OTHERS THEN NULL;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='courses' AND column_name='classin_report_url') THEN
    ALTER TABLE courses ADD COLUMN classin_report_url TEXT DEFAULT '';
  END IF;
EXCEPTION WHEN OTHERS THEN NULL;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='courses' AND column_name='classin_replay_url') THEN
    ALTER TABLE courses ADD COLUMN classin_replay_url TEXT DEFAULT '';
  END IF;
EXCEPTION WHEN OTHERS THEN NULL;
END $$;

-- ============================================================
-- 第八步：历史数据回填（v0.5 升级兼容）
-- ============================================================

-- 把 ai_score 同步到 classin_ai_score
UPDATE courses SET classin_ai_score = ai_score
  WHERE (classin_ai_score IS NULL OR classin_ai_score = 0)
    AND ai_score IS NOT NULL;

-- 把 ai_report_url 同步到 classin_report_url
UPDATE courses SET classin_report_url = ai_report_url
  WHERE classin_report_url = '' AND ai_report_url IS NOT NULL AND ai_report_url <> '';

-- 把 replay_url 同步到 classin_replay_url
UPDATE courses SET classin_replay_url = replay_url
  WHERE classin_replay_url = '' AND replay_url IS NOT NULL AND replay_url <> '';

-- 把 course_name 同步到 classin_class_name
UPDATE courses SET classin_class_name = course_name
  WHERE classin_class_name = '' AND course_name IS NOT NULL;

-- 报告读取状态初始化
UPDATE courses SET report_fetch_status = 'pending'
  WHERE (report_fetch_status IS NULL OR report_fetch_status = '')
    AND ai_report_url IS NOT NULL AND ai_report_url <> '';

UPDATE courses SET report_fetch_status = 'none'
  WHERE (report_fetch_status IS NULL OR report_fetch_status = '')
    AND (ai_report_url IS NULL OR ai_report_url = '');

-- analysis_depth 初始化
UPDATE courses SET analysis_depth = 'basic_report_only'
  WHERE analysis_depth IS NULL OR analysis_depth = '';

-- ai_analysis_status 初始化
UPDATE courses SET ai_analysis_status = 'success'
  WHERE ai_deep_analysis IS NOT NULL AND ai_deep_analysis <> ''
    AND (ai_analysis_status IS NULL OR ai_analysis_status = '');

UPDATE courses SET ai_analysis_status = 'pending'
  WHERE analysis_depth = 'report_deep_ai'
    AND (ai_analysis_status IS NULL OR ai_analysis_status = '');

-- ============================================================
-- 第九步：3 个督课官 RPC 函数
-- ============================================================

-- 函数 1：get_reviewer_info
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
  IF p_token IS NULL OR p_token = '' THEN RETURN; END IF;
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
    WHERE r.token = p_token AND r.status = '启用'
    LIMIT 1;
  RETURN;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public;

-- 函数 2：get_reviewer_courses
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
  updated_at TEXT,
  risk_level TEXT,
  needs_leader_review BOOLEAN,
  ai_deep_analysis TEXT
) AS $$
DECLARE
  v_valid BOOLEAN;
BEGIN
  IF p_token IS NULL OR p_token = '' THEN RETURN; END IF;
  SELECT EXISTS (
    SELECT 1 FROM reviewers WHERE token = p_token AND status = '启用'
  ) INTO v_valid;
  IF NOT v_valid THEN RETURN; END IF;
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
      c.updated_at,
      c.risk_level,
      c.needs_leader_review,
      c.ai_deep_analysis
    FROM courses c
    WHERE c.reviewer_token = p_token
    ORDER BY c.created_at DESC;
  RETURN;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public;

-- 函数 3：submit_review
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
  IF p_token IS NULL OR p_token = '' THEN RETURN FALSE; END IF;
  IF p_course_id IS NULL OR p_course_id = '' THEN RETURN FALSE; END IF;
  IF p_final_layer IS NULL OR p_final_layer = '' THEN RETURN FALSE; END IF;

  SELECT reviewer_name, token INTO v_reviewer_name, v_reviewer_token
  FROM reviewers
  WHERE token = p_token AND status = '启用'
  LIMIT 1;

  IF v_reviewer_name IS NULL THEN RETURN FALSE; END IF;

  IF NOT EXISTS (
    SELECT 1 FROM courses
    WHERE course_id = p_course_id AND reviewer_token = v_reviewer_token
  ) THEN
    RETURN FALSE;
  END IF;

  IF p_final_layer IN ('暂停授课建议', '清退复审建议') THEN
    v_status := '需负责人复审';
  ELSE
    v_status := '已完成';
  END IF;

  UPDATE courses
  SET
    final_layer = p_final_layer,
    need_followup = p_need_followup,
    review_status = v_status,
    teacher_feedback = COALESCE(p_teacher_feedback, ''),
    internal_notes = COALESCE(p_internal_notes, ''),
    updated_at = NOW()::TEXT
  WHERE course_id = p_course_id AND reviewer_token = v_reviewer_token;

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

-- 函数 4：increment_batch_count（批次计数原子更新）
CREATE OR REPLACE FUNCTION increment_batch_count(p_batch_id TEXT, p_field TEXT, p_delta INTEGER)
RETURNS BOOLEAN AS $$
DECLARE v_sql TEXT;
BEGIN
  IF p_batch_id IS NULL OR p_batch_id = '' THEN
    RETURN FALSE;
  END IF;
  IF p_field NOT IN (
    'fetch_success_count', 'fetch_failed_count',
    'ai_analysis_pending', 'ai_analysis_done', 'ai_analysis_failed',
    'total_rows', 'valid_course_rows'
  ) THEN
    RETURN FALSE;
  END IF;

  v_sql := 'UPDATE import_batches SET ' || quote_ident(p_field) || ' = '
        || quote_ident(p_field) || ' + $1 WHERE id = $2';
  EXECUTE v_sql USING p_delta, p_batch_id;
  RETURN TRUE;
EXCEPTION
  WHEN OTHERS THEN
    RAISE NOTICE 'increment_batch_count error: %', SQLERRM;
    RETURN FALSE;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public;

-- 授权 anon 和 authenticated 角色执行 RPC 函数
GRANT EXECUTE ON FUNCTION get_reviewer_info(TEXT) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION get_reviewer_courses(TEXT) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION submit_review(TEXT, TEXT, TEXT, BOOLEAN, BOOLEAN, TEXT, TEXT, TEXT) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION increment_batch_count(TEXT, TEXT, INTEGER) TO authenticated;

-- ============================================================
-- 第十步：统计视图（可选）
-- ============================================================

-- 按分层统计
CREATE OR REPLACE VIEW v_layer_stats AS
SELECT ai_layer AS layer, COUNT(*) AS cnt
FROM courses GROUP BY ai_layer;

-- 按科目统计
CREATE OR REPLACE VIEW v_subject_stats AS
SELECT subject, COUNT(*) AS cnt
FROM courses WHERE subject IS NOT NULL AND subject <> ''
GROUP BY subject;

-- 按风险等级统计
CREATE OR REPLACE VIEW v_risk_stats AS
SELECT risk_level, COUNT(*) AS cnt
FROM courses WHERE risk_level IS NOT NULL AND risk_level <> ''
GROUP BY risk_level;

-- 报告读取状态统计
CREATE OR REPLACE VIEW v_report_fetch_stats AS
SELECT report_fetch_status AS status, COUNT(*) AS cnt
FROM courses GROUP BY report_fetch_status;

-- AI 分析状态统计
CREATE OR REPLACE VIEW v_ai_analysis_stats AS
SELECT ai_analysis_status AS status, COUNT(*) AS cnt
FROM courses GROUP BY ai_analysis_status;

-- 授权 authenticated 角色视图查询权限
GRANT SELECT ON v_layer_stats TO authenticated;
GRANT SELECT ON v_subject_stats TO authenticated;
GRANT SELECT ON v_risk_stats TO authenticated;
GRANT SELECT ON v_report_fetch_stats TO authenticated;
GRANT SELECT ON v_ai_analysis_stats TO authenticated;

-- ============================================================
-- 迁移完成
-- ============================================================
-- 迁移版本：v1.0
-- 迁移日期：2026-09
-- 说明：
--   1. All-in-One 完整迁移，从全新 Supabase 项目可直接执行
--   2. v0.5 项目可安全重跑，不会报错
--   3. 包含 admin_uids 表 + is_admin() 函数
--   4. 包含 courses / reviewers / review_logs 三张表 + RLS
--   5. 包含 import_batches 表 + RLS
--   6. courses 表包含全部 v1.0 新字段
--   7. 包含 3 个督课官 RPC 函数
--   8. 包含历史数据回填逻辑
--   9. 包含 5 个统计视图
