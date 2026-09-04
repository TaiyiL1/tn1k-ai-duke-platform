/**
 * Cloudflare Worker: fetch-classin-report
 *
 * 功能：后端抓取 ClassIn 报告页面，提取正文并做初步结构化解析，返回 JSON。
 * 用途：替代前端直接 CORS 代理，解决浏览器跨域限制。
 *
 * 部署方式：
 *   方式 A（Dashboard）：Cloudflare Dashboard → Workers & Pages → Create Worker
 *            → 用本文件内容替换默认代码 → Deploy
 *   方式 B（Wrangler）：
 *            npm install -g wrangler
 *            wrangler login
 *            wrangler init fetch-classin-report
 *            # 用本文件替换 src/index.js
 *            wrangler deploy
 *
 * 前端 API 调用：
 *   POST <worker-url>
 *   Content-Type: application/json
 *   Body: { "report_url": "https://share.eeo.cn/..." }
 *
 * 与 Supabase Edge Function 版本接口完全一致。
 */

const ALLOWED_HOSTNAMES = ["eeo.cn", "share.eeo.cn", "www.eeo.cn"];
const USER_AGENT = "Mozilla/5.0 (compatible; ClassinReportFetcher/1.0)";
const FETCH_TIMEOUT_MS = 30_000;

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "Content-Type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function jsonResponse(data, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: {
      ...corsHeaders,
      "Content-Type": "application/json;charset=utf-8",
    },
  });
}

function isAllowedUrl(reportUrl) {
  try {
    const u = new URL(reportUrl);
    const host = u.hostname.toLowerCase();
    return ALLOWED_HOSTNAMES.some(
      (h) => host === h || host.endsWith("." + h.replace(/^www\./, ""))
    );
  } catch {
    return false;
  }
}

function stripHtmlNoise(html) {
  let cleaned = html.replace(
    /<(script|style|noscript|iframe)[\s\S]*?<\/\1>/gi,
    ""
  );
  cleaned = cleaned.replace(/<(nav|footer|header)[\s\S]*?<\/\1>/gi, "");
  return cleaned;
}

function extractTextFromHtml(html) {
  const cleaned = stripHtmlNoise(html);
  const withNewlines = cleaned.replace(/<\/(p|div|br|li|h[1-6])>/gi, "\n");
  const text = withNewlines.replace(/<[^>]+>/g, " ");
  return text.replace(/\s+/g, " ").trim();
}

function extractHeadings(html) {
  const headings = [];
  const re = /<h[1-3][^>]*>([\s\S]*?)<\/h[1-3]>/gi;
  let m;
  while ((m = re.exec(html)) !== null) {
    const txt = m[1].replace(/<[^>]+>/g, "").replace(/\s+/g, " ").trim();
    if (txt) headings.push(txt);
  }
  return [...new Set(headings)].slice(0, 50);
}

function parseStructured(rawText, html) {
  const result = {
    score: null,
    issue_summary: null,
    interaction_summary: null,
    teacher_behavior: null,
    student_participation: null,
    raw_sections: [],
  };

  if (!rawText) return result;

  // 分数
  const scorePatterns = [
    /(?:AI授课分析得分|AI得分|综合得分|总评分|得分|分数)[^0-9]{0,10}(\d{1,3}(?:\.\d{1,2})?)/i,
    /(\d{2,3}(?:\.\d{1,2})?)\s*分/,
  ];
  for (const p of scorePatterns) {
    const m = rawText.match(p);
    if (m) {
      const s = parseFloat(m[1]);
      if (s >= 0 && s <= 100) {
        result.score = s;
        break;
      }
    }
  }

  // 章节标题
  const headings = extractHeadings(html);
  const sectionKeywords = [
    "课堂概况",
    "课堂互动",
    "教师表现",
    "学生参与",
    "教学内容",
    "教学过程",
    "问题反馈",
    "综合评价",
    "需关注问题",
    "亮点",
    "建议",
  ];
  result.raw_sections = [...headings];
  for (const kw of sectionKeywords) {
    if (rawText.includes(kw) && !result.raw_sections.includes(kw)) {
      result.raw_sections.push(kw);
    }
  }
  result.raw_sections = [...new Set(result.raw_sections)].slice(0, 50);

  // 需关注问题
  const issueMatch = rawText.match(
    /需关注问题[^。！？]{0,200}([^。！？]{20,200})/
  );
  if (issueMatch) {
    result.issue_summary = issueMatch[1].trim().substring(0, 200);
  } else {
    const sentences = rawText
      .split(/[。！？\n]/)
      .filter(
        (s) =>
          /问题|不足|需关注|风险/.test(s) && s.length > 8 && s.length < 150
      );
    if (sentences.length) {
      result.issue_summary = sentences.slice(0, 3).join("；").substring(0, 200);
    }
  }

  // 课堂互动
  const interactMatch = rawText.match(
    /(?:课堂互动|互动情况|互动参与)[^。！？]{0,50}([^。！？]{20,200})/
  );
  if (interactMatch) {
    result.interaction_summary = interactMatch[1].trim().substring(0, 200);
  } else {
    const sentences = rawText
      .split(/[。！？\n]/)
      .filter(
        (s) =>
          /互动|提问|回答|举手|参与/.test(s) && s.length > 10 && s.length < 150
      );
    if (sentences.length) {
      result.interaction_summary = sentences
        .slice(0, 3)
        .join("；")
        .substring(0, 200);
    }
  }

  // 教师表现
  const teacherMatch = rawText.match(
    /(?:教师表现|教师行为|授课表现|教学状态)[^。！？]{0,50}([^。！？]{20,200})/
  );
  if (teacherMatch) {
    result.teacher_behavior = teacherMatch[1].trim().substring(0, 200);
  } else {
    const sentences = rawText
      .split(/[。！？\n]/)
      .filter(
        (s) =>
          /教师|老师|授课|教学/.test(s) && s.length > 10 && s.length < 150
      );
    if (sentences.length) {
      result.teacher_behavior = sentences
        .slice(0, 3)
        .join("；")
        .substring(0, 200);
    }
  }

  // 学生参与
  const studentMatch = rawText.match(
    /(?:学生参与|学生表现|学生状态|课堂参与)[^。！？]{0,50}([^。！？]{20,200})/
  );
  if (studentMatch) {
    result.student_participation = studentMatch[1].trim().substring(0, 200);
  } else {
    const sentences = rawText
      .split(/[。！？\n]/)
      .filter(
        (s) =>
          /学生|参与|专注|注意力/.test(s) && s.length > 10 && s.length < 150
      );
    if (sentences.length) {
      result.student_participation = sentences
        .slice(0, 3)
        .join("；")
        .substring(0, 200);
    }
  }

  return result;
}

