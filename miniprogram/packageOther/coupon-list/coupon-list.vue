<template>
  <view class="coupon-page">
    <view class="filter-bar"><view class="filter-item" :class="{ active: currentFilter === 'usable' }" @click="changeFilter('usable')">可使用</view><view class="filter-item" :class="{ active: currentFilter === 'unusable' }" @click="changeFilter('unusable')">不可使用</view></view>
    <view class="coupon-list" v-if="filteredCouponList.length > 0">
      <view class="coupon-item" v-for="(item, index) in filteredCouponList" :key="index" v-if="currentFilter === 'usable'">
        <view class="coupon-main"><view class="coupon-left"><view class="coupon-type-tag">{{ getCouponTypeName(item.coupon_type) }}</view><view class="coupon-name">{{ item.coupon_name }}</view><view class="coupon-validity">有效期至 {{ formatDate(item.expire_time) }}</view></view><view class="coupon-middle"><template v-if="item.coupon_type === 'discount'"><view class="coupon-value">{{ (item.discount_value / 10).toFixed(1) }}折</view><view class="coupon-desc">满{{ item.min_amount }}元可用</view></template><template v-if="item.coupon_type === 'full_reduction'"><view class="coupon-value">¥{{ item.discount_value }}</view><view class="coupon-desc">满{{ item.min_amount }}元减</view></template><template v-if="item.coupon_type === 'direct_reduction'"><view class="coupon-value">¥{{ item.discount_value }}</view><view class="coupon-desc">无门槛立减</view></template></view><view class="coupon-right" v-if="orderPickFlow"><view class="radio-wrapper" @click.stop="useCoupon(item)"><view class="radio-icon" :class="{ active: couponid === item.id }"><text class="radio-text" v-if="couponid === item.id">✓</text></view></view></view></view>
        <view class="coupon-rule"><view class="rule-content">{{ item.description || '暂无详细规则' }}</view><view class="toggle-triangle" @click="toggleRule(index)"><image class="triangle-down" :class="{ active: getShowRuleStatus(index) }" :src="staticUrl('images/triangle-down.png')" mode="widthFix"></image></view></view>
      </view>
      <view class="coupon-item disabled" v-for="(item, index) in filteredCouponList" :key="index" v-if="currentFilter === 'unusable'">
        <view class="coupon-main"><view class="coupon-left"><view class="coupon-type-tag">{{ getCouponTypeName(item.coupon_type) }}</view><view class="coupon-name">{{ item.coupon_name }}</view><view class="coupon-validity"><template v-if="getStatus(item.status) === 'used'">使用时间 {{ formatDate(item.use_time) }}</template><template v-if="getStatus(item.status) === 'expired'">过期时间 {{ formatDate(item.end_time) }}</template><template v-if="getStatus(item.status) === 'usable'">有效期至 {{ formatDate(item.expire_time) }}</template></view></view><view class="coupon-middle"><template v-if="item.coupon_type === 'discount'"><view class="coupon-value">{{ (item.discount_value / 10).toFixed(1) }}折</view><view class="coupon-desc">满{{ item.min_amount }}元可用</view></template><template v-if="item.coupon_type === 'full_reduction'"><view class="coupon-value">¥{{ item.discount_value }}</view><view class="coupon-desc">满{{ item.min_amount }}元减</view></template><template v-if="item.coupon_type === 'direct_reduction'"><view class="coupon-value">¥{{ item.discount_value }}</view><view class="coupon-desc">无门槛立减</view></template></view><view class="coupon-right"></view></view>
        <view class="status-tag" v-if="getStatus(item.status) === 'used'">已使用</view><view class="status-tag expired" v-if="getStatus(item.status) === 'expired'">已过期</view><view class="status-tag" v-if="getStatus(item.status) === 'usable' && !isCouponUsable(item)">不满足条件</view><view class="coupon-rule"><view class="rule-content">不可使用原因：{{ getUnusableReason(item) }}</view><view class="toggle-triangle" @click="toggleRule(index)"><image class="triangle-down" :class="{ active: getShowRuleStatus(index) }" :src="staticUrl('images/triangle-down.png')" mode="widthFix"></image></view></view>
      </view>
    </view>
    <view class="empty-state" v-if="filteredCouponList.length === 0 && !isLoading"><image :src="staticUrl('images/empty_coupon.png')" mode="widthFix" class="empty-img"></image><view class="empty-text">暂无{{ currentFilter === 'usable' ? '可使用' : '不可使用' }}优惠券</view></view>
    <view class="loading-state" v-if="isLoading"><text>加载中...</text></view>
  </view>
