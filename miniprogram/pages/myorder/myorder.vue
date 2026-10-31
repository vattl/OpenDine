<template>
  <view class="order-page">
   
    
    <!-- 订单状态筛选栏 -->
    <view class="filter-bar">
      <scroll-view scroll-x="true" class="filter-scroll" :show-scrollbar="false">
        <view class="filter-items">
          <view 
            class="filter-item" 
            :class="{ 'active': currentFilter === 'all' }"
            @click="changeFilter('all')"
          >
            全部
          </view>
          <view 
            class="filter-item" 
            :class="{ 'active': currentFilter === 'mis_order' }"
            @click="changeFilter('mis_order')"
          >
            待接单
          </view>
          <view 
            class="filter-item" 
            :class="{ 'active': currentFilter === 'rec_order' }"
            @click="changeFilter('rec_order')"
          >
            已接单
          </view>
          <view 
            class="filter-item" 
            :class="{ 'active': currentFilter === 'off_order' }"
            @click="changeFilter('off_order')"
          >
            已完成
          </view>
          
        </view>
      </scroll-view>
    </view>
    
    <!-- 订单列表内容区域 -->
    <view class="order-content">
      <scroll-view 
        scroll-y="true" 
        class="order-scroll" 
        enhanced 
        :show-scrollbar="false"
        @scrolltolower="loadMoreOrders"
      >
        <!-- 订单列表 - 卡片式布局 -->
        <view class="order-list">
          <view 
            class="order-card" 
            v-for="(order, index) in filteredOrders" 
            :key="order.id"
            @click="navigateToDetail(order)"
          >
            <!-- 卡片头部 - 包含店名和订单状态 -->
            <view class="card-header">
              <view class="store-name">{{ getOrderStoreName(order) }}</view>
              <view class="order-status" 
                :class="{
                  'pending': isUnpaidOrder(order),
                  'processing': isProcessingOrder(order),
                  'completed': isPaidCompletedOrder(order),
                  'cancelled': isCancelledOrder(order)
                }"
              >
                {{ getStatusText(order.transactionStatus,order.orderRece) }}
              </view>
            </view>
            
            <!-- 卡片主体 - 主要信息 -->
            <view class="card-body">
              <view class="order-info-row">
                <view class="info-item">
                  <text class="info-icon">🍽️</text>
                  <text class="info-text">{{
                    order.dineInOrTakeOut === '堂食'
                      ? '堂食'
                      : order.dineInOrTakeOut === '外卖'
                        ? '外卖'
                        : '打包'
                  }}</text>
                </view>
                <view class="info-item">
                  <text class="info-icon">🕒</text>
                  <text class="info-text">{{ formatTime(order.orderTime) }}</text>
                </view>
              </view>
              
              <!-- 简要商品信息 -->
              <view class="order-goods">
                <view class="goods-item" v-for="(goods, gIndex) in order.orderDetails" :key="gIndex" v-if="gIndex < 2">
                  <text>{{ goods.name }} x{{ goods.quantity }}</text>
                </view>
                <view class="goods-more" v-if="order.orderDetails.length > 2">
                  <text>... 共{{ order.orderDetails.length }}件商品</text>
                </view>
              </view>
              
              <!-- 金额信息：实付=原价-优惠，原价已含新年服务费时展示“含服务费” -->
              <view class="order-amount">
                <text>合计</text>
                <text class="amount-tag" v-if="order.serviceFee > 0">含服务费</text>
                <text class="amount-value">¥{{ order.totalAmount.toFixed(2) }}</text>
              </view>
            </view>
            
            <!-- 卡片底部 - 操作按钮（用 view+catchtap 阻止冒泡，避免触发卡片跳转详情） -->
            <view class="card-footer" @tap.stop>
              <view class="order-actions">
                <view 
                  class="action-btn" 
                  hover-class="action-btn-hover"
                  v-if="isUnpaidOrder(order) && order.dineInOrTakeOut !== '堂食'"
                  @tap.stop="cancelOrder(order, index)"
                >
                  取消订单
                </view>
                <view 
                  class="action-btn" 
                  hover-class="action-btn-hover"
                  v-if="canShowCommentBtn(order)"
                  @tap.stop="goComment(order)"
                >
                  去评价
                </view>
                <view 
                  class="action-btn primary" 
                  hover-class="action-btn-hover"
                  v-if="isPaidCompletedOrder(order)"
                  @tap.stop="reorder(order)"
                >
                  再次购买
                </view>
                <view 
                  class="action-btn" 
                  hover-class="action-btn-hover"
                  v-if="isProcessingOrder(order)"
                  @tap.stop="contactMerchant(order.id)"
                >
                  联系商家
                </view>
              </view>
            </view>
          </view>
        </view>
        
        <!-- 空状态 -->
        <view class="empty-state" v-if="filteredOrders.length === 0 && !loading">
          <image :src="staticUrl('images/empty_order.png')" mode="widthFix" class="empty-img"></image>
          <view class="empty-text">暂无相关订单</view>
          
        </view>
        

        <!-- 加载更多 -->
        <view class="loading-more" v-if="loading">
          <view class="loading-spinner"></view>
          <view class="loading-text">加载中...</view>
        </view>
        
        <!-- 没有更多数据 -->
        <view class="no-more" v-if="!hasMore && filteredOrders.length > 0 && !loading">
          没有更多数据了
        </view>
        
        <!-- 底部留白 -->
        <view class="bottom-space"></view>
      </scroll-view>
    </view>
    
    <!-- 已移除订单详情弹窗 -->
    
    <global-activity-popup ref="globalActivityPopup" />

    <!-- 取消订单确认弹窗（契约：POST /order/cancel 传 order_no、openid） -->
    <view class="confirm-modal" v-if="showCancelConfirm">
      <view class="confirm-mask" @tap="closeCancelConfirm"></view>
      <view class="confirm-content" @tap.stop>
        <view class="confirm-title">取消订单</view>
        <view class="confirm-message">确定要取消该订单吗？</view>
        <view class="confirm-input">
          <textarea 
            placeholder="请输入取消原因（选填）" 
            v-model="cancelReason"
            maxlength="50"
          ></textarea>
        </view>
        <view class="confirm-buttons">
          <view class="confirm-btn cancel" @tap="closeCancelConfirm">取消</view>
          <view class="confirm-btn confirm" @tap="confirmCancelOrder">确认取消</view>
        </view>
      </view>
    </view>
  </view>
