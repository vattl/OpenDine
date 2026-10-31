/**
 * 菜品库与门店状态变更 WebSocket 适配层（已统一收敛至 /ws/v1/notify 单连接通道）
 *
 * 保持原有导出函数签名 100% 兼容：
 * - startMenuCatalogSocket({ onRefetchMenu, onBusinessChanged, onAnnouncementChanged })
 * - stopMenuCatalogSocket()
 * - subscribeMenuCatalogChanged(cb)
 * - isMenuCatalogSocketConnected()
 * - getMenuWebSocketUrl()
 */
import {
  buildUnifiedWebSocketUrl,
  ensureUnifiedNotifySocketStarted,
  isUnifiedNotifySocketConnected,
  subscribeAnnouncementChanged,
  subscribeLegacyCompatEvent,
} from './unifiedNotifyCenter.js';

const DEBOUNCE_MS = 400;

let debounceTimer = null;
const handlers = {
  /** @type {((payloads: object[]) => void) | null} */
  onRefetchMenu: null,
  /** @type {((msg: object) => void) | null} */
  onBusinessChanged: null,
  /** @type {((msg: object) => void) | null} */
  onAnnouncementChanged: null,
};
let refetchHandler = null;
/** @type {object[]} */
let pendingCatalogPayloads = [];

const notifyListeners = new Set();
let unsubscribeUnified = null;
let unsubscribeAnnouncement = null;

/** @returns {boolean} */
export function isMenuCatalogSocketConnected() {
  return isUnifiedNotifySocketConnected();
}

/**
 * 由 getBaseUrl() 推导统一网关 wss/ws 地址 (/ws/v1/notify)
 * @returns {string}
 */
export function getMenuWebSocketUrl() {
  return buildUnifiedWebSocketUrl();
}

function emitNotify(payload) {
  notifyListeners.forEach((fn) => {
    try {
      fn(payload);
    } catch (e) {}
  });
}

/**
 * 订阅统一通道转发的兼容消息（含 dish_catalog_changed、business_changed、meal_pickup_ready 等）。
 * @param {(payload: object) => void} cb
 * @returns {() => void} 取消订阅
 */
export function subscribeMenuCatalogChanged(cb) {
  if (typeof cb !== 'function') return () => {};
  ensureBridgeRegistered();
  notifyListeners.add(cb);
  return () => notifyListeners.delete(cb);
}

function scheduleCatalogRefetchBatch(payload) {
  if (!handlers.onRefetchMenu) return;
  pendingCatalogPayloads.push(payload);
  if (debounceTimer) clearTimeout(debounceTimer);
  debounceTimer = setTimeout(() => {
    debounceTimer = null;
    const batch = pendingCatalogPayloads.slice();
    pendingCatalogPayloads = [];
    try {
      handlers.onRefetchMenu(batch);
    } catch (e) {
      console.warn('menuCatalogSocket onRefetchMenu', e);
    }
  }, DEBOUNCE_MS);
}

function ensureBridgeRegistered() {
  if (!unsubscribeUnified) {
    unsubscribeUnified = subscribeLegacyCompatEvent((msg) => {
      if (!msg || msg.type == null) return;
      emitNotify(msg);
      if (msg.type === 'dish_catalog_changed') {
        scheduleCatalogRefetchBatch(msg);
        return;
      }
      if (msg.type === 'business_changed') {
        const fn = handlers.onBusinessChanged;
        if (typeof fn === 'function') {
          try {
            fn(msg);
          } catch (e) {
            console.warn('menuCatalogSocket onBusinessChanged', e);
          }
        }
      }
    });
  }
  if (!unsubscribeAnnouncement) {
    unsubscribeAnnouncement = subscribeAnnouncementChanged((payload) => {
      const fn = handlers.onAnnouncementChanged;
      if (typeof fn === 'function') {
        try {
          fn(payload);
        } catch (e) {
          console.warn('menuCatalogSocket onAnnouncementChanged', e);
        }
      }
    });
  }
}

/**
 * 启动统一实时通道并注册菜单/营业/门店公告状态回调
 * @param {{
 *   onRefetchMenu: (payloads: object[]) => void,
 *   onBusinessChanged?: (msg: object) => void,
 *   onAnnouncementChanged?: (msg: object) => void
 * }} options
 * @returns {() => void}
 */
export function startMenuCatalogSocket(options = {}) {
  const { onRefetchMenu, onBusinessChanged, onAnnouncementChanged } = options;
  handlers.onRefetchMenu = typeof onRefetchMenu === 'function' ? onRefetchMenu : null;
  refetchHandler = handlers.onRefetchMenu;
  handlers.onBusinessChanged = typeof onBusinessChanged === 'function' ? onBusinessChanged : null;
  handlers.onAnnouncementChanged = typeof onAnnouncementChanged === 'function' ? onAnnouncementChanged : null;
  ensureBridgeRegistered();
  ensureUnifiedNotifySocketStarted();
  return () => stopMenuCatalogSocket();
}

/** 清理当前页面的菜单防抖回调（底层全局 /ws/v1/notify 保持在线以接收优惠券/取餐/叫号消息） */
export function stopMenuCatalogSocket() {
  handlers.onRefetchMenu = null;
  handlers.onBusinessChanged = null;
  handlers.onAnnouncementChanged = null;
  refetchHandler = null;
  pendingCatalogPayloads = [];
  if (debounceTimer) {
    clearTimeout(debounceTimer);
    debounceTimer = null;
  }
}
