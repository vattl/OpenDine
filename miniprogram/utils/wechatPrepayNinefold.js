/**
 * 夜间九折（与 GET /config/wechat-prepay-ninefold、getPrepayId / payByBalance 计算一致）
 * v1.2.112：各店独立配置；推荐订单场景传 order_no（优先于 X-Shop-Id）。
 * 叠九折须：enabled + 时段 + minBaseYuan + payRate + 订单 dineInOrTakeOut ∈ eligibleDiningTypes + 未用券。
 * 互斥：用券不可叠九折；余额支付不可叠九折（仅微信支付可享）。
 */
import { requestUtil } from "./requestUtil.js";
import { getCurrentShopId } from "./shopContext.js";

const NINEFOLD_CACHE_TTL_MS = 60 * 1000;
/** @type {Map<string, { at: number, config: object }>} */
const ninefoldCacheByKey = new Map();

function pickStr(obj, keys) {
  if (!obj || typeof obj !== "object") return "";
  for (let i = 0; i < keys.length; i++) {
    const v = obj[keys[i]];
    if (v != null && String(v).trim() !== "") return String(v).trim();
  }
  return "";
}

function parseTimeToMinutes(s) {
  const parts = String(s || "").trim().split(":");
  const h = parseInt(parts[0], 10);
  const m = parseInt(parts[1] != null ? parts[1] : "0", 10);
  const sec = parts[2] != null ? parseInt(parts[2], 10) : 0;
  const hh = Number.isFinite(h) ? h : 0;
  const mm = Number.isFinite(m) ? m : 0;
  const ss = Number.isFinite(sec) ? sec : 0;
  return hh * 60 + mm + (ss >= 30 ? 1 : 0);
}

/** 格式化后端返回的时间字符串为 HH:mm（不做默认值替换） */
export function formatBackendTimeLabel(timeStr) {
  const str = String(timeStr || "").trim();
  if (!str) return "";
  const parts = str.split(":");
  if (parts.length >= 2) {
    const h = String(parseInt(parts[0], 10) || 0).padStart(2, "0");
    const m = String(parseInt(parts[1], 10) || 0).padStart(2, "0");
    return `${h}:${m}`;
  }
  return str.length >= 5 ? str.slice(0, 5) : str;
}

function parseDiningTypeList(raw) {
  if (Array.isArray(raw)) {
    return raw.map((x) => String(x || "").trim()).filter(Boolean);
  }
  if (typeof raw === "string" && raw.trim()) {
    try {
      const parsed = JSON.parse(raw);
      if (Array.isArray(parsed)) {
        return parsed.map((x) => String(x || "").trim()).filter(Boolean);
      }
    } catch (e) {
      /* ignore */
    }
  }
  return [];
}

/** 从配置响应解析适用就餐方式（默认与后端一致：["堂食"]） */
export function normalizeEligibleDiningTypes(src) {
  if (!src || typeof src !== "object") return ["堂食"];
  const list = parseDiningTypeList(
    src.eligibleDiningTypes != null ? src.eligibleDiningTypes : src.eligible_dining_types
  );
  return list.length ? list : ["堂食"];
}

/**
 * 归一化 GET /config/wechat-prepay-ninefold 响应（字段均来自服务端）
 * @returns {null|{
 *   enabled: boolean,
 *   payRate: number,
 *   minBaseYuan: number,
 *   timeStart: string,
 *   timeEnd: string,
 *   zoneId: string,
 *   inWindow: boolean|null,
 *   eligibleDiningTypes: string[],
 *   supportedDiningTypes: string[],
 *   dineInOnly: boolean
 * }}
 */
