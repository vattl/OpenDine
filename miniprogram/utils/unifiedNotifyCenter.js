/**
 * 小程序全域实时消息与单模态优先级编排中心 (UnifiedNotificationCenter)
 *
 * 统一管理：
 * 1. /ws/v1/notify 单连接生命周期、心跳保活 (PING/PONG)、上下文动态绑定 (BIND_CONTEXT)
 * 2. 断线重连游标增量补拉 (GET /user/notifications/sync) 与已读确认 (POST /user/notifications/ack)
 * 3. 单模态互斥优先级队列 (P1 优惠券礼盒弹窗 > 500ms 呼吸冷却 > P2 GlobalActivityPopup 活动海报弹窗)
 * 4. 800ms 批量发券防刷屏聚合窗口 + 确认订单页 (confirm-order) 支付防打扰胶囊横幅降级
 * 5. P0 取餐/排队叫号置顶强提醒条、P1 退款结果横幅、P2 门店公告实时广播与临期券 SnackBar、P3 菜品静默同步
 */
import { getBaseUrl, requestUtil } from "./requestUtil.js";
import { getStoredUserToken } from "./userAuthToken.js";
import { getCurrentShopId } from "./shopContext.js";
import { getTopPageRoute } from "./pageLifecycle.js";

const SEQ_STORAGE_KEY = "mp_unified_notify_seq_id_v1";
const COUPON_AGGREGATION_WINDOW_MS = 800;
const MODAL_COOLDOWN_MS = 500;
const HEARTBEAT_INTERVAL_MS = 25000;
const RECONNECT_BASE_MS = 2000;
const RECONNECT_MAX_MS = 30000;
const DEDUP_RING_SIZE = 200;

/** 支付敏感路由前缀：禁止弹出全屏 Modal，P1 优惠券降级为顶部胶囊条，P2 活动海报挂起 */
const CHECKOUT_SENSITIVE_ROUTES = [
  "packageOther/confirm-order/confirm-order",
];

let socketTask = null;
let connected = false;
let started = false;
let manualStop = false;
let reconnectAttempt = 0;
let reconnectTimer = null;
let heartbeatTimer = null;
let couponBatchTimer = null;
let modalCooldownTimer = null;

/** 最近处理过的 message_id 环形去重表 */
const processedMessageIds = [];
const processedMessageIdSet = new Set();

/** 800ms 待聚合的优惠券事件队列 */
let pendingCouponEnvelopes = [];

/**
 * 单模态互斥锁与优先级等待队列
 * activeModalSlot: null | { type: 'COUPON_MODAL' | 'ACTIVITY_POPUP', priorityWeight: number, id: string }
 */
let activeModalSlot = null;
let modalWaitQueue = [];

/** 全局响应式 UI 状态快照（供 GlobalActivityPopup.vue 订阅渲染） */
const uiState = {
  /** P0/P1 顶部横幅: null | { mode: 'pickup'|'queue'|'refund', badge, title, subtitle, actionText, actionRoute, messageIds: string[] } */
  topBanner: null,
  /** 结账页防打扰胶囊横幅: null | { text, grantCount, coupons: object[], messageIds: string[] } */
  suppressCapsule: null,
  /** P1 天降优惠券礼盒弹窗: null | { tag, title, subtitle, grantCount, coupons: object[], messageIds: string[] } */
  couponModal: null,
  /** P2 底部临期优惠券 SnackBar: null | { text, couponName, remainingMinutes, actionRoute, messageIds: string[] } */
  expiringSnackbar: null,
};

const uiListeners = new Set();
const legacyEventListeners = new Set();
const activityInvalidateListeners = new Set();
const announcementListeners = new Set();

function notifyUiListeners() {
  const snapshot = {
    topBanner: uiState.topBanner ? { ...uiState.topBanner } : null,
    suppressCapsule: uiState.suppressCapsule ? { ...uiState.suppressCapsule } : null,
    couponModal: uiState.couponModal ? { ...uiState.couponModal } : null,
    expiringSnackbar: uiState.expiringSnackbar ? { ...uiState.expiringSnackbar } : null,
    activeModalType: activeModalSlot ? activeModalSlot.type : null,
    modalQueueLength: modalWaitQueue.length,
  };
  uiListeners.forEach((fn) => {
    try {
      fn(snapshot);
    } catch (e) {
      /* ignore */
    }
  });
}

