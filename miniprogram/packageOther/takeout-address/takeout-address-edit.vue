<template>
  <view class="page">
    <view class="hero">
      <text class="hero-title">{{ id ? '编辑地址' : '新增地址' }}</text>
      <text class="hero-desc">请先地图选点定位，再填写门牌号与联系人</text>
    </view>

    <view class="card map-card" @click="pickOnMap">
      <view class="map-row">
        <view class="map-icon-wrap">
          <text class="map-icon">📍</text>
        </view>
        <view class="map-texts">
          <text class="map-title">{{ hasMapLocation ? '重新地图选点' : '地图选址（必选）' }}</text>
          <text class="map-sub">{{ hasMapLocation ? '点击可更换定位' : '打开地图搜索小区、大厦、街道等' }}</text>
        </view>
        <text class="map-arrow">›</text>
      </view>
    </view>

    <view v-if="hasMapLocation" class="card location-card">
      <view class="sec-title">已选位置</view>
      <text class="loc-poi">{{ poiName || '地图选点' }}</text>
      <text class="loc-region">{{ regionDisplayLine }}</text>
      <text v-if="mapAddress" class="loc-place">{{ mapAddress }}</text>
      <view class="coord-hint ok">GCJ-02 坐标已确认，可用于配送距离计算</view>
    </view>

    <view v-if="hasMapLocation" class="card fine-tune-card">
      <view class="sec-title">微调配送入口</view>
      <view class="map-stage">
        <map
          id="delivery-address-map"
          class="fine-tune-map"
          :latitude="Number(lat)"
          :longitude="Number(lng)"
          :scale="18"
          :show-location="false"
          @regionchange="onMapRegionChange"
        >
          <cover-view class="center-pin">📍</cover-view>
        </map>
      </view>
      <text class="fine-tune-tip">拖动地图，把定位针放到小区、商场、园区或医院的实际配送入口。</text>
      <text v-if="pinAdjusted" class="fine-tune-updated">坐标已更新；门牌与配送说明已保留</text>
      <button class="refresh-place" @click="pickOnMap">重新确认附近地址名称</button>
    </view>

    <view v-if="hasMapLocation && qualityWarnings.length" class="card quality-card">
      <text v-for="warning in qualityWarnings" :key="warning" class="quality-warning">{{ warning }}</text>
    </view>

    <view v-if="hasMapLocation" class="card form-card">
      <view class="sec-title">门牌号 / 楼层补充</view>
      <view class="field no-border">
        <input
          v-model="form.doorplate"
          placeholder="如 3栋201、A座12楼、南门旁等"
          class="inp doorplate-inp"
          maxlength="80"
        />
        <text class="field-tip">在地图点位基础上补充，便于骑手准确送达</text>
      </view>

      <view class="sec-title">配送入口说明</view>
      <view class="field no-border">
        <textarea
          v-model="form.delivery_note"
          placeholder="如 骑手从南门进入、门禁联系前台"
          class="inp delivery-note-inp"
          maxlength="120"
          :show-confirm-bar="false"
        />
        <text class="field-tip">仅填写入口、门禁或前台说明，不要填写联系人电话</text>
      </view>

      <view class="sec-title">联系人</view>
      <view class="field">
        <text class="lab">姓名</text>
        <input v-model="form.contact_name" placeholder="怎么称呼您" class="inp" maxlength="16" />
      </view>
      <view class="field">
        <text class="lab">手机号</text>
        <input v-model="form.contact_phone" type="number" maxlength="11" placeholder="11位手机号码" class="inp" />
      </view>

      <view class="sec-title">地址标签</view>
      <view class="tag-row">
        <view
          v-for="t in tagOptions"
          :key="t"
          class="tag-chip"
          :class="{ on: form.tag === t }"
          @click="pickTag(t)"
        >
          {{ t }}
        </view>
      </view>
    </view>

    <view v-else class="card hint-card">
      <text class="hint-text">完成地图选址后，可填写门牌号、联系人与手机号</text>
    </view>

    <view v-if="hasMapLocation" class="card switch-card">
      <view class="switch-row">
        <view>
          <text class="switch-title">设为默认地址</text>
          <text class="switch-sub">下单时优先使用该地址</text>
        </view>
        <switch :checked="form.is_default === 1" @change="onDefChange" color="#e10606" />
      </view>
    </view>

    <view class="footer">
      <button class="save" :loading="saving" :disabled="!hasMapLocation" @click="save">保存地址</button>
    </view>
    <view class="safe-bottom"></view>
  </view>
