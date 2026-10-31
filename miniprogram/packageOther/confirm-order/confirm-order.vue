<template>
  <view class="confirm-order-page">
    <scroll-view class="main-content" scroll-y :show-scrollbar="false">
      <!-- 服务费提示 -->
      <view class="co-card co-card--notice" v-if="serviceFeeApplies">
        <text class="co-notice-text">本订单将加收新年服务费5%，随订单一并结算</text>
      </view>

      <!-- 模块：外卖配送 / 自提 -->
      <view class="co-card takeout-module" v-if="showPackFulfillmentBar && takeoutShopEnabled">
          <view class="takeout-mode-tabs">
            <view
              class="takeout-mode-tab"
              :class="{ active: packFulfillmentMode === 'pickup' }"
              @click="setPackFulfillmentMode('pickup')"
            >
              <text class="tab-main">到店自提</text>
              <text class="tab-sub">到店取餐</text>
            </view>
            <view
              class="takeout-mode-tab"
              :class="{ active: packFulfillmentMode === 'delivery' }"
              @click="setPackFulfillmentMode('delivery')"
            >
              <text class="tab-main">外卖配送</text>
              <text class="tab-sub">配送到家</text>
            </view>
          </view>

          <view
            v-if="packFulfillmentMode === 'delivery'"
            class="takeout-address-card"
            hover-class="takeout-address-card--hover"
            @click="openAddressPicker"
          >
            <view class="takeout-address-main">
              <view class="takeout-address-content">
                <block v-if="hasSelectedAddress">
                  <view class="takeout-addr-title-row">
                    <text class="takeout-addr-detail">{{ displayPoiName }}</text>
                    <text v-if="selectedAddressTag" class="takeout-addr-tag">{{ selectedAddressTag }}</text>
                  </view>
                  <text v-if="displayAddressFull" class="takeout-addr-region">{{ displayAddressFull }}</text>
                  <text v-if="displayAddressDetail" class="takeout-addr-extra">门牌：{{ displayAddressDetail }}</text>
                  <text v-if="displayDeliveryNote" class="takeout-addr-extra">配送说明：{{ displayDeliveryNote }}</text>
                  <view class="takeout-addr-contact-row">
                    <text class="takeout-addr-name">{{ selectedAddressName }}</text>
                    <text class="takeout-addr-phone">{{ selectedAddressPhoneMasked }}</text>
                  </view>
                </block>
                <block v-else>
                  <text class="takeout-addr-empty-title">请选择收货地址</text>
                  <text class="takeout-addr-empty-hint">添加地址后，将按距离自动计算配送费</text>
                </block>
              </view>
              <view class="takeout-address-arrow">
                <text class="takeout-modify-text">修改地址</text>
                <text class="takeout-arrow-text">›</text>
              </view>
            </view>

            <view class="takeout-address-divider" v-if="showTakeoutDeliveryStatus"></view>
            <view
              class="takeout-delivery-status"
              v-if="showTakeoutDeliveryStatus"
              :class="'takeout-delivery-status--' + takeoutDeliveryStatusType"
            >
              <text class="takeout-status-text">{{ takeoutDeliveryStatusText }}</text>
            </view>
          </view>

          <view v-if="packFulfillmentMode === 'delivery'" class="takeout-delivery-timing">
            <text class="takeout-timing-label">配送时间</text>
            <view class="takeout-timing-options">
              <view
                class="takeout-timing-option"
                :class="{ active: takeoutDeliveryTiming === 'immediate' }"
                @click="setTakeoutDeliveryTiming('immediate')"
              >
                <text>立即配送</text>
              </view>
              <view
                class="takeout-timing-option"
                :class="{ active: takeoutDeliveryTiming === 'scheduled' }"
                @click="setTakeoutDeliveryTiming('scheduled')"
              >
                <text>预约配送</text>
              </view>
            </view>
            <view
              v-if="takeoutDeliveryTiming === 'scheduled'"
              class="takeout-schedule-pickers"
            >
              <picker
                v-if="availableScheduleSlots.length"
                mode="selector"
                :range="availableScheduleSlots"
                :value="takeoutScheduledSlotIndex"
                @change="onTakeoutScheduleSlotChange"
              >
                <view class="takeout-schedule-picker takeout-schedule-picker--solo">
                  <text class="takeout-schedule-picker-k">时间</text>
                  <text
                    class="takeout-schedule-picker-v"
                    :class="{ 'takeout-schedule-picker-v--placeholder': !takeoutScheduledTime }"
                  >{{ takeoutScheduledTime || '请选择配送时间' }}</text>
                  <text class="takeout-arrow-text">›</text>
                </view>
              </picker>
              <view v-else class="takeout-schedule-empty">
                <text>今日预约时段已满，请选立即配送或稍后再试</text>
              </view>
              <text class="takeout-schedule-hint">目前订单较多，骑手紧张，送达时间可能波动</text>
            </view>
          </view>

          <view v-else class="takeout-pickup-card">
            <text class="takeout-pickup-store">{{ currentStoreName }}</text>
            <text class="takeout-pickup-tip">下单后请到店自提，具体取餐时间以门店通知为准</text>
          </view>
        </view>

      <!-- 模块：订单信息 -->
      <view class="co-card">
        <view class="co-card-head">
          <text class="co-card-title">订单信息</text>
        </view>
        <view class="co-kv-list">
          <view class="co-kv-row">
            <text class="co-kv-label">门店</text>
            <text class="co-kv-value co-kv-value--strong">{{ currentStoreName }}</text>
          </view>
          <view
            class="co-kv-row"
            v-if="showTableNumberRow"
          >
            <text class="co-kv-label">桌号</text>
            <text class="co-kv-value">{{ table_number }}</text>
          </view>
          <view
            class="co-kv-row"
            v-if="!(showPackFulfillmentBar && packFulfillmentMode === 'delivery')"
          >
            <text class="co-kv-label">人数</text>
            <text class="co-kv-value">{{ numberOfDiners }}人</text>
          </view>
          <view class="co-kv-row co-kv-row--last">
            <text class="co-kv-label">用餐方式</text>
            <text class="co-kv-value">{{ diningModeDisplayText }}</text>
          </view>
        </view>
      </view>

      <!-- 模块：商品清单 -->
      <view class="co-card">
        <view class="co-card-head co-card-head--border">
          <text class="co-card-title">已选菜品</text>
          <text class="co-card-badge">{{ goodsItemCount }}件</text>
        </view>
        <view class="goods-list">
          <view
            v-for="(item, index) in shoppingCart"
            :key="index"
            class="goods-row"
          >
            <view class="goods-thumb-wrap">
              <image
                class="goods-thumb"
                :src="getCartItemImageUrl(item)"
                mode="aspectFill"
                lazy-load
              />
            </view>
            <view class="goods-row-main">
              <view class="goods-title-line">
                <text class="goods-name">{{ item.name }}</text>
                <text v-if="item.isCombo" class="goods-tag">套餐</text>
              </view>
              <text
                v-if="item.isCombo && item.comboSummary"
                class="goods-desc"
              >{{ item.comboSummary }}</text>
              <text
                v-if="getSpicyText(item.selectedSpicy)"
                class="goods-desc"
              >{{ getSpicyText(item.selectedSpicy) }}</text>
            </view>
            <view class="goods-row-aside">
              <text v-if="!isDineInOrder" class="goods-price">
                ¥{{ formatCartLineUnitPrice(item) }}
              </text>
              <text class="goods-qty" :class="{ 'goods-qty--solo': isDineInOrder }">
                ×{{ item.quantity }}
              </text>
            </view>
          </view>
          <view v-if="appliesPackagingFee" class="goods-row goods-row--pack">
            <view class="goods-row-main goods-row-main--pack">
              <text class="goods-name">打包费</text>
              <text class="goods-desc">{{ packagingFeeHint }}</text>
            </view>
            <view class="goods-row-aside">
              <text v-if="!isDineInOrder" class="goods-price">
                ¥{{ packagingFee.toFixed(2) }}
              </text>
              <text class="goods-qty" :class="{ 'goods-qty--solo': isDineInOrder }">
                ×{{ packagingBoxCount }}
              </text>
            </view>
          </view>
        </view>
        
      </view>

      <!-- 模块：优惠券 -->
      <view
        v-if="showCouponSection"
        class="co-card co-card--tap"
        hover-class="co-card--tap-hover"
        @click="selectCoupon"
      >
        <view class="co-row-tap">
          <view class="co-row-left">
            <text class="co-row-title">优惠券</text>
          </view>
          <view class="co-row-right">
            <text class="co-row-value co-row-value--accent" v-if="selectedCoupon">
              {{ selectedCoupon.coupon_name }}
              <template v-if="selectedCoupon.coupon_type === 'discount'">({{ (selectedCoupon.discount_value / 10).toFixed(1) }}折)</template>
              <template v-else-if="selectedCoupon.coupon_type === 'full_reduction'">(满{{ selectedCoupon.min_amount }}减{{ selectedCoupon.discount_value }})</template>
              <template v-else-if="selectedCoupon.coupon_type === 'direct_reduction'">(无门槛减{{ selectedCoupon.discount_value }})</template>
            </text>
            <text class="co-row-value" v-else>
              <template v-if="availableCouponCount > 0">未选择<text class="co-muted">（{{ availableCouponCount }}张可用）</text></template>
              <template v-else-if="availableCouponCount === 0">没有可用券</template>
              <template v-else>未选择</template>
            </text>
            <text class="co-chevron">›</text>
          </view>
        </view>
      </view>
      <view v-else-if="showComboPaymentRestrictHint" class="co-card co-card--disabled">
        <view class="co-row-tap">
          <view class="co-row-left">
            <text class="co-row-title">优惠券</text>
          </view>
          <text class="co-row-hint">{{ comboPaymentRestrictMsg }}</text>
        </view>
      </view>

      <!-- 模块：费用明细（堂食不展示合计；堂食金额模糊） -->
      <view class="co-card" v-if="showFeeDetailCard">
        <view class="co-card-head">
          <text class="co-card-title">费用明细</text>
        </view>
        <view class="co-fee-list">
          <view class="co-fee-row">
            <text class="co-fee-label">商品总价</text>
            <text class="co-fee-value" :class="{ 'price-fuzzy': isDineInOrder }">
              ¥{{ goodsTotal.toFixed(2) }}
            </text>
          </view>
          <view class="co-fee-row" v-if="appliesPackagingFee && packagingFee > 0">
            <text class="co-fee-label">打包费</text>
            <text class="co-fee-value" :class="{ 'price-fuzzy': isDineInOrder }">
              ¥{{ packagingFee.toFixed(2) }}
            </text>
          </view>
          <view
            class="co-fee-row"
            v-if="packFulfillmentMode === 'delivery' && takeoutPreviewLoaded && takeoutDeliverable"
          >
            <text class="co-fee-label">配送费</text>
            <text
              class="co-fee-value co-fee-value--green"
              v-if="takeoutFreeDelivery"
            >免配送费</text>
            <text class="co-fee-value" v-else>¥{{ deliveryFee.toFixed(2) }}</text>
          </view>
          <view class="co-fee-row" v-if="serviceFeeApplies">
            <text class="co-fee-label">新年服务费(5%)</text>
            <text class="co-fee-value" :class="{ 'price-fuzzy': isDineInOrder }">
              ¥{{ serviceFeeAmount }}
            </text>
          </view>
          <view class="co-fee-row" v-if="couponDiscount > 0">
            <text class="co-fee-label">优惠券抵扣</text>
            <text
              class="co-fee-value co-fee-value--discount"
              :class="{ 'price-fuzzy': isDineInOrder }"
            >-¥{{ couponDiscount.toFixed(2) }}</text>
          </view>
          <view class="co-fee-row co-fee-total-row" v-if="!isDineInOrder">
            <text class="co-fee-label">合计</text>
            <text class="co-fee-value co-fee-amount">¥{{ finalTotalPrice }}</text>
          </view>
          <view class="co-dinein-fee-hint" v-else>
            <text>堂食订单以门店结账为准，具体金额请咨询服务员</text>
          </view>
        </view>
      </view>

      <!-- 模块：备注 -->
      <view class="co-card co-card--remark">
        <view class="co-card-head">
          <text class="co-card-title">订单备注</text>
          <text class="co-card-sub">选填</text>
        </view>
        <textarea
          v-model="remark"
          :placeholder="remarkPlaceholder"
          class="co-remark-input"
          maxlength="200"
          :show-confirm-bar="false"
        />
        <view class="co-remark-tip">{{ remark.length }}/200</view>
      </view>

      <view class="bottom-placeholder"></view>
    </scroll-view>

    <view class="submit-btn-container">
      <button
        @click="submitOrder"
        class="submit-order-btn"
        :disabled="isSubmitting"
      >
        {{ isSubmitting ? '提交中...' : (isAddDishes ? '确认加菜' : '确认提交订单') }}
      </button>
    </view>
    <global-activity-popup ref="globalActivityPopup" />
  </view>
