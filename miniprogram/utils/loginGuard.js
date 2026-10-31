/** 是否已登录（与地址/下单等接口一致：需 isLogin + openid） */
export function isLoggedIn() {
  const app = getApp();
  if (!app || !app.globalData) return false;
  const openid = app.globalData.openid || wx.getStorageSync("openid");
  return !!(app.globalData.isLogin && openid);
}

/**
 * 未登录时提示并可跳转「我的」页登录
 * @param {{ toast?: string, backUrl?: string }} [options]
 * @returns {boolean} 已登录为 true
 */
export function promptLoginIfNeeded(options = {}) {
  if (isLoggedIn()) return true;
  const app = getApp();
  const toast = options.toast || "请先登录";
  wx.showToast({ title: toast, icon: "none" });
  const backUrl = options.backUrl;
  if (backUrl && app && typeof app.checkLogin === "function") {
    app.checkLogin(backUrl);
  }
  return false;
}