</template>

<script>
import { requestUtil } from '../../utils/requestUtil.js';
import { isLoggedIn } from '../../utils/loginGuard.js';
import { buildDetailFromPlaceParts } from '../../utils/takeoutAddressRegion.js';
import { chooseLocationWithAuth, classifyLocationError } from '../../utils/locationAuth.js';
import { distanceKm } from '../../utils/geoDistance.js';
import {
  buildLocationDiagnostic,
  buildStoredDetail,
  getAddressQualityWarnings,
  parseStoredDetail,
  validateGcj02Coordinates,
} from '../../utils/takeoutAddress.js';

const app = getApp();

export default {
  data() {
    return {
      id: null,
      saving: false,
      tagOptions: ['家', '公司', '学校', '其他'],
      poiName: '',
      mapAddress: '',
      pinAdjusted: false,
      distanceFromCurrentKm: null,
      currentLocationCoordinate: null,
      form: {
        contact_name: '',
        contact_phone: '',
        province: '',
        city: '',
        district: '',
        doorplate: '',
        delivery_note: '',
        tag: '家',
        is_default: 0,
      },
      lat: null,
      lng: null,
    };
  },
  onLoad(options) {
    if (!isLoggedIn()) {
      wx.showToast({ title: '请先登录', icon: 'none' });
      wx.navigateBack({ delta: 1 });
      return;
    }
    const raw = options && options.id;
    if (raw != null && String(raw).trim() !== '') {
      this.id = Number(raw);
    }
    const user = app.globalData.userInfo || wx.getStorageSync('userInfo') || {};
    if (user.phone && !this.form.contact_phone) this.form.contact_phone = String(user.phone).trim();
    if (user.nickName && !this.form.contact_name) this.form.contact_name = String(user.nickName).slice(0, 16);
    if (this.id) this.loadOne();
  },
  onReady() {
    if (typeof wx !== 'undefined' && typeof wx.createMapContext === 'function') {
      this.addressMapContext = wx.createMapContext('delivery-address-map', this);
    }
  },
  computed: {
    hasRegion() {
      return !!(this.form.province && this.form.city && this.form.district);
    },
    regionDisplayLine() {
      const p = [this.form.province, this.form.city, this.form.district].filter(Boolean);
      return p.length ? p.join(' ') : '';
    },
    hasValidCoords() {
      return validateGcj02Coordinates({ lat: this.lat, lng: this.lng }).valid;
    },
    hasMapLocation() {
      return this.hasValidCoords && !!(this.poiName || this.mapAddress);
    },
    qualityWarnings() {
      if (!this.hasMapLocation) return [];
      const warnings = getAddressQualityWarnings({
        poiName: this.poiName,
        mapAddress: this.mapAddress,
        detail: this.form.doorplate,
        distanceFromCurrentKm: this.distanceFromCurrentKm,
      });
      if (this.pinAdjusted) {
        warnings.unshift('定位针已移动，请确认地图上的附近地址与实际配送入口一致');
      }
      return warnings;
    },
  },
  methods: {
    showLocationHint(message) {
      const now = Date.now();
      if (this.lastLocationHintAt && now - this.lastLocationHintAt < 10000) return;
      this.lastLocationHintAt = now;
      wx.showToast({ title: message, icon: 'none', duration: 2200 });
    },
    pickTag(t) {
      this.form.tag = t;
    },
    onDefChange(e) {
      this.form.is_default = e.detail.value ? 1 : 0;
    },
    buildSavedDetailAddress() {
      return buildStoredDetail({
        poiName: this.poiName,
        mapAddress: this.mapAddress,
        detail: this.form.doorplate,
        deliveryNote: this.form.delivery_note,
      });
    },
    logLocationDiagnostic(source, accuracy = null) {
      console.info('[takeout-address-location]', buildLocationDiagnostic({
        source,
        accuracy,
        lat: this.lat,
        lng: this.lng,
      }));
    },
    captureCurrentLocationQualityContext() {
      if (typeof wx === 'undefined' || typeof wx.getLocation !== 'function') return;
      wx.getLocation({
        type: 'gcj02',
        success: (position) => {
          const current = validateGcj02Coordinates({
            lat: position && position.latitude,
            lng: position && position.longitude,
          });
          if (!current.valid) return;
          this.currentLocationCoordinate = { lat: current.lat, lng: current.lng };
          this.distanceFromCurrentKm = distanceKm(current.lat, current.lng, this.lat, this.lng);
          console.info('[takeout-address-location]', buildLocationDiagnostic({
            source: 'getLocation',
            accuracy: position.accuracy,
            lat: current.lat,
            lng: current.lng,
          }));
        },
        fail: (error) => {
          console.warn('[takeout-address-location-failure]', {
            source: 'getLocation',
            error_type: classifyLocationError(error),
          });
        },
      });
    },
    locationFailureMessage(result) {
      const type = result && result.errorType;
      if (type === 'permission_denied') return '未授予定位权限，请在设置中开启后重试';
      if (type === 'service_disabled') return '手机定位服务未开启，请开启后重试';
      if (type === 'network_error') return '网络异常，暂时无法打开地图选点';
      return '地图选点失败，请稍后重试';
    },
    applyMapPick(res) {
      const name = (res.name || '').trim();
      const addr = (res.address || '').trim();
      const coordinate = validateGcj02Coordinates({ lat: res.latitude, lng: res.longitude });
      if (!coordinate.valid) {
        this.showLocationHint(coordinate.message);
        return false;
      }
      const part = buildDetailFromPlaceParts({ name, address: addr });
      if (part.province) {
        this.form.province = part.province;
        this.form.city = part.city;
        this.form.district = part.district;
      }
      this.poiName = name || part.detail_address || addr;
      const mapDetail = part.detail_address || addr;
      this.mapAddress = name && mapDetail.indexOf(name) === 0
        ? mapDetail.slice(name.length).trim()
        : mapDetail;
      this.lat = coordinate.lat;
      this.lng = coordinate.lng;
      this.pinAdjusted = false;
      this.logLocationDiagnostic('chooseLocation', res.accuracy);
      this.captureCurrentLocationQualityContext();
      return true;
    },
    onMapRegionChange(e) {
      const eventType = (e && e.detail && e.detail.type) || (e && e.type) || '';
      if (eventType !== 'end') return;
      if (!this.addressMapContext || typeof this.addressMapContext.getCenterLocation !== 'function') return;
      this.addressMapContext.getCenterLocation({
        success: (position) => {
          const coordinate = validateGcj02Coordinates({
            lat: position && position.latitude,
            lng: position && position.longitude,
          });
          if (!coordinate.valid) {
            this.showLocationHint(coordinate.message);
            return;
          }
          this.lat = coordinate.lat;
          this.lng = coordinate.lng;
          this.pinAdjusted = true;
          if (this.currentLocationCoordinate) {
            this.distanceFromCurrentKm = distanceKm(
              this.currentLocationCoordinate.lat,
              this.currentLocationCoordinate.lng,
              coordinate.lat,
              coordinate.lng
            );
          }
          this.logLocationDiagnostic('mapPin');
        },
      });
    },
    confirmAddressQuality() {
      if (!this.qualityWarnings.length) return Promise.resolve(true);
      return new Promise((resolve) => {
        wx.showModal({
          title: '请确认配送位置',
          content: this.qualityWarnings.join('\n'),
          cancelText: '返回调整',
          confirmText: '仍然保存',
          success: (result) => resolve(!!result.confirm),
          fail: () => resolve(false),
        });
      });
    },
    async pickOnMap() {
      const result = await chooseLocationWithAuth({
        latitude: this.lat,
        longitude: this.lng,
        purposeHint: '地图选址需要获取您的位置权限，以便在地图上快速定位您的收货地址并准确计算配送费。',
      });

      if (result.success && result.data) {
        if (this.applyMapPick(result.data)) {
          wx.showToast({ title: '已选定位置', icon: 'success', duration: 1200 });
        }
      } else if (!result.success && !result.userCancelled) {
        this.showLocationHint(this.locationFailureMessage(result));
      }
    },
    async loadOne() {
      const openid = app.globalData.openid || wx.getStorageSync('openid');
      if (!openid) return;
      try {
        const res = await requestUtil({
          url: '/order/takeout/address/list',
          method: 'get',
          data: { openid },
          showLoading: true,
        });
        const list =
          res && res.code === 0
            ? (() => {
                const raw = res.data != null ? res.data : res;
                const arr = (raw && (raw.list || raw.records)) || [];
                return Array.isArray(arr) ? arr : [];
              })()
            : [];
        const row = list.find((x) => Number(x.id) === Number(this.id));
        if (row) {
          this.form = {
            contact_name: row.contact_name || '',
            contact_phone: row.contact_phone || '',
            province: row.province || '',
            city: row.city || '',
            district: row.district || '',
            doorplate: '',
            delivery_note: '',
            tag: row.tag || '家',
            is_default: row.is_default === true || row.is_default === 1 ? 1 : 0,
          };
          const la = row.lat != null ? Number(row.lat) : null;
          const ln = row.lng != null ? Number(row.lng) : null;
          this.lat = Number.isFinite(la) ? la : null;
          this.lng = Number.isFinite(ln) ? ln : null;
          const region = [row.province, row.city, row.district].filter(Boolean).join(' ');
          const detail = String(row.detail_address || '').trim();
          const parsed = parseStoredDetail(detail);
          this.poiName = row.poi_name || parsed.poiName || detail || region;
          this.mapAddress = row.address || parsed.mapAddress || region;
          this.form.doorplate = row.detail || parsed.detail || '';
          this.form.delivery_note = row.delivery_note || parsed.deliveryNote || '';
          if (!this.hasValidCoords || !this.hasRegion) {
            wx.showToast({ title: '请重新地图选点', icon: 'none', duration: 2200 });
          }
        }
      } catch (e) {}
    },
    async save() {
      const phone = String(this.form.contact_phone || '').trim();
      const door = String(this.form.doorplate || '').trim();
      if (!/^1\d{10}$/.test(phone)) {
        wx.showToast({ title: '请填写正确手机号', icon: 'none' });
        return;
      }
      if (!this.hasMapLocation) {
        wx.showModal({
          title: '请先地图选址',
          content: '请使用地图选择收货位置，再填写门牌号与联系人信息。',
          confirmText: '去选点',
          success: (r) => {
            if (r.confirm) this.pickOnMap();
          },
        });
        return;
      }
      const coordinate = validateGcj02Coordinates({ lat: this.lat, lng: this.lng });
      if (!coordinate.valid) {
        wx.showToast({ title: coordinate.message, icon: 'none', duration: 2500 });
        return;
      }
      if (!door) {
        wx.showToast({ title: '请填写门牌号或楼层补充', icon: 'none' });
        return;
      }
      const detail = this.buildSavedDetailAddress();
      if (!detail) {
        wx.showToast({ title: '请填写门牌号或楼层补充', icon: 'none' });
        return;
      }
      if (!isLoggedIn()) {
        wx.showToast({ title: '请先登录', icon: 'none' });
        return;
      }
      if (detail.length > 255) {
        wx.showToast({ title: '地址补充内容过长，请精简后再保存', icon: 'none', duration: 2800 });
        return;
      }
      if (!(await this.confirmAddressQuality())) return;
      const openid = app.globalData.openid || wx.getStorageSync('openid');
      this.saving = true;
      try {
        const body = {
          openid,
          contact_name: String(this.form.contact_name || '').trim() || '用户',
          contact_phone: phone,
          province: this.form.province || '',
          city: this.form.city || '',
          district: this.form.district || '',
          detail_address: detail,
          tag: this.form.tag || '',
          is_default: this.form.is_default ? 1 : 0,
          lat: coordinate.lat,
          lng: coordinate.lng,
          coordinate_type: 'gcj02',
        };
        if (this.id) body.id = this.id;
        const res = await requestUtil({
          url: '/order/takeout/address/save',
          method: 'post',
          data: body,
        });
        if (res && res.code === 0) {
          const newId =
            (res.data && (res.data.id || res.data.address_id)) ||
            res.id ||
            res.address_id ||
            this.id;
          if (newId != null) {
            try {
              wx.setStorageSync('takeout_selected_address_id', newId);
              wx.setStorageSync('takeout_selected_address', JSON.stringify({
                ...body,
                id: newId,
                poi_name: this.poiName,
                address: this.mapAddress,
                detail: door,
                delivery_note: String(this.form.delivery_note || '').trim(),
              }));
            } catch (e) {}
          }
          wx.showToast({ title: '已保存', icon: 'success' });
          setTimeout(() => wx.navigateBack({ delta: 1 }), 400);
        } else {
          wx.showToast({ title: (res && res.msg) || '保存失败', icon: 'none' });
        }
      } catch (e) {
        wx.showToast({ title: '网络异常', icon: 'none' });
      } finally {
        this.saving = false;
      }
    },
  },
};
</script>

