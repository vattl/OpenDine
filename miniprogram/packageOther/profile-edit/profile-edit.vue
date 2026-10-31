<template>
  <view class="profile-edit-page">
    <view class="nav-bar" :style="{ paddingTop: statusBarHeight + 'px' }">
      <view class="nav-back" @click="goBack">
        <image class="nav-back-icon" :src="staticUrl('images/go-back.png')" mode="aspectFit" alt="返回"></image>
      </view>
      <view class="nav-title">完善资料</view>
    </view>
    <view class="edit-card" :style="{ marginTop: (navBarHeight + statusBarHeight) + 'px' }">
      <!-- 头像：点击头像即可更换 -->
      <view class="form-row">
        <view class="form-label">头像</view>
        <button class="avatar-tap" open-type="chooseAvatar" @chooseavatar="onChooseAvatar">
          <image class="avatar-img" :src="displayAvatarUrl" mode="aspectFill" @error="onAvatarError"></image>
        </button>
      </view>
      <!-- 昵称：左侧标题，右侧可编辑 -->
      <view class="form-row">
        <view class="form-label">昵称</view>
        <input class="form-input-right" v-model="form.name" placeholder="请输入昵称" maxlength="10" />
      </view>
      <!-- 手机号：仅展示（脱敏） -->
      <view class="form-row">
        <view class="form-label">手机号</view>
        <view class="form-value-right">{{ maskedPhone }}</view>
      </view>
      <!-- 生日：仅可设置一次，点击选择 -->
      <view class="form-row">
        <view class="form-label">生日</view>
        <picker
          v-if="!initialBirthday"
          mode="date"
          :value="form.birthday || ''"
          start="1900-01-01"
          :end="todayStr"
          @change="onBirthdayChange"
        >
          <view class="form-value-right form-picker">{{ form.birthday || '请选择（仅可设置一次）' }}</view>
        </picker>
        <view v-else class="form-value-right">{{ form.birthday }}</view>
      </view>
    </view>
    <view class="save-wrap">
      <button class="save-btn" @click="save">保存</button>
    </view>
  </view>
</template>

<script>
const app = getApp();
import { getBaseUrl, requestUtil } from "../../utils/requestUtil.js";
import { staticUrl } from "../../utils/staticAssetUrl.js";

