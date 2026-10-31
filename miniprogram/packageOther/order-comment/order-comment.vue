<template>
  <view class="comment-page">
    <view class="tip-card">
      <text class="tip-title">微信交易评价</text>
      <text class="tip-desc">已完成且通过微信支付的订单，可在此发起评价。评价由微信平台提供，商家回复请在微信公众平台「交易评价」中处理。</text>
    </view>

    <view class="section-head">
      <text class="section-title">待评价订单</text>
      <text class="section-link" @tap="onOpenCommentCenter">评价中心</text>
    </view>

    <scroll-view
      scroll-y
      class="order-scroll"
      :show-scrollbar="false"
      @scrolltolower="loadMore"
    >
      <view
        class="order-card"
        v-for="(item, index) in commentableOrders"
        :key="item.orderNo"
      >
        <view class="card-top">
          <text class="store-name">{{ item.shopName || defaultShopName }}</text>
          <text class="order-time">{{ formatTime(item.orderTime) }}</text>
        </view>
        <view class="card-mid">
          <text class="order-no">订单号 {{ item.orderNo }}</text>
          <text class="amount">¥{{ item.totalAmount.toFixed(2) }}</text>
        </view>
        <view class="card-foot">
          <text class="tag-wxpay">微信支付</text>
          <view
            class="btn-comment"
            hover-class="btn-comment-hover"
            @tap.stop="onComment(item)"
          >去评价</view>
        </view>
      </view>

      <view class="empty" v-if="!loading && commentableOrders.length === 0">
        <text class="empty-text">暂无待评价订单</text>
        <text class="empty-hint">完成订单后，微信支付的单据会出现在这里</text>
      </view>

      <view class="loading-more" v-if="loading">
        <text>加载中...</text>
      </view>
      <view class="no-more" v-if="!hasMore && commentableOrders.length > 0 && !loading">
        <text>没有更多了</text>
      </view>
    </scroll-view>
  </view>
</template>

<script>
import { requestUtil } from "../../utils/requestUtil.js";
import { getCurrentShopSnapshot } from "../../utils/shopContext.js";
import {
  canOrderBeCommented,
  openOrderComment,
  openGeneralCommentPage,
  isOpenBusinessViewSupported,
} from "../../utils/wxTransactionComment.js";

const app = getApp();

export default {
  data() {
    return {
      defaultShopName: "老肥油边王",
      orders: [],
      commentableOrders: [],
      currentPage: 1,
      pageSize: 10,
      hasMore: true,
      loading: false,
    };
  },
  onLoad() {
    this.refreshShopName();
    if (!isOpenBusinessViewSupported()) {
      wx.showToast({ title: "请升级微信后使用评价功能", icon: "none", duration: 3000 });
    }
    this.loadOrders(true);
  },
  onPullDownRefresh() {
    this.loadOrders(true).finally(() => wx.stopPullDownRefresh());
  },
  methods: {
    refreshShopName() {
      const s = getCurrentShopSnapshot();
      const n = s && s.name && String(s.name).trim();
      if (n) this.defaultShopName = n;
    },
    formatOrderRow(order) {
      const goodsAndPack = Number(order.sett_amount || 0);
      const serviceFee = Number(order.service_fee ?? 0);
      const discount = Number(order.discount_amount || 0);
      const payAmount = Math.max(
        0,
        Math.round((goodsAndPack + serviceFee - discount) * 100) / 100
      );
      return {
        id: order.id,
        orderNo: order.order_no,
        shopName: order.shop_name || order.shopName || "",
        orderTime: order.order_time,
        totalAmount: payAmount,
        transactionStatus: order.transac_status,
        orderRece: order.order_receiving || order.receiving,
        transaction_id: order.transaction_id,
        transac_status: order.transac_status,
        order_receiving: order.order_receiving,
        order_no: order.order_no,
      };
    },
    rebuildCommentableList() {
      this.commentableOrders = this.orders.filter((o) => canOrderBeCommented(o));
    },
    async loadOrders(refresh = false) {
      if (this.loading) return;
      if (refresh) {
        this.orders = [];
        this.currentPage = 1;
        this.hasMore = true;
      }
      if (!this.hasMore && !refresh) return;

      const openid = app.globalData.openid;
      if (!openid) {
        wx.showToast({ title: "请先登录", icon: "none" });
        return;
      }

      this.loading = true;
      try {
        const res = await requestUtil({
          url: "/order/history",
          method: "post",
          data: {
            openid,
            page: this.currentPage,
            pageSize: this.pageSize,
            status: "off_order",
          },
          showLoading: refresh,
        });

        if (res.code === 0 && res.hasHistory) {
          const rows = (res.orders || []).map((o) => this.formatOrderRow(o));
          this.orders = refresh ? rows : [...this.orders, ...rows];
          this.rebuildCommentableList();
          const total = Number(res.total);
          if (Number.isFinite(total) && total >= 0) {
            this.hasMore = this.orders.length < total;
          } else {
            this.hasMore = rows.length >= this.pageSize;
          }
          if (this.hasMore) this.currentPage += 1;
        } else if (refresh) {
          this.orders = [];
          this.commentableOrders = [];
          this.hasMore = false;
        }
      } catch (e) {
        console.error("load comment orders", e);
      } finally {
        this.loading = false;
      }
    },
    loadMore() {
      this.loadOrders(false);
    },
    formatTime(timestamp) {
      if (!timestamp) return "";
      let date;
      if (typeof timestamp === "string" && timestamp.indexOf(" ") !== -1) {
        date = new Date(timestamp.replace(" ", "T"));
      } else {
        date = new Date(timestamp);
      }
      if (isNaN(date.getTime())) return String(timestamp);
      const y = date.getFullYear();
      const m = String(date.getMonth() + 1).padStart(2, "0");
      const d = String(date.getDate()).padStart(2, "0");
      const h = String(date.getHours()).padStart(2, "0");
      const min = String(date.getMinutes()).padStart(2, "0");
      return `${y}-${m}-${d} ${h}:${min}`;
    },
    async onComment(order) {
      await openOrderComment(order);
    },
    onOpenCommentCenter() {
      openGeneralCommentPage();
    },
  },
};
</script>

