<template>
  <view class="profile-page">
    <global-activity-popup ref="globalActivityPopup" />
    <!-- 顶部背景 -->
    <view class="top-bg"></view>
    
    <!-- 已登录状态内容 -->
    <view v-if="isLogin">
      <!-- 用户信息区域 -->
      <view class="user-info-card">
        <view class="avatar-container">
          <image 
            class="avatar" 
            :src="displayAvatarUrl" 
            mode="widthFix"
            alt="用户头像"
            @error="onAvatarLoadError"
          ></image>
          <button 
            class="edit-avatar" 
            open-type="chooseAvatar" 
            @chooseavatar="onChooseAvatar"
          >
            <image :src="staticUrl('images/edit_icon.png')" mode="widthFix" alt="编辑头像"></image>
          </button>
        </view>
        
        <view class="user-details">
          <view class="user-name" @click="handleNicknameClick">
            {{ userInfo.name || '设置昵称' }}
            <span v-if="!userInfo.name" class="edit_icon">✎</span>
          </view>
          <view class="user-phone">{{ maskedPhone }}</view>
        </view>
        <view class="complete-profile-wrap">
          <button class="complete-profile-btn" @click="goToProfileEdit">{{ profileComplete ? '编辑资料' : '完善资料' }}</button>
        </view>
      </view>
      
      <!-- 余额、优惠券、积分 -->
      <view class="stats-card">
        <navigator
          class="stats-item stats-item-balance stats-item-link"
          url="/packageOther/member-recharge/member-recharge"
          hover-class="stats-item-link-hover"
        >
          <view class="stats-value stats-balance">{{ balanceDisplay }}</view>
          <view class="stats-label">余额</view>
        </navigator>
        <view class="stats-divider"></view>
        <view class="stats-item" @click="goToCouponList">
          <view class="stats-value">{{ userInfo.couponCount || 0 }}</view>
          <view class="stats-label">优惠券</view>
        </view>
        <view class="stats-divider"></view>
        <view class="stats-item">
          <view class="stats-value">{{ userInfo.points || 0 }}</view>
          <view class="stats-label">积分</view>
        </view>
      </view>
      
      <!-- 功能菜单区域 -->
      <view class="function-menu">
        <!-- 其他功能 -->
        <view class="menu-section">
          <view class="menu-item" @click="goToAllOrders">
            <view class="menu-icon">
              <i class="fa fa-list-alt" aria-hidden="true"></i>
            </view>
            <view class="menu-text">我的订单</view>
            <view class="menu-arrow">
              <i class="fa fa-angle-right" aria-hidden="true"></i>
            </view>
          </view>
		  <view class="menu-item" @click="goToCouponList">
		    <view class="menu-icon">
		      <i class="fa fa-ticket" aria-hidden="true"></i>
		    </view>
		    <view class="menu-text">我的优惠券</view>
		    <view class="menu-arrow">
		      <i class="fa fa-angle-right" aria-hidden="true"></i>
		    </view>
		  </view>
		  <navigator class="menu-item menu-item-link" url="/packageOther/member-recharge/member-recharge" hover-class="menu-item-hover">
		    <view class="menu-icon">
		      <i class="fa fa-credit-card" aria-hidden="true"></i>
		    </view>
		    <view class="menu-text">会员充值</view>
		    <view class="menu-arrow">
		      <i class="fa fa-angle-right" aria-hidden="true"></i>
		    </view>
		  </navigator>
		  <!-- 新增：停车优惠入口 -->
		  <view class="menu-item" @click="goToParkDiscount">
		    <view class="menu-icon">
		      <i class="fa fa-car" aria-hidden="true"></i>
		    </view>
		    <view class="menu-text">停车优惠</view>
		    <view class="menu-arrow">
		      <i class="fa fa-angle-right" aria-hidden="true"></i>
		    </view>
		  </view>
		  <view class="menu-item" @click="goToOrderComment">
		    <view class="menu-icon">
		      <i class="fa fa-star" aria-hidden="true"></i>
		    </view>
		    <view class="menu-text">订单评价</view>
		    <view class="menu-arrow">
		      <i class="fa fa-angle-right" aria-hidden="true"></i>
		    </view>
		  </view>
		  <!-- 邀请好友入口 -->
		  <view class="menu-item" @click="goToInviteFriend">
		    <view class="menu-icon">
		      <i class="fa fa-share-alt" aria-hidden="true"></i>
		    </view>
		    <view class="menu-text">邀请好友</view>
		    <view class="menu-arrow">
		      <i class="fa fa-angle-right" aria-hidden="true"></i>
		    </view>
		  </view>
          <view class="menu-item" @click="goToAddressManagement">
            <view class="menu-icon">
              <i class="fa fa-map-marker" aria-hidden="true"></i>
            </view>
            <view class="menu-text">地址管理</view>
            <view class="menu-arrow">
              <i class="fa fa-angle-right" aria-hidden="true"></i>
            </view>
          </view>
          <view class="menu-item" @click="goToHelpCenter">
            <view class="menu-icon">
              <i class="fa fa-question-circle" aria-hidden="true"></i>
            </view>
            <view class="menu-text">帮助中心</view>
            <view class="menu-arrow">
              <i class="fa fa-angle-right" aria-hidden="true"></i>
            </view>
          </view>
          <view class="menu-item" @click="contactUs">
            <view class="menu-icon">
              <i class="fa fa-phone" aria-hidden="true"></i>
            </view>
            <view class="menu-text">联系我们</view>
            <view class="menu-arrow">
              <i class="fa fa-angle-right" aria-hidden="true"></i>
            </view>
          </view>
        </view>
      </view>
    </view>
    
    <!-- 未登录状态内容 -->
    <view v-else class="unlogin-container">
      <view class="login-prompt-card">
        <view class="login-illustration-wrap">
          <image :src="loginIllustrationSrc" mode="aspectFill" class="login-illustration" alt="请登录"></image>
        </view>
        <view class="login-title">请先登录</view>
        <view class="login-description">登录后可查看您的个人信息、订单历史和更多专属服务</view>
        <button class="login-button btn-primary" @click="handleLogin">立即登录</button>
      </view>
    </view>
    
    <!-- 手机号快速验证弹窗：可关闭/拒绝 -->
    <view class="confirm-modal" v-if="showPhoneModal">
      <view class="modal-mask" @click="closePhoneModal"></view>
      <view class="modal-content phone-modal-content">
        <view class="modal-close" @click="closePhoneModal">×</view>
        <view class="modal-title">绑定手机号</view>
        <view class="modal-message">绑定后即可接收订单通知、优惠提醒，账户更安全；您也可稍后在「完善资料」中设置。</view>
        <button
          class="phone-verification-btn"
          open-type="getPhoneNumber"
          @getphonenumber="onGetPhoneNumber"
        >
          一键验证并绑定
        </button>
        <view class="modal-buttons phone-modal-buttons">
          <button class="modal-btn cancel" @click="closePhoneModal">稍后再说</button>
        </view>
      </view>
    </view>
    
    <!-- 设置昵称弹窗 -->
    <view class="confirm-modal" v-if="showNicknameModal">
      <view class="modal-mask" @click="showNicknameModal = false"></view>
      <view class="modal-content">
        <view class="modal-title">设置昵称</view>
        <form @submit="onSubmitNickname">
          <view class="input-container">
            <input 
              type="nickname" 
              v-model="nicknameInput" 
              placeholder="请输入您的昵称"
              maxlength="10"
              @input="handleNicknameInput"
              @blur="onNicknameBlur"
              name="nickname"
            />
          </view>
          <view class="tips" v-if="showTips">
            {{ tipsText }}
          </view>
          <view class="modal-buttons">
            <button class="modal-btn cancel" @click="showNicknameModal = false">
              取消
            </button>
            <button 
              class="modal-btn confirm" 
              form-type="submit"
              :disabled="!isNicknameValid"
              :class="{ 'disabled-btn': !isNicknameValid }"
            >
              确认
            </button>
          </view>
        </form>
      </view>
    </view>
  </view>