export function subscribeUnifiedUiState(cb) {
  if (typeof cb !== "function") return () => {};
  uiListeners.add(cb);
  try {
    cb({
      topBanner: uiState.topBanner,
      suppressCapsule: uiState.suppressCapsule,
      couponModal: uiState.couponModal,
      expiringSnackbar: uiState.expiringSnackbar,
      activeModalType: activeModalSlot ? activeModalSlot.type : null,
      modalQueueLength: modalWaitQueue.length,
    });
  } catch (e) {
    /* ignore */
  }
  return () => uiListeners.delete(cb);
}

export function subscribeLegacyCompatEvent(cb) {
  if (typeof cb !== "function") return () => {};
  legacyEventListeners.add(cb);
  return () => legacyEventListeners.delete(cb);
}

export function subscribeActivityPopupInvalidate(cb) {
  if (typeof cb !== "function") return () => {};
  activityInvalidateListeners.add(cb);
  return () => activityInvalidateListeners.delete(cb);
}

export function subscribeAnnouncementChanged(cb) {
  if (typeof cb !== "function") return () => {};
  announcementListeners.add(cb);
  return () => announcementListeners.delete(cb);
}

export function isCheckoutSensitiveRoute(route) {
  const r = String(route || getTopPageRoute() || "").trim();
  if (!r) return false;
  return CHECKOUT_SENSITIVE_ROUTES.some((prefix) => r.indexOf(prefix) !== -1);
}

export function getLastSeqId() {
  try {
    const val = Number(wx.getStorageSync(SEQ_STORAGE_KEY) || 0);
    return Number.isFinite(val) && val > 0 ? val : 0;
  } catch (e) {
    return 0;
  }
}

function saveLastSeqId(seqId) {
  const n = Number(seqId || 0);
  if (!Number.isFinite(n) || n <= 0) return;
  const current = getLastSeqId();
  if (n > current) {
    try {
      wx.setStorageSync(SEQ_STORAGE_KEY, n);
    } catch (e) {
      /* ignore */
    }
  }
}

function recordMessageProcessed(messageId) {
  if (!messageId) return false;
  const id = String(messageId).trim();
  if (!id) return false;
  if (processedMessageIdSet.has(id)) return true;
  processedMessageIdSet.add(id);
  processedMessageIds.push(id);
  if (processedMessageIds.length > DEDUP_RING_SIZE) {
    const oldest = processedMessageIds.shift();
    if (oldest) processedMessageIdSet.delete(oldest);
  }
  return false;
}

/**
 * 单模态互斥队列：申请模态弹窗展示槽位
 * @param {{
 *   priorityWeight: number, // 1 = P1 优惠券弹窗, 2 = P2 GlobalActivityPopup 活动海报
 *   type: 'COUPON_MODAL' | 'ACTIVITY_POPUP',
 *   id?: string,
 *   onAcquire: () => void
 * }} request
 */
export function requestModalSlot(request) {
  if (!request || typeof request.onAcquire !== "function") return;
  const type = request.type || "ACTIVITY_POPUP";
  const priorityWeight = Number(request.priorityWeight) || 2;
  const id = request.id || type;

  // 若当前已是同类型激活弹窗，直接执行更新
  if (activeModalSlot && activeModalSlot.type === type) {
    request.onAcquire();
    notifyUiListeners();
    return;
  }

  // 去重替换队列中同类型请求
  modalWaitQueue = modalWaitQueue.filter((item) => item.type !== type);
  modalWaitQueue.push({
    priorityWeight,
    type,
    id,
    onAcquire: request.onAcquire,
  });
  modalWaitQueue.sort((a, b) => a.priorityWeight - b.priorityWeight);

  drainModalQueue();
}

/**
 * 释放当前模态槽位，并在 500ms 呼吸冷却后自动唤醒队列中下一优先级弹窗
 */
export function releaseModalSlot(type) {
  if (activeModalSlot && (!type || activeModalSlot.type === type)) {
    activeModalSlot = null;
  }
  notifyUiListeners();
  if (modalCooldownTimer) clearTimeout(modalCooldownTimer);
  if (modalWaitQueue.length > 0) {
    modalCooldownTimer = setTimeout(() => {
      modalCooldownTimer = null;
      drainModalQueue();
    }, MODAL_COOLDOWN_MS);
  }
}

