<template>
  <view class="container">
    
	<!-- 底层轮播图背景 (最底层) -->
	<view class="brand-header">
	  <swiper 
	    class="brand-swiper" 
	    autoplay 
	    circular 
	    indicator-dots 
	    indicator-color="rgba(255,255,255,0.5)"
	    indicator-active-color="#ffffff"
		interval="3000"
	  >
	    <swiper-item v-for="(item, index) in (adImages || [])" :key="index">
	      <view class="brand-swiper-item" @click="handleCarouselClick(item)">
	        <image 
	          class="brand-illustration" 
	          :src="getAdItemImageUrl(item)" 
	          mode="aspectFill"
	          :lazy-load="index > 0"
	          alt="广告图片"
	        ></image>
	      </view>
	    </swiper-item>
	  </swiper>
	</view>
	<view class="main-area">
		<view class="operation-area">
			<image
			  class="operation-OldFat" 
			  src="https://www.laofei.com.cn/image/img/OldFatOilKing.png" 
			  mode="widthFix"
			></image>
			<view class="brand-slogan">
				<!-- 品牌标语 -->
				<view>吃油边,认准老肥油边王</view>
				<!-- 全部订单入口 -->
				<view class="all-orders" @click="goToMyOrder" >
				  全部订单 >
				</view>
			</view>
			<!-- 核心操作区：审核态仅显示排队取号 -->
			<view class="main-operation-area">
			  <view class="operation-card" v-if="!IsReview">
			    <!-- 堂食选项 -->
			    <view 
			      class="operation-item" 
			      :class="{ active: orderType === 'dinein' }"
			      @click="switchOrderType('dinein')"
			    >
			      <image 
			        class="operation-dinein" 
			        src="https://www.laofei.com.cn/image/img/dinein.png" 
			        mode="widthFix"
			        alt="堂食图标"
			      ></image>
				  
				  <view class="operation-text-main">
					  <view class="operation-text">堂食</view>
					  <view class="operation-desc">现场用餐更便捷</view>
				  </view>
			      
			    </view>
			    <view class="divider-line"></view>
			    <!-- 打包选项 -->
			    <view 
			      class="operation-item" 
			      :class="{ active: orderType === 'takeaway' }"
			      @click="switchOrderType('takeaway')"
			    >
			      <image 
			        class="operation-takeaway" 
			        src="https://www.laofei.com.cn/image/img/takeaway.png" 
			        mode="widthFix"
			        alt="打包图标"
			      ></image>
				  <view class="operation-text-main">
					  <view class="operation-text">打包</view>
					  <view class="operation-desc">提前下单更省时</view>
				  </view>
			    </view>
			</view>
			  <view class="operation-card operation-card-review" v-else>
				<view class="operation-item operation-item-review" @click="goToQueueTicket">
				  <view class="operation-text-main">
					  <view class="operation-text">排队取号</view>
					  <view class="operation-desc">高峰期先取号，减少等待</view>
				  </view>
				</view>
			  </view>
			</view>

			<!-- 会员信息区域 -->
			<view class="member-info-area" v-if="memberInfo">
			  <view class="member-card">
			    <!-- 会员头像 -->
			    <image 
			      class="member-avatar" 
			      :src="memberAvatarUrl" 
			      mode="widthFix"
			      alt="会员头像"
			    ></image>
			    <!-- 会员名称 -->
			    <view class="member-name-container">
			      <view class="member-name">{{ memberInfo.name || '老肥油边王' }}
				  <image
				    class="lv-icon" 
				    src="https://www.laofei.com.cn/image/img/lv-ico.png" 
				    mode="widthFix"
				    alt="图标"
					v-if="false"
				  ></image>
				  </view>
			      <view class="member-tag" v-if="memberInfo.user_type == 1">老肥会员</view>
			    </view>
				
			    <view class="member-stats-row">
			      <view class="member-data-coupons" @click="goToCouponList">
			        <view class="data-value">{{ memberInfo.couponCount || 0 }}</view>
			        <view class="data-label">优惠券</view>
			      </view>
			      <navigator
			        class="member-data-balance member-stats-link"
			        url="/packageOther/member-recharge/member-recharge"
			        hover-class="member-stats-link-hover"
			      >
			        <view class="data-value data-value-balance">{{ memberBalanceDisplay }}</view>
			        <view class="data-label">余额</view>
			      </navigator>
			      <view class="member-data-points">
			        <view class="data-value">{{ memberInfo.points || 0 }}</view>
			        <view class="data-label">积分</view>
			      </view>
			    </view>
			  </view>
			</view>
			
			<!-- 中部轮播图（契约：POST /activity/popupList，type: page_activity） -->
			<view class="index-popup-area" v-if="indexPopupList.length > 0">
			  <swiper
			    class="index-popup-swiper"
			    autoplay
			    circular
			    indicator-dots
			    indicator-color="rgba(255,255,255,0.5)"
			    indicator-active-color="#b32424"
			    interval="3000"
			  >
			    <swiper-item v-for="(item, index) in indexPopupList" :key="index">
			      <view class="index-popup-item" @click="handleIndexPopupClick(item)">
			        <image
			          class="index-popup-img"
			          :src="item.imageUrl"
			          mode="aspectFill"
			          :lazy-load="index > 0"
			        ></image>
			      </view>
			    </swiper-item>
			  </swiper>
			</view>
		</view>
		
		<!-- 底部操作按钮（扫码点餐） -->
		<view class="bottom-actions" v-if="orderType === 'dinein' && !IsReview">
		  <button class="scan-btn" @click="scanCode">
		    <image 
		      class="scan-icon" 
		      :src="staticUrl('icons/scan.png')" 
		      mode="widthFix"
		      alt="扫码图标"
		    ></image>
		    <view class="scan-text">扫码点餐</view>
		  </button>
		</view>
		
		<global-activity-popup ref="globalActivityPopup" />

		<!-- 加载中提示 -->
		<view class="loading-mask" v-if="isLoading">
		  <view class="loading-content">
		    <uni-load-more type="loading" color="#b32424"></uni-load-more>
		  </view>
		</view>

		<!-- 兑换成功弹窗（参考领取成功视觉：图标 + 主副标题 + 规则胶囊条 + 主按钮） -->
		<view class="redeem-modal" v-if="showRedeemModal">
		  <view class="redeem-mask"></view>
		  <view class="redeem-panel" @tap.stop>
		    <view class="redeem-icon-section">
		      <view class="redeem-confetti">
		        <view class="redeem-confetti-dot c1"></view>
		        <view class="redeem-confetti-dot c2"></view>
		        <view class="redeem-confetti-dot c3"></view>
		        <view class="redeem-confetti-dot c4"></view>
		        <view class="redeem-confetti-arc a1"></view>
		        <view class="redeem-confetti-arc a2"></view>
		      </view>
		      <view class="redeem-success-circle">
		        <text class="redeem-check-mark">✓</text>
		      </view>
		    </view>
		    <view class="redeem-main-title">领取成功</view>
		    <view class="redeem-subtitle">
		      <text>{{ redeemCouponInfo.coupon_name || '优惠券' }}有效期至{{ formatRedeemValidDate(redeemCouponInfo.expire_time) }}</text>
		    </view>
		    <view class="redeem-notice-bar">
		      <text class="redeem-notice-icon">ⓘ</text>
		      <text class="redeem-notice-text">{{ redeemNoticeText }}</text>
		    </view>
		    <view class="redeem-ok-btn" @tap="closeRedeemModal">我知道了</view>
		  </view>
		</view>
		
	</view>
    
  </view>
