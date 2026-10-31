<template>
  <view class="tab-bar">
    <view 
      class="tab-item" 
      v-for="(item, index) in list" 
      :key="index"
      @click="switchTab(item.pagePath, index)"
    >
      <text 
        class="tab-text"
        :class="{ 'tab-text-selected': currentIndex === index }"
      >
        {{ item.text }}
      </text>
    </view>
  </view>
</template>

<script>
export default {
  data() {
    return {
      currentIndex: 0,
      list: [
        { "pagePath": "pages/saoma/saoma", "text": "首页" },
        { "pagePath": "pages/home-page/page", "text": "点餐" },
        { "pagePath": "pages/myorder/myorder", "text": "订单" },
        { "pagePath": "pages/my/my", "text": "我的" }
      ]
    };
  },
  onShow() {
    // 同步当前页面选中状态
    const pages = getCurrentPages();
    const currentPage = pages[pages.length - 1].route;
    const index = this.list.findIndex(item => item.pagePath === currentPage);
    if (index !== -1) this.currentIndex = index;
  },
  methods: {
    switchTab(url, index) {
      if (this.currentIndex === index) return;
      uni.switchTab({ url });
    }
  }
};
</script>

<style scoped>
.tab-bar {
  display: flex;
  height: 100rpx;
  width: 100%;
  position: fixed;
  bottom: 0;
  background-color: #fff;
  border-top: 1px solid #eee;
}

.tab-item {
  flex: 1;
  display: flex;
  align-items: center;
  justify-content: center;
}

/* 文字样式 - 可自由设置外边距 */
.tab-text {
  font-size: 24rpx;
  color: #999;
  /* 文字外边距设置 */
  margin: 0 10rpx; /* 左右各10rpx外边距 */
  padding: 5rpx 0; /* 上下内边距（可模拟外边距效果） */
}

.tab-text-selected {
  color: #000;
  font-weight: bold;
  /* 选中状态可单独设置外边距 */
  margin: 0 8rpx;
}
</style>
