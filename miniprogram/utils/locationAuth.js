/**
 * 微信小程序定位权限管理与地图选点工具
 */

export function classifyLocationError(error) {
  const msg = String(error && error.errMsg ? error.errMsg : error || '').toLowerCase();
  if (msg.indexOf('cancel') !== -1) return 'cancelled';
  if (
    msg.indexOf('auth deny') !== -1 ||
    msg.indexOf('permission denied') !== -1 ||
    msg.indexOf('permission fail') !== -1
  ) return 'permission_denied';
  if (
    msg.indexOf('service is disabled') !== -1 ||
    msg.indexOf('location service') !== -1 ||
    msg.indexOf('gps') !== -1
  ) return 'service_disabled';
  if (msg.indexOf('network') !== -1 || msg.indexOf('timeout') !== -1) return 'network_error';
  return 'unknown';
}

/**
 * 检查并申请位置授权 (scope.userLocation)
 * @param {Object} options
 * @param {string} [options.purposeHint] 授权用途说明提示文案
 * @param {boolean} [options.showModalIfDenied=true] 如果用户曾拒绝，是否弹窗引导去设置页
 * @returns {Promise<boolean>} 是否获得了位置授权
 */
export function ensureLocationPermission(options = {}) {
  const {
    purposeHint = '地图选址需要获取您的位置权限，以便在地图上快速定位您的收货地址并准确计算配送费。',
    showModalIfDenied = true,
  } = options;

  return new Promise((resolve) => {
    if (typeof wx === 'undefined' || typeof wx.getSetting !== 'function') {
      resolve(true);
      return;
    }

    wx.getSetting({
      success: (settingRes) => {
        const auth = settingRes && settingRes.authSetting && settingRes.authSetting['scope.userLocation'];

        // 1. 已经授权
        if (auth === true) {
          resolve(true);
          return;
        }

        // 2. 之前明确拒绝过 (auth === false)，引导去设置页
        if (auth === false) {
          if (!showModalIfDenied) {
            resolve(false);
            return;
          }
          wx.showModal({
            title: '需要位置授权',
            content: purposeHint,
            confirmText: '去设置',
            cancelText: '取消',
            confirmColor: '#e10606',
            success: (modalRes) => {
              if (modalRes.confirm) {
                wx.openSetting({
                  success: (openSettingRes) => {
                    const reAuth = openSettingRes && openSettingRes.authSetting && openSettingRes.authSetting['scope.userLocation'];
                    if (reAuth === true) {
                      resolve(true);
                    } else {
                      wx.showToast({ title: '未开启位置权限', icon: 'none' });
                      resolve(false);
                    }
                  },
                  fail: () => resolve(false),
                });
              } else {
                resolve(false);
              }
            },
            fail: () => resolve(false),
          });
          return;
        }

        // 3. 首次申请授权 (auth === undefined)
        wx.authorize({
          scope: 'scope.userLocation',
          success: () => {
            resolve(true);
          },
          fail: (authErr) => {
            console.warn('[locationAuth] wx.authorize fail', authErr);
            if (showModalIfDenied) {
              wx.showModal({
                title: '需要位置授权',
                content: purposeHint,
                confirmText: '去设置',
                cancelText: '取消',
                confirmColor: '#e10606',
                success: (modalRes) => {
                  if (modalRes.confirm) {
                    wx.openSetting({
                      success: (openSettingRes) => {
                        const reAuth = openSettingRes && openSettingRes.authSetting && openSettingRes.authSetting['scope.userLocation'];
                        resolve(reAuth === true);
                      },
                      fail: () => resolve(false),
                    });
                  } else {
                    resolve(false);
                  }
                },
                fail: () => resolve(false),
              });
            } else {
              resolve(false);
            }
          },
        });
      },
      fail: () => resolve(true),
    });
  });
}

/**
 * 带有完整授权询问与异常处理的地图选点 (wx.chooseLocation)
 * @param {Object} [options]
 * @param {number} [options.latitude] 初始中心纬度
 * @param {number} [options.longitude] 初始中心经度
 * @param {string} [options.purposeHint] 授权用途文案
 * @returns {Promise<{ success: boolean, data?: Object, errMsg?: string, userCancelled?: boolean }>}
 */
export async function chooseLocationWithAuth(options = {}) {
  const {
    latitude,
    longitude,
    purposeHint = '地图选址需要获取您的位置权限，以便在地图上快速定位您的收货地址并准确计算配送费。',
  } = options;

  const authed = await ensureLocationPermission({ purposeHint, showModalIfDenied: true });
  if (!authed) {
    return {
      success: false,
      errMsg: 'user_denied_permission',
      errorType: 'permission_denied',
      userCancelled: false,
    };
  }

  return new Promise((resolve) => {
    const chooseParams = {
      success: (res) => {
        resolve({ success: true, data: res });
      },
      fail: (err) => {
        const msg = (err && err.errMsg) || '';
        const errorType = classifyLocationError(err);
        console.warn('[locationAuth] chooseLocation fail', err);

        // 用户主动取消选点
        if (errorType === 'cancelled') {
          resolve({ success: false, errMsg: 'user_cancelled', errorType, userCancelled: true });
          return;
        }

        // 权限拒绝
        if (errorType === 'permission_denied') {
          wx.showModal({
            title: '需要位置授权',
            content: purposeHint,
            confirmText: '去设置',
            cancelText: '取消',
            confirmColor: '#e10606',
            success: (modalRes) => {
              if (modalRes.confirm) {
                wx.openSetting({
                  success: (openRes) => {
                    const reAuth = openRes && openRes.authSetting && openRes.authSetting['scope.userLocation'];
                    if (reAuth === true) {
                      // 开启成功后再次打开地图选点
                      chooseLocationWithAuth(options).then(resolve);
                      return;
                    }
                  },
                });
              }
            },
          });
          resolve({ success: false, errMsg: 'permission_denied', errorType, userCancelled: false });
          return;
        }

        resolve({ success: false, errMsg: msg, errorType, userCancelled: false });
      },
    };

    if (latitude != null && longitude != null && Number.isFinite(Number(latitude)) && Number.isFinite(Number(longitude))) {
      chooseParams.latitude = Number(latitude);
      chooseParams.longitude = Number(longitude);
    }

    wx.chooseLocation(chooseParams);
  });
}