</template>

<script>
const app = getApp();
import { getBaseUrl, requestUtil } from "../../utils/requestUtil.js";
import {
  setCurrentShop,
  sortShopsForDisplay,
  getCurrentShopId,
  markShopBoundFromQr,
} from "../../utils/shopContext.js";
import { activityCarouselStorageKey } from "../../utils/activityCarouselCache.js";
import { parseTableNumberFromMergedQuery } from "../../utils/tableQrParse.js";
import { formatBalanceForDisplay } from "../../utils/formatBalance.js";
import { staticUrl } from "../../utils/staticAssetUrl.js";
import {
  activityPopupImageUrl,
  advertisingImageUrlDetail,
  avatarImageUrl,
  imgAssetUrl,
  IMAGE_Q_DETAIL,
  IMAGE_Q_LIST,
  pickActivityPopupImage,
  preloadImages,
} from "../../utils/imageUrl.js";
import {
  getValidDinersCount,
  buildHomePageDineInQuery,
} from "../../utils/dinersCache.js";

export default {
  data() {
    return {
	  adImages: null,
      /** 首页轮播缓存按门店隔离，切店后 onShow 会刷新 */
      bannerShopId: 0,
      indexPopupList: [], // 中部轮播（POST /activity/popupList type: page_activity）
      orderType: "takeaway", // 默认选择打包
      isLoading: false,
      table_number: "",
      OrderStatus: false,
      // 会员信息
      memberInfo: {
        isMember: true,
        couponCount: 0,
        balance: 0,
        points: 0,
	  },
	  showRedeemModal: false,
	  redeemCouponInfo: {},
	  IsReview: false
    };
  },
  computed: {
    // 会员头像完整地址，避免相对路径被解析到 127.0.0.1
    memberAvatarUrl() {
      const av = this.memberInfo && this.memberInfo.avatar;
      return avatarImageUrl(av, imgAssetUrl("member-avatar.png"));
    },
    /** 兑换成功弹窗底部胶囊条文案：优先规则说明，否则用类型+折扣兜底 */
    redeemNoticeText() {
      const c = this.redeemCouponInfo || {};
      const rule = String(c.description || "").trim();
      if (rule) return rule;
      const discount = this.getCouponDiscountText(c);
      const type = this.getRedeemCouponTypeDisplay(c);
      const parts = [];
      if (type && type !== "-") parts.push(type);
      if (discount && discount !== "-") parts.push(discount);
      if (parts.length) return parts.join("，");
      return "请在有效期内使用，具体规则以门店说明为准";
    },
    memberBalanceDisplay() {
      return formatBalanceForDisplay(this.memberInfo && this.memberInfo.balance);
    },
  },
  methods: {
    staticUrl,
    /** 从扫码路径或落地页参数解析 shop_id（餐桌二维码：...?number=1&shop_id=2） */
    parseShopIdFromAny(raw) {
      if (raw === undefined || raw === null) return null;
      const s = String(raw).trim();
      if (!s) return null;
      const m = s.match(/(?:^|[?&])shop_id=(\d+)/i);
      if (m) return Number(m[1]);
      return null;
    },
    /** 从扫码路径解析桌号（与 App / 点餐页一致，支持 D02、table= 等） */
    parseTableNumberFromAny(raw) {
      return parseTableNumberFromMergedQuery(raw);
    },
    async applyShopFromQr(shopId) {
      const id = Number(shopId);
      if (!Number.isFinite(id) || id <= 0) return;
      try {
        const res = await requestUtil({
          url: "/shop/list",
          method: "get",
          showLoading: false,
        });
        if (!res || res.code !== 0 || !Array.isArray(res.list)) {
          wx.showToast({ title: "门店列表获取失败", icon: "none" });
          return;
        }
        const shops = sortShopsForDisplay(res.list);
        const hit = shops.find((s) => Number(s.id) === id);
        if (!hit) {
          wx.showToast({ title: "门店不存在或未营业", icon: "none" });
          return;
        }
        markShopBoundFromQr(hit);
        const sid = Number(getCurrentShopId()) || 0;
        if (sid !== Number(this.bannerShopId)) {
          this.bannerShopId = sid;
          this.getBanner(true);
          this.loadIndexPopupList();
        }
      } catch (e) {
        console.error("applyShopFromQr", e);
        wx.showToast({ title: "绑定门店失败", icon: "none" });
      }
    },
  // 我的优惠券
  goToCouponList() {
      wx.navigateTo({
        url: "/packageOther/coupon-list/coupon-list?from=my",
      });
  },    
	// 从服务端拉取最新用户信息，更新会员卡片（积分、优惠券）
	refreshMemberInfo() {
	  if (app.globalData.openid) {
	    return app.getUserInfo().then(() => {
	      if (app.globalData.userInfo) this.memberInfo = { ...this.memberInfo, ...app.globalData.userInfo };
	    });
	  }
	  if (app.globalData.userInfo) this.memberInfo = { ...this.memberInfo, ...app.globalData.userInfo };
	  return Promise.resolve();
	},
    // 刷新审核态：true 仅展示“排队取号”；false 展示堂食/打包
    async refreshReviewFlag(force = false) {
      try {
        if (typeof app.fetchReviewMode === "function") {
          this.IsReview = !!(await app.fetchReviewMode(!!force));
        } else {
          this.IsReview = !!(app.globalData && app.globalData.isReviewMode);
        }
      } catch (e) {
        this.IsReview = !!(app.globalData && app.globalData.isReviewMode);
      }
      if (this.IsReview && typeof app.guardToQueueIfReview === "function") {
        await app.guardToQueueIfReview({ skipFetch: true });
      }
    },
	getUrl(image) {
	  return advertisingImageUrlDetail(image);
	},
	getAdItemImageUrl(item) {
	  if (!item) return imgAssetUrl("brand-header.jpg", IMAGE_Q_DETAIL);
	  if (item.imageUrl) return item.imageUrl;
	  const url = activityPopupImageUrl(item, IMAGE_Q_DETAIL);
	  return url || imgAssetUrl("brand-header.jpg", IMAGE_Q_DETAIL);
	},
	getCouponTypeName(type) {
	  const t = String(type || "").toLowerCase();
	  if (t === "discount") return "折扣券";
	  if (t === "full_reduction") return "满减券";
	  if (t === "direct_reduction") return "立减券";
	  return "优惠券";
	},
	// 兑换弹窗：优先用接口返回的 type_label / typeLabel
	getRedeemCouponTypeDisplay(coupon) {
	  if (!coupon) return "-";
	  const pre = String(coupon.type_label || "").trim();
	  if (pre) return pre;
	  return this.getCouponTypeName(coupon.coupon_type);
	},
	getCouponDiscountText(coupon) {
	  if (!coupon) return "-";
	  const pre = String(coupon.discount_text || "").trim();
	  if (pre) return pre;
	  const type = String(coupon.coupon_type || "").toLowerCase();
	  const value = Number(coupon.discount_value || 0);
	  const minAmount = Number(coupon.min_amount || 0);
	  if (type === "discount") {
	    return value > 0 ? `${(value / 10).toFixed(1)}折${minAmount > 0 ? `（满${minAmount}元）` : ""}` : "-";
	  }
	  if (type === "full_reduction") {
	    return minAmount > 0 ? `满${minAmount}减${value}` : `减${value}`;
	  }
	  if (type === "direct_reduction") {
	    return `立减${value}`;
	  }
	  return value > 0 ? `${value}` : "-";
	},
	normalizeRedeemCouponInfo(res = {}) {
	  const nested = (res && (res.data || res.coupon || res.coupon_info || res.result)) || {};
	  const top = res && typeof res === "object" ? res : {};
	  const info = { ...top, ...nested };
	  return {
	    coupon_name: info.coupon_name || info.couponName || info.name || "",
	    expire_time:
	      info.expire_time ||
	      info.end_time ||
	      info.valid_until ||
	      info.validUntil ||
	      "",
	    coupon_type: info.coupon_type || info.type || "",
	    type_label: info.type_label || info.typeLabel || "",
	    discount_text: info.discount_text || info.discountText || "",
	    description:
	      info.description ||
	      info.rule ||
	      info.rule_text ||
	      info.ruleText ||
	      "",
	    discount_value: info.discount_value ?? info.value ?? 0,
	    min_amount: info.min_amount ?? info.minAmount ?? 0
	  };
	},
	closeRedeemModal() {
	  this.showRedeemModal = false;
	},
	/** 有效期展示为 YYYY.MM.DD（与参考 UI 一致） */
	formatRedeemValidDate(raw) {
	  if (raw === undefined || raw === null || String(raw).trim() === "") return "-";
	  const s = String(raw).trim();
	  const m = s.match(/^(\d{4})-(\d{2})-(\d{2})/);
	  if (m) return `${m[1]}.${m[2]}.${m[3]}`;
	  const m2 = s.match(/^(\d{4})\/(\d{1,2})\/(\d{1,2})/);
	  if (m2) {
	    const y = m2[1];
	    const mo = m2[2].length === 1 ? "0" + m2[2] : m2[2];
	    const d = m2[3].length === 1 ? "0" + m2[3] : m2[3];
	    return `${y}.${mo}.${d}`;
	  }
	  return s;
	},
	// 通过兑换码领取优惠券（openapi: GET /coupon/redeem）
	async redeemCouponByCode(rawCode) {
	  const redeemCode = String(rawCode || "").trim();
	  if (!redeemCode) return;
	  const openid = app.globalData.openid || wx.getStorageSync("openid") || "";
	  const userInfo = app.globalData.userInfo || wx.getStorageSync("userInfo") || {};
	  const phone = userInfo && userInfo.phone ? String(userInfo.phone).trim() : "";
	  const data = { redeem_code: redeemCode };
	  if (openid) {
	    data.openid = openid;
	  } else if (phone) {
	    data.phone = phone;
	  }
	  try {
	    const res = await requestUtil({
	      url: "/coupon/redeem",
	      data,
	      method: "get",
	      showLoading: false,
	    });
	    if (res && res.code === 0) {
		  this.redeemCouponInfo = this.normalizeRedeemCouponInfo(res);
		  this.showRedeemModal = true;
	      this.refreshMemberInfo();
	    } else {
	      wx.showToast({
	        title: (res && (res.msg || res.message)) || "兑换失败",
	        icon: "none"
	      });
	    }
	  } catch (e) {
	    wx.showToast({ title: "兑换失败，请重试", icon: "none" });
	  }
	},
	// 轮播图点击事件 - 处理跳转
	handleCarouselClick(item) {
	  this.calculateFinishTime();		
	  if (!item.url) return; // 没有链接则不执行操作
	  
	  // 根据链接类型选择不同的跳转方式
	  if (item.url.startsWith('http')) {
	    wx.setClipboardData({
	      data: item.url,
	      success: () => {
	        wx.showToast({ title: '链接已复制，请在浏览器中打开', icon: 'none', duration: 2500 });
	      }
	    });
	  } else {
	    // 内部页面直接跳转
	    wx.navigateTo({
	      url: item.url
	    });
	  }
	},  
    // 切换订单类型（堂食/打包）
    async switchOrderType(type) {
      this.orderType = type;
      if (type === 'dinein') {
        const redirected = await this.checkOrderStatus();
        if (redirected) return;
        if (!this.OrderStatus) {
          this.navigateToSelectNumberForDineIn();
        }
      } else {
        this.navigateToHomePage('打包');
      }
    },

    /** 堂食：15 分钟内已选人数则直达点餐页，否则进入选人数页 */
    navigateToSelectNumberForDineIn() {
      const cached = getValidDinersCount(app);
      const tn = this.table_number ? String(this.table_number).trim() : '';
      if (cached != null) {
        wx.reLaunch({
          url: `/pages/home-page/page?${buildHomePageDineInQuery({
            diners: cached,
            tableNumber: tn,
          })}`,
        });
        return;
      }
      wx.navigateTo({
        url: `/packageOther/select_number/select_number?number=${encodeURIComponent(tn)}`,
      });
    },

    // 跳转首页并传递订单类型（打包等）
    navigateToHomePage(type) {
      wx.reLaunch({
        url: `/pages/home-page/page?dineInOrTakeOut=${encodeURIComponent(type)}`
      });
    },
    goToQueueTicket() {
      wx.reLaunch({
        url: "/packageOther/queue-ticket/queue-ticket",
      });
    },
	goToMyOrder(){
	  wx.reLaunch({
        url: `/pages/myorder/myorder`
      });
	},
    // 检查订单状态
    async checkOrder() {
      this.isLoading = true;
      let res = { goods_list: [] };
      try {
        if (this.table_number) {
          res = await requestUtil({
            url: "/order/get",
            data: { table_number: this.table_number, transac_status: "unsettled" },
            method: "get"
          });
        }
        const list = res && res.goods_list;
        this.OrderStatus = Array.isArray(list) ? list.length > 0 : false;
        
      } catch (e) {
        console.error("检查订单状态失败:", e);
        this.OrderStatus = false;
      } finally {
        this.isLoading = false;
      }
    },
	async calculateFinishTime(){
		const res = await requestUtil({
		  url: "/order/calculateFinishTime",
		  data: { dineInOrTakeOut: "堂食" },
		  method: "post"
		});
		console.log(res);
	},
    /**
     * 检查订单状态；有未结账订单时跳转订单详情。
     * @returns {Promise<boolean>} 已发起跳转订单详情时为 true，调用方不应再继续导航
     */
    async checkOrderStatus() {
      if (!this.table_number || !String(this.table_number).trim()) {
        this.OrderStatus = false;
        return false;
      }
      try {
        await this.verifyTableNumber();
        await this.checkOrder();

        if (this.OrderStatus) {
          wx.reLaunch({
            url: `/packageOther/order-details/details?table_number=${this.table_number}`
          });
          return true;
        }
        return false;
      } catch (e) {
        console.error("检查订单失败:", e);
        wx.showToast({
          title: "检查订单失败",
          icon: "none"
        });
        return false;
      }
    },
	
    // 验证台号
    async verifyTableNumber() {
      try {
        const res = await requestUtil({
          url: "/order/table_verify",
          data: { number: this.table_number },
          method: "get"
        });
        return res.code === 0;
      } catch (e) {
        console.error("验证台号失败:", e);
        return false;
      }
    },
	async getBanner(force = false) {
		try {
		  const cacheKey = activityCarouselStorageKey("adImages");
		  if (!force) {
		    const cached = app.getStorageWithExpiry(cacheKey);
		    if (cached != null) {
		      this.adImages = cached;
		      this._preloadBannerImages(cached);
		      return;
		    }
		  }
		  const res = await requestUtil({
		    url: "/activity/popupList",
		    method: "post",
		    data: { type: "home_top" },
		    showLoading: false,
		  });
		  if (res.code === 0) {
		    this.adImages = res.activity;
		    app.setStorageWithExpiry(cacheKey, this.adImages);
		    this._preloadBannerImages(this.adImages);
		  } else {
		    wx.showToast({
		      title: "获取轮播图失败",
		      icon: "none",
		    });
		  }
		} catch (e) {
		  console.log(e);
		  wx.showToast({
		    title: "获取轮播图失败",
		    icon: "none",
		  });
		}
	},
	// 中部轮播（契约：POST /activity/popupList，type: page_activity，body 含 activity: ActivityPopup[]）
	_preloadBannerImages(list) {
	  const urls = (list || [])
	    .slice(0, 2)
	    .map((item) => this.getAdItemImageUrl(item))
	    .filter(Boolean);
	  preloadImages(urls, { max: 2, concurrency: 2 });
	},
	async loadIndexPopupList() {
	  try {
	    const res = await requestUtil({
	      url: "/activity/popupList",
	      method: "post",
	      data: { openid: app.globalData.openid || undefined, type: "home_bottom" },
	      
	    });
	    if (res && res.code === 0 && Array.isArray(res.activity) && res.activity.length > 0) {
	      this.indexPopupList = res.activity
	        .filter((a) => pickActivityPopupImage(a))
	        .map((a) => ({
	          ...a,
	          imageUrl: activityPopupImageUrl(a, IMAGE_Q_LIST),
	        }))
	        .filter((a) => a.imageUrl);
	      preloadImages(
	        this.indexPopupList.slice(0, 2).map((a) => a.imageUrl),
	        { max: 2, concurrency: 2 }
	      );
	    }
	  } catch (e) {
	    console.error("获取中部轮播失败:", e);
	  }
	},
	handleIndexPopupClick(item) {
	  if (!item.url) return;
	  if (item.url.startsWith("http")) {
	    wx.setClipboardData({
	      data: item.url,
	      success: () => {
	        wx.showToast({ title: '链接已复制，请在浏览器中打开', icon: 'none', duration: 2500 });
	      }
	    });
	  } else {
	    wx.navigateTo({ url: item.url });
	  }
	},
    // 扫码点餐
    scanCode() {
      app.scanCode({
        onSuccess: async (res) => {
          console.log("扫码结果:", res);
          const rawResult = res.result || res.path || "";
          if (!rawResult) {
            wx.showToast({
              title: "扫码内容无效",
              icon: "none"
            });
            return;
          }
          const merged = [res.path, res.result, rawResult].filter(Boolean).join(" ");
          const sid = this.parseShopIdFromAny(merged);
          if (sid != null) await this.applyShopFromQr(sid);
          const numFromQuery = parseTableNumberFromMergedQuery(merged);
          const rawTrim = String(rawResult || "").trim();
          this.table_number =
            numFromQuery || (rawTrim && !/[?&]/.test(rawTrim) ? rawTrim : "");
          wx.setStorageSync("table_number", this.table_number);
          app.setStorageWithExpiry("table_number", this.table_number);
          this.checkOrderStatus();
        },
        onFail: (err) => {
          console.error("扫码失败:", err);
          if (err.errMsg === "scanCode:fail cancel") {
            wx.showToast({
              title: "已取消扫码",
              icon: "none"
            });
          } else {
            wx.showToast({
              title: "扫码失败，请重试",
              icon: "none"
            });
          }
        }
      });
    }
  },
  async onLoad(options) {
    if (typeof app.guardToQueueIfReview === "function") {
      const redirected = await app.guardToQueueIfReview({ force: true });
      if (redirected) return;
    }
    this.refreshReviewFlag(true);
    console.log(options);
    if (app.globalData.userInfo) this.memberInfo = { ...this.memberInfo, ...app.globalData.userInfo };
    if (options && options.shop_id != null && String(options.shop_id).trim() !== "") {
      await this.applyShopFromQr(options.shop_id);
    }
    this.bannerShopId = Number(getCurrentShopId()) || 0;
    if (options && options.number) {
      this.table_number = options.number;
      
      app.setStorageWithExpiry("table_number", this.table_number);
    }
    if (options && options.redeem_code) {
      this.redeemCouponByCode(decodeURIComponent(options.redeem_code));
    }
    setTimeout(() => {
      this.getBanner();
      this.loadIndexPopupList();
      if (this.table_number) this.checkOrderStatus();
    }, 0);
  },
  // 每次显示时拉取最新用户信息（积分、优惠券等），保证数据实时
  async onShow() {
	if (typeof app.guardToQueueIfReview === "function") {
	  const redirected = await app.guardToQueueIfReview();
	  if (redirected) return;
	}
	this.refreshReviewFlag();
	this.refreshMemberInfo();
	const sid = Number(getCurrentShopId()) || 0;
	if (sid !== Number(this.bannerShopId)) {
	  this.bannerShopId = sid;
	  this.getBanner(true);
	  this.loadIndexPopupList();
	}
  },
  onPullDownRefresh() {
	this.refreshMemberInfo().finally(() => { wx.stopPullDownRefresh(); });
  },
  mounted() {
	if (app && app.event && typeof app.event.on === 'function') {
	  this._onUnifiedCouponGranted = () => this.refreshMemberInfo();
	  app.event.on('unified:coupon_granted', this._onUnifiedCouponGranted);
	}
  },
  beforeDestroy() {
	if (app && app.event && typeof app.event.off === 'function' && this._onUnifiedCouponGranted) {
	  app.event.off('unified:coupon_granted', this._onUnifiedCouponGranted);
	}
  }
};
</script>

