<template>
  <view class="page">
    <view class="hero">
      <text class="hero-title">收货地址</text>
      <text class="hero-sub">{{ isPickMode ? '点选下方地址用于本单配送' : '请通过地图选址添加收货地址' }}</text>
    </view>

    <view v-if="loading" class="state-wrap">
      <view class="skeleton-list">
        <view v-for="n in 3" :key="n" class="sk-card"></view>
      </view>
      <text class="state-text">加载中…</text>
    </view>

    <view v-else-if="!list.length" class="empty-wrap">
      <view class="empty-illu">
        <text class="empty-icon">📮</text>
      </view>
      <text class="empty-title">还没有收货地址</text>
      <text class="empty-desc">添加后可快速完成外卖下单</text>
      <button class="btn-primary" @click="goEdit()">添加收货地址</button>
    </view>

    <scroll-view v-else scroll-y class="list" :show-scrollbar="false">
      <view
        v-for="item in list"
        :key="item.id"
        class="addr-card"
        :class="{ active: isPickMode && selectedId === item.id }"
        @click="onCardTap(item)"
      >
        <view v-if="isPickMode && selectedId === item.id" class="check-mark">✓</view>
        <view class="card-inner">
          <view class="row-top">
            <text class="name">{{ item.contact_name || '收货人' }}</text>
            <text class="phone">{{ item.contact_phone }}</text>
            <view v-if="item.is_default === 1 || item.is_default === true" class="badge-def">默认</view>
          </view>
          <view class="addr-lines">
            <text class="tag-pill" v-if="item.tag">{{ item.tag }}</text>
            <text class="addr-text">{{ formatFull(item) }}</text>
          </view>
          <text v-if="!isAddressCoordinateValid(item)" class="coord-error">缺少有效地图坐标，请编辑后重新选点</text>
          <view class="row-actions" @click.stop>
            <template v-if="isPickMode">
              <view class="link-btn" @click.stop="goEdit(item.id)">编辑</view>
              <view class="link-btn primary" @click.stop="selectRow(item)">使用该地址</view>
            </template>
            <template v-else>
              <view class="link-btn" @click.stop="goEdit(item.id)">编辑</view>
              <view
                v-if="!isDefaultAddress(item)"
                class="link-btn"
                @click.stop="setDefaultAddress(item)"
              >设为默认</view>
              <view class="link-btn danger" @click.stop="confirmDeleteAddress(item)">删除</view>
            </template>
          </view>
        </view>
      </view>
      <view class="bottom-pad"></view>
    </scroll-view>

    <view v-if="!loading && list.length" class="fab-wrap">
      <button class="btn-fab" @click="goEdit()">+ 新建地址</button>
    </view>
    <view class="safe-bottom"></view>
  </view>
</template>

<script>
import { requestUtil } from '../../utils/requestUtil.js';
import { isLoggedIn, promptLoginIfNeeded } from '../../utils/loginGuard.js';
import { normalizeTakeoutAddress, validateGcj02Coordinates } from '../../utils/takeoutAddress.js';

const app = getApp();

function parseTakeoutAddressList(res) {
  if (res && res.code !== undefined && res.code !== 0) return [];
  const raw = res && res.data != null ? res.data : res;
  const arr = (raw && (raw.list || raw.records)) || (Array.isArray(raw) ? raw : []);
  return Array.isArray(arr) ? arr.map((item) => normalizeTakeoutAddress(item)) : [];
}

