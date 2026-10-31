/**
 * 微信「交易评价」能力（wx.openBusinessView + 服务端 setUserNotify）
 * 文档：https://developers.weixin.qq.com/miniprogram/dev/platform-capabilities/business-capabilities/guarantee/comment.html
 */
import { requestUtil } from "./requestUtil.js";

/** 调起微信侧服务评价页 */
export const COMMENT_BUSINESS_TYPE = "servicecommentpage";

export function isOpenBusinessViewSupported() {
  return typeof wx !== "undefined" && typeof wx.openBusinessView === "function";
}

/** 是否为微信支付 transaction_id（420 开头） */
export function isWechatPayTransactionId(transactionId) {
  const s = String(transactionId || "").trim();
  if (!s || s.startsWith("BAL_")) return false;
  return /^420\d{10,}$/.test(s) || s.startsWith("420");
}

/**
 * 构建 openBusinessView.extraData（与微信评价 orderInfo 字段对齐）
 * @see orderInfo.busiOrderId / wxPayId
 */
export function buildCommentExtraData(order) {
  const orderNo = String(
    (order && (order.order_no || order.orderNo || order.busiOrderId)) || ""
  ).trim();
  const rawTid = String(
    (order && (order.transaction_id || order.transactionId || order.wxPayId)) || ""
  ).trim();
  const extra = {};
  if (orderNo) extra.busiOrderId = orderNo;
  if (rawTid && isWechatPayTransactionId(rawTid)) {
    extra.wxPayId = rawTid;
    extra.orderId =
      rawTid.indexOf("payorder@") === 0 ? rawTid : `payorder@_${rawTid}`;
  }
  return extra;
}

/** 订单是否满足「去评价」展示条件（已结账且制作完成，且为微信支付） */
export function canOrderBeCommented(order) {
  if (!order || typeof order !== "object") return false;
  const transac = order.transac_status || order.transactionStatus;
  const rec = order.order_receiving || order.orderRece;
  if (transac === "cancelled") return false;
  if (transac !== "success") return false;
  if (rec && rec !== "off_order") return false;
  const tid = order.transaction_id || order.transactionId;
  return isWechatPayTransactionId(tid);
}

/** 不可评价时的提示文案 */
export function getCommentBlockReason(order) {
  if (!order) return "订单信息无效";
  const transac = order.transac_status || order.transactionStatus;
  const rec = order.order_receiving || order.orderRece;
  if (transac === "cancelled") return "已取消订单无法评价";
  if (transac !== "success") return "订单未结账，暂不可评价";
  if (rec && rec !== "off_order") return "订单未完成，请稍后再评价";
  const tid = order.transaction_id || order.transactionId;
  if (!tid) return "订单缺少支付单号，暂不可评价";
  if (String(tid).startsWith("BAL_")) {
    return "余额支付订单请使用微信支付后，在微信「发现-小程序」中评价";
  }
  if (!isWechatPayTransactionId(tid)) return "仅支持微信支付订单评价";
  return "";
}

/**
 * 查询订单评价状态（需后端代理微信评价接口，未实现时返回 null）
 * @returns {Promise<{commented?:boolean,commentId?:string,canComment?:boolean}|null>}
 */
export async function fetchOrderCommentStatus(orderNo) {
  const no = String(orderNo || "").trim();
  if (!no) return null;
  try {
    const res = await requestUtil({
      url: "/comment/order/status",
      method: "get",
      data: { order_no: no },
      showLoading: false,
      showErrorMsg: false,
    });
    if (res && res.code === 0) {
      return res.data != null ? res.data : res;
    }
  } catch (e) {
    // 后端未接入时忽略
  }
  return null;
}

/**
 * 通知后端回传交易信息（setUserNotify），便于微信邀请评价
 */
export async function syncOrderCommentNotify(orderNo) {
  const no = String(orderNo || "").trim();
  if (!no) return null;
  try {
    const res = await requestUtil({
      url: "/comment/order/sync-notify",
      method: "post",
      data: { order_no: no },
      showLoading: false,
      showErrorMsg: false,
    });
    if (res && res.code === 0) return res.data != null ? res.data : res;
  } catch (e) {
    // 未接入时不阻断打开评价页
  }
  return null;
}

/**
 * 调起微信服务评价页
 * @param {Object} extraData buildCommentExtraData 结果或自定义字段
 */
export function openServiceCommentPage(extraData = {}) {
  return new Promise((resolve, reject) => {
    if (!isOpenBusinessViewSupported()) {
      reject(new Error("当前微信版本不支持评价功能，请升级微信"));
      return;
    }
    wx.openBusinessView({
      businessType: COMMENT_BUSINESS_TYPE,
      extraData: extraData || {},
      success: (res) => resolve(res),
      fail: (err) => reject(err || new Error("打开评价页失败")),
    });
  });
}

function formatOpenCommentFail(err) {
  const raw = (err && (err.errMsg || err.message)) || "打开评价失败";
  const msg = String(raw).replace(/^openBusinessView:fail\s*/i, "");
  if (/CGI error/i.test(msg) || err.errCode === -2) {
    return {
      title: "暂无法打开评价",
      content:
        "请确认：① 订单为微信支付且已完成；② 小程序已在微信公众平台开通「交易评价」；③ 商家已按文档回传交易信息（setUserNotify）。也可稍后在微信「发现 - 小程序」中评价。",
    };
  }
  return { title: "打开评价失败", content: msg || "请稍后重试" };
}

/**
 * 对指定订单打开微信评价页
 * @param {Object} order 含 order_no、transaction_id、transac_status、order_receiving
 * @param {{ syncNotify?: boolean }} options
 */
export async function openOrderComment(order, options = {}) {
  const reason = getCommentBlockReason(order);
  if (reason) {
    wx.showToast({ title: reason, icon: "none", duration: 2800 });
    return false;
  }

  const orderNo = order.order_no || order.orderNo;
  if (options.syncNotify !== false && orderNo) {
    await syncOrderCommentNotify(orderNo);
  }

  const status = orderNo ? await fetchOrderCommentStatus(orderNo) : null;
  if (status && status.commented === true) {
    wx.showToast({ title: "您已评价过该订单", icon: "none" });
    return false;
  }

  try {
    await openServiceCommentPage(buildCommentExtraData(order));
    return true;
  } catch (err) {
    const tip = formatOpenCommentFail(err);
    wx.showModal({
      title: tip.title,
      content: tip.content,
      showCancel: false,
    });
    return false;
  }
}

/** 打开评价中心（不绑定单笔订单） */
export async function openGeneralCommentPage() {
  if (!isOpenBusinessViewSupported()) {
    wx.showToast({ title: "当前微信版本不支持评价功能", icon: "none" });
    return false;
  }
  try {
    await openServiceCommentPage({});
    return true;
  } catch (err) {
    const tip = formatOpenCommentFail(err);
    wx.showModal({ title: tip.title, content: tip.content, showCancel: false });
    return false;
  }
}
