<template>
  <view class="coupon-page">
    <!-- 导航栏：保持原有功能，样式适配统一风格 -->
    <view class="nav-bar">
      <view class="nav-back" @click="goBack">
        <image :src="staticUrl('images/back.png')" mode="widthFix" class="back-icon"></image>
      </view>
      <view class="nav-title">优惠券中心</view>
      <view class="nav-empty"></view>
    </view>

    <!-- 优惠券列表：完全统一为目标样式 + 严谨的类型判断 -->
    <view class="coupon-list" v-if="(couponList || []).length > 0">
      <view class="coupon-item" v-for="(item, index) in couponList" :key="index" :class="{ disabled: item.stock === 0 && item.stock !== -1 }">
        <!-- 优惠券主体 -->
        <view class="coupon-main">
          <!-- 左侧：优惠券名称 + 有效期 + 左上角类型标签 -->
          <view class="coupon-left">
            <view class="coupon-type-tag">{{ getCouponTypeName(item.coupon_type) }}</view>
            <view class="coupon-name">{{ item.coupon_name || '未知优惠券' }}</view>
            <view class="coupon-validity">有效期{{ formatDate(item.start_time) }}-{{ formatDate(item.end_time) }}</view>
            <!-- 库存显示（适配目标样式位置） -->
            <view class="coupon-stock" v-if="item.stock > 0" style="font-size: 22rpx; opacity: 0.8; margin-top: 8rpx;">
              剩余{{ item.stock }}张
            </view>
            <view class="coupon-stock" v-if="item.stock === -1" style="font-size: 22rpx; opacity: 0.8; margin-top: 8rpx;">
              无限量
            </view>
          </view>

          <!-- 中间：满减/折扣/立减金额（优化类型判断逻辑） -->
          <view class="coupon-middle">
            <!-- 折扣券：显示X.X折，处理异常值 -->
            <template v-if="item.coupon_type === 'discount'">
              <view class="coupon-value">
                {{ formatDiscountValue(item.discount_value) }}折
              </view>
              <view class="coupon-desc" v-if="item.min_amount > 0">满{{ item.min_amount || 0 }}元可用</view>
              <view class="coupon-desc" v-else>无门槛折扣</view>
            </template>

            <!-- 满减券：显示¥XX，必须满XX元 -->
            <template v-else-if="item.coupon_type === 'full_reduction'">
              <view class="coupon-value">¥{{ formatAmountValue(item.discount_value) }}</view>
              <view class="coupon-desc">满{{ item.min_amount || 0 }}元减</view>
            </template>

            <!-- 立减券：显示¥XX，无门槛 -->
            <template v-else-if="item.coupon_type === 'direct_reduction'">
              <view class="coupon-value">¥{{ formatAmountValue(item.discount_value) }}</view>
              <view class="coupon-desc">无门槛立减</view>
            </template>

            <!-- 未知类型：显示默认文案 -->
            <template v-else>
              <view class="coupon-value">¥0</view>
              <view class="coupon-desc">未知优惠券类型</view>
            </template>
			<!-- 立即领取按钮（适配目标样式位置和风格） -->
			<view class="use-btn" @click="receiveCoupon(item.id)" v-if="!item.has_received && item.stock !== 0">
			  立即领取
			</view>
			<!-- 已领取/已抢完状态标签（适配目标样式） -->
			<view class="status-tag" v-if="item.has_received">已领取</view>
			<view class="status-tag expired" v-if="item.stock === 0 && !item.has_received">已抢完</view>
          </view>

          
        </view>

        <!-- 规则展开区域（完全统一目标样式） -->
        <view class="coupon-rule">
          <view class="rule-content" :class="{ expanded: getShowRuleStatus(index) }">
            {{ item.description || '暂无详细规则' }}
          </view>
          <view class="toggle-triangle" @click="toggleRule(index)">
            <image class="triangle-down" :class="{ active: getShowRuleStatus(index) }" :src="staticUrl('images/triangle-down.png')" mode="widthFix"></image>
          </view>
        </view>
      </view>
    </view>

    <!-- 空状态：样式完全统一 -->
    <view class="empty-state" v-if="(couponList || []).length === 0 && !isLoading">
      <image :src="staticUrl('images/empty-coupon.png')" mode="widthFix" class="empty-img"></image>
      <view class="empty-text">暂无可领取的优惠券</view>
    </view>

    <!-- 加载中：样式完全统一 -->
    <view class="loading-state" v-if="isLoading">
      <text>加载中...</text>
    </view>
  </view>
