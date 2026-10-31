/**
 * 微信登录态续登（openapi v1.2.51）
 * POST /order/takeout/create、POST /order/getPrepayId 可传 code/wx_code；
 * 登录过期返回 code=40101，成功响应可含 openid 供刷新缓存。
 */
import { requestUtil } from './requestUtil.js';
import { persistUserAuthFromResponse } from './userAuthToken.js';

/** 登录态失效业务码 */
export const WX_LOGIN_EXPIRED_CODE = 40101;

export function isWxLoginExpiredResponse(res) {
  return res != null && Number(res.code) === WX_LOGIN_EXPIRED_CODE;
}

export function persistOpenidFromResponse(res, app) {
  return persistUserAuthFromResponse(res, app);
}

export function wxLoginCode() {
  return new Promise((resolve) => {
    wx.login({
      success: (r) => resolve((r && r.code) || ''),
      fail: () => resolve(''),
    });
  });
}

/**
 * 40101 时用 wx.login code 重试一次
 * @param {{ requestFn: (body: object) => Promise<any>, buildBody: (wxCode: string|null) => Promise<object>|object, maxRetry?: number }} options
 */
export async function requestWithLoginRetry({ requestFn, buildBody, maxRetry = 1 }) {
  let body = await Promise.resolve(buildBody(null));
  let res = await requestFn(body);
  persistUserAuthFromResponse(res);
  if (!isWxLoginExpiredResponse(res) || maxRetry <= 0) {
    return res;
  }
  const code = await wxLoginCode();
  if (!code) return res;
  body = await Promise.resolve(buildBody(code));
  res = await requestFn(body);
  persistUserAuthFromResponse(res);
  return res;
}

/** 外卖创单（含 code 续登） */
export async function createTakeoutOrder(orderData) {
  const app = getApp();
  return requestWithLoginRetry({
    requestFn: (body) =>
      requestUtil({
        url: '/order/takeout/create',
        method: 'post',
        data: body,
      }),
    buildBody: async (code) => {
      const openid = (app.globalData && app.globalData.openid) || wx.getStorageSync('openid') || '';
      const base = { ...(orderData || {}), openid };
      if (code) {
        base.code = code;
        base.wx_code = code;
      }
      return base;
    },
  });
}

/** getPrepayId（含 code 续登） */
export async function requestGetPrepayId(payData) {
  return requestWithLoginRetry({
    requestFn: (body) =>
      requestUtil({
        url: '/order/getPrepayId',
        method: 'post',
        data: body,
      }),
    buildBody: async (code) => {
      const base = { ...(payData || {}) };
      if (code) {
        base.code = code;
        base.wx_code = code;
      }
      return base;
    },
  });
}
