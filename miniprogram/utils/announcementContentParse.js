/**
 * 门店公告：富文本 HTML 方案（与公众号/编辑器一致，后端存 HTML，小程序 rich-text 渲染）
 * 说明：微信 rich-text 支持的标签子集有限，后台编辑器导出时请尽量使用 p/div/span/strong/br/h2/ul/li 等常见标签。
 */

export function stripAnnouncementScripts(html) {
  if (html == null || html === "") return "";
  return String(html).replace(/<script[\s\S]*?>[\s\S]*?<\/script>/gi, "");
}

/** 去掉常见 XSS 载体（保留正文标签由后台可信源控制） */
export function sanitizeAnnouncementHtml(html) {
  let s = stripAnnouncementScripts(html);
  s = s.replace(/<iframe[\s\S]*?>[\s\S]*?<\/iframe>/gi, "");
  s = s.replace(/<object[\s\S]*?>[\s\S]*?<\/object>/gi, "");
  s = s.replace(/<embed[^>]*>/gi, "");
  // 行内事件属性
  s = s.replace(/\s+on\w+\s*=\s*(["'])[\s\S]*?\1/gi, "");
  s = s.replace(/\s+on\w+\s*=\s*[^\s>]+/gi, "");
  s = relaxTightEditorLineHeight(s);
  return s;
}

/**
 * 富文本编辑器常导出 line-height:1，在小程序 rich-text 里会显得上下贴死；
 * 只把「数值为 1 / 1.0」的写法放宽，不误伤 1.2、12px 等。
 */
export function relaxTightEditorLineHeight(html) {
  return String(html).replace(
    /line-height\s*:\s*(1(\.0+)?)(?![0-9.])(\s*;|\s*(?=["']))/gi,
    () => "line-height: 1.72;"
  );
}

/** 整块公告外边距（内部仍以内联 style 为准） */
function wrapAnnouncementRichRoot(innerHtml) {
  return `<div style="font-size:28rpx;color:#333;padding:8rpx 0 16rpx 0;box-sizing:border-box;">${innerHtml}</div>`;
}

function looksLikeHtml(s) {
  const t = String(s).trim();
  if (!t) return false;
  if (t.startsWith("<")) return true;
  return /<\/?[a-z][a-z0-9]*[\s>]/i.test(t);
}

function escapeHtmlText(s) {
  return String(s)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}

/**
 * 供 rich-text :nodes 使用（字符串 HTML，基础库支持）
 * @param {string|{ html?: string }|null|undefined} content
 * @returns {string}
 */
export function getAnnouncementRichTextHtml(content) {
  if (content == null || content === "") {
    return '<div style="font-size:28rpx;color:#999;line-height:1.6;">（无正文）</div>';
  }

  if (typeof content === "object" && content !== null) {
    if (typeof content.html === "string" && content.html.trim()) {
      return wrapAnnouncementRichRoot(sanitizeAnnouncementHtml(content.html));
    }
    return '<div style="font-size:28rpx;color:#999;">（无正文）</div>';
  }

  const str = String(content).trim();
  if (!str) {
    return '<div style="font-size:28rpx;color:#999;line-height:1.6;">（无正文）</div>';
  }

  if (looksLikeHtml(str)) {
    return wrapAnnouncementRichRoot(sanitizeAnnouncementHtml(str));
  }

  // 旧版 JSON 区块数据：引导后台改存富文本 HTML
  if (str.startsWith("{") && /"blocks"\s*:/.test(str)) {
    return '<div style="font-size:26rpx;color:#888;line-height:1.65;padding:8rpx 0;">该公告为旧版数据，请在管理后台用富文本重新编辑并保存。</div>';
  }

  // 纯文本（无标签）：保留换行，运营直接粘贴也能看
  const escaped = escapeHtmlText(str);
  return `<div style="font-size:28rpx;color:#444;line-height:1.75;white-space:pre-wrap;word-break:break-word;">${escaped}</div>`;
}
