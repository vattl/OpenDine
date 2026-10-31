/**
 * 门店支付能力（GET /config/payment-capabilities）
 * v1.2.111：订单详情推荐传 order_no，按下单门店解析（忽略当前 X-Shop-Id）
 */
import { requestUtil } from "./requestUtil.js";
import { getCurrentShopId } from "./shopContext.js";
import {
  normalizeWechatPrepayNinefoldConfig,
  invalidateWechatPrepayNinefoldCache,
} from "./wechatPrepayNinefold.js";

export const PAYMENT_ONLINE_DISABLED_CODE = 40201;
export const PAYMENT_CHANNEL_DISABLED_CODE = 40202;
/** 未配置或未就绪微信商户（v1.2.105+） */
export const PAYMENT_WECHAT_MERCHANT_MISSING_CODE = 40203;
export const DEFAULT_PAYMENT_DISABLED_MESSAGE = "请联系服务员结账";

const CACHE_TTL_MS = 60 * 1000;
/** @type {Map<string, { at: number, caps: object }>} */
const cacheByKey = new Map();

function pickStr(obj, keys) {
  if (!obj || typeof obj !== "object") return "";
  for (let i = 0; i < keys.length; i++) {
    const v = obj[keys[i]];
    if (v != null && String(v).trim() !== "") return String(v).trim();
  }
  return "";
}

function pickBool(obj, keys) {
  if (!obj || typeof obj !== "object") return false;
  for (let i = 0; i < keys.length; i++) {
    const v = obj[keys[i]];
    if (v === true || v === 1 || v === "1" || v === "true") return true;
    if (v === false || v === 0 || v === "0" || v === "false") return false;
  }
  return false;
}

function pickBoolOrDefault(obj, keys, defaultVal) {
  if (!obj || typeof obj !== "object") return defaultVal;
  for (let i = 0; i < keys.length; i++) {
    const v = obj[keys[i]];
    if (v === true || v === 1 || v === "1" || v === "true") return true;
    if (v === false || v === 0 || v === "0" || v === "false") return false;
  }
  return defaultVal;
}

function normalizeChannel(ch) {
  if (!ch || typeof ch !== "object") return { enabled: false };
  return {
    enabled: pickBool(ch, ["enabled"]) || ch.enabled === 1,
    disabledMessage: pickStr(ch, ["disabledMessage", "disabled_message"]),
  };
}

function normalizeChannelState(state) {
  if (!state || typeof state !== "object") return null;
  return {
    enabled: pickBool(state, ["enabled"]),
    available: pickBoolOrDefault(state, ["available"], false),
    hint: pickStr(state, ["hint", "message"]),
  };
}

function normalizeMiniProgramClient(mp) {
  if (!mp || typeof mp !== "object") return null;
  const enabled = pickBool(mp, ["enabled"]);

  const channelsRaw =
    mp.channels && typeof mp.channels === "object" ? mp.channels : {};
  const channels = {
    wechat: pickBool(channelsRaw, ["wechat"]),
    balance: pickBool(channelsRaw, ["balance"]),
    alipay: pickBool(channelsRaw, ["alipay"]),
  };

  const csRaw =
    mp.channelStates && typeof mp.channelStates === "object"
      ? mp.channelStates
      : {};
  const channelStates = {
    wechat: normalizeChannelState(csRaw.wechat),
    balance: normalizeChannelState(csRaw.balance),
    alipay: normalizeChannelState(csRaw.alipay),
  };

  const wechatMerchantReady = pickBoolOrDefault(
    mp,
    ["wechatMerchantReady", "wechat_merchant_ready"],
    true
  );

  return {
    enabled,
    channels,
    channelStates,
    wechatMerchantReady,
  };
}

function normalizeNineFoldFromCapabilities(src) {
  const nf = src.nineFold != null ? src.nineFold : src.nine_fold;
  if (!nf || typeof nf !== "object") return null;
  if (nf.code !== undefined) return normalizeWechatPrepayNinefoldConfig(nf);
  return normalizeWechatPrepayNinefoldConfig({ code: 0, ...nf });
}

function resolveCapabilitiesCacheKey(opts = {}) {
  const orderNo = pickStr(opts, ["orderNo", "order_no"]);
  if (orderNo) return `order:${orderNo}`;
  const shopId = Number(getCurrentShopId());
  const sid = Number.isFinite(shopId) && shopId > 0 ? shopId : 0;
  return `shop:${sid}`;
}

/**
 * OpenAPI v1.2.233 (D017) 精简契约：
 * C 端 /config/payment-capabilities 只返回可用性直接相关字段
 * @returns {null|{
 *   onlinePayEnabled: boolean,
 *   disabledMessage: string,
 *   resolvedShopId: number|null,
 *   wechatMerchantReady: boolean,
 *   channels: { wechat, alipay, balance, offlineCollect },
 *   clients: { miniProgram: ReturnType<typeof normalizeMiniProgramClient> },
 *   miniProgram: ReturnType<typeof normalizeMiniProgramClient>,
 *   nineFold: ReturnType<typeof normalizeWechatPrepayNinefoldConfig>
 * }}
 */
