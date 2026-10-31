/**
 * 连锁门店：当前门店 ID 写入本地后，由 requestUtil 统一在请求头携带 **X-Shop-Id**（与 openapi 一致）。
 * 业务请求体 / query 不再传 shop_id，由服务端从请求头解析。
 */
import { DISH_CACHE_KEY, DISH_CACHE_TIME_KEY } from "../config/perf.js";

const SHOP_ID_KEY = "mp_current_shop_id";
const SHOP_SNAPSHOT_KEY = "mp_current_shop_snapshot";

/** 从门店对象拼营业时间展示文案（与点餐页 applyCurrentShopInfo 口径一致，供快照与界面共用） */
export function buildShopBusinessHoursLabel(shop) {
  if (!shop || typeof shop !== "object") return "";
  const openTime = (shop.open_time || "").toString().trim();
  const closeTime = (shop.close_time || "").toString().trim();
  const rangeTime = openTime && closeTime ? `${openTime}-${closeTime}` : "";
  return (shop.business_hours || shop.businessTime || rangeTime || "").toString().trim();
}

/** 打包/外带时段；无独立字段时可回退到 open_time-close_time */
export function buildShopTakeoutHoursLabel(shop) {
  if (!shop || typeof shop !== "object") return "";
  const openTime = (shop.open_time || "").toString().trim();
  const closeTime = (shop.close_time || "").toString().trim();
  const rangeTime = openTime && closeTime ? `${openTime}-${closeTime}` : "";
  return (shop.takeout_hours || shop.takeoutTime || shop.delivery_time || rangeTime || "").toString().trim();
}

/** 用户在选店页手动选择过门店后为 true；点餐页仅在非手动时按定位自动选最近店 */
export const MENU_SHOP_MANUAL_KEY = "mp_menu_shop_manual_v1";

/** 扫码/落地页携带 shop_id 绑定门店后写入，点餐页不再强制跳转选店 */
export const MENU_SHOP_QR_BOUND_KEY = "mp_menu_shop_qr_bound_v1";

/** 扫码绑店有效期（分钟），过期后须重新选店或再次扫码 */
export const SHOP_QR_BOUND_EXPIRY_MINUTES = 60;

function resolveAppForExpiry() {
  try {
    const g = typeof getApp === "function" ? getApp() : null;
    if (
      g &&
      typeof g.setStorageWithExpiry === "function" &&
      typeof g.getStorageWithExpiry === "function"
    ) {
      return g;
    }
  } catch (e) {
    /* ignore */
  }
  return null;
}

function readQrBoundShopIdFromExpiry(app) {
  if (!app) return null;
  const cached = app.getStorageWithExpiry(MENU_SHOP_QR_BOUND_KEY);
  const n = Number(cached);
  return Number.isFinite(n) && n > 0 ? n : null;
}

/** 旧版 plain number 无 TTL，视为已过期并清除 */
function migrateLegacyQrBoundIfNeeded() {
  try {
    const raw = wx.getStorageSync(MENU_SHOP_QR_BOUND_KEY);
    if (raw == null || raw === "") return;
    if (typeof raw === "object" && raw.expiry != null) return;
    wx.removeStorageSync(MENU_SHOP_QR_BOUND_KEY);
  } catch (e) {
    /* ignore */
  }
}

export function getQrBoundShopId() {
  try {
    migrateLegacyQrBoundIfNeeded();
    const app = resolveAppForExpiry();
    const fromExpiry = readQrBoundShopIdFromExpiry(app);
    if (fromExpiry != null) return fromExpiry;
    return null;
  } catch (e) {
    return null;
  }
}

export function isShopBoundFromQr() {
  return getQrBoundShopId() != null;
}

export function clearShopQrBound() {
  try {
    wx.removeStorageSync(MENU_SHOP_QR_BOUND_KEY);
  } catch (e) {
    /* ignore */
  }
}

/**
 * 扫码绑定门店：写入当前店并标记「已绑定」（1 小时有效），避免点餐页再弹选店
 * @param {object} shop GET /shop/list 中的门店项
 */
export function markShopBoundFromQr(shop) {
  if (!shop || shop.id == null) return;
  setCurrentShop(shop);
  try {
    const app = resolveAppForExpiry();
    if (app) {
      app.setStorageWithExpiry(
        MENU_SHOP_QR_BOUND_KEY,
        Number(shop.id),
        SHOP_QR_BOUND_EXPIRY_MINUTES
      );
    } else {
      wx.setStorageSync(MENU_SHOP_QR_BOUND_KEY, Number(shop.id));
    }
  } catch (e) {
    /* ignore */
  }
}