</template>

<script>
import { getBaseUrl, requestUtil } from "../../utils/requestUtil.js";
import { getCurrentShopSnapshot } from "../../utils/shopContext.js";
import { staticUrl } from "../../utils/staticAssetUrl.js";
import {
  canOrderBeCommented,
  openOrderComment,
} from "../../utils/wxTransactionComment.js";

const app = getApp();

export default {
  data() {
    return {
      baseUrl: getBaseUrl(),
      orderListStoreLabel: "老肥油边王",
      shopNameById: {},
      orders: [],               // 所有订单数据
      filteredOrders: [],       // 筛选后的订单
      currentFilter: 'all',     // 当前筛选条件（与文档 status 一致：all/mis_order/rec_order/off_order）
      currentPage: 1,           // 当前页码，从 1 开始（与文档分页约定一致）
      pageSize: 10,             // 每页条数
      hasMore: true,
      loading: false,
      showCancelConfirm: false,
      cancelReason: '',
      cancelOrderId: null,
      cancelOrderNo: '',        // 取消订单时传 order_no（与文档约定一致）
      cancelOrderIndex: -1
    };
  },
  
  onLoad() {
    this.refreshOrderListStoreLabel();
    this.loadShopNameMap();
    // 页面加载时获取订单数据
    this.loadOrders();
  },
  async onShow() {
    if (typeof app.guardToQueueIfReview === "function") {
      const redirected = await app.guardToQueueIfReview();
      if (redirected) return;
    }
    this.refreshOrderListStoreLabel();
  },
  
  methods: {
    staticUrl,
    refreshOrderListStoreLabel() {
      const s = getCurrentShopSnapshot();
      const n = (s && s.name && String(s.name).trim()) || "";
      this.orderListStoreLabel = n ? `${n}` : "老肥油边王";
    },
    async loadShopNameMap() {
      try {
        const res = await requestUtil({
          url: "/shop/list",
          method: "get",
          showLoading: false
        });
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
      } catch (e) {
        // 门店名称映射获取失败时使用订单内字段与默认店名兜底
      }
    },
    getOrderStoreName(order) {
      if (!order) return this.orderListStoreLabel;
      const orderName = order.shopName ? String(order.shopName).trim() : "";
      if (orderName) return orderName;
      const id = Number(order.shopId);
      if (Number.isFinite(id) && id > 0 && this.shopNameById[id]) {
        return this.shopNameById[id];
      }
      return this.orderListStoreLabel;
    },
    // 加载订单数据 - 与文档约定一致：支持 page、pageSize、status
    async loadOrders(refresh = false) {
      if (this.loading) return;

      if (refresh) {
        this.orders = [];
        this.currentPage = 1;
        this.hasMore = true;
      }

      if (!this.hasMore && !refresh) return;

      this.loading = true;

      try {
        const openid = app.globalData.openid;
        if (!openid) {
          wx.showToast({ title: '请先登录', icon: 'none' });
          this.loading = false;
          return;
        }

        const res = await requestUtil({
          url: "/order/history",
          data: {
            openid,
            page: this.currentPage,
            pageSize: this.pageSize,
            status: this.currentFilter === 'all' ? 'all' : this.currentFilter
          },
          method: "post"
        });

        if (res.code === 0 && res.hasHistory) {
          const formattedOrders = (res.orders || []).map(order => this.formatOrderData(order));
          if (refresh) {
            this.orders = formattedOrders;
          } else {
            this.orders = [...this.orders, ...formattedOrders];
          }
          this.filterOrders();
          const total = res.total != null ? res.total : res.orderCount;
          this.hasMore = this.orders.length < (total || 0);
          if (formattedOrders.length >= this.pageSize) {
            this.currentPage += 1; // 下一页，供下次 loadMore 使用
          }
        } else {
          if (refresh) {
            this.orders = [];
            this.filterOrders();
          }
          if (res.msg) {
            wx.showToast({ title: res.msg, icon: 'none' });
          }
        }
      } catch (error) {
        console.error('获取订单失败:', error);
        wx.showToast({ title: '获取订单失败，请重试', icon: 'none' });
      } finally {
        this.loading = false;
      }
    },
    
    // 格式化订单数据 - sett_amount=商品+打包，实付=sett_amount+服务费-优惠
    formatOrderData(order) {
      const goodsAndPack = Number(order.sett_amount || 0);
      const serviceFee = Number(order.service_fee ?? 0);
      const discount = Number(order.discount_amount || 0);
      const payAmount = Math.max(0, Math.round((goodsAndPack + serviceFee - discount) * 100) / 100);
      return {
        id: order.id,
        shopId: order.shop_id != null ? Number(order.shop_id) : null,
        shopName: order.shop_name || order.shopName || "",
        orderNo: order.order_no,
        dineInOrTakeOut: order.dineInOrTakeOut,
        transactionStatus: order.transac_status,
        orderTime: order.order_time,
        payTime: order.pay_time,
        tableNumber: order.table_number,
        totalAmount: payAmount, // 实付 = 商品+打包+服务费-优惠
        serviceFee,
        orderDetails: order.orderDetails || [],
        orderRece: order.order_receiving || order.receiving,
        transaction_id: order.transaction_id,
        transac_status: order.transac_status,
        order_receiving: order.order_receiving,
        order_no: order.order_no,
      };
    },

    canShowCommentBtn(order) {
      return canOrderBeCommented(order);
    },

    async goComment(order) {
      await openOrderComment(order);
    },
    
	
    // 未支付订单（可取消）：后端 transac_status 为 unsettled，或前端 transactionStatus 为 pending
    isUnpaidOrder(order) {
      const s = order.transactionStatus || '';
      return s === 'unsettled' || s === 'pending';
    },
    // 已支付进行中（联系商家）：transac_status 为 success 且 待接单/已接单
    isProcessingOrder(order) {
      const s = order.transactionStatus || '';
      const rec = order.orderRece || '';
      return s === 'success' && (rec === 'mis_order' || rec === 'rec_order');
    },
    // 已支付且已完成：后端 success 且 order_receiving 为 off_order，或前端 completed
    isPaidCompletedOrder(order) {
      const s = order.transactionStatus || '';
      const rec = order.orderRece || '';
      return (s === 'success' && rec === 'off_order') || s === 'completed';
    },
    // 已取消
    isCancelledOrder(order) {
      const s = order.transactionStatus || '';
      return s === 'cancelled';
    },

    // 筛选订单
    filterOrders() {
      if (this.currentFilter === 'all') {
        this.filteredOrders = [...this.orders];
      } else{
        this.filteredOrders = this.orders.filter(order => order.orderRece === this.currentFilter);
      }
    },
    
    // 切换筛选条件
    changeFilter(filter) {
      if (this.currentFilter === filter) return;
      
      this.currentFilter = filter;
      this.loadOrders(true); // 重新加载数据
    },
    
    // 加载更多订单
    loadMoreOrders() {
      if (!this.loading && this.hasMore) {
        this.loadOrders();
      }
    },
    
    // 新增：跳转到订单详情页
    navigateToDetail(order) {
		
      wx.navigateTo({
        url: `/packageOther/order-details/details?order_no=${order.orderNo}`
      });
    },
    
    cancelOrder(order, index = -1) {
      this.cancelOrderId = order.id;
      this.cancelOrderNo = order.orderNo || '';
      this.cancelOrderIndex = index;
      this.cancelReason = '';
      this.showCancelConfirm = true;
    },

    closeCancelConfirm() {
      this.showCancelConfirm = false;
    },

    /** 确认取消订单（契约：POST /order/cancel 请求体 { order_no, openid }） */
    async confirmCancelOrder() {
      const orderNo = this.cancelOrderNo && this.cancelOrderNo.trim();
      if (!orderNo) {
        wx.showToast({ title: '订单号无效', icon: 'none' });
        return;
      }
      const openid = app.globalData.openid;
      if (!openid) {
        wx.showToast({ title: '请先登录', icon: 'none' });
        return;
      }

      this.loading = true;
      try {
        const res = await requestUtil({
          url: "/order/cancel",
          data: {
            order_no: orderNo,
            openid
          },
          method: "post"
        });
        
        if (res.code === 0) {
          wx.showToast({
            title: '订单已取消',
            icon: 'success'
          });
          
          // 更新本地订单状态
          if (this.cancelOrderIndex !== -1 && this.cancelOrderIndex < this.filteredOrders.length) {
            this.$set(this.filteredOrders[this.cancelOrderIndex], 'transactionStatus', 'cancelled');
          }
          
          this.showCancelConfirm = false;
        } else {
          wx.showToast({
            title: res.msg || '取消订单失败',
            icon: 'none'
          });
        }
      } catch (error) {
        console.error('取消订单失败:', error);
        wx.showToast({
          title: '取消订单失败，请重试',
          icon: 'none'
        });
      } finally {
        this.loading = false;
      }
    },
    
    // 再次购买：点餐页为 tabBar，用 reLaunch 关闭当前栈并打开点餐页（也可用 switchTab）
    reorder(order) {
      const goodsParam = encodeURIComponent(JSON.stringify(order.dineInOrTakeOut));
      wx.reLaunch({
        url: `/pages/home-page/page?dineInOrTakeOut=${order.dineInOrTakeOut}`
      });
    },
    
    contactMerchant(orderId) {
      wx.showModal({
        title: '联系商家',
        content: '是否拨打商家电话：15975017545',
        confirmText: '拨打',
        cancelText: '取消',
        success(res) {
          if (res.confirm) {
            wx.makePhoneCall({
              phoneNumber: '15975017545'
            });
          }
        }
      });
    },
    
    goToHome() {
      wx.switchTab({
        url: '/pages/home-page/page'
      });
    },
    
    // iOS 仅支持 yyyy-MM-dd、yyyy-MM-ddTHH:mm:ss 等，后端可能返回 yyyy-MM-dd HH:mm:ss，需归一化
    formatTime(timestamp) {
      if (!timestamp) return '';
      let date;
      if (typeof timestamp === 'string' && timestamp.indexOf(' ') !== -1) {
        date = new Date(timestamp.replace(' ', 'T'));
      } else {
        date = new Date(timestamp);
      }
      if (isNaN(date.getTime())) return String(timestamp);
      const year = date.getFullYear();
      const month = (date.getMonth() + 1).toString().padStart(2, '0');
      const day = date.getDate().toString().padStart(2, '0');
      const hours = date.getHours().toString().padStart(2, '0');
      const minutes = date.getMinutes().toString().padStart(2, '0');
      return `${year}-${month}-${day} ${hours}:${minutes}`;
    },
    
    getStatusText(status, reve) {
      const statusMap = {
        'mis_order': '待接单',
        'rec_order': '已接单',
        'off_order': '已完成',
        'unsettled': '未支付',
        'cancelled': '已取消',
        'success': '已支付'
      };
      if (status === 'cancelled') {
        return statusMap[status] || '已取消';
      }
      if (reve === 'off_order') {
        return statusMap[reve] || '已完成';
      }
      const receText = statusMap[reve] || '';
      const statusText = statusMap[status] || '';
      if (receText && statusText) {
        return `${receText}【${statusText}】`;
      }
      return receText || statusText || '未知状态';
    },
    
    getSpicyText(spicy) {
      switch(spicy) {
        case 'mild':
          return '微辣';
        case 'none':
          return '不辣';
        default:
          return '默认辣度';
      }
    }
  },
  
  onPullDownRefresh() {
    this.loadOrders(true).then(() => {
      wx.stopPullDownRefresh();
    });
  },
  
  onReachBottom() {
    this.loadMoreOrders();
  }
};
</script>

