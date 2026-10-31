<template>
  <view class="unified-notify-root">
    <!-- 1. P0 / P1 置顶强提醒卡片（出餐取餐 / 排队叫号 / 退款结果） -->
    <view
      v-if="topBanner"
      class="unified-top-banner"
      :class="{
        'unified-top-banner--queue': topBanner.mode === 'queue',
        'unified-top-banner--refund': topBanner.mode === 'refund',
      }"
    >
      <view class="unified-top-badge">{{ topBanner.badge }}</view>
      <view class="unified-top-info" @click="handleTopBannerAction(true)">
        <view class="unified-top-title">{{ topBanner.title }}</view>
        <view class="unified-top-sub">{{ topBanner.subtitle }}</view>
      </view>
      <view class="unified-top-btn" @click.stop="handleTopBannerAction(true)">
        {{ topBanner.actionText || '知道了' }}
      </view>
    </view>

    <!-- 2. 结账确认页防打扰胶囊横幅（新优惠券到账降级展示，绝不打断支付） -->
    <view v-if="suppressCapsule" class="unified-suppress-capsule">
      <text class="unified-capsule-text">{{ suppressCapsule.text }}</text>
      <view class="unified-capsule-btn" @click.stop="handleSuppressCapsuleClick">
        重选优惠
      </view>
    </view>

    <!-- 3. P1 天降优惠券礼盒弹窗（单模态优先级 P1，支持 800ms 批量聚合） -->
    <view class="unified-coupon-modal-mask" v-if="couponModal" @touchmove.stop.prevent>
      <view class="unified-coupon-modal-card" @click.stop>
        <view class="unified-coupon-tag">{{ couponModal.tag }}</view>
        <view class="unified-coupon-title">{{ couponModal.title }}</view>
        <view class="unified-coupon-sub">{{ couponModal.subtitle }}</view>
        <scroll-view scroll-y class="unified-coupon-list">
          <view
            class="unified-coupon-ticket"
            v-for="(c, idx) in (couponModal.coupons || [])"
            :key="idx"
          >
            <view class="unified-ticket-amount">
              <text class="unified-ticket-symbol" v-if="c.coupon_type !== 'discount'">¥</text>
              <text class="unified-ticket-num">{{ formatTicketMainValue(c) }}</text>
            </view>
            <view class="unified-ticket-meta">
              <view class="unified-ticket-name">{{ c.coupon_name || '专属优惠券' }}</view>
              <view class="unified-ticket-desc">
                {{ c.discount_text || formatTicketSubRule(c) }}
              </view>
            </view>
          </view>
        </scroll-view>
        <view class="unified-coupon-cta" @click="handleCloseCouponModal(true)">
          立即去点餐使用
        </view>
        <view class="unified-coupon-dismiss" @click="handleCloseCouponModal(false)">
          收下并放入卡包
        </view>
      </view>
    </view>

    <!-- 4. P2 营销活动海报轮播弹窗（纳入单模态互斥队列 P2，在 P1 关闭 500ms 后自动唤醒） -->
    <view class="activity-modal" v-if="visible && !couponModal">
      <view class="modal-mask" @click="close"></view>
      <view class="activity-container">
        <scroll-view
          class="activity-scroll"
          scroll-x
          scroll-with-animation="false"
          @scroll="onScroll"
          @touchstart="onTouchStart"
          @touchend="onTouchEnd"
          :scroll-left="scrollLeft"
        >
          <view class="activity-track" :style="{ width: `${popupList.length * 100}%` }">
            <view
              class="activity-slide"
              v-for="(item, index) in popupList"
              :key="index"
              :style="{ width: `${100 / popupList.length}%` }"
            >
              <view class="activity-content">
                <image
                  class="activity-img"
                  :src="imageUrl(item)"
                  mode="widthFix"
                  :lazy-load="index > 0"
                  @click="goToActivityPage(item.image_url)"
                ></image>
                <view class="page-indicator">
                  <view
                    class="indicator-dot"
                    v-for="(dot, dotIndex) in popupList.length"
                    :key="dotIndex"
                    :class="{ active: currentPage === dotIndex }"
                  ></view>
                </view>
              </view>
            </view>
          </view>
        </scroll-view>
        <view class="close-btn" @click="close">
          <image :src="staticUrl('tab/guanbi.png')" mode="widthFix"></image>
        </view>
      </view>
    </view>

    <!-- 5. P2 优惠券临期底部非阻断悬浮 SnackBar -->
    <view v-if="expiringSnackbar" class="unified-expiring-snackbar">
      <text class="unified-snack-text">{{ expiringSnackbar.text }}</text>
      <view class="unified-snack-btn" @click.stop="handleExpiringSnackbarClick">
        去使用
      </view>
    </view>
  </view>
