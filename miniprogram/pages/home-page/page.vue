<template>
  <view class="page-container" :style="cssVars">
    <!-- 固定的顶部店名和消息通知区域 -->
    <view class="fixed-header">
      <view class="top-name">
        <view
          class="shop-entry"
          :class="{ 'shop-entry--switchable': canSwitchShop }"
          @click="onShopEntryTap"
        >
          <view class="shop-entry-top">
            <text class="shop-entry-title">{{ displayMenuShopTitle }}</text>
          </view>
          <view
            v-if="canSwitchShop"
            class="shop-switch-hint"
          >
            <text v-if="shopKmPrefix" class="shop-km-prefix">{{ shopKmPrefix }}</text>
            <text class="shop-switch-action">切换门店</text>
          </view>
          <text
            v-else-if="!canSwitchShop && shopKmLineSingle"
            class="shop-single-km"
          >{{ shopKmLineSingle }}</text>
        </view>
        <view class="top-name-options">
          <view 
            class="top-notice-option" 
            :class="{ 'top-notice-option-active': dineInOrTakeOut === '堂食' }"
            @click="confirmDiningType('堂食')"
          >堂食</view>
          <view 
            class="top-notice-option" 
            :class="{ 'top-notice-option-active': dineInOrTakeOut === '打包' }"
            @click="confirmDiningType('打包')"
          >打包</view>
        </view>
      </view>
	  
      <view class="top-notice" @click="openAnnouncementSheet">
        <view class="top-notice-text-wrap">
          <text class="top-notice-text">门店动态信息</text>
        </view>
        <view class="top-notice-show">点击查看 ></view>
      </view>
    </view>

    <!-- 外层滚动容器：仅负责轮播区滚动，点餐区通过sticky吸顶 -->
    <scroll-view 
      class="main-scroll" 
      scroll-y
      ref="outerScroll"
	  :scroll-into-view="scroll_into"
      @scroll="onMainScroll"
      :scroll-with-animation="true"
    >
      <!-- 轮播区 -->
      <view class="swiper-container" id="carousel-top">
        <OrangeSwiper
          :key="'menu-carousel-' + menuCarouselShopId"
          ref="menuCarousel"
          @swiperDataChange="handleSwiperDataChange"
        ></OrangeSwiper>
      </view>
      
      <!-- 点餐区：使用sticky吸顶，核心优化区域 -->
      <view class="commodity-wrapper" ref="commodityWrapper">
        <view class="commodity">
          <!-- 左侧分类导航：吸顶时隐藏，由页面级 fixed 层显示 -->
          <view class="order-left sticky-sidebar" :class="{ 'order-left-hidden': leftSidebarFixed }">
            <scroll-view 
              scroll-y="true" 
              class="scroll-Hei" 
              :scroll-with-animation="true" 
              enhanced
              show-scrollbar="false"
			  
            >
              <block v-for="(item,index) in itemize" :key="index">
                <view 
                  class="itemize-text" 
                  :class="{active: index == trigger}" 
                  @click="itemIze(index,item.cid)"
                >
                  <text>{{item.value}}</text>
                  <text v-if="item.sele_quantity > 0">{{item.sele_quantity}}</text>
                </view>
              </block>
            </scroll-view>
          </view>

          <!-- 右侧商品列表 -->
          <view class="order-right">
            
              <block v-for="(item,index) in goods" :key="index">
                <view :id="item.cid" class="rig-height">
                  <view class="classif">{{item.label}}</view>
                  <view 
                    class="classif-goods" 
                    v-for="(itemgood,good_index) in item.dishList" 
                    :key="good_index"
                    @click="dishOnShelf(itemgood) ? openComboOrDish(index,good_index,item.cid,itemgood) : showNotOnSaleTip()"
                    :class="{ 'not-on-sale': !dishCanOrder(itemgood) }"
                  >
                    <view class="goods-image">
                      <image
                        v-if="itemgood.image"
                        :src="dishImageUrlList(itemgood.image)"
                        mode="aspectFill"
                        class="real-img"
                        lazy-load
                      ></image>
                      <image
                        v-else
                        :src="staticUrl('images/default-avatar.png')"
                        mode="aspectFill"
                        class="placeholder-img"
                      ></image>
                    </view>
                    
                    <view class="goods-Price">
                      <view class="goods-name">
                        <text class="Bold">{{itemgood.name}}</text>
                        <text class="Thinning">已售 {{itemgood.monthlysale}}</text>
                      </view>
                      <view class="unit-price">
                        <text class="Symbol">¥</text>
                        <text class="Unitprice">{{itemgood.unitprice}}</text>
                        <text class="unit">/{{itemgood.unit}}</text>
                      </view>
                    </view>
                    
                    <view class="quantity">
                      <view class="quantity-badge" v-if="itemgood.quantity > 0">
                        <text>{{ itemgood.quantity }}</text>
                      </view>
                      <view v-if="dishCanOrder(itemgood)">
                        <button 
                          class="spec-btn" 
                          @click.stop="openComboOrDish(index,good_index,item.cid,itemgood)"
                        >
                          {{ isComboDish(itemgood) ? '选套餐' : '选规格' }}
                        </button>
                      </view>
                      <view v-else-if="dishSoldOut(itemgood)" class="spec-soldout-tag">已售罄</view>
                    </view>
                  </view>
                </view>
              </block>
              <!-- 底部留白 -->
              <view style="height: 400rpx;"></view>
            
          </view>
        </view>
      </view>
    </scroll-view>

    <!-- 吸顶时显示的左侧分类（放在 scroll-view 外，fixed 才生效） -->
    <view 
      v-if="leftSidebarFixed" 
      class="left-sidebar-fixed-layer"
    >
      <scroll-view 
        scroll-y 
        class="scroll-Hei fixed-sidebar-scroll"
        :scroll-with-animation="true"
        show-scrollbar="false"
      >
        <block v-for="(item, index) in itemize" :key="index">
          <view 
            class="itemize-text" 
            :class="{ active: index == trigger }" 
            @click="itemIze(index, item.cid)"
          >
            <text>{{ item.value }}</text>
            <text v-if="item.sele_quantity > 0">{{ item.sele_quantity }}</text>
          </view>
        </block>
      </scroll-view>
    </view>

    <!-- 非营业：底部红条与顶部一致，点击复用门店公告（GET /announcement/list 实时拉取，营业时间由后台公告维护） -->
    <view
      class="place-order-Business place-order-Business--notice"
      v-if="isNonBusinessHours"
      @tap="openAnnouncementSheet"
    >
      <view class="Business-notice-main">
        <text class="Business-notice-title">未营业</text>
        <text class="Business-notice-sub">点击查看门店营业时间</text>
      </view>
    </view>
    
    <!-- 底部操作栏 -->
    <view class="order-bottom" v-if="!isNonBusinessHours">
      <view class="Shopping" style="width: 115rpx;">
        <view class="Shopping-left" @click="pop_Shopping">
          <image :src="staticUrl('tab/gouwuche.png')" mode="widthFix"></image>
        </view>
        <view class="Shopping-number" v-if="total_quantity > 0">{{total_quantity}}</view>
      </view>
      <view class="Shopping-title" v-if="total_quantity > 0">已点{{total_quantity}}份菜品</view>
      
      <view class="place-order" @click="goToConfirmOrder" v-if="!needScanTable" >
        <button :disabled="total_quantity === 0">
          {{order_no ? '加菜' : '选好了'}}
        </button>
      </view>
      <view class="place-order" @click="scanCode" v-if="needScanTable">
        <button plain="true">
          扫台号
        </button>
      </view>
    </view>


    <global-activity-popup ref="globalActivityPopup" />

    <!-- 距离过远提示：红色强调，避免误关 -->
    <view class="far-shop-modal-root" v-if="showFarShopModal">
      <view class="far-shop-modal-mask"></view>
      <view class="far-shop-modal-panel" @click.stop>
        <view class="far-shop-modal-title">距离过远提醒</view>
        <view class="far-shop-modal-text">
          当前门店
          <text class="far-shop-modal-shop-name">「{{ displayMenuShopTitle || '未识别门店' }}」</text>
          距离较远（约{{ farShopKmText }}公里），请确认门店后再下单
        </view>
        <view class="far-shop-modal-actions">
          <view class="far-shop-btn far-shop-btn-confirm" @click="handleFarShopModalConfirm">继续下单</view>
          <view class="far-shop-btn far-shop-btn-cancel" @click="handleFarShopModalCancel">
            {{ canSwitchShop ? '切换门店' : '取消' }}
          </view>
        </view>
      </view>
    </view>

    <!-- 组件引入 -->
    <Cart v-if="card" :shopping_card="shopping_card" @empty-data="empty_data" @add-sub="shopping_Cart_add_sub"></Cart>
    <Details
      v-if="popupitem && pro_details.itemgood && dishOnShelf(pro_details.itemgood)"
      :pro_details="pro_details"
      :isNonBusinessHours="isNonBusinessHours"
      @close-popup="popup_item(false)"
    ></Details>
    <Home v-if="exist"></Home>

    <!-- 门店公告：GET /announcement/list，点击顶部条或底部非营业条从底部弹出 -->
    <view class="announcement-sheet-root" v-if="showAnnouncementSheet">
      <view class="announcement-sheet-mask" @click="closeAnnouncementSheet" @touchmove.stop.prevent></view>
      <view class="announcement-sheet-panel" @click.stop>
        <view class="announcement-sheet-header">
          <text class="announcement-sheet-title">门店公告</text>
          <view class="announcement-sheet-close" @click="closeAnnouncementSheet">
            <text>关闭</text>
          </view>
        </view>
        <scroll-view scroll-y class="announcement-sheet-body" :show-scrollbar="true">
          <view v-if="announcementLoading" class="announcement-sheet-loading">加载中…</view>
          <view v-else-if="!announcementList.length" class="announcement-sheet-empty">
            <text>暂无动态公告</text>
          </view>
          <block v-else>
            <view
              class="announcement-sheet-item"
              v-for="(a, idx) in announcementList"
              :key="announcementItemKey(a, idx)"
            >
              <view class="announcement-item-body">
                <announcement-body :content="a.content" />
              </view>
            </view>
          </block>
        </scroll-view>
      </view>
    </view>
  </view>
</template>

<script>
import { getBaseUrl, requestUtil } from "../../utils/requestUtil.js";
import {
  parseTableNumberFromMergedQuery,
  parseTableNumberFromScanCodeResult,
} from "../../utils/tableQrParse.js";
import feieService from "../../utils/feie-service.js";
import OrangeSwiper from './components/OrangeSwiper.vue';
import Home from '../skeleton-view/home.vue';
import Cart from './components/shopping-cart.vue';
import Details from './components/goods-details.vue';
import AnnouncementBody from './components/announcement-body.vue';
import { Code } from '../../config/order.js';
import {
  PAGE_LOAD_TARGET_MS,
  DEFER_READY_DELAY_MS,
  DISH_CACHE_TTL_MS,
  DISH_CACHE_KEY,
  DISH_CACHE_TIME_KEY,
  DISH_STATUS_POLL_INTERVAL_MS,
} from '../../config/perf.js';
import {
  startMenuCatalogSocket,
  stopMenuCatalogSocket,
  isMenuCatalogSocketConnected,
} from '../../utils/menuCatalogSocket.js';
import {
  getCurrentShopId,
  getCurrentShopSnapshot,
  setCurrentShop,
  sortShopsForDisplay,
  syncLocalShopFromOpenList,
  MENU_SHOP_MANUAL_KEY,
  markShopBoundFromQr,
  isShopBoundFromQr,
  clearShopQrBound,
  parseShopIdFromLaunchOptions,
  buildShopBusinessHoursLabel,
  buildShopTakeoutHoursLabel,
} from '../../utils/shopContext.js';
import { distanceUserToShopKm } from '../../utils/geoDistance.js';
import { dishSoldOut, dishCanOrder, dishOnShelf, normalizeSoldOut } from '../../utils/dishSale.js';
import { isComboDish, recalcComboCartLineTotal } from '../../utils/comboMeal.js';
import { staticUrl } from "../../utils/staticAssetUrl.js";
import { dishImageUrlList } from "../../utils/imageUrl.js";
import { getValidDinersCount, saveDinersCount } from "../../utils/dinersCache.js";
import { parseReviewFromBusinessResponse } from "../../utils/reviewMode.js";