export function normalizeWechatPrepayNinefoldConfig(raw) {
  if (!raw || typeof raw !== "object") return null;
  if (raw.code !== undefined && raw.code !== 0) return null;

  const src =
    raw.data != null && typeof raw.data === "object" && !Array.isArray(raw.data)
      ? raw.data
      : raw;

  const enabled = src.enabled === true || src.enabled === 1;
  const payRateRaw = pickStr(src, ["payRate", "pay_rate"]);
  const payRate = payRateRaw !== "" ? Number(payRateRaw) : NaN;
  const minBaseRaw = pickStr(src, ["minBaseYuan", "min_base_yuan"]);
  const minBaseYuan = minBaseRaw !== "" ? Number(minBaseRaw) : 0;
  const timeStart = pickStr(src, ["timeStart", "time_start"]);
  const timeEnd = pickStr(src, ["timeEnd", "time_end"]);
  const zoneId = pickStr(src, ["zoneId", "zone_id"]);

  let inWindow = null;
  if (src.inWindow === true || src.in_window === true || src.inNightWindow === true) {
    inWindow = true;
  } else if (src.inWindow === false || src.in_window === false || src.inNightWindow === false) {
    inWindow = false;
  }

  const eligibleDiningTypes = normalizeEligibleDiningTypes(src);
  const supportedDiningTypes = parseDiningTypeList(
    src.supportedDiningTypes != null ? src.supportedDiningTypes : src.supported_dining_types
  );
  const dineInOnly =
    src.dineInOnly === true ||
    src.dine_in_only === true ||
    (eligibleDiningTypes.length === 1 && eligibleDiningTypes[0] === "堂食");

  return {
    enabled,
    payRate,
    minBaseYuan: Number.isFinite(minBaseYuan) ? minBaseYuan : 0,
    timeStart,
    timeEnd,
    zoneId,
    inWindow,
    eligibleDiningTypes,
    supportedDiningTypes,
    dineInOnly,
  };
}

function resolveNinefoldCacheKey(opts = {}) {
  const orderNo = pickStr(opts, ["orderNo", "order_no"]);
  if (orderNo) return `order:${orderNo}`;
  const shopId = opts.shopId != null ? opts.shopId : opts.shop_id;
  const sid =
    shopId != null && shopId !== ""
      ? Number(shopId)
      : Number(getCurrentShopId());
  const n = Number.isFinite(sid) && sid >= 0 ? sid : 0;
  return `shop:${n}`;
}

export function invalidateWechatPrepayNinefoldCache() {
  ninefoldCacheByKey.clear();
}

/**
 * GET /config/wechat-prepay-ninefold（按 order_no 或 shop_id 解析门店）
 * @param {{ force?: boolean, orderNo?: string, order_no?: string, shopId?: number|string, shop_id?: number|string }} [opts]
 */
export async function fetchWechatPrepayNinefoldConfig(opts = {}) {
  const force = opts.force === true;
  const orderNo = pickStr(opts, ["orderNo", "order_no"]);
  const cacheKey = resolveNinefoldCacheKey(opts);
  const now = Date.now();
  const cached = ninefoldCacheByKey.get(cacheKey);
  if (!force && cached && cached.config && now - cached.at < NINEFOLD_CACHE_TTL_MS) {
    return cached.config;
  }

  /** @type {Record<string, string>} */
  const query = {};
  if (orderNo) {
    query.order_no = orderNo;
  } else {
    const shopId = opts.shopId != null ? opts.shopId : opts.shop_id;
    const sid = Number(shopId);
    if (Number.isFinite(sid) && sid > 0) {
      query.shop_id = String(sid);
    }
  }

  try {
    const res = await requestUtil({
      url: "/config/wechat-prepay-ninefold",
      method: "get",
      data: Object.keys(query).length ? query : undefined,
      showLoading: false,
    });
    const config = normalizeWechatPrepayNinefoldConfig(res);
    if (config) {
      ninefoldCacheByKey.set(cacheKey, { at: now, config });
      return config;
    }
  } catch (e) {
    /* ignore */
  }
  return cached && cached.config ? cached.config : null;
}

function useChinaWallClock(zoneId) {
  const z = zoneId != null ? String(zoneId) : "";
  return (
    !z ||
    z.indexOf("Shanghai") !== -1 ||
    z.indexOf("Chongqing") !== -1 ||
    z.indexOf("Hong_Kong") !== -1
  );
}

/** 指定时刻在配置时区下的墙钟分钟数（0–1439）；zoneId 来自后端 */
export function getWallClockMinutes(atDate, zoneId) {
  const d = atDate instanceof Date && !isNaN(atDate.getTime()) ? atDate : new Date();
  if (useChinaWallClock(zoneId)) {
    const utcMs = d.getTime() + d.getTimezoneOffset() * 60000;
    const china = new Date(utcMs + 8 * 3600000);
    return china.getHours() * 60 + china.getMinutes();
  }
  return d.getHours() * 60 + d.getMinutes();
}