</template>

<script>
import { staticUrl } from "../utils/staticAssetUrl.js";
import {
  appendActivityShowRecords,
  buildPopupImageUrl,
  fetchActivityPopupList,
  getCachedUnshownActivities,
  invalidateActivityPopupCache,
  markActivityPopupFetched,
  preloadPopupImages,
  shouldRefetchActivityPopup,
  shouldTryActivityPopupOnRoute,
} from "../utils/globalActivityPopup.js";
import { getTopPageRoute, isRouteStillTop } from "../utils/pageLifecycle.js";
import {
  dismissCouponModal,
  dismissExpiringSnackbar,
  dismissSuppressCapsule,
  dismissTopBanner,
  releaseModalSlot,
  requestModalSlot,
  subscribeActivityPopupInvalidate,
  subscribeUnifiedUiState,
} from "../utils/unifiedNotifyCenter.js";

const app = getApp();

export default {
  name: "GlobalActivityPopup",
  data() {
    return {
      visible: false,
      popupList: [],
      currentPage: 0,
      scrollLeft: 0,
      startX: 0,
      slideWidth: 0,
      isScrolling: false,
      bannerTimer: null,
      _tryShowPending: false,
      _tryShowRoute: "",
      topBanner: null,
      suppressCapsule: null,
      couponModal: null,
      expiringSnackbar: null,
      _unsubUiState: null,
      _unsubActivityInvalidate: null,
    };
  },
  mounted() {
    this._unsubUiState = subscribeUnifiedUiState((snap) => {
      if (!snap) return;
      this.topBanner = snap.topBanner;
      this.suppressCapsule = snap.suppressCapsule;
      this.couponModal = snap.couponModal;
      this.expiringSnackbar = snap.expiringSnackbar;
    });
    this._unsubActivityInvalidate = subscribeActivityPopupInvalidate(() => {
      invalidateActivityPopupCache(app);
      const route = getTopPageRoute();
      if (shouldTryActivityPopupOnRoute(route)) {
        this.tryShow({ forceRefresh: true });
      }
    });
  },
  beforeDestroy() {
    this.stopBannerTimer();
    this._tryShowRoute = "";
    if (typeof this._unsubUiState === "function") {
      this._unsubUiState();
      this._unsubUiState = null;
    }
    if (typeof this._unsubActivityInvalidate === "function") {
      this._unsubActivityInvalidate();
      this._unsubActivityInvalidate = null;
    }
  },
  methods: {
    staticUrl,
    imageUrl(image) {
      return buildPopupImageUrl(image);
    },
    formatTicketMainValue(c) {
      if (!c) return "券";
      if (c.coupon_type === "discount") {
        const v = Number(c.discount_value || 0);
        return v > 0 ? `${(v / 10).toFixed(1)}折` : "折扣";
      }
      return c.discount_value != null ? String(c.discount_value) : "0";
    },
    formatTicketSubRule(c) {
      if (!c) return "到店点餐可用";
      const min = Number(c.min_amount || 0);
      return min > 0 ? `满 ${min} 元可用` : "无门槛直接抵扣";
    },
    handleCloseCouponModal(navigateToMenu) {
      dismissCouponModal(navigateToMenu);
    },
    handleSuppressCapsuleClick() {
      dismissSuppressCapsule(true);
    },
    handleTopBannerAction(navigateAction) {
      dismissTopBanner(navigateAction);
    },
    handleExpiringSnackbarClick() {
      dismissExpiringSnackbar(true);
    },
    /** 缓存秒开 + 后台刷新（全局 mixin onShow、各页 onLoad 或实时通道 ACTIVITY_POPUP_CHANGED 均可调用） */
    async tryShow(options = {}) {
      const forceRefresh = !!(options && options.forceRefresh);
      if ((this.visible && !forceRefresh) || this._tryShowPending) return;
      this._tryShowPending = true;
      this._tryShowRoute = getTopPageRoute();
      try {
        if (!forceRefresh) {
          const cached = getCachedUnshownActivities(app);
          if (cached.length > 0 && this._canUpdatePopup()) {
            this.enqueueActivityModal(cached);
          }
        }
        if (forceRefresh || shouldRefetchActivityPopup()) {
          markActivityPopupFetched();
          const { unshown } = await fetchActivityPopupList(app);
          if (!this._canUpdatePopup()) return;
          if (unshown.length > 0) {
            this.enqueueActivityModal(unshown);
          } else if (forceRefresh) {
            this.visible = false;
            this.popupList = [];
            releaseModalSlot("ACTIVITY_POPUP");
          }
        }
      } finally {
        this._tryShowPending = false;
      }
    },
    _canUpdatePopup() {
      if (!this._tryShowRoute) return true;
      return isRouteStillTop(this._tryShowRoute);
    },
    /**
     * 申请单模态队列 P2 槽位展示活动海报，若当前正在展示 P1 优惠券弹窗，则在 P1 关闭 500ms 后自动弹出
     */
    enqueueActivityModal(list) {
      if (!this._canUpdatePopup()) return;
      if (!list || !list.length) return;
      requestModalSlot({
        priorityWeight: 2,
        type: "ACTIVITY_POPUP",
        id: list.map((i) => i.id).join(","),
        onAcquire: () => {
          this.openWithList(list);
        },
      });
    },
    openWithList(list) {
      if (!this._canUpdatePopup()) {
        releaseModalSlot("ACTIVITY_POPUP");
        return;
      }
      if (!list || !list.length) {
        releaseModalSlot("ACTIVITY_POPUP");
        return;
      }
      this.popupList = list;
      this.visible = true;
      preloadPopupImages(list);
      appendActivityShowRecords(app, list);
      this.$nextTick(() => {
        this.initSlider();
        this.startBannerTimer();
      });
    },
    close() {
      this.visible = false;
      this.stopBannerTimer();
      if (this.popupList.length > 0 && app.globalData.activity_record) {
        app.globalData.activity_record.type = "close";
      }
      releaseModalSlot("ACTIVITY_POPUP");
    },
    onScroll(e) {
      if (this.isScrolling) return;
      const scrollLeft = e.detail.scrollLeft;
      if (this.slideWidth) {
        this.currentPage = Math.round(scrollLeft / this.slideWidth);
      }
    },
    onTouchStart(e) {
      this.startX = e.touches[0].clientX;
      this.isScrolling = true;
      this.stopBannerTimer();
    },
    onTouchEnd(e) {
      if (!this.slideWidth) return;
      const endX = e.changedTouches[0].clientX;
      const diffX = endX - this.startX;
      const minSwipeDistance = 20;
      if (Math.abs(diffX) > minSwipeDistance) {
        diffX > 0 ? this.prevSlide() : this.nextSlide();
      } else {
        this.scrollLeft = this.currentPage * this.slideWidth;
      }
      this.isScrolling = false;
      this.startBannerTimer();
    },
    prevSlide() {
      if (this.currentPage > 0) {
        this.currentPage--;
        this.scrollLeft = this.currentPage * this.slideWidth;
        this.startBannerTimer();
      }
    },
    nextSlide() {
      if (this.currentPage < this.popupList.length - 1) {
        this.currentPage++;
        this.scrollLeft = this.currentPage * this.slideWidth;
        this.startBannerTimer();
      }
    },
    initSlider() {
      this.$nextTick(() => {
        const query = wx.createSelectorQuery().in(this);
        query
          .select(".activity-scroll")
          .boundingClientRect((rect) => {
            if (rect) {
              this.slideWidth = rect.width;
              this.scrollLeft = 0;
              this.currentPage = 0;
              this.startBannerTimer();
            }
          })
          .exec();
      });
    },
    startBannerTimer() {
      if (this.bannerTimer) clearInterval(this.bannerTimer);
      this.bannerTimer = setInterval(() => {
        if (!this.isScrolling && this.popupList.length > 1 && this.slideWidth) {
          const nextPage = (this.currentPage + 1) % this.popupList.length;
          const scrollInterval = setInterval(() => {
            const targetScrollLeft = nextPage * this.slideWidth;
            const distance = targetScrollLeft - this.scrollLeft;
            if (Math.abs(distance) <= 10) {
              this.scrollLeft = targetScrollLeft;
              this.currentPage = nextPage;
              clearInterval(scrollInterval);
            } else {
              this.scrollLeft += distance > 0 ? 10 : -10;
            }
          }, 30);
        }
      }, 3000);
    },
    stopBannerTimer() {
      if (this.bannerTimer) {
        clearInterval(this.bannerTimer);
        this.bannerTimer = null;
      }
    },
    goToActivityPage(url) {
      if (!url) return;
      this.close();
      wx.navigateTo({
        url,
        fail: () => {
          wx.showToast({ title: "页面不存在", icon: "none" });
        },
      });
    },
  },
};
</script>