const app = getApp();
/** 首次进点餐完成「定位选店 / 与同步列表」后写入；选店页手动选店时也会写入，避免覆盖用户选择 */
const MENU_SHOP_BOOTSTRAP_KEY = 'mp_menu_shop_bootstrap_v1';



export default {
  components: { Cart, Details, Home, OrangeSwiper, AnnouncementBody },
  data() {
    return {
      baseUrl: '',
      isLoading: false,
      isNonBusinessHours: false,
      exist: true,
      itemize: [],      // 类目
      trigger: 0,       // 类目选中的值
      goods: [],        // 所有菜品
      heightset: [],    // 存储右边每一个分类菜品的高度
      tophei: 0,        // 滚动时距离顶部的高度
      scroll_into: '',
      card: false,      // 购物车隐藏
      shopping_card: [],// 购物车里的数据
      popupitem: false, // 单个商品弹出框隐藏
      pro_details: {},  // 单个商品弹出框里的数据
      order_no: '',     // 订单编号
      order_used_coupon: false, // 加菜时原订单是否已用优惠券，用于确认页显隐优惠券入口
      is_add_dishes: false, // 是否是加菜操作
      dineInOrTakeOut: '',  // 堂食或打包的选择
      isSubmitting: false, // 提交状态
      isReview: false,
      table_number: '',
      showDiningModal: false,
      currentIndex: 0,
      autoPlayInterval: 3000,  // 自动轮播间隔(毫秒)
      systemInfo: {}, // 系统信息
      cssVars: {}, // 动态CSS变量
      swiperChildData: {
        topCarouselList: null,
        bottomCarouselList: null,
        isEmpty: false
      },
	  scrollAutoTriggered: false,
	  swiperRealHeight: 0, 
	  isInnerScrollEnabled: false, // 是否允许内部滚动
      outerScrollTop: 0, // 外层滚动距离
      isOuterScrollAtTop: true, // 外层是否在顶部
	  
	  categoryTops: [], // 存储右侧每个分类距离顶部的绝对位置
	  swiperHeightRetryCount: 0,
	  leftSidebarFixed: false, // 左侧分类是否吸顶固定（不随右侧滚动）
      dishStatusPollTimer: null,
      _dishStatusRefreshing: false,
      dishStatusPageVisible: false,
      _dishStatusShowRefreshTimer: null,
      _menuWsListFetching: false,
      menuHeaderShopName: '',
      /** GET /shop/list 营业门店数量；大于 1 时展示「切换门店」 */
      shopListCount: 0,
      /** 轮播组件 :key，切换门店时重建并拉取该店轮播 */
      menuCarouselShopId: 0,
      /** 与当前定位到所选门店的直线距离（公里），无定位或门店无坐标则为 null */
      kmToCurrentShop: null,
      /** 提交前门店距离提醒阈值（公里） */
      shopDistanceWarnKm: 0.5,
      /** GET /announcement/list，连锁依赖请求头 X-Shop-Id */
      announcementList: [],
      announcementLoading: false,
      showAnnouncementSheet: false,
      currentShopAddress: '暂未提供',
      currentShopPhone: '暂未提供',
      currentShopBusinessHours: '',
      currentShopTakeoutHours: '下午6:30-凌晨2:00',
      currentShopLatitude: null,
      currentShopLongitude: null,
      announcementTickerIndex: 0,
      announcementTickerTimer: null,
      /** 节流：避免 onLoad 与 onShow 连续两次拉公告 */
      lastAnnouncementLoadedAt: 0,
      /** 首次进入页面时，跳过 onShow 的门店/公告二次拉取 */
      skipFirstShowShopRefresh: true,
      /** 定位失败提示节流时间戳，避免反复打扰 */
      lastLocationHintAt: 0,
      /** 距离过远确认弹窗 */
      showFarShopModal: false,
      farShopKmText: '',
    }
  },
  computed: {
    displayMenuShopTitle() {
      const n = (this.menuHeaderShopName || '').trim();
      return n || '老肥油边王(松源海鲜街)';
    },
    total_quantity() {
      return this.shopping_card.reduce((sum, item) => sum + item.quantity, 0);
    },
    // 堂食且无台号且非审核时显示「扫台号」，否则显示「选好了」
    needScanTable() {
      if (this.dineInOrTakeOut !== '堂食' || this.isReview) return false;
      const t = this.table_number;
      return !t || t === 'undefined' || String(t).trim() === '';
    },
    /** 顶部条文案：有公告时展示首条标题（截断），否则品牌标语 */
    announcementBarText() {
      const list = this.announcementList || [];
      if (!list.length) return '吃油边，认准老肥油边王';
      const idx = this.announcementTickerIndex % list.length;
      const current = list[idx] || list[0];
      const t = current && current.title != null ? String(current.title).trim() : '';
      if (t) return t.length > 20 ? `${t.slice(0, 20)}…` : t;
      return list.length > 1 ? `门店公告（${list.length}条）` : '门店公告';
    },
    shouldMarqueeAnnouncement() {
      return Array.isArray(this.announcementList) && this.announcementList.length > 1;
    },
    announcementTickerKey() {
      return `${this.announcementTickerIndex}-${this.announcementBarText}`;
    },
    canSwitchShop() {
      return this.shopListCount > 1;
    },
    /** 多店时与「切换门店」同行，如「1.2公里 切换门店」前段 */
    shopKmPrefix() {
      const k = this.kmToCurrentShop;
      if (k == null || !Number.isFinite(k) || k < 0) return '';
      return `距离${Number(k).toFixed(1)}公里  `; 
    },
    /** 单店时仅显示距离，无「切换」 */
    shopKmLineSingle() {
      if (this.canSwitchShop) return '';
      const k = this.kmToCurrentShop;
      if (k == null || !Number.isFinite(k) || k < 0) return '';
      return `距约${Number(k).toFixed(1)}公里`;
    },
  },
  methods: {
    staticUrl,
    announcementItemKey(a, idx) {
      return a && a.id != null ? `ann-${a.id}` : `ann-i-${idx}`;
    },
    dishSoldOut,
    dishCanOrder,
    dishOnShelf,
    isComboDish,
    refreshMenuHeaderShop() {
      const s = getCurrentShopSnapshot();
      this.menuHeaderShopName = (s && s.name) ? String(s.name).trim() : '';
      this.currentShopAddress = (s && s.address) ? String(s.address).trim() : this.currentShopAddress;
      const lat = Number(s && s.latitude);
      const lon = Number(s && s.longitude);
      this.currentShopLatitude = Number.isFinite(lat) ? lat : this.currentShopLatitude;
      this.currentShopLongitude = Number.isFinite(lon) ? lon : this.currentShopLongitude;
      const snapBh = (s && s.businessHours) ? String(s.businessHours).trim() : '';
      if (snapBh) this.currentShopBusinessHours = snapBh;
      const snapTh = (s && s.takeoutHours) ? String(s.takeoutHours).trim() : '';
      if (snapTh) this.currentShopTakeoutHours = snapTh;
      const snapPhone = (s && s.contact_phone) ? String(s.contact_phone).trim() : '';
      if (snapPhone) this.currentShopPhone = snapPhone;
      this.syncMenuCarouselShopId();
    },
    /** 当前门店变化时更新轮播 :key，触发 OrangeSwiper 按新店重新拉取 */
    syncMenuCarouselShopId(shopId) {
      const sid =
        shopId != null && shopId !== ''
          ? Number(shopId) || 0
          : Number(getCurrentShopId()) || 0;
      if (sid !== Number(this.menuCarouselShopId)) {
        this.menuCarouselShopId = sid;
      }
    },
    applyCurrentShopInfo(shop) {
      if (!shop || typeof shop !== 'object') return;
      const sid = Number(shop.id);
      if (Number.isFinite(sid) && sid > 0) {
        this.syncMenuCarouselShopId(sid);
      }
      const address = shop.address != null ? String(shop.address).trim() : '';
      if (address) this.currentShopAddress = address;
      // 按 openapi Shop 字段优先：contact_phone/open_time/close_time
      const phone = (shop.contact_phone || shop.phone || shop.tel || shop.mobile || '').toString().trim();
      if (phone) this.currentShopPhone = phone;
      const businessHours = buildShopBusinessHoursLabel(shop);
      if (businessHours) this.currentShopBusinessHours = businessHours;
      const takeoutHours = buildShopTakeoutHoursLabel(shop);
      if (takeoutHours) this.currentShopTakeoutHours = takeoutHours;
      const lat = Number(shop.latitude);
      const lon = Number(shop.longitude);
      if (Number.isFinite(lat)) this.currentShopLatitude = lat;
      if (Number.isFinite(lon)) this.currentShopLongitude = lon;
    },
    contactCurrentShop() {
      const phone = (this.currentShopPhone || '').trim();
      if (!phone || phone === '暂未提供') {
        wx.showToast({ title: '门店电话暂未提供', icon: 'none' });
        return;
      }
      wx.makePhoneCall({
        phoneNumber: phone,
        fail: () => {
          wx.showToast({ title: '拨号失败', icon: 'none' });
        },
      });
    },
    navigateToCurrentShop() {
      if (!Number.isFinite(this.currentShopLatitude) || !Number.isFinite(this.currentShopLongitude)) {
        wx.showToast({ title: '门店定位暂未提供', icon: 'none' });
        return;
      }
      wx.openLocation({
        latitude: this.currentShopLatitude,
        longitude: this.currentShopLongitude,
        name: this.displayMenuShopTitle,
        address: this.currentShopAddress,
        scale: 18,
      });
    },
    /**
     * 门店公告列表（openapi：GET /announcement/list，无需 JWT；按 X-Shop-Id 过滤门店与全局公告）
     */
    async loadShopAnnouncements(force = false) {
      const now = Date.now();
      if (!force && this.lastAnnouncementLoadedAt && now - this.lastAnnouncementLoadedAt < 900) {
        return;
      }
      this.announcementLoading = true;
      try {
        const res = await requestUtil({
          url: '/announcement/list',
          method: 'get',
          showLoading: false,
        });
        if (res && res.code === 0 && Array.isArray(res.list)) {
          this.announcementList = res.list.slice().sort((a, b) => {
            const sa = Number(a.sort_order);
            const sb = Number(b.sort_order);
            const oa = Number.isFinite(sa) ? sa : 0;
            const ob = Number.isFinite(sb) ? sb : 0;
            if (oa !== ob) return oa - ob;
            return (Number(a.id) || 0) - (Number(b.id) || 0);
          });
          if (this.announcementList.length > 0) {
            this.announcementTickerIndex = this.announcementTickerIndex % this.announcementList.length;
          } else {
            this.announcementTickerIndex = 0;
          }
          this.startAnnouncementTicker();
        } else {
          this.announcementList = [];
          this.announcementTickerIndex = 0;
          this.stopAnnouncementTicker();
        }
      } catch (e) {
        this.announcementList = [];
        this.announcementTickerIndex = 0;
        this.stopAnnouncementTicker();
      } finally {
        this.announcementLoading = false;
        this.lastAnnouncementLoadedAt = Date.now();
      }
    },
    startAnnouncementTicker() {
      this.stopAnnouncementTicker();
      if (!Array.isArray(this.announcementList) || this.announcementList.length <= 1) return;
      this.announcementTickerTimer = setInterval(() => {
        const total = this.announcementList.length || 0;
        if (total <= 1) return;
        this.announcementTickerIndex = (this.announcementTickerIndex + 1) % total;
      }, 3200);
    },
    stopAnnouncementTicker() {
      if (this.announcementTickerTimer) {
        clearInterval(this.announcementTickerTimer);
        this.announcementTickerTimer = null;
      }
    },
    openAnnouncementSheet() {
      this.showAnnouncementSheet = true;
      this.loadShopAnnouncements(true);
    },
    closeAnnouncementSheet() {
      this.showAnnouncementSheet = false;
    },
    _shopLocateLog(stage, detail = null) {
      if (detail == null) {
        console.info(`[menu-shop-locate] ${stage}`);
        return;
      }
      console.info(`[menu-shop-locate] ${stage}`, detail);
    },
    showLocationHint(message = '定位失败，请开启定位权限后重试') {
      const now = Date.now();
      if (this.lastLocationHintAt && (now - this.lastLocationHintAt) < 10000) {
        return;
      }
      this.lastLocationHintAt = now;
      wx.showToast({
        title: message,
        icon: 'none',
        duration: 2200,
      });
    },
    /**
     * 微信小程序定位：优先使用 getLocation（更精确），失败时降级到 getFuzzyLocation
     * @returns {Promise<{ latitude: number, longitude: number } | null>}
     */
    fetchUserLocationForMenu() {
      return new Promise((resolve) => {
        const resolveLoc = (res) => {
          const lat = Number(res && res.latitude);
          const lng = Number(res && res.longitude);
          if (Number.isFinite(lat) && Number.isFinite(lng)) {
            resolve({ latitude: lat, longitude: lng });
            return true;
          }
          return false;
        };
        const tryFuzzy = () => {
          if (typeof wx.getFuzzyLocation !== 'function') {
            this.showLocationHint('定位服务不可用，请检查定位权限');
            resolve(null);
            return;
          }
          wx.getFuzzyLocation({
            type: 'gcj02',
            success: (res) => {
              if (!resolveLoc(res)) {
                this.showLocationHint('定位结果异常，请稍后重试');
                resolve(null);
              }
            },
            fail: (err) => {
              this._shopLocateLog('getFuzzyLocation fail', err);
              this.showLocationHint('定位失败，请确认已开启定位权限');
              resolve(null);
            },
          });
        };
        if (typeof wx.getLocation !== 'function') {
          tryFuzzy();
          return;
        }
        wx.getLocation({
          type: 'gcj02',
          success: (res) => {
            if (!resolveLoc(res)) tryFuzzy();
          },
          fail: (err) => {
            this._shopLocateLog('getLocation fail', err);
            this.showLocationHint('未获取到精确定位，已尝试模糊定位');
            tryFuzzy();
          },
        });
      });
    },
    /**
     * 拉门店列表后：若用户未在选店页手动指定门店，则每次按定位选最近店；
     * 手动选店后不再自动覆盖。展示用户与当前店直线距离（公里）。
     */
    async ensureShopForMenuPage() {
      try {
        const res = await requestUtil({
          url: '/shop/list',
          method: 'get',
          showLoading: false,
        });
        if (!res || res.code !== 0 || !Array.isArray(res.list)) {
          this._shopLocateLog('ensureShopForMenuPage: shop list invalid', res);
          this.kmToCurrentShop = null;
          return;
        }
        const shops = sortShopsForDisplay(res.list);
        if (!shops.length) {
          this.shopListCount = 0;
          this.kmToCurrentShop = null;
          this._shopLocateLog('ensureShopForMenuPage: no shop in list');
          return;
        }

        this.shopListCount = shops.length;
        const userLoc = await this.fetchUserLocationForMenu();
        const manualPick = !!wx.getStorageSync(MENU_SHOP_MANUAL_KEY);
        const qrBound = isShopBoundFromQr();
        syncLocalShopFromOpenList(shops);
        const id = getCurrentShopId();
        const current = shops.find((s) => Number(s.id) === Number(id)) || shops[0];
        if (current) {
          setCurrentShop(current);
          this.applyCurrentShopInfo(current);
        }
        const bootstrapped = !!wx.getStorageSync(MENU_SHOP_BOOTSTRAP_KEY);
        if (!bootstrapped) {
          try {
            wx.setStorageSync(MENU_SHOP_BOOTSTRAP_KEY, 1);
          } catch (e) {
            /* 忽略 */
          }
        }
        this.kmToCurrentShop = current ? distanceUserToShopKm(userLoc, current) : null;
        this._shopLocateLog('ensureShopForMenuPage: current shop', {
          resolvedId: current && current.id,
          resolvedName: current && current.name,
          fromStorageId: id,
          shopListCount: shops.length,
          hasUserLoc: !!userLoc,
          manualPick,
          qrBound,
          km: this.kmToCurrentShop,
        });
        this.refreshMenuHeaderShop();
      } catch (e) {
        this._shopLocateLog('ensureShopForMenuPage: exception', e);
        this.kmToCurrentShop = null;
      }
    },
    onShopEntryTap() {
      if (!this.canSwitchShop) {
        return;
      }
      wx.navigateTo({
        url: '/packageOther/select-shop/select-shop?from=menu',
      });
    },
    // 接收轮播组件的基础数据
    handleSwiperDataChange(emitData) {
      this.swiperChildData = emitData;
      // 如果轮播为空，重新计算高度
      if (emitData.isEmpty) {
        this.calculateCssVars();
      }
    },
    
    // 计算并设置CSS变量（核心：高度补偿）
    calculateCssVars() {
      const { windowHeight } = this.systemInfo;
      // 固定头部高度（rpx转px）
      const headerHeightPx = 150 * (windowHeight / 750);
      // 底部操作栏高度（rpx转px）
      const bottomHeightPx = 120 * (windowHeight / 750);
      // 点餐区可用高度 = 视口高度 - 头部高度 - 底部高度
      const orderViewHeight = windowHeight - headerHeightPx - bottomHeightPx;
	  
      
      // 设置CSS变量
      this.cssVars = {
        '--window-height': `${windowHeight}px`,
        '--header-height': `${headerHeightPx}px`,
        '--bottom-height': `${bottomHeightPx}px`,
        '--order-view-height': `${orderViewHeight}px`,
      };
    },
	
	// 主区域滚动监听 - 左侧吸顶固定（吸顶层在 scroll-view 外，fixed 才生效）
	onMainScroll(e) {
	  const scrollTop = e.detail.scrollTop;
	  this.outerScrollTop = scrollTop;
	  // 吸顶阈值：轮播区高度，若未取到则用约 200px 兜底
	  const threshold = this.swiperRealHeight > 0 ? this.swiperRealHeight : 200;
	  this.leftSidebarFixed = scrollTop >= threshold;
	  if (scrollTop < threshold) {
	    this.trigger = 0;
	    this.isOuterScrollAtTop = true;
	    return;
	  }
	  this.isOuterScrollAtTop = false;
	  this.tophei = scrollTop;
	},
	
	
	
    // 获取轮播区真实高度
    async getSwiperRealHeight() {
      try {
        await this.$nextTick(); // 等待DOM渲染完成
        const query = uni.createSelectorQuery().in(this);
        query.select('#carousel-top').boundingClientRect(rect => {
          if (rect && rect.height) {
            this.swiperRealHeight = rect.height;
          } else {
            // 重试机制：最多重试3次
            if (this.swiperHeightRetryCount < 3) {
              this.swiperHeightRetryCount++;
              setTimeout(() => this.getSwiperRealHeight(), 200);
            } else {
              this.swiperRealHeight = 500; // 兜底高度
            }
          }
        }).exec();
      } catch (err) {
        this.swiperRealHeight = 500;
      }
    },

   
    
    dishImageUrlList,
    
    /** 是否营业中：与后台 business 字段一致（兼容 boolean / 1 / "1"） */
    isStoreBusinessOpen(raw) {
      return raw === true || raw === 1 || raw === '1';
    },

    // 检查营业时间
    async checkBusinessHours() {
      try {
        const response = await requestUtil({
          url: "/order/Business",
          method: "post",
          showLoading: false,
        });
        this.isNonBusinessHours = !this.isStoreBusinessOpen(response && response.business);
        const review = parseReviewFromBusinessResponse(response);
        this.isReview = review;
        if (app.globalData) {
          app.globalData.isReviewMode = review;
          app.globalData.isReviewModeUpdatedAt = Date.now();
        }
        if (review && typeof app.guardToQueueIfReview === "function") {
          app.guardToQueueIfReview({ skipFetch: true });
        }
      } catch (e) {
        console.warn('checkBusinessHours', e);
      }
    },

    /** WebSocket：POST /order/ChangeBusiness 成功后推送，实时刷新顶部休息条与底部栏 */
    applyBusinessChangedFromSocket(msg) {
      if (!msg || msg.type !== 'business_changed') return;
      this.isNonBusinessHours = !this.isStoreBusinessOpen(msg.business);
    },
    
    // 确认用餐方式
    confirmDiningType(type) {
      if (type === '堂食' && this.dineInOrTakeOut === '打包') {
        const hasDiners = getValidDinersCount(app) != null;
        if (!hasDiners) {
          const tn = this.table_number ? String(this.table_number).trim() : '';
          wx.navigateTo({
            url: `/packageOther/select_number/select_number?number=${encodeURIComponent(tn)}`,
          });
          return;
        }
      }
      this.dineInOrTakeOut = type;
      this.showDiningModal = false;
      wx.setStorageSync('dineInOrTakeOut', type);
      try {
        app.setStorageWithExpiry('dineInOrTakeOut', type, 7 * 24 * 60);
      } catch (e) {}
    },

    /** 餐桌码 path/query 中的 shop_id，容错缺少 &：...number=1shop_id=2 */
    parseShopIdFromScanString(raw) {
      if (raw === undefined || raw === null) return null;
      const s = String(raw).trim();
      if (!s) return null;
      const m = s.match(/(?:^|[?&])shop_id=(\d+)/i);
      return m ? Number(m[1]) : null;
    },
    /**
     * 扫码携带 shop_id 且与当前门店不一致时：写入本地 X-Shop-Id、刷新菜单与公告。
     * 同步 MENU_SHOP_MANUAL_KEY，避免 onShow 里 ensureShopForMenuPage 按定位覆盖扫码门店。
     */
    async applyShopFromTableQr(shopId) {
      const id = Number(shopId);
      if (!Number.isFinite(id) || id <= 0) return;
      if (Number(getCurrentShopId()) === id) return;
      try {
        const res = await requestUtil({
          url: '/shop/list',
          method: 'get',
          showLoading: false,
        });
        if (!res || res.code !== 0 || !Array.isArray(res.list)) {
          wx.showToast({ title: '门店列表获取失败', icon: 'none' });
          return;
        }
        const shops = sortShopsForDisplay(res.list);
        const hit = shops.find((s) => Number(s.id) === id);
        if (!hit) {
          wx.showToast({ title: '门店不存在或未营业', icon: 'none' });
          return;
        }
        markShopBoundFromQr(hit);
        this.shopListCount = shops.length;
        this.applyCurrentShopInfo(hit);
        const userLoc = await this.fetchUserLocationForMenu();
        this.kmToCurrentShop = distanceUserToShopKm(userLoc, hit);
        this.refreshMenuHeaderShop();
        await this.dishEs();
        await this.loadShopAnnouncements(true);
        await this.checkBusinessHours();
      } catch (e) {
        console.error('applyShopFromTableQr', e);
        wx.showToast({ title: '切换门店失败', icon: 'none' });
      }
    },
    
    // 扫码
    scanCode() {
      app.scanCode({
        onSuccess: async (res) => {
          console.log('扫码结果:', res.path || res.result);
          const path = res.path || res.result;
          if (!path) {
            wx.showToast({ title: '扫码内容无效', icon: 'none' });
            return;
          }
          const { merged, shopId } = parseTableNumberFromScanCodeResult(res);
          const sid = shopId != null ? shopId : this.parseShopIdFromScanString(merged);
          if (sid != null) {
            await this.applyShopFromTableQr(sid);
          }
          const pathStr = String(path || '').trim();
          let url = pathStr.startsWith('/') ? pathStr : '/' + pathStr;
          if (!/dineInOrTakeOut=/i.test(url)) {
            const sep = url.includes('?') ? '&' : '?';
            url += sep + 'dineInOrTakeOut=' + encodeURIComponent(this.dineInOrTakeOut || '堂食');
          }
          this.getTable(url, merged);
        }
      });
    },
    
    // 获取台号（与 App.scanCode 一致：支持 D02、number=8shop_id=4 粘连等）
    getTable(url, scanMerged) {
      const s = [scanMerged, url].filter(Boolean).join(' ');
      const number = parseTableNumberFromMergedQuery(s);
      if (number) {
        this.table_number = number;
        wx.setStorageSync('table_number', this.table_number);
        app.setStorageWithExpiry("table_number", this.table_number);
        this.checkOrderStatus();
      }
    },
    
    // 切换分类
    itemIze(index, cid) {
        this.trigger = index;
        this.scroll_into = cid;
		setTimeout(() => {
          this.scroll_into = '';
        }, 200);
        
    },
    
    // 增加菜品
    plus(index, good_index, cid, itemgood) {
      if (!dishOnShelf(itemgood)) {
        this.showNotOnSaleTip();
        return;
      }
      if (dishSoldOut(itemgood)) {
        this.showSoldOutTip();
        return;
      }
      
      const { quantity, new_quantity, image, name, unitprice, unit, id, onsale, selectedSpicy, sold_out } = itemgood;
      const QU = new_quantity;
      
      this.$set(this.goods[index].dishList[good_index], 'quantity', quantity);
      this.$set(this.goods[index].dishList[good_index], 'selectedSpicy', selectedSpicy);
      const arr = { image, name, unitprice, quantity: QU, unit, total_price: unitprice * QU, id, cid, index, good_index, onsale, sold_out: normalizeSoldOut(sold_out), selectedSpicy };
      this.shopping_Cart(arr);
    },
    
    // 减少菜品
    reduce(index, good_index, cid, itemgood) {
      const { quantity, new_quantity, image, name, unitprice, unit, id, onsale, selectedSpicy, sold_out } = itemgood;
      if (quantity <= 0) return;
      
      const QU = quantity;
      this.$set(this.goods[index].dishList[good_index], 'quantity', QU);
      this.$set(this.goods[index].dishList[good_index], 'selectedSpicy', selectedSpicy);
      
      if (QU === 0) {
        this.qunint_of_goods();
        this.removeFromShoppingCart(id);
      } else {
        const arr = { image, name, unitprice, quantity: QU, unit, total_price: unitprice * QU, id, cid, index, good_index, onsale, sold_out: normalizeSoldOut(sold_out), selectedSpicy };
        this.shopping_Cart(arr);
      }
    },
    
    /**
     * 从本地 storage 恢复购物车（Tab 切换回来时 onLoad 不会执行，须与 AI 点餐等写入的缓存对齐）
     */
    syncShoppingCartFromStorage() {
      let list = [];
      try {
        const raw = wx.getStorageSync('shopping_cart');
        list = Array.isArray(raw) ? raw : [];
      } catch (e) {
        list = [];
      }
      this.shopping_card = list;
      if (!this.goods || !this.goods.length) {
        return;
      }
      if (list.length) {
        this.pruneShoppingCartOffShelf({ toastIfRemoved: false });
      }
      if (!this.shopping_card.length) {
        this._resetMenuQuantitiesToMatchEmptyCart();
        return;
      }
      this.updateCar();
    },
    /** 购物车为空时，清空左侧分类角标与菜品列表上的数量（与 empty_data 视觉一致，不移除 storage） */
    _resetMenuQuantitiesToMatchEmptyCart() {
      this.itemize.forEach((item) => {
        this.$set(item, 'sele_quantity', 0);
      });
      this.goods.forEach((cat) => {
        (cat.dishList || []).forEach((d) => {
          this.$set(d, 'quantity', 0);
        });
      });
    },
    // 更新购物车（套餐多行合并为菜单上的数量合计）
    updateCar() {
      if (this.shopping_card.length === 0) return;
      const qtyAcc = {};
      const spicyLast = {};
      this.shopping_card.forEach((item) => {
        const k = `${item.index}_${item.good_index}`;
        qtyAcc[k] = (qtyAcc[k] || 0) + Number(item.quantity || 0);
        if (!item.isCombo && item.selectedSpicy) {
          spicyLast[k] = item.selectedSpicy;
        }
      });
      this.shopping_card.forEach((item) => {
        const cat = this.goods[item.index];
        const row = cat && cat.dishList && cat.dishList[item.good_index];
        if (!row) return;
        const k = `${item.index}_${item.good_index}`;
        this.$set(row, 'quantity', qtyAcc[k] || 0);
        if (spicyLast[k]) {
          this.$set(row, 'selectedSpicy', spicyLast[k]);
        }
      });
      this.qunint_of_goods();
    },
    
    // 从购物车移除
    removeFromShoppingCart(id) {
      const itemIndex = this.shopping_card.findIndex(item => item.id === id);
      if (itemIndex !== -1) {
        this.shopping_card.splice(itemIndex, 1);
        this.qunint_of_goods();
      }
    },
    
    // 加入购物车
    shopping_Cart(arr) {
      if (arr.quantity <= 0) {
        if (arr.isCombo && arr.cartKey) {
          const i = this.shopping_card.findIndex((c) => c.cartKey === arr.cartKey);
          if (i >= 0) this.shopping_card.splice(i, 1);
        } else {
          this.removeFromShoppingCart(arr.id);
        }
        return;
      }
      
      if (!arr.onsale) {
        return;
      }
      if (dishSoldOut(arr)) {
        return;
      }
      
      if (arr.isCombo && arr.cartKey) {
        const existIdx = this.shopping_card.findIndex((c) => c.cartKey === arr.cartKey);
        if (existIdx >= 0) {
          const merged = {
            ...this.shopping_card[existIdx],
            quantity: this.shopping_card[existIdx].quantity + arr.quantity,
          };
          recalcComboCartLineTotal(merged).then((line) => {
            this.$set(this.shopping_card, existIdx, line);
            wx.setStorageSync('shopping_cart', this.shopping_card);
            this.sortShoppingCart();
            this.updateCar();
          });
          return;
        }
        this.shopping_card.push(arr);
      } else if (this.shopping_card.length === 0) {
        this.shopping_card.push(arr);
      } else {
        let itemindex = this.shopping_card.findIndex(item => item.id == arr.id);
        if (itemindex === -1) {
          this.shopping_card.push(arr);
        } else {
          const sameSpicyIndex = this.shopping_card.findIndex(
            item => item.id === arr.id && item.selectedSpicy === arr.selectedSpicy && !item.isCombo
          );
          
          if (sameSpicyIndex !== -1) {
            this.$set(this.shopping_card[sameSpicyIndex], 'quantity', this.shopping_card[sameSpicyIndex].quantity + arr.quantity);
            this.$set(this.shopping_card[sameSpicyIndex], 'total_price', this.shopping_card[sameSpicyIndex].total_price + arr.total_price);
          } else {
            this.shopping_card.push(arr);
          }
        }
      }
      
      wx.setStorageSync('shopping_cart', this.shopping_card);
      this.sortShoppingCart();
      this.updateCar();
    },
    
    // 排序购物车
    sortShoppingCart() {
      this.shopping_card.sort((a, b) => {
        const cidA = parseInt(a.index, 10);
        const cidB = parseInt(b.index, 10);
        
        if (cidA !== cidB) {
          return cidA - cidB;
        }
        
        const indexA = parseInt(a.good_index, 10);
        const indexB = parseInt(b.good_index, 10);
        return indexA - indexB;
      });
      
      this.$forceUpdate();
    },
    
    // 计算菜品数量
    qunint_of_goods() {
      let array = this.shopping_card;
      let res = {};
      
      array.forEach(item => {
        if (res[item.cid]) {
          res[item.cid] += item.quantity;
        } else {
          res[item.cid] = item.quantity;
        }
      });
      
      let M = [];
      for (let k in res) {
        M.push({ cid: k, value: res[k] });
      }
      
      M.forEach(item => {
        let res_index = this.itemize.findIndex(iteming => iteming.cid == item.cid);
        this.$set(this.itemize[res_index], 'sele_quantity', item.value);
      });
    },
    
    // 购物车加减
    async shopping_Cart_add_sub(index, QU, id, cid, good_index, unitprice) {
      const line = this.shopping_card[index];
      if (line && line.isCombo) {
        const delta = QU > 0 ? 1 : -1;
        const newQty = line.quantity + delta;
        if (newQty <= 0) {
          this.shopping_card.splice(index, 1);
        } else {
          const merged = { ...line, quantity: newQty };
          const recalc = await recalcComboCartLineTotal(merged);
          this.$set(this.shopping_card, index, recalc);
        }
        wx.setStorageSync('shopping_cart', this.shopping_card);
        this.updateCar();
        return;
      }

      let quantity = QU;
      const itemcid = this.goods.findIndex(item => item.cid == cid);
      
      if (QU > 0) {
        quantity = QU;
        QU = this.goods[itemcid].dishList[good_index].quantity + 1;
      } else {
        quantity = QU * -1;
        QU = this.goods[itemcid].dishList[good_index].quantity - 1;
      }
      
      this.$set(this.shopping_card[index], 'quantity', quantity);
      this.$set(this.shopping_card[index], 'total_price', quantity * unitprice);
      this.$set(this.goods[itemcid].dishList[good_index], 'quantity', QU);
      
      if (quantity === 0) {
        this.removeFromShoppingCart(id);
      } else {
        this.qunint_of_goods();
      }
      wx.setStorageSync('shopping_cart', this.shopping_card);
    },
    
    // 清空购物车
    empty_data() {
      this.shopping_card = [];
      wx.removeStorageSync('shopping_cart');
      this.itemize.forEach(item => { item.sele_quantity = 0 });
      this.goods.forEach(item => {
        item.dishList.forEach(T => {
          T.quantity = 0;
        });
      });
      this.pop_Shopping(false);
    },
    
    /** 套餐进选规格页，普通菜进弹窗 */
    openComboOrDish(index, good_index, cid, itemgood) {
      if (!dishOnShelf(itemgood)) {
        this.showNotOnSaleTip();
        return;
      }
      if (isComboDish(itemgood)) {
        let dishSnap = "";
        try {
          dishSnap = encodeURIComponent(
            JSON.stringify({
              id: itemgood.id,
              name: itemgood.name,
              unit: itemgood.unit,
              image: itemgood.image,
              unitprice: itemgood.unitprice,
              onsale: itemgood.onsale,
              sold_out: itemgood.sold_out,
              specification: itemgood.specification || "",
            })
          );
        } catch (e) {
          dishSnap = "";
        }
        wx.navigateTo({
          url:
            `/packageOther/combo-select/combo-select?dishId=${itemgood.id}` +
            `&catIndex=${index}&dishIndex=${good_index}` +
            `&cid=${encodeURIComponent(cid || "")}` +
            (dishSnap ? `&dishSnap=${dishSnap}` : ""),
        });
        return;
      }
      this.popup_item(true, index, good_index, cid, itemgood);
    },

    // 商品弹窗
    popup_item(value = true, index, good_index, cid, itemgood) {
      if (value) {
        if (!dishOnShelf(itemgood)) {
          this.showNotOnSaleTip();
          return;
        }
        if (isComboDish(itemgood)) {
          this.openComboOrDish(index, good_index, cid, itemgood);
          return;
        }
        itemgood.new_quantity = 1;
        this.pro_details = { index, good_index, cid, itemgood };
      }
      this.popupitem = value;
    },
    
    /** 按菜品 id 在最新 goods 中定位（用于购物车与菜单对齐） */
    findDishInGoodsById(id) {
      if (id == null || !this.goods || !this.goods.length) return null;
      for (let ci = 0; ci < this.goods.length; ci++) {
        const cat = this.goods[ci];
        const list = cat.dishList || [];
        for (let di = 0; di < list.length; di++) {
          if (list[di].id == id) {
            return { catIndex: ci, dishIndex: di, dish: list[di], cid: cat.cid };
          }
        }
      }
      return null;
    },

    /**
     * 菜单数据更新后：弹窗内必须用 goods 里最新引用，否则下架后仍卡在旧对象上可选规格。
     * 已下架或已从列表移除则关弹窗并提示。
     */
    syncPopupWithLatestGoods() {
      if (!this.popupitem || !this.pro_details || !this.pro_details.itemgood) return;
      const id = this.pro_details.itemgood.id;
      const hit = id != null ? this.findDishInGoodsById(id) : null;
      if (!hit || hit.dish.onsale === false) {
        this.popupitem = false;
        wx.showToast({
          title: !hit ? '该商品已从菜单移除' : '该商品已下架',
          icon: 'none',
        });
        return;
      }
      const d = hit.dish;
      this.pro_details = {
        index: hit.catIndex,
        good_index: hit.dishIndex,
        cid: hit.cid,
        itemgood: d,
      };
      if (d.new_quantity == null || d.new_quantity < 1) {
        this.$set(d, 'new_quantity', 1);
      }
    },

    /**
     * 移除购物车中已下架/已售罄或菜单里已不存在的菜品，并同步 goods 数量与本地缓存。
     * @param {{ toastIfRemoved?: boolean }} options 打开购物车时可 toast 提示
     */
    pruneShoppingCartOffShelf(options = {}) {
      const { toastIfRemoved = false } = options;
      if (!Array.isArray(this.shopping_card) || !this.shopping_card.length) return 0;
      if (!this.goods || !this.goods.length) return 0;

      const next = [];
      for (const item of this.shopping_card) {
        const hit = this.findDishInGoodsById(item.id);
        if (!hit || hit.dish.onsale === false || dishSoldOut(hit.dish)) {
          if (hit) {
            this.$set(this.goods[hit.catIndex].dishList[hit.dishIndex], 'quantity', 0);
          }
          continue;
        }
        next.push({
          ...item,
          index: hit.catIndex,
          good_index: hit.dishIndex,
          cid: hit.cid,
          onsale: true,
          sold_out: normalizeSoldOut(hit.dish.sold_out),
        });
      }

      const removedCount = this.shopping_card.length - next.length;
      const prevSnap = this.shopping_card.map((x) => `${x.id}:${x.index}:${x.good_index}`);
      const nextSnap = next.map((x) => `${x.id}:${x.index}:${x.good_index}`);

      if (removedCount > 0 || prevSnap.join('|') !== nextSnap.join('|')) {
        this.shopping_card = next;
        wx.setStorageSync('shopping_cart', this.shopping_card);
        this.sortShoppingCart();
        this.qunint_of_goods();
        if (removedCount > 0 && toastIfRemoved) {
          wx.showToast({ title: `已移除${removedCount}个下架或已售罄菜品`, icon: 'none' });
        }
      }
      return removedCount;
    },

    // 购物车弹窗
    pop_Shopping(value = true) {
      const opening = value !== false && value !== 0 && value !== 'false';
      if (opening) {
        this.pruneShoppingCartOffShelf({ toastIfRemoved: true });
      }
      this.card = opening;
    },
    
    stopDishStatusPoller() {
      if (this.dishStatusPollTimer != null) {
        clearInterval(this.dishStatusPollTimer);
        this.dishStatusPollTimer = null;
      }
      if (this._dishStatusShowRefreshTimer != null) {
        clearTimeout(this._dishStatusShowRefreshTimer);
        this._dishStatusShowRefreshTimer = null;
      }
    },

    startDishStatusPoller() {
      this.stopDishStatusPoller();
      if (DISH_STATUS_POLL_INTERVAL_MS <= 0) return;
      this.dishStatusPollTimer = setInterval(() => {
        if (!this.dishStatusPageVisible) return;
        this.silentRefreshDishStatus();
      }, DISH_STATUS_POLL_INTERVAL_MS);
    },

    /**
     * 仅合并服务端在售（onsale）与售罄（sold_out），不重跑 _applyDishList（避免图片 observer、全量 setData）
     * @returns {boolean} 是否有字段发生变化
     */
    mergeDishSaleStatusFromList(freshList) {
      if (!Array.isArray(freshList) || !freshList.length || !this.goods || !this.goods.length) return false;
      const statusById = new Map();
      freshList.forEach((cat) => {
        (cat.dishList || []).forEach((d) => {
          if (d && d.id != null) {
            statusById.set(d.id, {
              onsale: d.onsale !== false,
              sold_out: normalizeSoldOut(d.sold_out),
            });
          }
        });
      });
      let changed = false;
      this.goods.forEach((cat, ci) => {
        (cat.dishList || []).forEach((d, di) => {
          if (d.id == null || !statusById.has(d.id)) return;
          const snap = statusById.get(d.id);
          const prevOn = d.onsale !== false;
          if (prevOn !== snap.onsale) {
            this.$set(this.goods[ci].dishList[di], 'onsale', snap.onsale);
            changed = true;
          }
          const prevSo = normalizeSoldOut(d.sold_out);
          if (prevSo !== snap.sold_out) {
            this.$set(this.goods[ci].dishList[di], 'sold_out', snap.sold_out);
            changed = true;
          }
        });
      });
      return changed;
    },

    /** 静默拉菜单，只同步售罄；并发保护；页面不可见时不请求 */
    async silentRefreshDishStatus() {
      if (isMenuCatalogSocketConnected()) return;
      if (!this.dishStatusPageVisible || this._dishStatusRefreshing) return;
      if (!this.goods || !this.goods.length) return;
      this._dishStatusRefreshing = true;
      try {
        const res = await requestUtil({
          url: '/dish/listAll',
          method: 'get',
          showLoading: false,
        });
        const list = res && res.allDish;
        if (!list || !list.length) return;
        const changed = this.mergeDishSaleStatusFromList(list);
        if (changed) {
          this.pruneShoppingCartOffShelf({ toastIfRemoved: false });
          if (DISH_CACHE_TTL_MS > 0) {
            try {
              wx.setStorageSync(DISH_CACHE_KEY, list);
              wx.setStorageSync(DISH_CACHE_TIME_KEY, Date.now());
            } catch (e) {}
          }
        }
        this.syncPopupWithLatestGoods();
      } catch (e) {
        // 静默失败，不打断用户
      } finally {
        this._dishStatusRefreshing = false;
      }
    },

    /**
     * 推送中是否必须全量 listAll（新菜、排序、结构变化等，WS 未带完整菜品树）
     */
    _menuCatalogPushRequiresFullList(payload) {
      if (!payload || payload.type !== 'dish_catalog_changed') return true;
      const a = payload.action;
      if (!a) return true;
      if (a === 'sort' || a === 'save_new' || a === 'save') return true;
      const id = payload.dishId;
      const idMissing = id == null || id === '';
      if ((a === 'delete' || a === 'updateOnSale' || a === 'save_update') && idMissing) return true;
      return false;
    },

    /** 单条局部变更；delete 本地无则视为已同步；改价等未在推送中的字段仍依赖偶发全量或进页刷新 */
    _applyOneCatalogPushPartial(payload) {
      const a = payload.action;
      const dishId = payload.dishId;
      if (a === 'delete') {
        const hit = this.findDishInGoodsById(dishId);
        if (!hit) return 'ok';
        const { catIndex, dishIndex } = hit;
        this.goods[catIndex].dishList.splice(dishIndex, 1);
        if (!this.goods[catIndex].dishList.length) {
          this.goods.splice(catIndex, 1);
        }
        return 'ok';
      }
      if (a === 'updateOnSale' || a === 'save_update') {
        const hit = this.findDishInGoodsById(dishId);
        if (!hit) return 'need_full';
        const d = hit.dish;
        const dn = payload.dishName;
        if (dn != null && String(dn).trim() !== '') {
          this.$set(d, 'name', String(dn).trim());
        }
        if (a === 'updateOnSale') {
          this.$set(d, 'onsale', payload.onsale !== false);
        } else if (payload.onsale !== undefined && payload.onsale !== null) {
          this.$set(d, 'onsale', payload.onsale !== false);
        }
        if (payload.sold_out !== undefined && payload.sold_out !== null) {
          this.$set(d, 'sold_out', normalizeSoldOut(payload.sold_out));
        }
        return 'ok';
      }
      return 'need_full';
    },

    _syncMenuCacheFromCurrentGoods() {
      if (DISH_CACHE_TTL_MS <= 0) return;
      try {
        wx.setStorageSync(DISH_CACHE_KEY, JSON.parse(JSON.stringify(this.goods)));
        wx.setStorageSync(DISH_CACHE_TIME_KEY, Date.now());
      } catch (e) {}
    },

    /** 静默全量（无 loading），用于 WS 兜底或与局部补丁衔接 */
    async _menuSocketSilentListAll() {
      if (!this.dishStatusPageVisible) return;
      if (this._menuWsListFetching) return;
      this._menuWsListFetching = true;
      try {
        const res = await requestUtil({
          url: '/dish/listAll',
          method: 'get',
          showLoading: false,
        });
        const list = res && res.allDish;
        if (!list || !list.length) return;
        if (DISH_CACHE_TTL_MS > 0) {
          try {
            wx.setStorageSync(DISH_CACHE_KEY, list);
            wx.setStorageSync(DISH_CACHE_TIME_KEY, Date.now());
          } catch (e) {}
        }
        this._applyDishList(list);
        if (this.order_no) {
          await this.restoreSelectedDishes();
          this.dineInOrTakeOut = '堂食';
        }
        this.updateCar();
      } catch (e) {
        console.warn('_menuSocketSilentListAll', e);
      } finally {
        this._menuWsListFetching = false;
      }
    },

    /**
     * WebSocket 批量推送 dish_catalog_changed：能局部则改内存，否则静默 listAll
     * @param {object|object[]} payloads
     */
    async refreshMenuFromSocketPush(payloads) {
      if (!this.dishStatusPageVisible) return;
      let batch = payloads;
      if (!Array.isArray(batch)) batch = batch != null ? [batch] : [];
      if (!batch.length) return;

      if (batch.some((p) => this._menuCatalogPushRequiresFullList(p))) {
        await this._menuSocketSilentListAll();
        return;
      }
      if (!this.goods || !this.goods.length) {
        await this._menuSocketSilentListAll();
        return;
      }

      if (this._menuWsListFetching) return;
      this._menuWsListFetching = true;
      try {
        for (let i = 0; i < batch.length; i++) {
          const r = this._applyOneCatalogPushPartial(batch[i]);
          if (r === 'need_full') {
            this._menuWsListFetching = false;
            await this._menuSocketSilentListAll();
            return;
          }
        }
        this.pruneShoppingCartOffShelf({ toastIfRemoved: false });
        this.syncPopupWithLatestGoods();
        this.updateCar();
        this._syncMenuCacheFromCurrentGoods();
        this.$nextTick(() => {
          setTimeout(() => this.goods_height(), 0);
        });
      } catch (e) {
        console.warn('refreshMenuFromSocketPush', e);
      } finally {
        this._menuWsListFetching = false;
      }
    },

    // 获取菜品列表（有缓存则先展示再后台更新；预处理懒加载字段减少 setData 次数）
    async dishEs() {
      const now = Date.now();
      if (DISH_CACHE_TTL_MS > 0) {
        try {
          const cache = wx.getStorageSync(DISH_CACHE_KEY);
          const cacheTime = wx.getStorageSync(DISH_CACHE_TIME_KEY) || 0;
          if (cache && cache.length > 0 && now - cacheTime < DISH_CACHE_TTL_MS) {
            this._applyDishList(cache);
            this.updateCar();
            requestUtil({ url: "/dish/listAll", method: "get" }).then(res => {
              const list = res.allDish || [];
              if (list.length > 0) {
                wx.setStorageSync(DISH_CACHE_KEY, list);
                wx.setStorageSync(DISH_CACHE_TIME_KEY, Date.now());
                this._applyDishList(list);
                if (this.order_no) {
                  this.restoreSelectedDishes().then(() => {
                    this.dineInOrTakeOut = '堂食';
                    this.updateCar();
                  });
                } else {
                  this.updateCar();
                }
              }
            }).catch(() => {});
            return;
          }
        } catch (e) {}
      }
      const res = await requestUtil({ url: "/dish/listAll", method: "get" });
      const list = res.allDish || [];
      if (DISH_CACHE_TTL_MS > 0 && list.length > 0) {
        try {
          wx.setStorageSync(DISH_CACHE_KEY, list);
          wx.setStorageSync(DISH_CACHE_TIME_KEY, Date.now());
        } catch (e) {}
      }
      this._applyDishList(list);
      if (this.order_no) {
        await this.restoreSelectedDishes();
        this.dineInOrTakeOut = '堂食';
      }
      this.updateCar();
    },
    _applyDishList(list) {
      if (!list || list.length === 0) return;
      list.forEach(cat => {
        (cat.dishList || []).forEach(d => {
          d.sold_out = normalizeSoldOut(d.sold_out);
        });
      });
      this.itemize = list;
      this.goods = list;
      this.pruneShoppingCartOffShelf({ toastIfRemoved: false });
      this.syncPopupWithLatestGoods();
      this.$nextTick(() => {
        setTimeout(() => this.goods_height(), 0);
      });
    },

    
    // 恢复已选菜品
    async restoreSelectedDishes() {
      try {
        const res = await requestUtil({
          url: "/order/get",
          data: {
            table_number: this.table_number,
            transac_status: 'unsettled'
          },
          method: "get"
        });
        
        const currentDishes = res.goods_list;
        if (currentDishes && currentDishes.length > 0) {
          currentDishes.forEach(dish => {
            const categoryIndex = this.goods.findIndex(cat =>
              cat.dishList.some(item => item.id === dish.id)
            );
            
            if (categoryIndex !== -1) {
              const dishIndex = this.goods[categoryIndex].dishList.findIndex(item => item.id === dish.id);
              
              if (dishIndex !== -1) {
                const menuRow = this.goods[categoryIndex].dishList[dishIndex];
                if (dishCanOrder(menuRow)) {
                  this.$set(
                    this.goods[categoryIndex].dishList[dishIndex],
                    'quantity',
                    dish.quantity || 0
                  );
                  
                  const cartItem = {
                    image: dish.image,
                    name: dish.name,
                    unitprice: dish.unitprice,
                    quantity: dish.quantity || 0,
                    unit: dish.unit,
                    total_price: dish.total_price || 0,
                    id: dish.id,
                    cid: this.goods[categoryIndex].cid,
                    good_index: dishIndex,
                    onsale: true,
                    sold_out: normalizeSoldOut(menuRow.sold_out),
                  };
                  
                  this.shopping_Cart(cartItem);
                }
              }
            }
          });
        }
      } catch (error) {
        console.error("恢复已选菜品失败:", error);
      }
    },
    
    // 计算菜品高度
    goods_height() {
      this.heightset = [];
      let cate_height = 0;
      const query = uni.createSelectorQuery().in(this);
      // 选择所有的 .rig-height 元素
      query.selectAll('.rig-height').boundingClientRect(rects => {
          rects.forEach((rect) => {
              cate_height += rect.height;
              this.heightset.push(cate_height);
          });
      }).exec();
    },
    
    shouldWarnFarShopWhenConfirm() {
      const km = Number(this.kmToCurrentShop);
      const warnKm = Number(this.shopDistanceWarnKm);
      return Number.isFinite(km) && Number.isFinite(warnKm) && warnKm > 0 && km >= warnKm;
    },
    confirmFarShopProceed(kmText) {
      this.farShopKmText = String(kmText || '');
      this.showFarShopModal = true;
      return new Promise((resolve) => {
        this._farShopModalResolver = resolve;
      });
    },
    handleFarShopModalCancel() {
      this.showFarShopModal = false;
      const resolve = this._farShopModalResolver;
      this._farShopModalResolver = null;
      if (typeof resolve === 'function') resolve(false);
    },
    handleFarShopModalConfirm() {
      this.showFarShopModal = false;
      const resolve = this._farShopModalResolver;
      this._farShopModalResolver = null;
      if (typeof resolve === 'function') resolve(true);
    },
    // 去确认订单
    async goToConfirmOrder() {
      if (this.isNonBusinessHours) {
        wx.showToast({ title: '非营业时间', icon: 'none' });
        return;
      }

      if (this.goods && this.goods.length) {
        this.pruneShoppingCartOffShelf({ toastIfRemoved: false });
      }

      const validItems = this.shopping_card.filter(item => item.quantity > 0);
      
      if (validItems.length === 0) {
        wx.showToast({ title: '购物车为空', icon: 'none' });
        return;
      }

      if (this.shouldWarnFarShopWhenConfirm()) {
        const kmText = Number(this.kmToCurrentShop).toFixed(1);
        const proceed = await this.confirmFarShopProceed(kmText);
        if (!proceed) {
          if (this.canSwitchShop) {
            this.onShopEntryTap();
          }
          return;
        }
      }
     
      wx.setStorageSync('shopping_cart', validItems);
      wx.setStorageSync('dineInOrTakeOut', this.dineInOrTakeOut);
      wx.setStorageSync('order_no', this.order_no);
      
      const url = `/packageOther/confirm-order/confirm-order?order_no=${this.order_no}&orderNumber=${this.orderNumber || 1}&table_number=${this.table_number}&order_used_coupon=${this.order_used_coupon}`
      
      wx.navigateTo({ url: url });
    },
    
    // 加载页面数据（先保证连锁选店再拉菜单，避免无 X-Shop-Id）
    async loadPageData(options) {
      if (options && options.order_no) {
        this.order_no = options.order_no;
        this.is_add_dishes = true;
      }
      
      if (options && options.orderNumber) {
        this.orderNumber = options.orderNumber;
        this.is_add_dishes = true;
      }
      if (options && options.order_used_coupon !== undefined && options.order_used_coupon !== '') {
        this.order_used_coupon = options.order_used_coupon;
      }
      
      await this.ensureShopForMenuPage();
      await this.loadShopAnnouncements(true);
      await this.checkBusinessHours();
      try {
        const raw = wx.getStorageSync('shopping_cart');
        this.shopping_card = Array.isArray(raw) ? raw : [];
      } catch (e) {
        this.shopping_card = [];
      }
      // 须在 dishEs 之前读入购物车：dishEs 同步分支会立刻 updateCar，否则缓存首屏会用空的 shopping_card
      this.dishEs();
    },
    
    // 检查订单
    async checkOrder() {
      this.isLoading = true;
      let res = { goods_list: [] };
      
      try {
        if (this.table_number) {
          res = await requestUtil({
            url: "/order/get",
            data: { table_number: this.table_number, transac_status: "unsettled" ,order_no:this.order_no || ''},
            method: "get"
          });
        }
        const list = res && res.goods_list;
        this.OrderStatus = Array.isArray(list) ? list.length > 0 : false;
      } catch (e) {
        this.OrderStatus = false;
      } finally {
        this.isLoading = false;
      }
    },
    
    // 检查订单状态
    async checkOrderStatus() {
      try {
        await this.checkOrder();
        
        if (this.OrderStatus) {
          wx.reLaunch({
            url: "/packageOther/order-details/details?table_number=" + this.table_number
          });
        }
      } catch (e) {
        wx.showToast({ title: "检查订单失败", icon: "none" });
      }
    },
    
    // 显示售罄提示
    showNotOnSaleTip() {
      wx.showToast({ title: '该商品已下架，无法选择', icon: 'none' });
    },
    showSoldOutTip() {
      wx.showToast({ title: '该商品已售罄', icon: 'none' });
    },
    resolveDiningTypeFromOptions(options) {
      const hasNumberPeople =
        options &&
        options.number_people != null &&
        String(options.number_people).trim() !== "";
      if (hasNumberPeople) {
        return "堂食";
      }
      let dining = "";
      if (options && options.dineInOrTakeOut != null && String(options.dineInOrTakeOut).trim() !== "") {
        try {
          dining = decodeURIComponent(String(options.dineInOrTakeOut));
        } catch (e) {
          dining = String(options.dineInOrTakeOut).trim();
        }
      }
      if (!dining && app.getStorageWithExpiry) {
        dining = app.getStorageWithExpiry("dineInOrTakeOut") || "";
      }
      if (!dining) {
        try {
          const raw = wx.getStorageSync("dineInOrTakeOut");
          if (raw === "堂食" || raw === "打包") dining = raw;
        } catch (e) {
          /* ignore */
        }
      }
      return dining || "堂食";
    },
    /**
     * 非扫码绑定门店的进入方式：须先进入选店页，避免按定位自动选错店
     * @returns {Promise<boolean>} true 表示已 redirect，调用方应中止 onLoad
     */
    async ensureShopSelectedForEntry(options) {
      const qrShopId = parseShopIdFromLaunchOptions(options);
      if (qrShopId != null) {
        await this.applyShopFromTableQr(qrShopId);
        return false;
      }

      const tableFromOptions =
        options && options.table_number != null
          ? String(options.table_number).trim()
          : "";
      let tableStored = "";
      try {
        tableStored = app.getStorageWithExpiry
          ? app.getStorageWithExpiry("table_number") || ""
          : wx.getStorageSync("table_number") || "";
      } catch (e) {
        tableStored = "";
      }
      const hasTableContext = !!(tableFromOptions || String(tableStored).trim());
      if (!hasTableContext) {
        clearShopQrBound();
      }

      if (isShopBoundFromQr()) {
        return false;
      }
      if (options && String(options.shop_picked || "").trim() === "1") {
        return false;
      }
      try {
        if (wx.getStorageSync(MENU_SHOP_MANUAL_KEY)) {
          return false;
        }
      } catch (e) {
        /* ignore */
      }

      try {
        const res = await requestUtil({
          url: "/shop/list",
          method: "get",
          showLoading: true,
        });
        if (!res || res.code !== 0 || !Array.isArray(res.list) || !res.list.length) {
          wx.showToast({ title: "暂无营业门店", icon: "none" });
          return true;
        }
      } catch (e) {
        wx.showToast({ title: "门店列表加载失败", icon: "none" });
        return true;
      }

      wx.redirectTo({
        url: "/packageOther/select-shop/select-shop?from=entry",
      });
      return true;
    },
    /**
     * 堂食直接进入点餐：未选人数则跳转选人数页
     * @returns {boolean} 已发起跳转
     */
    redirectToSelectNumberIfNeeded(options, diningType) {
      if (options && options.order_no) return false;
      if (
        options &&
        options.number_people != null &&
        String(options.number_people).trim() !== ""
      ) {
        return false;
      }
      if (diningType !== "堂食") return false;
      if (getValidDinersCount(app) != null) return false;

      const tn = this.table_number ? String(this.table_number).trim() : "";
      wx.redirectTo({
        url: `/packageOther/select_number/select_number?number=${encodeURIComponent(tn)}`,
      });
      return true;
    },
  },
  
  // 下拉刷新
  onPullDownRefresh() {
    this.scrollAutoTriggered = false;
    this.isInnerScrollEnabled = false; // 重置内部滚动状态
    this.outerScrollTop = 0;
    this.isOuterScrollAtTop = true;
    
    this.shopping_card = wx.getStorageSync('shopping_cart') || [];
    this.ensureShopForMenuPage().then(() => {
      this.checkBusinessHours();
    });
    this.dishEs();
    
    setTimeout(() => {
      uni.stopPullDownRefresh();
      this.getSwiperRealHeight();
    }, 1000);
  },

  
  async onShow() {
    if (typeof app.guardToQueueIfReview === "function") {
      const redirected = await app.guardToQueueIfReview();
      if (redirected) return;
    }
    this.dishStatusPageVisible = true;
    this.refreshMenuHeaderShop();
    // 从 AI 点餐等返回时：storage 已更新但内存 shopping_card 仍为切走前的状态，须同步
    this.syncShoppingCartFromStorage();
    if (this.skipFirstShowShopRefresh) {
      this.skipFirstShowShopRefresh = false;
      this.checkBusinessHours();
    } else {
      this.ensureShopForMenuPage().then(() => {
        this.loadShopAnnouncements(false);
        this.checkBusinessHours();
      });
    }
    startMenuCatalogSocket({
      onRefetchMenu: (batch) => this.refreshMenuFromSocketPush(batch),
      onBusinessChanged: (msg) => this.applyBusinessChangedFromSocket(msg),
      onAnnouncementChanged: () => this.loadShopAnnouncements(true),
    });
    this.startDishStatusPoller();
    this._dishStatusShowRefreshTimer = setTimeout(() => {
      this._dishStatusShowRefreshTimer = null;
      this.silentRefreshDishStatus();
    }, 900);
  },

  onHide() {
    this.showFarShopModal = false;
    this._farShopModalResolver = null;
    this.dishStatusPageVisible = false;
    stopMenuCatalogSocket();
    this.stopDishStatusPoller();
    this.stopAnnouncementTicker();
  },

  // 页面卸载
  onUnload() {
    this.showFarShopModal = false;
    this._farShopModalResolver = null;
    stopMenuCatalogSocket();
    this.stopDishStatusPoller();
    this.stopAnnouncementTicker();
    // 统一用 uni 移除监听
    uni.offWindowResize();
  },
  
  // 页面加载（仅做首屏必要逻辑，其余延后；onLoad 建议 < PAGE_LOAD_TARGET_MS，即 500ms）
  async onLoad(options) {
    if (typeof app.guardToQueueIfReview === "function") {
      const redirected = await app.guardToQueueIfReview({ force: true });
      if (redirected) return;
    }

    const shopRedirected = await this.ensureShopSelectedForEntry(options || {});
    if (shopRedirected) return;

    this.refreshMenuHeaderShop();
    this.syncMenuCarouselShopId();
    this.systemInfo = wx.getWindowInfo();
    this.calculateCssVars();

    const hasNumberPeople =
      options &&
      options.number_people != null &&
      String(options.number_people).trim() !== "";

    this.dineInOrTakeOut = this.resolveDiningTypeFromOptions(options);
    if (hasNumberPeople) {
      try {
        wx.setStorageSync("dineInOrTakeOut", "堂食");
        if (typeof app.setStorageWithExpiry === "function") {
          app.setStorageWithExpiry("dineInOrTakeOut", "堂食", 7 * 24 * 60);
        }
      } catch (e) {
        /* ignore */
      }
    } else {
      try {
        wx.setStorageSync("dineInOrTakeOut", this.dineInOrTakeOut);
        if (typeof app.setStorageWithExpiry === "function") {
          app.setStorageWithExpiry("dineInOrTakeOut", this.dineInOrTakeOut, 7 * 24 * 60);
        }
      } catch (e) {
        /* ignore */
      }
    }

    this.table_number =
      (options && options.table_number) ||
      (app.getStorageWithExpiry && app.getStorageWithExpiry("table_number")) ||
      "";
    try {
      if (!this.table_number) {
        this.table_number = wx.getStorageSync("table_number") || "";
      }
    } catch (e) {
      /* ignore */
    }

    if (this.redirectToSelectNumberIfNeeded(options, this.dineInOrTakeOut)) {
      return;
    }

    if (hasNumberPeople) {
      const np = parseInt(String(options.number_people).trim(), 10);
      if (Number.isFinite(np) && np > 0) {
        saveDinersCount(app, np);
      }
    }
    const isDineIn = this.dineInOrTakeOut === "堂食";
    const hasTableNumber = !!this.table_number;
    if (isDineIn && hasTableNumber && !(options && options.order_no)) {
      this.checkOrderStatus();
    }
    this.baseUrl = getBaseUrl();
    this.loadPageData(options);
  },
  onReady() {
    wx.onWindowResize(() => {
      this.calculateCssVars();
    });
    const readyDelay = DEFER_READY_DELAY_MS; // 延后任务控制在 PAGE_LOAD_TARGET_MS 内
    setTimeout(() => {
      this.getSwiperRealHeight();
    }, readyDelay);
  },

 
}
</script>

