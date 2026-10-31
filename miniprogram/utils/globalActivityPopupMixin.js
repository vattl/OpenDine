import {
  shouldTryActivityPopupOnRoute,
  tryShowGlobalActivityPopup,
} from "./globalActivityPopup.js";
import { runWhenRouteSettled } from "./pageLifecycle.js";
import {
  drainModalQueue,
  ensureUnifiedNotifySocketStarted,
} from "./unifiedNotifyCenter.js";

/**
 * 全局混入：
 * 1. 确保统一实时通道 `/ws/v1/notify` 在线并同步门店/用户上下文
 * 2. 页面切换至常规页时自动唤醒单模态队列中挂起的弹窗
 * 3. Tab 等页面挂载 GlobalActivityPopup 后，onShow 自动尝试展示（纳入 P2 单模态优先级队列，与 P1 优惠券弹窗互斥）
 */
export default {
  onShow() {
    ensureUnifiedNotifySocketStarted();
    const pages = getCurrentPages();
    const current = pages && pages.length ? pages[pages.length - 1] : null;
    const route = current && current.route ? String(current.route) : "";
    drainModalQueue();
    if (!shouldTryActivityPopupOnRoute(route)) return;
    const self = this;
    runWhenRouteSettled(route, () => {
      if (!shouldTryActivityPopupOnRoute(route)) return;
      tryShowGlobalActivityPopup(self);
    });
  },
};