</template>

<script>
import { getBaseUrl, requestUtil } from "../../utils/requestUtil.js";
import { staticUrl } from "../../utils/staticAssetUrl.js";
import { dishImageUrlOrDefault } from "../../utils/imageUrl.js";
import feieService from "../../utils/feie-service.js";
import { getCurrentShopId, getCurrentShopSnapshot } from "../../utils/shopContext.js";
import {
  countCouponsPassingLocalOrderRules,
  normalizeCouponListPayload,
  buildCouponOrderSelectionPayload,
  couponPassesLocalOrderRules,
  calculateCouponDiscount,
} from "../../utils/couponRules.js";
import {
  mapCartToGoodsList,
  cartHasComboLines,
  COMBO_PAYMENT_RESTRICT_MSG,
} from "../../utils/comboMeal.js";
import { orderAllowsCoupon } from "../../utils/couponRules.js";
import { getDinersCountOrDefault } from "../../utils/dinersCache.js";
import {
  normalizeTakeoutPreviewPayload,
  normalizeTakeoutConfigPayload,
} from "../../utils/takeoutPreview.js";
import {
  buildTakeoutPreviewAddressPayload,
  normalizeTakeoutAddress,
  validateGcj02Coordinates,
} from "../../utils/takeoutAddress.js";
import {
  needsPackagingFee,
  calcPackagingFee,
  getPackagingFeeHintText,
} from "../../utils/packagingFee.js";
import { promptLoginIfNeeded } from "../../utils/loginGuard.js";
import { createTakeoutOrder, persistOpenidFromResponse, isWxLoginExpiredResponse } from "../../utils/wxAuth.js";
import {
  getAvailableTakeoutScheduleSlots,
  resolveTakeoutScheduleDateTime,
  formatTakeoutScheduleRemark,
} from "../../utils/takeoutDeliverySchedule.js";
import {
  fetchPaymentCapabilities,
  isWechatPayAvailable,
  resolveWechatPayDisabledMessage,
} from "../../utils/paymentCapabilities.js";
import { requestSceneSubscribe } from '../../utils/wechatSubscribeManager.js';
const app = getApp();

// 新年服务费截止：2月23日后不收取（即 2025-02-24 00:00 起不再收取）
const SERVICE_FEE_CUTOFF = new Date('2026-02-24T00:00:00');
const MENU_TAB_URL = '/pages/home-page/page';