</template>

<script>
import {getBaseUrl, requestUtil} from "../../utils/requestUtil.js";
import { formatBalanceForDisplay } from "../../utils/formatBalance.js";
import { staticUrl } from "../../utils/staticAssetUrl.js";
import { promptLoginIfNeeded } from "../../utils/loginGuard.js";
const app = getApp();

// 默认头像地址（微信官方默认头像）
const defaultAvatarUrl = 'https://mmbiz.qpic.cn/mmbiz/icTdbqWNOwNRna42FI242Lcia07jQodd2FJGIYQfG0LAJGFxM4FbnQP6yfMxBgJ0F3YRqJCJ1aPAK2dQagdusBZg/0';
// 停车优惠外链地址
const PARK_DISCOUNT_URL = 'https://qr.4pyun.com/discount?token=1156AC2846FA04790CE48D9715A8FF06';

export default {
  data() {
    return {
      // 用户信息
      userInfo: {
        avatar: '',      // 头像
        nickname: '',   // 昵称
        name: '',        // 昵称（与 API name 一致）
        phone: '',      // 手机号
        points: 0,       // 积分
        couponCount: 0,  // 可用优惠券数量（来自 getUserInfo）
        birthday: '',     // 生日 yyyy-MM-dd，仅可设置一次
        balance: 0        // 账户余额（元），来自 getUserInfo data.balance
      },
      isLogin: false,
      showLogoutModal: false,
      loginStatusChange: null,
      showPhoneModal: false,
      showNicknameModal: false,
      nicknameInput: '',
      isNicknameValid: false,
      isFirstLoginCheck: false,
      showTips: false,
      tipsText: '',
      avatarLoadError: false, // 头像图片加载失败时回退默认头像，避免变白
    };
  },
  computed: {
    // 用户头像完整地址，避免相对路径被解析到 127.0.0.1
    userAvatarUrl() {
      const av = this.userInfo && this.userInfo.avatar;
      if (!av) return staticUrl("images/default-avatar.png");
      if (av.startsWith("http://") || av.startsWith("https://")) return av;
      return getBaseUrl() + (av.startsWith("/") ? "" : "/") + av;
    },
    // 头像展示地址：加载失败时显示默认头像，避免变白
    displayAvatarUrl() {
      const defaultAvatar = staticUrl("images/default-avatar.png");
      if (this.avatarLoadError) return defaultAvatar;
      return this.userAvatarUrl || defaultAvatar;
    },
    loginIllustrationSrc() {
      return staticUrl("images/default-avatar.png");
    },
    // 手机号脱敏显示：前3后4，中间用 ****
    maskedPhone() {
      const phone = this.userInfo && this.userInfo.phone;
      if (!phone || phone === '未绑定手机' || typeof phone !== 'string') return '未绑定手机';
      const s = String(phone).trim();
      if (s.length >= 11) return s.slice(0, 3) + '****' + s.slice(-4);
      if (s.length >= 7) return s.slice(0, 3) + '****' + s.slice(-2);
      return s.length >= 4 ? s.slice(0, 2) + '****' : s || '未绑定手机';
    },
    // 用户资料是否完整：头像、昵称、手机、生日均有值
    profileComplete() {
      const u = this.userInfo;
      if (!u) return false;
      const hasAvatar = !!(u.avatar && u.avatar.trim());
      const hasName = !!(u.name && u.name.trim());
      const hasPhone = !!(u.phone && u.phone.trim() && u.phone !== '未绑定手机');
      const hasBirthday = !!(u.birthday && String(u.birthday).trim());
      return hasAvatar && hasName && hasPhone && hasBirthday;
    },
    balanceDisplay() {
      const u = this.userInfo;
      return formatBalanceForDisplay(u && u.balance);
    },
  },
  onLoad(option) {
    if (option && option.invite_code) app.globalData.invite_code = option.invite_code;
    this.checkLoginStatus();
  },
  async onShow() {
    if (typeof app.guardToQueueIfReview === "function") {
      const redirected = await app.guardToQueueIfReview();
      if (redirected) return;
    }
    // 每次显示时拉取最新用户信息（积分、优惠券等），保证数据实时
    this.refreshUserInfoFromServer();
  },
  onPullDownRefresh() {
    // 下拉刷新：重新拉取用户信息（积分、优惠券）
    this.refreshUserInfoFromServer().finally(() => {
      wx.stopPullDownRefresh();
    });
  },
  onUnload() {
    // 安全地移除事件监听
    if (this.loginStatusChange && app.event && typeof app.event.off === 'function') {
      app.event.off('loginStatusChange', this.loginStatusChange);
    }
  },
  
  methods: {
    staticUrl,
    // 从服务端拉取最新用户信息（积分、优惠券等），更新页面与 globalData
    refreshUserInfoFromServer() {
      if (this.isLogin && app.globalData.openid) {
        return app.getUserInfo().then(() => {
          if (app.globalData.userInfo) {
            this.userInfo = app.globalData.userInfo;
            this.avatarLoadError = false;
          }
        });
      }
      if (app.globalData.userInfo) {
        this.userInfo = app.globalData.userInfo;
        this.avatarLoadError = false;
      }
      return Promise.resolve();
    },
    // 纯 Vue + 微信小程序原生语法（无 uni-app 依赖）
    goToParkDiscount() {
      wx.navigateTo({
        url: "/packageOther/parking/parking",
      });
    },
    
    handleNicknameClick() {
      if (!this.userInfo.name) {
        this.getWechatUserInfo();
      } else {
        wx.showActionSheet({
          itemList: ['修改昵称', '使用微信昵称'],
          success: (res) => {
            if (res.tapIndex === 0) {
              this.goToSetNickname();
            } else if (res.tapIndex === 1) {
              this.getWechatUserInfo();
            }
          }
        });
      }
    },
    goToOrderComment() {
      wx.navigateTo({
        url: "/packageOther/order-comment/order-comment",
      });
    },
    // 邀请好友
    goToInviteFriend() {
      wx.navigateTo({
        url: "/packageOther/invite-friend/invite-friend",
      });
    },
    // 我的优惠券
    goToCouponList() {
      wx.navigateTo({
        url: "/packageOther/coupon-list/coupon-list?from=my",
      });
    },
    // 完善资料子页（头像、昵称可编辑，生日仅可设一次）
    goToProfileEdit() {
      wx.navigateTo({ url: '/packageOther/profile-edit/profile-edit' });
    },
    
    // 调用微信接口获取用户信息
    getWechatUserInfo() {
      wx.showLoading({
        title: '获取信息中...',
        mask: true
      });
      wx.getUserProfile({
        desc: '用于完善用户资料',
        success: (res) => {
          wx.hideLoading();
          const userInfo = res.userInfo;
          this.nicknameInput = userInfo.name;
          this.checkNicknameValidity();
          this.showNicknameModal = true;
          if (userInfo.avatarUrl && !this.userInfo.avatar) {
            this.userInfo.avatar = userInfo.avatarUrl;
            this.uploadAvatarToServer(userInfo.avatarUrl);
          }
		  wx.setStorageSync("userInfo",this.userInfo);
        },
        fail: (err) => {
          wx.hideLoading();
          if (err.errMsg.includes('auth deny')) {
            wx.showToast({title: '需要授权才能获取昵称',icon: 'none',duration: 2000});
            this.goToSetNickname();
          } else {
            console.error('获取微信用户信息失败', err);
            wx.showToast({title: '获取信息失败',icon: 'none'});
          }
        }
      });
    },
    
    // 微信头像选择回调
    onChooseAvatar(e) {
      const { avatarUrl } = e.detail;
      this.avatarLoadError = false;
      this.userInfo.avatar = avatarUrl;
      this.uploadAvatarToServer(avatarUrl);
    },
    // 头像图片加载失败时回退默认图，避免变白
    onAvatarLoadError() {
      this.avatarLoadError = true;
    },
    
    // 上传头像到服务器
    uploadAvatarToServer(tempPath) {
      if (!app.globalData.openid) {
        wx.showToast({title: '请先登录',icon: 'none'});
        return;
      }
      wx.showLoading({title: '上传头像中...',mask: true});
      wx.uploadFile({
        url: getBaseUrl() + '/order/updateAvatar',
        filePath: tempPath,
        name: 'avatar',
        formData: {openid: app.globalData.openid,phone: app.globalData.userInfo.phone || ''},
        success: (res) => {
          wx.hideLoading();
          if (res.statusCode !== 200) {
            console.error('上传请求失败，状态码:', res.statusCode);
            wx.showToast({title: '服务器异常',icon: 'none'});
            return;
          }
          try {
            if (!res.data) throw new Error('服务器返回空数据');
            if (res.data.trim().startsWith('<')) throw new Error('服务器返回非JSON数据');
            const data = JSON.parse(res.data);
            if (data.code === 0) {
              if (data.data && data.data.avatar) {
                let avatarUrl = data.data.avatar;
                if (avatarUrl && !avatarUrl.startsWith('http')) {
                  const baseUrl = getBaseUrl().replace(/\/api$/, '');
                  const normalizedBaseUrl = baseUrl.endsWith('/') ? baseUrl.slice(0, -1) : baseUrl;
                  const normalizedAvatarUrl = avatarUrl.startsWith('/') ? avatarUrl : `/${avatarUrl}`;
                  avatarUrl = normalizedBaseUrl + normalizedAvatarUrl;
                }
                this.avatarLoadError = false;
                this.userInfo.avatar = avatarUrl;
                wx.setStorageSync("userInfo",this.userInfo);
                if (app.globalData.userInfo) app.globalData.userInfo.avatar = avatarUrl;
                wx.showToast({title: '头像更新成功',icon: 'success'});
              } else throw new Error('未获取到头像URL');
            } else wx.showToast({title: data.msg || '头像上传失败',icon: 'none'});
          } catch (e) {
            console.error('解析头像上传结果失败', e, '返回内容:', res.data);
            wx.showToast({title: '头像上传失败',icon: 'none'});
          }
        },
        fail: (err) => {
          wx.hideLoading();
          console.error('头像上传失败', err);
          let errorMsg = '上传失败，请重试';
          if (err.errMsg && err.errMsg.includes('domain list')) {
            errorMsg = '请在小程序后台配置 uploadFile 合法域名';
          } else if (err.errMsg && err.errMsg.includes('timeout')) {
            errorMsg = '上传超时，请检查网络';
          } else if (err.errMsg && err.errMsg.includes('network')) {
            errorMsg = '网络异常，请稍后再试';
          } else if (err.errMsg && err.errMsg.includes('abort')) {
            errorMsg = '上传已取消';
          }
          wx.showToast({title: errorMsg, icon: 'none', duration: 2500});
        }
      });
    },
    
    // 提交昵称表单
    onSubmitNickname(e) {
        e.stopPropagation();
        const nickname = this.nicknameInput.trim();
        if (!nickname) {
			this.showTips = true;
			this.tipsText = '请输入昵称';
			return;
        }
        if (nickname.length < 1 || nickname.length > 10) {
          this.showTips =  true;
          this.tipsText = '昵称长度必须在1-10个字符之间';
		  return;
        }
        this.saveNickname(nickname);
      },
    
    // 保存昵称到服务器
    saveNickname(nickname) {
      const openid = app.globalData.openid?.trim();
      if (!openid) {
        wx.showToast({title: '登录状态异常，请重新登录',icon: 'none',duration: 2000});
        setTimeout(() => {this.handleLogin();}, 1500);
        return;
      }
      const trimmedNickname = nickname?.trim();
      if (!trimmedNickname || trimmedNickname.length < 1 || trimmedNickname.length > 10) {
        wx.showToast({title: '昵称长度必须在1-10个字符之间',icon: 'none'});
        return;
      }
      wx.showLoading({title: '保存中...',mask: true});
      requestUtil({
        url: '/order/updateUser',method: 'post',data: {openid: openid,name: trimmedNickname}
      }).then(res => {
        wx.hideLoading();
        if (res.code === 0) {
          wx.showToast({title: '昵称设置成功',icon: 'success'});
          this.userInfo.name = trimmedNickname;
          if (app.globalData.userInfo) app.globalData.userInfo.name = trimmedNickname;
          this.showNicknameModal = false;
        } else wx.showToast({title: res.msg || '保存失败',icon: 'none'});
      }).catch(err => {
        wx.hideLoading();
        console.error('保存昵称失败', err);
        let errorMsg = '网络错误';
        if (err.message.includes('timeout')) errorMsg = '请求超时，请重试';
        else if (err.message.includes('401')) {
          errorMsg = '登录已过期，请重新登录';
          setTimeout(() => {this.handleLogin();}, 1500);
        }
        wx.showToast({title: errorMsg,icon: 'none'});
      });
    },

    // 检查登录状态（轻量：优先用 globalData，避免同步 storage 阻塞首屏）
    checkLoginStatus() {
      this.isLogin = app.globalData.isLogin || false;
      const gUser = app.globalData.userInfo;
      if (!this.isLogin) {
        this.userInfo = {avatar: '',nickname: '',name: '',phone: '',points: 0,couponCount: 0,birthday: '',balance: 0};
        this.avatarLoadError = false;
        this.isFirstLoginCheck = false;
        return;
      }
      if (gUser) {
        const phone = gUser.phone;
        if (phone === null || phone === '') {
          this.showPhoneModal = true;
          this.loadUserInfo();
        } else {
          this.userInfo = gUser;
          this.avatarLoadError = false;
        }
      } else {
        this.loadUserInfo();
      }
    },
    
    // 登录
    handleLogin() {
      
      wx.showLoading({title: '登录中...',mask: true});
      app.wxLogin()
        .then((code) => {
          wx.hideLoading();
          if (app.globalData.isLogin && app.globalData.openid) {
            wx.showToast({title: '登录成功',icon: 'success',duration: 1500});
            this.isLogin = true;
            this.loadUserInfo();
          } else wx.showToast({title: '登录信息获取失败',icon: 'none',duration: 2000});
        })
        .catch((err) => {
          wx.hideLoading();
          console.error('登录失败:', err);
          let errorMsg = '登录失败，请重试';
          if (err.message.includes('获取openid失败')) errorMsg = '获取用户信息失败';
          else if (err.message.includes('网络')) errorMsg = '网络异常，请检查网络';
          wx.showToast({title: errorMsg,icon: 'none',duration: 2000});
        });
    },
    
    // 加载用户信息
    loadUserInfo() {
      if (app.globalData.openid) {
        this.fetchUserInfoByOpenid(app.globalData.openid)
		  .then(userInfo => {
			let avatar = userInfo.avatar || defaultAvatarUrl;
			if (avatar && !avatar.startsWith('http')) {
			  const baseUrl = getBaseUrl().replace(/\/api$/, '');
			  const normalizedBaseUrl = baseUrl.endsWith('/') ? baseUrl.slice(0, -1) : baseUrl;
			  const normalizedAvatarUrl = avatar.startsWith('/') ? avatar : `/${avatar}`;
			  avatar = normalizedBaseUrl + normalizedAvatarUrl;
			}
			const balRaw = userInfo.balance;
			const balNum = balRaw == null || balRaw === '' ? 0 : Number(balRaw);
			const balance = Number.isFinite(balNum) ? Math.round(balNum * 100) / 100 : 0;
			this.userInfo = {...userInfo, avatar, name: userInfo.name || userInfo.nickname || '', birthday: userInfo.birthday || '', couponCount: userInfo.couponCount != null ? userInfo.couponCount : 0, balance};
			this.avatarLoadError = false;
			app.globalData.userInfo = this.userInfo;
			wx.setStorageSync("userInfo",this.userInfo);
			this.checkFirstLogin();
      const phone = app.globalData.userInfo && app.globalData.userInfo.phone;
      const hasPhone = phone && String(phone).trim() && phone !== '未绑定手机';
      if (app.globalData.backUrl && hasPhone) {
        const targetUrl = app.globalData.backUrl;
        app.globalData.backUrl = "";
        const isTab = ['/pages/index/index', '/pages/home-page/page', '/pages/myorder/myorder', '/pages/my/my']
          .some(tab => targetUrl.startsWith(tab));
        if (isTab) {
          wx.switchTab({ url: targetUrl });
        } else {
          wx.navigateTo({
            url: targetUrl,
            fail: () => wx.reLaunch({ url: targetUrl })
          });
        }
      }
		  })
          .catch(err => {
            console.error('获取用户信息失败:', err);
            this.userInfo = {avatar: defaultAvatarUrl,nickname: '',name: '',phone: '',points: 0,couponCount: 0,birthday: '',balance: 0,openid: app.globalData.openid};
            this.avatarLoadError = false;
            this.checkFirstLogin();
          });

      }
    },
    
    // 检查首次登录
    checkFirstLogin() {
      if (!this.isFirstLoginCheck && (!this.userInfo.phone || this.userInfo.phone === '未绑定手机')) {
        this.isFirstLoginCheck = true;
        this.showPhoneModal = true;
      }
    },
    
    // 获取用户信息（与接口返回字段一致：avatar/birthday/couponCount/id/invite_code/level/name/openid/phone/points/time/user_type）
    fetchUserInfoByOpenid(openid) {
      return new Promise(async (resolve, reject) => {
        try {
          const response = await requestUtil({ url: "/order/getUserInfo", data: { openid }, method: "post" });
          if (response.code === 0) {
            const d = response.data || {};
            resolve({
              avatar: d.avatar || '',
              name: d.name || '',
              nickname: d.name || d.nickname || '',
              phone: d.phone || '',
              points: d.points != null ? d.points : 0,
              time: d.time,
              user_type: d.user_type,
              birthday: d.birthday || '',
              id: d.id,
              invite_code: d.invite_code || '',
              level: d.level,
              openid: d.openid || openid,
              couponCount: response.couponCount != null ? response.couponCount : (d.couponCount != null ? d.couponCount : 0),
              balance: (() => {
                const x = d.balance;
                if (x == null || x === "") return 0;
                const n = Number(x);
                return Number.isFinite(n) ? Math.round(n * 100) / 100 : 0;
              })(),
            });
          } else reject(new Error(`获取用户信息失败: ${response.msg || '未知错误'}`));
        } catch (error) {
          console.error('获取用户信息接口调用失败:', error);
          reject(error);
        }
      });
    },
    
    // 绑定手机号
    onGetPhoneNumber(e) {
      if (e.detail.code) {
        wx.showLoading({title: '绑定中...',mask: true});
        this.bindPhoneNumber(e.detail.code)
          .then(phone => {
            wx.hideLoading();
            this.userInfo.phone = phone;
            if (app.globalData.userInfo) app.globalData.userInfo.phone = phone;
            wx.setStorageSync("userInfo",this.userInfo);
            this.showPhoneModal = false;
            wx.showToast({title: '手机号绑定成功',icon: 'success'});
			if(app.globalData.backUrl){
				const targetUrl = app.globalData.backUrl;
				app.globalData.backUrl = "";
				const isTab = ['/pages/index/index', '/pages/home-page/page', '/pages/myorder/myorder', '/pages/my/my']
					.some(tab => targetUrl.startsWith(tab));
				if (isTab) {
					wx.switchTab({ url: targetUrl });
				} else {
					wx.navigateTo({
						url: targetUrl,
						fail: () => wx.reLaunch({ url: targetUrl })
					});
				}
			}
          })
          .catch(err => {
            wx.hideLoading();
            console.error('手机号绑定失败:', err);
            wx.showToast({title: '绑定失败，请重试',icon: 'none'});
          });
      } else {
        // 用户拒绝授权：不强制提示，可稍后在完善资料中绑定
        this.showPhoneModal = false;
      }
    },
    
    // 绑定手机号接口
    bindPhoneNumber(code) {
      return new Promise(async (resolve, reject) => {
        try {
          const response = await requestUtil({
            url: "/order/getOfficialPhoneNumber",
            data: { "openid": app.globalData.openid, "code": code,"invite_code":app.globalData.invite_code },method: "post"
          });
          if (response && response.data && response.data.phoneNumber) { 
            const phone = response.data.phoneNumber;
            resolve(phone);
          } else reject(new Error("后端未返回有效手机号"));
        } catch (error) { reject(error); }
      });
    },
    
    // 关闭绑定手机弹窗（遮罩/稍后再说/右上角×）
    closePhoneModal() {
      this.showPhoneModal = false;
    },
    
    // 设置昵称
    goToSetNickname() {
      this.nicknameInput = this.userInfo.name || '';
      this.checkNicknameValidity();
      this.showNicknameModal = true;
    },
    
    // 昵称输入处理
    handleNicknameInput(e) {
      this.nicknameInput = e.detail.value;
      this.checkNicknameValidity();
    },
    
    // 昵称失焦校验
    onNicknameBlur(e) {
      const value = e.detail.value.trim();
      this.nicknameInput = value;
      this.checkNicknameValidity();
      if (value.length > 0 && value.length < 1) {
        this.showTips = true;this.tipsText = '昵称长度不能少于1个字符';
      } else if (value.length > 10) {
        this.showTips = true;this.tipsText = '昵称长度不能超过10个字符';
      } else this.showTips = false;
    },
    
    // 昵称校验
    checkNicknameValidity() {
      const trimmed = this.nicknameInput.trim();
		this.isNicknameValid = trimmed.length >= 1 && trimmed.length <= 10;
		if (trimmed.length > 0 && trimmed.length < 1) {
		  this.showTips = true;this.tipsText = '昵称长度不能少于1个字符';
		} else if (trimmed.length > 10) {
		  this.showTips = true;this.tipsText = '昵称长度不能超过10个字符';
		} else this.showTips = false;
    },
    
    // 积分中心
    goToPointsCenter() {
      wx.showToast({ title: '积分商城建设中', icon: 'none' });
    },
    
    // 我的订单
    goToAllOrders() {
      wx.reLaunch({url: '/pages/myorder/myorder?status=all'});
    },
    
    // 地址管理（外卖收货地址）
    goToAddressManagement() {
      if (!promptLoginIfNeeded({ toast: "请先登录后管理地址" })) {
        return;
      }
      wx.navigateTo({
        url: "/packageOther/takeout-address/takeout-address?mode=manage",
      });
    },
    
    // 帮助中心
    goToHelpCenter() {
      wx.showToast({ title: '帮助中心建设中', icon: 'none' });
    },
    
    // 联系我们
    contactUs() {
      wx.showModal({
        title: '联系我们',content: "客服电话：15975017545\n工作时间：18:30-2:00",
        showCancel: false,confirmText: '拨打',
        success: (res) => {if (res.confirm) wx.makePhoneCall({phoneNumber: '15975017545'});}
      });
    }
    
  }
};
</script>