export function drainModalQueue() {
  if (activeModalSlot !== null || modalWaitQueue.length === 0) {
    notifyUiListeners();
    return;
  }
  const route = getTopPageRoute();
  const onSensitivePage = isCheckoutSensitiveRoute(route);

  // 结账确认页禁止弹出 P2 活动海报，保留在队列中等待返回常规页
  const nextIndex = modalWaitQueue.findIndex((item) => {
    if (onSensitivePage && item.type === "ACTIVITY_POPUP") return false;
    return true;
  });

  if (nextIndex === -1) {
    notifyUiListeners();
    return;
  }

  const [nextItem] = modalWaitQueue.splice(nextIndex, 1);
  activeModalSlot = {
    type: nextItem.type,
    priorityWeight: nextItem.priorityWeight,
    id: nextItem.id,
  };
  notifyUiListeners();
  try {
    nextItem.onAcquire();
  } catch (e) {
    activeModalSlot = null;
    notifyUiListeners();
  }
}

/**
 * 向服务端发送消息已读确认 (POST /user/notifications/ack)
 */
export async function ackNotifications(messageIds = []) {
  const validIds = (Array.isArray(messageIds) ? messageIds : [messageIds])
    .map((id) => String(id || "").trim())
    .filter(Boolean);
  if (!validIds.length) return;

  // 若 WebSocket 在线，同时发送轻量 ACK 帧
  if (connected && socketTask && typeof socketTask.send === "function") {
    validIds.forEach((msgId) => {
      try {
        socketTask.send({
          data: JSON.stringify({
            frame_type: "ACK",
            message_id: msgId,
          }),
        });
      } catch (e) {
        /* ignore */
      }
    });
  }

  try {
    const app = typeof getApp === "function" ? getApp() : null;
    const openid = app && app.globalData ? app.globalData.openid : wx.getStorageSync("openid");
    if (!openid) return;
    const shopId = Number(getCurrentShopId()) || 1;
    const token = getStoredUserToken();
    await requestUtil({
      url: "/user/notifications/ack",
      method: "post",
      header: token ? { "X-User-Token": token } : {},
      data: {
        shop_id: shopId,
        message_ids: validIds,
        openid,
      },
      showLoading: false,
    });
  } catch (e) {
    /* ignore network error */
  }
}

/**
 * 断线重连或启动时按 last_seq_id 游标补拉未读消息 (GET /user/notifications/sync)
 */
export async function syncUnreadNotifications() {
  try {
    const app = typeof getApp === "function" ? getApp() : null;
    const openid = app && app.globalData ? app.globalData.openid : wx.getStorageSync("openid");
    const token = getStoredUserToken();
    if (!openid || !token) return;

    const shopId = Number(getCurrentShopId()) || 1;
    const lastSeqId = getLastSeqId();
    const res = await requestUtil({
      url: `/user/notifications/sync?shop_id=${shopId}&last_seq_id=${lastSeqId}&limit=50`,
      method: "get",
      header: token ? { "X-User-Token": token } : {},
      showLoading: false,
    });
    if (!res || res.code !== 0 || !res.data) return;
    const { items, server_head_seq_id } = res.data;
    if (Array.isArray(items) && items.length > 0) {
      items.forEach((envelope) => {
        handleIncomingEnvelope(envelope);
      });
    }
    if (server_head_seq_id) {
      saveLastSeqId(server_head_seq_id);
    }
  } catch (e) {
    /* ignore */
  }
}

/**
 * 关闭优惠券礼盒弹窗并释放 P1 模态锁
 */
export function dismissCouponModal(navigateToMenu = false) {
  const modal = uiState.couponModal;
  uiState.couponModal = null;
  if (modal && Array.isArray(modal.messageIds) && modal.messageIds.length) {
    ackNotifications(modal.messageIds);
  }
  releaseModalSlot("COUPON_MODAL");
  if (navigateToMenu) {
    const route = getTopPageRoute();
    if (route !== "pages/home-page/page") {
      wx.switchTab({
        url: "/pages/home-page/page",
        fail: () => {
          wx.reLaunch({ url: "/pages/home-page/page" });
        },
      });
    }
  }
}

/**
 * 确认并关闭结账页防打扰胶囊横幅
 */
