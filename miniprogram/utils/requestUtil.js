import { getShopRequestHeaders } from "./shopContext.js";
import { getStoredUserToken } from "./userAuthToken.js";

// 同时进行中的请求数（含 showLoading: false 的请求）
let ajaxTimes = 0;
// 本批请求中是否曾调用过 wx.showLoading（用于与无 loading 的并发请求正确配对 hide）
let loadingMaskRef = 0;

// 定义公共的 url（与 docs 约定一致：统一 baseUrl、错误提示）
// const baseUrl = "http://localhost";
const baseUrl = "http://localhost:8080";

/** 默认请求超时时间（毫秒），与文档「请求超时」约定一致 */
const DEFAULT_TIMEOUT = 15000;

/**
 * 返回 baseUrl
 */
export const getBaseUrl = () => {
  return baseUrl;
};

/**
 * 后端请求工具类（与 docs 约定：code===0 判断成功，非 0 展示 msg；网络失败/超时统一提示）
 * @param {Object} params 请求参数（url、method、data、header、showLoading、timeout、showErrorMsg）
 * @param {boolean} params.showErrorMsg 是否在业务失败时自动 toast 后端 msg，默认 false（由各页按需展示）
 */
export const requestUtil = (params) => {
  /** 门店：以 X-Shop-Id 为准；放在最后合并，避免调用方 header 覆盖丢失门店 */
  const header = { ...(params.header || {}), ...getShopRequestHeaders() };
  const userToken = getStoredUserToken();
  if (userToken && header["X-User-Token"] == null) header["X-User-Token"] = userToken;
  // 历史小程序曾使用 token 头；短期保留，避免后端灰度期间兼容字段缺失。
  if (userToken && header["token"] == null) header["token"] = userToken;

  ajaxTimes++;
  const showGlobalLoading = params.showLoading !== false;
  if (showGlobalLoading) {
    loadingMaskRef++;
    wx.showLoading({ title: "加载中", mask: true });
  }

  const timeout = params.timeout != null ? params.timeout : DEFAULT_TIMEOUT;

  return new Promise((resolve, reject) => {
    wx.request({
      ...params,
      header,
      url: baseUrl + params.url,
      timeout,
      success: (result) => {
        const data = result.data;
        // 与文档约定一致：code 非 0 时可由调用方展示 msg；若传 showErrorMsg: true 则此处统一 toast
        if (data && data.code !== undefined && data.code !== 0 && params.showErrorMsg === true && data.msg) {
          wx.showToast({
            icon: "none",
            title: data.msg,
            duration: 2500,
          });
        }
        resolve(data);
      },
      fail: (err) => {
        const isTimeout = err.errMsg && (err.errMsg.indexOf("timeout") !== -1 || err.errMsg.indexOf("超时") !== -1);
        wx.showToast({
          icon: "none",
          title: isTimeout ? "请求超时" : "连接服务器失败",
          duration: 3000,
        });
        reject(err);
      },
      complete: () => {
        ajaxTimes--;
        if (showGlobalLoading) {
          loadingMaskRef = Math.max(0, loadingMaskRef - 1);
          // 当所有需要 Loading 的请求全部返回时，立即释放遮罩，避免被静默后台请求阻断
          if (loadingMaskRef === 0) {
            wx.hideLoading();
          }
        } else if (ajaxTimes === 0 && loadingMaskRef === 0) {
          wx.hideLoading();
        }
      },
    });
  });
};