<style scoped>
/* 基础样式 */
.order-page {
  background-color: #f5f5f5;
  min-height: 100vh;
  
}



.nav-title {
  font-size: 36rpx;
  font-weight: bold;
  color: #333;
}

/* 筛选栏样式 */
.filter-bar {
  background-color: #fff;
  padding: 20rpx 0;
  top: 120rpx;
  left: 0;
  right: 0;
  z-index: 998;
  border-bottom: 1px solid #eee;
}

.filter-scroll {
  width: 100%;
  white-space: nowrap;
}

.filter-items {
  display: inline-flex;
  padding: 0 20rpx;
}

.filter-item {
  padding: 10rpx 30rpx;
  margin: 0 10rpx;
  font-size: 28rpx;
  border-radius: 30rpx;
  color: #666;
}

.filter-item.active {
  background-color: #ec0606;
  color: #fff;
  font-weight: bold;
}



.order-scroll {
  min-height: calc(100vh - 200rpx);
  padding-bottom: 40rpx;
}

/* 订单列表 - 卡片式布局 */
.order-list {
  padding: 20rpx;
  display: flex;
  flex-direction: column;
  gap: 20rpx;
}

/* 订单卡片样式 */
.order-card {
  background-color: #fff;
  border-radius: 20rpx;
  padding: 30rpx;
  box-shadow: 0 2rpx 10rpx rgba(0, 0, 0, 0.05);
  display: flex;
  flex-direction: column;
  gap: 20rpx;
  /* 增加点击反馈效果 */
  transition: transform 0.2s, box-shadow 0.2s;
}

