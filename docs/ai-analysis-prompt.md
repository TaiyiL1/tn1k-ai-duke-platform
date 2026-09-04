# AI 深度分析 Prompt 模板

本文档定义 v1.0 中「AI 二次分析」调用大模型时使用的 System Prompt 和 User Prompt 模板。

## 一、模型配置

| 项目 | 值 |
|------|-----|
| API 协议 | OpenAI Compatible (Chat Completions) |
| 支持供应商 | Moonshot（Kimi）、OpenAI、智谱、通义千问等 |
| 响应格式 | JSON Object |
| 温度 (temperature) | 0.3 |
| 最大 Token | 2048 |

## 二、System Prompt

```
你是一名专业的在线课堂督课分析师，服务于「童年一课云教室」公益项目。
你的任务是对 ClassIn AI 授课分析报告进行二次深度分析，从教育质量、学生体验、教师成长三个维度给出可执行的建议。

请严格遵守以下分析原则：
1. **客观中立**：基于报告事实分析，不臆测、不夸大
2. **具体可操作**：建议必须具体到可以直接给老师反馈，避免空泛表述
3. **分层归因**：区分「课程设计问题」「教师技能问题」「学生因素」「技术因素」
4. **风险敏感**：涉及体罚、辱骂、不当言论、安全隐患等必须标记为高风险
5. **公益导向**：童年一课是乡村教育公益项目，教师多为志愿者，建议语气鼓励为主

输出必须是合法的 JSON 对象，严格遵循以下结构（字段不可缺省）：
{
  "course_summary": "一句话概括本节课整体情况（50字以内）",
  "classin_issues_summary": "对 ClassIn AI 标注的问题进行归纳梳理（100字以内）",
  "ai_second_opinion": "你的二次分析意见，包含深度洞察和与 ClassIn AI 的异同判断（150字以内）",
  "risk_level": "low | medium | high | critical",
  "manual_review_issues": ["需要人工复核的问题点列表，每条30字以内"],
  "reviewer_focus_points": ["督课官复核时应重点关注的方向列表，每条20字以内"],
  "teacher_improvement_suggestions": ["给授课老师的具体改进建议，每条40字以内，可操作"],
  "suggest_video_review": true|false,
  "suggest_audio_transcript": true|false,
  "suggest_leader_review": true|false
}

风险等级说明：
- low：整体优秀或常规，无明显问题
- medium：有改进空间，但不影响基本教学质量
- high：存在较明显问题，需要督课官重点关注并反馈
- critical：存在严重问题（体罚、辱骂、违规、安全隐患等），必须负责人复审
```

## 三、User Prompt 模板

```
请对以下课程的 AI 分析报告进行二次深度分析：

【基本信息】
- 课程名称：{course_name}
- 科目：{subject}
- 授课教师：{teacher_name}
- 班级：{class_name}
- 课程时长：{duration} 分钟
- ClassIn AI 得分：{ai_score} / 100
- 课堂标签：{class_label}

【ClassIn AI 标注的问题】
{classin_ai_issues}

【AI 报告原文摘要】
{report_raw_text}

【规则初筛结果】
- 初筛分层：{initial_layer}
- 初筛理由：{screen_reason}

请基于以上信息，输出你的深度分析结果（JSON 格式）。
```

## 四、字段回填映射

AI 返回的 JSON 结果，按以下规则回填到数据库字段：

| AI 返回字段 | 数据库字段 | 说明 |
|-------------|-----------|------|
| `course_summary` | `ai_action_suggestions.course_summary` | 存入 JSON |
| `classin_issues_summary` | `ai_action_suggestions.classin_issues_summary` | 存入 JSON |
| `ai_second_opinion` | `ai_action_suggestions.ai_second_opinion` | 存入 JSON；同时取前 200 字存入 `ai_deep_analysis` |
| `risk_level` | `risk_level`；`ai_action_suggestions.risk_level` | 双写 |
| `manual_review_issues` | `ai_action_suggestions.manual_review_issues` | 存入 JSON |
| `reviewer_focus_points` | `ai_action_suggestions.reviewer_focus_points` | 存入 JSON |
| `teacher_improvement_suggestions` | `ai_action_suggestions.teacher_improvement_suggestions` | 存入 JSON |
| `suggest_video_review` | `needs_video_review`；`ai_action_suggestions.suggest_video_review` | 双写 |
| `suggest_audio_transcript` | `needs_audio_transcript`；`ai_action_suggestions.suggest_audio_transcript` | 双写 |
| `suggest_leader_review` | `needs_leader_review`；`ai_action_suggestions.suggest_leader_review` | 双写 |
| - | `analysis_depth` | 成功分析后更新为 `report_deep_ai` |

## 五、失败与降级

### 5.1 重试策略

- 最多重试 3 次
- 每次重试间隔 2 秒
- 重试条件：网络错误、5xx 响应、JSON 解析失败

### 5.2 失败标记

分析失败时：
- `analysis_depth` 保持原值
- `ai_deep_analysis` 写入错误信息（`[分析失败] xxx`）
- `ai_action_suggestions` 为空

### 5.3 Token 估算

- 输入 Token 估算：`(report_raw_text 字数 + prompt 字数) / 1.5`
- 输出 Token 估算：`500`（固定上限预估）
- 成本估算（按 Moonshot 8K 模型 0.012元/千tokens）：
  - 单课约 `0.02 ~ 0.05 元`
  - 批量分析前显示总成本预估

## 六、分层分类决策树（规则初筛 + AI 校准）

### 第一层：规则初筛（零成本，全量执行）

```
if 无AI报告 → 待人工判断（analysis_depth = basic_report_only）
else if AI 得分 < 40 → 异常课（高风险候选）
else if 含「不当」「辱骂」「体罚」「违规」关键词 → 异常课 + 需负责人复审
else if AI 得分 < 60 → 重点提升课
else if 含「互动低」「参与度低」「沉默」关键词 → 重点提升课
else if AI 得分 > 85 且无严重问题 → 优秀课候选
else → 常规课
```

### 第二层：AI 深度分析（仅重点提升课 + 异常课）

根据 AI 返回结果调整分层：
- `risk_level = critical` → 升级为「清退复审建议」+ 需负责人复审
- `risk_level = high` + 严重教学问题 → 升级为「暂停授课建议」
- 原本规则初筛为「重点提升课」但 AI 分析认为问题轻微 → 降级为「常规课」
- 原本规则初筛为「常规课」但 AI 发现隐藏问题 → 升级为「重点提升课」

### 第三层：人工复核（高风险必走）

- 所有「暂停授课建议」和「清退复审建议」必须人工复审
- 督课官提交后，负责人（管理员）最终确认

## 七、提示词优化备注

1. 报告原文较长时（>3000字），自动截断前 2500 字 + 后 500 字
2. 科目信息作为上下文注入，帮助模型判断专业性
3. 规则初筛结果提供给模型，避免重复劳动，让模型聚焦于「深度洞察」
4. response_format 设为 json_object 确保结构化输出稳定