<style scoped>
page {
  background-color: #fff5f2;
  height: 100%;
}

.container {
  display: flex;
  flex-direction: column;
  min-height: 100vh;
  position: relative;
}

/* 品牌头部样式 */
.brand-header {
  width: 100%;
  position: relative;
  margin-bottom: 30rpx;
}
.brand-swiper {
  width: 100%;
  height: 610rpx;  /* 根据设计稿调整高度 */
}
.brand-swiper-item {
  width: 100%;
  height: 100%;
}
.brand-illustration {
  width: 100%;
  height: 100%;
}

.brand-slogan {
	font-size: 30rpx;
    color: #333;
    text-align: left;
    margin-bottom: 20rpx;
    font-weight: 500;
    display: flex;
	padding: 0 5rpx;
}

.all-orders {
    position: relative;
    text-align: right;
    top: 5rpx;
    font-size: 26rpx;
    color: #d86c20;
	margin-left: auto;
}

.main-area{
	width: 100%;
    border-radius: 50rpx;
    top: 530rpx;
    position: absolute;
    background-color: rgba(255,244,238, 100); 
}
.operation-OldFat{
	width: 450rpx;
	
}
.operation-area{
	width: 100%;
    padding: 10rpx 40rpx;
	box-sizing: border-box;
    top: 30rpx;
    position: relative;
}
/* 核心操作区样式 */
.main-operation-area {
  width: 100%;
  margin-bottom: 20rpx;
}