/* 点击卡片时的效果 */
.order-card:active {
  transform: scale(0.99);
  box-shadow: 0 1rpx 5rpx rgba(0, 0, 0, 0.03);
}

/* 卡片头部 */
.card-header {
  display: flex;
  justify-content: space-between;
  align-items: center;
}

.store-name {
  font-size: 32rpx;
  font-weight: bold;
  color: #333;
}

.order-status {
  padding: 5rpx 15rpx;
  border-radius: 20rpx;
  font-size: 24rpx;
  font-weight: 500;
}

/* 卡片主体 */
.card-body {
  display: flex;
  flex-direction: column;
  gap: 20rpx;
}

.order-info-row {
  display: flex;
  justify-content: space-between;
  color: #666;
  font-size: 26rpx;
}

.info-item {
  display: flex;
  align-items: center;
  gap: 10rpx;
}

.info-icon {
  font-size: 28rpx;
}

.order-goods {
  padding: 10rpx 0;
  border-top: 1px dashed #eee;
  border-bottom: 1px dashed #eee;
  font-size: 26rpx;
  color: #666;
  display: flex;
  flex-direction: column;
  gap: 10rpx;
}

.goods-more {
  color: #999;
  font-size: 24rpx;
}

.order-amount {
  display: flex;
  align-items: center;
  justify-content: flex-end;
  gap: 10rpx;
  font-size: 28rpx;
  color: #333;
}