</template>

<script>
import { getBaseUrl, requestUtil } from "../../utils/requestUtil.js";
import { staticUrl } from "../../utils/staticAssetUrl.js";
import { requestSceneSubscribe } from "../../utils/wechatSubscribeManager.js";
const app = getApp();

export default {
  data() {
    return {
      baseUrl: getBaseUrl(),
      couponList: [], // 可领取优惠券列表
      isLoading: false,
      showRuleMap: {} // 规则展开状态
    };
  },
  onLoad() {
    if (!app.globalData.isLogin) {
      wx.showToast({
        title: "请先登录",
        icon: "none",
      });
      const pages = getCurrentPages();
      if (pages && pages.length > 1) {
        wx.navigateBack();
      } else {
        wx.switchTab({ url: "/pages/my/my" });
      }
      return;
    }
    this.getAvailableCoupons();
  },
  methods: {
    staticUrl,
    // 返回上一页
    goBack() {
      wx.navigateBack();
    },

    // 获取可领取优惠券列表
    async getAvailableCoupons() {
      this.isLoading = true;
      try {
        const res = await requestUtil({
          url: "/coupon/getAvailable",
          data: { openid: app.globalData.openid },
          method: "post",
        });
        if (res.code === 0) {
          this.showRuleMap = {};
          this.couponList = (res.data || []).map((coupon, index) => {
            this.showRuleMap[index] = false;
            // 确保优惠券类型字段存在
            return { 
              coupon_type: coupon.coupon_type || '',
              discount_value: coupon.discount_value || 0,
              min_amount: coupon.min_amount || 0,
              ...coupon 
            };
          });
        } else {
          wx.showToast({
            title: res.msg || "获取优惠券列表失败",
            icon: "none",
          });
        }
      } catch (e) {
        console.error("获取可领取优惠券失败:", e);
        wx.showToast({
          title: "网络异常，请重试",
          icon: "none",
        });
      } finally {
        this.isLoading = false;
      }
    },

    // 格式化日期
    formatDate(timestamp) {
      if (!timestamp) return "";
      try {
        const date = new Date(timestamp);
        if (isNaN(date.getTime())) return "";
        return `${date.getFullYear()}-${(date.getMonth() + 1).toString().padStart(2, "0")}-${date.getDate().toString().padStart(2, "0")}`;
      } catch (error) {
        console.error('格式化日期出错:', error);
        return "";
      }
    },

    // 领取优惠券
    async receiveCoupon(couponId) {
      // 领券点击手势内智能决策订阅优惠券临期提醒并同步配额台账
      await requestSceneSubscribe("COUPON_EXPIRING", {
        openid: (app && app.globalData && app.globalData.openid) || wx.getStorageSync("openid"),
        showToast: false,
      });

      this.isLoading = true;
      try {
        const res = await requestUtil({
          url: "/coupon/receive",
          data: {
            openid: app.globalData.openid,
            coupon_id: couponId,
          },
          method: "post",
        });
        if (res.code === 0) {
          wx.showToast({
            title: "领取成功",
            icon: "success",
          });
          // 更新列表状态
          this.couponList = this.couponList.map((item) => {
            if (item.id === couponId) {
              item.has_received = true;
              // 如果是有限库存，领取后库存减1
              if (item.stock > 0) {
                item.stock--;
              }
            }
            return item;
          });
        } else {
          wx.showToast({
            title: res.msg || "领取失败",
            icon: "none",
          });
        }
      } catch (e) {
        console.error("领取优惠券失败:", e);
        wx.showToast({
          title: "网络异常，请重试",
          icon: "none",
        });
      } finally {
        this.isLoading = false;
      }
    },

    // 获取优惠券类型名称（和目标页面统一）
    getCouponTypeName(type) {
      const typeMap = {
        'full_reduction': '满减券',
        'discount': '折扣券',
        'direct_reduction': '立减券'
      };
      return typeMap[type] || '优惠券';
    },

    // 格式化折扣值（处理异常值，确保显示X.X格式）
    formatDiscountValue(value) {
      if (!value || isNaN(Number(value))) return '0.0';
      const num = Number(value) / 10;
      return num.toFixed(1);
    },

    // 格式化金额值（处理异常值，确保显示正常数字）
    formatAmountValue(value) {
      if (!value || isNaN(Number(value))) return '0';
      return Number(value).toString();
    },

    // 规则展开/收起相关（和目标页面统一）
    getShowRuleStatus(index) {
      return this.showRuleMap[index] !== undefined ? this.showRuleMap[index] : false;
    },

    toggleRule(index) {
      this.showRuleMap[index] = !this.getShowRuleStatus(index);
      this.$forceUpdate();
    }
  },
};
</script>