export function dismissSuppressCapsule(triggerReselect = false) {
  const cap = uiState.suppressCapsule;
  uiState.suppressCapsule = null;
  if (cap && Array.isArray(cap.messageIds) && cap.messageIds.length) {
    ackNotifications(cap.messageIds);
  }
  notifyUiListeners();
  if (triggerReselect) {
    try {
      const app = typeof getApp === "function" ? getApp() : null;
      if (app && app.event && typeof app.event.emit === "function") {
        app.event.emit("unified:reselect_coupon", cap);
      }
    } catch (e) {
      /* ignore */
    }
  }
}

/**
 * 确认并关闭顶部 P0/P1 强提醒横幅
 */
export function dismissTopBanner(navigateAction = false) {
  const banner = uiState.topBanner;
  uiState.topBanner = null;
  if (banner && Array.isArray(banner.messageIds) && banner.messageIds.length) {
    ackNotifications(banner.messageIds);
  }
  notifyUiListeners();
  if (navigateAction && banner && banner.actionRoute) {
    wx.navigateTo({
      url: banner.actionRoute,
      fail: () => {},
    });
  }
}

/**
 * 确认并关闭底部临期优惠券 SnackBar
 */
export function dismissExpiringSnackbar(navigateAction = false) {
  const snack = uiState.expiringSnackbar;
  uiState.expiringSnackbar = null;
  if (snack && Array.isArray(snack.messageIds) && snack.messageIds.length) {
    ackNotifications(snack.messageIds);
  }
  notifyUiListeners();
  if (navigateAction) {
    const route = getTopPageRoute();
    if (route !== "pages/home-page/page") {
      wx.switchTab({
        url: "/pages/home-page/page",
        fail: () => {
          wx.reLaunch({ url: "/pages/home-page/page" });
        },
      });
    }
  }
}

function flushCouponAggregationWindow() {
  couponBatchTimer = null;
  if (!pendingCouponEnvelopes.length) return;
  const batch = pendingCouponEnvelopes.slice();
  pendingCouponEnvelopes = [];

  const messageIds = [];
  const coupons = [];
  batch.forEach((env) => {
    if (env.message_id) messageIds.push(env.message_id);
    const p = env.payload || {};
    coupons.push({
      user_coupon_id: p.user_coupon_id,
      coupon_id: p.coupon_id,
      coupon_name: p.coupon_name || "专属优惠券",
      coupon_type: p.coupon_type || "full_reduction",
      discount_value: p.discount_value != null ? Number(p.discount_value) : 0,
      min_amount: p.min_amount != null ? Number(p.min_amount) : 0,
      discount_text: p.discount_text || "",
      expire_time: p.expire_time || "",
    });
  });

  // 广播给页面刷新优惠券角标与列表
  try {
    const app = typeof getApp === "function" ? getApp() : null;
    if (app && app.event && typeof app.event.emit === "function") {
      app.event.emit("unified:coupon_granted", { coupons, messageIds });
    }
  } catch (e) {
    /* ignore */
  }

  // 若当前处于确认订单结账页，自动降级为顶部胶囊横幅，绝不弹窗打断支付
  if (isCheckoutSensitiveRoute()) {
    const first = coupons[0] || {};
    const text =
      coupons.length > 1
        ? `🎉 新到账 ${coupons.length} 张优惠券可用（含${first.coupon_name}）`
        : `🎉 新到账优惠券可用：${first.coupon_name}（${first.discount_text || "立即抵扣"}）`;
    uiState.suppressCapsule = {
      text,
      grantCount: coupons.length,
      coupons,
      messageIds,
    };
    notifyUiListeners();
    return;
  }

  // 常规页面：申请 P1 模态弹窗锁展示天降优惠券礼盒
  requestModalSlot({
    priorityWeight: 1,
    type: "COUPON_MODAL",
    id: messageIds.join(","),
    onAcquire: () => {
      uiState.couponModal = {
        tag: coupons.length > 1 ? `实时到账 · 连发 ${coupons.length} 张` : "天降福利 · 实时到账",
        title: coupons.length > 1 ? `恭喜获得 ${coupons.length} 张专属优惠券` : "恭喜获得专属优惠券",
        subtitle: "已自动放入您的卡包，点餐结算直接抵扣",
        grantCount: coupons.length,
        coupons,
        messageIds,
      };
      notifyUiListeners();
    },
  });
}

function ensureGlobalEventListeners() {
  try {
    const app = typeof getApp === "function" ? getApp() : null;
    if (app && app.event && typeof app.event.on === "function" && !app._unifiedContextBound) {
      app._unifiedContextBound = true;
      app.event.on("unified:context_changed", () => {
        notifyContextChanged();
      });
    }
  } catch (e) {}
}