/** 是否落在后端配置的 timeStart–timeEnd 内（跨天由两端时间大小推断） */
export function isInNightWindowAt(timeStart, timeEnd, zoneId, atDate) {
  const startStr = timeStart != null ? String(timeStart).trim() : "";
  const endStr = timeEnd != null ? String(timeEnd).trim() : "";
  if (!startStr || !endStr) return false;

  const startMin = parseTimeToMinutes(startStr);
  const endMin = parseTimeToMinutes(endStr);
  const nowMin = getWallClockMinutes(atDate, zoneId);

  if (startMin <= endMin) {
    return nowMin >= startMin && nowMin <= endMin;
  }
  return nowMin >= startMin || nowMin <= endMin;
}

export function isNowInNightWindow(timeStart, timeEnd, zoneId) {
  return isInNightWindowAt(timeStart, timeEnd, zoneId, new Date());
}

/** 展示用时段文案：完全由后端 timeStart/timeEnd 组成 */
export function formatNightNinefoldTimeRange(timeStart, timeEnd) {
  const s = formatBackendTimeLabel(timeStart);
  const e = formatBackendTimeLabel(timeEnd);
  if (!s || !e) return "";
  const startMin = parseTimeToMinutes(timeStart);
  const endMin = parseTimeToMinutes(timeEnd);
  if (startMin > endMin) {
    return `${s}–次日${e}`;
  }
  return `${s}–${e}`;
}

export function hasBackendNightTimeRange(cfg) {
  if (!cfg) return false;
  return !!(String(cfg.timeStart || "").trim() && String(cfg.timeEnd || "").trim());
}

export function isNightNinefoldConfigEnabled(cfg) {
  if (!cfg || cfg.enabled !== true) return false;
  const payRate = Number(cfg.payRate);
  if (!Number.isFinite(payRate) || payRate <= 0 || payRate >= 1) return false;
  return hasBackendNightTimeRange(cfg);
}

/** 订单就餐方式是否落在配置的 eligibleDiningTypes 内 */
export function isNightNinefoldEligibleDiningType(dineInOrTakeOut, config) {
  const mode = String(dineInOrTakeOut || "").trim();
  if (!mode) return false;
  const eligible =
    config && Array.isArray(config.eligibleDiningTypes) && config.eligibleDiningTypes.length
      ? config.eligibleDiningTypes
      : ["堂食"];
  return eligible.some((t) => String(t || "").trim() === mode);
}

/** 展示用：适用就餐方式文案，如「堂食订单」「堂食、打包订单」 */
export function formatNightNinefoldEligibleDiningText(config) {
  const eligible =
    config && Array.isArray(config.eligibleDiningTypes) && config.eligibleDiningTypes.length
      ? config.eligibleDiningTypes
      : ["堂食"];
  if (config && config.dineInOnly) return "仅堂食订单";
  if (eligible.length === 1) return `${eligible[0]}订单`;
  return `${eligible.join("、")}订单`;
}

/** 当前是否在优惠时段：优先后端 inWindow，否则按后端 timeStart/timeEnd/zoneId 计算 */
export function isNightNinefoldInWindowNow(cfg) {
  if (!cfg || !hasBackendNightTimeRange(cfg)) return false;
  if (cfg.inWindow === true) return true;
  if (cfg.inWindow === false) return false;
  return isNowInNightWindow(cfg.timeStart, cfg.timeEnd, cfg.zoneId);
}

/** 将 payRate（如 0.9）格式化为中文「九折」类文案 */
export function formatNightNinefoldZheLabel(payRate) {
  const r = Number(payRate);
  if (!Number.isFinite(r) || r >= 1 || r <= 0) return "";
  const zhe10 = Math.round(r * 100) / 10;
  const cn = ["零", "一", "二", "三", "四", "五", "六", "七", "八", "九"];
  if (zhe10 >= 1 && zhe10 <= 9 && Math.abs(zhe10 - Math.round(zhe10)) < 1e-6) {
    return `${cn[Math.round(zhe10)]}折`;
  }
  return `${zhe10}折`;
}