.operation-card {
	background-color: #fff;
    border-radius: 20rpx;
    display: flex;
    padding: 30rpx 20rpx;
    box-shadow: 0 4rpx 10rpx rgba(0,0,0,0.05);
    height: 350rpx;
    box-sizing: border-box;
}
.operation-card-review {
  align-items: center;
  justify-content: center;
}

.operation-item {
  flex: 1;
  display: flex;
  flex-direction: column;
  align-items: center;
  text-align: center;
  border-radius: 15rpx;
  transition: all 0.3s ease;
}
.operation-item-review {
  justify-content: center;
}



.operation-takeaway {
  width: 200rpx;
  
}
.operation-dinein {
	width: 200rpx;
   
}
/* 分隔线样式 */
.divider-line {
  width: 1rpx;               /* 线的宽度 */
  height: 300rpx;             /* 线的高度，可根据需求调整 */
  background-color: #e5e5e5;/* 浅灰色，适配大多数UI风格 */
  margin: 0 15px;           /* 左右间距，避免贴太紧 */
}
.operation-text-main{
    position: relative;
}
.operation-text {
  font-family: "Microsoft YaHei", sans-serif;
  font-size: 50rpx;
  font-weight: bold;
  color: #333;
  margin-bottom: 5rpx;
}

.operation-desc {
  font-size: 22rpx;
  color: #999;
}