<style scoped>
.page {
  min-height: 100vh;
  background: linear-gradient(180deg, #fff0eb 0%, #f5f5f7 220rpx, #f5f5f7 100%);
  padding: 0 24rpx 40rpx;
  box-sizing: border-box;
}
.hero {
  padding: 36rpx 8rpx 28rpx;
}
.hero-title {
  display: block;
  font-size: 40rpx;
  font-weight: 700;
  color: #1a1a1a;
  letter-spacing: 1rpx;
}
.hero-desc {
  display: block;
  margin-top: 12rpx;
  font-size: 26rpx;
  color: #888;
  line-height: 1.45;
}
.card {
  background: #fff;
  border-radius: 20rpx;
  box-shadow: 0 8rpx 32rpx rgba(225, 6, 6, 0.06);
  margin-bottom: 24rpx;
  overflow: hidden;
}
.map-card {
  padding: 0;
}
.map-row {
  display: flex;
  align-items: center;
  padding: 28rpx 24rpx;
  gap: 20rpx;
}
.map-icon-wrap {
  width: 88rpx;
  height: 88rpx;
  border-radius: 20rpx;
  background: linear-gradient(135deg, #ffe8e0 0%, #ffd4c8 100%);
  display: flex;
  align-items: center;
  justify-content: center;
  flex-shrink: 0;
}
.map-icon {
  font-size: 44rpx;
}
.map-texts {
  flex: 1;
  min-width: 0;
}
.map-title {
  display: block;
  font-size: 30rpx;
  font-weight: 600;
  color: #333;
}
.map-sub {
  display: block;
  margin-top: 8rpx;
  font-size: 24rpx;
  color: #999;
  line-height: 1.4;
}
.map-arrow {
  font-size: 44rpx;
  color: #ccc;
  font-weight: 300;
  flex-shrink: 0;
}
.location-card {
  padding: 8rpx 28rpx 24rpx;
}
.loc-region {
  display: block;
  font-size: 28rpx;
  font-weight: 600;
  color: #333;
  line-height: 1.45;
}
.loc-poi {
  display: block;
  font-size: 32rpx;
  font-weight: 700;
  color: #222;
  line-height: 1.45;
  margin-bottom: 8rpx;
}
.loc-place {
  display: block;
  margin-top: 10rpx;
  font-size: 26rpx;
  color: #666;
  line-height: 1.5;
}
.fine-tune-card {
  padding: 8rpx 24rpx 24rpx;
}
.map-stage {
  position: relative;
  height: 360rpx;
  overflow: hidden;
  border-radius: 16rpx;
}
.fine-tune-map {
  width: 100%;
  height: 100%;
}
.center-pin {
  position: absolute;
  left: 50%;
  top: 50%;
  width: 64rpx;
  height: 80rpx;
  margin-left: -32rpx;
  margin-top: -72rpx;
  font-size: 52rpx;
  line-height: 80rpx;
  text-align: center;
}
.fine-tune-tip,
.fine-tune-updated {
  display: block;
  margin-top: 16rpx;
  font-size: 23rpx;
  line-height: 1.5;
  color: #777;
}
.fine-tune-updated {
  color: #16803a;
}
.refresh-place {
  margin-top: 18rpx;
  height: 72rpx;
  line-height: 72rpx;
  border-radius: 36rpx;
  border: 2rpx solid rgba(225, 6, 6, 0.28);
  background: #fff7f4;
  color: #d92314;
  font-size: 25rpx;
}
.quality-card {
  padding: 24rpx 28rpx;
  background: #fffaf0;
  border: 2rpx solid #f3d08b;
}
.quality-warning {
  display: block;
  font-size: 24rpx;
  line-height: 1.55;
  color: #855b12;
}
.quality-warning + .quality-warning {
  margin-top: 8rpx;
}
.coord-hint {
  margin-top: 16rpx;
  font-size: 22rpx;
  line-height: 1.45;
}
.coord-hint.ok {
  color: #16a34a;
}
.hint-card {
  padding: 32rpx 28rpx;
}
.hint-text {
  font-size: 26rpx;
  color: #999;
  line-height: 1.5;
  text-align: center;
}
.form-card {
  padding: 8rpx 0 16rpx;
}
.sec-title {
  padding: 28rpx 28rpx 12rpx;
  font-size: 24rpx;
  font-weight: 600;
  color: #999;
  letter-spacing: 2rpx;
}
.field {
  padding: 20rpx 28rpx;
  border-bottom: 1rpx solid #f2f2f4;
}
.field.no-border {
  border-bottom: none;
}
.field-tip {
  display: block;
  margin-top: 10rpx;
  font-size: 22rpx;
  color: #aaa;
  line-height: 1.4;
}
.doorplate-inp {
  min-height: 52rpx;
}
.delivery-note-inp {
  width: 100%;
  min-height: 112rpx;
  line-height: 1.5;
}
.lab {
  display: block;
  font-size: 24rpx;
  color: #999;
  margin-bottom: 8rpx;
}
.inp {
  font-size: 30rpx;
  color: #222;
  min-height: 44rpx;
}
.tag-row {
  display: flex;
  flex-wrap: wrap;
  gap: 16rpx;
  padding: 8rpx 28rpx 20rpx;
}
.tag-chip {
  padding: 14rpx 32rpx;
  border-radius: 999rpx;
  font-size: 26rpx;
  color: #666;
  background: #f5f5f7;
  border: 2rpx solid transparent;
}
.tag-chip.on {
  color: #e10606;
  background: #fff5f2;
  border-color: rgba(225, 6, 6, 0.35);
  font-weight: 600;
}
.switch-card {
  padding: 28rpx;
}
.switch-row {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 24rpx;
}
.switch-title {
  display: block;
  font-size: 30rpx;
  font-weight: 600;
  color: #333;
}
.switch-sub {
  display: block;
  margin-top: 8rpx;
  font-size: 24rpx;
  color: #999;
}
.footer {
  margin-top: 16rpx;
  padding: 0 8rpx;
}
.save {
  height: 96rpx;
  line-height: 96rpx;
  background: linear-gradient(90deg, #ff5117, #f0331a, #e10606);
  color: #fff;
  border-radius: 48rpx;
  font-size: 32rpx;
  font-weight: 700;
  border: none;
  box-shadow: 0 12rpx 28rpx rgba(225, 6, 6, 0.28);
}
.save[disabled] {
  opacity: 0.45;
  box-shadow: none;
}
.safe-bottom {
  height: env(safe-area-inset-bottom);
  min-height: 20rpx;
}
</style>
