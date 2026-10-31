<template>
  <view class="details-view od-page">
    <!-- 骑手配送 Hero（地图置顶 · 美团式） -->
    <view v-if="showRiderSection" class="od-rider-hero">
      <view class="od-rider-map-wrap">
        <map
          v-if="riderMapCenter"
          class="od-rider-map"
          :latitude="riderMapCenter.lat"
          :longitude="riderMapCenter.lng"
          :scale="riderMapScale"
          :markers="riderMapMarkers"
          :include-points="riderMapIncludePoints"
          show-location
          enable-scroll
          enable-zoom
        ></map>
        <view v-else class="od-rider-map od-rider-map--placeholder">
          <text class="od-rider-map-ph-text">地图加载中…</text>
        </view>
      </view>
      <view class="od-rider-hero-panel">
        <view class="od-rider-hero-head">
          <view class="od-rider-hero-head-main">
            <text class="od-rider-hero-title">{{ riderHero.headline }}</text>
            <text v-if="riderHero.summaryLine" class="od-rider-hero-sub">{{ riderHero.summaryLine }}</text>
          </view>
          <view
            class="od-rider-refresh-btn"
            :class="{ 'od-rider-refresh-btn--loading': riderTrackingRefreshing }"
            @tap="refreshRiderTracking"
          >
            <text>{{ riderTrackingRefreshing ? '同步中' : '刷新' }}</text>
          </view>
        </view>
        <view class="od-rider-metrics">
          <view class="od-rider-metric">
            <text class="od-rider-metric-val">{{ riderHero.distanceText || '—' }}</text>
            <text class="od-rider-metric-key">{{ riderHero.distanceLabel || '距离' }}</text>
          </view>
          <view class="od-rider-metric od-rider-metric--accent">
            <text class="od-rider-metric-val od-rider-metric-val--lg">{{ riderHero.etaMinutesText }}</text>
            <text class="od-rider-metric-key">预计送达(分钟)</text>
          </view>
        </view>
        <view v-if="riderHero.name || riderHero.phone" class="od-rider-contact">
          <view class="od-rider-contact-info">
            <text class="od-rider-contact-label">配送骑手</text>
            <text class="od-rider-contact-name">{{ riderHero.name || '骑手' }}</text>
            <text v-if="riderHero.phone" class="od-rider-contact-phone">{{ riderHero.phone }}</text>
          </view>
          <view
            v-if="riderHero.phone"
            class="od-rider-call-btn"
            @tap="callRiderPhone"
          >
            联系骑手
          </view>
        </view>
        <text v-if="riderSyncTimeText" class="od-rider-sync-hint">位置更新于 {{ riderSyncTimeText }}</text>
      </view>
    </view>

    <!-- 订单状态（有骑手地图时不重复展示外卖文案） -->
    <view v-if="!hideStatusForRiderHero" class="od-card od-card--status">
      <view class="order-remind">
        <view v-if="other_data.transac_status === 'cancelled'">
          <text class="od-status-title">订单已取消</text>
          <text class="od-status-sub">该订单已取消，无法继续操作</text>
        </view>
        <view v-else-if="other_data.dineInOrTakeOut === '外卖'">
          <template v-if="other_data.transac_status === 'success'">
            <text v-if="isTakeoutDeliveryCompleted" class="od-status-badge od-status-badge--done">配送已完成</text>
            <text class="od-status-num">{{ other_data.id || orderId }}</text>
            <text v-if="isTakeoutDeliveryCompleted" class="od-status-sub">您的外卖已送达，请查收餐品</text>
            <text v-else class="od-status-sub">商家备餐完成后将尽快为您配送，请保持手机畅通</text>
          </template>
          <template v-else>
            <text class="od-status-title">订单未支付</text>
            <text class="od-status-sub">订单未支付不会接单哦</text>
          </template>
        </view>
        <view v-else-if="other_data.dineInOrTakeOut === '外带' || other_data.dineInOrTakeOut === '打包'">
          <template v-if="other_data.transac_status === 'success'">
            <text class="od-status-num">{{ other_data.id || orderId }}</text>
            <text class="od-status-sub">稍后请凭取餐码前往取餐</text>
          </template>
          <template v-else>
            <text class="od-status-title">订单未支付</text>
            <text class="od-status-sub">订单未支付不会接单哦</text>
          </template>
        </view>
        <view v-else-if="other_data.transac_status === 'success'">
          <text class="od-status-title">订单已完成，欢迎下次光临！</text>
          <text class="od-status-sub">如有疑问请咨询前台</text>
        </view>
        <view v-else>
          <text class="od-status-title">下单成功，坐等开吃</text>
          <text class="od-status-sub">为保证产品质量，请耐心等待</text>
        </view>
      </view>
    </view>

    <!-- 预估出餐 -->
    <view
      v-if="other_data.transac_status !== 'cancelled' && other_data.transac_status !== 'success' && estimatedFinishTime"
      class="od-card od-card--estimate"
    >
      <text class="estimated-finish-title">预估出餐时间</text>
      <text class="estimated-finish-value">{{ estimatedFinishTime }}</text>
    </view>

    <!-- 服务费提示 -->
    <view class="od-card od-card--notice" v-if="orderServiceFee > 0">
      <text class="od-notice-text">本订单含新年服务费5%，已计入订单金额</text>
    </view>

    <!-- 订单信息 -->
    <view class="od-card">
      <view class="od-card-head">
        <text class="od-card-title">订单信息</text>
        <text class="od-status-pill">{{ getOrderStatusText() }}</text>
      </view>
      <view class="od-kv-list">
        <view class="od-kv-row">
          <text class="od-kv-k">门店</text>
          <text class="od-kv-v od-kv-v--strong">{{ currentStoreName }}</text>
        </view>
        <view class="od-kv-row od-kv-row--last">
          <text class="od-kv-k">用餐方式</text>
          <text class="od-kv-v">{{ other_data.dineInOrTakeOut }}</text>
        </view>
      </view>
    </view>

    <!-- 配送信息 -->
    <view
      v-if="isTakeoutOrder && (showTakeoutDeliveryFeeRow || takeoutAddressLine || takeoutReceiverLine || takeoutDispatchLabel || takeoutMerchantRemarkLine)"
      class="od-card"
    >
      <view class="od-card-head">
        <text class="od-card-title">配送信息</text>
      </view>
      <view class="od-kv-list">
        <view v-if="takeoutReceiverLine" class="od-kv-row">
          <text class="od-kv-k">联系人</text>
          <text class="od-kv-v">{{ takeoutReceiverLine }}</text>
        </view>
        <view v-if="takeoutAddressLine" class="od-kv-row od-kv-row--addr">
          <text class="od-kv-k">收货地址</text>
          <text class="od-kv-v">{{ takeoutAddressLine }}</text>
        </view>
        <view v-if="showTakeoutDeliveryFeeRow" class="od-kv-row">
          <text class="od-kv-k">配送费</text>
          <text class="od-kv-v od-kv-v--price">¥{{ takeoutDeliveryFeeFormatted }}</text>
        </view>
        <view v-if="takeoutDispatchLabel && !showRiderSection" class="od-kv-row">
          <text class="od-kv-k">配送状态</text>
          <text class="od-kv-v">{{ takeoutDispatchLabel }}</text>
        </view>
        <view
          v-if="takeoutMerchantRemarkLine"
          class="od-kv-row od-kv-row--last od-kv-row--addr"
        >
          <text class="od-kv-k">配送备注</text>
          <text class="od-kv-v">{{ takeoutMerchantRemarkLine }}</text>
        </view>
      </view>
    </view>

    <!-- 订单菜品 -->
    <view class="od-card">
      <view class="od-card-head od-card-head--line">
        <text class="od-card-title">订单菜品</text>
      </view>
      <block v-for="(orderGroup, groupIndex) in groupedGoods" :key="groupIndex">
        <view class="od-batch" v-if="groupedGoods.length > 1">
          <text class="order-group-tag">第{{ orderGroup.orderNumber }}次下单</text>
        </view>
        <block v-for="(item, index) in orderGroup.items" :key="index">
          <view
            class="foot-deta"
            :class="{
              'foot-deta-last': index === orderGroup.items.length - 1 && groupIndex === groupedGoods.length - 1,
              'foot-deta--combo': isComboHeaderLine(item),
            }"
            @tap="onComboLineTap(item)"
          >
            <view class="dish-thumb-wrap">
              <image
                :src="dishImageUrlOrDefault(item.image, 'list')"
                mode="aspectFill"
                lazy-load
              />
            </view>
            <view class="foot-name">
              <text class="dish-name">
                {{ item.name }}
                <text v-if="isComboHeaderLine(item)" class="dish-combo-tag">套餐</text>
              </text>
              <text class="dish-meta">{{ getOrderLineMeta(item) }}</text>
            </view>
            <view class="dish-price-col">
              <text class="foot-total">¥{{ Number(item.total_price || 0).toFixed(1) }}</text>
              <text class="dish-qty">×{{ item.quantity }}</text>
            </view>
          </view>
        </block>
      </block>
    </view>

    <!-- 费用明细 -->
    <view class="od-card">
      <view class="od-card-head">
        <text class="od-card-title">费用明细</text>
      </view>
      <view class="total-list">
        <view class="total-item" v-if="showFeeDetailGoodsRow">
          <text class="total-left">商品总价</text>
          <text class="total-right od-price">¥{{ orderGoodsTotalFormatted }}</text>
        </view>
        <view class="total-item" v-if="showFeeDetailPackagingRow">
          <text class="total-left">打包费</text>
          <text class="total-right od-price">¥{{ feeDetailPackagingFeeFormatted }}</text>
        </view>
        <view class="total-item" v-if="showTakeoutDeliveryFeeRow">
          <text class="total-left">配送费</text>
          <text class="total-right od-price">¥{{ takeoutDeliveryFeeFormatted }}</text>
        </view>
        <view class="total-item" v-if="orderServiceFee > 0">
          <text class="total-left">服务费</text>
          <text class="total-right od-price">¥{{ orderServiceFeeAmount }}</text>
        </view>
        <view
          class="total-item total-coupon-row order-coupon-section"
          @click="selectCoupon"
          v-if="canUseCouponOnOrder"
        >
          <text class="total-left">优惠券</text>
          <view class="coupon-arrow">
            <text class="selected-coupon" v-if="selectedCoupon">
              {{ selectedCoupon.coupon_name }}
              <template v-if="selectedCoupon.coupon_type === 'discount'">（{{ (selectedCoupon.discount_value / 10).toFixed(1) }}折）</template>
              <template v-else-if="selectedCoupon.coupon_type === 'full_reduction'">（满{{ selectedCoupon.min_amount }}减{{ selectedCoupon.discount_value }}）</template>
              <template v-else-if="selectedCoupon.coupon_type === 'direct_reduction'">（无门槛减{{ selectedCoupon.discount_value }}）</template>
            </text>
            <text class="selected-coupon" v-else>
              <template v-if="availableCouponCount > 0">未选择<text class="coupon-count">（{{ availableCouponCount }}张）</text></template>
              <template v-else-if="availableCouponCount === 0">没有可用券</template>
              <template v-else>未选择</template>
            </text>
            <text class="od-chevron">›</text>
          </view>
        </view>
        <view class="fee-detail-hint" v-if="canUseCouponOnOrder && showNightNinefoldFeeRow && !selectedCoupon">
          <text class="fee-detail-hint-text">使用优惠券后不可叠加夜间九折</text>
        </view>
        <view class="total-item" v-if="showExistingDiscountRow">
          <text class="total-left">订单优惠</text>
          <text class="total-right price-discount-value">-¥{{ existingDiscountAmountFormatted }}</text>
        </view>
        <view class="fee-detail-hint" v-if="hasOrderDiscountAmount && other_data.transac_status === 'unsettled'">
          <text class="fee-detail-hint-text">订单已含优惠，不可再使用优惠券及夜间九折</text>
        </view>
        <view class="total-item" v-if="showCouponDiscountRow">
          <text class="total-left">优惠券抵扣</text>
          <text class="total-right price-discount-value">-¥{{ displayCouponRowAmountFormatted }}</text>
        </view>
        <view class="total-item" v-if="showNightNinefoldFeeRow">
          <text class="total-left">{{ nightNinefoldRowLabel }}</text>
          <text class="total-right price-discount-value">-¥{{ feeDetailNightNinefoldDiscountFormatted }}</text>
        </view>
        <view class="night-ninefold-tip" v-if="showNightNinefoldFeeRow && nightNinefoldTipText">
          <text class="night-ninefold-tip-text">{{ nightNinefoldTipText }}</text>
        </view>
        
        <view class="total-item" v-if="orderRefundAmountYuan > 0">
          <text class="total-left">已退款</text>
          <text class="total-right price-discount-value">-¥{{ orderRefundAmountDisplay }}</text>
        </view>
        <view class="total-item total-final-row">
          <text class="total-left">合计</text>
          <text class="total-right total-amount">¥{{ displaySettAmount }}</text>
        </view>
      </view>

      <view class="payment-method-block" v-if="other_data.transac_status === 'unsettled'">
        <view class="payment-method-title">支付方式</view>
        <view v-if="!showOnlinePaymentMethods" class="payment-offline-hint">
          <text>{{ paymentDisabledHint }}</text>
          <view
            v-if="showOfflineCollectEntry"
            class="payment-offline-btn"
            @click="openOfflineCollectQr"
          >查看线下收款码</view>
        </view>
        <template v-else>
        <view class="payment-method-row">
          <view
            v-if="showWechatPayChip"
            class="payment-chip"
            :class="{
              'payment-chip-active': paymentMethod === 'wxpay',
              'payment-chip-disabled': !canUseWechatPay,
            }"
            @click="setPaymentMethod('wxpay')"
          >
            微信支付
          </view>
          <view
            v-if="showBalancePayChip"
            class="payment-chip"
            :class="{
              'payment-chip-active': paymentMethod === 'balance',
              'payment-chip-disabled': !canPayByBalance,
            }"
            @click="pickBalancePayment"
          >
            余额支付
            <text v-if="userBalance != null && Number.isFinite(Number(userBalance))" class="payment-balance-text">
              （¥{{ userBalanceDisplayFormatted }}）
            </text>
          </view>
        </view>
        <view class="payment-balance-tip" v-if="showWechatPayChip && !canUseWechatPay">
          <text>{{ wechatPayDisabledTip }}</text>
        </view>
        <view class="payment-balance-tip" v-if="orderHasCombo">
          <text>{{ comboPaymentRestrictMsg }}</text>
        </view>
        <view class="payment-balance-tip" v-else-if="hasOrderDiscountAmount && other_data.transac_status === 'unsettled'">
          <text>订单已含优惠，不可再使用优惠券及夜间九折。</text>
        </view>
        <view class="payment-balance-tip" v-else-if="orderUsesCoupon">
          <text>已使用优惠券，本单不可用余额支付及夜间九折优惠，请使用微信支付。</text>
        </view>
        <view class="payment-balance-tip" v-else-if="nightNinefoldShowPreview">
          <text>当前可享夜间九折优惠，不可使用余额支付，请使用微信支付。</text>
        </view>
        <view
          class="payment-balance-tip"
          v-else-if="userBalance != null && Number.isFinite(Number(userBalance)) && !canPayByBalance"
        >
          <text>当前余额不足以支付本单，请使用微信支付或</text>
          <text class="payment-recharge-link" @click.stop="goToMemberRecharge">去充值</text>
        </view>
        </template>
      </view>
    </view>

    <!-- 订单详情 -->
    <view class="od-card od-card--meta">
      <view class="od-card-head od-card-head--line">
        <text class="od-card-title">订单详情</text>
      </view>
      <view class="od-kv-list">
        <view v-if="other_data.remark && String(other_data.remark).trim()" class="od-kv-row od-kv-row--addr">
          <text class="od-kv-k">备注</text>
          <text class="od-kv-v">{{ other_data.remark }}</text>
        </view>
        <view
          v-if="other_data.table_number != null && other_data.table_number !== '' && other_data.dineInOrTakeOut !== '外卖'"
          class="od-kv-row"
        >
          <text class="od-kv-k">桌台</text>
          <text class="od-kv-v">{{ other_data.table_number }}</text>
        </view>
        <view class="od-kv-row">
          <text class="od-kv-k">结账状态</text>
          <text class="od-kv-v">{{ transacStatusText }}</text>
        </view>
        <view class="od-kv-row">
          <text class="od-kv-k">下单时间</text>
          <text class="od-kv-v">{{ formatDate(other_data.order_time) }}</text>
        </view>
        <view class="od-kv-row">
          <text class="od-kv-k">订单编号</text>
          <text class="od-kv-v od-kv-v--mono">{{ other_data.order_no }}</text>
        </view>
        <view
          v-if="other_data.transac_status === 'success' && other_data.payment_method"
          class="od-kv-row od-kv-row--last"
        >
          <text class="od-kv-k">支付方式</text>
          <text class="od-kv-v">{{ other_data.payment_method }}</text>
        </view>
      </view>
    </view>

    <view class="od-bottom-spacer"></view>

  <!-- 底部操作栏 -->
    <view class="foot-section" :style="{ paddingBottom: Modelmes ? '35rpx' : '' }">
      <view class="add-a-dish" v-if="other_data.transac_status !== 'cancelled'">
        <view
          v-if="other_data.transac_status === 'unsettled' && other_data.dineInOrTakeOut === '堂食'"
          class="od-btn od-btn--primary"
          @click="add_Dish"
        >
          加菜
        </view>
        <view v-if="showCancelOrderBtn" class="od-btn od-btn--ghost" @click="onCancelOrder">取消订单</view>
        <view v-if="showOrderCommentBtn" class="od-btn od-btn--outline" @click="onOpenOrderComment">去评价</view>
        <view
          v-if="showUnsettledFooterBtn"
          class="od-btn od-btn--primary"
          :class="{
            disabled: footerCheckoutBtnDisabled,
            'od-btn--long-label': checkoutButtonLabel.length > 4,
          }"
          @click="onFooterCheckoutClick"
        >
          {{ checkoutButtonLabel }}
        </view>
      </view>
    </view>
    <view class="toast" v-if="showToast">
      <view class="toast-content">{{ toastMessage }}</view>
    </view>

    <view
      class="offline-collect-mask"
      v-if="offlineCollectVisible"
      @tap="closeOfflineCollect"
    >
      <view class="offline-collect-sheet" @tap.stop="">
        <text class="offline-collect-title">线下收款</text>
        <text class="offline-collect-sub">请使用微信或支付宝「扫一扫」扫描下方二维码</text>
        <image
          v-if="offlineCollectQrUrl"
          class="offline-collect-qr"
          :src="offlineCollectQrUrl"
          mode="aspectFit"
          show-menu-by-longpress
        />
        <text v-else-if="offlineCollectLoading" class="offline-collect-loading">生成收款码中…</text>
        <text v-else class="offline-collect-err">{{ offlineCollectError || '暂无法展示收款码' }}</text>
        <view class="offline-collect-close" @tap="closeOfflineCollect">关闭</view>
      </view>
    </view>

    <view
      class="combo-detail-mask"
      v-if="comboDetailVisible"
      @tap="closeComboDetail"
    >
      <view class="combo-detail-sheet" @tap.stop="">
        <view class="combo-detail-head">
          <text class="combo-detail-title">{{ comboDetailTitle }}</text>
          <text class="combo-detail-close" @tap="closeComboDetail">×</text>
        </view>
        <text v-if="comboDetailSummary" class="combo-detail-summary">{{ comboDetailSummary }}</text>
        <scroll-view scroll-y class="combo-detail-scroll" :show-scrollbar="false">
          <view
            v-for="(row, ci) in comboDetailItems"
            :key="ci"
            class="combo-detail-row"
          >
            <text class="combo-detail-name">{{ row.name }}</text>
            <text class="combo-detail-qty">×{{ row.quantity }}{{ row.unit || '份' }}</text>
          </view>
          <view v-if="!comboDetailItems.length" class="combo-detail-empty">暂无子菜明细</view>
        </scroll-view>
      </view>
    </view>
      <global-activity-popup />
  </view>