/* 会员信息区样式 */
.member-info-area {
  width: 100%;
  margin-bottom: 20rpx;
}

.member-card {
  background-color: #fff;
  border-radius: 20rpx;
  display: flex;
  align-items: center;
  padding: 20rpx 40rpx;
  box-sizing: border-box;
  box-shadow: 0 4rpx 10rpx rgba(0,0,0,0.05);
  height: 200rpx;
}

.member-avatar {
  width: 120rpx;
  height: 100rpx;
  border-radius: 50%;
  margin-right: 20rpx;
}

.member-name-container {
  display: flex;
  flex-direction: column;
  margin-right: 40rpx;
}
.lv-icon{
    width: 35rpx;
    bottom: 10rpx;
    position: relative;
	padding: 0 2rpx;
	
}
.member-name {
  font-size: 35rpx;
  font-weight: bold;
  color: #333;
  margin-bottom: 5rpx;
}

.member-tag {
	font-size: 20rpx;
    color: #fff;
    background-color: #e84a27;
    border-radius: 10rpx;
    padding: 2rpx 10rpx;
    width: fit-content;
    margin-top: 5rpx;
}

.member-stats-row {
  display: flex;
  align-items: center;
  margin-left: auto;
  gap: 28rpx;
  flex-shrink: 0;
}
.member-data-coupons,
.member-data-points {
  display: flex;
  flex-direction: column;
  align-items: center;
}
.member-data-balance.member-stats-link {
  display: flex;
  flex-direction: column;
  align-items: center;
  text-decoration: none;
  color: inherit;
}
.member-stats-link-hover {
  opacity: 0.88;
}
.data-value-balance {
  font-size: 32rpx;
  font-weight: bold;
  color: #b32424;
}