<style scoped>
/* 基础样式 */
.profile-page {
  background-color: #f5f5f5;
  min-height: 100vh;
  position: relative;
}

/* 顶部背景 */
.top-bg {
  position: absolute;
  top: 0;left: 0;right: 0;height: 240rpx;z-index: 1;
}

/* 用户信息卡片 */
.user-info-card {
  position: relative;z-index: 2;background-color: #fff;border-radius: 20rpx;
  margin: 50rpx 30rpx 30rpx;padding: 40rpx 30rpx;
  display: flex;align-items: center;gap: 30rpx;
}

/* 头像容器 */
.avatar-container {position: relative;width: 160rpx;height: 160rpx;}
.avatar {width:100%;height:100%;border-radius:50%;border:5rpx solid #fff;box-shadow:0 5rpx15rpx rgba(0,0,0,0.1);}
.edit-avatar {position:absolute;bottom:0;right:0;width:40rpx;height:40rpx;background:#fff;border-radius:50%;display:flex;align-items:center;justify-content:center;box-shadow:0 2rpx8rpx rgba(0,0,0,0.15);padding:0;margin:0;border:none;}
.edit-avatar image {width:24rpx;height:24rpx;}

/* 用户详情 */
.user-details {flex:1;min-width:0;display:flex;flex-direction:column;gap:15rpx;}
.user-name {font-size:36rpx;font-weight:bold;color:#333;display:inline-flex;align-items:center;gap:8rpx;cursor:pointer;}
.user-name:not(.has-nickname) {color:#f7ba1e;}
.user-name .edit_icon {font-size:24rpx;color:#f7ba1e;}
.user-phone {font-size:28rpx;color:#666;}
.complete-profile-wrap {flex-shrink:0;}
.complete-profile-btn {background:#e74c3c;color:#fff;font-size:22rpx;padding:8rpx 20rpx;border-radius:20rpx;border:none;}

/* 积分与优惠券独立卡片 */
.stats-card {
  position:relative;z-index:2;margin:24rpx 30rpx 0;padding:28rpx 32rpx;
  background:#fff;border-radius:20rpx;
  display:flex;align-items:center;justify-content:space-around;
}
.stats-item {flex:1;text-align:center;min-width:0;}
.stats-item-balance {padding:0 4rpx;}
.stats-item-link {text-decoration:none;color:inherit;box-sizing:border-box;}
.stats-item-link-hover {opacity:0.88;}
.stats-value {font-size:40rpx;font-weight:bold;color:#e74c3c;}
.stats-balance {font-size:30rpx;word-break:break-all;}
.stats-label {font-size:26rpx;color:#999;margin-top:8rpx;}
.stats-divider {width:1px;height:48rpx;background:#eee;flex-shrink:0;}

/* 功能菜单 */
.function-menu {position:relative;z-index:2;padding:030rpx;display:flex;flex-direction:column;gap:30rpx;}
.menu-section {background:#fff;border-radius:20rpx;overflow:hidden;box-shadow:05rpx15rpx rgba(0,0,0,0.05);}
.menu-item {display:flex;align-items:center;padding:30rpx;border-bottom:1px solid #f5f5f5;}
.menu-item-link {text-decoration:none;color:inherit;}
.menu-item-hover {background:#fafafa;}
.menu-item:last-child {border-bottom:none;}
.menu-icon {width:40rpx;height:40rpx;font-size:36rpx;color:#f7d45f;display:flex;align-items:center;justify-content:center;margin-right:25rpx;}
.menu-text {flex:1;font-size:30rpx;color:#333;}
.menu-arrow {font-size:36rpx;color:#ddd;}

/* 退出登录项 */
.logout-item {background:#fff8f8;}
.logout-icon {color:#f5222d;}
.logout-text {color:#f5222d;}

/* 未登录状态 */
.unlogin-container {position:relative;z-index:2;padding:160rpx 30rpx 60rpx;}
.login-prompt-card {
  border-radius:24rpx;padding:56rpx 40rpx 48rpx;
  text-align:center;
  overflow:hidden;
}
.login-illustration-wrap {
  width:220rpx;height:220rpx;margin:0 auto 36rpx;
  background:linear-gradient(145deg,#fff5f5 0%,#ffe8e8 100%);
  border-radius:50%;overflow:hidden;
}
.login-illustration {width:100%;height:100%;display:block;}
.login-title {font-size:40rpx;font-weight:bold;color:#1a1a1a;margin-bottom:16rpx;letter-spacing:1rpx;}
.login-description {font-size:28rpx;color:#666;line-height:1.7;margin-bottom:48rpx;padding:0 24rpx;}
.login-button {font-size:32rpx;font-weight:500;padding:28rpx 0;border-radius:70rpx;width:100%;max-width:400rpx;margin:0 auto;border:none;}
.btn-primary {background:#e74c3c;color:#fff;}
.unlogin-functions {display:flex;justify-content:center;gap:60rpx;margin-top:40rpx;flex-wrap: wrap;}
.unlogin-function-item {display:flex;flex-direction:column;align-items:center;color:#666;font-size:26rpx;gap:10rpx;margin:0 10rpx;}
.unlogin-function-item i {font-size:40rpx;color:#e74c3c;}

/* 弹窗样式 */
.confirm-modal {position:fixed;top:0;left:0;right:0;bottom:0;z-index:999;display:flex;align-items:center;justify-content:center;}
.modal-mask {position:absolute;top:0;left:0;right:0;bottom:0;background:rgba(0,0,0,0.5);}
.modal-content {position:relative;width:600rpx;background:#fff;border-radius:20rpx;padding:40rpx;display:flex;flex-direction:column;gap:30rpx;}
.phone-modal-content {padding:50rpx 30rpx 30rpx;position:relative;}
.modal-close {position:absolute;top:20rpx;right:20rpx;width:50rpx;height:50rpx;display:flex;align-items:center;justify-content:center;font-size:40rpx;color:#999;}
.modal-title {font-size:34rpx;font-weight:bold;color:#333;text-align:center;}
.modal-message {font-size:28rpx;color:#666;text-align:center;padding:10rpx 0;line-height:1.5;}
.modal-buttons {display:flex;gap:20rpx;margin-top:20rpx;}
.phone-modal-buttons {justify-content:center;margin-top:24rpx;}
.modal-btn {flex:1;padding:20rpx0;font-size:30rpx;border-radius:15rpx;border:none;}
.modal-btn.cancel {background:#f5f5f5;color:#666;}
.modal-btn.confirm {background:#e74c3c;color:#fff;opacity:1;}
.modal-btn.confirm:disabled {opacity:0.6;}

/* 手机号验证按钮（统一红色） */
.phone-verification-btn {background:#e74c3c;color:#fff;font-size:30rpx;padding:20rpx0;border-radius:15rpx;width:100%;margin:10rpx0;border:none;}
.modal-footer {font-size:24rpx;color:#999;text-align:center;margin-top:10rpx;}

/* 昵称输入框 */
.input-container {padding:010rpx;}
.input-container input {width:100%;height:80rpx;border:1px solid #eee;border-radius:10rpx;padding:020rpx;font-size:30rpx;}
.tips {font-size:26rpx;color:#ff4d4f;padding-left:10rpx;height:30rpx;}
</style>