<style scoped>
/* 页面容器：基础布局 */
.page-container {
  display: flex;
  flex-direction: column;
  height: 100vh;
  /* 使用CSS变量 */
  --window-height: 100vh;
  --header-height: 155rpx;
  --bottom-height: 120rpx;
  --order-view-height: calc(100vh - var(--header-height) - var(--bottom-height));
}

/* 固定头部样式 */
.fixed-header {
  position: fixed;
  top: 0;
  left: 0;
  right: 0;
  background-color: #ffffff;
  z-index: 9998;
  
  box-shadow: 0 2rpx 10rpx rgba(0,0,0,0.05);
  height: var(--header-height);
  box-sizing: border-box;
}

/* 外层滚动容器：核心优化 */
.main-scroll {
  flex: 1;
  overflow-y: auto;
  z-index:995;
  padding-top: var(--header-height); /* 给固定头部留空间 */
  -webkit-overflow-scrolling: touch; /* 开启iOS弹性滚动 */
  touch-action: pan-y;
  /* 新增：确保滚动容器有足够高度 */
  min-height: calc(100vh - var(--header-height));
}

/* 轮播容器样式 */
.swiper-container {
  z-index: 995;
  width: 100%;
  box-sizing: border-box;
  flex-shrink: 0;
  position: relative;
 
}