export default {
  data() {
    return {
      list: [],
      loading: true,
      selectedId: null,
      mode: 'manage',
      actionLoading: false,
    };
  },
  computed: {
    isPickMode() {
      return this.mode === 'pick';
    },
  },
  onLoad(options) {
    if (!isLoggedIn()) {
      wx.showToast({ title: '请先登录', icon: 'none' });
      setTimeout(() => wx.navigateBack({ delta: 1 }), 400);
      return;
    }
    const m = (options && options.mode) || 'manage';
    this.mode = m === 'pick' ? 'pick' : 'manage';
    wx.setNavigationBarTitle({
      title: this.isPickMode ? '选择收货地址' : '地址管理',
    });
    if (this.isPickMode) {
      try {
        const sid = wx.getStorageSync('takeout_selected_address_id');
        if (sid != null && sid !== '') this.selectedId = Number(sid);
      } catch (e) {}
    }
	
    this.loadList();
  },
  methods: {
	_shopLocateLog(stage, detail = null) {
	  if (detail == null) {
	    console.info(`[menu-shop-locate] ${stage}`);
	    return;
	  }
	  console.info(`[menu-shop-locate] ${stage}`, detail);
	},
	showLocationHint(message = '定位失败，请开启定位权限后重试') {
	  const now = Date.now();
	  if (this.lastLocationHintAt && (now - this.lastLocationHintAt) < 10000) {
	    return;
	  }
	  this.lastLocationHintAt = now;
	  wx.showToast({
	    title: message,
	    icon: 'none',
	    duration: 2200,
	  });
	},  
	/**
	 * 微信小程序定位：优先使用 getLocation（更精确），失败时降级到 getFuzzyLocation
	 * @returns {Promise<{ latitude: number, longitude: number } | null>}
	 */
	fetchUserLocationForMenu() {
	  return new Promise((resolve) => {
	    const resolveLoc = (res) => {
	      const lat = Number(res && res.latitude);
	      const lng = Number(res && res.longitude);
	      if (Number.isFinite(lat) && Number.isFinite(lng)) {
	        resolve({ latitude: lat, longitude: lng });
	        return true;
	      }
	      return false;
	    };
	    const tryFuzzy = () => {
	      if (typeof wx.getFuzzyLocation !== 'function') {
	        this.showLocationHint('定位服务不可用，请检查定位权限');
	        resolve(null);
	        return;
	      }
	      wx.getFuzzyLocation({
	        type: 'gcj02',
	        success: (res) => {
	          if (!resolveLoc(res)) {
	            this.showLocationHint('定位结果异常，请稍后重试');
	            resolve(null);
	          }
	        },
	        fail: (err) => {
	          this._shopLocateLog('getFuzzyLocation fail', err);
	          this.showLocationHint('定位失败，请确认已开启定位权限');
	          resolve(null);
	        },
	      });
	    };
	    if (typeof wx.getLocation !== 'function') {
	      tryFuzzy();
	      return;
	    }
	    wx.getLocation({
	      type: 'gcj02',
	      success: (res) => {
	        if (!resolveLoc(res)) tryFuzzy();
	      },
	      fail: (err) => {
	        this._shopLocateLog('getLocation fail', err);
	        this.showLocationHint('未获取到精确定位，已尝试模糊定位');
	        tryFuzzy();
	      },
	    });
	  });
	},  
	  
    isDefaultAddress(item) {
      return item && (item.is_default === 1 || item.is_default === true);
    },
    getOpenid() {
      return app.globalData.openid || wx.getStorageSync('openid') || '';
    },
    formatFull(item) {
      const normalized = normalizeTakeoutAddress(item);
      const p = [item.province, item.city, item.district].filter(Boolean).join('');
      const location = [normalized.poi_name, normalized.address]
        .filter(Boolean)
        .filter((value, index, values) => values.indexOf(value) === index)
        .join(' · ');
      return [p, location, normalized.detail].filter(Boolean).join(' ');
    },
    isAddressCoordinateValid(item) {
      return validateGcj02Coordinates(item).valid;
    },
    async loadList() {
      this.loading = true;
      const openid = this.getOpenid();
      if (!openid) {
        this.loading = false;
        this.list = [];
        return;
      }
      try {
        const res = await requestUtil({
          url: '/order/takeout/address/list',
          method: 'get',
          data: { openid },
          showLoading: false,
        });
        this.list = parseTakeoutAddressList(res);
      } catch (e) {
        this.list = [];
      } finally {
        this.loading = false;
      }
    },
    onCardTap(item) {
      if (this.isPickMode) {
        this.selectRow(item);
      } else {
        this.goEdit(item.id);
      }
    },
    async setDefaultAddress(item) {
      if (!item || item.id == null || this.actionLoading) return;
      if (!promptLoginIfNeeded({ toast: '请先登录' })) return;
      const openid = this.getOpenid();
      if (!openid) return;
      this.actionLoading = true;
      try {
        const res = await requestUtil({
          url: '/order/takeout/address/setDefault',
          method: 'post',
          data: { openid, id: item.id },
          showLoading: true,
        });
        if (res && res.code === 0) {
          wx.showToast({ title: '已设为默认', icon: 'success' });
          await this.loadList();
        } else {
          wx.showToast({ title: (res && res.msg) || '设置失败', icon: 'none' });
        }
      } catch (e) {
        wx.showToast({ title: '网络异常', icon: 'none' });
      } finally {
        this.actionLoading = false;
      }
    },
    confirmDeleteAddress(item) {
      if (!item || item.id == null || this.actionLoading) return;
      wx.showModal({
        title: '删除地址',
        content: '确定删除该收货地址吗？',
        confirmText: '删除',
        confirmColor: '#e10606',
        success: (r) => {
          if (r.confirm) this.deleteAddress(item);
        },
      });
    },
    async deleteAddress(item) {
      if (!item || item.id == null) return;
      if (!promptLoginIfNeeded({ toast: '请先登录' })) return;
      const openid = this.getOpenid();
      if (!openid) return;
      this.actionLoading = true;
      try {
        const res = await requestUtil({
          url: '/order/takeout/address/delete',
          method: 'post',
          data: { openid, id: item.id },
          showLoading: true,
        });
        if (res && res.code === 0) {
          try {
            const sid = wx.getStorageSync('takeout_selected_address_id');
            if (sid != null && Number(sid) === Number(item.id)) {
              wx.removeStorageSync('takeout_selected_address_id');
              wx.removeStorageSync('takeout_selected_address');
            }
          } catch (e) {}
          wx.showToast({ title: '已删除', icon: 'success' });
          await this.loadList();
        } else {
          wx.showToast({ title: (res && res.msg) || '删除失败', icon: 'none' });
        }
      } catch (e) {
        wx.showToast({ title: '网络异常', icon: 'none' });
      } finally {
        this.actionLoading = false;
      }
    },
    selectRow(item) {
      const coordinate = validateGcj02Coordinates(item);
      if (!coordinate.valid) {
        wx.showModal({
          title: '请重新地图选点',
          content: coordinate.message,
          confirmText: '去编辑',
          success: (result) => {
            if (result.confirm) this.goEdit(item.id);
          },
        });
        return;
      }
      const normalized = normalizeTakeoutAddress(item);
      try {
        wx.setStorageSync('takeout_selected_address_id', normalized.id);
        wx.setStorageSync('takeout_selected_address', JSON.stringify(normalized));
      } catch (e) {}
      wx.navigateBack({ delta: 1 });
    },
    goEdit(id) {
      if (!promptLoginIfNeeded({ toast: '请先登录' })) {
        return;
      }
      const q = id != null ? '?id=' + encodeURIComponent(String(id)) : '';
      wx.navigateTo({
        url: '/packageOther/takeout-address/takeout-address-edit' + q,
      });
    },
  },
  onShow() {
    if (isLoggedIn()) {
      this.loadList();
    }
  },
};
</script>

