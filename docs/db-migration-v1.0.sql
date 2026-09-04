-- ============================================================
-- AI 辅助督课深度分析平台 v1.0 数据库迁移 SQL
-- 适用：从 v0.5 升级到 v1.0
-- 执行方式：在 Supabase SQL Editor 中完整执行
-- ============================================================

-- ============================================================
-- 一、import_batches 表（导入批次）
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
  subject_distribution TEXT DEFAULT '', -- JSON 字符串
  ai_analysis_pending INTEGER DEFAULT 0,
  ai_analysis_done INTEGER DEFAULT 0,
  ai_analysis_failed INTEGER DEFAULT 0
);

ALTER TABLE import_batches ENABLE ROW LEVEL SECURITY;

CREATE POLICY "import_batches_select_admin" ON import_batches FOR SELECT TO authenticated USING (is_admin());
CREATE POLICY "import_batches_insert_admin" ON import_batches FOR INSERT TO authenticated WITH CHECK (is_admin());
CREATE POLICY "import_batches_update_admin" ON import_batches FOR UPDATE TO authenticated USING (is_admin()) WITH CHECK (is_admin());
CREATE POLICY "import_batches_delete_admin" ON import_batches FOR DELETE TO authenticated USING (is_admin());

-- ============================================================
-- 二、courses 表新增字段
-- ============================================================

-- 报告读取相关
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='courses' AND column_name='report_fetch_status') THEN
    ALTER TABLE courses ADD COLUMN report_fetch_status TEXT DEFAULT 'pending';
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='courses' AND column_name='report_fetch_error') THEN
    ALTER TABLE courses ADD COLUMN report_fetch_error TEXT DEFAULT '';
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='courses' AND column_name='report_raw_text') THEN
    ALTER TABLE courses ADD COLUMN report_raw_text TEXT DEFAULT '';
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='courses' AND column_name='report_structured_json') THEN
    ALTER TABLE courses ADD COLUMN report_structured_json TEXT DEFAULT '';
  END IF;
END $$;

-- AI 深度分析相关
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='courses' AND column_name='ai_deep_analysis') THEN
    ALTER TABLE courses ADD COLUMN ai_deep_analysis TEXT DEFAULT '';
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='courses' AND column_name='ai_action_suggestions') THEN
    ALTER TABLE courses ADD COLUMN ai_action_suggestions TEXT DEFAULT '';
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='courses' AND column_name='analysis_depth') THEN
    ALTER TABLE courses ADD COLUMN analysis_depth TEXT DEFAULT 'basic_report_only';
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='courses' AND column_name='risk_level') THEN
    ALTER TABLE courses ADD COLUMN risk_level TEXT DEFAULT '';
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='courses' AND column_name='needs_video_review') THEN
    ALTER TABLE courses ADD COLUMN needs_video_review BOOLEAN DEFAULT false;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='courses' AND column_name='needs_audio_transcript') THEN
    ALTER TABLE courses ADD COLUMN needs_audio_transcript BOOLEAN DEFAULT false;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='courses' AND column_name='needs_leader_review') THEN
    ALTER TABLE courses ADD COLUMN needs_leader_review BOOLEAN DEFAULT false;
  END IF;
END $$;

-- 科目识别来源
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='courses' AND column_name='subject_detected_from') THEN
    ALTER TABLE courses ADD COLUMN subject_detected_from TEXT DEFAULT '';
  END IF;
END $$;

-- 导入批次
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='courses' AND column_name='import_batch_id') THEN
    ALTER TABLE courses ADD COLUMN import_batch_id TEXT DEFAULT '';
  END IF;
END $$;

-- ClassIn 原始字段
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='courses' AND column_name='classin_class_id') THEN
    ALTER TABLE courses ADD COLUMN classin_class_id TEXT DEFAULT '';
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='courses' AND column_name='classin_class_name') THEN
    ALTER TABLE courses ADD COLUMN classin_class_name TEXT DEFAULT '';
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='courses' AND column_name='classin_class_label') THEN
    ALTER TABLE courses ADD COLUMN classin_class_label TEXT DEFAULT '';
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='courses' AND column_name='classin_ai_score') THEN
    ALTER TABLE courses ADD COLUMN classin_ai_score NUMERIC;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='courses' AND column_name='classin_ai_issues') THEN
    ALTER TABLE courses ADD COLUMN classin_ai_issues TEXT DEFAULT '';
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='courses' AND column_name='classin_report_url') THEN
    ALTER TABLE courses ADD COLUMN classin_report_url TEXT DEFAULT '';
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='courses' AND column_name='classin_replay_url') THEN
    ALTER TABLE courses ADD COLUMN classin_replay_url TEXT DEFAULT '';
  END IF;
