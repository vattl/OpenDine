<template>
  <view class="carousel-root">
    <view class="carousel-scroll-wrapper">
      <scroll-view
        v-if="topCarouselList && topCarouselList.length > 0"
        class="carousel-container top-carousel"
        scroll-x
        :show-scrollbar="false"
        scroll-with-animation
        scroll-animation-duration="500"
        :scroll-left="topScrollLeft"
        @scroll="onTopScroll"
        :style="{ height: '420rpx' }"
      >
        <view class="carousel-wrapper" :style="{ width: topCarouselInnerWidth }">
          <view
            class="img-wrapper"
            v-for="(item, index) in topCarouselList"
            :key="index"
            @click="handleCarouselClick(item)"
          >
            <image
              :src="carouselImageUrl(item, 750)"
              class="carousel-img"
              mode="cover"
              lazy-load
              @error="(e) => onImageError(e, index, 'top')"
            />
          </view>
        </view>
      </scroll-view>
    </view>
    <swiper
      v-if="bottomCarouselList && bottomCarouselList.length > 0"
      class="bottom-swiper"
      indicator-dots
      autoplay
      interval="3000"
      circular
      duration="500"
      :style="{ height: '150rpx', marginTop: '20rpx' }"
    >
      <swiper-item v-for="(item, index) in bottomCarouselList" :key="index">
        <view class="bottom-img-wrapper" @click="handleCarouselClick(item)">
          <image
            :src="getUrl(item.popup_image, 300)"
            class="bottom-carousel-img"
            mode="cover"
            lazy-load
            @error="(e) => onImageError(e, index, 'bottom')"
          />
        </view>
      </swiper-item>
    </swiper>
  </view>
</template>

<script>
import { requestUtil } from '../../../utils/requestUtil.js';
import { activityCarouselStorageKey } from '../../../utils/activityCarouselCache.js';
import {
  activityPopupImageUrl,
  IMAGE_Q_DETAIL,
  IMAGE_Q_LIST,
  preloadImages,
} from '../../../utils/imageUrl.js';

const app = getApp();

