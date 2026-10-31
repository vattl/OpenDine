/**
 * 优惠券本地规则（与连锁核销一致：门店 / 菜品范围 / 用餐方式 / 门槛）
 */

import { cartHasComboLines, COMBO_PAYMENT_RESTRICT_MSG } from "./comboMeal.js";

/** 订单是否允许使用优惠券（含套餐则不允许，与余额支付规则一致） */
export function orderAllowsCoupon(ctx) {
  const { shoppingCart } = normalizeLocalOrderRulesCtx(ctx);
  return !cartHasComboLines(shoppingCart);
}

export function parseCouponTime(value, fallback = NaN) {
  if (value == null || value === "") return fallback;
  // 兼容秒/毫秒时间戳（number 或纯数字字符串）
  const raw = String(value).trim();
  if (/^\d{10,13}$/.test(raw)) {
    const n = Number(raw);
    if (Number.isFinite(n)) {
      const ms = raw.length === 10 ? n * 1000 : n;
      return ms;
    }
  }
  const t =
    typeof value === "string"
      ? new Date(value.replace(/-/g, "/")).getTime()
      : new Date(value).getTime();
  return Number.isFinite(t) ? t : fallback;
}

function getCouponStartTime(coupon, now = Date.now()) {
  return parseCouponTime(
    coupon.start_time ??
      coupon.begin_time ??
      coupon.startTime ??
      coupon.beginTime ??
      coupon.effective_time ??
      coupon.effect_time,
    now
  );
}

function getCouponEndTime(coupon) {
  return parseCouponTime(
    coupon.expire_time ??
      coupon.end_time ??
      coupon.expireTime ??
      coupon.endTime ??
      coupon.invalid_time,
    Infinity
  );
}

export function normalizeDiningType(type) {
  const t = String(type || "").trim();
  if (!t) return "";
  if (t === "堂食" || t.toLowerCase() === "dinein" || t.toLowerCase() === "dine_in") return "堂食";
  if (t === "外卖" || t.toLowerCase() === "delivery" || t.toLowerCase() === "waimai") return "外卖";
  if (
    t === "打包" ||
    t === "外带" ||
    t.toLowerCase() === "takeaway" ||
    t.toLowerCase() === "takeout" ||
    t.toLowerCase() === "take_out"
  )
    return "打包";
  const lower = t.toLowerCase();
  if (lower === "all" || lower === "both" || t === "不限" || t === "全部") return "all";
  return t;
}

export function getCouponStatus(status) {
  const s = String(status == null ? "" : status)
    .trim()
    .toLowerCase();
  if (s === "0" || s === "usable") return "usable";
  if (s === "1" || s === "used") return "used";
  if (s === "2" || s === "expired") return "expired";
  return "expired";
}

/** 解析 apply_dish_ids：JSON 数组字符串或已是数组；空/NULL 表示不限菜品 */
export function parseCouponApplyDishIds(raw) {
  if (raw == null) return null;
  if (Array.isArray(raw)) {
    const set = new Set();
    raw.forEach((x) => {
      const n = Number(x);
      if (Number.isFinite(n)) set.add(n);
    });
    return set.size ? set : null;
  }
  const s = String(raw).trim();
  if (!s) return null;
  try {
    const arr = JSON.parse(s);
    if (!Array.isArray(arr)) return null;
    const set = new Set();
    arr.forEach((x) => {
      const n = Number(x);
      if (Number.isFinite(n)) set.add(n);
    });
    return set.size ? set : null;
  } catch (e) {
    return null;
  }
}

/** 解析 apply_shop_ids：JSON 数组；空/未配置表示全部门店 */
export function parseApplyShopIds(raw) {
  if (raw == null || raw === "") return null;
  try {
    const parsed = typeof raw === "string" ? JSON.parse(raw) : raw;
    if (!Array.isArray(parsed)) return null;
    const ids = parsed.map((x) => Number(x)).filter((n) => Number.isFinite(n) && n > 0);
    return ids.length ? ids : null;
  } catch (e) {
    return null;
  }
}