export default {
  async fetch(request, env, ctx) {
    // 处理 CORS 预检
    if (request.method === "OPTIONS") {
      return new Response("ok", { headers: corsHeaders });
    }

    // 仅允许 POST
    if (request.method !== "POST") {
      return jsonResponse(
        {
          success: false,
          error_type: "parse_failed",
          message: "仅支持 POST 请求",
        },
        405
      );
    }

    let reportUrl = "";
    try {
      const body = await request.json();
      reportUrl = (body.report_url || "").toString().trim();
    } catch {
      return jsonResponse(
        {
          success: false,
          error_type: "parse_failed",
          message: "请求体 JSON 解析失败",
        },
        400
      );
    }

    if (!reportUrl) {
      return jsonResponse(
        {
          success: false,
          error_type: "parse_failed",
          message: "report_url 不能为空",
        },
        400
      );
    }

    // 域名校验
    if (!isAllowedUrl(reportUrl)) {
      return jsonResponse(
        {
          success: false,
          error_type: "unsupported_domain",
          message:
            "不支持的域名，仅允许 eeo.cn / share.eeo.cn / www.eeo.cn 下的报告链接",
        },
        400
      );
    }

    // 抓取页面（30 秒超时）
    const controller = new AbortController();
    const timeoutId = setTimeout(() => controller.abort(), FETCH_TIMEOUT_MS);
    let resp;

    try {
      resp = await fetch(reportUrl, {
        signal: controller.signal,
        headers: {
          "User-Agent": USER_AGENT,
          Accept:
            "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
          "Accept-Language": "zh-CN,zh;q=0.9",
        },
        redirect: "follow",
        cf: {
          // Cloudflare 特有：缓存 TTL（仅 GET 有效，这里是后端发起请求，不缓存）
          cacheTtl: 0,
          cacheEverything: false,
        },
      });
    } catch (e) {
      clearTimeout(timeoutId);
      const msg = e.message || String(e);
      if (msg.includes("abort") || msg.includes("timeout")) {
        return jsonResponse(
          {
            success: false,
            error_type: "timeout",
            message: "请求 ClassIn 报告页面超时（30秒）",
          },
          504
        );
      }
      return jsonResponse(
        {
          success: false,
          error_type: "parse_failed",
          message: "抓取报告页面失败：" + msg,
        },
        502
      );
    }

    clearTimeout(timeoutId);

    // 检查 HTTP 状态码
    if (resp.status === 401 || resp.status === 403) {
      return jsonResponse(
        {
          success: false,
          error_type: "auth_required",
          message: `报告页面需要登录或权限不足（HTTP ${resp.status}）`,
        },
        resp.status
      );
    }

    if (resp.status === 404) {
      return jsonResponse(
        {
          success: false,
          error_type: "parse_failed",
          message: "页面不存在（HTTP 404）",
        },
        404
      );
    }

    if (!resp.ok) {
      return jsonResponse(
        {
          success: false,
          error_type: "parse_failed",
          message: `报告页面返回 HTTP ${resp.status}`,
        },
        502
      );
    }

    const html = await resp.text();
    const rawText = extractTextFromHtml(html);

    if (!rawText || rawText.length < 50) {
      return jsonResponse(
        {
          success: false,
          error_type: "parse_failed",
          message: "页面正文内容过短，可能不是有效报告页面",
        },
        502
      );
    }

    const structured = parseStructured(rawText, html);

    return jsonResponse({
      success: true,
      raw_text: rawText.substring(0, 20000),
      structured,
    });
  },
};