.data-value {
  font-size: 40rpx;
  font-weight: bold;
  color: #333;
  margin-bottom: 5rpx;
}

.data-label {
  font-size: 25rpx;
  color: #999;
}

/* 中部轮播（/activity/popupList） */
.index-popup-area {
  width: 100%;
  margin-bottom: 40rpx;
  border-radius: 20rpx;
  overflow: hidden;
  background-color: #f5f5f5;
}

.index-popup-swiper {
  height: 280rpx;
  width: 100%;
}

.index-popup-item {
  width: 100%;
  height: 100%;
  box-sizing: border-box;
}

.index-popup-img {
  width: 100%;
  height: 100%;
  border-radius: 16rpx;
  display: block;
}

/* 底部扫码按钮 */
.bottom-actions {
  width: 100%;
  margin-top: auto;
  padding: 20rpx 0 40rpx;
}

.scan-btn {
  width: 100%;
  background-color: #b32424;
  color: #fff;
  border-radius: 15rpx;
  padding: 30rpx 0;
  font-size: 34rpx;
  display: flex;
  align-items: center;
  justify-content: center;
  border: none;
}

.scan-icon {
  width: 40rpx;
  height: 40rpx;
  margin-right: 15rpx;
}

.scan-text {
  font-size: 34rpx;
}