export function normalizePaymentCapabilities(raw) {
  if (!raw || typeof raw !== "object") return null;
  if (raw.code !== undefined && raw.code !== 0) return null;

  const src =
    raw.data != null && typeof raw.data === "object" && !Array.isArray(raw.data)
      ? raw.data
      : raw;

  const clientsRaw =
    src.clients && typeof src.clients === "object" ? src.clients : {};
  const miniProgram = normalizeMiniProgramClient(
    clientsRaw.miniProgram || clientsRaw.mini_program
  );

  const onlinePayEnabled = miniProgram
    ? miniProgram.enabled
    : pickBool(src, ["onlinePayEnabled", "online_pay_enabled"]);

  const disabledMessage =
    pickStr(src, ["disabledMessage", "disabled_message"]) ||
    DEFAULT_PAYMENT_DISABLED_MESSAGE;

  const channelsRaw =
    src.channels && typeof src.channels === "object" ? src.channels : {};
  const channels = {
    wechat: normalizeChannel(channelsRaw.wechat),
    alipay: normalizeChannel(channelsRaw.alipay),
    balance: normalizeChannel(channelsRaw.balance),
    offlineCollect: normalizeChannel(
      channelsRaw.offlineCollect != null
        ? channelsRaw.offlineCollect
        : channelsRaw.offline_collect
    ),
  };

  const wechatMerchantReady = miniProgram
    ? miniProgram.wechatMerchantReady
    : pickBoolOrDefault(
        src,
        ["wechatMerchantReady", "wechat_merchant_ready"],
        true
      );

  const shopRaw = src.shopId != null ? src.shopId : src.shop_id;
  const shopNum = Number(shopRaw);
  const resolvedShopId =
    shopRaw != null && shopRaw !== "" && Number.isFinite(shopNum) && shopNum >= 0
      ? shopNum
      : null;

  return {
    onlinePayEnabled,
    disabledMessage,
    resolvedShopId,
    wechatMerchantReady,
    channels,
    clients: {
      miniProgram,
    },
    miniProgram,
    nineFold: normalizeNineFoldFromCapabilities(src),
  };
}

export function invalidatePaymentCapabilitiesCache() {
  cacheByKey.clear();
  invalidateWechatPrepayNinefoldCache();
}

export function getCachedPaymentCapabilities(opts = {}) {
  const key = resolveCapabilitiesCacheKey(opts);
  const hit = cacheByKey.get(key);
  return hit ? hit.caps : null;
}

/**
 * @param {{ force?: boolean, orderNo?: string, order_no?: string }} [opts]
 */
export async function fetchPaymentCapabilities(opts = {}) {
  const force = opts.force === true;
  const orderNo = pickStr(opts, ["orderNo", "order_no"]);
  const cacheKey = resolveCapabilitiesCacheKey(opts);
  const now = Date.now();
  const cached = cacheByKey.get(cacheKey);
  if (!force && cached && cached.caps && now - cached.at < CACHE_TTL_MS) {
    return cached.caps;
  }

  /** @type {Record<string, string>} */
  const query = {};
  if (orderNo) {
    query.order_no = orderNo;
  }

  try {
    const res = await requestUtil({
      url: "/config/payment-capabilities",
      method: "get",
      data: Object.keys(query).length ? query : undefined,
      showLoading: false,
    });
    const caps = normalizePaymentCapabilities(res);
    if (caps) {
      cacheByKey.set(cacheKey, { at: now, caps });
      return caps;
    }
  } catch (e) {
    /* ignore */
  }
  return cached && cached.caps ? cached.caps : null;
}

export function isOnlinePayEnabled(caps) {
  if (!caps) return false;
  const mp = (caps.clients && caps.clients.miniProgram) || caps.miniProgram;
  if (mp && mp.enabled !== undefined) {
    return !!mp.enabled;
  }
  return !!caps.onlinePayEnabled;
}

export function isWechatPayAvailable(caps) {
  if (!caps) return false;
  if (!isOnlinePayEnabled(caps)) return false;

  const mp = (caps.clients && caps.clients.miniProgram) || caps.miniProgram;
  if (mp) {
    // D017 核心契约：付款前可用性统一按 channelStates.<渠道>.available 判断
    if (mp.channelStates && mp.channelStates.wechat) {
      const ws = mp.channelStates.wechat;
      return !!(ws.enabled && ws.available);
    }
    // 兼容回退检查 channels 与 wechatMerchantReady
    if (mp.channels && mp.channels.wechat !== undefined) {
      if (mp.wechatMerchantReady === false) return false;
      return !!mp.channels.wechat;
    }
  }

  // 兼容旧版顶层字段
  if (caps.wechatMerchantReady === false) return false;
  return !!(caps.channels && caps.channels.wechat && caps.channels.wechat.enabled);
}