<style scoped>
.comment-page {
  min-height: 100vh;
  background: #f5f5f5;
  display: flex;
  flex-direction: column;
}

.tip-card {
  margin: 24rpx 24rpx 0;
  padding: 24rpx 28rpx;
  background: #fff8f6;
  border-radius: 16rpx;
  border: 1rpx solid #ffe0d6;
}

.tip-title {
  display: block;
  font-size: 30rpx;
  font-weight: 600;
  color: #e10606;
  margin-bottom: 12rpx;
}

.tip-desc {
  display: block;
  font-size: 24rpx;
  color: #666;
  line-height: 1.55;
}

.section-head {
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: 28rpx 24rpx 16rpx;
}

.section-title {
  font-size: 30rpx;
  font-weight: 600;
  color: #333;
}

.section-link {
  font-size: 26rpx;
  color: #e10606;
}

.order-scroll {
  flex: 1;
  height: calc(100vh - 280rpx);
  padding: 0 24rpx 40rpx;
  box-sizing: border-box;
}

.order-card {
  background: #fff;
  border-radius: 20rpx;
  padding: 28rpx;
  margin-bottom: 20rpx;
  box-shadow: 0 2rpx 12rpx rgba(0, 0, 0, 0.04);
}

.card-top {
  display: flex;
  justify-content: space-between;
  align-items: center;
  margin-bottom: 16rpx;
}

.store-name {
  font-size: 30rpx;
  font-weight: 600;
  color: #333;
}

.order-time {
  font-size: 24rpx;
  color: #999;
}

.card-mid {
  display: flex;
  justify-content: space-between;
  align-items: center;
  margin-bottom: 20rpx;
}

.order-no {
  font-size: 24rpx;
  color: #888;
  flex: 1;
  margin-right: 16rpx;
}

.amount {
  font-size: 32rpx;
  font-weight: 600;
  color: #e10606;
}

.card-foot {
  display: flex;
  align-items: center;
  justify-content: space-between;
}

.tag-wxpay {
  font-size: 22rpx;
  color: #07c160;
  border: 1rpx solid #07c160;
  border-radius: 8rpx;
  padding: 4rpx 12rpx;
}

.btn-comment {
  padding: 12rpx 36rpx;
  font-size: 26rpx;
  color: #fff;
  background: linear-gradient(to right, #ff5117, #e10606);
  border-radius: 40rpx;
}

.btn-comment-hover {
  opacity: 0.85;
}

.empty {
  padding: 80rpx 40rpx;
  text-align: center;
}

.empty-text {
  display: block;
  font-size: 30rpx;
  color: #666;
  margin-bottom: 12rpx;
}

.empty-hint {
  display: block;
  font-size: 24rpx;
  color: #aaa;
}

.loading-more,
.no-more {
  text-align: center;
  padding: 24rpx;
  font-size: 24rpx;
  color: #999;
}
</style>