/* 加载遮罩 */
.loading-mask {
  position: fixed;
  top: 0;
  left: 0;
  right: 0;
  bottom: 0;
  background-color: rgba(255,255,255,0.8);
  display: flex;
  align-items: center;
  justify-content: center;
  z-index: 999;
}

.loading-content {
  background-color: #fff;
  padding: 40rpx 60rpx;
  border-radius: 10rpx;
  box-shadow: 0 4rpx 20rpx rgba(0,0,0,0.1);
}

.redeem-modal {
  position: fixed;
  left: 0;
  right: 0;
  top: 0;
  bottom: 0;
  z-index: 1200;
  display: flex;
  align-items: center;
  justify-content: center;
}

.redeem-mask {
  position: absolute;
  left: 0;
  right: 0;
  top: 0;
  bottom: 0;
  background: rgba(0, 0, 0, 0.55);
}

.redeem-panel {
  position: relative;
  width: 78%;
  max-width: 600rpx;
  background: #fff7f7;
  border-radius: 48rpx;
  padding: 48rpx 40rpx 44rpx;
  box-sizing: border-box;
  display: flex;
  flex-direction: column;
  align-items: center;
  text-align: center;
  box-shadow: 0 16rpx 64rpx rgba(191, 24, 24, 0.18);
}