.amount-tag {
  font-size: 22rpx;
  color: #b8860b;
  background: #fff8e6;
  padding: 2rpx 10rpx;
  border-radius: 6rpx;
}

.amount-value {
  color: #f5222d;
  font-weight: bold;
}

/* 卡片底部 */
.card-footer {
  display: flex;
  justify-content: flex-start; /* 按钮左对齐，因为移除了右侧的查看详情按钮 */
  align-items: center;
  padding-top: 10rpx;
}

.order-actions {
  display: flex;
  gap: 15rpx;
}

.action-btn {
  padding: 8rpx 20rpx;
  font-size: 24rpx;
  border-radius: 20rpx;
  background-color: #f5f5f5;
  color: #666;
  border: none;
}

.action-btn.primary {
  background-color: #f7d45f;
  color: #333;
}

.action-btn-hover {
  opacity: 0.85;
}

/* 状态样式 */
.order-status.pending {
  background-color: #fff7e6;
  color: #faad14;
}

.order-status.processing {
  background-color: #e6f7ff;
  color: #1890ff;
}

.order-status.completed {
  background-color: #f6ffed;
  color: #52c41a;
}

.order-status.cancelled {
  background-color: #fef0f0;
  color: #f5222d;
}

/* 空状态样式 */
.empty-state {
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  padding: 100rpx 0;
}