export default {
  data() {
    return {
      shoppingCart: [],      // 购物车商品列表
      goodsTotal: 0,
      packagingFee: 0,
      table_number: '',      // 桌号
      numberOfDiners: 0,     // 用餐人数
      dineInOrTakeOut: '堂食',   // 用餐方式，默认为堂食
      remark: '',            // 备注信息
      isSubmitting: false,   // 提交状态
      orderNumber: 1,        // 订单序号
      order_no: '',          // 订单编号
      isAddDishes: false,    // 是否是加菜操作
      orderUsedCoupon: false, // 加菜时原订单是否已用优惠券，已用则隐藏优惠券入口
      selectedSpicy:'',
      subscribeTemplateId1:'',
      subscribeTemplateId2:'',
      subscribeTmplIds: [],
      subscribeTemplatesLoading: null,
      authResult:'',
      packagingBoxCount: 0,
      showDiningModal: false, // 用餐方式选择弹窗
      openid:"",
      isProcessingPayment:false,
      selectedCoupon: null,  // 选中的优惠券
      availableCouponCount: null,
      paymentSuccess:false,
      currentStoreName: '老肥油边王',
      isPackOrderFlow: false,
      packFulfillmentMode: 'pickup',
      takeoutShopEnabled: false,
      takeoutMinOrderAmount: 0,
      deliveryFee: 0,
      meetMinOrderOk: true,
      takeoutPreviewLoaded: false,
      takeoutDeliverable: true,
      takeoutFreeDelivery: false,
      takeoutDistanceKm: null,
      takeoutUndeliverableMsg: "",
      takeoutFreeDeliveryThreshold: 168,
      selectedAddressId: null,
      selectedAddressSummary: '',
      selectedAddress: null,
      previewAddressSnapshot: null,
      previewRequestSeq: 0,
      takeoutDeliveryTiming: 'immediate',
      takeoutScheduledTime: '',
      takeoutScheduledSlotIndex: 0,
      availableScheduleSlots: [],
    }
  },
  async onLoad(options) {
    if (typeof app.guardToQueueIfReview === "function") {
      const redirected = await app.guardToQueueIfReview({ force: true });
      if (redirected) return;
    }
	this.selectedCoupon = null	
    wx.removeStorageSync("selected_coupon");
    

    if (options && options.order_no) {
      this.order_no = options.order_no;
      this.isAddDishes = true;
      this.dineInOrTakeOut = "堂食";
      this.orderUsedCoupon =options.order_used_coupon ;
      console.log(this.orderUsedCoupon);
    } 
    if (options && options.table_number) {
      this.table_number = options.table_number;
    }
    if (options && options.orderNumber) {
      this.orderNumber = parseInt(options.orderNumber);
    }
    this.refreshCurrentStoreName();
    console.log(this.table_number);
    this.loadSubscribeTemplates();
    this.loadOrderInfo();
    if (app && app.event && typeof app.event.on === 'function') {
      this._onUnifiedCouponGranted = () => this.fetchAvailableCouponCount();
      this._onUnifiedReselectCoupon = () => {
        this.fetchAvailableCouponCount();
        this.selectCoupon();
      };
      app.event.on('unified:coupon_granted', this._onUnifiedCouponGranted);
      app.event.on('unified:reselect_coupon', this._onUnifiedReselectCoupon);
    }
  },
  onUnload() {
    if (app && app.event && typeof app.event.off === 'function') {
      if (this._onUnifiedCouponGranted) app.event.off('unified:coupon_granted', this._onUnifiedCouponGranted);
      if (this._onUnifiedReselectCoupon) app.event.off('unified:reselect_coupon', this._onUnifiedReselectCoupon);
    }
  },
  async onShow() {
    if (typeof app.guardToQueueIfReview === "function") {
      const redirected = await app.guardToQueueIfReview();
      if (redirected) return;
    }
    if (typeof this.handleCouponPageShow === 'function') {
      this.handleCouponPageShow();
    }
    if (this.shoppingCart && this.shoppingCart.length > 0) {
      this.calculateTotalPrice();
    }
    if (this.showPackFulfillmentBar && this.packFulfillmentMode === "delivery") {
      this.syncSelectedAddressFromStorage();
      this.refreshTakeoutPreview();
      if (this.takeoutDeliveryTiming === "scheduled") {
        this.refreshAvailableScheduleSlots();
      }
    }
  },
  computed: {
    effectiveDineInOrTakeOut() {
      if (this.isPackOrderFlow && this.packFulfillmentMode === 'delivery') return '外卖';
      return this.dineInOrTakeOut || '堂食';
    },
    diningModeDisplayText() {
      if (this.showPackFulfillmentBar) {
        return this.packFulfillmentMode === 'delivery' ? '外卖配送' : '门店自提（打包）';
      }
      return this.dineInOrTakeOut || '堂食';
    },
    showTableNumberRow() {
      if (this.showPackFulfillmentBar && this.packFulfillmentMode === 'delivery') {
        return false;
      }
      const t = this.table_number;
      if (t == null) return false;
      return String(t).trim() !== '';
    },
    remarkPlaceholder() {
      if (this.effectiveDineInOrTakeOut === '外卖') {
        return '口味、忌口等要求；配送时间已在上方选择，将一并提交';
      }
      return '口味、忌口等要求，如：不要辣、少冰';
    },
    showPackFulfillmentBar() {
      return this.isPackOrderFlow && !this.isAddDishes;
    },
    isDineInOrder() {
      return this.effectiveDineInOrTakeOut === "堂食";
    },
    showFeeDetailCard() {
      if (!this.isDineInOrder) return true;
      return this.serviceFeeApplies || this.couponDiscount > 0;
    },
    goodsItemCount() {
      const cart = this.shoppingCart || [];
      let n = 0;
      for (let i = 0; i < cart.length; i++) {
        n += Number(cart[i].quantity) || 0;
      }
      if (this.appliesPackagingFee && this.packagingBoxCount > 0) {
        n += this.packagingBoxCount;
      }
      return n;
    },
    hasSelectedAddress() {
      return !!this.selectedAddressId && !!this.selectedAddressSummary;
    },
    normalizedSelectedAddress() {
      return normalizeTakeoutAddress(this.selectedAddress || {});
    },
    displayPoiName() {
      return this.normalizedSelectedAddress.poi_name || '地图选点';
    },
    displayAddressDetail() {
      return this.normalizedSelectedAddress.detail || '';
    },
    displayAddressFull() {
      const o = this.normalizedSelectedAddress;
      const region = [o.province, o.city, o.district].filter(Boolean).join('');
      const parts = [region, o.address].filter(Boolean);
      return parts.filter((value, index) => parts.indexOf(value) === index).join(' ');
    },
    displayDeliveryNote() {
      return this.normalizedSelectedAddress.delivery_note || '';
    },
    selectedAddressName() {
      const o = this.selectedAddress;
      return (o && o.contact_name) ? String(o.contact_name).trim() : "收货人";
    },
    selectedAddressPhoneMasked() {
      const phone = this.selectedAddress && this.selectedAddress.contact_phone;
      const s = String(phone || "").trim();
      if (s.length >= 11) return s.slice(0, 3) + "****" + s.slice(-4);
      return s || "";
    },
    selectedAddressTag() {
      const o = this.selectedAddress;
      const tag = o && (o.tag || o.address_tag);
      return tag ? String(tag).trim() : "";
    },
    showTakeoutDeliveryStatus() {
      return (
        this.packFulfillmentMode === "delivery" &&
        (this.hasSelectedAddress || this.takeoutPreviewLoaded)
      );
    },
    takeoutDeliveryStatusType() {
      if (!this.selectedAddressId) return "hint";
      if (!this.takeoutDeliverable) return "error";
      if (!this.takeoutPreviewLoaded) return "loading";
      if (!this.meetMinOrderOk) return "warning";
      return "ok";
    },
    takeoutDeliveryStatusText() {
      if (!this.selectedAddressId) {
        return "请选择收货地址，系统将按距离计算配送费";
      }
      if (!this.takeoutDeliverable) {
        return this.takeoutUndeliverableMsg || "当前地址超出配送范围，请更换地址";
      }
      if (!this.takeoutPreviewLoaded) {
        return "正在计算配送费…";
      }
      if (!this.meetMinOrderOk) {
        return `未满起送价 ¥${this.takeoutMinOrderAmount.toFixed(2)}，请再加购`;
      }
      const parts = [];
      if (this.takeoutDistanceKm != null) {
        parts.push(`配送约 ${this.takeoutDistanceKm} km`);
      }
      if (this.takeoutFreeDelivery) {
        parts.push(`已满 ¥${this.takeoutFreeDeliveryThreshold} 且 5km 内免配送费`);
      } else if (this.deliveryFee > 0) {
        parts.push(`配送费 ¥${this.deliveryFee.toFixed(2)}`);
      } else {
        parts.push("可配送");
      }
      return parts.join(" · ");
    },
    appliesPackagingFee() {
      return !this.isAddDishes && needsPackagingFee(this.effectiveDineInOrTakeOut);
    },
    packagingFeeHint() {
      return getPackagingFeeHintText();
    },
    cartHasCombo() {
      return cartHasComboLines(this.shoppingCart);
    },
    comboPaymentRestrictMsg() {
      return COMBO_PAYMENT_RESTRICT_MSG;
    },
    /** 堂食、加菜、含套餐：提交前不可选券 */
    couponAllowedForOrder() {
      return !this.isAddDishes && !this.cartHasCombo && !this.isDineInOrder;
    },
    showCouponSection() {
      return this.couponAllowedForOrder;
    },
    showComboPaymentRestrictHint() {
      return !this.isAddDishes && this.cartHasCombo;
    },
    couponDiscount() {
      if (!this.couponAllowedForOrder) return 0;
      return calculateCouponDiscount(this.selectedCoupon, this.getCouponOrderCtx());
    },

    serviceFeeApplies() {
      return new Date() < SERVICE_FEE_CUTOFF;
    },

    serviceFeeAmount() {
      if (!this.serviceFeeApplies) return '0.00';
      const base =
        this.goodsTotal +
        this.packagingFee +
        (this.packFulfillmentMode === 'delivery' ? Number(this.deliveryFee || 0) : 0);
      const fee = Math.round(base * 0.05 * 100) / 100;
      return fee.toFixed(2);
    },

    finalTotalPrice() {
      const base =
        this.goodsTotal +
        this.packagingFee +
        (this.packFulfillmentMode === 'delivery' ? Number(this.deliveryFee || 0) : 0);
      const serviceFee = this.serviceFeeApplies ? Math.round(base * 0.05 * 100) / 100 : 0;
      const total = base + serviceFee - this.couponDiscount;
      const preciseTotal = Math.round(total * 100) / 100;
      return Math.max(preciseTotal, 0).toFixed(2);
    }
  },
  methods: {
    staticUrl,
    normalizeSubscribeTemplateConfig(config) {
      const templates = config && config.templates && typeof config.templates === 'object'
        ? config.templates
        : {};
      const subscribeTemplateId1 = String(config && (config.subscribeTemplateId1 || templates.orderStatus) || '').trim();
      const subscribeTemplateId2 = String(config && (config.subscribeTemplateId2 || templates.pickupNotice) || '').trim();
      const couponGranted = String(templates.couponGranted || '').trim();
      const couponExpiring = String(templates.couponExpiring || '').trim();
      const sourceIds = Array.isArray(config && config.tmplIds) && config.tmplIds.length
        ? config.tmplIds
        : [subscribeTemplateId1, subscribeTemplateId2, couponGranted, couponExpiring];
      const tmplIds = Array.from(new Set(
        sourceIds.map(id => String(id || '').trim()).filter(Boolean)
      )).slice(0, 3);

      return {
        subscribeTemplateId1,
        subscribeTemplateId2,
        couponGranted,
        couponExpiring,
        tmplIds
      };
    },
    async loadSubscribeTemplates(force = false) {
      if (!force && this.subscribeTmplIds && this.subscribeTmplIds.length) {
        return {
          subscribeTemplateId1: this.subscribeTemplateId1,
          subscribeTemplateId2: this.subscribeTemplateId2,
          tmplIds: this.subscribeTmplIds
        };
      }
      if (this.subscribeTemplatesLoading) {
        return this.subscribeTemplatesLoading;
      }

      this.subscribeTemplatesLoading = requestUtil({
        url: '/config/subscribe-templates',
        method: 'GET',
        showLoading: false
      }).then(res => {
        const config = this.normalizeSubscribeTemplateConfig(res || {});
        this.subscribeTemplateId1 = config.subscribeTemplateId1;
        this.subscribeTemplateId2 = config.subscribeTemplateId2;
        this.subscribeTmplIds = config.tmplIds;
        return config;
      }).catch(err => {
        console.error('load subscribe templates failed:', err);
        return {
          subscribeTemplateId1: '',
          subscribeTemplateId2: '',
          tmplIds: []
        };
      }).finally(() => {
        this.subscribeTemplatesLoading = null;
      });

      return this.subscribeTemplatesLoading;
    },
    getCartItemImageUrl(item) {
      const raw =
        item &&
        (item.image || item.dish_image || item.cover_image || item.cover);
      return dishImageUrlOrDefault(raw, 'list');
    },
    refreshCurrentStoreName() {
      const s = getCurrentShopSnapshot();
      const n = (s && s.name && String(s.name).trim()) || '';
      this.currentStoreName = n || '老肥油边王';
    },
    getCouponOrderBaseTotal() {
      return Math.round((Number(this.goodsTotal || 0) + Number(this.packagingFee || 0)) * 100) / 100;
    },
    getCouponOrderCtx() {
      return buildCouponOrderSelectionPayload('confirm', {
        orderBaseTotal: this.getCouponOrderBaseTotal(),
        orderLines: Array.isArray(this.shoppingCart) ? this.shoppingCart : [],
        dineInOrTakeOut: this.effectiveDineInOrTakeOut || '堂食',
        currentShopId: getCurrentShopId(),
      }).ctx;
    },
    validateSelectedCoupon() {
      if (!this.selectedCoupon) return;
      const ctx = this.getCouponOrderCtx();
      if (!orderAllowsCoupon(ctx) || !couponPassesLocalOrderRules(this.selectedCoupon, ctx)) {
        wx.removeStorageSync("selected_coupon");
        this.selectedCoupon = null;
      }
    },
    clearCouponWhenComboInCart() {
      if (!cartHasComboLines(this.shoppingCart)) return;
      this.clearSelectedCoupon();
    },
    clearSelectedCoupon() {
      try {
        wx.removeStorageSync("selected_coupon");
      } catch (e) {
        /* ignore */
      }
      this.selectedCoupon = null;
      this.availableCouponCount = 0;
    },
    clearTableNumberCache() {
      this.table_number = '';
      try {
        wx.removeStorageSync('table_number');
      } catch (e) {}
      // 鍏煎鍏ㄥ眬甯﹁繃鏈熺紦字
      try {
        app.setStorageWithExpiry('table_number', '', 0);
      } catch (e) {}
    },

    handleCouponPageShow() {
      if (!this.couponAllowedForOrder) {
        this.clearSelectedCoupon();
        if (this.isAddDishes) return;
      }
      try {
        const cart = wx.getStorageSync("shopping_cart");
        if (Array.isArray(cart)) {
          this.shoppingCart = cart;
          this.calculateTotalPrice();
        }
      } catch (e) {
        /* ignore */
      }
      this.clearCouponWhenComboInCart();

      if (this.couponAllowedForOrder) {
        const selectedCoupon = wx.getStorageSync("selected_coupon");
        if (selectedCoupon !== this.selectedCoupon) {
          this.selectedCoupon = selectedCoupon;
          this.validateSelectedCoupon();
          this.calculateTotalPrice();
        }
      }

      this.$nextTick(() => {
        this.fetchAvailableCouponCount();
        if (this.showPackFulfillmentBar && this.packFulfillmentMode === 'delivery') {
          this.syncSelectedAddressFromStorage();
          this.refreshTakeoutPreview();
        }
      });
    },
    selectCoupon() {
      if (!this.couponAllowedForOrder) {
        if (this.isDineInOrder) {
          wx.showToast({ title: "堂食订单暂不可使用优惠券", icon: "none" });
        } else if (this.cartHasCombo) {
          wx.showToast({ title: COMBO_PAYMENT_RESTRICT_MSG, icon: "none", duration: 2800 });
        }
        return;
      }
      const payload = buildCouponOrderSelectionPayload('confirm', {
        orderBaseTotal: this.getCouponOrderBaseTotal(),
        orderLines: Array.isArray(this.shoppingCart) ? this.shoppingCart : [],
        dineInOrTakeOut: this.effectiveDineInOrTakeOut || '堂食',
        currentShopId: getCurrentShopId(),
      });
      wx.navigateTo({
        url: payload.navigateUrl,
        success: (res) => {
          try {
            if (res && res.eventChannel && typeof res.eventChannel.emit === "function") {
              res.eventChannel.emit("couponOrderCtx", { orderLines: payload.orderLines });
            }
          } catch (e) {}
        },
      });
    },
    loadOrderInfo() {
      try {
        this.numberOfDiners = getDinersCountOrDefault(app, 2);

        if (this.isAddDishes) {
          this.dineInOrTakeOut = "堂食";
          this.isPackOrderFlow = false;
        } else {
          let dining = "";
          try {
            if (typeof app.getStorageWithExpiry === "function") {
              dining = app.getStorageWithExpiry("dineInOrTakeOut") || "";
            }
          } catch (e) {
            /* ignore */
          }
          if (!dining) {
            dining = wx.getStorageSync("dineInOrTakeOut") || "堂食";
          }
          this.dineInOrTakeOut = dining;
          this.isPackOrderFlow = this.dineInOrTakeOut === "打包";
          this.packFulfillmentMode = "pickup";
          if (this.isPackOrderFlow) {
            this.bootstrapTakeoutShop();
          } else {
            this.takeoutShopEnabled = false;
            this.deliveryFee = 0;
            this.meetMinOrderOk = true;
            this.takeoutPreviewLoaded = false;
          }
        }

        const cartInfo = wx.getStorageSync("shopping_cart");
        this.shoppingCart =
          cartInfo && Array.isArray(cartInfo) && cartInfo.length > 0 ? cartInfo : [];
        this.calculateTotalPrice();

        this.clearCouponWhenComboInCart();
        if (!this.couponAllowedForOrder) {
          this.clearSelectedCoupon();
        }
        this.fetchAvailableCouponCount();
      } catch (error) {
        console.error("加载订单信息失败:", error);
        wx.showToast({
          title: '获取订单信息失败',
          icon: 'none'
        });
      }
    },

    async bootstrapTakeoutShop() {
      try {
        const res = await requestUtil({
          url: '/order/takeout/config',
          method: 'get',
          showLoading: false,
        });
        const cfgNorm = normalizeTakeoutConfigPayload(res);
        this.takeoutShopEnabled = cfgNorm.enabled;
        this.takeoutMinOrderAmount = cfgNorm.minOrderAmount;
        this.takeoutFreeDeliveryThreshold = cfgNorm.freeDeliveryThreshold;
      } catch (e) {
        this.takeoutShopEnabled = false;
      }
    },

    setPackFulfillmentMode(mode) {
      if (mode === 'delivery' && !this.takeoutShopEnabled) {
        wx.showToast({ title: '本店暂未开通外卖配送', icon: 'none' });
        return;
      }
      this.packFulfillmentMode = mode;
      if (mode === 'delivery') {
        this.syncSelectedAddressFromStorage();
        this.refreshTakeoutPreview();
      } else {
        this.resetTakeoutDeliveryTiming();
        this.deliveryFee = 0;
        this.meetMinOrderOk = true;
        this.takeoutPreviewLoaded = false;
        this.takeoutDeliverable = true;
        this.takeoutFreeDelivery = false;
        this.takeoutDistanceKm = null;
        this.takeoutUndeliverableMsg = "";
        this.previewAddressSnapshot = null;
      }
      this.calculateTotalPrice();
      this.$nextTick(() => this.fetchAvailableCouponCount());
    },

    resetTakeoutDeliveryTiming() {
      this.takeoutDeliveryTiming = 'immediate';
      this.takeoutScheduledTime = '';
      this.takeoutScheduledSlotIndex = 0;
      this.availableScheduleSlots = [];
    },

    refreshAvailableScheduleSlots() {
      const slots = getAvailableTakeoutScheduleSlots(new Date());
      this.availableScheduleSlots = slots;
      if (!slots.length) {
        this.takeoutScheduledTime = '';
        this.takeoutScheduledSlotIndex = 0;
        return;
      }
      const idx = slots.indexOf(this.takeoutScheduledTime);
      if (idx >= 0) {
        this.takeoutScheduledSlotIndex = idx;
      } else {
        this.takeoutScheduledSlotIndex = 0;
        this.takeoutScheduledTime = slots[0];
      }
    },

    setTakeoutDeliveryTiming(mode) {
      if (mode !== 'immediate' && mode !== 'scheduled') return;
      this.takeoutDeliveryTiming = mode;
      if (mode === 'scheduled') {
        this.refreshAvailableScheduleSlots();
      }
    },

    onTakeoutScheduleSlotChange(e) {
      const idx = Number((e && e.detail && e.detail.value) ?? 0);
      const slots = this.availableScheduleSlots || [];
      const safeIdx = idx >= 0 && idx < slots.length ? idx : 0;
      this.takeoutScheduledSlotIndex = safeIdx;
      this.takeoutScheduledTime = slots[safeIdx] || '';
    },

    buildDeliveryTimingRemarkLine() {
      if (this.effectiveDineInOrTakeOut !== '外卖') return '';
      if (this.takeoutDeliveryTiming === 'scheduled') {
        return formatTakeoutScheduleRemark(this.takeoutScheduledTime);
      }
      return '【配送时间】立即配送';
    },

    buildOrderRemark() {
      const parts = [];
      const timingLine = this.buildDeliveryTimingRemarkLine();
      if (timingLine) parts.push(timingLine);
      const userRemark = String(this.remark || '').trim();
      if (userRemark) parts.push(userRemark);
      return parts.join('；');
    },

    validateTakeoutDeliveryTiming() {
      if (this.effectiveDineInOrTakeOut !== '外卖') return true;
      if (this.takeoutDeliveryTiming !== 'scheduled') return true;
      this.refreshAvailableScheduleSlots();
      if (!this.availableScheduleSlots.length) {
        wx.showToast({ title: '当前暂无可预约时段', icon: 'none' });
        return false;
      }
      if (!this.takeoutScheduledTime) {
        wx.showToast({ title: '请选择预约配送时间', icon: 'none' });
        return false;
      }
      if (!this.availableScheduleSlots.includes(this.takeoutScheduledTime)) {
        wx.showToast({ title: '该时段已过期，请重新选择', icon: 'none' });
        this.refreshAvailableScheduleSlots();
        return false;
      }
      const scheduled = resolveTakeoutScheduleDateTime(
        this.takeoutScheduledTime,
        new Date()
      );
      if (!scheduled || Number.isNaN(scheduled.getTime())) {
        wx.showToast({ title: '预约时间无效，请重新选择', icon: 'none' });
        return false;
      }
      if (scheduled.getTime() <= Date.now()) {
        wx.showToast({ title: '预约时间须晚于当前时间', icon: 'none' });
        return false;
      }
      return true;
    },

    getConfirmOrderBackUrl() {
      const parts = [];
      if (this.order_no) parts.push(`order_no=${encodeURIComponent(this.order_no)}`);
      if (this.orderNumber) parts.push(`orderNumber=${this.orderNumber}`);
      if (this.table_number) parts.push(`table_number=${encodeURIComponent(this.table_number)}`);
      if (this.orderUsedCoupon) parts.push("order_used_coupon=true");
      const qs = parts.length ? `?${parts.join("&")}` : "";
      return `/packageOther/confirm-order/confirm-order${qs}`;
    },

    openAddressPicker() {
      if (!promptLoginIfNeeded({ backUrl: this.getConfirmOrderBackUrl() })) {
        return;
      }
      wx.navigateTo({
        url: "/packageOther/takeout-address/takeout-address?mode=pick",
      });
    },

    syncSelectedAddressFromStorage() {
      try {
        const id = wx.getStorageSync('takeout_selected_address_id');
        this.selectedAddressId = id != null && id !== '' ? Number(id) : null;
        if (!Number.isFinite(this.selectedAddressId) || this.selectedAddressId <= 0) {
          this.selectedAddressId = null;
        }
        const raw = wx.getStorageSync('takeout_selected_address');
        if (raw) {
          const o = typeof raw === 'string' ? JSON.parse(raw) : raw;
          const normalized = o && typeof o === 'object' ? normalizeTakeoutAddress(o) : null;
          if (normalized && Number(normalized.id) === Number(this.selectedAddressId)) {
            this.selectedAddress = normalized;
            const p = [normalized.province, normalized.city, normalized.district].filter(Boolean).join('');
            this.selectedAddressSummary = [p, normalized.poi_name, normalized.address, normalized.detail]
              .filter(Boolean)
              .join(' ');
          } else {
            this.selectedAddress = null;
            this.selectedAddressSummary = '';
          }
        } else {
          this.selectedAddress = null;
          this.selectedAddressSummary = '';
        }
      } catch (e) {
        this.selectedAddressId = null;
        this.selectedAddress = null;
        this.selectedAddressSummary = '';
      }
    },

    async refreshTakeoutPreview() {
      if (this.packFulfillmentMode !== "delivery" || !this.isPackOrderFlow) return;
      const requestSeq = ++this.previewRequestSeq;
      const shopIdNum = Number(getCurrentShopId());
      if (!Number.isFinite(shopIdNum) || shopIdNum <= 0) return;

      const openid = app.globalData.openid || wx.getStorageSync("openid");
      this.syncSelectedAddressFromStorage();
      const addressPayload = buildTakeoutPreviewAddressPayload({
        addressId: this.selectedAddressId,
        openid,
        address: this.selectedAddress,
      });
      if (!addressPayload) {
        this.takeoutPreviewLoaded = false;
        this.deliveryFee = 0;
        this.takeoutDeliverable = false;
        this.takeoutFreeDelivery = false;
        this.takeoutDistanceKm = null;
        this.takeoutUndeliverableMsg = this.selectedAddressId
          ? validateGcj02Coordinates(this.selectedAddress || {}).message
          : '';
        this.previewAddressSnapshot = null;
        return;
      }

      const goodsSub = Math.round((Number(this.goodsTotal || 0) + Number(this.packagingFee || 0)) * 100) / 100;
      this.takeoutPreviewLoaded = false;
      this.takeoutDeliverable = true;
      this.takeoutUndeliverableMsg = '';
      this.previewAddressSnapshot = null;
      this.deliveryFee = 0;
      try {
        const res = await requestUtil({
          url: "/order/takeout/preview",
          method: "post",
          data: {
            shop_id: shopIdNum,
            ...addressPayload,
            goods_subtotal: goodsSub,
            goods_list: mapCartToGoodsList(this.shoppingCart || []),
          },
          showLoading: false,
        });
        if (requestSeq !== this.previewRequestSeq) return;
        if (!res || res.code !== 0) {
          this.takeoutPreviewLoaded = false;
          this.previewAddressSnapshot = null;
          const msg = (res && (res.msg || res.message)) || "";
          if (/坐标|经纬|coordinate/i.test(msg)) {
            this.takeoutDeliverable = false;
            this.takeoutUndeliverableMsg = '后端判定地址坐标类型或范围错误，请重新选点';
          } else if (/配送范围|超出范围|不可配送/.test(msg)) {
            this.takeoutDeliverable = false;
            this.takeoutUndeliverableMsg = msg || '当前地址超出配送范围';
          }
          if (msg) wx.showToast({ title: msg, icon: "none", duration: 2800 });
          return;
        }
        const norm = normalizeTakeoutPreviewPayload(res, { goodsSubtotal: goodsSub });
        this.deliveryFee = norm.deliveryFee;
        this.takeoutFreeDelivery = norm.freeDelivery;
        this.takeoutDeliverable = norm.deliverable;
        this.takeoutDistanceKm = norm.distanceKm;
        this.takeoutUndeliverableMsg = norm.undeliverableMsg;
        if (norm.minOrderAmount != null) {
          this.takeoutMinOrderAmount = norm.minOrderAmount;
        }
        this.meetMinOrderOk = norm.meetMinOrderOk;
        if (norm.freeDeliveryThreshold != null) {
          this.takeoutFreeDeliveryThreshold = norm.freeDeliveryThreshold;
        }
        this.takeoutPreviewLoaded = true;
        this.previewAddressSnapshot = {
          addressId: addressPayload.address_id,
          lat: addressPayload.lat,
          lng: addressPayload.lng,
          coordinateType: addressPayload.coordinate_type,
        };
      } catch (e) {
        if (requestSeq !== this.previewRequestSeq) return;
        this.takeoutPreviewLoaded = false;
        this.previewAddressSnapshot = null;
        this.takeoutDeliverable = false;
        this.takeoutUndeliverableMsg = '网络异常，配送费计算失败，请重试';
      }
    },

    async fetchAvailableCouponCount() {
      if (!this.couponAllowedForOrder) {
        this.clearSelectedCoupon();
        return;
      }
      const openid = app.globalData.openid || wx.getStorageSync('openid');
      if (!openid) return;
      try {
        const res = await requestUtil({
          url: '/coupon/getUserAvailableCoupons',
          method: 'post',
          data: { openid },
          showLoading: false
        });
        if (res && res.code === 0) {
          const raw = normalizeCouponListPayload(res);
          const ctx = this.getCouponOrderCtx();
          this.availableCouponCount = countCouponsPassingLocalOrderRules(raw, ctx);
          this.validateSelectedCoupon();
        } else {
          this.availableCouponCount = 0;
        }
      } catch (e) {
        console.error('获取可用优惠券数量失败', e);
        this.availableCouponCount = 0;
      }
    },


    async handleCheckout() {
      if (this.isProcessingPayment) return;
      const paymentCaps = await fetchPaymentCapabilities({
        orderNo: this.order_no || undefined,
      });
      if (!isWechatPayAvailable(paymentCaps)) {
        this.showToastMessage(resolveWechatPayDisabledMessage(paymentCaps));
        return;
      }
      this.isProcessingPayment = true;
      try {
        const comboBlocksPromo = cartHasComboLines(this.shoppingCart);
        const couponOk = this.couponAllowedForOrder && !comboBlocksPromo;
        const result = await app.payOrder({
          orderNo: this.order_no,
          totalAmount: this.finalTotalPrice * 1,
          dineInOrTakeOut: this.effectiveDineInOrTakeOut,
          coupon_id: couponOk && this.selectedCoupon ? this.selectedCoupon.id || "" : "",
          coupon_type: couponOk && this.selectedCoupon ? this.selectedCoupon.coupon_type || "" : "",
          discount_amount: couponOk ? this.couponDiscount || 0 : 0,
        });
        if (result && result.success) {
          this.showToastMessage('微信支付成功，已结账');
          this.paymentSuccess = true;
        } else {
          if (!app.globalData.openid) {
            this.showToastMessage('支付失败: 未登录小程序');
          } else {
            const msg = (result && result.response && (result.response.message || result.response.msg)) || (result && result.error && result.error.message) || '未知错误';
            this.showToastMessage(`支付失败: ${msg}`);
          }
          this.paymentSuccess = false;
        }
      } catch (error) {
        console.error('微信支付失败:', error);
        this.showToastMessage('支付过程中发生错误，请重试');
        this.paymentSuccess = false;
      } finally {
        this.isProcessingPayment = false;
      }
    },

    showToastMessage(message) {
      wx.showToast({
        title: message,
        icon: 'none',
        duration: 3000
      });
    },

    calculateTotalPrice() {

      this.goodsTotal = this.shoppingCart.reduce((total, item) => {

        const itemPrice = item.total_price || (item.unitprice * item.quantity);
        // 解决精度问题：转整数计算
        return Math.round(total * 100 + itemPrice * 100) / 100;
      }, 0);


      if (needsPackagingFee(this.effectiveDineInOrTakeOut)) {
        const pack = calcPackagingFee(this.goodsTotal);
        this.packagingBoxCount = pack.boxCount;
        this.packagingFee = pack.fee;
      } else {
        this.packagingBoxCount = 0;
        this.packagingFee = 0;
      }


      console.log(`商品总价: ${this.goodsTotal}, 打包费: ${this.packagingFee}, 优惠券抵扣: ${this.couponDiscount}`);
      if (this.showPackFulfillmentBar && this.packFulfillmentMode === "delivery") {
        this.refreshTakeoutPreview();
      }
    },
    formatCartLineUnitPrice(item) {
      if (!item) return "0.00";
      if (item.isCombo || item.combo_id) {
        const q = Math.max(1, Number(item.quantity) || 1);
        const tp = Number(item.total_price);
        if (Number.isFinite(tp)) return (tp / q).toFixed(2);
      }
      const u = Number(item.unitprice);
      return Number.isFinite(u) ? u.toFixed(2) : "0.00";
    },
    getSpicyText(spicy) {
      if (!spicy) return '';

      // 1) JSON 字符串：{"mild":"涓嶈荆"}
      // 2) 纯文本：不辣 / 微辣
      if (typeof spicy === 'object') {
        const result = Object.entries(spicy).map(([, value]) => `${value}`).join(',');
        return result || '';
      }
      const raw = String(spicy).trim();
      if (!raw) return '';
      if (raw.startsWith('{') || raw.startsWith('[')) {
        try {
          const parsed = JSON.parse(raw);
          if (parsed && typeof parsed === 'object') {
            return Object.entries(parsed).map(([, value]) => `${value}`).join(',') || raw;
          }
        } catch (e) {
          return raw;
        }
      }
      return raw;
    },

    goBack() {
      wx.navigateBack();
    },

    showOrderFailModal(message) {
      wx.showModal({
        title: '提示',
        content: message || '下单失败，请重试',
        showCancel: false,
        confirmText: '我知道了',
        success: (res) => {
          if (res.confirm) {
            wx.switchTab({ url: MENU_TAB_URL });
          }
        }
      });
    },
    // 选择用餐方式 - 仅在非加菜模式下可用
    selectDiningType(type) {
      if (!this.isAddDishes) {
        this.dineInOrTakeOut = type;
        // 淇濆瓨鐢ㄩ鏂瑰紡鍒版湰鍦板瓨鍌?
        wx.setStorageSync('dineInOrTakeOut', type);
        this.calculateTotalPrice(); // 鍒囨崲鍚庨噸鏂拌绠楁€讳环
      }
    },

    async submitOrder() {
      // 已有提交在进行中，直接返回，防止重复下单
      if (this.isSubmitting) return;

      // 未登录或未绑定手机号：跳转我的页登录，并提示
      const openid = app.globalData.openid || wx.getStorageSync('openid');
      const userInfo = app.globalData.userInfo || wx.getStorageSync('userInfo') || {};
      const hasPhone = userInfo && userInfo.phone && String(userInfo.phone).trim();
      if (!openid || !hasPhone) {
        const url = `/packageOther/confirm-order/confirm-order?order_no=${this.order_no}&orderNumber=${this.orderNumber || 1}&table_number=${this.table_number}&order_used_coupon=${this.orderUsedCoupon ? true : false}`;
        app.checkLogin(url);
        wx.showToast({ title: '请先登录并绑定手机号', icon: 'none' });
        return;
      }


      if (this.shoppingCart.length === 0 || this.goodsTotal <= 0) {
        wx.showToast({
          title: '购物车为空',
          icon: 'none'
        });
        return;
      }
      const shopIdNum = Number(getCurrentShopId());
      if (!Number.isFinite(shopIdNum) || shopIdNum <= 0) {
        wx.showToast({ title: '请先选择门店后再下单', icon: 'none' });
        return;
      }
      if (this.isPackOrderFlow && this.packFulfillmentMode === 'delivery') {
        await this.refreshTakeoutPreview();
      }
      if (this.effectiveDineInOrTakeOut === '外卖') {
        if (!this.takeoutShopEnabled) {
          wx.showToast({ title: '本店暂未开通外卖配送', icon: 'none' });
          return;
        }
        if (!this.selectedAddressId) {
          wx.showToast({ title: '请选择收货地址', icon: 'none' });
          return;
        }
        const coordinate = validateGcj02Coordinates(this.selectedAddress || {});
        if (!coordinate.valid) {
          wx.showToast({ title: coordinate.message, icon: 'none', duration: 2800 });
          return;
        }
        if (!this.takeoutPreviewLoaded) {
          wx.showToast({ title: "请先选择地址并等待配送费计算", icon: "none" });
          return;
        }
        const snapshot = this.previewAddressSnapshot;
        if (
          !snapshot ||
          Number(snapshot.addressId) !== Number(this.selectedAddressId) ||
          snapshot.lat !== coordinate.lat ||
          snapshot.lng !== coordinate.lng ||
          snapshot.coordinateType !== 'gcj02'
        ) {
          wx.showToast({ title: '收货地址已变化，请等待配送费重新计算', icon: 'none', duration: 2800 });
          return;
        }
        if (!this.takeoutDeliverable) {
          wx.showToast({
            title: this.takeoutUndeliverableMsg || "超出配送范围",
            icon: "none",
            duration: 2800,
          });
          return;
        }
        if (!this.meetMinOrderOk) {
          wx.showToast({ title: "未达起送价，请继续加购", icon: "none" });
          return;
        }
        if (!this.validateTakeoutDeliveryTiming()) {
          return;
        }
      }
      const submitRemark = this.buildOrderRemark();
      if (submitRemark.length > 500) {
        wx.showToast({ title: '备注内容过长，请精简后重试', icon: 'none' });
        return;
      }
      // 璁剧疆涓烘彁浜や腑鐘舵€?
      this.isSubmitting = true;
      await this.requestSubscribeMessage();
      this.clearCouponWhenComboInCart();
      if (!this.couponAllowedForOrder) {
        this.clearSelectedCoupon();
      }

      try {
        const comboBlocksPromo = cartHasComboLines(this.shoppingCart);

        const deliveryYuan =
          this.effectiveDineInOrTakeOut === '外卖'
            ? Math.round(Number(this.deliveryFee || 0) * 100) / 100
            : 0;
        const goodsAndPack = Math.round((this.goodsTotal + this.packagingFee) * 100) / 100;
        const settCore = Math.round((goodsAndPack + deliveryYuan) * 100) / 100;
        const serviceFee = this.serviceFeeApplies ? Math.round(settCore * 0.05 * 100) / 100 : 0;

        const couponOk = this.couponAllowedForOrder && !comboBlocksPromo;
        const orderData = {
          coupon_id: couponOk && this.selectedCoupon ? this.selectedCoupon.id || "" : "",
          coupon_type: couponOk && this.selectedCoupon ? this.selectedCoupon.coupon_type || "" : "",
          discount_amount: couponOk ? this.couponDiscount || 0 : 0,
          table_number: this.effectiveDineInOrTakeOut === '外卖' ? (this.table_number || '外卖') : this.table_number,
          number_of_diners: this.numberOfDiners,
          sett_amount: settCore,
          service_fee: serviceFee, // 新年服务费?5%
          order_no: this.order_no,
          transac_status: 'unsettled', // 结账鐘舵€?
          order_receiving: 'mis_order', // 鎺ュ崟鐘舵€?
          goods_list: mapCartToGoodsList(this.shoppingCart),
          dineInOrTakeOut: this.effectiveDineInOrTakeOut,
          number_of_times: this.isAddDishes ? this.orderNumber : 0,
          orderStatus: "pending",
          orderNumber: this.isAddDishes ? this.orderNumber : 1,
          order_time: Date.now(),
          remark: submitRemark,
          qrCodeUrl: "https://u.wechat.com/EF9MZwaAbHhL79QCtBgAVAA?s=2",

          packagingBoxCount: this.packagingBoxCount,
          packagingFee: this.packagingFee,
          openid: app.globalData.openid,
          shop_id: shopIdNum,
        };
        // 鎻愪氦璁㈠崟鍒版湇鍔″櫒
        let response;
        if (this.isAddDishes) {
          // 鍔犺彍鎿嶄綔
          response = await requestUtil({
            url: "/order/addDishes",
            data: orderData,
            method: "post"
          });
        } else if (this.effectiveDineInOrTakeOut === '外卖') {
          const coordinate = validateGcj02Coordinates(this.selectedAddress || {});
          response = await createTakeoutOrder({
            ...orderData,
            address_id: this.selectedAddressId,
            addressId: this.selectedAddressId,
            lat: coordinate.lat,
            lng: coordinate.lng,
            coordinate_type: 'gcj02',
          });
          persistOpenidFromResponse(response, app);
          if (isWxLoginExpiredResponse(response)) {
            wx.showToast({ title: response.msg || '登录已失效，请重试', icon: 'none' });
            return;
          }
        } else {
          
          response = await requestUtil({
            url: "/order/create",
            data: orderData,
            method: "post"
          });
        }

        if (response && response.code === 0) {
          // 先写回后端返回的订单号：打包支付/鍚庣画璺宠浆閮戒緷璧栧畠
          this.order_no = response.order_no;
          orderData.order_no = response.order_no;
          
           if (this.effectiveDineInOrTakeOut === '打包' || this.effectiveDineInOrTakeOut === '外卖') {
            await this.handleCheckout();
            if (this.paymentSuccess !== true) {
              wx.showToast({
                title: "订单未支付成功",
                icon: 'none'
              });
            }
          }

          // this.order_no = response.order_no ;

          if (this.subscribeTemplateId1 && this.authResult && this.authResult[this.subscribeTemplateId1] === 'accept') {
            await this.sendSubscribeMessage(orderData,response.id);
          }
          if(this.subscribeTemplateId2 && this.authResult && this.authResult[this.subscribeTemplateId2] === 'accept'){
            this.notice(orderData.order_no);
          }
         
          wx.setStorageSync('current_order', orderData);

          wx.removeStorageSync('shopping_cart');
          wx.removeStorageSync('selected_coupon');
          // 跳转到订单详情页
          setTimeout(() => {
            wx.reLaunch({
              url: '/packageOther/order-details/details?order_no=' + this.order_no
            });
          },100);
        } else if(response && response.code === 1001) {
          this.showOrderFailModal('请勿同时提交订单');
        } else {
          const errorMsg = response?.message || response?.msg || '下单失败，请重试';
          if (/台号不存在|桌号不存在|无效的桌台号/.test(String(errorMsg))) {
            this.clearTableNumberCache();
          }
          this.showOrderFailModal(errorMsg);
        }
      } catch (error) {
        console.error("提交订单失败:", error);
        this.showOrderFailModal('网络异常，下单失败');
      } finally {

        this.isSubmitting = false;
      }
    },
    
    
    async requestSubscribeMessage() {
      const openid = this.openid || (app && app.globalData && app.globalData.openid) || wx.getStorageSync('openid');
      const fallbackConfig = await this.loadSubscribeTemplates();
      const res = await requestSceneSubscribe('ORDER_PICKUP', {
        openid,
        shopId: Number(getCurrentShopId()) || 1,
        fallbackTemplates: fallbackConfig,
        showToast: true,
      });

      if (res && res.authResults) {
        this.authResult = res.authResults;
        return res.authResults;
      }
      this.authResult = {};
      return null;
    },
    
    async sendSubscribeMessage(orderData,Id) {
      if (!this.subscribeTemplateId1) {
        return;
      }
      try {
        const res = await requestUtil({
          url: "/order/sendSubscribe",
          method: "POST",
          data: {
            openid: wx.getStorageSync('openid'),
            order_no: orderData.order_no,
            templateId: this.subscribeTemplateId1,
            data: {
              character_string3: { value: String(Id).slice(0, 20) },
              phrase5: { value: `已接单` },
              thing6: { value: String(this.currentStoreName || '老肥油边王').slice(0, 20) },
              time4: { value: this.formatDate(orderData.order_time) },
              thing9:{value: (orderData.remark || '无备注').slice(0, 20) }
            }
          }
        });
        
        if (res.code === 0) {
          console.log("订阅消息发送请求成功");
        } else {
          console.error("订阅消息发送请求失败", res.msg);
        }
      } catch (error) {
        console.error("调用发送订阅消息接口失败", error);
      }
    },
	async notice(order_no) {
	  try {
	    const res = await requestUtil({
	      url: "/order/notice",
	      method: "POST",
	      data: {
	        "order_no":order_no,
			"notice":1
	      }
	    });
	    
	    if (res.code === 0) {
	      
	    } else {
	      console.error("取餐订阅消息发送请求失败", res.msg);
	    }
	  } catch (error) {
	    console.error("调用发送订阅消息接口失败", error);
	  }
	},
    
    generateOrderNo() {
      const date = new Date();
      return 'ORD' + 
             date.getFullYear() + 
             this.padZero(date.getMonth() + 1) + 
             this.padZero(date.getDate()) + 
             this.padZero(date.getHours()) + 
             this.padZero(date.getMinutes()) + 
             this.padZero(date.getSeconds()) + 
             Math.floor(Math.random() * 1000);
    },
    
    padZero(num) {
      return num < 10 ? '0' + num : num;
    },
    
    formatDate(timestamp) {
      if (!timestamp) return ''
      const date = new Date(timestamp)
      return date.getFullYear() + '-' + 
             (date.getMonth() + 1).toString().padStart(2, '0') + '-' + 
             date.getDate().toString().padStart(2, '0') + ' ' + 
             date.getHours().toString().padStart(2, '0') + ':' + 
             date.getMinutes().toString().padStart(2, '0')
    }
  }
}
</script>