/* 点餐区：核心sticky吸顶 */
.commodity-wrapper {
  position: sticky; /* 新增：关键吸顶属性 */
  top: var(--header-height); /* 吸顶位置对齐头部 */
  z-index: 995;
  background: #fff;
  width: 100%;
  will-change: position;
  transform: translateZ(0);
  box-sizing: border-box;
}


/* 点餐区布局容器 */
.commodity {
  display: flex;
  /* 继承父容器高度 */
  
}
/* 左侧菜单：未吸顶时用 sticky，吸顶后由 .sticky-sidebar-fixed 改为 fixed */
.sticky-sidebar {
  position: sticky;
  top: 0;
  height: var(--order-view-height);
  z-index: 10;
}
/* 吸顶时隐藏滚动区内的左侧栏，由页面级 .left-sidebar-fixed-layer 显示 */
.order-left-hidden {
  visibility: hidden;
}
/* 左侧分类栏：宽度 + 背景 */
.order-left {
  width: 200rpx;
  box-sizing: border-box;
  background-color: #f8f8f8;
}
/* 页面级吸顶左侧栏（必须在 scroll-view 外，fixed 才不随滚动） */
.left-sidebar-fixed-layer {
  position: fixed;
  left: 0;
  top: var(--header-height);
  width: 200rpx;
  height: var(--order-view-height);
  z-index: 996;
  background-color: #f8f8f8;
}
.fixed-sidebar-scroll {
  width: 100%;
  height: 100%;
  box-sizing: border-box;
}