.empty-img {
  width: 200rpx;
  height: 200rpx;
  margin-bottom: 40rpx;
}

.empty-text {
  font-size: 32rpx;
  color: #666;
  margin-bottom: 40rpx;
}

.empty-btn {
  background-color: #f7d45f;
  color: #333;
  font-size: 28rpx;
  padding: 20rpx 60rpx;
  border-radius: 50rpx;
}

/* 加载更多样式 */
.loading-more {
  display: flex;
  flex-direction: column;
  align-items: center;
  padding: 40rpx 0;
}

.loading-spinner {
  width: 40rpx;
  height: 40rpx;
  border: 4rpx solid #eee;
  border-top-color: #f7d45f;
  border-radius: 50%;
  animation: spin 1s linear infinite;
  margin-bottom: 15rpx;
}

.loading-text {
  font-size: 26rpx;
  color: #999;
}

/* 没有更多数据 */
.no-more {
  text-align: center;
  padding: 30rpx 0;
  font-size: 26rpx;
  color: #999;
}

/* 底部留白 */
.bottom-space {
  height: 40rpx;
}

/* 动画 */
@keyframes spin {
  to { transform: rotate(360deg); }
}

/* 取消订单确认弹窗 */
.confirm-modal {
  position: fixed;
  top: 0;
  left: 0;
  right: 0;
  bottom: 0;
  z-index: 1000;
}
.confirm-mask {
  position: absolute;
  top: 0;
  left: 0;
  right: 0;
  bottom: 0;
  background: rgba(0, 0, 0, 0.5);
}
.confirm-content {
  position: absolute;
  left: 50%;
  top: 50%;
  transform: translate(-50%, -50%);
  width: 85%;
  max-width: 600rpx;
  background: #fff;
  border-radius: 20rpx;
  padding: 40rpx 30rpx;
  box-sizing: border-box;
}
.confirm-title {
  font-size: 34rpx;
  font-weight: bold;
  text-align: center;
  margin-bottom: 20rpx;
  color: #333;
}
.confirm-message {
  font-size: 28rpx;
  color: #666;
  text-align: center;
  margin-bottom: 24rpx;
}
.confirm-input textarea {
  width: 100%;
  min-height: 120rpx;
  padding: 16rpx;
  box-sizing: border-box;
  border: 1rpx solid #eee;
  border-radius: 12rpx;
  font-size: 26rpx;
}
.confirm-buttons {
  display: flex;
  justify-content: space-between;
  gap: 24rpx;
  margin-top: 32rpx;
}
.confirm-btn {
  flex: 1;
  height: 80rpx;
  line-height: 80rpx;
  text-align: center;
  font-size: 30rpx;
  border-radius: 12rpx;
}
.confirm-btn.cancel {
  background: #f5f5f5;
  color: #666;
}
.confirm-btn.confirm {
  background: #ec0606;
  color: #fff;
}
.confirm-btn.confirm:active {
  opacity: 0.9;
}
</style>
    