export default {
  data() {
    return {
      form: { name: '', avatar: '', phone: '', birthday: '' },
      initialForm: { name: '', avatar: '', birthday: '' }, // 用于判断是否有修改
      initialBirthday: '',
      avatarLoadError: false,
      todayStr: '',
      statusBarHeight: 20,
      navBarHeight: 44
    };
  },
  computed: {
    isDirty() {
      return this.form.name !== this.initialForm.name ||
        this.form.avatar !== this.initialForm.avatar ||
        this.form.birthday !== this.initialForm.birthday;
    },
    displayAvatarUrl() {
      if (this.avatarLoadError) return staticUrl('images/default-avatar.png');
      const av = this.form.avatar;
      if (!av) return staticUrl('images/default-avatar.png');
      if (av.startsWith('http')) return av;
      return getBaseUrl().replace(/\/api$/, '') + (av.startsWith('/') ? av : '/' + av);
    },
    maskedPhone() {
      const phone = this.form.phone;
      if (!phone || typeof phone !== 'string') return '未绑定';
      const s = String(phone).trim();
      if (s.length >= 11) return s.slice(0, 3) + '****' + s.slice(-4);
      return s.length >= 7 ? s.slice(0, 3) + '****' + s.slice(-2) : s;
    }
  },
  onLoad() {
    const win = wx.getWindowInfo();
    this.statusBarHeight = win.statusBarHeight || 20;
    this.navBarHeight = 44;
    const y = new Date().getFullYear(), m = String(new Date().getMonth() + 1).padStart(2, '0'), d = String(new Date().getDate()).padStart(2, '0');
    this.todayStr = `${y}-${m}-${d}`;
    this.loadUser();
  },
  methods: {
    staticUrl,
    loadUser() {
      const openid = app.globalData.openid;
      if (!openid) {
        wx.showToast({ title: '请先登录', icon: 'none' });
        setTimeout(() => wx.navigateBack(), 1500);
        return;
      }
      const cached = app.globalData.userInfo;
      if (cached && (cached.openid || cached.avatar !== undefined || cached.name !== undefined)) {
        const f = {
          name: cached.name || cached.nickname || '',
          avatar: cached.avatar || '',
          phone: cached.phone || '',
          birthday: cached.birthday || ''
        };
        this.form = f;
        this.initialForm = { name: f.name, avatar: f.avatar, birthday: f.birthday || '' };
        this.initialBirthday = cached.birthday || '';
        return;
      }
      wx.showLoading({ title: '加载中', mask: true });
      requestUtil({ url: '/order/getUserInfo', method: 'post', data: { openid } })
        .then(res => {
          wx.hideLoading();
          if (res.code === 0 && res.data) {
            const d = res.data;
            const f = { name: d.name || '', avatar: d.avatar || '', phone: d.phone || '', birthday: d.birthday || '' };
            this.form = f;
            this.initialForm = { name: f.name, avatar: f.avatar, birthday: f.birthday || '' };
            this.initialBirthday = d.birthday || '';
          } else wx.showToast({ title: res.msg || '获取信息失败', icon: 'none' });
        })
        .catch(() => {
          wx.hideLoading();
          wx.showToast({ title: '加载失败', icon: 'none' });
        });
    },
    onChooseAvatar(e) {
      const { avatarUrl } = e.detail;
      if (!avatarUrl) return;
      this.avatarLoadError = false;
      this.form.avatar = avatarUrl;
      this.uploadAvatar(avatarUrl);
    },
    onAvatarError() {
      this.avatarLoadError = true;
    },
    uploadAvatar(tempPath) {
      const openid = app.globalData.openid;
      if (!openid) return;
      wx.showLoading({ title: '上传头像中...', mask: true });
      wx.uploadFile({
        url: getBaseUrl() + '/order/updateAvatar',
        filePath: tempPath,
        name: 'avatar',
        formData: { openid, phone: (app.globalData.userInfo && app.globalData.userInfo.phone) || '' },
        success: res => {
          wx.hideLoading();
          if (res.statusCode !== 200) {
            wx.showToast({ title: '服务器异常', icon: 'none' });
            return;
          }
          try {
            const data = JSON.parse(res.data || '{}');
            if (data.code === 0 && data.data && data.data.avatar) {
              let url = data.data.avatar;
              if (url && !url.startsWith('http')) {
                const base = getBaseUrl().replace(/\/api$/, '').replace(/\/$/, '');
                url = base + (url.startsWith('/') ? url : '/' + url);
              }
              this.form.avatar = url;
              if (app.globalData.userInfo) app.globalData.userInfo.avatar = url;
              wx.setStorageSync('userInfo', app.globalData.userInfo || this.form);
              wx.showToast({ title: '头像已更新', icon: 'success' });
            } else wx.showToast({ title: data.msg || '头像上传失败', icon: 'none' });
          } catch (err) {
            wx.showToast({ title: '头像上传失败', icon: 'none' });
          }
        },
        fail: () => {
          wx.hideLoading();
          wx.showToast({ title: '上传失败', icon: 'none' });
        }
      });
    },
    onBirthdayChange(e) {
      this.form.birthday = e.detail.value;
    },
    goBack() {
      if (!this.isDirty) {
        wx.navigateBack();
        return;
      }
      wx.showModal({
        title: '提示',
        content: '是否保存修改？',
        confirmText: '保存',
        cancelText: '不保存',
        success: (res) => {
          if (res.confirm) this.save();
          else if (res.cancel) wx.navigateBack();
        }
      });
    },
    save() {
      const openid = app.globalData.openid;
      if (!openid) {
        wx.showToast({ title: '请先登录', icon: 'none' });
        return;
      }
      const name = (this.form.name || '').trim();
      if (name.length < 1 || name.length > 10) {
        wx.showToast({ title: '昵称长度为 1～10 个字符', icon: 'none' });
        return;
      }
      const payload = { openid, name: name };
      if (this.form.birthday && !this.initialBirthday) payload.birthday = this.form.birthday;
      wx.showLoading({ title: '保存中...', mask: true });
      requestUtil({ url: '/order/updateUser', method: 'post', data: payload })
        .then(res => {
          wx.hideLoading();
          if (res.code === 0) {
            const u = { ...(app.globalData.userInfo || {}), name, avatar: this.form.avatar, phone: this.form.phone, birthday: this.form.birthday || (app.globalData.userInfo && app.globalData.userInfo.birthday) };
            app.globalData.userInfo = u;
            wx.setStorageSync('userInfo', u);
            this.initialForm = { name: this.form.name, avatar: this.form.avatar, birthday: this.form.birthday || '' };
            wx.showToast({ title: '保存成功', icon: 'success' });
            setTimeout(() => wx.navigateBack(), 1500);
          } else wx.showToast({ title: res.msg || '保存失败', icon: 'none' });
        })
        .catch(() => {
          wx.hideLoading();
          wx.showToast({ title: '保存失败', icon: 'none' });
        });
    }
  }
};
</script>

<style scoped>
.profile-edit-page { min-height: 100vh; background: #f5f5f5; padding: 30rpx 30rpx 120rpx; }
.edit-card { background: #fff; border-radius: 20rpx; padding: 0 32rpx; box-shadow: 0 6rpx 20rpx rgba(0,0,0,0.06); }
.form-row { display: flex; align-items: center; justify-content: space-between; min-height: 100rpx; border-bottom: 1rpx solid #f0f0f0; }
.form-row:last-child { border-bottom: none; }
.form-label { font-size: 30rpx; color: #333; flex-shrink: 0; }
.form-value-right { font-size: 30rpx; color: #333; text-align: right; }
.form-input-right { flex: 1; font-size: 30rpx; color: #333; text-align: right; margin-left: 24rpx; min-height: 80rpx; }
.form-picker { color: #999; }
.avatar-tap { padding: 0; margin: 0; background: none; border: none; line-height: 0; }
.avatar-tap::after { border: none; }
.avatar-img { width: 96rpx; height: 96rpx; border-radius: 50%; display: block; }
.save-wrap { margin-top: 48rpx; padding: 0 20rpx; }
.save-btn { background: #e74c3c; color: #fff; font-size: 32rpx; padding: 28rpx; border-radius: 80rpx; border: none; width: 100%; }
.nav-bar { position: fixed; top: 0; left: 0; right: 0; z-index: 999; height: 44px; background: #fefefe; display: flex; align-items: center; padding-left: 8px; padding-right: 16px; box-sizing: border-box; }
.nav-back { width: 80rpx; height: 88rpx; display: flex; align-items: center; justify-content: flex-start; margin-top: 90rpx;}
.nav-back-icon { width: 40rpx; height: 40rpx; }
.nav-title { flex: 1; text-align: center; font-size: 36rpx; color: #333; margin-right: 80rpx;margin-top: 90rpx; }
</style>