/* 左侧滚动容器：核心样式 */
.scroll-Hei {
  
  overflow-y: auto;
  -webkit-overflow-scrolling: touch;
  will-change: scroll-position;
  transform: translateZ(0); /* 硬件加速 */
}

/* 右侧菜品列表容器 */
.order-right {
  flex: 1;
  overflow: visible; /* 允许溢出 */
}

/* 右侧商品滚动容器 */
.goods-scroll {
  height: 100%;
  overflow-y: auto;
  -webkit-overflow-scrolling: touch;
  will-change: scroll-position;
  transform: translateZ(0); /* 硬件加速 */
}
.goods-scroll[style*="pointer-events: none"] {
  touch-action: none;
}
/* 隐藏滚动条增强体验 */
::-webkit-scrollbar {
  width: 0;
  height: 0;
  color: transparent;
}

/* 距离过远提示弹窗：红色强调 */
.far-shop-modal-root{
  position: fixed;
  left: 0;
  right: 0;
  top: 0;
  bottom: 0;
  z-index: 1200;
  display: flex;
  align-items: center;
  justify-content: center;
}
.far-shop-modal-mask{
  position: absolute;
  left: 0;
  right: 0;
  top: 0;
  bottom: 0;
  background: rgba(0, 0, 0, 0.58);
}
.far-shop-modal-panel{
  position: relative;
  width: 78%;
  max-width: 620rpx;
  background: #fff;
  border-radius: 20rpx;
  padding: 32rpx 28rpx 26rpx;
  box-sizing: border-box;
  border: 2rpx solid #ffd6d6;
  box-shadow: 0 12rpx 36rpx rgba(211, 6, 6, 0.18);
}
.far-shop-modal-title{
  text-align: center;
  color: #d30606;
  font-size: 34rpx;
  font-weight: 700;
  margin-bottom: 16rpx;
}
.far-shop-modal-text{
  color: #d30606;
  background: #fff2f2;
  border-radius: 12rpx;
  font-size: 28rpx;
  line-height: 1.55;
  padding: 18rpx 20rpx;
  margin-bottom: 24rpx;
}
.far-shop-modal-shop-name{
  color: #b40000;
  font-weight: 700;
  font-size: 30rpx;
}
.far-shop-modal-actions{
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 18rpx;
}
.far-shop-btn{
  flex: 1;
  height: 76rpx;
  line-height: 76rpx;
  text-align: center;
  font-size: 28rpx;
  border-radius: 12rpx;
}
.far-shop-btn-cancel{
  background: #fff4f4;
  color: #c04f4f;
  border: 1rpx solid #f0bcbc;
}
.far-shop-btn-confirm{
  background: #d30606;
  color: #ffffff;
  font-weight: 600;
}

