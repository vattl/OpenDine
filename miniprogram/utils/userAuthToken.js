export const USER_TOKEN_STORAGE_KEY = "userToken";
export const LEGACY_TOKEN_STORAGE_KEY = "token";

const TOKEN_KEYS = ["userToken", "user_token", "xUserToken", "x_user_token", "token"];

function normalizeNonEmptyString(value) {
  if (value == null) return "";
  const str = String(value).trim();
  return str || "";
}

function responseData(res) {
  return res && typeof res.data === "object" && res.data !== null ? res.data : null;
}

export function extractOpenidFromResponse(res) {
  if (!res || typeof res !== "object") return "";
  const data = responseData(res);
  return (
    normalizeNonEmptyString(res.openid) ||
    normalizeNonEmptyString(data && data.openid)
  );
}

export function extractUserTokenFromResponse(res) {
  if (!res || typeof res !== "object") return "";
  const data = responseData(res);
  for (const key of TOKEN_KEYS) {
    const token = normalizeNonEmptyString(res[key]) || normalizeNonEmptyString(data && data[key]);
    if (token) return token;
  }
  return "";
}

export function getStoredUserToken() {
  return normalizeNonEmptyString(wx.getStorageSync(USER_TOKEN_STORAGE_KEY)) ||
    normalizeNonEmptyString(wx.getStorageSync(LEGACY_TOKEN_STORAGE_KEY));
}

export function persistUserAuthFromResponse(res, app) {
  const openid = extractOpenidFromResponse(res);
  const userToken = extractUserTokenFromResponse(res);
  if (!openid && !userToken) return false;

  const a = app || getApp();
  if (a && a.globalData) {
    if (openid) {
      a.globalData.openid = openid;
      a.globalData.isLogin = true;
    }
    if (userToken) {
      a.globalData.userToken = userToken;
    }
  }

  try {
    if (openid) wx.setStorageSync("openid", openid);
    if (userToken) {
      wx.setStorageSync(USER_TOKEN_STORAGE_KEY, userToken);
      wx.setStorageSync(LEGACY_TOKEN_STORAGE_KEY, userToken);
    }
  } catch (e) {}

  try {
    const a = app || (typeof getApp === "function" ? getApp() : null);
    if (a && a.event && typeof a.event.emit === "function") {
      a.event.emit("unified:context_changed");
    }
  } catch (e) {}

  return true;
}

export function clearUserAuth(app) {
  const a = app || getApp();
  if (a && a.globalData) {
    a.globalData.openid = null;
    a.globalData.userToken = "";
    a.globalData.isLogin = false;
  }
  try {
    wx.removeStorageSync("openid");
    wx.removeStorageSync(USER_TOKEN_STORAGE_KEY);
    wx.removeStorageSync(LEGACY_TOKEN_STORAGE_KEY);
  } catch (e) {}
}