</template>

<script>
import { getBaseUrl, requestUtil } from "../../utils/requestUtil.js";
import {
  couponPassesLocalOrderRules,
  normalizeCouponListPayload,
  explainCouponUnusable,
  normalizeLocalOrderRulesCtx,
  getThresholdAmountForCoupon,
  parseCouponTime as parseCouponRuleTime,
  normalizeDiningType,
  matchDiningType,
  getCouponStatus,
} from "../../utils/couponRules.js";
import { getCurrentShopId } from "../../utils/shopContext.js";
import { staticUrl } from "../../utils/staticAssetUrl.js";
const app = getApp();

/** 置为 true 时输出优惠券规则调试日志（默认关闭，避免控制台刷屏与性能损耗） */
const COUPON_LIST_DEBUG = false;

export default {
  data() {
    return {
      baseUrl: getBaseUrl(),
      couponList: [], // 原始优惠券列表
      currentFilter: "usable", // 筛选条件：usable/unusable
      isLoading: false,
      fromPage: '',
	  couponid:'',
      orderBaseTotal: 0,
	  selectedCoupon:'',
      dineInOrTakeOut: '堂食',
      showRuleMap: {}, // 格式：{ index: true/false }
      /** details -> coupon-list 通过 eventChannel 直传订单行，避免陈旧缓存 */
      detailsOrderLines: [],
      /** confirm/details：本地规则上下文缓存，避免 filteredCouponList 每条券重复读 storage */
      _orderRulesCtxCache: null,
    };
  },
  computed: {
	// 计算属性：根据当前筛选条件过滤优惠券
	filteredCouponList() {
		  const result = this.couponList.filter(item => {
			// 先判断优惠券基础状态
			const status = this.getStatus(item.status);
			const isBaseUsable = status === 'usable';
			if (COUPON_LIST_DEBUG) {
			  console.log(`优惠券[${item.coupon_name}] - 基础状态:`, status, '是否基础可用:', isBaseUsable);
			}
			let isConditionSatisfied = this.isCouponUsable(item);
			if (COUPON_LIST_DEBUG) {
			  console.log(`优惠券[${item.coupon_name}] - 是否满足使用条件:`, isConditionSatisfied);
			}
			if (this.currentFilter === 'usable') {
			  const isUsable = isBaseUsable && isConditionSatisfied;
			  if (COUPON_LIST_DEBUG) {
			    console.log(`优惠券[${item.coupon_name}] - 最终是否可使用:`, isUsable);
			  }
			  return isUsable;
			}
			  const isUnusable = !isBaseUsable || !isConditionSatisfied;
			  if (COUPON_LIST_DEBUG) {
			    console.log(`优惠券[${item.coupon_name}] - 最终是否不可使用:`, isUnusable);
			  }
			  return isUnusable;
		});
		
		return result;
	    
	},
    /** 确认订单 / 订单详情：同一套可用券接口与选券返回逻辑 */
    orderPickFlow() {
      return this.fromPage === "confirm" || this.fromPage === "details";
    },
    
  },
  onLoad(options) { // 修复：添加options参数
    if (!app.globalData.isLogin) {
      wx.showToast({
        title: "请先登录",
        icon: "none",
      });
      wx.navigateBack();
      return;
    }

    this._orderRulesCtxCache = null;
    const storedCoupon = wx.getStorageSync("selected_coupon");
    this.selectedCoupon =
      storedCoupon && typeof storedCoupon === "object" ? storedCoupon : null;
    // 接收从确认订单页传入的参数
    this.fromPage = options.from || '';
    // 兼容历史参数 discount，新参数优先使用 orderBaseTotal
    let orderBaseTotalRaw = options.orderBaseTotal;
    if (orderBaseTotalRaw == null || orderBaseTotalRaw === '') {
      orderBaseTotalRaw = options.discount;
    }
    if (orderBaseTotalRaw != null && orderBaseTotalRaw !== '') {
      try {
        orderBaseTotalRaw = decodeURIComponent(String(orderBaseTotalRaw));
      } catch (e) {
        orderBaseTotalRaw = String(orderBaseTotalRaw);
      }
      const n = Number(orderBaseTotalRaw);
      this.orderBaseTotal = Number.isFinite(n) ? n : 0;
    } else {
      this.orderBaseTotal = 0;
    }
    if (COUPON_LIST_DEBUG) {
      console.log("[coupon-debug][list][onLoad] raw-options", {
        from: options.from,
        orderBaseTotal: options.orderBaseTotal,
        discount: options.discount,
        dineInOrTakeOut: options.dineInOrTakeOut,
      });
    }
    try {
      this.dineInOrTakeOut = options.dineInOrTakeOut
        ? decodeURIComponent(String(options.dineInOrTakeOut))
        : "堂食";
    } catch (e) {
      this.dineInOrTakeOut = options.dineInOrTakeOut || "堂食";
    }
    if (COUPON_LIST_DEBUG) {
      console.log("[coupon-debug][list][onLoad] parsed-options", {
        fromPage: this.fromPage,
        orderBaseTotal: this.orderBaseTotal,
        dineInOrTakeOut: this.dineInOrTakeOut,
      });
    }
    this.couponid =
      this.selectedCoupon && this.selectedCoupon.id != null
        ? this.selectedCoupon.id
        : "";
    if (this.orderPickFlow) {
      try {
        const channel = this.getOpenerEventChannel && this.getOpenerEventChannel();
        if (channel && typeof channel.on === "function") {
          channel.on("couponOrderCtx", (payload = {}) => {
            const lines = Array.isArray(payload.orderLines) ? payload.orderLines : [];
            this.detailsOrderLines = lines;
            this._orderRulesCtxCache = null;
          });
        }
      } catch (e) {}
    }
    this.getCouponList();
  },
  onShow() {
    // 页面可能被缓存：从确认单/详情返回后购物车或订单行变化时，须重建规则上下文
    if (this.fromPage === "confirm" || this.fromPage === "details") {
      this._orderRulesCtxCache = null;
    }
  },
  onUnload() {},
  methods: {
    staticUrl,
	getCouponDiningTypeText(coupon) {
	  const raw =
	    coupon.dineInOrTakeOut ??
	    coupon.dine_in_or_take_out ??
	    coupon.dining_type ??
	    coupon.use_scene ??
	    coupon.apply_dining_type ??
	    coupon.apply_dining_types;
	  if (raw == null || String(raw).trim() === '') return '指定用餐方式';
	  const text = String(raw).trim();
	  let list = [];
	  if (text.startsWith('[')) {
	    try {
	      const arr = JSON.parse(text);
	      if (Array.isArray(arr)) list = arr.map((x) => normalizeDiningType(x));
	    } catch (e) {}
	  }
	  if (!list.length) {
	    list = text.split(/[,\|\/、\s]+/).map((x) => normalizeDiningType(x)).filter(Boolean);
	  }
	  return list.length ? list.join('或') : '指定用餐方式';
	},
    /** confirm/details：复用同一份规则上下文，避免列表过滤时重复读 storage */
    getOrBuildLocalOrderRulesCtx() {
      if (!this.orderPickFlow) {
        return this.buildLocalOrderRulesCtx({ silent: true });
      }
      if (!this._orderRulesCtxCache) {
        this._orderRulesCtxCache = this.buildLocalOrderRulesCtx({ silent: true });
      }
      return this._orderRulesCtxCache;
    },
	/** 与 confirm-order / order-details 同一套 normalizeLocalOrderRulesCtx，仅订单行来源因 from 不同 */
    buildLocalOrderRulesCtx(options = {}) {
      const silent = options.silent === true;
      let cart = [];
      try {
        cart = Array.isArray(this.detailsOrderLines) && this.detailsOrderLines.length
          ? this.detailsOrderLines
          : (this.fromPage === "details" ? [] : (wx.getStorageSync("shopping_cart") || []));
      } catch (e) {
        cart = [];
      }
      const ctx = normalizeLocalOrderRulesCtx({
        orderBaseTotal: this.orderBaseTotal,
        shoppingCart: Array.isArray(cart) ? cart : [],
        dineInOrTakeOut: this.dineInOrTakeOut,
        currentShopId: getCurrentShopId(),
      });
      if (COUPON_LIST_DEBUG && !silent) {
        console.log("[coupon-debug][list][order-lines-raw]", {
          fromPage: this.fromPage,
          sourceKey:
            this.fromPage === "details"
              ? "eventChannel.couponOrderCtx.orderLines"
              : (Array.isArray(this.detailsOrderLines) && this.detailsOrderLines.length
                  ? "eventChannel.couponOrderCtx.orderLines"
                  : "shopping_cart"),
          cartLength: Array.isArray(cart) ? cart.length : 0,
          cart,
        });
        console.log(
          "[coupon-debug][list][order-lines-normalized]",
          (ctx.shoppingCart || []).map((item, idx) => ({
            idx,
            id: item && item.id,
            dish_id: item && item.dish_id,
            dishId: item && item.dishId,
            goods_id: item && item.goods_id,
            goodsId: item && item.goodsId,
            item_id: item && item.item_id,
            itemId: item && item.itemId,
            quantity:
              item &&
              (item.quantity ?? item.qty ?? item.count ?? item.num ?? 0),
            unitprice: item && (item.unitprice ?? item.unit_price ?? item.price),
            total_price:
              item &&
              (item.total_price ??
                item.totalPrice ??
                item.subtotal ??
                item.amount ??
                item.line_total ??
                item.lineTotal),
          }))
        );
      }
      if (COUPON_LIST_DEBUG && !silent && this.fromPage === "details") {
        console.log("[coupon-debug][list][ctx-details]", {
          orderBaseTotal: ctx.orderBaseTotal,
          shoppingCartLength: Array.isArray(ctx.shoppingCart) ? ctx.shoppingCart.length : 0,
          dineInOrTakeOut: ctx.dineInOrTakeOut,
          shopId: ctx.currentShopId,
        });
      }
      return ctx;
    },
	// 获取不可使用原因
    getUnusableReason(coupon) {
      if (this.orderPickFlow) {
        const msg = explainCouponUnusable(coupon, this.getOrBuildLocalOrderRulesCtx());
        return msg || "不满足使用条件";
      }
      const now = Date.now();
      const endTime = parseCouponRuleTime(
        coupon.expire_time ??
          coupon.end_time ??
          coupon.expireTime ??
          coupon.endTime ??
          coupon.invalid_time,
        Infinity
      );
      const startTime = parseCouponRuleTime(
        coupon.start_time ??
          coupon.begin_time ??
          coupon.startTime ??
          coupon.beginTime ??
          coupon.effective_time ??
          coupon.effect_time,
        now
      );
      const orderAmount = this.orderBaseTotal;
      const minAmount = coupon.min_amount || 0;
      
      const orderType = this.dineInOrTakeOut;
      
      if (now < startTime) {
        return "优惠券尚未生效";
      } else if (now > endTime) {
        return "优惠券已过期";
      } else if (!matchDiningType(coupon, orderType)) {
        return `仅限${this.getCouponDiningTypeText(coupon)}使用`;
      } else if (orderAmount < minAmount) {
        return `订单金额未满足（需满${minAmount}元）`;
      } else if (getCouponStatus(coupon.status) === 'used') {
        return "优惠券已使用";
      } else {
        return "不满足使用条件";
      }
    },  
	isCouponUsable(coupon) {
      if (this.orderPickFlow) {
        // getUserAvailableCoupons：需经 couponPassesLocalOrderRules（含金额/适用菜门槛）
        const ctx = this.getOrBuildLocalOrderRulesCtx();
        const ok = couponPassesLocalOrderRules(coupon, ctx);
        if (!ok && this.fromPage === "details" && COUPON_LIST_DEBUG) {
          const reason = explainCouponUnusable(coupon, ctx);
          const now = Date.now();
          const startTimeMs = parseCouponRuleTime(
            coupon.start_time ??
              coupon.begin_time ??
              coupon.startTime ??
              coupon.beginTime ??
              coupon.effective_time ??
              coupon.effect_time,
            now
          );
          const endTimeMs = parseCouponRuleTime(
            coupon.expire_time ??
              coupon.end_time ??
              coupon.expireTime ??
              coupon.endTime ??
              coupon.invalid_time,
            Infinity
          );
          const thresholdAmount = getThresholdAmountForCoupon(
            coupon,
            ctx.orderBaseTotal,
            ctx.shoppingCart
          );
          console.log("[coupon-debug][list][details][reject-reason]", {
            couponName: coupon && coupon.coupon_name,
            couponId: coupon && coupon.id,
            reason: reason || "unknown",
            minAmount: Number(coupon && coupon.min_amount) || 0,
            orderBaseTotal: ctx.orderBaseTotal,
            thresholdAmount: Math.round(Number(thresholdAmount || 0) * 100) / 100,
            applyDishIdsRaw: coupon && coupon.apply_dish_ids,
            startTimeRaw: coupon && (coupon.start_time ?? coupon.begin_time ?? coupon.startTime ?? coupon.beginTime ?? coupon.effective_time ?? coupon.effect_time),
            endTimeRaw: coupon && (coupon.expire_time ?? coupon.end_time ?? coupon.expireTime ?? coupon.endTime ?? coupon.invalid_time),
            nowMs: now,
            startTimeMs,
            endTimeMs,
            shopId: ctx.currentShopId,
            dineInOrTakeOut: ctx.dineInOrTakeOut,
          });
        }
        return ok;
      }
      // getUserCoupons：仅时段/用餐方式/状态，不按订单金额做门槛判断
      const now = Date.now();
      const endTime = parseCouponRuleTime(
        coupon.expire_time ??
          coupon.end_time ??
          coupon.expireTime ??
          coupon.endTime ??
          coupon.invalid_time,
        Infinity
      );
      const startTime = parseCouponRuleTime(
        coupon.start_time ??
          coupon.begin_time ??
          coupon.startTime ??
          coupon.beginTime ??
          coupon.effective_time ??
          coupon.effect_time,
        now
      );
      if (now > endTime || now < startTime) {
        return false;
      }
      if (!matchDiningType(coupon, this.dineInOrTakeOut)) {
        return false;
      }
      if (getCouponStatus(coupon.status) === "used") {
        return false;
      }
      return true;
    },
    goBack() {
      wx.navigateBack();
    },
    changeFilter(type) {
      if (this.currentFilter === type) return;
      this.currentFilter = type;
      this.showRuleMap = {}; // 切换筛选时重置规则展开状态
    },
    getStatus(status) {
      return getCouponStatus(status);
    },
    async getCouponList() {
      this.isLoading = true;
      try {
        // confirm/details：可用券接口 + 本地订单规则；其它入口：全量券接口，筛选不走金额门槛
        const useAvailableApi = this.orderPickFlow;
        const reqUrl = useAvailableApi ? "/coupon/getUserAvailableCoupons" : "/coupon/getUserCoupons";
        const reqData = useAvailableApi
          ? { openid: app.globalData.openid }
          : {
              openid: app.globalData.openid,
              // 非确认页沿用原接口与状态筛选
              status: this.currentFilter
            };
        const res = await requestUtil({
          url: reqUrl,
          data: reqData,
          method: "post",
        });
        if (res.code === 0) {
          this.showRuleMap = {};
          const rawList = normalizeCouponListPayload(res);
          this.couponList = rawList.map((coupon, index) => {
            this.showRuleMap[index] = false;
           
            return { ...coupon };
          });
        } else {
          wx.showToast({
            title: res.msg || "获取优惠券失败",
            icon: "none",
          });
        }
      } catch (e) {
        console.error("获取优惠券失败:", e);
        wx.showToast({
          title: "网络异常，请重试",
          icon: "none",
        });
      } finally {
        this.isLoading = false;
      }
    },
    formatDate(date) {
      if (!date) return "";
      const targetDate = typeof date === 'string' ? new Date(date.replace(/-/g, '/')) : date;
      return `${targetDate.getFullYear()}-${(targetDate.getMonth() + 1).toString().padStart(2, "0")}-${targetDate.getDate().toString().padStart(2, "0")}`;
    },
    useCoupon(coupon) {
		
	  // 1. 判断当前点击的优惠券是否已选中
      if(this.couponid === coupon.id) {
        // 取消选中：清除缓存 + 重置状态
        wx.removeStorageSync("selected_coupon");
        this.selectedCoupon = null;
        this.couponid = ''; // 关键修复：重置couponid，让单选框状态更新
        
        return;
      }	
	  
      const now = Date.now();
      const endTime = parseCouponRuleTime(
        coupon.expire_time ??
          coupon.end_time ??
          coupon.expireTime ??
          coupon.endTime ??
          coupon.invalid_time,
        Infinity
      );
      const startTime = parseCouponRuleTime(
        coupon.start_time ??
          coupon.begin_time ??
          coupon.startTime ??
          coupon.beginTime ??
          coupon.effective_time ??
          coupon.effect_time,
        now
      );

      if (now > endTime) {
        wx.showToast({ title: "优惠券已过期", icon: "none" });
        return;
      }
      if (now < startTime) {
        wx.showToast({ title: "优惠券尚未生效", icon: "none" });
        return;
      }

      if (this.orderPickFlow) {
        const ctx = this.getOrBuildLocalOrderRulesCtx();
        if (!couponPassesLocalOrderRules(coupon, ctx)) {
          const msg = explainCouponUnusable(coupon, ctx) || "不满足使用条件";
          wx.showToast({
            title: msg.length > 22 ? "不满足当前订单使用条件" : msg,
            icon: "none",
            duration: 2200,
          });
          return;
        }
      } else {
        if (getCouponStatus(coupon.status) !== "usable") {
          wx.showToast({ title: "优惠券不可用", icon: "none" });
          return;
        }
        if (!matchDiningType(coupon, this.dineInOrTakeOut)) {
          wx.showToast({ title: "用餐方式不适用", icon: "none" });
          return;
        }
      }

      wx.setStorageSync("selected_coupon", coupon);
      this.selectedCoupon = coupon;
      this.couponid = coupon.id; // 关键修复：更新couponid，触发单选框选中状态
      if (this.orderPickFlow) {
        setTimeout(() => {
          wx.navigateBack();
        }, 120);
      }
      
    },
    goToGetCoupon() {
      wx.navigateTo({ url: "/packageOther/coupon-center/coupon-center" });
    },
    getShowRuleStatus(index) {
      return this.showRuleMap[index] !== undefined ? this.showRuleMap[index] : false;
    },
    toggleRule(index) {
      this.showRuleMap[index] = !this.getShowRuleStatus(index);
      this.$forceUpdate();
    },
    getCouponTypeName(type) {
      const typeMap = {
        'full_reduction': '满减券',
        'discount': '折扣券',
        'direct_reduction': '立减券'
      };
      return typeMap[type] || '优惠券';
    }
  },
};
</script>