/* 数量徽章样式 */
.quantity {
  position: relative;
  display: inline-block;
  align-items: center;
  align-self: flex-end;
}

.spec-container {
  position: relative;
  display: inline-block;
}

.quantity-badge {
  width: 28rpx;
  height: 28rpx;
  background-color: #eb5941;
  border-radius: 50%;
  display: flex;
  align-items: center;
  justify-content: center;
  color: white;
  font-size: 18rpx;
  font-weight: bold;
  position: absolute;
  top: -8rpx;
  right: -8rpx;
  z-index: 1;
}

.spec-btn {
  width: 80rpx;
  height: 50rpx;
  line-height: 50rpx;
  font-size: 20rpx;
  padding: 0;
  margin: 0;
  background:linear-gradient(to right,#ff5117,#f0331a,#e10606,#d30606);
  color: #fff;
  border-radius: 8rpx;
  border: none;
  display: flex;
  align-items: center;
  justify-content: center;
  position: relative;
}

.spec-btn::after {
  border: none;
}

/* 售罄：占位与「选规格」按钮同宽，避免标题区拥挤 */
.spec-soldout-tag {
  width: 80rpx;
  height: 50rpx;
  line-height: 50rpx;
  text-align: center;
  font-size: 20rpx;
  color: #999;
  background: #f0f0f0;
  border-radius: 8rpx;
  box-sizing: border-box;
}

/* 顶部店名样式 */
.top-name{
  padding: 0 20rpx;
  display: flex;
  align-items: flex-start;
  margin-bottom: 30rpx;
}
.shop-entry{
  display: flex;
  flex-direction: column;
  min-width: 0;
  flex: 1;
}
.shop-entry--switchable:active {
  opacity: 0.88;
}
.shop-switch-hint {
  display: flex;
  flex-direction: row;
  align-items: center;
  flex-wrap: wrap;
  gap: 12rpx;
  margin-top: 6rpx;
  font-size: 24rpx;
  font-weight: 400;
  color: #999999;
}
.shop-km-prefix {
  color: #999999;
}
.shop-switch-action {
  color: #999999;
  font-weight: 600;
}
.shop-single-km {
  display: block;
  margin-top: 6rpx;
  font-size: 22rpx;
  font-weight: 400;
  color: #999999;
  line-height: 1.2;
}
.shop-entry-top{
  min-width: 0;
}
.shop-entry-title{
  display: block;
  font-size: 34rpx;
  font-weight: bold;
  line-height: 1.1;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

/* 堂食/打包：合并为一组，选中红底白字 */
.top-name-options{
  margin-left: auto;
  display: flex;
  align-items: stretch;
  border: 1rpx solid #e0e0e0;
  border-radius: 12rpx;
  overflow: hidden;
  background-color: #f5f5f5;
  margin-bottom: 20rpx;
}
.top-name-options .top-notice-option{
  margin: 0;
  padding: 12rpx 28rpx;
  font-size: 28rpx;
  border: none;
  border-radius: 0;
  color: #666;
  background-color: transparent;
  min-width: 80rpx;
  text-align: center;
}
.top-name-options .top-notice-option:first-child{
  border-right: 1rpx solid #e0e0e0;
}
.top-name-options .top-notice-option-active{
  background-color: #d30606 !important;
  color: #ffffff !important;
  font-weight: bold;
  border: none !important;
  border-right: 1rpx solid rgba(255,255,255,0.35) !important;
}

.top-notice{
  padding: 0 20rpx;
  display: flex;
  align-items: center;
  font-size: 28rpx;
  margin-bottom: 20rpx;
  color: #a1a1a1;
}
.top-notice:active{
  opacity: 0.88;
}
.top-notice-text-wrap{
  flex: 1;
  min-width: 0;
  overflow: hidden;
  white-space: nowrap;
}
.top-notice-text{
  display: inline-block;
  max-width: 100%;
}
.top-notice-text-marquee{
  padding-left: 100%;
  animation: notice-marquee 3s linear;
}
@keyframes notice-marquee{
  0% { transform: translateX(0); }
  100% { transform: translateX(-100%); }
}

/* 门店公告底部弹层（GET /announcement/list） */
.announcement-sheet-root{
  position: fixed;
  left: 0;
  right: 0;
  top: 0;
  bottom: 0;
  z-index: 10002;
}
.announcement-sheet-mask{
  position: absolute;
  left: 0;
  right: 0;
  top: 0;
  bottom: 0;
  background: rgba(0, 0, 0, 0.45);
}
.announcement-sheet-panel{
  position: absolute;
  left: 0;
  right: 0;
  bottom: 0;
  max-height: 78vh;
  background: #fff;
  border-radius: 28rpx 28rpx 0 0;
  box-shadow: 0 -10rpx 36rpx rgba(0, 0, 0, 0.1);
  display: flex;
  flex-direction: column;
  
}
.announcement-sheet-header{
  flex-shrink: 0;
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: 30rpx 36rpx 18rpx;
  border-bottom: 1rpx solid #f0f0f0;
}
.announcement-sheet-title{
  font-size: 40rpx;
  font-weight: 600;
  color: #1f1f1f;
  letter-spacing: 0.3rpx;
}
.announcement-sheet-close{
  padding: 8rpx 14rpx;
  font-size: 26rpx;
  color: #8a8a8a;
}
.announcement-sheet-body{
  flex: 1;
  /* 勿用 height:0+flex:1：微信里 scroll-view 常算成可视高度为 0，内容区整片空白 */
  min-height: 360rpx;
  max-height: calc(78vh - 120rpx);
  padding: 20rpx 36rpx 42rpx;
  box-sizing: border-box;
}
.announcement-meta{
  margin-bottom: 24rpx;
}
.announcement-meta-desc{
  display: block;
  font-size: 30rpx;
  font-weight: 600;
  color: #222;
  line-height: 1.45;
  padding: 4rpx 0;
}
.announcement-section-title{
  display: block;
  font-size: 31rpx;
  font-weight: 600;
  color: #222;
  margin-bottom: 16rpx;
}
.announcement-store-section{
  margin-bottom: 34rpx;
}
.announcement-store-line{
  display: flex;
  align-items: flex-start;
  margin-bottom: 10rpx;
  font-size: 27rpx;
  line-height: 1.72;
}
.announcement-store-label{
  color: #333;
  flex-shrink: 0;
}
.announcement-store-value{
  color: #585858;
  white-space: pre-wrap;
  word-break: break-word;
}
.announcement-store-actions{
  display: flex;
  gap: 20rpx;
  margin-top: 22rpx;
  margin-bottom: 8rpx;
}
.announcement-store-btn{
  flex: 1;
  height: 76rpx;
  border: 1rpx solid #e0e0e0;
  border-radius: 10rpx;
  display: flex;
  align-items: center;
  justify-content: center;
  font-size: 27rpx;
  color: #2f2f2f;
  background: #fff;
}
.announcement-store-btn:active{
  opacity: 0.85;
  transform: scale(0.99);
}
.announcement-dynamic-section{
  margin-top: 10rpx;
}
.announcement-rule-section{
  margin-bottom: 30rpx;
}
.announcement-rule-line{
  display: block;
  font-size: 26rpx;
  color: #565656;
  line-height: 1.78;
  margin-bottom: 6rpx;
  white-space: pre-wrap;
  word-break: break-word;
}
.announcement-rule-subtitle{
  display: block;
  margin: 6rpx 0 8rpx;
  font-size: 24rpx;
  color: #8f8f8f;
}
.announcement-rule-highlight{
  color: #2f2f2f;
  font-weight: 600;
}
.announcement-rule-note{
  margin-top: 4rpx;
  color: #4a4a4a;
}
.announcement-sheet-loading,
.announcement-sheet-empty{
  padding: 36rpx 0;
  text-align: center;
  font-size: 26rpx;
  color: #888;
}
.announcement-sheet-empty-tip{
  display: block;
  margin-top: 14rpx;
  font-size: 24rpx;
  color: #bbb;
}
.announcement-sheet-item{
  padding: 20rpx 0 24rpx;
  margin-bottom: 18rpx;
  border-bottom: 1rpx solid #f5f5f5;
}
.announcement-sheet-item:last-child{
  margin-bottom: 0;
  border-bottom: none;
}
.announcement-item-title{
  display: block;
  font-size: 28rpx;
  font-weight: 600;
  color: #303030;
  margin-bottom: 10rpx;
}
.announcement-item-body{
  
  color: #5b5b5b;
  
}
.announcement-item-text{
  white-space: pre-wrap;
  word-break: break-word;
}

.top-notice-left{
  display: flex;
  align-items: center;
}
.top-notice-left .top-notice-text{
  margin-right: 16rpx;
}
.top-notice-option{
  margin-right: 12rpx;
  padding: 8rpx 20rpx;
  border-radius: 8rpx;
  color: #a1a1a1;
  border: 1rpx solid #e0e0e0;
}
.top-notice-option-active{
  color: #d30606;
  border-color: #d30606;
  font-weight: bold;
}
/* 堂食/打包在 top-name 内的红底白字已写在 .top-name-options 下 */

.top-notice-show{
  margin-left: auto;
  flex-shrink: 0;
}

/* 分类文字样式 */
.itemize-text {
  font-size: 27rpx;
  padding: 30rpx 10rpx;
  display: flex;
  align-items: center;
  color: #6a6a6a;
  text-align: center;
}

.itemize-text text:nth-child(1) {
  flex: 1;
}

.itemize-text text:nth-child(2) {
  background-color: #eb5941;
  border-radius: 50%;
  font-size: 20rpx;
  color: #FFFFFF;
  width: 30rpx;
  height: 30rpx;
  display: flex;
  justify-content: center;
  align-items: center;
  margin-left: 2rpx;
}

/* 分类标题样式 */
.classif {
  font-size: 27rpx;
  padding: 30rpx 20rpx;
  color: #797979;
}

/* 菜品项样式 */
.classif-goods {
  display: flex;
  justify-content: space-between;
  padding: 0 20rpx;
  height: 150rpx;
  font-size: 30rpx;
  margin-bottom: 45rpx;
}

/* 菜品图片容器 */
.goods-image {
  position: relative;
  width: 150rpx;
  height: 150rpx;
}

.placeholder-img {
  width: 100%;
  height: 100%;
  background-color: #f5f5f5;
}

.real-img {
  position: absolute;
  top: 0;
  left: 0;
  width: 100%;
  height: 100%;
}

.goods-image image {
  display: block;
  width: 150rpx;
  height: 150rpx;
  border-radius: 10rpx;
}

/* 菜品价格区域 */
.goods-Price {
  flex: 1;
  position: relative;
  padding: 0 20rpx;
}

.goods-Price text {
  display: block;
}

.goods-name {
  display: flex;
  flex-direction: column;
  position: relative;
  top: 0;
}

.goods-name text:nth-child(1) {
  padding-bottom: 9rpx;
}

.unit-price {
  position: absolute;
  bottom: 0;
  display: flex;
  align-items: baseline;
}

.Bold {
  font-weight: 550;
  font-size: 28rpx;
}

.Symbol {
  font-size: 20rpx;
  color: #e60909;
}

.Unitprice {
  font-weight: 550;
  font-size: 28rpx;
  color: #e60909;
}

.unit {
  font-size: 21rpx;
  color: #e60909;
}

.Thinning {
  font-size: 21rpx;
  color: #cccccc;
}

/* 底部操作栏 */
.order-bottom {
  background-color: #fefefe;
  height: var(--bottom-height);
  position: fixed;
  left: 0;
  right: 0;
  box-shadow: 0rpx -1.9rpx 1rpx 1rpx #f9f9f9;
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: 0 20rpx;
  bottom: 0 !important;
  z-index: 996;
}

/* 购物车样式 */
.Shopping image {
  width: 75rpx;
  height: 75rpx;
  display: block;
}

.Shopping-left {
  width: 75rpx;
  height: 75rpx;
}

.Shopping {
  display: flex;
  align-items: center;
}

/* 用餐方式选择弹窗样式 */
.dining-modal {
  position: fixed;
  top: 0;
  left: 0;
  right: 0;
  bottom: 0;
  background-color: rgba(0, 0, 0, 0.5);
  display: flex;
  justify-content: center;
  align-items: center;
  z-index: 999;
}

.modal-content {
  width: 80%;
  background-color: #ffffff;
  border-radius: 20rpx;
  padding: 40rpx;
}

.modal-title {
  font-size: 34rpx;
  font-weight: bold;
  text-align: center;
  margin-bottom: 40rpx;
  color: #333;
}

.modal-options {
  display: flex;
  gap: 30rpx;
}

.modal-option {
  flex: 1;
  height: 100rpx;
  display: flex;
  justify-content: center;
  align-items: center;
  background-color: #f5f5f5;
  border-radius: 10rpx;
  font-size: 30rpx;
  font-weight: bold;
  color: #333;
  touch-action: manipulation;
}

.modal-option:active {
  background-color: #f7d45f;
}

/* 购物车数量 */
.Shopping-number {
  align-self: flex-start;
  background: #eb5941;
  color: #ffff;
  width: 40rpx;
  border-radius: 50rpx;
  text-align: center;
  font-size: 20rpx;
}

.Shopping-title {
  flex: 1;
  padding: 0 25rpx;
  color: #999999;
}

/* 非营业时底部：未营业 + 点击查看营业时间 */
.place-order-Business{
  background-color: #d30606;
  height: var(--bottom-height);
  position: fixed;
  left: 0;
  right: 0;
  box-shadow: 0rpx -1.9rpx 1rpx 1rpx #f9f9f9;
  display: flex;
  align-items: center;
  justify-content: center;
  padding: 0 28rpx;
  bottom: 0 !important;
  z-index: 996;
}
.place-order-Business--notice:active{
  opacity: 0.92;
}
.Business-notice-main{
  flex: 1;
  min-width: 0;
  display: flex;
  flex-direction: column;
  justify-content: center;
  align-items: center;
  text-align: center;
  gap: 8rpx;
}
.Business-notice-title{
  font-size: 32rpx;
  font-weight: 700;
  color: #fff;
  line-height: 1.2;
}
.Business-notice-sub{
  font-size: 24rpx;
  color: rgba(255, 255, 255, 0.9);
  line-height: 1.35;
}

/* 下单按钮 */
.place-order button {
  border: none;
  background:linear-gradient(to right,#ff5117,#f0331a,#e10606,#d30606);
  color: #fff;
  width: 200rpx;
  height: 75rpx;
  line-height: 75rpx;
  border-radius: 50rpx;
  font-weight: bold;
  z-index: 9;
}

/* 激活状态 */
.active {
  background-color: #FFFFFF;
  color: #000 !important;
  font-weight: bold;
  
}

/* 售罄/不可加购：仅弱化样式，保留整行点击（仍可打开详情） */
.not-on-sale {
  opacity: 0.72;
}

.onsale-tag {
  position: absolute;
  top: 0;
  left: 0;
  background-color: rgba(0, 0, 0, 0.7);
  color: white;
  font-size: 24rpx;
  padding: 5rpx 10rpx;
  border-radius: 5rpx 0 5rpx 0;
  z-index: 1;
}
</style>