<style scoped>
/* 全局样式完全统一目标页面 */
.coupon-page {
  background-color: #f5f5f5;
  min-height: 100vh;
}

/* 导航栏：适配目标页面风格 */
.nav-bar {
  display: flex;
  align-items: center;
  padding: 20rpx 30rpx;
  background-color: #fff;
  border-bottom: 1rpx solid #eee;
}
.back-icon {
  width: 36rpx;
  height: 36rpx;
}
.nav-title {
  flex: 1;
  text-align: center;
  font-size: 32rpx;
  font-weight: bold;
  color: #333;
}
.nav-empty {
  width: 36rpx;
}

/* 优惠券列表：完全统一目标样式 */
.coupon-list {
  padding: 20rpx 30rpx;
  display: flex;
  flex-direction: column;
  gap: 20rpx;
}

/* 优惠券项容器：渐变背景统一 */
.coupon-item {
  background: linear-gradient(to right, #ff5117, #e10606);
  border-radius: 10rpx;
  color: #fff;
  overflow: hidden;
  position: relative;
  padding-bottom: 18rpx;
}
/* 已抢完状态样式统一 */
.coupon-item.disabled {
  background: linear-gradient(to right, #999, #666);
  opacity: 0.8;
}

/* 优惠券主体：布局统一 */
.coupon-main {
  display: flex;
  align-items: baseline;
  padding: 30rpx 30rpx 10rpx 30rpx;
  cursor: pointer;
}

/* 左侧：名称 + 有效期 + 左上角类型标签 - 样式完全统一 */
.coupon-left {
  display: flex;
  flex-direction: column;
  gap: 8rpx;
  position: relative;
  padding-top: 30rpx;
  flex: 1;
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

/* 中间：满减/折扣/立减 - 样式完全统一 */
.coupon-middle {
  margin-left: 13%;
  margin-bottom: 10rpx;
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

/* 右侧：空容器 - 保持布局一致 */
.coupon-right {
  margin-right: 20rpx;
}

/* 立即领取按钮：样式统一目标页面 */
.use-btn {
  margin-top: 15rpx;
  right: 30rpx;
  background-color: #fff;
  color: #e10606;
  font-size: 24rpx;
  padding: 10rpx 20rpx;
  border-radius: 20rpx;
  z-index: 1;
}
/* 已抢完/已领取状态标签：样式统一 */
.status-tag {
  margin-top: 15rpx;
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

/* 三角形样式：完全统一 */
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

/* 规则展开区域：完全统一目标样式 */
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
/* 展开后样式：统一自动换行 */
.rule-content.expanded {
  white-space: normal;
  overflow: visible;
  text-overflow: clip;
  min-height: 21px;
}

/* 空状态：完全统一目标样式 */
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
}

/* 加载中：完全统一目标样式 */
.loading-state {
  text-align: center;
  padding: 50rpx 0;
  font-size: 28rpx;
  color: #999;
}

/* 解决按钮默认样式冲突 */
button::after {
  border: none;
}
</style>