<style scoped>
.coupon-page {
  background-color: #f5f5f5;
  min-height: 100vh;
}

/* 筛选栏 */
.filter-bar {
  display: flex;
  background-color: #fff;
  padding: 20rpx 0;
  border-bottom: 1rpx solid #eee;
}
.filter-item {
  flex: 1;
  text-align: center;
  font-size: 28rpx;
  color: #666;
  padding: 10rpx 0;
}
.filter-item.active {
  color: #e10606;
  font-weight: bold;
  border-bottom: 3rpx solid #e10606;
}

/* 优惠券列表 */
.coupon-list {
  padding: 20rpx 30rpx;
  display: flex;
  flex-direction: column;
  gap: 20rpx;
}

/* 优惠券项容器 */
.coupon-item {
  background: linear-gradient(to right, rgba(255, 81, 23, 0.9), rgba(225, 6, 6, 0.9));
  border-radius: 10rpx;
  color: #fff;
  overflow: hidden;
  position: relative;
  padding-bottom: 20rpx;
}
.coupon-item.disabled {
  background: linear-gradient(to right, #999, #666);
  opacity: 0.8;
}

/* 优惠券主体 */
.coupon-main {
  display: flex;
  align-items: baseline;
  padding: 30rpx 30rpx 10rpx 30rpx;
  cursor: pointer;
}

/* 左侧：名称 + 有效期 + 左上角类型标签 */
.coupon-left {
  display: flex;
  flex-direction: column;
  gap: 8rpx;
  position: relative;
  padding-top: 30rpx;
}
.coupon-type-tag {
  position: absolute;
  top: 0;
  left: 0;
  font-size: 20rpx;
  background-color: rgba(255, 255, 255, 0.3);
  padding: 4rpx 12rpx;
  border-radius: 0 0 15rpx 0;
  z-index: 1;
}
.coupon-item.disabled .coupon-type-tag {
  background-color: rgba(255, 255, 255, 0.15);
  color: #eee;
}
.coupon-name {
  font-size: 36rpx;
  font-weight: bold;
  z-index: 2;
}
.coupon-validity {
  font-size: 22rpx;
  opacity: 0.8;
  z-index: 2;
}

/* 中间：满减/折扣/立减 */
.coupon-middle {
  margin-left: 13%;
  flex-direction: column;
  justify-content: center;
  text-align: center;
}
.coupon-value {
  font-size: 50rpx;
  font-weight: bold;
  line-height: 1;
}
.coupon-desc {
  font-size: 22rpx;
  opacity: 0.8;
  margin-top: 10rpx;
}

/* 右侧：空容器 */
.coupon-right {
  margin-right: 20rpx;
}

/* 三角形样式 */
.triangle-down {
  width: 16px;
  height: 16px;
  display: flex;
  transition: transform 0.3s ease;
  transform-origin: center center;
}
.toggle-triangle {
  display: flex;
  justify-content: center;
  align-items: center;
  
  cursor: pointer;
}
.triangle-down.active {
  transform: rotate(180deg);
}

/* 立即使用按钮 */
.use-btn {
  position: absolute;
  top: 80rpx;
  right: 30rpx;
  background-color: #fff;
  color: #e10606;
  font-size: 24rpx;
  padding: 10rpx 20rpx;
  border-radius: 20rpx;
  z-index: 1;
}

/* 状态标签 */
.status-tag {
  position: absolute;
  bottom: 80rpx;
  right: 30rpx;
  background-color: #fff;
  color: #666;
  font-size: 24rpx;
  padding: 10rpx 20rpx;
  border-radius: 20rpx;
  z-index: 1;
}
.status-tag.expired {
  color: #999;
}

/* 展开的规则描述 */
.coupon-rule {
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: 10rpx 20rpx;
  margin: 0 30rpx;
  background-color: rgba(0, 0, 0, 0.15);
  border-radius: 8rpx;
  max-height: 300rpx;
  overflow-y: auto;
  position: relative;
  z-index: 0;
}
.rule-content {
  flex: 1;
  white-space: nowrap;
  overflow: hidden; 
  text-overflow: ellipsis; 
  font-size: 20rpx;
  line-height: 1.6;
  opacity: 0.9;
}
/* 展开后样式：自动换行，显示全部文字 */
.rule-content.expanded {
  white-space: normal; /* 取消单行限制 */
  overflow: visible; /* 显示全部内容 */
  text-overflow: clip;
  /* 展开后可能需要多行，调整最小高度避免布局跳动 */
  min-height: 21px;
}
/* 不可使用原因样式 */
.unusable-reason {
  margin-bottom: 15rpx;
  padding-bottom: 15rpx;
  font-weight: bold;
}
.radio-wrapper {
  position: absolute;
  top: 80rpx;
  right: 30rpx;
  display: flex;
  align-items: center;
  border-radius: 20rpx;
  padding: 8rpx 16rpx;
  z-index: 1;
}
.radio-text {
  font-size: 30rpx;
  color: #e10606;
}
/* 选中状态样式修改 */
.radio-icon.active {
  background-color: #FFD700; /* 金黄色背景 */
  color: #000; /* 黑色勾号 */
  border-color: #FFD700; /* 边框也改为黄色，可选 */
}
.radio-icon {
  width: 35rpx;
  height: 35rpx;
  border-radius: 50%;
  border: 2rpx solid #e10606;
  display: flex;
  justify-content: center;
  align-items: center;
  margin-right: 8rpx;
  font-size: 16rpx;
  color: transparent;
  background-color: #fff;
  /* 确保勾号居中 */
  font-weight: bold;
}
.reason-label {
  color: #ffd700; /* 金色高亮原因标签 */
}
.rule-divider {
  height: 1rpx;
  background-color: rgba(255, 255, 255, 0.2);
  margin-bottom: 15rpx;
}

/* 空状态 */
.empty-state {
  display: flex;
  flex-direction: column;
  align-items: center;
  padding: 100rpx 0;
}
.empty-img {
  width: 200rpx;
  height: 200rpx;
  margin-bottom: 30rpx;
}
.empty-text {
  font-size: 28rpx;
  color: #999;
  margin-bottom: 30rpx;
}
.get-coupon-btn {
  background-color: #e10606;
  color: #fff;
  font-size: 28rpx;
  padding: 20rpx 40rpx;
  border-radius: 50rpx;
  border: none;
}

/* 加载中 */
.loading-state {
  text-align: center;
  padding: 50rpx 0;
  font-size: 28rpx;
  color: #999;
}

@import url("https://unpkg.com/@dcloudio/uni-ui/lib/uni-icons/uni-icons.css");
</style>