export default {
  data() {
    return {
      topCarouselList: null,
      bottomCarouselList: null,
      topScrollLeft: 0,
      topCurrentIndex: 0,
      topAutoTimer: null,
      topItemWidthPx: 0,
      winWidth: 375
    }
  },
  computed: {
    topCarouselInnerWidth() {
      if (!this.topCarouselList || this.topCarouselList.length === 0) return 'auto';
      const n = this.topCarouselList.length;
      const totalRpx = 20 + n * 320;
      const px = Math.ceil((totalRpx * this.winWidth) / 750);
      return px + 'px';
    }
  },
  created() {
    const win = wx.getWindowInfo();
    this.winWidth = win.windowWidth || 375;
    this.topItemWidthPx = Math.round((320 * this.winWidth) / 750);
    this.loadAllCarouselData();
  },
  beforeDestroy() {
    this.stopTopAutoScroll();
  },
  methods: {
    carouselImageUrl(item, q = IMAGE_Q_DETAIL) {
      return activityPopupImageUrl(item, q);
    },
    // 轮播图点击跳转：支持 link_url / url / image_url（外链用 webview，小程序路径用 navigateTo）
    handleCarouselClick(item) {
      const link = item && (item.link_url || item.url || item.image_url);
      if (!link || !String(link).trim()) return;
      const url = link.trim();
      if (url.startsWith('http://') || url.startsWith('https://')) {
        wx.setClipboardData({
          data: url,
          success: () => {
            wx.showToast({ title: '链接已复制，请在浏览器中打开', icon: 'none', duration: 2500 });
          }
        });
      } else {
        wx.navigateTo({ url });
      }
    },  
    async reloadCarouselData(force = false) {
      this.stopTopAutoScroll();
      this.topCarouselList = [];
      this.bottomCarouselList = [];
      this.topScrollLeft = 0;
      this.topCurrentIndex = 0;
      await this.loadAllCarouselData(force);
    },
    async loadAllCarouselData(force = false) {
      try {
        await Promise.all([
          this.fetchCarouselList('page_top', 'topCarouselList', 'topCarouselList', force),
          this.fetchCarouselList('page_hor', 'bottomCarouselList', 'bottomCarouselList', force)
        ]);
        this.$emit('swiperDataChange', {
          topCarouselList: this.topCarouselList,
          bottomCarouselList: this.bottomCarouselList,
          isEmpty: !(this.topCarouselList && this.topCarouselList.length) && !(this.bottomCarouselList && this.bottomCarouselList.length)
        });
        if (this.topCarouselList && this.topCarouselList.length >= 3) {
          this.startTopAutoScroll();
        }
        const topUrls = (this.topCarouselList || [])
          .slice(0, 2)
          .map((item) => this.carouselImageUrl(item, IMAGE_Q_DETAIL));
        const bottomUrls = (this.bottomCarouselList || [])
          .slice(0, 1)
          .map((item) => this.carouselImageUrl(item, IMAGE_Q_LIST));
        preloadImages([].concat(topUrls, bottomUrls).filter(Boolean), {
          max: 4,
          concurrency: 2,
        });
      } catch (e) {
        console.error('轮播数据加载异常', e);
      }
    },
    async fetchCarouselList(type, storageKey, dataKey, force = false) {
      const cacheKey = activityCarouselStorageKey(storageKey);
      if (!force) {
        const cached = app.getStorageWithExpiry(cacheKey);
        if (cached && cached.length > 0) {
          this[dataKey] = cached;
          return cached;
        }
      }
      try {
        const res = await requestUtil({
          url: '/activity/popupList',
          method: 'post',
          data: { type },
          showLoading: false,
        });
        if (res.code === 0 && res.activity && res.activity.length) {
          this[dataKey] = res.activity;
          app.setStorageWithExpiry(cacheKey, res.activity, 30);
        } else {
          this[dataKey] = [];
        }
      } catch (e) {
        this[dataKey] = [];
      }
      return this[dataKey];
    }, 
    onImageError(e, index, type) {
      if (type === 'top' && this.topCarouselList && this.topCarouselList[index]) {
        this.topCarouselList[index].imageUrl = "https://picsum.photos/300/400?random=999";
      } else if (this.bottomCarouselList && this.bottomCarouselList[index]) {
        this.bottomCarouselList[index].imageUrl = "https://picsum.photos/400/150?random=888";
      }
    },
    startTopAutoScroll() {
      this.stopTopAutoScroll();
      this.topAutoTimer = setInterval(() => {
        if (!this.topCarouselList || this.topCarouselList.length < 3) return;
        this.topCurrentIndex = (this.topCurrentIndex + 1) % this.topCarouselList.length;
        this.topScrollLeft = this.topCurrentIndex * this.topItemWidthPx;
      }, 2000);
    },
    stopTopAutoScroll() {
      if (this.topAutoTimer) {
        clearInterval(this.topAutoTimer);
        this.topAutoTimer = null;
      }
    },
    onTopScroll(e) {
      const left = e.detail.scrollLeft;
      if (this.topItemWidthPx > 0 && this.topCarouselList && this.topCarouselList.length) {
        const index = Math.round(left / this.topItemWidthPx);
        this.topCurrentIndex = Math.min(Math.max(0, index), this.topCarouselList.length - 1);
      }
    }
  }
}
</script>

<style scoped>
.carousel-root {
  width: 100vw;
  padding-bottom: 20rpx;
}
.carousel-scroll-wrapper {
  width: 100vw;
  overflow: visible;
  position: relative;
}
.carousel-container {
  width: 100vw;
  padding: 0;
  position: relative;
}
.carousel-wrapper {
  display: flex;
  height: 100%;
  align-items: center;
  padding: 0 10rpx;
  margin: 0;
  flex-shrink: 0;
  box-sizing: border-box;
}
.top-carousel {
  height: 420rpx;
  margin-top: 10rpx;
}
.top-carousel .img-wrapper {
  width: 300rpx;
  height: 400rpx;
  margin: 0 10rpx;
  position: relative;
  aspect-ratio: 3/4;
}
.top-carousel .carousel-img {
  position: absolute;
  top: 0;
  left: 0;
  width: 100%;
  height: 100%;
  border-radius: 25rpx;
  object-fit: cover;
}
.bottom-swiper {
  width: 100vw;
  padding: 0 20rpx;
  box-sizing: border-box;
}
.bottom-swiper .wx-swiper-item {
  width: 100%;
  height: 100%;
  display: flex;
  align-items: center;
  justify-content: flex-start;
}
.bottom-img-wrapper {
  width: 100%;
  height: 130rpx;
  position: relative;
}
.bottom-carousel-img {
  position: absolute;
  top: 0;
  left: 0;
  width: 100%;
  height: 100%;
  border-radius: 25rpx;
  object-fit: cover;
}
.bottom-swiper .swiper-pagination {
  bottom: 5rpx;
}
.bottom-swiper .swiper-pagination-bullet {
  width: 6rpx;
  height: 6rpx;
  background: #fff;
  opacity: 0.6;
}
.bottom-swiper .swiper-pagination-bullet-active {
  background: #ff6700;
  opacity: 1;
}
</style>