export function matchesApplyShopIds(coupon, currentShopId) {
  const ids = parseApplyShopIds(coupon.apply_shop_ids);
  if (!ids || !ids.length) return true;
  const sid = Number(currentShopId);
  if (!Number.isFinite(sid) || sid <= 0) return false;
  return ids.some((id) => Number(id) === sid);
}

/**
 * 购物车中与券适用菜品重合的金额（用于门槛；不限菜品时用订单基准总额）
 */
export function getEligibleAmountForCoupon(coupon, shoppingCart) {
  const allowIds = parseCouponApplyDishIds(coupon.apply_dish_ids);
  const cart = Array.isArray(shoppingCart) ? shoppingCart : [];
  const getDishId = (item) => {
    if (!item || typeof item !== "object") return NaN;
    const raw =
      item.dish_id ??
      item.dishId ??
      item.goods_id ??
      item.goodsId ??
      item.item_id ??
      item.itemId ??
      item.id;
    const n = Number(raw);
    return Number.isFinite(n) ? n : NaN;
  };
  const lineSum = (item) => {
    if (!item) return 0;
    const direct = Number(
      item.total_price ??
        item.totalPrice ??
        item.subtotal ??
        item.amount ??
        item.line_total ??
        item.lineTotal
    );
    const unit = Number(item.unitprice ?? item.unit_price ?? item.price ?? 0);
    const qty = Number(item.quantity ?? item.qty ?? item.count ?? item.num ?? 0);
    const p = Number.isFinite(direct) && direct > 0 ? direct : unit * qty;
    return Number.isFinite(p) ? p : 0;
  };
  if (!allowIds || allowIds.size === 0) {
    return Math.round(cart.reduce((t, item) => t + lineSum(item), 0) * 100) / 100;
  }
  let sum = 0;
  cart.forEach((item) => {
    const dishId = getDishId(item);
    if (Number.isFinite(dishId) && allowIds.has(dishId)) {
      sum += lineSum(item);
    }
  });
  return Math.round(sum * 100) / 100;
}

/**
 * 与 min_amount 比较的金额：不限菜品 = orderBaseTotal；限菜品 = 适用菜品小计
 */
export function getThresholdAmountForCoupon(coupon, orderBaseTotal, shoppingCart) {
  const allowIds = parseCouponApplyDishIds(coupon.apply_dish_ids);
  const base = Math.round(Number(orderBaseTotal || 0) * 100) / 100;
  if (!allowIds || allowIds.size === 0) return base;
  return getEligibleAmountForCoupon(coupon, shoppingCart);
}

export function matchDiningType(coupon, diningType) {
  const current = normalizeDiningType(diningType);
  if (!current) return true;
  const raw =
    coupon.dineInOrTakeOut ??
    coupon.dine_in_or_take_out ??
    coupon.dining_type ??
    coupon.use_scene ??
    coupon.apply_dining_type ??
    coupon.apply_dining_types;
  if (raw == null || String(raw).trim() === "") return true;
  const text = String(raw).trim();
  let candidates = [];
  if (text.startsWith("[")) {
    try {
      const arr = JSON.parse(text);
      if (Array.isArray(arr)) candidates = arr.map((x) => normalizeDiningType(x));
    } catch (e) {
      /* ignore */
    }
  }
  if (!candidates.length) {
    candidates = text
      .split(/[,\|\/、\s]+/)
      .map((x) => normalizeDiningType(x))
      .filter(Boolean);
  }
  if (!candidates.length) return true;
  if (candidates.includes("all")) return true;
  if (current === "外卖" && candidates.includes("打包")) return true;
  return candidates.includes(current);
}

/**
 * 接口列表规范化（兼容 data / list / coupons）
 */
export function normalizeCouponListPayload(res) {
  const d = res && res.data;
  if (Array.isArray(d)) return d;
  if (d && Array.isArray(d.list)) return d.list;
  if (d && Array.isArray(d.coupons)) return d.coupons;
  if (d && Array.isArray(d.records)) return d.records;
  const l = res && res.list;
  if (Array.isArray(l)) return l;
  return [];
}

/**
 * 跳转优惠券列表页的完整 path+query（confirm / details 共用 discount、dineInOrTakeOut 规则，仅 `from` 区分入口）。
 * 金额两位小数、参数一律 encodeURIComponent，与 coupon-list onLoad 解析一致。
 *
 * @param {'confirm'|'details'|string} fromPage
 * @param {{ orderBaseTotal?: number, dineInOrTakeOut?: string }} params
 */