function emitLegacyCompatFromEnvelope(envelope) {
  const eventType = String(envelope.event_type || "").toUpperCase();
  const payload = envelope.payload || {};

  if (eventType === "DISH_CATALOG_CHANGED") {
    const compat = {
      type: "dish_catalog_changed",
      shopId: payload.shopId || (envelope.target && envelope.target.shop_id) || 1,
      action: payload.action || "update",
      dishId: payload.dishId,
      dishName: payload.dishName,
      onsale: payload.onsale,
      ts: envelope.timestamp || Date.now(),
    };
    legacyEventListeners.forEach((fn) => {
      try {
        fn(compat);
      } catch (e) {}
    });
    return;
  }

  if (eventType === "SHOP_BUSINESS_CHANGED") {
    const compat = {
      type: "business_changed",
      shopId: payload.shopId || (envelope.target && envelope.target.shop_id) || 1,
      business: payload.business,
      ts: envelope.timestamp || Date.now(),
    };
    legacyEventListeners.forEach((fn) => {
      try {
        fn(compat);
      } catch (e) {}
    });
    return;
  }

  if (payload && payload.type) {
    legacyEventListeners.forEach((fn) => {
      try {
        fn(payload);
      } catch (e) {}
    });
  }
}

export function handleIncomingEnvelope(envelope) {
  if (!envelope || typeof envelope !== "object") return;

  // 兼容旧版扁平消息
  if (!envelope.frame_type && envelope.type) {
    legacyEventListeners.forEach((fn) => {
      try {
        fn(envelope);
      } catch (e) {}
    });
    return;
  }

  if (envelope.seq_id) {
    saveLastSeqId(envelope.seq_id);
  }

  const frameType = String(envelope.frame_type || "").toUpperCase();
  if (frameType === "CONTEXT_BOUND") {
    const payload = envelope.payload || {};
    if (payload.server_head_seq_id) {
      const localSeq = getLastSeqId();
      if (Number(payload.server_head_seq_id) > localSeq) {
        syncUnreadNotifications();
      }
    }
    return;
  }
  if (frameType === "CONNECTED") {
    const payload = envelope.payload || {};
    if (payload.server_head_seq_id) {
      const localSeq = getLastSeqId();
      if (Number(payload.server_head_seq_id) > localSeq) {
        syncUnreadNotifications();
      }
    }
    return;
  }

  if (frameType !== "EVENT") {
    return;
  }

  if (recordMessageProcessed(envelope.message_id)) {
    return;
  }

  const eventType = String(envelope.event_type || "").toUpperCase();
  const payload = envelope.payload || {};
  const strategy = envelope.display_strategy || {};

  // 1. P3 静默菜品/营业/配送状态变更转发
  emitLegacyCompatFromEnvelope(envelope);

  // 2. P1 优惠券发放 -> 800ms 批量聚合 + 单模态锁 / 结账页胶囊横幅降级
  if (eventType === "COUPON_GRANTED") {
    pendingCouponEnvelopes.push(envelope);
    if (couponBatchTimer) clearTimeout(couponBatchTimer);
    couponBatchTimer = setTimeout(flushCouponAggregationWindow, COUPON_AGGREGATION_WINDOW_MS);
    return;
  }

  // 3. P0 出餐取餐强提醒
  if (eventType === "ORDER_READY_FOR_PICKUP" || eventType === "MEAL_PICKUP_READY") {
    const pickupCode = payload.pickup_code || payload.pickupCode || payload.order_id || payload.orderId || "";
    const tableNumber = payload.table_number || payload.tableNumber || "";
    try {
      if (typeof wx.vibrateLong === "function") wx.vibrateLong();
    } catch (e) {}
    uiState.topBanner = {
      mode: "pickup",
      badge: pickupCode ? `#${pickupCode}` : "取餐",
      title: "您的餐品已全部制作完成！",
      subtitle: tableNumber ? `桌号 ${tableNumber} · 请凭取餐号前往取餐口` : (payload.message || "请凭取餐号前往取餐口取餐"),
      actionText: strategy.action_text || "查看详情",
      actionRoute: strategy.action_route || (payload.order_id ? `/packageOther/order-details/details?id=${payload.order_id}` : ""),
      messageIds: envelope.message_id ? [envelope.message_id] : [],
    };
    notifyUiListeners();
    return;
  }

  // 4. P0 排队叫号到号强提醒
  if (eventType === "QUEUE_TICKET_CALLED") {
    const ticketNo = payload.ticket_no || "到号";
    try {
      if (typeof wx.vibrateLong === "function") wx.vibrateLong();
    } catch (e) {}
    uiState.topBanner = {
      mode: "queue",
      badge: String(ticketNo),
      title: "排队到号提醒：请立即前往就餐！",
      subtitle: payload.message || `排号 ${ticketNo} 已叫号，请前往迎宾台入座`,
      actionText: strategy.action_text || "查看排号",
      actionRoute: strategy.action_route || "/packageOther/queue-ticket/queue-ticket",
      messageIds: envelope.message_id ? [envelope.message_id] : [],
    };
    notifyUiListeners();
    return;
  }

  // 5. P1 订单退款审批结果通知
  if (eventType === "ORDER_REFUND_PROCESSED") {
    const amount = payload.refund_amount != null ? Number(payload.refund_amount).toFixed(2) : "";
    uiState.topBanner = {
      mode: "refund",
      badge: "退款",
      title: amount ? `退款通知 (¥${amount})` : "订单退款状态更新",
      subtitle: payload.remark || "商家已处理您的退款申请，请留意微信支付到账通知",
      actionText: strategy.action_text || "查看订单",
      actionRoute: strategy.action_route || "",
      messageIds: envelope.message_id ? [envelope.message_id] : [],
    };
    notifyUiListeners();
    return;
  }

  // 6. P2 优惠券临期提醒 SnackBar
  if (eventType === "COUPON_EXPIRING_SOON") {
    const couponName = payload.coupon_name || "优惠券";
    const mins = payload.remaining_minutes != null ? payload.remaining_minutes : 60;
    uiState.expiringSnackbar = {
      text: `⏰ 您的【${couponName}】将于 ${mins} 分钟后到期`,
      couponName,
      remainingMinutes: mins,
      actionRoute: strategy.action_route || "/pages/home-page/page",
      messageIds: envelope.message_id ? [envelope.message_id] : [],
    };
    notifyUiListeners();
    return;
  }

  // 7. P2 后台发布/更新营销活动海报弹窗 -> 失效本地 3 分钟缓存并触发 P2 单模态队列展示
  if (eventType === "ACTIVITY_POPUP_CHANGED") {
    activityInvalidateListeners.forEach((fn) => {
      try {
        fn(payload);
      } catch (e) {}
    });
    return;
  }

  // 8. P2 门店公告实时广播 -> 通知门店点餐页立即刷新顶部公告条
  if (eventType === "SHOP_ANNOUNCEMENT_CHANGED") {
    announcementListeners.forEach((fn) => {
      try {
        fn(payload);
      } catch (e) {}
    });
  }
}