</template>

<script>
    import {getBaseUrl, requestUtil} from "../../utils/requestUtil.js"
    import { getCurrentShopSnapshot, getCurrentShopId } from "../../utils/shopContext.js"
    import {
      countCouponsPassingLocalOrderRules,
      normalizeCouponListPayload,
      buildCouponOrderSelectionPayload,
      couponPassesLocalOrderRules,
      calculateCouponDiscount,
      orderAllowsCoupon,
    } from "../../utils/couponRules.js"
    import {
      cartHasComboLines,
      COMBO_PAYMENT_RESTRICT_MSG,
      isComboHeaderOrderLine,
      buildOrderComboDetailView,
    } from "../../utils/comboMeal.js"
    import { saveDinersCount } from "../../utils/dinersCache.js"
    import { needsPackagingFee, calcPackagingFee } from "../../utils/packagingFee.js"
    import { formatBalanceForDisplay } from "../../utils/formatBalance.js"
    import { staticUrl } from "../../utils/staticAssetUrl.js"
    import { dishImageUrlOrDefault } from "../../utils/imageUrl.js"
    import {
      parseReviewFromBusinessResponse,
      parseWxzfFromBusinessResponse,
    } from "../../utils/reviewMode.js"
    import {
      canOrderBeCommented,
      openOrderComment,
    } from "../../utils/wxTransactionComment.js"
    import {
      resolveNightNinefoldForOrder,
      resolveOrderFeeDiscountDisplay,
      orderHasExistingDiscountAmount,
      buildNightNinefoldRowLabel,
      buildNightNinefoldExplainText,
      fetchWechatPrepayNinefoldConfig,
      isNightNinefoldEligibleDiningType,
    } from "../../utils/wechatPrepayNinefold.js"
    import {
      buildRiderDeliveryHero,
      buildRiderMapState,
      formatRiderSyncTime,
      hasRiderUiContent,
      RIDER_TRACKING_POLL_MS,
      shouldPollTakeoutRiderTracking,
      parseTakeoutTrackingResponse,
      resolveTakeoutDispatchStatus,
      isTakeoutDeliveryCompleted,
    } from "../../utils/takeoutRiderTracking.js"
    import { isPageVmStillActive } from "../../utils/pageLifecycle.js"
    import Order from '../../pages/skeleton-view/order.vue'
    import paymentCapModule from "../../utils/paymentCapabilities.js"

    const paymentCap = paymentCapModule && paymentCapModule.default
      ? paymentCapModule.default
      : paymentCapModule;
    const fetchPaymentCapabilities = paymentCap.fetchPaymentCapabilities;
    const fetchOfflineCollectTempQrcode = paymentCap.fetchOfflineCollectTempQrcode;
    const isOnlinePayEnabled = paymentCap.isOnlinePayEnabled;
    const isWechatPayAvailable = paymentCap.isWechatPayAvailable;
    const isBalanceChannelEnabled = paymentCap.isBalanceChannelEnabled;
    const isOfflineCollectAvailable = paymentCap.isOfflineCollectAvailable;
    const resolvePaymentApiErrorMessage = paymentCap.resolvePaymentApiErrorMessage;
    const PAYMENT_ONLINE_DISABLED_CODE = paymentCap.PAYMENT_ONLINE_DISABLED_CODE;
    const PAYMENT_CHANNEL_DISABLED_CODE = paymentCap.PAYMENT_CHANNEL_DISABLED_CODE;
    const PAYMENT_WECHAT_MERCHANT_MISSING_CODE = paymentCap.PAYMENT_WECHAT_MERCHANT_MISSING_CODE;
    const DEFAULT_PAYMENT_DISABLED_MESSAGE = paymentCap.DEFAULT_PAYMENT_DISABLED_MESSAGE || "请联系服务员结账";

    function resolveWechatPayDisabledMessage(caps) {
      if (typeof paymentCap.resolveWechatPayDisabledMessage === "function") {
        return paymentCap.resolveWechatPayDisabledMessage(caps);
      }
      if (!caps) return DEFAULT_PAYMENT_DISABLED_MESSAGE;
      const wx = caps.channels && caps.channels.wechat;
      if (wx && wx.disabledMessage) return wx.disabledMessage;
      if (!caps.onlinePayEnabled && caps.disabledMessage) return caps.disabledMessage;
      if (caps.wechatPayEnableHint) return caps.wechatPayEnableHint;
      if (caps.disabledMessage) return caps.disabledMessage;
      return DEFAULT_PAYMENT_DISABLED_MESSAGE;
    }

    const app = getApp()
    const {Modelmes} = app.globalData

    // 浠锋牸琛ラ浂
    const Price = require('e-commerce_price')
    export default{
        components:{Order},
        data() {
            return {
                baseUrl:'',
                exist:true,
                Modelmes,
				OrderStatus: false,
                Price,
                overall:0,
                other_data:{},
                comp_data:[],//瀹屾暣鏁版嵁
                goods_data:[],//鍓嶄笁椤规暟鎹?
                isLoading: false,
                refreshTimer: null,
                orderId: '',
				selectedSpicy:'',
				table_number:'',
				order_no:'',
                availableCouponCount: null,
                selectedCoupon: null,
				showToast: false,
				toastMessage: '',
				isProcessingPayment: false, // 是否正在处理支付
				estimatedFinishTime: '',
				currentStoreName: '老肥油边王',
				shopNameById: {},
                /** 结账支付方式：wxpay 微信支付；balance 余额（POST /order/payByBalance） */
                paymentMethod: 'wxpay',
                /** 账户余额（元），null 表示尚未拉取到 */
                userBalance: null,
                /** GET /order/getOrder 外卖时根级 TakeoutDelivery，与 openapi 一致；非外卖为 null */
                takeoutDelivery: null,
                /** GET /order/takeout/order/tracking → ZsqRiderTrackingResponse */
                riderTracking: null,
                riderTrackingTimer: null,
                riderTrackingRefreshing: false,
                riderTrackingUpdatedAt: 0,
                riderMapScale: 14,
                comboDetailVisible: false,
                comboDetailTitle: "",
                comboDetailSummary: "",
                comboDetailItems: [],
                /** GET /config/wechat-prepay-ninefold 规则（与 getPrepayId 九折一致） */
                ninefoldConfig: null,
                /** GET /config/payment-capabilities */
                paymentCapabilities: null,
                paymentCapabilitiesLoaded: false,
                offlineCollectVisible: false,
                offlineCollectQrUrl: "",
                offlineCollectLoading: false,
                offlineCollectError: "",
                /** POST /order/Business → Wxzf 为真时须联系服务员结账 */
                businessWxzf: false,
                businessFlagsLoaded: false,
            }
        },
        computed: {
            /** 外卖配送扩展对象（优先于 Order 扁平字段） */
            takeoutDel() {
                const td = this.takeoutDelivery;
                return td && typeof td === 'object' ? td : {};
            },
            transacStatusText() {
                const t = (this.other_data || {}).transac_status;
                if (t === 'success') {
                    return this.orderRefundAmountYuan > 0 ? '已结账（含退款）' : '已结账';
                }
                if (t === 'unsettled') return '未结账';
                if (t === 'cancelled') return '已取消';
                return '-';
            },
            // 打包且未支付时显示取消订单按钮（契约：订单详情支持取消）
            showCancelOrderBtn() {
                const d = this.other_data || {};
                return (d.dineInOrTakeOut === '打包' || d.dineInOrTakeOut === '外卖') && d.transac_status === 'unsettled';
            },
            showOrderCommentBtn() {
                return canOrderBeCommented(this.other_data || {});
            },

            /** 外卖单（依据订单 dineInOrTakeOut） */
            isTakeoutOrder() {
                return (this.other_data || {}).dineInOrTakeOut === '外卖';
            },
            /** 配送费（元）：优先 TakeoutDelivery.delivery_fee，其次 Order.delivery_fee（openapi v1.2.33） */
            takeoutDeliveryFeeYuan() {
                if (!this.isTakeoutOrder) return null;
                const del = this.takeoutDel;
                const d = this.other_data || {};
                const candidates = [del.delivery_fee, d.delivery_fee, d.deliveryFee];
                for (let i = 0; i < candidates.length; i++) {
                    const v = candidates[i];
                    if (v == null || v === '') continue;
                    const n = Number(v);
                    if (Number.isFinite(n) && n >= 0) return Math.round(n * 100) / 100;
                }
                return null;
            },
            takeoutDeliveryFeeFormatted() {
                const y = this.takeoutDeliveryFeeYuan;
                if (y == null) return '';
                return y.toFixed(2);
            },
            showTakeoutDeliveryFeeRow() {
                return this.isTakeoutOrder && this.takeoutDeliveryFeeYuan != null;
            },
            /** 完整收货地址：优先 TakeoutDelivery.address_full（getOrder 契约），再兼容 Order 扁平字段 */
            takeoutAddressLine() {
                if (!this.isTakeoutOrder) return '';
                const del = this.takeoutDel;
                const d = this.other_data || {};
                if (del.address_full != null && String(del.address_full).trim()) {
                    return String(del.address_full).trim();
                }
                const direct =
                    d.address_full ||
                    d.addressFull ||
                    d.takeout_address_full ||
                    d.takeoutAddressFull ||
                    d.delivery_address ||
                    d.deliveryAddress;
                if (direct != null && String(direct).trim()) return String(direct).trim();
                const p = [d.receiver_province, d.receiver_city, d.receiver_district, d.province, d.city, d.district]
                    .filter((x) => x != null && String(x).trim() !== '')
                    .join('');
                const det = d.receiver_detail || d.detail_address || d.receiver_address || d.receiverAddress;
                const tail = det != null ? String(det).trim() : '';
                const combined = (p + tail).trim();
                return combined || '';
            },
            /** 收货人 + 电话：优先 TakeoutDelivery.receiver_* */
            takeoutReceiverLine() {
                if (!this.isTakeoutOrder) return '';
                const del = this.takeoutDel;
                const d = this.other_data || {};
                const name = (del.receiver_name || d.receiver_name || d.receiverName || d.contact_name || d.contactName || '').trim();
                const phone = (del.receiver_phone || d.receiver_phone || d.receiverPhone || d.contact_phone || d.contactPhone || '').trim();
                const parts = [name, phone].filter(Boolean);
                return parts.join(' ');
            },
            /** 配送履约：Order.takeout_dispatch_status 与 TakeoutDelivery.dispatch_status 一致，优先 Order */
            takeoutDispatchLabel() {
                if (!this.isTakeoutOrder) return '';
                const del = this.takeoutDel;
                const d = this.other_data || {};
                const raw =
                    d.takeout_dispatch_status ||
                    d.takeoutDispatchStatus ||
                    del.dispatch_status ||
                    del.dispatchStatus;
                if (raw == null || String(raw).trim() === '') return '';
                const s = String(raw).trim().toLowerCase();
                const map = {
                    submitted: '已提交',
                    paid: '已支付',
                    accepted: '商家已接单',
                    delivering: '配送中',
                    completed: '已完成',
                    cancelled: '已取消',
                    dispatch_failed: '发配送失败',
                };
                return map[s] || raw;
            },
            riderHero() {
                return buildRiderDeliveryHero(this.riderTracking, this.takeoutDel);
            },
            riderMapState() {
                return buildRiderMapState(this.riderTracking, this.takeoutDel);
            },
            riderMapCenter() {
                const c = this.riderMapState && this.riderMapState.center;
                return c && c.lat != null && c.lng != null ? c : null;
            },
            riderMapMarkers() {
                return (this.riderMapState && this.riderMapState.markers) || [];
            },
            riderMapIncludePoints() {
                return (this.riderMapState && this.riderMapState.includePoints) || [];
            },
            riderSyncTimeText() {
                return formatRiderSyncTime(this.riderTrackingUpdatedAt);
            },
            hideStatusForRiderHero() {
                return this.showRiderSection;
            },
            isTakeoutDeliveryCompleted() {
                if (!this.isTakeoutOrder) return false;
                return isTakeoutDeliveryCompleted(
                    this.riderTracking,
                    this.takeoutDel,
                    this.other_data
                );
            },
            showRiderSection() {
                if (!this.isTakeoutOrder) return false;
                const o = this.other_data || {};
                if (String(o.transac_status || '').trim().toLowerCase() !== 'success') return false;
                if (this.isTakeoutDeliveryCompleted) return false;
                if (hasRiderUiContent(this.riderHero, this.riderMapState)) return true;
                return shouldPollTakeoutRiderTracking(this.takeoutDel, o, this.riderTracking);
            },
            /** 骑手/商家配送备注（TakeoutDelivery.merchant_remark） */
            takeoutMerchantRemarkLine() {
                if (!this.isTakeoutOrder) return '';
                const del = this.takeoutDel;
                const m = del.merchant_remark != null ? del.merchant_remark : del.merchantRemark;
                if (m == null || String(m).trim() === '') return '';
                return String(m).trim();
            },

            hasDiscount() {
                return this.hasOrderDiscountAmount || this.couponDiscount > 0;
            },

            hasOrderDiscountAmount() {
                return orderHasExistingDiscountAmount(this.other_data);
            },

            orderGoodsTotal() {
                const lines = this.buildCouponOrderLines();
                if (lines.length) {
                    const sum = lines.reduce(
                        (total, item) => total + Number(item.total_price || 0),
                        0
                    );
                    if (sum > 0) {
                        return Math.round(sum * 100) / 100;
                    }
                }
                const sett = Number((this.other_data || {}).sett_amount || 0);
                return Math.max(0, Math.round(sett * 100) / 100);
            },
            orderGoodsTotalFormatted() {
                return Number(this.orderGoodsTotal || 0).toFixed(2);
            },
            showFeeDetailGoodsRow() {
                return Number(this.orderGoodsTotal || 0) > 0;
            },
            feeDetailPackagingFeeYuan() {
                const d = this.other_data || {};
                if (!needsPackagingFee(d.dineInOrTakeOut)) return 0;
                return Math.round(Number(this.orderPackagingFeeEstimate || 0) * 100) / 100;
            },
            showFeeDetailPackagingRow() {
                return this.feeDetailPackagingFeeYuan > 0;
            },
            feeDetailPackagingFeeFormatted() {
                return this.feeDetailPackagingFeeYuan.toFixed(2);
            },
            /** 未结账、无已锁定优惠、非套餐单时可选券（同桌扫码均可使用自己的券） */
            canUseCouponOnOrder() {
                const d = this.other_data || {};
                return (
                    d.transac_status === "unsettled" &&
                    !this.hasOrderDiscountAmount &&
                    !this.orderHasCombo
                );
            },
            // 订单新年服务费（后端返回 service_fee 鏃朵娇鐢紝涓?confirm-order 鎻愪氦涓€鑷达級
            orderServiceFee() {
                return Number((this.other_data || {}).service_fee ?? 0);
            },
            orderServiceFeeAmount() {
                const fee = this.orderServiceFee;
                return fee.toFixed(2);
            },

            /** 累计成功退款（元），对应 t_order.refund_amount / Order.refund_amount */
            orderRefundAmountYuan() {
                const d = this.other_data || {};
                const v = d.refund_amount != null ? d.refund_amount : d.refundAmount;
                const n = Number(v);
                if (!Number.isFinite(n) || n <= 0) return 0;
                return Math.round(n * 100) / 100;
            },
            orderRefundAmountDisplay() {
                return this.orderRefundAmountYuan.toFixed(2);
            },

            /** 订单原价（商品+打包+服务费），与 openapi 订单原价口径一致 */
            orderSubtotalYuan() {
                const d = this.other_data || {};
                const sett = Number(d.sett_amount || 0);
                const sf = this.orderServiceFee;
                return Math.round((sett + sf) * 100) / 100;
            },
            /** 订单是否使用优惠券：用券则不可用夜间九折与余额支付（与 openapi 结算规则一致） */
            orderUsesCoupon() {
                if (this.orderHasBoundCoupon) return true;
                if (this.selectedCoupon && this.couponDiscount > 0) {
                    return true;
                }
                return false;
            },
            /** 未用券、就餐方式匹配配置且未结账时，可叠夜间九折展示 */
            ninefoldStackAllowed() {
                const d = this.other_data || {};
                if (d.transac_status !== "unsettled") return false;
                if (this.hasOrderDiscountAmount) return false;
                if (this.orderUsesCoupon) return false;
                return isNightNinefoldEligibleDiningType(d.dineInOrTakeOut, this.ninefoldConfig);
            },
            nightNinefoldResolved() {
                return resolveNightNinefoldForOrder({
                    order: this.other_data,
                    config: this.ninefoldConfig,
                    orderSubtotalYuan: this.orderSubtotalYuan,
                    orderHasBoundCoupon: this.orderHasBoundCoupon,
                    orderUsesCoupon: this.orderUsesCoupon,
                });
            },
            nightNinefoldShowPreview() {
                return this.nightNinefoldResolved.mode === "preview";
            },
            nightNinefoldDiscountYuanPreview() {
                if (!this.nightNinefoldShowPreview) return 0;
                return this.nightNinefoldResolved.amount;
            },
            /** 费用明细优惠行（券/九折互斥，九折仅微信支付预览） */
            feeDiscountDisplay() {
                const d = this.other_data || {};
                return resolveOrderFeeDiscountDisplay({
                    transacStatus: d.transac_status,
                    paymentMethod: this.paymentMethod,
                    orderUsesCoupon: this.orderUsesCoupon,
                    orderHasBoundCoupon: this.orderHasBoundCoupon,
                    orderHasExistingDiscount: this.hasOrderDiscountAmount,
                    discountAmountFromOrder: d.discount_amount,
                    selectedCouponDiscountYuan: this.couponDiscount,
                    nightNinefoldResolved: this.nightNinefoldResolved,
                });
            },
            showExistingDiscountRow() {
                return this.feeDiscountDisplay.showExistingDiscountRow;
            },
            existingDiscountAmountFormatted() {
                return Number(this.feeDiscountDisplay.existingDiscountAmount || 0).toFixed(2);
            },
            showCouponDiscountRow() {
                return this.feeDiscountDisplay.showCouponRow;
            },
            displayCouponRowAmount() {
                return this.feeDiscountDisplay.couponAmount;
            },
            displayCouponRowAmountFormatted() {
                return Number(this.displayCouponRowAmount || 0).toFixed(2);
            },
            showNightNinefoldFeeRow() {
                return this.feeDiscountDisplay.showNinefoldRow;
            },
            feeDetailNightNinefoldDiscountYuan() {
                return this.feeDiscountDisplay.ninefoldAmount;
            },
            feeDetailNightNinefoldDiscountFormatted() {
                return this.feeDetailNightNinefoldDiscountYuan.toFixed(2);
            },
            /** 应付（扣券/九折后，未扣退款） */
            feeDetailPayableBeforeRefundYuan() {
                const base = this.orderSubtotalYuan;
                const fd = this.feeDiscountDisplay;
                const couponOff = Number(fd.couponAmount || 0);
                const ninefoldOff = Number(fd.ninefoldAmount || 0);
                const existingOff = Number(fd.existingDiscountAmount || 0);
                return Math.max(
                    Math.round((base - couponOff - ninefoldOff - existingOff) * 100) / 100,
                    0
                );
            },
            orderHasBoundCoupon() {
                const d = this.other_data || {};
                const keys = ["user_coupon_id", "userCouponId", "coupon_id", "couponId"];
                for (let i = 0; i < keys.length; i++) {
                    const v = d[keys[i]];
                    if (v == null || v === "") continue;
                    const n = Number(v);
                    if (Number.isFinite(n) && n > 0) return true;
                    if (typeof v === "string" && String(v).trim() !== "") return true;
                }
                return false;
            },
            /** 已结账或未结账已锁定：归因夜间九折金额 */
            nightNinefoldAttributedDiscountYuan() {
                const r = this.nightNinefoldResolved;
                return r.mode === "applied" ? r.amount : 0;
            },
            nightNinefoldRowAmount() {
                return this.feeDetailNightNinefoldDiscountYuan;
            },
            nightNinefoldRowAmountFixed() {
                return this.feeDetailNightNinefoldDiscountFormatted;
            },
            nightNinefoldRowLabel() {
                const r = this.nightNinefoldResolved || {};
                const cfg = this.ninefoldConfig || {};
                return buildNightNinefoldRowLabel(r.zheLabel, cfg.payRate);
            },
            nightNinefoldTipVisible() {
                const r = this.nightNinefoldResolved;
                return r.mode === "preview" || r.mode === "applied";
            },
            nightNinefoldTipText() {
                if (!this.showNightNinefoldFeeRow) return "";
                const r = this.nightNinefoldResolved;
                const cfg = this.ninefoldConfig || {};
                return buildNightNinefoldExplainText({
                    mode: r.mode,
                    zheLabel: r.zheLabel,
                    timeRange: r.timeRange,
                    minBaseYuan: cfg.minBaseYuan,
                    payRate: cfg.payRate,
                    eligibleDiningTypes: cfg.eligibleDiningTypes,
                    dineInOnly: cfg.dineInOnly,
                });
            },
            orderGoodsAndPackAmount() {
                const d = this.other_data || {};
                const sett = Number(d.sett_amount || 0);
                return Math.max(sett, 0).toFixed(2);
            },
       
            orderPackagingFeeEstimate() {
                const goods = Number(this.orderGoodsTotal || 0);
                const d = this.other_data || {};
                if (!needsPackagingFee(d.dineInOrTakeOut) || goods <= 0) return 0;
                return calcPackagingFee(goods).fee;
            },
            couponOrderBaseTotal() {
                const goods = Math.round(Number(this.orderGoodsTotal || 0) * 100) / 100;
                const pack = Math.round(Number(this.orderPackagingFeeEstimate || 0) * 100) / 100;
                const fromClient = Math.round((goods + pack) * 100) / 100;
                const sett = Math.round(Number((this.other_data || {}).sett_amount || 0) * 100) / 100;
                return Math.max(fromClient, sett);
            },
            couponDiscount() {
                if (this.orderHasCombo) return 0;
                return calculateCouponDiscount(this.selectedCoupon, this.getCouponOrderCtx());
            },
            finalPayAmount() {
                return this.displaySettAmount;
            },
            displayDiscountAmount() {
                const d = this.other_data || {};
                if (this.hasOrderDiscountAmount) {
                    return Number(d.discount_amount || 0);
                }
                if (d.transac_status === 'unsettled' && this.selectedCoupon && this.couponDiscount > 0) {
                    return this.couponDiscount;
                }
                return Number(d.discount_amount || 0);
            },

            displaySettAmount() {
                const d = this.other_data || {};
                let pay = this.feeDetailPayableBeforeRefundYuan;
                if (d.transac_status === "success") {
                    pay = Math.round((pay - this.orderRefundAmountYuan) * 100) / 100;
                }
                return Math.max(pay, 0).toFixed(2);
            },
            // 按订单分组的菜品数据
            groupedGoods() {
                if (!this.goods_data || !this.goods_data.length || !this.other_data) {
                    return [];
                }
                
                const currentOrderNumber = this.other_data.morder_num || 1;
                
                const groups = {};
                this.goods_data.forEach(item => {
                    const lt = String(item.line_type || item.lineType || "").toLowerCase();
                    if (lt === "combo_component") return;
                    const orderNum = item.morder_num || currentOrderNumber;
                    if (!groups[orderNum]) {
                        groups[orderNum] = {
                            orderNumber: orderNum,
                            items: []
                        };
                    }
                    groups[orderNum].items.push(item);
                });
                
                return Object.values(groups).sort((a, b) => b.orderNumber - a.orderNumber);
            },
            
            
            
            /** 应付金额（元，数字） */
            payAmountYuan() {
                const n = Number(this.displaySettAmount);
                return Number.isFinite(n) ? Math.round(n * 100) / 100 : 0;
            },
            orderHasCombo() {
                const lines = this.buildCouponOrderLines();
                return cartHasComboLines(lines) || cartHasComboLines(this.goods_data);
            },
            comboPaymentRestrictMsg() {
                return COMBO_PAYMENT_RESTRICT_MSG;
            },
            showOnlinePaymentMethods() {
                if (this.isWaiterCheckoutOnly) return false;
                const c = this.paymentCapabilities;
                if (c == null) return true;
                return isOnlinePayEnabled(c);
            },
            /** 接口顶层 disabledMessage（关闭线上支付等场景） */
            paymentDisabledHint() {
                if (this.isWaiterCheckoutOnly) return '联系服务员结账';
                const c = this.paymentCapabilities;
                if (c && c.disabledMessage) return c.disabledMessage;
                return resolveWechatPayDisabledMessage(c);
            },
            /** 当前是否可走微信支付结账 */
            canCheckoutWithWechat() {
                return (
                    this.paymentCapabilitiesLoaded &&
                    this.canUseWechatPay &&
                    this.paymentMethod === 'wxpay' &&
                    !this.isCheckoutDisabled
                );
            },
            /** 当前是否可走余额支付结账（渠道开启 + 余额足额 + 业务互斥通过） */
            canCheckoutWithBalance() {
                return (
                    this.paymentCapabilitiesLoaded &&
                    this.balanceChannelEnabled &&
                    this.paymentMethod === 'balance' &&
                    this.canPayByBalance &&
                    !this.isCheckoutDisabled
                );
            },
            /** Wxzf=真 或 merchantId=2 时须联系服务员线下结账 */
            isWaiterCheckoutOnly() {
                if (this.businessWxzf === true) return true;
                const mid = (this.other_data || {}).merchantId;
                return String(mid) === '2';
            },
            /** 底部结账按钮是否可点击 */
            isCheckoutFooterEnabled() {
                if (this.isWaiterCheckoutOnly) return false;
                if (this.isProcessingPayment) return false;
                if (!this.paymentCapabilitiesLoaded) return false;
                return this.canCheckoutWithWechat || this.canCheckoutWithBalance;
            },
            checkoutButtonLabel() {
                if (this.isWaiterCheckoutOnly) return '联系服务员结账';
                if ((this.other_data || {}).transac_status !== 'unsettled') return '结账';
                if (this.isCheckoutFooterEnabled) return '结账';
                return this.paymentDisabledHint;
            },
            showUnsettledFooterBtn() {
                return (this.other_data || {}).transac_status === 'unsettled';
            },
            footerCheckoutBtnDisabled() {
                return !this.isCheckoutFooterEnabled;
            },
            /** 可走线上结账（微信或余额，与底部按钮可点一致） */
            canProceedOnlineCheckout() {
                return this.isCheckoutFooterEnabled;
            },
            showOfflineCollectEntry() {
                if (this.isWaiterCheckoutOnly) return false;
                return isOfflineCollectAvailable(this.paymentCapabilities);
            },
            canUseWechatPay() {
                if (this.isWaiterCheckoutOnly) return false;
                if (!this.paymentCapabilitiesLoaded) return true;
                const c = this.paymentCapabilities;
                if (c == null) return false;
                return isWechatPayAvailable(c);
            },
            wechatPayDisabledTip() {
                const c = this.paymentCapabilities;
                if (c) {
                    const msg = resolveWechatPayDisabledMessage(c);
                    if (msg && msg !== DEFAULT_PAYMENT_DISABLED_MESSAGE) {
                        return msg;
                    }
                }
                return '微信支付暂不可用，请选用其他方式或联系门店。';
            },
            balanceChannelEnabled() {
                if (this.isWaiterCheckoutOnly) return false;
                const c = this.paymentCapabilities;
                if (c == null) return true;
                return isBalanceChannelEnabled(c);
            },
            showWechatPayChip() {
                return this.showOnlinePaymentMethods;
            },
            showBalancePayChip() {
                return this.showOnlinePaymentMethods && this.balanceChannelEnabled;
            },
            showCheckoutButton() {
                if ((this.other_data || {}).transac_status !== 'unsettled') return false;
                if (!this.showOnlinePaymentMethods) return false;
                if (this.paymentMethod === 'balance' && this.canPayByBalance) return true;
                if (this.paymentMethod === 'wxpay' && this.canUseWechatPay) return true;
                if (this.canUseWechatPay) return true;
                return this.canPayByBalance;
            },
            /** 是否可用余额全额支付（与 openapi /order/payByBalance 一致：不可与券、夜间九折叠加） */
            canPayByBalance() {
                if ((this.other_data || {}).transac_status !== 'unsettled') return false;
                if (!this.balanceChannelEnabled) return false;
                if (this.orderHasCombo) return false;
                if (this.orderUsesCoupon) return false;
                if (this.nightNinefoldShowPreview) return false;
                if (this.userBalance == null || !Number.isFinite(Number(this.userBalance))) return false;
                return Number(this.userBalance) + 1e-6 >= this.payAmountYuan;
            },
            userBalanceDisplayFormatted() {
                return formatBalanceForDisplay(this.userBalance);
            },
            // 结账按钮是否禁用
            isCheckoutDisabled() {
                if (this.isWaiterCheckoutOnly) return true;
                if (this.isProcessingPayment) {
                    return true; // 处理中时禁用按钮
                }
                if (this.other_data && this.other_data.transac_status) {
                    if (['success'].includes(this.other_data.transac_status)) return true;
                    if (this.other_data.transac_status === 'unsettled') {
                        if (!this.showOnlinePaymentMethods) return true;
                        if (this.paymentMethod === 'wxpay' && !this.canUseWechatPay) return true;
                        if (
                            this.paymentMethod === 'balance' &&
                            !this.canPayByBalance
                        ) {
                            return true;
                        }
                    }
                }
                return false;
            }
        },
        watch: {
            orderHasCombo(val) {
                if (val) {
                    try {
                        wx.removeStorageSync('selected_coupon');
                    } catch (e) {
                        /* ignore */
                    }
                    this.selectedCoupon = null;
                    this.availableCouponCount = 0;
                    if (this.paymentMethod === 'balance') {
                        this.paymentMethod = 'wxpay';
                    }
                }
            },
            orderUsesCoupon(val) {
                if (val && this.paymentMethod === 'balance') {
                    this.paymentMethod = 'wxpay';
                }
            },
            nightNinefoldShowPreview(val) {
                if (val && this.paymentMethod === 'balance') {
                    this.paymentMethod = 'wxpay';
                }
            },
            paymentMethod(val) {
                if (val === 'balance' && this.nightNinefoldShowPreview && !this.orderUsesCoupon) {
                    this.paymentMethod = 'wxpay';
                }
            },
            canPayByBalance(val) {
                if (val === false && this.paymentMethod === 'balance') {
                    this.paymentMethod = 'wxpay';
                }
            },
            showOnlinePaymentMethods(val) {
                if (!val && this.paymentMethod !== 'wxpay') {
                    this.paymentMethod = 'wxpay';
                }
            },
            canUseWechatPay(val) {
                if (!val && this.paymentMethod === 'wxpay' && this.canPayByBalance) {
                    this.paymentMethod = 'balance';
                }
            },
        },
        methods:{
            staticUrl,
            dishImageUrlOrDefault,
            isPageAlive() {
                return isPageVmStillActive(this);
            },

            formatDate(timestamp) {
                if (!timestamp) return ''
                let date
                if (typeof timestamp === 'string' && timestamp.indexOf(' ') !== -1) {
                    date = new Date(timestamp.replace(' ', 'T'))
                } else {
                    date = new Date(timestamp)
                }
                if (isNaN(date.getTime())) return String(timestamp)
                return date.getFullYear() + '-' +
                       (date.getMonth() + 1).toString().padStart(2, '0') + '-' +
                       date.getDate().toString().padStart(2, '0') + ' ' +
                       date.getHours().toString().padStart(2, '0') + ':' +
                       date.getMinutes().toString().padStart(2, '0')
            },

            resolvePaymentCapabilitiesOrderNo() {
                const o = this.other_data || {};
                return String(o.order_no || this.order_no || "").trim();
            },
            async loadBusinessFlags(force = false) {
                if (!force && this.businessFlagsLoaded) return;
                try {
                    const res = await requestUtil({
                        url: "/order/Business",
                        method: "post",
                        showLoading: false,
                    });
                    if (!this.isPageAlive()) return;
                    this.businessWxzf = parseWxzfFromBusinessResponse(res);
                    const review = parseReviewFromBusinessResponse(res);
                    if (app.globalData) {
                        app.globalData.isReviewMode = review;
                        app.globalData.isReviewModeUpdatedAt = Date.now();
                    }
                } catch (e) {
                    if (!this.isPageAlive()) return;
                } finally {
                    if (this.isPageAlive()) {
                        this.businessFlagsLoaded = true;
                    }
                }
            },
            async loadPaymentCapabilities(force = false) {
                const orderNo = this.resolvePaymentCapabilitiesOrderNo();
                const caps = await fetchPaymentCapabilities({
                    force: force === true,
                    orderNo: orderNo || undefined,
                });
                if (!this.isPageAlive()) return;
                this.paymentCapabilitiesLoaded = true;
                this.paymentCapabilities = caps;
                if (caps && caps.nineFold) {
                    this.ninefoldConfig = caps.nineFold;
                } else {
                    await this.loadNinefoldConfig();
                }
                this.syncPaymentMethodWithCapabilities();
            },
            syncPaymentMethodWithCapabilities() {
                if (!this.showOnlinePaymentMethods) return;
                if (this.paymentMethod === 'wxpay' && !this.canUseWechatPay) {
                    if (this.canPayByBalance) this.paymentMethod = 'balance';
                }
                if (this.paymentMethod === 'balance' && !this.balanceChannelEnabled) {
                    this.paymentMethod = 'wxpay';
                }
            },
            resolveNinefoldShopId() {
                const caps = this.paymentCapabilities;
                if (caps && caps.resolvedShopId != null && Number(caps.resolvedShopId) > 0) {
                    return Number(caps.resolvedShopId);
                }
                const oid = Number((this.other_data || {}).shop_id);
                return Number.isFinite(oid) && oid > 0 ? oid : null;
            },
            async loadNinefoldConfig(force = false) {
                const orderNo = this.resolvePaymentCapabilitiesOrderNo();
                const shopId = orderNo ? null : this.resolveNinefoldShopId();
                try {
                    const cfg = await fetchWechatPrepayNinefoldConfig({
                        force: force === true,
                        orderNo: orderNo || undefined,
                        shopId: shopId != null ? shopId : undefined,
                    });
                    if (!this.isPageAlive()) return;
                    this.ninefoldConfig = cfg;
                } catch (e) {
                    if (!this.isPageAlive()) return;
                    this.ninefoldConfig = null;
                }
            },
            closeOfflineCollect() {
                this.offlineCollectVisible = false;
                this.offlineCollectQrUrl = "";
                this.offlineCollectError = "";
            },
            async openOfflineCollectQr() {
                this.offlineCollectVisible = true;
                this.offlineCollectQrUrl = "";
                this.offlineCollectError = "";
                this.offlineCollectLoading = true;
                try {
                    const caps = this.paymentCapabilities;
                    const shopId =
                        caps && caps.resolvedShopId != null && Number(caps.resolvedShopId) > 0
                            ? Number(caps.resolvedShopId)
                            : undefined;
                    const res = await fetchOfflineCollectTempQrcode({
                        channel: "wechat",
                        shopId,
                    });
                    if (!this.isPageAlive()) return;
                    if (res && res.code === 0 && res.qrImageDataUrl) {
                        this.offlineCollectQrUrl = res.qrImageDataUrl;
                    } else {
                        this.offlineCollectError =
                            (res && (res.msg || res.message)) || "暂无法生成收款码，请联系门店";
                    }
                } catch (e) {
                    if (!this.isPageAlive()) return;
                    this.offlineCollectError = "网络异常，请稍后重试";
                } finally {
                    if (this.isPageAlive()) this.offlineCollectLoading = false;
                }
            },
			
            isComboHeaderLine(item) {
                return isComboHeaderOrderLine(item);
            },
            getOrderLineMeta(item) {
                if (!item) return "";
                const spicy = this.getSpicyText(item.selectedSpicy);
                if (spicy) return spicy;
                if (this.isComboHeaderLine(item)) {
                    const view = buildOrderComboDetailView(item, this.goods_data);
                    if (view.summary) {
                        const max = 28;
                        const short =
                            view.summary.length > max
                                ? view.summary.slice(0, max) + "…"
                                : view.summary;
                        return `${short} · 点击查看`;
                    }
                    return "点击查看套餐明细";
                }
                return item.unit ? "规格：" + item.unit : "";
            },
            onComboLineTap(item) {
                if (!this.isComboHeaderLine(item)) return;
                const view = buildOrderComboDetailView(item, this.goods_data);
                if (!view.hasDetail) {
                    wx.showToast({ title: "暂无套餐明细", icon: "none" });
                    return;
                }
                this.comboDetailTitle = view.title;
                this.comboDetailSummary = view.summary || "";
                this.comboDetailItems = view.items || [];
                this.comboDetailVisible = true;
            },
            closeComboDetail() {
                this.comboDetailVisible = false;
            },
			getSpicyText(spicy) {
				if (!spicy) return '';

				
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
            
            getOrderStatusText() {
                const order = this.other_data || {};
                const transac = order.transac_status;
                const receiving = order.order_receiving;

                if (transac === 'cancelled') return '已取消';
                
				switch (receiving) {
                        case 'mis_order': return '等待接单';
                        case 'rec_order': return '已接单，正在制作';
                        case 'off_order': return '制作完成';
                        case 'cancelled': return '已取消';
                        default: return '未结账';
                    }
               
            },


            async get_menu(showLoading = true){
                if (showLoading) {
                    this.isLoading = true
                    wx.showLoading({ title: '加载中...' })
                }
                
                try{
                    
					let res = null;
					if(this.table_number){
						res = await requestUtil({
						    url: "/order/get",
						    data: { 'table_number': this.table_number ,'transac_status': 'unsettled' },
						    method: "get"
						});
						
					}else{
						res = await requestUtil({
						    url: "/order/getOrder",
						    data: { 'order_no': this.order_no },
						    method: "get"
						});
					}
					if (!this.isPageAlive()) return;
					console.log(res);
					const payload = res && res.data != null && typeof res.data === 'object' && !Array.isArray(res.data) ? res.data : res;
                    if(payload.goods_list != null){
						this.OrderStatus = payload.goods_list.length <= 0;
						if(this.OrderStatus){
							wx.switchTab({
							    url: `/pages/index/index`
							});
						}
						let res_data = payload.goods_list || []
						this.overall = res_data.length
						this.takeoutDelivery = null;
						this.riderTracking = null;
						this.other_data = (payload && payload.menu) || {}
						// openapi：GET /order/getOrder 外卖时根级 delivery 为 TakeoutDelivery（address_full、receiver_*、delivery_fee、dispatch_status 等）
						if (payload && typeof payload === 'object') {
							if (payload.delivery != null && typeof payload.delivery === 'object') {
								this.takeoutDelivery = payload.delivery;
							} else if (payload.menu && payload.menu.delivery != null && typeof payload.menu.delivery === 'object') {
								this.takeoutDelivery = payload.menu.delivery;
							}
							const liftTakeoutKeys = [
								'address_full', 'addressFull', 'takeout_address_full', 'takeoutAddressFull',
								'delivery_address', 'deliveryAddress',
								'receiver_name', 'receiverName', 'receiver_phone', 'receiverPhone',
								'receiver_province', 'receiver_city', 'receiver_district', 'receiver_detail',
							];
							liftTakeoutKeys.forEach((k) => {
								const v = payload[k];
								if (v != null && v !== '' && (this.other_data[k] == null || this.other_data[k] === '')) {
									this.$set(this.other_data, k, v);
								}
							});
						}
						
						if (this.other_data.orderNumber === undefined || this.other_data.orderNumber === null) {
						    this.other_data.orderNumber = 1;
						}
						
						if (!this.other_data.orderStatus) {
						    this.other_data.orderStatus = 'pending';
						}
						
						if (res_data && res_data.length) {
						    res_data.forEach(item => {
						        item.orderNumber = item.orderNumber || this.other_data.orderNumber;
						    });
						}
						
						this.goods_data = res_data
						if (this.hasOrderDiscountAmount) {
							wx.removeStorageSync('selected_coupon');
							this.selectedCoupon = null;
							this.availableCouponCount = 0;
						} else {
							this.fetchAvailableCouponCount();
						}
						this.refreshCurrentStoreName()
						this.exist = false
						this.fetchEstimatedFinishTime()
						this.refreshUserBalanceForPay()
						this.syncRiderTrackingSchedule()
						await this.loadPaymentCapabilities(true)

					}else{
						wx.showToast({
						    title: '获取订单数据失败',
						    icon: 'none'
						})
						setTimeout(() => {
							wx.switchTab({
								url: `/pages/index/index`
							});
						}, 1000);
						
					}
					
                    
                    
                }catch(e){
                    console.error('获取订单数据失败:', e)
                    wx.showToast({
                        title: '获取订单数据失败',
                        icon: 'none'
                    })
                } finally {
                    if (showLoading && this.isPageAlive()) {
                        this.isLoading = false
                        wx.hideLoading()
                    }
                }
            },
            applyTakeoutTrackingPayload(payload) {
                if (!payload) return;
                const { tracking, orderPatch, delivery } = parseTakeoutTrackingResponse(payload);
                if (tracking) {
                    this.riderTracking = tracking;
                    this.riderTrackingUpdatedAt = Date.now();
                    const del = this.takeoutDelivery || this.takeoutDel;
                    const r = tracking.rider || {};
                    if (del && typeof del === 'object') {
                        if (r.name) this.$set(del, 'zsq_rider_name', r.name);
                        if (r.phone) this.$set(del, 'zsq_rider_phone', r.phone);
                        if (r.lat != null) this.$set(del, 'zsq_rider_lat', r.lat);
                        if (r.lng != null) this.$set(del, 'zsq_rider_lng', r.lng);
                    }
                }
                if (orderPatch && typeof orderPatch === 'object') {
                    this.other_data = { ...(this.other_data || {}), ...orderPatch };
                }
                if (delivery && typeof delivery === 'object') {
                    this.takeoutDelivery = delivery;
                }
                const status = resolveTakeoutDispatchStatus(
                    tracking || this.riderTracking,
                    delivery || this.takeoutDelivery,
                    this.other_data
                );
                if (status && this.other_data) {
                    this.$set(this.other_data, 'takeout_dispatch_status', status);
                }
            },
            async fetchRiderTracking(silent = true) {
                if (!this.isTakeoutOrder) return;
                const orderNo = (this.other_data && this.other_data.order_no) || this.order_no || '';
                const openid = app.globalData && app.globalData.openid;
                if (!orderNo || !openid) return;
                if (!shouldPollTakeoutRiderTracking(this.takeoutDel, this.other_data, this.riderTracking) &&
                    !hasRiderUiContent(this.riderHero, this.riderMapState)) {
                    return;
                }
                if (this.riderTrackingRefreshing) return;
                this.riderTrackingRefreshing = true;
                try {
                    const res = await requestUtil({
                        url: '/order/takeout/order/tracking',
                        method: 'get',
                        data: { openid, order_no: orderNo },
                        showLoading: !silent,
                    });
                    if (!this.isPageAlive()) return;
                    if (res && res.code === 0) {
                        this.applyTakeoutTrackingPayload(res);
                        const pts = this.riderMapIncludePoints;
                        if (pts && pts.length >= 2) {
                            this.riderMapScale = 13;
                        }
                        if (!shouldPollTakeoutRiderTracking(this.takeoutDel, this.other_data, this.riderTracking)) {
                            this.stopRiderTrackingPoll();
                        }
                    }
                } catch (e) {
                    if (!silent) {
                        wx.showToast({ title: '位置同步失败', icon: 'none' });
                    }
                } finally {
                    if (this.isPageAlive()) {
                        this.riderTrackingRefreshing = false;
                    }
                }
            },
            refreshRiderTracking() {
                if (this.riderTrackingRefreshing) return;
                this.fetchRiderTracking(false);
            },
            syncRiderTrackingSchedule() {
                this.stopRiderTrackingPoll();
                if (!shouldPollTakeoutRiderTracking(this.takeoutDel, this.other_data, this.riderTracking)) {
                    this.fetchRiderTracking(true);
                    return;
                }
                this.fetchRiderTracking(true);
                this.riderTrackingTimer = setInterval(() => {
                    if (!this.isPageAlive()) {
                        this.stopRiderTrackingPoll();
                        return;
                    }
                    this.fetchRiderTracking(true);
                }, RIDER_TRACKING_POLL_MS);
            },
            stopRiderTrackingPoll() {
                if (this.riderTrackingTimer) {
                    clearInterval(this.riderTrackingTimer);
                    this.riderTrackingTimer = null;
                }
            },
            callRiderPhone() {
                const phone = this.riderHero && this.riderHero.phone;
                if (!phone) return;
                wx.makePhoneCall({
                    phoneNumber: String(phone),
                    fail: () => {
                        wx.showToast({ title: '无法拨打', icon: 'none' });
                    },
                });
            },
            async fetchEstimatedFinishTime() {
                const order = this.other_data || {};
                if (order.transac_status === 'cancelled') return;
                const dineInOrTakeOut = order.dineInOrTakeOut || '堂食';
                const orderInfo = {
                    id: order.id || this.orderId || '',
                    order_no: order.order_no || this.order_no || '',
                    table_number: order.table_number || this.table_number || '',
                    dineInOrTakeOut,
                    transac_status: order.transac_status || '',
                    order_receiving: order.order_receiving || '',
                    morder_num: order.morder_num || order.orderNumber || 1
                };
                try {
                    const res = await requestUtil({
                        url: '/order/calculateFinishTime',
                        method: 'post',
                        data: orderInfo,
                        showLoading: false
                    });
                    if (!this.isPageAlive()) return;
                    if (res && res.code === 0 && res.makeTime) {
                        this.estimatedFinishTime = String(res.makeTime);
                    } else {
                        this.estimatedFinishTime = '';
                    }
                } catch (e) {
                    console.error('预估出餐时间获取失败:', e);
                    if (this.isPageAlive()) this.estimatedFinishTime = '';
                }
            },
            async checkOrder(number){
				if(number){
					this.table_number = number;
				}
				const res = await requestUtil({
				    url: "/order/table_status",
				    data: { 'number': this.table_number },
				    method: "get"
				});
				this.OrderStatus = res.status;
			},
            // 鍔犺彍
			async add_Dish() {
			    if (this.isLoading) return;
			    
			    try {
					await this.checkOrder(this.other_data.table_number);
			        
			        if (this.OrderStatus > 0) {
						const dn = Number(this.other_data.number_of_diners);
						if (Number.isFinite(dn) && dn > 0) {
							saveDinersCount(app, dn);
						}
						const orderUsedCoupon = Number(this.other_data.discount_amount || 0) > 0 ? true : false;
			            wx.reLaunch({
			                url: `/pages/home-page/page?order_no=${this.other_data.order_no}&orderNumber=${this.other_data.orderNumber}&table_number=${this.other_data.table_number}&dineInOrTakeOut=${this.other_data.dineInOrTakeOut}&order_used_coupon=${orderUsedCoupon}`
			            });
			        } else {
			            wx.switchTab({
			                url: `/pages/index/index`
			            });
			        }
			    } catch (error) {
			        console.error('加菜操作失败:', error);
			        wx.showToast({
			            title: '操作失败，请重试',
			            icon: 'none'
			        });
			    }
			},
			

			setPaymentMethod(method) {
				if (method === 'balance' && !this.canPayByBalance) return;
				this.paymentMethod = method === 'balance' ? 'balance' : 'wxpay';
			},
			pickBalancePayment() {
				if (this.orderHasCombo) {
					wx.showToast({
						title: COMBO_PAYMENT_RESTRICT_MSG,
						icon: 'none',
						duration: 2800,
					});
					return;
				}
				if (this.orderUsesCoupon) {
					wx.showToast({
						title: '使用优惠券时不可用余额支付，请使用微信支付',
						icon: 'none',
					});
					return;
				}
				if (this.nightNinefoldShowPreview) {
					wx.showToast({
						title: '夜间九折优惠与余额支付不可同时使用，请使用微信支付',
						icon: 'none',
					});
					return;
				}
				if (!this.canPayByBalance) {
					if (this.userBalance == null || !Number.isFinite(Number(this.userBalance))) {
						wx.showToast({ title: '正在获取账户余额，请稍候', icon: 'none' });
						this.refreshUserBalanceForPay();
					} else {
						this.openInsufficientBalanceModal();
					}
					return;
				}
				this.paymentMethod = 'balance';
			},
			goToMemberRecharge() {
				wx.navigateTo({ url: '/packageOther/member-recharge/member-recharge' });
			},
			/** 后端返回是否余额不足（兼容多种文案） */
			isInsufficientBalanceMsg(text) {
				const s = String(text || '');
				return /余额不足|余额不够|账户余额不足|可用余额不足|扣减.*失败|insufficient/i.test(s);
			},
			/**
			 * 余额不足时弹窗：去充值 / 改用微信支付
			 * @param {string} [serverMsg] 后端错误信息，附在说明后
			 */
			openInsufficientBalanceModal(serverMsg) {
				const balTxt =
					this.userBalance != null && Number.isFinite(Number(this.userBalance))
						? `¥${this.userBalanceDisplayFormatted}`
						: '—';
				const needTxt = `¥${this.displaySettAmount}`;
				let content = `当前余额 ${balTxt}，本单应付 ${needTxt}。请先充值后再用余额支付，或选「改用微信支付」后再次点击结账。`;
				if (serverMsg && String(serverMsg).trim()) {
					content += `\n\n${String(serverMsg).trim()}`;
				}
				wx.showModal({
					title: '余额不足',
					content,
					confirmText: '去充值',
					cancelText: '改用微信支付',
					success: (r) => {
						if (r.confirm) {
							wx.navigateTo({ url: '/packageOther/member-recharge/member-recharge' });
						} else if (r.cancel) {
							this.paymentMethod = 'wxpay';
						}
					},
				});
			},
			async refreshUserBalanceForPay() {
				const openid = app.globalData.openid || wx.getStorageSync('openid');
				if (!openid) {
					this.userBalance = null;
					return;
				}
				try {
					const res = await app.getUserInfo({ showLoading: false });
					if (!this.isPageAlive()) return;
					if (res && res.code === 0 && res.data) {
						const raw = res.data.balance;
						if (raw == null || raw === '') {
							this.userBalance = null;
						} else {
							const n = Number(raw);
							this.userBalance = Number.isFinite(n) ? Math.round(n * 100) / 100 : null;
						}
					}
				} catch (e) {
					this.userBalance = null;
				}
				if (this.paymentMethod === 'balance' && !this.canPayByBalance) {
					this.paymentMethod = 'wxpay';
				}
			},
			async payOrderByBalance() {
				if (!this.showOnlinePaymentMethods || !this.balanceChannelEnabled) {
					this.showToastMessage(this.paymentDisabledHint);
					return false;
				}
				if (this.orderHasCombo) {
					wx.showToast({
						title: COMBO_PAYMENT_RESTRICT_MSG,
						icon: 'none',
						duration: 2800,
					});
					return false;
				}
				if (this.orderUsesCoupon) {
					wx.showToast({
						title: '使用优惠券时不可用余额支付，请使用微信支付',
						icon: 'none',
					});
					return false;
				}
				if (this.nightNinefoldShowPreview) {
					wx.showToast({
						title: '夜间九折优惠与余额支付不可同时使用，请使用微信支付',
						icon: 'none',
					});
					return false;
				}
				const openid = app.globalData.openid || wx.getStorageSync('openid');
				const res = await requestUtil({
					url: '/order/payByBalance',
					method: 'post',
					data: {
						orderNo: this.other_data.order_no,
						openid,
						coupon_id: '',
					},
					showLoading: false,
				});
				if (res && res.code === 0 && (res.alreadyPaid === true || res.paidYuan != null || res.payment_method)) {
					wx.removeStorageSync('selected_coupon');
					this.other_data.order_receiving = 'rec_order';
					this.other_data.transac_status = 'success';
					if (res.payment_method) {
						this.other_data.payment_method = res.payment_method;
					}
					await this.refreshUserBalanceForPay();
					this.showToastMessage(res.alreadyPaid ? '订单已支付' : '余额支付成功，已结账');
					return true;
				}
				const payCode = res && Number(res.code);
				if (
					payCode === PAYMENT_ONLINE_DISABLED_CODE ||
					payCode === PAYMENT_CHANNEL_DISABLED_CODE ||
					payCode === PAYMENT_WECHAT_MERCHANT_MISSING_CODE
				) {
					await this.loadPaymentCapabilities(true);
					this.showToastMessage(
						resolvePaymentApiErrorMessage(res, this.paymentCapabilities)
					);
					return false;
				}
				const msg = (res && (res.msg || res.message)) || '余额支付失败';
				await this.refreshUserBalanceForPay();
				if (this.isInsufficientBalanceMsg(msg)) {
					this.openInsufficientBalanceModal(msg);
				} else {
					this.showToastMessage(String(msg));
				}
				return false;
			},
            onFooterCheckoutClick() {
                if (this.footerCheckoutBtnDisabled) return;
                if (!this.canProceedOnlineCheckout) {
                    if (this.showOfflineCollectEntry) {
                        this.openOfflineCollectQr();
                        return;
                    }
                    this.showToastMessage(this.checkoutButtonLabel);
                    return;
                }
                this.handleCheckout();
            },
			async handleCheckout() {
				if (this.isCheckoutDisabled) return;
				if (!this.canProceedOnlineCheckout) {
					if (this.showOfflineCollectEntry) {
						this.openOfflineCollectQr();
					} else {
						this.showToastMessage(this.checkoutButtonLabel);
					}
					return;
				}
				if (this.paymentMethod === 'wxpay' && !this.canUseWechatPay) {
					this.showToastMessage(this.paymentDisabledHint);
					return;
				}
				const openid = app.globalData.openid || wx.getStorageSync('openid');
				const userInfo = app.globalData.userInfo || wx.getStorageSync('userInfo') || {};
				const hasPhone = userInfo.phone && String(userInfo.phone).trim();
				if (!openid || !hasPhone) {
					const url = `/packageOther/order-details/details?order_no=${(this.other_data && this.other_data.order_no) || ''}`;
					app.checkLogin(url);
					wx.showToast({ title: '请先登录并绑定手机号', icon: 'none' });
					return;
				}
				if (this.paymentMethod === 'balance') {
					if (this.orderHasCombo) {
						wx.showToast({
							title: COMBO_PAYMENT_RESTRICT_MSG,
							icon: 'none',
							duration: 2800,
						});
						this.paymentMethod = 'wxpay';
						return;
					}
					if (this.orderUsesCoupon) {
						wx.showToast({
							title: '使用优惠券时不可用余额支付，请使用微信支付',
							icon: 'none',
						});
						this.paymentMethod = 'wxpay';
						return;
					}
					if (this.nightNinefoldShowPreview) {
						wx.showToast({
							title: '夜间九折优惠与余额支付不可同时使用，请使用微信支付',
							icon: 'none',
						});
						this.paymentMethod = 'wxpay';
						return;
					}
					if (!this.canPayByBalance) {
						this.openInsufficientBalanceModal();
						return;
					}
					const amount = this.displaySettAmount;
					const ok = await new Promise((resolve) => {
						wx.showModal({
							title: '确认余额支付',
							content: `将使用账户余额支付 ¥${amount}，支付后立即扣款并与本单绑定。是否继续？`,
							confirmText: '确认支付',
							cancelText: '取消',
							success: (r) => resolve(!!r.confirm),
						});
					});
					if (!ok) return;
				}
				this.isProcessingPayment = true;
				try {
					if (this.paymentMethod === 'balance') {
						await this.payOrderByBalance();
						return;
					}
					const result = await app.payOrder({
						orderNo: this.other_data.order_no,
						totalAmount: this.displaySettAmount * 1,
						dineInOrTakeOut: this.other_data.dineInOrTakeOut,
						coupon_id:
							!this.orderHasCombo && !this.hasOrderDiscountAmount && this.selectedCoupon
								? this.selectedCoupon.id || ""
								: "",
						coupon_type:
							!this.orderHasCombo && !this.hasOrderDiscountAmount && this.selectedCoupon
								? this.selectedCoupon.coupon_type || ""
								: "",
						discount_amount: this.orderHasCombo
							? 0
							: this.hasOrderDiscountAmount
								? Number((this.other_data || {}).discount_amount || 0)
								: Number(this.displayDiscountAmount) || 0,
					});
					if (result && result.success) {
						wx.removeStorageSync('selected_coupon');
						this.other_data.order_receiving = 'rec_order';
						this.showToastMessage('微信支付成功，已结账');
						this.other_data.transac_status = "success";
						this.other_data.payment_method = '微信支付';
						await this.refreshUserBalanceForPay();
					} else {
						
						if (!app.globalData.openid) {
							this.showToastMessage('支付失败: 未登录小程序');
						} else {
							const msg = (result && result.response && (result.response.message || result.response.msg)) || (result && result.error && result.error.message) || '未知错误';
							this.showToastMessage(`支付失败: ${msg}`);
						}
					}
				} catch (error) {
					
					console.error('支付失败:', error);
					this.showToastMessage('支付过程中发生错误，请重试');
				} finally {
					this.isProcessingPayment = false;
				}
			},
		

			showToastMessage(message) {
				this.toastMessage = message;
				this.showToast = true;
				setTimeout(() => {
					this.showToast = false;
				}, 3000);
			},
            // 优惠券规则使用的订单行：优先 other_data 内订单明细，兜底当前 goods_data
            buildCouponOrderLines() {
                const order = this.other_data || {};
                const candidates = [
                    order.goods_data,
                    order.goods_list,
                    order.items,
                    order.order_items,
                    order.dishes,
                ];
                for (let i = 0; i < candidates.length; i++) {
                    const raw = candidates[i];
                    if (Array.isArray(raw)) return this.normalizeCouponOrderLines(raw);
                    if (typeof raw === 'string' && raw.trim()) {
                        try {
                            const parsed = JSON.parse(raw);
                            if (Array.isArray(parsed)) return this.normalizeCouponOrderLines(parsed);
                        } catch (e) {}
                    }
                }
                return this.normalizeCouponOrderLines(Array.isArray(this.goods_data) ? this.goods_data : []);
            },
            // 统一订单行字段，确保优惠券规则层能稳定识别菜品ID和金额
            normalizeCouponOrderLines(lines) {
                if (!Array.isArray(lines)) return [];
                return lines
                    .map((item) => {
                        if (!item || typeof item !== 'object') return null;
                        const lt = String(item.line_type || item.lineType || "").toLowerCase();
                        if (lt === "combo_component") return null;
                        const dishRaw = item.dish_id ??
                            item.dishId ??
                            item.goods_id ??
                            item.goodsId ??
                            item.item_id ??
                            item.itemId ??
                            item.did ??
                            item.menu_id ??
                            item.menuId ??
                            item.id;
                        const dishIdNum = Number(dishRaw);
                        const qty = Number(item.quantity ?? item.qty ?? item.count ?? item.num ?? 0);
                        const unit = Number(
                            item.unitprice ?? item.unit_price ?? item.price ?? item.unitPrice ?? 0
                        );
                        const directTotal = Number(
                            item.total_price ??
                            item.totalPrice ??
                            item.subtotal ??
                            item.amount ??
                            item.line_total ??
                            item.lineTotal
                        );
                        const total = Number.isFinite(directTotal) && directTotal >= 0 ? directTotal : (unit * qty);
                        return {
                            ...item,
                            line_type: item.line_type || item.lineType,
                            // 保留原始明细 id（通常是 t_order_detail.id），避免覆盖业务语义
                            dish_id: Number.isFinite(dishIdNum) ? dishIdNum : item.dish_id,
                            dishId: Number.isFinite(dishIdNum) ? dishIdNum : item.dishId,
                            quantity: Number.isFinite(qty) ? qty : 0,
                            unitprice: Number.isFinite(unit) ? unit : 0,
                            total_price: Number.isFinite(total) ? total : 0,
                        };
                    })
                    .filter(Boolean);
            },

            getCouponOrderCtx() {
                const d = this.other_data || {};
                return buildCouponOrderSelectionPayload('details', {
                    orderBaseTotal: this.couponOrderBaseTotal,
                    orderLines: this.buildCouponOrderLines(),
                    dineInOrTakeOut: d.dineInOrTakeOut || '堂食',
                    currentShopId: getCurrentShopId(),
                }).ctx;
            },
            validateSelectedCoupon() {
                if (!this.selectedCoupon) return;
                const ctx = this.getCouponOrderCtx();
                if (!orderAllowsCoupon(ctx) || !couponPassesLocalOrderRules(this.selectedCoupon, ctx)) {
                    wx.removeStorageSync('selected_coupon');
                    this.selectedCoupon = null;
                }
            },
            async fetchAvailableCouponCount(force = false) {
                if (this.orderHasCombo) {
                    wx.removeStorageSync('selected_coupon');
                    this.selectedCoupon = null;
                    this.availableCouponCount = 0;
                    return;
                }
                if (this.hasOrderDiscountAmount) {
                    wx.removeStorageSync('selected_coupon');
                    this.selectedCoupon = null;
                    this.availableCouponCount = 0;
                    return;
                }
                const now = Date.now();
                const ttl = 30000;
                if (!force && this._couponCountFetchedAt && (now - this._couponCountFetchedAt < ttl)) {
                    return;
                }
                if (this._couponCountReq) {
                    return this._couponCountReq;
                }
                const openid = app.globalData.openid || wx.getStorageSync('openid');
                if (!openid) return;
                this._couponCountReq = (async () => {
                    try {
                    const res = await requestUtil({
                        url: '/coupon/getUserAvailableCoupons',
                        method: 'post',
                        data: { openid },
                        showLoading: false
                    });
                    if (!this.isPageAlive()) return;
                    if (res && res.code === 0) {
                        const raw = normalizeCouponListPayload(res);
                        const d = this.other_data || {};
                        const orderLines = this.buildCouponOrderLines();
                        console.log("[coupon-debug][details][count] local-rules-input", {
                            orderBaseTotal: this.couponOrderBaseTotal,
                            goodsTotal: this.orderGoodsTotal,
                            packagingFeeEstimate: this.orderPackagingFeeEstimate,
                            settAmount: Number(d.sett_amount || 0),
                            shoppingCartLength: Array.isArray(orderLines) ? orderLines.length : 0,
                            dineInOrTakeOut: d.dineInOrTakeOut || '堂食',
                            shopId: getCurrentShopId(),
                            apiListLength: Array.isArray(raw) ? raw.length : 0,
                        });
                        const ctx = this.getCouponOrderCtx();
                        this.availableCouponCount = countCouponsPassingLocalOrderRules(raw, ctx);
                        this.validateSelectedCoupon();
						if(this.availableCouponCount == 0){
							wx.removeStorageSync('selected_coupon');
							this.selectedCoupon = null;
						}
                        this._couponCountFetchedAt = Date.now();
                    } else {
                        this.availableCouponCount = 0;
						wx.removeStorageSync('selected_coupon');
						this.selectedCoupon = null;


                    }
                } catch (e) {
                    console.error('获取可用优惠券数量失败', e);
                    this.availableCouponCount = 0;
                } finally {
                    this._couponCountReq = null;
                }
                })();
                return this._couponCountReq;
            },

            selectCoupon() {
                if (!this.other_data || this.other_data.transac_status !== 'unsettled') return;
                if (this.orderHasCombo) {
                    wx.showToast({
                        title: COMBO_PAYMENT_RESTRICT_MSG,
                        icon: 'none',
                        duration: 2800,
                    });
                    return;
                }
                if (this.hasOrderDiscountAmount) {
                    wx.removeStorageSync('selected_coupon');
                    this.selectedCoupon = null;
                    return;
                }
                const diningType = this.other_data.dineInOrTakeOut || '堂食';
                const payload = buildCouponOrderSelectionPayload('details', {
                    orderBaseTotal: this.couponOrderBaseTotal,
                    orderLines: this.buildCouponOrderLines(),
                    dineInOrTakeOut: diningType,
                    currentShopId: getCurrentShopId(),
                });
                console.log("[coupon-debug][details][selectCoupon] navigate params", {
                    orderBaseTotal: payload.ctx.orderBaseTotal,
                    goodsTotal: this.orderGoodsTotal,
                    packagingFeeEstimate: this.orderPackagingFeeEstimate,
                    settAmount: Number((this.other_data || {}).sett_amount || 0),
                    goodsDataLength: Array.isArray(this.goods_data) ? this.goods_data.length : 0,
                    orderLinesLength: Array.isArray(payload.orderLines) ? payload.orderLines.length : 0,
                    dineInOrTakeOut: diningType,
                    targetUrl: payload.navigateUrl,
                });
                wx.navigateTo({
                    url: payload.navigateUrl,
                    success: (res) => {
                        try {
                            if (res && res.eventChannel && typeof res.eventChannel.emit === "function") {
                                res.eventChannel.emit("couponOrderCtx", {
                                    orderLines: payload.orderLines,
                                });
                            }
                        } catch (e) {}
                    },
                });
            },
            // 从缓存读取的优惠券是否存在且有效（有 id/coupon_type，未过期则视为有效）
            isValidSelectedCoupon(coupon) {
                if (!coupon || typeof coupon !== 'object') return false;
                if (coupon.id == null || coupon.id === '') return false;
                if (!coupon.coupon_type) return false;
                const expireTime = coupon.expire_time;
                if (expireTime) {
                    try {
                        const t = new Date(String(expireTime).replace(/-/g, '/')).getTime();
                        if (isNaN(t) || t < Date.now()) return false;
                    } catch (e) {
                        return false;
                    }
                }
                return true;
            },
            goBack() {
             wx.navigateBack();
            },    

			async onOpenOrderComment() {
				await openOrderComment(this.other_data || {});
			},
			onCancelOrder() {
				const orderNo = (this.other_data && this.other_data.order_no) ? this.other_data.order_no.trim() : '';
				if (!orderNo) {
					wx.showToast({ title: '订单号无效', icon: 'none' });
					return;
				}
				const openid = app.globalData.openid;
				if (!openid) {
					wx.showToast({ title: '请先登录', icon: 'none' });
					return;
				}
				wx.showModal({
					title: '取消订单',
					content: '确定要取消该订单吗？',
					confirmText: '确认取消',
					cancelText: '再想想',
					success: async (res) => {
						if (!res.confirm) return;
						try {
							wx.showLoading({ title: '处理中...', mask: true });
							const result = await requestUtil({
								url: '/order/cancel',
								data: { order_no: orderNo, openid },
								method: 'post',
								showLoading: false
							});
							wx.hideLoading();
							if (result && result.code === 0) {
								this.other_data.transac_status = 'cancelled';
								wx.showToast({ title: '订单已取消', icon: 'success' });
							} else {
								wx.showToast({ title: (result && result.msg) || '取消失败', icon: 'none' });
							}
						} catch (e) {
							wx.hideLoading();
							wx.showToast({ title: '取消失败，请重试', icon: 'none' });
						}
					}
				});
			},
			refreshCurrentStoreName() {
				const order = this.other_data || {};
				const orderShopName = order.shop_name != null ? String(order.shop_name).trim() : '';
				if (orderShopName) {
					this.currentStoreName = orderShopName;
					return;
				}
				const orderShopId = Number(order.shop_id);
				if (Number.isFinite(orderShopId) && orderShopId > 0 && this.shopNameById[orderShopId]) {
					this.currentStoreName = this.shopNameById[orderShopId];
					return;
				}
				const s = getCurrentShopSnapshot();
				const n = (s && s.name && String(s.name).trim()) || '';
				if (n) {
					this.currentStoreName = n;
					return;
				}
				if (Number.isFinite(orderShopId) && orderShopId > 0) {
					this.currentStoreName = `门店#${orderShopId}`;
					return;
				}
				this.currentStoreName = '老肥油边王';
			},
			async loadShopNameMap() {
				try {
					const res = await requestUtil({
						url: "/shop/list",
						method: "get",
						showLoading: false
					});
					if (!this.isPageAlive()) return;
					if (!res || res.code !== 0 || !Array.isArray(res.list)) return;
					const map = {};
					res.list.forEach((shop) => {
						const id = Number(shop && shop.id);
						const name = shop && shop.name != null ? String(shop.name).trim() : "";
						if (Number.isFinite(id) && id > 0 && name) {
							map[id] = name;
						}
					});
					this.shopNameById = map;
					this.refreshCurrentStoreName();
				} catch (e) {
					// 门店名映射加载失败时，仍可使用订单 shop_name / 本地快照兜底
				}
			},
        },
        async onShow() {
			if (typeof app.guardToQueueIfReview === "function") {
				const redirected = await app.guardToQueueIfReview();
				if (redirected) return;
			}
			this.loadBusinessFlags();
			this.loadPaymentCapabilities();
			this.refreshCurrentStoreName();
			this.refreshUserBalanceForPay();
            const raw = wx.getStorageSync('selected_coupon');
            const valid = this.isValidSelectedCoupon(raw);
            if (valid) {
                this.selectedCoupon = raw;
                if (Array.isArray(this.goods_data) && this.goods_data.length > 0) {
                    this.validateSelectedCoupon();
                }
            } else {
                if (raw) wx.removeStorageSync('selected_coupon');
                this.selectedCoupon = null;
            }
            if (Array.isArray(this.goods_data) && this.goods_data.length > 0) {
                this.fetchAvailableCouponCount();
            }
            this.syncRiderTrackingSchedule();
        },
        async onLoad(options) {
			if (typeof app.guardToQueueIfReview === "function") {
				const redirected = await app.guardToQueueIfReview({ force: true });
				if (redirected) return;
			}
			this.refreshCurrentStoreName();
			this.loadShopNameMap();
			// 每次进入订单详情都清理已选优惠券，避免从确认页残留并被自动选中
			wx.removeStorageSync('selected_coupon');
			this.selectedCoupon = null;
			this.availableCouponCount = null;
			if(options && options.table_number){
				this.table_number = options.table_number;
			}else{
				this.table_number = '';
				if (options.order_no) {
				    this.order_no = options.order_no;
				} else {
					wx.reLaunch({
					    url: `/pages/index/index`
					});
				}
			}
            this.loadBusinessFlags();
            this.loadPaymentCapabilities();
            this.get_menu()
            this.baseUrl=getBaseUrl()
        },
        onHide() {
            this.stopRiderTrackingPoll();
        },
        onUnload() {
            if (this.refreshTimer) {
                clearInterval(this.refreshTimer);
            }
            this.stopRiderTrackingPoll();
        }
    }
</script>

<style>
/* ========== 页面与卡片（美团式） ========== */
page {
  background-color: #f5f5f5;
}

.od-page {
  min-height: 100vh;
  padding: 16rpx 16rpx 0;
  box-sizing: border-box;
}

/* ========== 骑手配送 Hero（地图置顶） ========== */
.od-rider-hero {
  margin: -16rpx -16rpx 20rpx;
  background: #fff;
  border-radius: 0 0 24rpx 24rpx;
  overflow: hidden;
  box-shadow: 0 8rpx 24rpx rgba(0, 0, 0, 0.06);
}

.od-rider-map-wrap {
  width: 100%;
  height: 420rpx;
  position: relative;
}

.od-rider-map {
  width: 100%;
  height: 420rpx;
}

.od-rider-map--placeholder {
  display: flex;
  align-items: center;
  justify-content: center;
  background: linear-gradient(180deg, #e8f4ea 0%, #f5f5f5 100%);
}

.od-rider-map-ph-text {
  font-size: 26rpx;
  color: #888;
}

.od-rider-hero-panel {
  padding: 24rpx 24rpx 28rpx;
}

.od-rider-hero-head {
  display: flex;
  flex-direction: row;
  align-items: flex-start;
  justify-content: space-between;
  gap: 16rpx;
  margin-bottom: 24rpx;
}

.od-rider-hero-head-main {
  flex: 1;
  min-width: 0;
}

.od-rider-hero-title {
  display: block;
  font-size: 34rpx;
  font-weight: 700;
  color: #1a1a1a;
  line-height: 1.35;
}

.od-rider-hero-sub {
  display: block;
  margin-top: 8rpx;
  font-size: 26rpx;
  color: #666;
  line-height: 1.45;
}

.od-rider-refresh-btn {
  flex-shrink: 0;
  padding: 12rpx 24rpx;
  border-radius: 999rpx;
  border: 1rpx solid #ddd;
  background: #fff;
  font-size: 24rpx;
  color: #333;
  line-height: 1.3;
}

.od-rider-refresh-btn--loading {
  opacity: 0.65;
}

.od-rider-metrics {
  display: flex;
  flex-direction: row;
  gap: 20rpx;
  margin-bottom: 24rpx;
}

.od-rider-metric {
  flex: 1;
  background: #f7f7f7;
  border-radius: 16rpx;
  padding: 20rpx 16rpx;
  text-align: center;
}

.od-rider-metric--accent {
  background: #fff5f0;
}

.od-rider-metric-val {
  display: block;
  font-size: 30rpx;
  font-weight: 600;
  color: #222;
  line-height: 1.3;
}

.od-rider-metric-val--lg {
  font-size: 44rpx;
  font-weight: 700;
  color: #ff5117;
}

.od-rider-metric-key {
  display: block;
  margin-top: 8rpx;
  font-size: 22rpx;
  color: #999;
}

.od-rider-contact {
  display: flex;
  flex-direction: row;
  align-items: center;
  justify-content: space-between;
  padding: 20rpx 0 8rpx;
  border-top: 1rpx solid #f0f0f0;
}

.od-rider-contact-info {
  flex: 1;
  min-width: 0;
}

.od-rider-contact-label {
  display: block;
  font-size: 22rpx;
  color: #999;
}

.od-rider-contact-name {
  display: block;
  margin-top: 4rpx;
  font-size: 30rpx;
  font-weight: 600;
  color: #222;
}

.od-rider-contact-phone {
  display: block;
  margin-top: 4rpx;
  font-size: 24rpx;
  color: #666;
}

.od-rider-call-btn {
  flex-shrink: 0;
  padding: 14rpx 28rpx;
  border-radius: 999rpx;
  background: #ff5117;
  color: #fff;
  font-size: 26rpx;
  line-height: 1.3;
}

.od-rider-sync-hint {
  display: block;
  margin-top: 12rpx;
  font-size: 22rpx;
  color: #bbb;
  text-align: right;
}

.od-card {
  background: #fff;
  border-radius: 20rpx;
  padding: 24rpx 22rpx 20rpx;
  margin-bottom: 20rpx;
  box-shadow: 0 2rpx 16rpx rgba(0, 0, 0, 0.04);
}

.od-card--status {
  padding: 28rpx 22rpx;
}

.od-card--estimate {
  display: flex;
  flex-direction: row;
  align-items: center;
  justify-content: space-between;
  padding: 22rpx 22rpx;
}

.od-card--notice {
  padding: 20rpx 22rpx;
  background: linear-gradient(135deg, #fff8e6 0%, #ffecd2 100%);
  border: 1rpx solid #f0c674;
  box-shadow: none;
}

.od-notice-text {
  font-size: 26rpx;
  font-weight: 600;
  color: #b8860b;
  line-height: 1.45;
}

.od-card-head {
  display: flex;
  align-items: center;
  justify-content: space-between;
  margin-bottom: 20rpx;
}

.od-card-head--line {
  padding-bottom: 20rpx;
  margin-bottom: 8rpx;
  border-bottom: 1rpx solid #f0f0f0;
}

.od-card-title {
  font-size: 26rpx;
  font-weight: 400;
  color: #999;
}

.od-status-pill {
  font-size: 24rpx;
  font-weight: 600;
  color: #e10606;
  padding: 6rpx 16rpx;
  background: #fff5f3;
  border-radius: 20rpx;
  border: 1rpx solid rgba(225, 6, 6, 0.2);
}

.od-kv-list {
  padding-top: 4rpx;
}

.od-kv-row {
  display: flex;
  align-items: flex-start;
  justify-content: space-between;
  padding: 18rpx 0;
  border-bottom: 1rpx solid #f5f5f5;
}

.od-kv-row--last,
.od-kv-row:last-child {
  border-bottom: none;
  padding-bottom: 0;
}

.od-kv-row--addr {
  align-items: flex-start;
}

.od-kv-k {
  flex-shrink: 0;
  width: 140rpx;
  font-size: 28rpx;
  font-weight: 400;
  color: #999;
}

.od-kv-v {
  flex: 1;
  min-width: 0;
  font-size: 28rpx;
  font-weight: 400;
  color: #333;
  text-align: right;
  word-break: break-all;
  line-height: 1.45;
}

.od-kv-v--strong {
  font-weight: 600;
  color: #222;
}

.od-kv-v--price {
  color: #222;
  font-weight: 500;
}

.od-kv-v--mono {
  font-size: 26rpx;
  font-weight: 400;
  color: #666;
}

.od-batch {
  padding: 16rpx 0 8rpx;
}

.od-chevron {
  flex-shrink: 0;
  margin-left: 8rpx;
  font-size: 32rpx;
  color: #ccc;
  font-weight: 300;
}

.od-bottom-spacer {
  height: calc(160rpx + env(safe-area-inset-bottom));
}

.od-status-title {
  display: block;
  font-size: 40rpx;
  font-weight: 700;
  color: #222;
  line-height: 1.35;
  text-align: center;
}

.od-status-badge {
  display: block;
  text-align: center;
  font-size: 28rpx;
  font-weight: 600;
  line-height: 1.4;
  margin-bottom: 12rpx;
}
.od-status-badge--done {
  color: #2e9e5b;
}
.od-status-num {
  display: block;
  text-align: center;
  font-size: 72rpx;
  font-weight: 700;
  color: #222;
  line-height: 1.2;
}

.od-status-sub {
  display: block;
  margin-top: 12rpx;
  font-size: 28rpx;
  color: #888;
  line-height: 1.45;
  text-align: center;
}

.order-remind {
  padding: 0;
}


/* 底部按钮 */
.od-btn {
  flex: 1;
  min-width: 0;
  height: 88rpx;
  line-height: 88rpx;
  text-align: center;
  border-radius: 44rpx;
  font-size: 30rpx;
  font-weight: 700;
  margin: 0 8rpx;
  box-sizing: border-box;
}

.od-btn--primary {
  color: #fff;
  background: linear-gradient(to right, #ff5117, #f0331a, #e10606, #d30606);
}

.od-btn--primary.disabled {
  color: #fff;
  background: #c8c8c8;
  opacity: 1;
}

.od-btn--ghost {
  color: #666;
  background: #f5f5f5;
  border: 1rpx solid #e0e0e0;
}

.od-btn--outline {
  color: #e10606;
  background: #fff;
  border: 1rpx solid #e10606;
}

.dish-meta{
    margin-top: 8rpx;
    color: #8d8d8d;
    font-size: 24rpx;
    font-weight: 400;
    line-height: 1.25;
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
}
.dish-qty{
    margin-top: 8rpx;
    color: #b7b7b7;
    font-weight: 400;
    font-size: 26rpx;
}
.estimated-finish-title {
	font-size: 26rpx;
	color: #999;
	font-weight: 400;
}
.estimated-finish-value {
	font-size: 28rpx;
	color: #e10606;
	font-weight: 600;
}
.foot-deta image{
    width: 130rpx;
    height: 130rpx;
    border-radius: 10rpx;
}
.foot-deta{
    display: flex;
    align-items: center;
    justify-content: space-between;
    min-height: 130rpx;
    margin: 0;
    padding: 18rpx 0;
    border-bottom: 1rpx solid #f1f1f1;
}
.foot-deta-last{
    border-bottom: none;
}
.foot-deta--combo:active{
    background-color: #fafafa;
}
.dish-meta--combo{
    color: #e10606;
}
.dish-thumb-wrap{
    flex-shrink: 0;
}
.foot-name{
    flex: 1;
    display: flex;
    flex-direction: column;
    justify-content: center;
    padding: 0 14rpx;
    min-width: 0;
}
.dish-name{
    font-size: 28rpx !important;
    font-weight: 600;
    color: #222;
    line-height: 1.35;
    display: -webkit-box;
    -webkit-box-orient: vertical;
    -webkit-line-clamp: 2;
    text-overflow: ellipsis;
    overflow: hidden;
}
.dish-combo-tag{
    display: inline-block;
    margin-left: 8rpx;
    padding: 0 8rpx;
    font-size: 20rpx;
    color: #e10606;
    border: 1rpx solid #e10606;
    border-radius: 6rpx;
    vertical-align: middle;
}
.dish-price-col{
    width: 110rpx;
    display: flex;
    flex-direction: column;
    align-items: flex-end;
    justify-content: center;
}
.foot-total{
    min-width: 0;
    text-align: right;
    font-weight: 500;
    font-size: 28rpx;
    color: #222;
    line-height: 1.2;
}
.total-list{
    width: 100%;
}
.total-item{
    display: flex;
    align-items: center;
    justify-content: space-between;
    padding: 14rpx 0;
}
.total-left{
    color: #666;
    font-size: 28rpx;
    font-weight: 400;
}
.total-right{
    color: #222;
    font-size: 28rpx;
    font-weight: 500;
}
.total-right.od-price {
    color: #222;
    font-weight: 500;
}
.total-amount {
    font-size: 30rpx;
    font-weight: 600;
    color: #222;
}
.total-final-row .total-left {
    font-weight: 500;
    color: #333;
}
.total-coupon-row .total-left {
    font-weight: 400;
    color: #666;
}
.total-coupon-row.order-coupon-section {
    margin-top: 8rpx;
    padding-top: 8rpx;
    border-top: 1rpx solid #f0f0f0;
}

.total-view .order-coupon-section .coupon-arrow,
.total-coupon-row .coupon-arrow {
    font-size: 26rpx;
    color: #999;
    display: flex;
    align-items: center;
    justify-content: flex-end;
    flex: 1;
    min-width: 0;
    margin-left: 16rpx;
    text-align: right;
}
.total-view .order-coupon-section .selected-coupon {
    color: #e10606;
    font-weight: 600;
    margin-left: 0;
}
.total-view .order-coupon-section .coupon-count {
    color: #999;
    font-size: 24rpx;
    margin-left: 4rpx;
}
.night-ninefold-tip {
    margin: 12rpx 0 8rpx;
    padding: 16rpx 20rpx;
    background: linear-gradient(135deg, #f0f4ff 0%, #e8eeff 100%);
    border-radius: 12rpx;
    border: 1rpx solid rgba(79, 110, 200, 0.2);
}
.fee-detail-hint {
    margin: -4rpx 0 8rpx;
    padding: 0 4rpx;
}
.fee-detail-hint-text {
    font-size: 22rpx;
    color: #999;
    line-height: 1.4;
}
.night-ninefold-tip-text {
    font-size: 24rpx;
    color: #4a5a8c;
    line-height: 1.5;
}
.total-item .price-discount-value {
    color: #eb5941;
    font-weight: 500;
}
.total-final-row{
    border-top: 1rpx dashed #eee;
    margin-top: 8rpx;
    padding-top: 16rpx;
}

.payment-method-block {
    margin-top: 20rpx;
    padding-top: 4rpx;
}
.payment-method-title {
    font-size: 26rpx;
    font-weight: 400;
    color: #999;
    margin-bottom: 16rpx;
}
.payment-method-row {
    display: flex;
    gap: 20rpx;
}
.payment-chip {
    flex: 1;
    text-align: center;
    padding: 20rpx 12rpx;
    border-radius: 12rpx;
    font-size: 28rpx;
    color: #666;
    background: #f5f5f5;
    border: 2rpx solid transparent;
}
.payment-chip-active {
    color: #fff;
    font-weight: 600;
    background: linear-gradient(to right, #ff5117, #f0331a, #e10606);
    border-color: #e10606;
}
.payment-chip-disabled {
    opacity: 0.45;
}
.payment-balance-text {
    font-size: 24rpx;
    font-weight: 500;
}
.payment-recharge-link {
	color: #e74c3c;
	font-weight: 600;
	text-decoration: underline;
	margin-left: 4rpx;
}
.payment-balance-tip {
    margin-top: 12rpx;
    font-size: 24rpx;
    color: #c45656;
    line-height: 1.5;
}
.payment-offline-hint {
    font-size: 28rpx;
    color: #666;
    line-height: 1.6;
    padding: 8rpx 0;
}
.payment-offline-btn {
    margin-top: 20rpx;
    display: inline-block;
    padding: 16rpx 32rpx;
    border-radius: 12rpx;
    font-size: 28rpx;
    color: #fff;
    font-weight: 600;
    background: linear-gradient(to right, #ff5117, #e10606);
}
.offline-collect-mask {
    position: fixed;
    left: 0;
    right: 0;
    top: 0;
    bottom: 0;
    z-index: 1200;
    background: rgba(0, 0, 0, 0.55);
    display: flex;
    align-items: center;
    justify-content: center;
    padding: 40rpx;
}
.offline-collect-sheet {
    width: 100%;
    max-width: 620rpx;
    background: #fff;
    border-radius: 24rpx;
    padding: 36rpx 32rpx 28rpx;
    box-sizing: border-box;
}
.offline-collect-title {
    display: block;
    font-size: 34rpx;
    font-weight: 600;
    color: #222;
    text-align: center;
}
.offline-collect-sub {
    display: block;
    margin-top: 12rpx;
    font-size: 24rpx;
    color: #888;
    text-align: center;
    line-height: 1.5;
}
.offline-collect-qr {
    display: block;
    width: 480rpx;
    height: 480rpx;
    margin: 28rpx auto 0;
}
.offline-collect-loading,
.offline-collect-err {
    display: block;
    margin: 40rpx 0;
    text-align: center;
    font-size: 28rpx;
    color: #999;
}
.offline-collect-close {
    margin-top: 24rpx;
    text-align: center;
    font-size: 30rpx;
    color: #e10606;
    padding: 16rpx;
}

.od-btn--long-label {
    font-size: 26rpx;
    line-height: 1.35;
    padding-left: 20rpx;
    padding-right: 20rpx;
    white-space: normal;
    min-height: 72rpx;
    display: flex;
    align-items: center;
    justify-content: center;
    text-align: center;
}

.foot-section{
    position: fixed;
    bottom: 0;
    left: 0;
    right: 0;
    background: #fff;
    box-shadow: 0 -4rpx 24rpx rgba(0, 0, 0, 0.06);
    padding: 16rpx 16rpx calc(16rpx + env(safe-area-inset-bottom));
    z-index: 9;
    box-sizing: border-box;
}

.add-a-dish{
    display: flex;
    align-items: center;
    justify-content: center;
    flex-wrap: wrap;
    gap: 12rpx 0;
}

.order-group-tag {
    color: #e10606;
    font-size: 24rpx;
    padding: 6rpx 14rpx;
    background-color: #fff5f3;
    border-radius: 8rpx;
    font-weight: 500;
    border: 1rpx solid rgba(225, 6, 6, 0.15);
}


.coupon-section {
    display: flex;
    justify-content: space-between;
    align-items: center;
    padding: 20rpx 30rpx;
    margin-bottom: 20rpx;
    border-bottom: 1rpx solid #eaeaea;
}
.coupon-label {
    font-weight: bold;
    font-size: 34rpx;
    color: #c41e00;
}
.selected-coupon {
    color: #e10606;
    font-weight: 600;
    font-size: 28rpx;
    margin-left: 10rpx;
}
.coupon-count {
    color: #ff6633;
    font-size: 22rpx;
   
}
.coupon-arrow {
    font-size: 28rpx;
    color: #ff5117;
    font-weight: 600;
    display: flex;
    align-items: center;
}
.coupon-action {
    margin-left: 12rpx;
    font-size: 26rpx;
    color: #ff5117;
    opacity: 0.9;
}

/* 鎻愮ず妗嗘牱寮?*/
.toast {
    position: fixed;
    z-index: 1002;
    top: 50%;
    left: 50%;
    transform: translate(-50%, -50%);
}

.toast-content {
    display: inline-block;
    padding: 20rpx 30rpx;
    background-color: rgba(0, 0, 0, 0.7);
    color: #fff;
    border-radius: 10rpx;
    font-size: 30rpx;
}

.disabled {
    opacity: 0.6;
    pointer-events: none;
}


.combo-detail-mask {
    position: fixed;
    left: 0;
    right: 0;
    top: 0;
    bottom: 0;
    z-index: 1200;
    background: rgba(0, 0, 0, 0.45);
    display: flex;
    align-items: flex-end;
}
.combo-detail-sheet {
    width: 100%;
    max-height: 70vh;
    background: #fff;
    border-radius: 24rpx 24rpx 0 0;
    padding: 28rpx 32rpx calc(28rpx + env(safe-area-inset-bottom));
    box-sizing: border-box;
}
.combo-detail-head {
    display: flex;
    align-items: center;
    justify-content: space-between;
    margin-bottom: 12rpx;
}
.combo-detail-title {
    flex: 1;
    font-size: 32rpx;
    font-weight: 600;
    color: #222;
    padding-right: 16rpx;
}
.combo-detail-close {
    font-size: 44rpx;
    line-height: 1;
    color: #999;
    padding: 0 8rpx;
}
.combo-detail-summary {
    display: block;
    font-size: 24rpx;
    color: #888;
    line-height: 1.45;
    margin-bottom: 16rpx;
}
.combo-detail-scroll {
    max-height: 50vh;
}
.combo-detail-row {
    display: flex;
    align-items: center;
    justify-content: space-between;
    padding: 18rpx 0;
    border-bottom: 1rpx solid #f3f3f3;
}
.combo-detail-row:last-child {
    border-bottom: none;
}
.combo-detail-name {
    flex: 1;
    min-width: 0;
    font-size: 28rpx;
    font-weight: 600;
    color: #222;
    padding-right: 16rpx;
}
.combo-detail-qty {
    flex-shrink: 0;
    font-size: 26rpx;
    color: #999;
}
.combo-detail-empty {
    padding: 40rpx 0;
    text-align: center;
    font-size: 26rpx;
    color: #999;
}

</style>
    
