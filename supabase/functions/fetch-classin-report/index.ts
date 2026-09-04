// Follow this setup guide to integrate the Deno language server with your editor:
// https://deno.land/manual/getting_started/setup_your_environment
// This enables autocomplete, go to definition, etc.

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";

const ALLOWED_HOSTNAMES = ["eeo.cn", "share.eeo.cn", "www.eeo.cn"];
const USER_AGENT = "Mozilla/5.0 (compatible; ClassinReportFetcher/1.0)";
const FETCH_TIMEOUT_MS = 30_000;

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function isAllowedUrl(reportUrl: string): boolean {
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

function stripHtmlNoise(html: string): string {
  // 去除 script / style / noscript / iframe 标签及其内容
  let cleaned = html.replace(
    /<(script|style|noscript|iframe)[\s\S]*?<\/\1>/gi,
    ""
  );
  // 去除 nav / footer / header 标签
  cleaned = cleaned.replace(
    /<(nav|footer|header)[\s\S]*?<\/\1>/gi,
    ""
  );
  return cleaned;
}

function extractTextFromHtml(html: string): string {
  const cleaned = stripHtmlNoise(html);
  // 将所有 HTML 标签替换为换行，再合并空白
  const withNewlines = cleaned.replace(/<\/(p|div|br|li|h[1-6])>/gi, "\n");
  const text = withNewlines.replace(/<[^>]+>/g, " ");
  return text.replace(/\s+/g, " ").trim();
}

function extractHeadings(html: string): string[] {
  const headings: string[] = [];
  const re = /<h[1-3][^>]*>([\s\S]*?)<\/h[1-3]>/gi;
  let m: RegExpExecArray | null;
  while ((m = re.exec(html)) !== null) {
    const txt = m[1].replace(/<[^>]+>/g, "").replace(/\s+/g, " ").trim();
    if (txt) headings.push(txt);
  }
  return [...new Set(headings)].slice(0, 50);
}

function parseStructured(rawText: string, html: string) {
  const result = {
    score: null as number | null,
    issue_summary: null as string | null,
    interaction_summary: null as string | null,
    teacher_behavior: null as string | null,
    student_participation: null as string | null,
    raw_sections: [] as string[],
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

  // 章节标题：先从 h1-h3 提取，再补充关键词命中
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

serve(async (req: Request) => {
  // 处理 OPTIONS 预检请求
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  // 仅允许 POST
  if (req.method !== "POST") {
    return new Response(
      JSON.stringify({
        success: false,
        error_type: "parse_failed",
        message: "仅支持 POST 请求",
      }),
      { headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }

  let reportUrl = "";
  try {
    const body = await req.json();
    reportUrl = (body.report_url || "").toString().trim();
  } catch {
    return new Response(
      JSON.stringify({
        success: false,
        error_type: "parse_failed",
        message: "请求体 JSON 解析失败",
      }),
      {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
        status: 400,
      }
    );
  }

  if (!reportUrl) {
    return new Response(
      JSON.stringify({
        success: false,
        error_type: "parse_failed",
        message: "report_url 不能为空",
      }),
      {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
        status: 400,
      }
    );
  }

  // 域名校验
  if (!isAllowedUrl(reportUrl)) {
    return new Response(
      JSON.stringify({
        success: false,
        error_type: "unsupported_domain",
        message:
          "不支持的域名，仅允许 eeo.cn / share.eeo.cn / www.eeo.cn 下的报告链接",
      }),
      {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
        status: 400,
      }
    );
  }

  // 抓取页面（30 秒超时）
  const controller = new AbortController();
  const timeoutId = setTimeout(() => controller.abort(), FETCH_TIMEOUT_MS);
  let resp: Response;

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
    });
  } catch (e: unknown) {
    clearTimeout(timeoutId);
    const msg = e instanceof Error ? e.message : String(e);
    if (msg.includes("abort") || msg.includes("timeout")) {
      return new Response(
        JSON.stringify({
          success: false,
          error_type: "timeout",
          message: "请求 ClassIn 报告页面超时（30秒）",
        }),
        {
          headers: { ...corsHeaders, "Content-Type": "application/json" },
          status: 504,
        }
      );
    }
    return new Response(
      JSON.stringify({
        success: false,
        error_type: "parse_failed",
        message: "抓取报告页面失败：" + msg,
      }),
      {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
        status: 502,
      }
    );
  }

  clearTimeout(timeoutId);

  // 检查 HTTP 状态码
  if (resp.status === 401 || resp.status === 403) {
    return new Response(
      JSON.stringify({
        success: false,
        error_type: "auth_required",
        message: `报告页面需要登录或权限不足（HTTP ${resp.status}）`,
      }),
      {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
        status: resp.status,
      }
    );
  }

  if (resp.status === 404) {
    return new Response(
      JSON.stringify({
        success: false,
        error_type: "parse_failed",
        message: "页面不存在（HTTP 404）",
      }),
      {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
        status: 404,
      }
    );
  }

  if (!resp.ok) {
    return new Response(
      JSON.stringify({
        success: false,
        error_type: "parse_failed",
        message: `报告页面返回 HTTP ${resp.status}`,
      }),
      {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
        status: 502,
      }
    );
  }

  const html = await resp.text();
  const rawText = extractTextFromHtml(html);

  if (!rawText || rawText.length < 50) {
    return new Response(
      JSON.stringify({
        success: false,
        error_type: "parse_failed",
        message: "页面正文内容过短，可能不是有效报告页面",
      }),
      {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
        status: 502,
      }
    );
  }

  const structured = parseStructured(rawText, html);

  return new Response(
    JSON.stringify({
      success: true,
      raw_text: rawText.substring(0, 20000),
      structured,
    }),
    {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    }
  );
});

// To invoke:
// curl -i --location --request POST 'http://localhost:54321/functions/v1/fetch-classin-report' \
//   --header 'Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...' \
//   --header 'Content-Type: application/json' \
//   --data '{"report_url":"https://share.eeo.cn/xxx"}'