export function buildUnifiedWebSocketUrl() {
  const base = String(getBaseUrl() || "")
    .trim()
    .replace(/\/+$/, "");
  if (!base) return "";

  let wsBase = "";
  if (/^https:\/\//i.test(base)) {
    wsBase = `wss://${base.slice(8)}/ws/v1/notify`;
  } else if (/^http:\/\//i.test(base)) {
    wsBase = `ws://${base.slice(7)}/ws/v1/notify`;
  } else {
    wsBase = `wss://${base}/ws/v1/notify`;
  }

  const app = typeof getApp === "function" ? getApp() : null;
  const openid = (app && app.globalData && app.globalData.openid) || wx.getStorageSync("openid") || "";
  const token = getStoredUserToken() || "";
  const shopId = Number(getCurrentShopId()) || 1;
  const lastSeqId = getLastSeqId();

  const query = [
    `client_type=MINI_PROGRAM`,
    `shop_id=${encodeURIComponent(shopId)}`,
    `last_seq_id=${encodeURIComponent(lastSeqId)}`,
  ];
  if (openid) {
    query.push(`openid=${encodeURIComponent(openid)}`);
  }
  if (token) {
    query.push(`token=${encodeURIComponent(token)}`);
    query.push(`user_token=${encodeURIComponent(token)}`);
  }
  return `${wsBase}?${query.join("&")}`;
}

