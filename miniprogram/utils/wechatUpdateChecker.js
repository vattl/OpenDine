/**
 * uni-app 微信小程序专用更新检测工具
 * 仅支持微信小程序平台
 * 使用：在App.vue的onLaunch中调用
 */
export function checkWechatUpdate() {
  // 检查是否在微信环境（getSystemInfoSync 已废弃，改用 getDeviceInfo 获取 platform）
  let platform = '';
  try {
    if (typeof uni.getDeviceInfo === 'function') {
      platform = uni.getDeviceInfo().platform || '';
    } else {
      platform = (uni.getSystemInfoSync && uni.getSystemInfoSync())?.platform || '';
    }
  } catch (e) {
    console.warn('获取设备信息失败', e);
  }
  const normalizedPlatform = String(platform || '').toLowerCase();
  // 兼容鸿蒙微信（不同基础库可能上报为 harmony/openharmony/harmonyos）
  const supportedPlatforms = ['devtools', 'ios', 'android', 'harmony', 'openharmony', 'harmonyos'];
  if (!supportedPlatforms.includes(normalizedPlatform)) {
    console.log('非微信环境，不执行更新检测');
    return;
  }

  // 检查是否支持更新API
  if (!uni.canIUse('getUpdateManager')) {
    uni.showModal({
      title: '提示',
      content: '当前微信版本过低，无法支持自动更新，请升级微信至最新版本',
      showCancel: false,
      confirmText: '知道了'
    });
    return;
  }

  // 获取微信更新管理器
  const updateManager = uni.getUpdateManager();

  // 验证更新管理器方法是否存在
  if (!updateManager || typeof updateManager.checkForUpdate !== 'function') {
    console.log("当前环境不支持自动更新");
    return;
  }

  // 检测新版本
  updateManager.checkForUpdate({
    success: (res) => {
      // 有新版本
      if (res.hasUpdate) {
        console.log('检测到新版本，开始下载');
        
        // 监听下载完成
        updateManager.onUpdateReady(() => {
          uni.showModal({
            title: '更新提示',
            content: '新版本已下载完成，是否立即重启应用？',
            confirmText: '立即重启',
            cancelText: '稍后再说',
            success: (modalRes) => {
              if (modalRes.confirm) {
                // 应用新版本
                updateManager.applyUpdate();
              } else {
                // 记录稍后更新状态
                uni.setStorageSync('wechatNeedUpdate', true);
              }
            }
          });
        });

        // 监听下载失败
        updateManager.onUpdateFailed(() => {
          uni.showModal({
            title: '更新失败',
            content: '新版本下载失败，请删除小程序后重新搜索打开',
            showCancel: false,
            confirmText: '知道了'
          });
        });
      } else {
        console.log('当前已是最新版本');
        // 清除更新标记
        uni.removeStorageSync('wechatNeedUpdate');
      }
    },
    fail: (err) => {
      console.error('检查更新失败：', err);
      // 3秒后重试一次
      setTimeout(() => {
        checkWechatUpdate();
      }, 3000);
    }
  });

  // 监听更新应用事件
  updateManager.onUpdateApply(() => {
    console.log('微信小程序已更新并重启');
    // 清除更新标记
    uni.removeStorageSync('wechatNeedUpdate');
    // 可添加更新后的初始化操作
  });
}