export function buildCouponListNavigateUrl(fromPage, params = {}) {
  const from = String(fromPage || "confirm").trim() || "confirm";
  const orderBaseTotal = Math.round(Number(params.orderBaseTotal ?? 0) * 100) / 100;
  const dineInOrTakeOut =
    params.dineInOrTakeOut != null && String(params.dineInOrTakeOut).trim() !== ""
      ? String(params.dineInOrTakeOut).trim()
      : "堂食";
  const qs = [
    `from=${encodeURIComponent(from)}`,
    // orderBaseTotal 为新字段；保留 discount 兼容旧版本页面解析
    `orderBaseTotal=${encodeURIComponent(String(orderBaseTotal))}`,
    `discount=${encodeURIComponent(String(orderBaseTotal))}`,
    `dineInOrTakeOut=${encodeURIComponent(dineInOrTakeOut)}`,
  ].join("&");
  return `/packageOther/coupon-list/coupon-list?${qs}`;
}

/**
 * 规范化「本地订单规则」上下文，confirm / details / coupon-list 传入字段一致，避免同参不同果。
 * @param {object} ctx
 * @param {number|string} ctx.orderBaseTotal 订单基准额（与 confirm：商品+打包；与 details：couponOrderBaseTotal）
 * @param {Array} ctx.shoppingCart 购物车行或订单 goods_data
 * @param {string} [ctx.dineInOrTakeOut]
 * @param {number|string} [ctx.currentShopId]
 */
export function normalizeLocalOrderRulesCtx(ctx) {
  if (!ctx || typeof ctx !== "object") {
    return {
      orderBaseTotal: 0,
      shoppingCart: [],
      dineInOrTakeOut: "堂食",
      currentShopId: undefined,
    };
  }
  return {
    orderBaseTotal: Math.round(Number(ctx.orderBaseTotal ?? 0) * 100) / 100,
    shoppingCart: Array.isArray(ctx.shoppingCart) ? ctx.shoppingCart : [],
    dineInOrTakeOut: ctx.dineInOrTakeOut || "堂食",
    currentShopId: ctx.currentShopId,
  };
}

/**
 * 组装统一的订单优惠券规则上下文，并生成 coupon-list 跳转 URL。
 * 供 confirm-order / order-details 复用，避免各页面重复拼装参数。
 *
 * @param {'confirm'|'details'|string} fromPage
 * @param {object} payload
 * @param {number|string} payload.orderBaseTotal
 * @param {Array} payload.orderLines
 * @param {string} [payload.dineInOrTakeOut]
 * @param {number|string} [payload.currentShopId]
 */
export function buildCouponOrderSelectionPayload(fromPage, payload = {}) {
  const ctx = normalizeLocalOrderRulesCtx({
    orderBaseTotal: payload.orderBaseTotal,
    shoppingCart: payload.orderLines,
    dineInOrTakeOut: payload.dineInOrTakeOut,
    currentShopId: payload.currentShopId,
  });
  return {
    ctx,
    navigateUrl: buildCouponListNavigateUrl(fromPage, {
      orderBaseTotal: ctx.orderBaseTotal,
      dineInOrTakeOut: ctx.dineInOrTakeOut,
    }),
    orderLines: ctx.shoppingCart,
  };
}

/**
 * 仅适用于 POST /coupon/getUserAvailableCoupons 返回列表后的本地二次筛选：
 * 门店、有效期、用餐方式、金额门槛（含限菜品时的小计）等。
 *
 * GET/POST /coupon/getUserCoupons 场景勿用本函数做金额/门槛判断（仅展示态列表）。
 *
 * @param {object} coupon
 * @param {object} ctx 会先经 normalizeLocalOrderRulesCtx
 */
