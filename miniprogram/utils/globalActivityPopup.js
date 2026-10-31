/**
 * 全局首屏活动弹窗：缓存、预拉取、展示记录（各 Tab 页共用，已展示活动在缓存有效期内不重复弹）
 */
import { requestUtil } from "./requestUtil.js";
import {
  activityPopupImageUrl,
  advertisingImageUrlDetail,
  IMAGE_Q_DETAIL,
  isServeableImagePath,
  preloadFromMediaItems,
} from "./imageUrl.js";
import {
  ACTIVITY_POPUP_CACHE_KEY,
  ACTIVITY_POPUP_CACHE_MINUTES,
} from "../config/perf.js";

export const ACTIVITY_RECORD_KEY = "activity_record";
export const ACTIVITY_POPUP_TYPE = "page_activity";

/** 不自动尝试弹窗的路由前缀（选店/下单/排队等流程页） */
const POPUP_EXCLUDED_ROUTE_PREFIXES = [
  "packageOther/select-shop/",
  "packageOther/select_number/",
  "packageOther/confirm-order/",
  "packageOther/order-details/",
  "packageOther/queue-ticket/",
  "packageOther/combo-select/",
  "packageOther/order-comment/",
];

let prefetchPromise = null;
/** 后台刷新间隔，避免每次 Tab onShow 都打接口 */
const POPUP_REFETCH_GAP_MS = 3 * 60 * 1000;
let lastPopupFetchMs = 0;

export function shouldRefetchActivityPopup() {
  return Date.now() - lastPopupFetchMs > POPUP_REFETCH_GAP_MS;
}

export function markActivityPopupFetched() {
  lastPopupFetchMs = Date.now();
}

/**
 * 收到 /ws/v1/notify 的 ACTIVITY_POPUP_CHANGED 事件时立即失效本地 3 分钟缓存
 */
export function invalidateActivityPopupCache(app) {
  lastPopupFetchMs = 0;
  try {
    const inst = resolveApp(app);
    if (inst && typeof inst.setStorageWithExpiry === "function") {
      inst.setStorageWithExpiry(ACTIVITY_POPUP_CACHE_KEY, [], 0);
    }
    wx.removeStorageSync(ACTIVITY_POPUP_CACHE_KEY);
  } catch (e) {
    /* ignore */
  }
}

function resolveApp(app) {
  if (app && typeof app.getStorageWithExpiry === "function") return app;
  try {
    const g = typeof getApp === "function" ? getApp() : null;
    if (g && typeof g.getStorageWithExpiry === "function") return g;
  } catch (e) {
    /* ignore */
  }
  return null;
}

export function buildPopupImageUrl(imgOrItem) {
  if (!imgOrItem) return "";
  if (typeof imgOrItem === "object") {
    return activityPopupImageUrl(imgOrItem, IMAGE_Q_DETAIL);
  }
  if (!isServeableImagePath(imgOrItem)) return "";
  return advertisingImageUrlDetail(imgOrItem);
}

export function preloadPopupImages(list) {
  return preloadFromMediaItems(list, null, IMAGE_Q_DETAIL);
}

export function getShownActivityIds(app) {
  const inst = resolveApp(app);
  if (!inst) return [];
  const stored = inst.getStorageWithExpiry(ACTIVITY_RECORD_KEY) || [];
  if (!Array.isArray(stored)) return [];
  return [...new Set(stored.map((r) => r.activity_id).filter((id) => id != null))];
}

export function filterUnshownActivities(activity, app) {
  if (!Array.isArray(activity) || !activity.length) return [];
  const shown = getShownActivityIds(app);
  return activity.filter((act) => !shown.includes(act.id));
}

export function appendActivityShowRecords(app, activities) {
  const inst = resolveApp(app);
  if (!inst || !activities || !activities.length) return;
  const storedRecords = inst.getStorageWithExpiry(ACTIVITY_RECORD_KEY) || [];
  const newRecords = activities.map((act) => ({
    activity_id: act.id,
    time: new Date(),
    type: "show",
    name: act.name,
  }));
  const allRecords = [...storedRecords, ...newRecords].filter(
    (record, index, self) =>
      self.findIndex((r) => r.activity_id === record.activity_id) === index
  );
  inst.globalData.activity_record = allRecords;
  inst.setStorageWithExpiry(ACTIVITY_RECORD_KEY, allRecords, ACTIVITY_POPUP_CACHE_MINUTES);
}

export function getCachedUnshownActivities(app) {
  const inst = resolveApp(app);
  if (!inst) return [];
  const cached = inst.getStorageWithExpiry(ACTIVITY_POPUP_CACHE_KEY);
  if (!cached || !Array.isArray(cached) || !cached.length) return [];
  return filterUnshownActivities(cached, inst);
}

/**
 * 拉取活动弹窗列表并写缓存、预加载图片
 * @returns {Promise<{ hasActivity: boolean, activity: Array, unshown: Array }>}
 */
export async function fetchActivityPopupList(app, options = {}) {
  const inst = resolveApp(app);
  const openid =
    options.openid != null
      ? options.openid
      : inst && inst.globalData
        ? inst.globalData.openid
        : null;

  try {
    const response = await requestUtil({
      url: "/activity/popupList",
      data: { openid, type: ACTIVITY_POPUP_TYPE },
      method: "post",
      showLoading: false,
    });

    const { hasActivity, activity } = response || {};
    if (hasActivity && Array.isArray(activity) && activity.length > 0) {
      if (inst) {
        inst.setStorageWithExpiry(
          ACTIVITY_POPUP_CACHE_KEY,
          activity,
          ACTIVITY_POPUP_CACHE_MINUTES
        );
      }
      preloadPopupImages(activity);
      const unshown = filterUnshownActivities(activity, inst);
      return { hasActivity: true, activity, unshown };
    }
    return { hasActivity: false, activity: [], unshown: [] };
  } catch (e) {
    return { hasActivity: false, activity: [], unshown: [] };
  }
}

/** App 启动预拉取，任意页面 onShow 时缓存已就绪 */
export function prefetchActivityPopupOnLaunch(app) {
  const inst = resolveApp(app);
  if (!inst || !inst.globalData || !inst.globalData.openid) {
    return Promise.resolve();
  }
  if (prefetchPromise) return prefetchPromise;
  prefetchPromise = fetchActivityPopupList(inst).finally(() => {
    markActivityPopupFetched();
    prefetchPromise = null;
  });
  return prefetchPromise;
}

export function shouldTryActivityPopupOnRoute(route) {
  const r = String(route || "").trim();
  if (!r) return false;
  if (
    POPUP_EXCLUDED_ROUTE_PREFIXES.some((prefix) => r.startsWith(prefix))
  ) {
    return false;
  }
  try {
    const app = getApp();
    if (app && app.globalData && app.globalData.isReviewMode) return false;
  } catch (e) {
    /* ignore */
  }
  return true;
}

/** 由全局 mixin 在 onShow 调用，页面需挂载 <global-activity-popup ref="globalActivityPopup" /> */
export function tryShowGlobalActivityPopup(pageVm) {
  if (!pageVm || !pageVm.$refs) return;
  const ref = pageVm.$refs.globalActivityPopup;
  if (ref && typeof ref.tryShow === "function") {
    ref.tryShow();
  }
}