<style scoped>
/* 1. P0/P1 顶部强提醒卡片 */
.unified-top-banner {
  position: fixed;
  top: 24rpx;
  left: 24rpx;
  right: 24rpx;
  background: linear-gradient(135deg, #059669, #10b981);
  color: #ffffff;
  border-radius: 28rpx;
  padding: 24rpx 28rpx;
  box-shadow: 0 16rpx 44rpx rgba(16, 185, 129, 0.38);
  z-index: 10020;
  display: flex;
  align-items: center;
  justify-content: space-between;
}
.unified-top-banner--queue {
  background: linear-gradient(135deg, #ea580c, #dc2626);
  box-shadow: 0 16rpx 44rpx rgba(220, 38, 38, 0.4);
}
.unified-top-banner--refund {
  background: linear-gradient(135deg, #2563eb, #1d4ed8);
  box-shadow: 0 16rpx 44rpx rgba(37, 99, 235, 0.35);
}
.unified-top-badge {
  background: rgba(255, 255, 255, 0.22);
  padding: 12rpx 20rpx;
  border-radius: 18rpx;
  font-size: 32rpx;
  font-weight: 800;
  margin-right: 20rpx;
  flex-shrink: 0;
}
.unified-top-info {
  flex: 1;
  overflow: hidden;
}
.unified-top-title {
  font-size: 28rpx;
  font-weight: 700;
}
.unified-top-sub {
  font-size: 22rpx;
  opacity: 0.92;
  margin-top: 4rpx;
}
.unified-top-btn {
  background: #ffffff;
  color: #0f172a;
  padding: 12rpx 22rpx;
  border-radius: 999rpx;
  font-size: 22rpx;
  font-weight: 700;
  margin-left: 16rpx;
  flex-shrink: 0;
}

/* 2. 结账确认页防打扰胶囊横幅 */
.unified-suppress-capsule {
  position: fixed;
  top: 24rpx;
  left: 24rpx;
  right: 24rpx;
  background: linear-gradient(90deg, #fffbeb, #fef3c7);
  border: 2rpx solid #f59e0b;
  color: #92400e;
  border-radius: 999rpx;
  padding: 18rpx 28rpx;
  box-shadow: 0 12rpx 32rpx rgba(245, 158, 11, 0.22);
  z-index: 10015;
  display: flex;
  align-items: center;
  justify-content: space-between;
}
.unified-capsule-text {
  font-size: 24rpx;
  font-weight: 600;
  flex: 1;
  margin-right: 16rpx;
}
.unified-capsule-btn {
  background: #d97706;
  color: #ffffff;
  border-radius: 999rpx;
  padding: 8rpx 20rpx;
  font-size: 22rpx;
  font-weight: 700;
  flex-shrink: 0;
}

/* 3. P1 天降优惠券礼盒弹窗 */
.unified-coupon-modal-mask {
  position: fixed;
  top: 0;
  left: 0;
  right: 0;
  bottom: 0;
  background-color: rgba(15, 23, 42, 0.72);
  z-index: 10010;
  display: flex;
  align-items: center;
  justify-content: center;
  padding: 48rpx;
}
.unified-coupon-modal-card {
  width: 100%;
  max-width: 600rpx;
  background: linear-gradient(180deg, #ef4444 0%, #b91c1c 100%);
  border-radius: 40rpx;
  padding: 40rpx 32rpx 32rpx;
  color: #ffffff;
  text-align: center;
  box-shadow: 0 32rpx 80rpx rgba(185, 28, 28, 0.5);
  border: 4rpx solid #fcd34d;
}
.unified-coupon-tag {
  display: inline-block;
  background: #fde68a;
  color: #92400e;
  font-size: 22rpx;
  font-weight: 800;
  padding: 6rpx 22rpx;
  border-radius: 999rpx;
  margin-bottom: 16rpx;
}
.unified-coupon-title {
  font-size: 36rpx;
  font-weight: 800;
}
.unified-coupon-sub {
  font-size: 24rpx;
  color: #fecaca;
  margin-top: 8rpx;
  margin-bottom: 24rpx;
}
.unified-coupon-list {
  max-height: 420rpx;
  margin-bottom: 16rpx;
}
.unified-coupon-ticket {
  background: #ffffff;
  color: #1f2937;
  border-radius: 24rpx;
  padding: 22rpx 26rpx;
  margin-bottom: 18rpx;
  display: flex;
  align-items: center;
  justify-content: space-between;
  text-align: left;
}
.unified-ticket-amount {
  color: #dc2626;
  font-weight: 800;
  min-width: 140rpx;
}
.unified-ticket-symbol {
  font-size: 24rpx;
}
.unified-ticket-num {
  font-size: 44rpx;
}
.unified-ticket-meta {
  flex: 1;
}
.unified-ticket-name {
  font-size: 28rpx;
  font-weight: 700;
}
.unified-ticket-desc {
  font-size: 22rpx;
  color: #6b7280;
  margin-top: 4rpx;
}
.unified-coupon-cta {
  width: 100%;
  background: linear-gradient(90deg, #fde047, #f59e0b);
  color: #78350f;
  padding: 22rpx 0;
  border-radius: 999rpx;
  font-size: 28rpx;
  font-weight: 800;
  margin-top: 12rpx;
}
.unified-coupon-dismiss {
  margin-top: 20rpx;
  color: #fee2e2;
  font-size: 24rpx;
}

/* 4. 原有 P2 营销活动海报轮播样式 */
.activity-modal {
  position: fixed;
  top: 0;
  left: 0;
  right: 0;
  bottom: 0;
  z-index: 9999;
  display: flex;
  justify-content: center;
  align-items: center;
  padding: 40rpx;
}

.modal-mask {
  position: absolute;
  top: 0;
  left: 0;
  right: 0;
  bottom: 0;
  background-color: rgba(0, 0, 0, 0.7);
}

.activity-container {
  position: relative;
  width: 450rpx;
}

.activity-scroll {
  width: 100%;
  height: 100%;
  white-space: nowrap;
  overflow: hidden;
  border-radius: 20rpx;
}

.activity-track {
  display: flex;
  height: 100%;
  transition: transform 0.5s cubic-bezier(0.34, 1.56, 0.64, 1);
}

.activity-slide {
  flex-shrink: 0;
  height: 100%;
  width: 100%;
  box-sizing: border-box;
}

.activity-content {
  width: 100%;
  height: 100%;
  position: relative;
  background-color: #fff;
  overflow: hidden;
}

.activity-img {
  width: 100%;
  height: calc(100% - 60rpx);
  display: block;
}

.page-indicator {
  position: absolute;
  bottom: 20rpx;
  left: 0;
  right: 0;
  display: flex;
  justify-content: center;
  gap: 10rpx;
  height: 40rpx;
  align-items: center;
}

.indicator-dot {
  width: 12rpx;
  height: 12rpx;
  border-radius: 50%;
  background-color: #ccc;
  transition: all 0.3s ease;
}

.indicator-dot.active {
  width: 30rpx;
  background-color: #ff5117;
  border-radius: 6rpx;
}

.close-btn {
  position: absolute;
  top: -60rpx;
  right: 0;
  width: 50rpx;
  height: 50rpx;
  z-index: 10;
}

.close-btn image {
  width: 100%;
  height: 100%;
}

/* 5. P2 底部临期优惠券 SnackBar */
.unified-expiring-snackbar {
  position: fixed;
  bottom: 128rpx;
  left: 24rpx;
  right: 24rpx;
  background: #1e293b;
  color: #f8fafc;
  border-radius: 24rpx;
  padding: 20rpx 26rpx;
  display: flex;
  align-items: center;
  justify-content: space-between;
  font-size: 24rpx;
  box-shadow: 0 16rpx 40rpx rgba(15, 23, 42, 0.35);
  z-index: 9990;
}
.unified-snack-text {
  flex: 1;
  margin-right: 16rpx;
}
.unified-snack-btn {
  background: #ef4444;
  color: #ffffff;
  border-radius: 999rpx;
  padding: 10rpx 22rpx;
  font-size: 22rpx;
  font-weight: 700;
  flex-shrink: 0;
}
</style>