export function couponPassesLocalOrderRules(coupon, ctx) {
  const { orderBaseTotal, shoppingCart, dineInOrTakeOut, currentShopId } = normalizeLocalOrderRulesCtx(ctx);
  if (!orderAllowsCoupon(ctx)) return false;
  if (!coupon || typeof coupon !== "object") return false;
  if (getCouponStatus(coupon.status) !== "usable") return false;
  if (!matchesApplyShopIds(coupon, currentShopId)) return false;

  const now = Date.now();
  const endTime = getCouponEndTime(coupon);
  const startTime = getCouponStartTime(coupon, now);
  if (now > endTime || now < startTime) return false;
  if (!matchDiningType(coupon, dineInOrTakeOut)) return false;

  const threshold = getThresholdAmountForCoupon(coupon, orderBaseTotal, shoppingCart);
  const minAmount = Number(coupon.min_amount) || 0;
  if (threshold < minAmount) return false;

  return true;
}

/** @deprecated 请使用 couponPassesLocalOrderRules */
export const isCouponUsableForConfirm = couponPassesLocalOrderRules;

/**
 * 与 couponPassesLocalOrderRules 一致，对整张列表计数（用于确认页/订单详情角标等）。
 */
export function countCouponsPassingLocalOrderRules(list, ctx) {
  const arr = Array.isArray(list) ? list : [];
  return arr.filter((c) => couponPassesLocalOrderRules(c, ctx)).length;
}

/** @deprecated 请使用 countCouponsPassingLocalOrderRules */
export const countCouponsUsableForConfirm = countCouponsPassingLocalOrderRules;

export function calculateCouponDiscount(coupon, ctx) {
  const { orderBaseTotal, shoppingCart } = normalizeLocalOrderRulesCtx(ctx);
  if (!orderAllowsCoupon(ctx)) return 0;
  if (!coupon || typeof coupon !== "object") return 0;

  const eligible = getThresholdAmountForCoupon(coupon, orderBaseTotal, shoppingCart);
  if (!Number.isFinite(eligible) || eligible <= 0) return 0;

  const minAmount = Number(coupon.min_amount) || 0;
  if (eligible < minAmount) return 0;

  const discountValue = Number(coupon.discount_value) || 0;
  switch (coupon.coupon_type) {
    case "discount": {
      const afterDiscount = Math.round(eligible * (discountValue / 100) * 100) / 100;
      const discountAmount = Math.round((eligible - afterDiscount) * 100) / 100;
      return Math.max(0, Math.min(eligible, discountAmount));
    }
    case "full_reduction":
    case "direct_reduction":
      return Math.max(0, Math.min(eligible, discountValue));
    default:
      return 0;
  }
}

/** 订单详情进优惠券列表前写入的订单行（与购物车结构一致，供门槛计算） */
export const MP_COUPON_ORDER_LINES_FOR_LIST_KEY = "mp_coupon_order_lines_for_list_v1";

/**
 * 与 couponPassesLocalOrderRules 判定顺序一致；返回不可用时的人类可读原因，可用则 null
 */
export function explainCouponUnusable(coupon, ctx) {
  const { orderBaseTotal, shoppingCart, dineInOrTakeOut, currentShopId } =
    normalizeLocalOrderRulesCtx(ctx);
  if (!orderAllowsCoupon(ctx)) return COMBO_PAYMENT_RESTRICT_MSG;
  if (!coupon || typeof coupon !== "object") return "优惠券数据异常";
  const st = getCouponStatus(coupon.status);
  if (st === "used") return "优惠券已使用";
  if (st !== "usable") return "优惠券不可用或已失效";

  if (!matchesApplyShopIds(coupon, currentShopId)) return "不适用当前门店";

  const now = Date.now();
  const endTime = getCouponEndTime(coupon);
  const startTime = getCouponStartTime(coupon, now);
  if (now < startTime) return "优惠券尚未生效";
  if (now > endTime) return "优惠券已过期";

  if (!matchDiningType(coupon, dineInOrTakeOut)) return "用餐方式不符合优惠券适用范围";

  const threshold = getThresholdAmountForCoupon(coupon, orderBaseTotal, shoppingCart);
  const minAmount = Number(coupon.min_amount) || 0;
  if (threshold < minAmount) {
    const rounded = Math.round(Number(threshold || 0) * 100) / 100;
    return `适用商品金额未满足（当前${rounded}元，需满${minAmount}元）`;
  }
  return null;
}