/** 从页面 onLoad options 解析 shop_id（餐桌码落地） */
export function parseShopIdFromLaunchOptions(options) {
  if (!options || typeof options !== "object") return null;
  const raw = options.shop_id;
  if (raw == null || String(raw).trim() === "") return null;
  const n = Number(raw);
  return Number.isFinite(n) && n > 0 ? n : null;
}

/** 未选店或本地无记录时，请求头与业务默认使用的门店 ID（与点餐页加载逻辑一致） */
export const DEFAULT_SHOP_ID = 1;

export function getCurrentShopId() {
  const v = wx.getStorageSync(SHOP_ID_KEY);
  const n = Number(v);
  return Number.isFinite(n) && n > 0 ? n : DEFAULT_SHOP_ID;
}

export function getCurrentShopSnapshot() {
  try {
    const raw = wx.getStorageSync(SHOP_SNAPSHOT_KEY);
    if (!raw) return {};
    return typeof raw === "object" ? raw : JSON.parse(raw);
  } catch (e) {
    return {};
  }
}

function clearDishListCache() {
  try {
    wx.removeStorageSync(DISH_CACHE_KEY);
    wx.removeStorageSync(DISH_CACHE_TIME_KEY);
  } catch (e) {}
}

export function setCurrentShop(shop) {
  if (!shop || shop.id == null) return;
  const id = Number(shop.id);
  if (!Number.isFinite(id) || id <= 0) return;
  const prev = getCurrentShopId();
  wx.setStorageSync(SHOP_ID_KEY, id);
  try {
    const phone = (shop.contact_phone || shop.phone || shop.tel || shop.mobile || "").toString().trim();
    wx.setStorageSync(
      SHOP_SNAPSHOT_KEY,
      JSON.stringify({
        name: shop.name || "",
        address: shop.address || "",
        latitude: shop.latitude != null ? Number(shop.latitude) : null,
        longitude: shop.longitude != null ? Number(shop.longitude) : null,
        businessHours: buildShopBusinessHoursLabel(shop),
        takeoutHours: buildShopTakeoutHoursLabel(shop),
        contact_phone: phone,
      })
    );
  } catch (e) {}
  if (prev !== id) {
    clearDishListCache();
    try {
      wx.removeStorageSync('shopping_cart');
    } catch (e) {}
    try {
      const a = typeof getApp === "function" ? getApp() : null;
      if (a && a.event && typeof a.event.emit === "function") {
        a.event.emit("unified:context_changed");
      }
    } catch (e) {}
  }
}

export function clearCurrentShop() {
  try {
    wx.removeStorageSync(SHOP_ID_KEY);
    wx.removeStorageSync(SHOP_SNAPSHOT_KEY);
  } catch (e) {}
  clearDishListCache();
}

export function getShopRequestHeaders() {
  const id = getCurrentShopId();
  if (!id) return {};
  /** 与 docs/openapi 中 X-Shop-Id 一致（HTTP 头大小写不敏感） */
  return { "X-Shop-Id": String(id) };
}

export function sortShopsForDisplay(list) {
  if (!Array.isArray(list)) return [];
  return [...list].sort((a, b) => {
    const sa = Number(a.sort_order);
    const sb = Number(b.sort_order);
    const oa = Number.isFinite(sa) ? sa : 0;
    const ob = Number.isFinite(sb) ? sb : 0;
    if (oa !== ob) return oa - ob;
    return (Number(a.id) || 0) - (Number(b.id) || 0);
  });
}

export function isShopIdInList(list, shopId) {
  if (!shopId || !Array.isArray(list)) return false;
  return list.some((s) => Number(s.id) === Number(shopId));
}

/**
 * 根据 GET /shop/list 结果更新本地门店；多店且当前 ID 不在列表内时默认落到 {@link DEFAULT_SHOP_ID} 或首店
 * @returns {number} 营业门店数量
 */
export function syncLocalShopFromOpenList(list, onNeedSelect) {
  const sorted = sortShopsForDisplay(Array.isArray(list) ? list : []);
  const count = sorted.length;
  if (count === 0) {
    clearCurrentShop();
    return 0;
  }
  if (count === 1) {
    setCurrentShop(sorted[0]);
    return count;
  }
  if (!isShopIdInList(sorted, getCurrentShopId())) {
    const preferred = sorted.find((s) => Number(s.id) === DEFAULT_SHOP_ID);
    setCurrentShop(preferred || sorted[0]);
  }
  return count;
}
