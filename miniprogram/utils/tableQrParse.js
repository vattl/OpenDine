/**
 * 从扫码/落地页内容解析台号（支持 D02、scene 内嵌参数、JSON、粘连 query 等）
 */

export function decodeQueryParamValue(raw) {
  if (raw == null) return "";
  try {
    return decodeURIComponent(String(raw).replace(/\+/g, " ")).trim();
  } catch (e) {
    return String(raw).trim();
  }
}

const TABLE_QUERY_KEYS = [
  "number",
  "table_number",
  "table",
  "desk",
  "no",
  "tb",
  "tn",
  "tableNo",
  "table_no",
  "tableNumber",
  "qrcode",
];

/** 去掉值尾部粘连的 shop_id=…（含 number=D02shop_id=4 无 & 的情况） */
function stripTrailingShopIdFromParamValue(v) {
  let s = String(v || "").trim();
  if (!s) return "";
  const bySep = s.search(/[&?]shop_id=/i);
  if (bySep >= 0) s = s.slice(0, bySep).trim();
  const glued = s.search(/shop_id=/i);
  if (glued > 0 && !/^shop_id=/i.test(s)) s = s.slice(0, glued).trim();
  return s.replace(/[&;?]+$/g, "").trim();
}

/** 仅从 query 串解析 number=/table=…（不含 scene 展开，避免递归） */
function parseTableKeysFromQueryString(queryPart) {
  const str = String(queryPart || "").replace(/;/g, "&");
  if (!str) return "";
  for (let i = 0; i < TABLE_QUERY_KEYS.length; i++) {
    const key = TABLE_QUERY_KEYS[i];
    const re = new RegExp(`(?:^|[?&])${key}=([^&\\s#;]+)`, "i");
    const hit = str.match(re);
    if (hit && hit[1]) {
      let v = decodeQueryParamValue(hit[1]);
      v = stripTrailingShopIdFromParamValue(v);
      if (v) return v;
    }
  }
  // 容错：number 后漏写 =，如 ?numberD02shop_id=4
  const gluedKey = str.match(/(?:^|[?&])number([^&?#\s=][^&?#]*)/i);
  if (gluedKey && gluedKey[1]) {
    let v = decodeQueryParamValue(gluedKey[1]);
    v = stripTrailingShopIdFromParamValue(v);
    if (v) return v;
  }
  return "";
}

/** scene 为纯自定义串时尝试拆出台号（如 d_D02、D02、8） */
function parseTableFromPlainSceneToken(sceneDecoded) {
  let raw = String(sceneDecoded || "").trim();
  if (!raw || raw.length > 128) return "";
  if (/^https?:\/\//i.test(raw)) return "";
  raw = stripTrailingShopIdFromParamValue(raw);
  if (!raw) return "";
  if (raw.includes("=")) {
    const q = raw.replace(/,/g, "&");
    const t = parseTableKeysFromQueryString(q.startsWith("?") ? q : `?${q}`);
    if (t) return t;
  }
  const compressed = raw.match(/^s(\d+)n([\w.-]+)$/i);
  if (compressed && compressed[2]) return String(compressed[2]).trim();
  const segs = raw.split(/[,_/|]+/).map((s) => s.trim()).filter(Boolean);
  for (let i = 0; i < segs.length; i++) {
    const seg = segs[i];
    if (!seg) continue;
    if (/^shop/i.test(seg)) continue;
    if (/^s\d+$/i.test(seg) && segs.length > 1) continue;
    const segClean = stripTrailingShopIdFromParamValue(seg);
    if (!segClean) continue;
    if (/^\d{1,6}$/.test(segClean)) return segClean;
    if (/^[A-Za-z][-_]?\d{1,6}$/i.test(segClean)) return segClean;
    if (/^[A-Za-z]\d{1,6}$/.test(segClean)) return segClean;
    if (/^[A-Za-z]{1,4}\d{1,6}$/.test(segClean)) return segClean;
  }
  if (/^\d{1,6}$/.test(raw)) return raw;
  if (/[A-Za-z]/.test(raw) && /^[A-Za-z0-9._-]+$/.test(raw) && segs.length === 1) return raw;
  return "";
}

/** 解析含 scene= 的 query（小程序码常见：path?scene=number%3DD02 或 scene=d_D02） */
function parseTableFromQueryWithScene(queryPart) {
  const str = String(queryPart || "").replace(/;/g, "&");
  if (!str) return "";
  const sceneMatch = str.match(/(?:^|[?&])scene=([^&\s#;]+)/i);
  if (sceneMatch && sceneMatch[1]) {
    const decoded = decodeQueryParamValue(sceneMatch[1]);
    if (decoded) {
      const innerQuery = decoded.includes("=")
        ? decoded.replace(/,/g, "&")
        : "";
      if (innerQuery) {
        const t = parseTableKeysFromQueryString(innerQuery.startsWith("?") ? innerQuery : `?${innerQuery}`);
        if (t) return t;
      }
      const plain = parseTableFromPlainSceneToken(decoded);
      if (plain) return plain;
    }
  }
  return parseTableKeysFromQueryString(str.startsWith("?") ? str : `?${str}`);
}

/** 扫码 result 为 JSON（部分机型/容器会返回） */
function tryParseTableFromJsonString(s) {
  const t = String(s || "").trim();
  if (!t || t[0] !== "{") return "";
  try {
    const j = JSON.parse(t);
    const qObj = j.query || (j.miniProgram && j.miniProgram.query) || (j.referrerInfo && j.referrerInfo.extraData);
    if (qObj && typeof qObj === "object") {
      for (let i = 0; i < TABLE_QUERY_KEYS.length; i++) {
        const k = TABLE_QUERY_KEYS[i];
        if (qObj[k] != null && String(qObj[k]).trim()) return String(qObj[k]).trim();
      }
      if (qObj.scene != null && String(qObj.scene).trim()) {
        const sc = String(qObj.scene).trim();
        const fromScene = parseTableFromQueryWithScene(`?scene=${encodeURIComponent(sc)}`);
        if (fromScene) return fromScene;
      }
    }
    const paths = [j.path, j.miniProgram && j.miniProgram.path].filter(Boolean);
    for (let p = 0; p < paths.length; p++) {
      const full = String(paths[p]);
      const qi = full.indexOf("?");
      if (qi >= 0) {
        const sub = full.slice(qi);
        const tt = parseTableFromQueryWithScene(sub);
        if (tt) return tt;
      }
    }
  } catch (e) {
    return "";
  }
  return "";
}

/** result 仅为台号文本（无 query），且 merged 已含 shop_id 时仍可用 */
function tryParseIsolatedTableFromResult(merged, scanResult) {
  const raw = scanResult != null ? String(scanResult).trim() : "";
  if (!raw || raw.length > 32 || /[?&=]/.test(raw)) return "";
  if (/^pages\//i.test(raw) || /^https?:\/\//i.test(raw) || /^\{/.test(raw)) return "";
  if (/shop_id/i.test(raw)) return "";
  if (!/(?:^|[?&])shop_id=\d+/i.test(String(merged || ""))) return "";
  if (/^(?:\d{1,6}|[A-Za-z][A-Za-z0-9._-]{0,15})$/.test(raw)) return raw;
  return "";
}

function collectCandidates(merged) {
  const out = [];
  const seen = new Set();
  const add = (x) => {
    const t = String(x == null ? "" : x).trim();
    if (!t || seen.has(t)) return;
    seen.add(t);
    out.push(t);
  };
  add(merged);
  String(merged || "")
    .split(/\s+/)
    .forEach(add);
  for (let i = 0; i < out.length; i++) {
    const c = out[i];
    if (/^https?:\/\//i.test(c)) {
      const m = c.match(/\?([^#]+)/);
      if (m && m[1]) add(m[1]);
    }
  }
  return out;
}

/**
 * @param {string} merged path、result、多段拼接
 * @returns {string} 台号，未识别到则空串
 */
export function parseTableNumberFromMergedQuery(merged) {
  const candidates = collectCandidates(merged);
  for (let i = 0; i < candidates.length; i++) {
    const t = tryParseTableFromJsonString(candidates[i]);
    if (t) return t;
  }
  for (let i = 0; i < candidates.length; i++) {
    const c = candidates[i];
    if (c.includes("?")) {
      const sub = c.slice(c.indexOf("?"));
      const t = parseTableFromQueryWithScene(sub);
      if (t) return t;
    }
  }
  for (let i = 0; i < candidates.length; i++) {
    const t = parseTableFromQueryWithScene(candidates[i]);
    if (t) return t;
  }
  return "";
}

export function extractShopIdFromMerged(merged) {
  const m = String(merged || "").match(/(?:^|[?&])shop_id=(\d+)/i);
  return m ? Number(m[1]) : null;
}

/** 从 wx.scanCode 的 res 拼接待解析原文（含 rawData 可打印段） */
export function buildMergedFromScanCodeResult(res) {
  const mergeParts = [res && res.path, res && res.result].filter(Boolean);
  const rd = res && res.rawData != null ? String(res.rawData).trim() : "";
  if (rd && typeof wx !== "undefined" && typeof wx.base64ToArrayBuffer === "function") {
    try {
      const buf = wx.base64ToArrayBuffer(rd);
      const arr = new Uint8Array(buf);
      let txt = "";
      for (let i = 0; i < arr.length && i < 2048; i++) {
        const b = arr[i];
        if (b === 9 || b === 10 || b === 13 || (b >= 32 && b <= 126)) {
          txt += String.fromCharCode(b);
        } else {
          break;
        }
      }
      if (txt.length > 4 && /[?&=/A-Za-z0-9]/.test(txt)) mergeParts.push(txt);
    } catch (e) {
      /* ignore */
    }
  }
  return mergeParts.join(" ");
}

/**
 * 从扫码结果解析台号与 shop_id（与 App.scanCode 校验逻辑一致）
 * @param {object} res wx.scanCode success 回调参数
 * @returns {{ tableNumber: string, shopId: number|null, merged: string }}
 */
export function parseTableNumberFromScanCodeResult(res) {
  const merged = buildMergedFromScanCodeResult(res);
  let tableNumber = parseTableNumberFromMergedQuery(merged);
  const hasShopId = /(?:^|[?&])shop_id=\d+/i.test(merged);
  if (!tableNumber && !hasShopId) {
    const fb = merged.match(/\b(\d{1,6})\b/);
    if (fb) tableNumber = String(fb[1]);
  }
  if (!tableNumber && res && res.result) {
    tableNumber = tryParseIsolatedTableFromResult(merged, res.result);
  }
  if (!tableNumber && res && res.result) {
    const rawTrim = String(res.result).trim();
    if (rawTrim && !/[?&]/.test(rawTrim) && !hasShopId) {
      if (/^(?:\d{1,6}|[A-Za-z][A-Za-z0-9._-]{0,15})$/.test(rawTrim)) {
        tableNumber = rawTrim;
      }
    }
  }
  const shopId = extractShopIdFromMerged(merged);
  return { tableNumber: tableNumber || "", shopId, merged };
}