END $$;

-- ============================================================
-- 三、数据回填：将已有数据映射到新字段
-- ============================================================
-- 把 ai_score 同步到 classin_ai_score（便于保留原始分数）
UPDATE courses SET classin_ai_score = ai_score WHERE classin_ai_score IS NULL AND ai_score IS NOT NULL;

-- 把 ai_report_url 同步到 classin_report_url
UPDATE courses SET classin_report_url = ai_report_url WHERE classin_report_url = '' AND ai_report_url IS NOT NULL AND ai_report_url <> '';

-- 把 replay_url 同步到 classin_replay_url
UPDATE courses SET classin_replay_url = replay_url WHERE classin_replay_url = '' AND replay_url IS NOT NULL AND replay_url <> '';

-- 把 course_name 同步到 classin_class_name（保留原始名称）
UPDATE courses SET classin_class_name = course_name WHERE classin_class_name = '' AND course_name IS NOT NULL;

-- 已有报告链接的标记为待读取，无报告链接的标记为 none
UPDATE courses SET report_fetch_status = 'pending'
  WHERE report_fetch_status IS NULL OR report_fetch_status = ''
    AND ai_report_url IS NOT NULL AND ai_report_url <> '';

UPDATE courses SET report_fetch_status = 'none'
  WHERE (report_fetch_status IS NULL OR report_fetch_status = '')
    AND (ai_report_url IS NULL OR ai_report_url = '');

-- analysis_depth 初始化
UPDATE courses SET analysis_depth = 'basic_report_only' WHERE analysis_depth IS NULL OR analysis_depth = '';

-- ============================================================
-- 四、RLS 策略已在 v0.5 建表时整体授权给管理员，新增字段自动继承
--    无需额外 RLS 配置
-- ============================================================

-- ============================================================
-- 五、新增统计视图（可选，便于总览查询）
-- ============================================================

-- 按分层统计
CREATE OR REPLACE VIEW v_layer_stats AS
SELECT
  ai_layer AS layer,
  COUNT(*) AS cnt
FROM courses
GROUP BY ai_layer;

-- 按科目统计
CREATE OR REPLACE VIEW v_subject_stats AS
SELECT
  subject,
  COUNT(*) AS cnt
FROM courses
WHERE subject IS NOT NULL AND subject <> ''
GROUP BY subject;

-- 按风险等级统计
CREATE OR REPLACE VIEW v_risk_stats AS
SELECT
  risk_level,
  COUNT(*) AS cnt
FROM courses
WHERE risk_level IS NOT NULL AND risk_level <> ''
GROUP BY risk_level;

-- 报告读取状态统计
CREATE OR REPLACE VIEW v_report_fetch_stats AS
SELECT
  report_fetch_status AS status,
  COUNT(*) AS cnt
FROM courses
GROUP BY report_fetch_status;

-- AI 分析状态统计（根据 analysis_depth 判断）
CREATE OR REPLACE VIEW v_ai_analysis_stats AS
SELECT
  CASE
    WHEN analysis_depth = 'basic_report_only' THEN '未分析'
    WHEN analysis_depth = 'report_deep_ai' THEN '已深度分析'
    WHEN analysis_depth = 'video_frame_needed' THEN '需视频复核'
    WHEN analysis_depth = 'audio_transcript_needed' THEN '需音频转写'
    WHEN analysis_depth = 'manual_review_required' THEN '需人工复审'
    ELSE analysis_depth
  END AS analysis_status,
  COUNT(*) AS cnt
FROM courses
GROUP BY analysis_depth;

-- 授予 authenticated 角色视图查询权限（通过 RLS 控制 courses 表）
GRANT SELECT ON v_layer_stats TO authenticated;
GRANT SELECT ON v_subject_stats TO authenticated;
GRANT SELECT ON v_risk_stats TO authenticated;
GRANT SELECT ON v_report_fetch_stats TO authenticated;
GRANT SELECT ON v_ai_analysis_stats TO authenticated;

-- ============================================================
-- 迁移完成标记
-- ============================================================
-- 迁移版本：v1.0
-- 迁移日期：2026-09
-- 说明：
--   1. 新增 import_batches 导入批次表
--   2. courses 表新增 18 个字段（报告读取、AI分析、ClassIn原始字段）
--   3. 新增 5 个统计视图
--   4. 已有数据自动回填到对应新字段
