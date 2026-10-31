/**
 * 避免页面已跳转后异步回调仍 setData（微信 routeDone / webviewId 警告）
 */

export function getTopPageRoute() {
  try {
    const pages = getCurrentPages();
    const p = pages && pages.length ? pages[pages.length - 1] : null;
    return p && p.route ? String(p.route) : "";
  } catch (e) {
    return "";
  }
}

function normalizeRoute(r) {
  return String(r || "").replace(/^\//, "");
}

/** 指定路由是否仍为栈顶页 */
export function isRouteStillTop(route) {
  const expect = normalizeRoute(route);
  if (!expect) return false;
  return normalizeRoute(getTopPageRoute()) === expect;
}

/** 页面 Vue 实例是否仍为当前栈顶页 */
export function isPageVmStillActive(vm) {
  if (!vm) return false;
  try {
    const pages = getCurrentPages();
    if (!pages || !pages.length) return false;
    const top = pages[pages.length - 1];
    if (top.$vm === vm) return true;
    if (vm.$mp && vm.$mp.page === top) return true;
    const vmRoute = vm.__route__ || (vm.$scope && vm.$scope.route);
    if (vmRoute && top.route && normalizeRoute(vmRoute) === normalizeRoute(top.route)) {
      return true;
    }
    return false;
  } catch (e) {
    return false;
  }
}

/**
 * 等路由完成后再执行（用于 onShow 里弹窗、拉数等）
 * @param {string} route onShow 时捕获的路由
 * @param {Function} fn
 */
export function runWhenRouteSettled(route, fn) {
  const captured = normalizeRoute(route);
  setTimeout(() => {
    if (captured && !isRouteStillTop(captured)) return;
    fn();
  }, 0);
}