/* 顶部成功图标 + 轻量装饰 */
.redeem-icon-section {
  position: relative;
  width: 220rpx;
  height: 140rpx;
  display: flex;
  align-items: center;
  justify-content: center;
  margin-bottom: 8rpx;
}

.redeem-confetti {
  position: absolute;
  left: 0;
  right: 0;
  top: 0;
  bottom: 0;
  pointer-events: none;
}

.redeem-confetti-dot {
  position: absolute;
  width: 14rpx;
  height: 14rpx;
  border-radius: 50%;
}

.redeem-confetti-dot.c1 {
  top: 18%;
  left: 8%;
  background: #ff8d8d;
}

.redeem-confetti-dot.c2 {
  top: 28%;
  right: 6%;
  background: #ffd1d1;
}

.redeem-confetti-dot.c3 {
  bottom: 22%;
  left: 18%;
  background: #d92b2b;
  width: 10rpx;
  height: 10rpx;
}

.redeem-confetti-dot.c4 {
  bottom: 30%;
  right: 14%;
  background: #ff6b6b;
  width: 12rpx;
  height: 12rpx;
}

.redeem-confetti-arc {
  position: absolute;
  width: 24rpx;
  height: 24rpx;
  border: 4rpx solid transparent;
  border-top-color: #ff8d8d;
  border-right-color: #ff8d8d;
  border-radius: 50%;
  opacity: 0.85;
}

.redeem-confetti-arc.a1 {
  top: 8%;
  right: 22%;
  transform: rotate(-30deg);
}

.redeem-confetti-arc.a2 {
  bottom: 12%;
  right: 8%;
  transform: rotate(120deg);
  border-top-color: #ffd1d1;
  border-right-color: #ffd1d1;
}

.redeem-success-circle {
  width: 100rpx;
  height: 100rpx;
  border-radius: 50%;
  background: linear-gradient(135deg, #ff5a5a, #d8001f);
  display: flex;
  align-items: center;
  justify-content: center;
  box-shadow: 0 8rpx 24rpx rgba(216, 0, 31, 0.35);
}

.redeem-check-mark {
  color: #fff2c7;
  font-size: 56rpx;
  font-weight: 700;
  line-height: 1;
  margin-top: -4rpx;
}

.redeem-main-title {
  font-size: 40rpx;
  font-weight: 700;
  color: #c1121f;
  margin-top: 12rpx;
  margin-bottom: 16rpx;
  letter-spacing: 1rpx;
}

.redeem-subtitle {
  width: 100%;
  padding: 0 8rpx;
  box-sizing: border-box;
}

.redeem-subtitle text {
  font-size: 28rpx;
  color: #9b4b4b;
  line-height: 1.5;
}

/* 规则 / 说明胶囊条 */
.redeem-notice-bar {
  width: 100%;
  box-sizing: border-box;
  margin-top: 32rpx;
  padding: 22rpx 28rpx;
  background: #ffe7e7;
  border: 1rpx solid #ffd3d3;
  border-radius: 999rpx;
  display: flex;
  flex-direction: row;
  align-items: flex-start;
}

.redeem-notice-icon {
  color: #d43838;
  font-size: 28rpx;
  line-height: 1.4;
  margin-right: 12rpx;
  flex-shrink: 0;
}

.redeem-notice-text {
  flex: 1;
  text-align: left;
  font-size: 24rpx;
  color: #c93a3a;
  line-height: 1.5;
}

.redeem-ok-btn {
  margin-top: 40rpx;
  width: 100%;
  height: 88rpx;
  line-height: 88rpx;
  text-align: center;
  border-radius: 999rpx;
  color: #ffffff;
  font-size: 30rpx;
  font-weight: 600;
  background: linear-gradient(135deg, #ff4b4b, #d7001f);
}
</style>