export function computeNightNinefoldBaseYuan(settAmount, serviceFee) {
  const sett = Number(settAmount || 0);
  const sf = Number(serviceFee || 0);
  return Math.round((sett + sf) * 100) / 100;
}

export function computeNightNinefoldDiscountYuan(baseYuan, payRate) {
  const base = Number(baseYuan || 0);
  const r = Number(payRate);
  if (!Number.isFinite(base) || base <= 0 || !Number.isFinite(r) || r <= 0 || r >= 1) return 0;
  return Math.round(base * (1 - r) * 100) / 100;
}

function parseOrderMoment(order) {
  const o = order || {};
  const raw =
    o.pay_time ||
    o.payTime ||
    o.off_time ||
    o.offTime ||
    o.order_time ||
    o.orderTime;
  if (!raw) return null;
  if (typeof raw === "string" && raw.indexOf(" ") !== -1) {
    const d = new Date(raw.replace(" ", "T"));
    return isNaN(d.getTime()) ? null : d;
  }
  const d = new Date(raw);
  return isNaN(d.getTime()) ? null : d;
}

function amountsClose(a, b, tolerance) {
  return Math.abs(Number(a) - Number(b)) <= (tolerance != null ? tolerance : 0.06);
}

/** 订单 discount_amount > 0 表示后端已写入优惠（含手动打折），未结账时不可再叠券/九折 */
export function orderHasExistingDiscountAmount(order) {
  const o = order || {};
  return Number(o.discount_amount || 0) > 0;
}

function isInNightWindowAtPayTime(cfg, atDate) {
  if (!cfg || !hasBackendNightTimeRange(cfg) || !atDate) return false;
  return isInNightWindowAt(cfg.timeStart, cfg.timeEnd, cfg.zoneId, atDate);
}

/**
 * 解析订单上的夜间九折展示（未结账=预计；已结账=已享）
 * @returns {{ amount: number, mode: 'preview'|'applied'|'none', zheLabel: string, timeRange: string, timeStart: string, timeEnd: string }}
 */
export function resolveNightNinefoldForOrder({
  order,
  config,
  orderSubtotalYuan,
  orderHasBoundCoupon,
  orderUsesCoupon,
}) {
  const empty = {
    amount: 0,
    mode: "none",
    zheLabel: "",
    timeRange: "",
    timeStart: "",
    timeEnd: "",
  };
  if (orderUsesCoupon || orderHasBoundCoupon) return empty;
  if (!isNightNinefoldConfigEnabled(config)) return empty;

  const d = order || {};
  if (!isNightNinefoldEligibleDiningType(d.dineInOrTakeOut, config)) return empty;

  const payRate = Number(config.payRate);
  const minBase = Number(config.minBaseYuan ?? 0);
  const base = Number(orderSubtotalYuan || 0);
  const zheLabel = formatNightNinefoldZheLabel(payRate);
  const timeStart = String(config.timeStart || "").trim();
  const timeEnd = String(config.timeEnd || "").trim();
  const timeRange = formatNightNinefoldTimeRange(timeStart, timeEnd);

  if (!Number.isFinite(base) || base <= 0) return empty;
  if (Number.isFinite(minBase) && base + 1e-6 < minBase) return empty;

  const expectedOff = computeNightNinefoldDiscountYuan(base, payRate);
  const status = d.transac_status;
  const da = Number(d.discount_amount || 0);

  if (status === "unsettled" && da > 0) return empty;

  if (status === "unsettled") {
    if (isNightNinefoldInWindowNow(config)) {
      return { amount: expectedOff, mode: "preview", zheLabel, timeRange, timeStart, timeEnd };
    }
    return empty;
  }

  if (status === "success" && da > 0 && amountsClose(da, expectedOff)) {
    return { amount: da, mode: "applied", zheLabel, timeRange, timeStart, timeEnd };
  }

  return empty;
}

export function buildNightNinefoldRowLabel(zheLabel, payRate) {
  const z = zheLabel || formatNightNinefoldZheLabel(payRate);
  if (z) return `夜间${z}优惠`;
  return "夜间优惠";
}