export function sendBindContextFrame() {
  if (!connected || !socketTask || typeof socketTask.send !== "function") return;
  try {
    const app = typeof getApp === "function" ? getApp() : null;
    const openid = (app && app.globalData && app.globalData.openid) || wx.getStorageSync("openid") || "";
    const token = getStoredUserToken() || "";
    const shopId = Number(getCurrentShopId()) || 1;
    socketTask.send({
      data: JSON.stringify({
        frame_type: "BIND_CONTEXT",
        shop_id: shopId,
        openid,
        token,
        user_token: token,
        payload: {
          shop_id: shopId,
          openid,
          token,
          user_token: token,
        },
      }),
    });
  } catch (e) {
    /* ignore */
  }
}

/**
 * 当登录状态更新或门店切换时，主动刷新连接上下文并拉取增量未读消息
 */
export function notifyContextChanged() {
  if (connected && socketTask) {
    sendBindContextFrame();
  } else {
    ensureUnifiedNotifySocketStarted();
  }
  syncUnreadNotifications();
}

function startHeartbeat() {
  stopHeartbeat();
  heartbeatTimer = setInterval(() => {
    if (!connected || !socketTask || typeof socketTask.send !== "function") return;
    try {
      socketTask.send({
        data: JSON.stringify({
          frame_type: "PING",
          timestamp: Date.now(),
        }),
      });
    } catch (e) {
      /* ignore */
    }
  }, HEARTBEAT_INTERVAL_MS);
}

function stopHeartbeat() {
  if (heartbeatTimer) {
    clearInterval(heartbeatTimer);
    heartbeatTimer = null;
  }
}

function clearReconnectTimer() {
  if (reconnectTimer) {
    clearTimeout(reconnectTimer);
    reconnectTimer = null;
  }
}

function scheduleReconnect() {
  if (manualStop || !started) return;
  clearReconnectTimer();
  const delay = Math.min(RECONNECT_BASE_MS * Math.pow(2, reconnectAttempt), RECONNECT_MAX_MS);
  reconnectAttempt += 1;
  reconnectTimer = setTimeout(() => {
    reconnectTimer = null;
    connectUnifiedSocket();
  }, delay);
}

function connectUnifiedSocket() {
  if (manualStop || !started) return;
  if (connected && socketTask) return;
  const url = buildUnifiedWebSocketUrl();
  if (!url) {
    scheduleReconnect();
    return;
  }

  try {
    const token = getStoredUserToken() || "";
    const header = {};
    if (token) {
      header["X-User-Token"] = token;
    }
    socketTask = wx.connectSocket({
      url,
      header,
      fail: () => {
        connected = false;
        socketTask = null;
        if (!manualStop) scheduleReconnect();
      },
    });
  } catch (e) {
    connected = false;
    socketTask = null;
    if (!manualStop) scheduleReconnect();
    return;
  }

  if (!socketTask || typeof socketTask.onOpen !== "function") {
    socketTask = null;
    if (!manualStop) scheduleReconnect();
    return;
  }

  socketTask.onOpen(() => {
    connected = true;
    reconnectAttempt = 0;
    clearReconnectTimer();
    startHeartbeat();
    syncUnreadNotifications();
  });

  socketTask.onMessage((res) => {
    if (!res || !res.data) return;
    try {
      const parsed = typeof res.data === "string" ? JSON.parse(res.data) : res.data;
      handleIncomingEnvelope(parsed);
    } catch (e) {
      /* ignore malformed frame */
    }
  });

  socketTask.onError(() => {
    connected = false;
  });

  socketTask.onClose(() => {
    connected = false;
    socketTask = null;
    stopHeartbeat();
    if (!manualStop) scheduleReconnect();
  });
}

export function ensureUnifiedNotifySocketStarted() {
  ensureGlobalEventListeners();
  manualStop = false;
  if (!started) {
    started = true;
    reconnectAttempt = 0;
    connectUnifiedSocket();
  } else if (!connected && !socketTask) {
    connectUnifiedSocket();
  } else {
    sendBindContextFrame();
  }
}

export function isUnifiedNotifySocketConnected() {
  return connected;
}

export function stopUnifiedNotifySocket() {
  manualStop = true;
  started = false;
  connected = false;
  stopHeartbeat();
  clearReconnectTimer();
  if (socketTask && typeof socketTask.close === "function") {
    try {
      socketTask.close({ code: 1000, reason: "client stop" });
    } catch (e) {}
  }
  socketTask = null;
}