<style scoped>
/* ========== 页面骨架（美团式灰底 + 卡片间距） ========== */
.confirm-order-page {
  min-height: 100vh;
  display: flex;
  flex-direction: column;
  background: #f5f5f5;
}

.main-content {
  flex: 1;
  overflow-y: auto;
  padding: 16rpx 16rpx 0;
  box-sizing: border-box;
}

.bottom-placeholder {
  height: calc(140rpx + env(safe-area-inset-bottom));
}

/* ========== 通用卡片 ========== */
.co-card {
  background: #fff;
  border-radius: 20rpx;
  padding: 24rpx 22rpx 20rpx;
  margin-bottom: 20rpx;
  box-shadow: 0 2rpx 16rpx rgba(0, 0, 0, 0.04);
}

.co-card--notice {
  display: flex;
  align-items: flex-start;
  padding: 20rpx 22rpx;
  background: linear-gradient(135deg, #fff8e6 0%, #ffecd2 100%);
  border: 1rpx solid #f0c674;
  box-shadow: none;
}

.co-notice-text {
  flex: 1;
  font-size: 26rpx;
  font-weight: 600;
  color: #b8860b;
  line-height: 1.45;
}

.co-card--tap {
  padding: 0;
}

.co-card--tap-hover {
  opacity: 0.92;
}

.co-card--disabled {
  opacity: 0.88;
}

.co-card--remark {
  padding-bottom: 20rpx;
}

.co-card-head {
  display: flex;
  align-items: center;
  margin-bottom: 20rpx;
}

.co-card-head--border {
  width: 100%;
  padding-bottom: 20rpx;
  margin-bottom: 8rpx;
  border-bottom: 1rpx solid #f0f0f0;
  box-sizing: border-box;
}

.co-card-title {
  font-size: 26rpx;
  font-weight: 400;
  color: #999;
}

.co-card-sub {
  margin-left: 12rpx;
  font-size: 24rpx;
  color: #999;
  font-weight: 400;
}

.co-card-badge {
  margin-left: auto;
  font-size: 24rpx;
  color: #999;
}

/* 键值列表（订单信息） */
.co-kv-list {
  padding-top: 4rpx;
}

.co-kv-row {
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: 18rpx 0;
  border-bottom: 1rpx solid #f5f5f5;
}

.co-kv-row--last,
.co-kv-row:last-child {
  border-bottom: none;
  padding-bottom: 0;
}

.co-kv-label {
  font-size: 28rpx;
  font-weight: 400;
  color: #999;
  flex-shrink: 0;
  width: 140rpx;
}

.co-kv-value {
  font-size: 28rpx;
  font-weight: 400;
  color: #333;
  text-align: right;
  flex: 1;
  margin-left: 24rpx;
  line-height: 1.45;
  word-break: break-all;
}

.co-kv-value--strong {
  font-weight: 600;
  color: #222;
}

/* 可点击行（优惠券） */
.co-row-tap {
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: 24rpx 22rpx;
  min-height: 96rpx;
  box-sizing: border-box;
}

.co-row-left {
  display: flex;
  align-items: center;
  flex-shrink: 0;
}

.co-row-title {
  font-size: 28rpx;
  font-weight: 400;
  color: #666;
}

.co-row-right {
  display: flex;
  align-items: center;
  justify-content: flex-end;
  flex: 1;
  min-width: 0;
  margin-left: 16rpx;
}

.co-row-value {
  font-size: 28rpx;
  font-weight: 400;
  color: #666;
  text-align: right;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
  max-width: 380rpx;
}

.co-row-value--accent {
  color: #e10606;
  font-weight: 600;
}

.co-muted {
  color: #999;
  font-size: 24rpx;
}

.co-chevron {
  flex-shrink: 0;
  margin-left: 8rpx;
  font-size: 32rpx;
  color: #ccc;
  font-weight: 300;
  line-height: 1;
}

.co-row-hint {
  flex: 1;
  margin-left: 16rpx;
  font-size: 24rpx;
  color: #999;
  text-align: right;
  line-height: 1.4;
}

/* 费用明细 */
.co-fee-list {
  padding: 4rpx 0 8rpx;
}

.co-fee-row {
  display: flex;
  justify-content: space-between;
  align-items: center;
  padding: 14rpx 0;
}

.co-fee-label {
  font-size: 28rpx;
  font-weight: 400;
  color: #666;
}

.co-fee-value {
  font-size: 28rpx;
  color: #222;
  font-weight: 500;
}

.co-fee-value--discount {
  color: #eb5941;
  font-weight: 500;
}

.co-fee-value--green {
  color: #00a870;
  font-weight: 500;
}

.co-fee-total-row {
  margin-top: 8rpx;
  padding-top: 16rpx;
  border-top: 1rpx dashed #eee;
}

.co-fee-total-row .co-fee-label {
  font-weight: 500;
  color: #333;
}

.co-fee-amount {
  font-size: 30rpx;
  font-weight: 600;
  color: #222;
}

/* 备注 */
.co-remark-input {
  width: 100%;
  min-height: 140rpx;
  padding: 18rpx 20rpx;
  font-size: 28rpx;
  font-weight: 400;
  color: #333;
  background: #f8f8f8;
  border-radius: 12rpx;
  border: none;
  box-sizing: border-box;
  line-height: 1.5;
}

.co-remark-tip {
  margin-top: 12rpx;
  font-size: 24rpx;
  color: #bbb;
  text-align: right;
}

/* ========== 商品清单 ========== */
.goods-list {
  padding-top: 4rpx;
}

.goods-row {
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: 24rpx 0;
  border-bottom: 1rpx solid #f5f5f5;
}

.goods-thumb-wrap {
  flex-shrink: 0;
  width: 120rpx;
  height: 120rpx;
  margin-right: 20rpx;
  border-radius: 12rpx;
  overflow: hidden;
  background: #f5f5f5;
}

.goods-thumb {
  width: 120rpx;
  height: 120rpx;
  display: block;
}

.goods-row:last-child {
  border-bottom: none;
  padding-bottom: 4rpx;
}

.goods-row-main {
  flex: 1;
  min-width: 0;
  padding-right: 16rpx;
  align-self: center;
}

.goods-title-line {
  display: flex;
  align-items: flex-start;
  flex-wrap: wrap;
  gap: 10rpx;
}

.goods-name {
  font-size: 28rpx;
  font-weight: 600;
  color: #222;
  line-height: 1.4;
  word-break: break-all;
}

.goods-tag {
  flex-shrink: 0;
  margin-top: 4rpx;
  padding: 2rpx 10rpx;
  font-size: 20rpx;
  color: #e10606;
  border: 1rpx solid rgba(225, 6, 6, 0.35);
  border-radius: 6rpx;
  line-height: 1.35;
}

.goods-desc {
  display: block;
  margin-top: 8rpx;
  font-size: 24rpx;
  font-weight: 400;
  color: #8d8d8d;
  line-height: 1.25;
  word-break: break-all;
}

.goods-row-aside {
  flex-shrink: 0;
  display: flex;
  flex-direction: column;
  align-items: flex-end;
  min-width: 112rpx;
}

.goods-price {
  font-size: 28rpx;
  font-weight: 500;
  color: #222;
  line-height: 1.3;
}

.goods-qty {
  margin-top: 8rpx;
  font-size: 26rpx;
  color: #999;
  font-weight: 400;
  line-height: 1.2;
}

.goods-qty--solo {
  margin-top: 0;
  font-size: 28rpx;
  color: #666;
  font-weight: 600;
}

.goods-row--pack {
  padding-left: 0;
}

.goods-row-main--pack {
  padding-left: 140rpx;
  box-sizing: border-box;
}

.goods-row--pack .goods-name {
  font-weight: 600;
  font-size: 28rpx;
}

.goods-row--pack .goods-price {
  font-size: 28rpx;
  color: #222;
}

/* 堂食：模糊价格，弱化金额边界 */
.price-fuzzy {
  color: #222 !important;
  filter: blur(6rpx);
  opacity: 0.72;
  letter-spacing: 2rpx;
}

.co-dinein-fee-hint {
  margin-top: 16rpx;
  padding-top: 20rpx;
  border-top: 1rpx dashed #eee;
}

.co-dinein-fee-hint text {
  display: block;
  font-size: 24rpx;
  color: #999;
  line-height: 1.5;
  text-align: center;
}

.co-dinein-fee-hint--goods {
  margin-top: 8rpx;
  padding-top: 16rpx;
  border-top: 1rpx dashed #eee;
}


/* —— 外卖模块 —— */
.takeout-module {
  padding-bottom: 8rpx;
}

.takeout-mode-tabs {
  display: flex;
  gap: 16rpx;
  margin-bottom: 24rpx;
  padding: 8rpx;
  background: #f5f5f5;
  border-radius: 16rpx;
}

.takeout-mode-tab {
  flex: 1;
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  padding: 20rpx 12rpx;
  border-radius: 12rpx;
  border: 2rpx solid transparent;
  transition: background 0.2s;
}

.takeout-mode-tab.active {
  background: linear-gradient(to right, #ff5117, #f0331a, #e10606);
  border-color: #e10606;
  box-shadow: 0 4rpx 16rpx rgba(225, 6, 6, 0.28);
}

.takeout-mode-tab .tab-main {
  font-size: 28rpx;
  font-weight: 500;
  color: #666;
  line-height: 1.3;
}

.takeout-mode-tab.active .tab-main {
  color: #ffffff;
  font-weight: 600;
}

.takeout-mode-tab .tab-sub {
  margin-top: 6rpx;
  font-size: 22rpx;
  color: #999;
}

.takeout-mode-tab.active .tab-sub {
  color: rgba(255, 255, 255, 0.88);
}

.takeout-delivery-timing {
  margin-top: 20rpx;
}

.takeout-timing-label {
  display: block;
  font-size: 26rpx;
  font-weight: 400;
  color: #999;
  margin-bottom: 16rpx;
}

.takeout-timing-options {
  display: flex;
  gap: 16rpx;
}

.takeout-timing-option {
  flex: 1;
  display: flex;
  align-items: center;
  justify-content: center;
  padding: 18rpx 12rpx;
  border-radius: 12rpx;
  background: #f5f5f5;
  border: 2rpx solid transparent;
  box-sizing: border-box;
}

.takeout-timing-option text {
  font-size: 28rpx;
  font-weight: 400;
  color: #666;
}

.takeout-timing-option.active {
  background: #fff5f3;
  border-color: #e10606;
}

.takeout-timing-option.active text {
  color: #e10606;
  font-weight: 600;
}

.takeout-schedule-pickers {
  margin-top: 16rpx;
  background: #fafafa;
  border-radius: 12rpx;
  border: 1rpx solid #f0f0f0;
  overflow: hidden;
}

.takeout-schedule-picker {
  display: flex;
  align-items: center;
  padding: 22rpx 20rpx;
  border-bottom: 1rpx solid #f0f0f0;
}

.takeout-schedule-picker--solo {
  border-bottom: none;
}

.takeout-schedule-empty {
  padding: 28rpx 20rpx;
  text-align: center;
}

.takeout-schedule-empty text {
  font-size: 26rpx;
  font-weight: 400;
  color: #999;
  line-height: 1.45;
}

.takeout-schedule-picker-k {
  flex-shrink: 0;
  width: 72rpx;
  font-size: 28rpx;
  font-weight: 400;
  color: #999;
}

.takeout-schedule-picker-v {
  flex: 1;
  font-size: 28rpx;
  font-weight: 500;
  color: #222;
  text-align: right;
  padding-right: 8rpx;
}

.takeout-schedule-picker-v--placeholder {
  font-weight: 400;
  color: #bbb;
}

.takeout-schedule-hint {
  display: block;
  padding: 14rpx 20rpx 18rpx;
  font-size: 24rpx;
  font-weight: 400;
  color: #999;
  line-height: 1.45;
}

.takeout-address-card {
  background: #fafafa;
  border-radius: 16rpx;
  border: 1rpx solid #f0f0f0;
  overflow: hidden;
}

.takeout-address-card--hover {
  opacity: 0.92;
}

.takeout-address-main {
  display: flex;
  align-items: flex-start;
  padding: 22rpx 20rpx 18rpx;
}

.takeout-address-content {
  flex: 1;
  min-width: 0;
  padding-right: 8rpx;
}

.takeout-addr-title-row {
  display: flex;
  align-items: flex-start;
  flex-wrap: wrap;
  gap: 12rpx;
}

.takeout-addr-detail {
  flex: 1;
  min-width: 0;
  font-size: 28rpx;
  font-weight: 600;
  color: #222;
  line-height: 1.45;
  word-break: break-all;
}

.takeout-addr-tag {
  flex-shrink: 0;
  padding: 4rpx 12rpx;
  font-size: 22rpx;
  color: #e10606;
  background: #fff5f3;
  border: 1rpx solid #ffd4cc;
  border-radius: 6rpx;
  line-height: 1.3;
}

.takeout-addr-region {
  display: block;
  margin-top: 10rpx;
  font-size: 26rpx;
  font-weight: 400;
  color: #999;
  line-height: 1.4;
}

.takeout-addr-extra {
  display: block;
  margin-top: 8rpx;
  font-size: 25rpx;
  color: #555;
  line-height: 1.45;
}

.takeout-addr-contact-row {
  display: flex;
  align-items: center;
  flex-wrap: wrap;
  margin-top: 14rpx;
  gap: 16rpx;
}

.takeout-addr-name,
.takeout-addr-phone {
  font-size: 28rpx;
  font-weight: 400;
  color: #333;
}

.takeout-addr-name {
  font-weight: 500;
}

.takeout-addr-phone {
  color: #666;
  font-weight: 400;
}

.takeout-addr-empty-title {
  display: block;
  font-size: 28rpx;
  font-weight: 600;
  color: #222;
  line-height: 1.4;
}

.takeout-addr-empty-hint {
  display: block;
  margin-top: 10rpx;
  font-size: 26rpx;
  color: #999;
  line-height: 1.4;
}

.takeout-address-arrow {
  flex-shrink: 0;
  align-self: center;
  padding-left: 8rpx;
  display: flex;
  align-items: center;
  gap: 4rpx;
}

.takeout-modify-text {
  font-size: 23rpx;
  color: #d92314;
}

.takeout-arrow-text {
  font-size: 32rpx;
  font-weight: 300;
  color: #ccc;
  line-height: 1;
}

.takeout-address-divider {
  height: 1rpx;
  margin: 0 20rpx;
  background: #f0f0f0;
}

.takeout-delivery-status {
  padding: 14rpx 20rpx 18rpx;
  background: #f9f9f9;
}

.takeout-delivery-status--ok .takeout-status-text {
  color: #00a870;
}

.takeout-delivery-status--warning .takeout-status-text,
.takeout-delivery-status--error .takeout-status-text {
  color: #e10606;
}

.takeout-delivery-status--hint .takeout-status-text,
.takeout-delivery-status--loading .takeout-status-text {
  color: #999;
}

.takeout-status-text {
  font-size: 26rpx;
  line-height: 1.5;
  color: #666;
}

.takeout-pickup-card {
  padding: 22rpx 20rpx;
  background: #fafafa;
  border-radius: 16rpx;
  border: 1rpx solid #eee;
}

.takeout-pickup-store {
  display: block;
  font-size: 28rpx;
  font-weight: 600;
  color: #222;
  line-height: 1.4;
}

.takeout-pickup-tip {
  display: block;
  margin-top: 10rpx;
  font-size: 26rpx;
  font-weight: 400;
  color: #999;
  line-height: 1.45;
}

.submit-btn-container {
  padding: 24rpx 16rpx calc(24rpx + env(safe-area-inset-bottom));
  position: fixed;
  bottom: 0;
  left: 0;
  right: 0;
  background-color: #ffffff;
  box-shadow: 0 -2rpx 10rpx rgba(0, 0, 0, 0.05);
  z-index: 999;
}

.submit-order-btn {
  width: 100%;
  height: 90rpx;
  background: linear-gradient(to right, #ff5117, #f0331a, #e10606, #d30606);
  border-radius: 45rpx;
  color: #fff;
  font-size: 32rpx;
  font-weight: bold;
  border: none;
}

.submit-order-btn[disabled] {
  opacity: 0.7;
}

.submit-order-btn::after {
  border: none;
}
</style>