<style scoped>
.page {
  min-height: 100vh;
  background: linear-gradient(180deg, #fff0eb 0%, #f5f5f7 200rpx, #ebebef 100%);
  padding-bottom: 160rpx;
  box-sizing: border-box;
}
.hero {
  padding: 40rpx 32rpx 28rpx;
}
.hero-title {
  display: block;
  font-size: 44rpx;
  font-weight: 800;
  color: #1a1a1a;
  letter-spacing: 1rpx;
}
.hero-sub {
  display: block;
  margin-top: 12rpx;
  font-size: 26rpx;
  color: #888;
}
.state-wrap {
  padding: 48rpx 32rpx;
}
.skeleton-list {
  display: flex;
  flex-direction: column;
  gap: 24rpx;
}
.sk-card {
  height: 160rpx;
  border-radius: 20rpx;
  background: linear-gradient(90deg, #eee 0%, #f5f5f5 40%, #eee 80%);
  background-size: 200% 100%;
  animation: sk 1.2s ease-in-out infinite;
}
@keyframes sk {
  0% {
    background-position: 100% 0;
  }
  100% {
    background-position: -100% 0;
  }
}
.state-text {
  display: block;
  text-align: center;
  margin-top: 24rpx;
  font-size: 26rpx;
  color: #999;
}
.empty-wrap {
  padding: 80rpx 48rpx 48rpx;
  text-align: center;
}
.empty-illu {
  width: 160rpx;
  height: 160rpx;
  margin: 0 auto 28rpx;
  border-radius: 48rpx;
  background: linear-gradient(145deg, #fff 0%, #ffe8e0 100%);
  display: flex;
  align-items: center;
  justify-content: center;
  box-shadow: 0 12rpx 40rpx rgba(225, 6, 6, 0.12);
}
.empty-icon {
  font-size: 72rpx;
}
.empty-title {
  display: block;
  font-size: 34rpx;
  font-weight: 700;
  color: #333;
}
.empty-desc {
  display: block;
  margin-top: 12rpx;
  font-size: 26rpx;
  color: #999;
  margin-bottom: 48rpx;
}
.btn-primary {
  width: 420rpx;
  height: 88rpx;
  line-height: 88rpx;
  border-radius: 44rpx;
  background: linear-gradient(90deg, #ff5117, #e10606);
  color: #fff;
  font-size: 30rpx;
  font-weight: 700;
  border: none;
  box-shadow: 0 12rpx 28rpx rgba(225, 6, 6, 0.25);
}
.list {
  max-height: calc(100vh - 220rpx);
  padding: 8rpx 24rpx 0;
  box-sizing: border-box;
}
.addr-card {
  position: relative;
  margin-bottom: 24rpx;
  border-radius: 22rpx;
  background: #fff;
  box-shadow: 0 8rpx 28rpx rgba(0, 0, 0, 0.06);
  border: 2rpx solid transparent;
  overflow: hidden;
}
.addr-card.active {
  border-color: #e10606;
  box-shadow: 0 8rpx 32rpx rgba(225, 6, 6, 0.15);
}
.check-mark {
  position: absolute;
  top: 0;
  right: 0;
  width: 56rpx;
  height: 56rpx;
  background: linear-gradient(135deg, #e10606, #ff5117);
  color: #fff;
  font-size: 28rpx;
  font-weight: 700;
  display: flex;
  align-items: center;
  justify-content: center;
  border-bottom-left-radius: 16rpx;
}
.card-inner {
  padding: 28rpx 28rpx 20rpx;
}
.row-top {
  display: flex;
  align-items: center;
  flex-wrap: wrap;
  gap: 12rpx 20rpx;
  margin-bottom: 16rpx;
}
.name {
  font-size: 32rpx;
  font-weight: 700;
  color: #222;
}
.phone {
  font-size: 28rpx;
  color: #666;
}
.badge-def {
  margin-left: auto;
  font-size: 22rpx;
  color: #e10606;
  border: 1rpx solid rgba(225, 6, 6, 0.45);
  padding: 4rpx 14rpx;
  border-radius: 999rpx;
  background: #fff5f2;
}
.addr-lines {
  display: flex;
  flex-wrap: wrap;
  align-items: flex-start;
  gap: 12rpx;
}
.tag-pill {
  flex-shrink: 0;
  font-size: 22rpx;
  color: #e10606;
  background: #fff0eb;
  padding: 4rpx 14rpx;
  border-radius: 8rpx;
}
.addr-text {
  flex: 1;
  min-width: 0;
  font-size: 28rpx;
  color: #555;
  line-height: 1.55;
}
.coord-error {
  display: block;
  margin-top: 12rpx;
  font-size: 23rpx;
  line-height: 1.45;
  color: #c2410c;
}
.row-actions {
  display: flex;
  justify-content: flex-end;
  gap: 28rpx;
  margin-top: 20rpx;
  padding-top: 20rpx;
  border-top: 1rpx solid #f2f2f4;
}
.link-btn {
  font-size: 26rpx;
  color: #888;
  padding: 8rpx 12rpx;
}
.link-btn.primary {
  color: #e10606;
  font-weight: 600;
}
.link-btn.danger {
  color: #e10606;
  font-weight: 500;
}
.bottom-pad {
  height: 120rpx;
}
.fab-wrap {
  position: fixed;
  left: 0;
  right: 0;
  bottom: 0;
  padding: 20rpx 32rpx calc(20rpx + env(safe-area-inset-bottom));
  background: linear-gradient(180deg, transparent 0%, rgba(245, 245, 247, 0.95) 30%, #f5f5f7 100%);
  pointer-events: none;
}
.btn-fab {
  pointer-events: auto;
  height: 92rpx;
  line-height: 92rpx;
  border-radius: 46rpx;
  background: linear-gradient(90deg, #ff5117, #e10606);
  color: #fff;
  font-size: 30rpx;
  font-weight: 700;
  border: none;
  box-shadow: 0 12rpx 32rpx rgba(225, 6, 6, 0.3);
}
.safe-bottom {
  height: env(safe-area-inset-bottom);
}
</style>