/** 说明文案：时段、折扣倍率、门槛、适用就餐方式均来自后端配置 */
export function buildNightNinefoldExplainText({
  mode,
  zheLabel,
  timeRange,
  minBaseYuan,
  payRate,
  eligibleDiningTypes,
  dineInOnly,
}) {
  const zhePart = zheLabel ? `「${zheLabel}」` : "";
  const minBase = Number(minBaseYuan ?? 0);
  const minPart =
    Number.isFinite(minBase) && minBase > 0 ? `，订单满 ${minBase} 元可用` : "";
  const rowLabel = buildNightNinefoldRowLabel(zheLabel, payRate);
  const diningText = formatNightNinefoldEligibleDiningText({
    eligibleDiningTypes,
    dineInOnly,
  });

  if (mode === "preview") {
    const timePrefix = timeRange ? `当前为 ${timeRange} 时段，` : "";
    const zheText = zhePart || "优惠";
    const diningPrefix = diningText ? `${diningText}` : "本单";
    return `${timePrefix}${diningPrefix}未使用优惠券支付预计可享${zheText}${minPart}，不可与优惠券或余额支付叠加`;
  }
  if (mode === "applied") {
    const timePrefix = timeRange ? `${timeRange} 时段` : "";
    const zheText = zhePart || "优惠";
    if (timePrefix) {
      return `本单已享受${timePrefix}${zheText}，优惠金额已计入上方「${rowLabel}」。`;
    }
    return `本单已享受夜间${zheText}，优惠金额已计入上方「${rowLabel}」。`;
  }
  return "";
}

/**
 * 费用明细优惠行展示（券与九折互斥；九折预览仅微信支付；discount_amount>0 时不再叠券/九折）
 * @returns {{
 *   couponAmount: number,
 *   ninefoldAmount: number,
 *   showCouponRow: boolean,
 *   showNinefoldRow: boolean,
 *   showExistingDiscountRow: boolean,
 *   existingDiscountAmount: number
 * }}
 */
export function resolveOrderFeeDiscountDisplay({
  transacStatus,
  paymentMethod,
  orderUsesCoupon,
  orderHasBoundCoupon,
  orderHasExistingDiscount,
  discountAmountFromOrder,
  selectedCouponDiscountYuan,
  nightNinefoldResolved,
}) {
  const da = Number(discountAmountFromOrder || 0);
  const makeExisting = (amount) => ({
    couponAmount: 0,
    ninefoldAmount: 0,
    showCouponRow: false,
    showNinefoldRow: false,
    showExistingDiscountRow: amount > 0,
    existingDiscountAmount: amount > 0 ? amount : 0,
  });
  const empty = makeExisting(0);
  const status = String(transacStatus || "").trim();
  const resolved = nightNinefoldResolved || { amount: 0, mode: "none" };
  const couponDisc = Number(selectedCouponDiscountYuan || 0);
  const usesCoupon = orderUsesCoupon === true || orderHasBoundCoupon === true;
  const payMethod = paymentMethod === "balance" ? "balance" : "wxpay";
  const ninefoldAmt = Number(resolved.amount || 0);
  const hasExisting = orderHasExistingDiscount === true || da > 0;

  if (status === "unsettled" && hasExisting) {
    return makeExisting(da);
  }

  if (usesCoupon) {
    let couponAmount = 0;
    if (status === "unsettled" && couponDisc > 0) {
      couponAmount = couponDisc;
    } else if (da > 0) {
      couponAmount = da;
    }
    if (couponAmount > 0) {
      return { ...empty, couponAmount, showCouponRow: true };
    }
    return empty;
  }

  if (resolved.mode === "applied" && ninefoldAmt > 0 && da > 0 && amountsClose(da, ninefoldAmt)) {
    return {
      couponAmount: 0,
      ninefoldAmount: ninefoldAmt,
      showCouponRow: false,
      showNinefoldRow: true,
      showExistingDiscountRow: false,
      existingDiscountAmount: 0,
    };
  }

  if (
    status === "unsettled" &&
    resolved.mode === "preview" &&
    ninefoldAmt > 0 &&
    payMethod !== "balance"
  ) {
    return {
      couponAmount: 0,
      ninefoldAmount: ninefoldAmt,
      showCouponRow: false,
      showNinefoldRow: true,
      showExistingDiscountRow: false,
      existingDiscountAmount: 0,
    };
  }

  if (da > 0) {
    return makeExisting(da);
  }

  return empty;
}
