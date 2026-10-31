<template>
  <view class="page">
    <view class="head">
      <text class="title">选择门店</text>
      <text class="sub">请选择您要下单的营业门店</text>
    </view>
    <view class="list" v-if="shops.length">
      <view
        class="item"
        v-for="s in shops"
        :key="s.id"
        @click="onPick(s)"
      >
        <view class="item-main">
          <text class="name">{{ s.name || ("门店" + s.id) }}</text>
          <text class="addr" v-if="s.address">{{ s.address }}</text>
        </view>
        <text class="chev">›</text>
      </view>
    </view>
    <view class="empty" v-else-if="!loading">
      <text>暂无营业门店</text>
    </view>
    <view class="loading" v-if="loading">
      <text>加载中…</text>
    </view>
  </view>
</template>

<script>
import { requestUtil } from "../../utils/requestUtil.js";
import { setCurrentShop, sortShopsForDisplay, MENU_SHOP_MANUAL_KEY } from "../../utils/shopContext.js";

export default {
  data() {
    return {
      shops: [],
      loading: true,
      fromMenu: false,
      fromEntry: false,
    };
  },
  onLoad(options) {
    this.fromMenu = !!(options && options.from === "menu");
    this.fromEntry = !!(options && options.from === "entry");
    this.loadShops();
  },
  methods: {
    async loadShops() {
      this.loading = true;
      try {
        const res = await requestUtil({
          url: "/shop/list",
          method: "get",
          showLoading: true,
        });
        if (res && res.code === 0 && Array.isArray(res.list)) {
          this.shops = sortShopsForDisplay(res.list);
        } else {
          this.shops = [];
          if (res && res.msg) {
            wx.showToast({ title: res.msg, icon: "none" });
          }
        }
      } catch (e) {
        this.shops = [];
        wx.showToast({ title: "加载失败", icon: "none" });
      } finally {
        this.loading = false;
      }
    },
    onPick(shop) {
      setCurrentShop(shop);
      try {
        wx.setStorageSync("mp_menu_shop_bootstrap_v1", 1);
        wx.setStorageSync(MENU_SHOP_MANUAL_KEY, 1);
      } catch (e) {
        /* 忽略 */
      }
      if (this.fromMenu || this.fromEntry) {
        // 重新进入点餐页，走完整 onLoad/loadPageData，避免切店后菜单/营业态等仍用旧缓存
        wx.reLaunch({ url: "/pages/home-page/page?shop_picked=1" });
      } else {
        wx.switchTab({ url: "/pages/index/index" });
      }
    },
  },
};
</script>

<style scoped>
.page {
  min-height: 100vh;
  background: #fff5f2;
  padding: 32rpx 28rpx 48rpx;
  box-sizing: border-box;
}
.head {
  margin-bottom: 28rpx;
}
.title {
  display: block;
  font-size: 40rpx;
  font-weight: 600;
  color: #222;
}
.sub {
  display: block;
  margin-top: 12rpx;
  font-size: 26rpx;
  color: #888;
}
.list {
  background: #fff;
  border-radius: 20rpx;
  overflow: hidden;
  box-shadow: 0 4rpx 16rpx rgba(0, 0, 0, 0.06);
}
.item {
  display: flex;
  align-items: center;
  padding: 28rpx 24rpx;
  border-bottom: 1rpx solid #f0f0f0;
}
.item:last-child {
  border-bottom: none;
}
.item-main {
  flex: 1;
  min-width: 0;
}
.name {
  display: block;
  font-size: 32rpx;
  color: #333;
  font-weight: 500;
}
.addr {
  display: block;
  margin-top: 8rpx;
  font-size: 24rpx;
  color: #999;
  line-height: 1.4;
}
.chev {
  font-size: 40rpx;
  color: #ccc;
  margin-left: 16rpx;
}
.empty,
.loading {
  text-align: center;
  padding: 80rpx 24rpx;
  font-size: 28rpx;
  color: #999;
}
</style>
