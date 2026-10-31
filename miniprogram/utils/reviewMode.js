/** 审核态下唯一允许停留的页面（排队/预约取号） */
export const QUEUE_TICKET_PAGE = "/packageOther/queue-ticket/queue-ticket";

/**
 * 解析 POST /order/Business 返回的审核开关（兼容 isReview / IsReview / 字符串 / 数字）
 * @param {*} value
 * @returns {boolean}
 */
export function isReviewFlagTruthy(value) {
  if (value === true || value === 1) return true;
  if (typeof value === "string") {
    const s = value.trim().toLowerCase();
    return s === "true" || s === "1" || s === "yes" || s === "真";
  }
  return false;
}

/**
 * @param {object|null|undefined} res Business 接口响应体
 * @returns {boolean}
 */
export function parseReviewFromBusinessResponse(res) {
  if (!res || typeof res !== "object") return false;
  const data = res.data && typeof res.data === "object" ? res.data : null;
  const candidates = [
    res.isReview,
    res.IsReview,
    res.is_review,
    res.ordering_review,
    data && data.isReview,
    data && data.IsReview,
    data && data.is_review,
    data && data.ordering_review,
  ];
  return candidates.some((v) => isReviewFlagTruthy(v));
}

/**
 * @param {object|null|undefined} res Business 接口响应体
 * @returns {boolean}
 */
export function parseWxzfFromBusinessResponse(res) {
  if (!res || typeof res !== "object") return false;
  const data = res.data && typeof res.data === "object" ? res.data : null;
  const candidates = [
    res.Wxzf,
    res.wxzf,
    res.wxZf,
    res.wx_zf,
    data && data.Wxzf,
    data && data.wxzf,
    data && data.wxZf,
    data && data.wx_zf,
  ];
  return candidates.some((v) => isReviewFlagTruthy(v));
}

export function isQueueTicketRoute(route) {
  const r = String(route || "").replace(/^\//, "");
  return r === "packageOther/queue-ticket/queue-ticket";
}