export function resolveWechatPayDisabledMessage(caps) {
  if (!caps) return DEFAULT_PAYMENT_DISABLED_MESSAGE;
  const mp = (caps.clients && caps.clients.miniProgram) || caps.miniProgram;
  if (mp) {
    const ws = mp.channelStates && mp.channelStates.wechat;
    if (ws && ws.hint) return ws.hint;
  }
  const wx = caps.channels && caps.channels.wechat;
  const fromWx = wx && wx.disabledMessage;
  if (fromWx) return fromWx;
  if (!isOnlinePayEnabled(caps) && caps.disabledMessage) {
    return caps.disabledMessage;
  }
  if (caps.disabledMessage) return caps.disabledMessage;
  return DEFAULT_PAYMENT_DISABLED_MESSAGE;
}

export function isBalanceChannelEnabled(caps) {
  if (!caps) return false;
  if (!isOnlinePayEnabled(caps)) return false;

  const mp = (caps.clients && caps.clients.miniProgram) || caps.miniProgram;
  if (mp) {
    // D017 核心契约：付款前可用性统一按 channelStates.<渠道>.available 判断
    if (mp.channelStates && mp.channelStates.balance) {
      const bs = mp.channelStates.balance;
      return !!(bs.enabled && bs.available);
    }
    // 兼容回退检查 channels
    if (mp.channels && mp.channels.balance !== undefined) {
      return !!mp.channels.balance;
    }
  }

  // 兼容旧版顶层字段
  return !!(caps.channels && caps.channels.balance && caps.channels.balance.enabled);
}

export function isAlipayChannelEnabled(caps) {
  if (!caps) return false;
  if (!isOnlinePayEnabled(caps)) return false;

  const mp = (caps.clients && caps.clients.miniProgram) || caps.miniProgram;
  if (mp) {
    if (mp.channelStates && mp.channelStates.alipay) {
      const as = mp.channelStates.alipay;
      return !!(as.enabled && as.available);
    }
    if (mp.channels && mp.channels.alipay !== undefined) {
      return !!mp.channels.alipay;
    }
  }
  return false;
}

export function isOfflineCollectAvailable(caps) {
  return !!(caps && caps.channels && caps.channels.offlineCollect.enabled);
}

export function hasAnyOnlineCheckoutChannel(caps) {
  return (
    isWechatPayAvailable(caps) ||
    isBalanceChannelEnabled(caps) ||
    isAlipayChannelEnabled(caps)
  );
}

export function resolvePaymentApiErrorMessage(res, caps) {
  const code = Number(res && res.code);
  const fromRes = pickStr(res || {}, ["msg", "message", "disabled_message", "disabledMessage"]);
  if (
    code === PAYMENT_ONLINE_DISABLED_CODE ||
    code === PAYMENT_CHANNEL_DISABLED_CODE ||
    code === PAYMENT_WECHAT_MERCHANT_MISSING_CODE
  ) {
    if (fromRes) return fromRes;
    if (
      (code === PAYMENT_CHANNEL_DISABLED_CODE ||
        code === PAYMENT_WECHAT_MERCHANT_MISSING_CODE) &&
      caps
    ) {
      const wxMsg = resolveWechatPayDisabledMessage(caps);
      if (wxMsg) return wxMsg;
    }
    return (caps && caps.disabledMessage) || DEFAULT_PAYMENT_DISABLED_MESSAGE;
  }
  return fromRes;
}

/**
 * POST /pay/offline-collect/temp-qrcode
 * @param {{ channel?: 'wechat'|'alipay', shopId?: number }} [opts]
 */
export async function fetchOfflineCollectTempQrcode(opts = {}) {
  const channel =
    opts && (opts.channel === "alipay" || opts.channel === "wechat")
      ? opts.channel
      : "wechat";
  const data = { channel };
  const sid = Number(opts && opts.shopId);
  if (Number.isFinite(sid) && sid > 0) {
    data.shop_id = sid;
  }

  const res = await requestUtil({
    url: "/pay/offline-collect/temp-qrcode",
    method: "post",
    data,
    showLoading: true,
  });
  if (!res || res.code !== 0) return res;
  const b64 = res.qrImageBase64 || res.qr_image_base64;
  if (b64) {
    const raw = String(b64).trim();
    const qrImageDataUrl = raw.startsWith("data:") ? raw : `data:image/png;base64,${raw}`;
    return { ...res, qrImageDataUrl };
  }
  return res;
}

const paymentCapabilities = {
  PAYMENT_ONLINE_DISABLED_CODE,
  PAYMENT_CHANNEL_DISABLED_CODE,
  PAYMENT_WECHAT_MERCHANT_MISSING_CODE,
  DEFAULT_PAYMENT_DISABLED_MESSAGE,
  normalizePaymentCapabilities,
  invalidatePaymentCapabilitiesCache,
  getCachedPaymentCapabilities,
  fetchPaymentCapabilities,
  isOnlinePayEnabled,
  isWechatPayAvailable,
  resolveWechatPayDisabledMessage,
  isBalanceChannelEnabled,
  isAlipayChannelEnabled,
  isOfflineCollectAvailable,
  hasAnyOnlineCheckoutChannel,
  resolvePaymentApiErrorMessage,
  fetchOfflineCollectTempQrcode,
};

export default paymentCapabilities;
