<template>
  <view class="combo-page" v-if="loaded">
    <view class="combo-header-card">
      <image
        class="combo-cover"
        :src="headerImageUrl"
        mode="aspectFill"
        lazy-load
      ></image>
      <view class="combo-header-info">
        <text class="combo-name">{{ headerName }}</text>
        <view class="combo-price-row">
          <text class="combo-price">¥{{ unitPriceDisplay }}</text>
          <text class="combo-unit">/{{ headerUnit }}</text>
          <text v-if="showOriginalUnitPrice" class="combo-original">原价 ¥{{ originalUnitPriceDisplay }}</text>
        </view>
      </view>
    </view>

    <scroll-view scroll-y class="combo-scroll" :show-scrollbar="false">
      <view v-if="fixedItems.length" class="combo-section">
        <text class="section-title">套餐包含</text>
        <view class="fixed-list">
          <view class="fixed-row" v-for="(it, idx) in fixedItems" :key="'f-' + idx">
            <text class="fixed-name">{{ itemName(it) }}</text>
            <text class="fixed-qty">×{{ itemQtyPerCombo(it) }}</text>
          </view>
        </view>
      </view>

      <view
        class="combo-section"
        v-for="g in groups"
        :key="g.groupKey"
      >
        <view class="section-head">
          <text class="section-title">{{ g.title || g.groupKey }}</text>
          <text class="section-hint">{{ groupPickHint(g) }}</text>
        </view>
        <view class="option-grid">
          <view
            v-for="it in g.options"
            :key="g.groupKey + '-' + itemDishId(it)"
            class="option-chip"
            :class="{
              'option-chip--on': isPicked(g.groupKey, it),
              'option-chip--disabled': !itemSelectable(it),
            }"
            @tap="onToggleGroupItem(g, it)"
          >
            <text class="option-name">{{ itemName(it) }}</text>
            <text v-if="itemExtraPrice(it) > 0" class="option-extra">+¥{{ itemExtraPrice(it) }}</text>
            <text v-if="!itemSelectable(it)" class="option-tag">售罄</text>
          </view>
        </view>
      </view>

      <view v-if="hasSpecification" class="combo-section spec-section">
        <text class="section-title">规格</text>
        <view
          v-for="group in specificationGroups"
          :key="group.key"
          class="spec-group"
        >
          <text class="spec-title">{{ group.key }}</text>
          <view class="spec-options">
            <view
              v-for="(opt, oi) in group.options"
              :key="group.key + '-' + oi"
              class="spec-chip"
              :class="{ 'spec-chip--on': isSpecPicked(group.key, opt) }"
              @tap.stop="onPickSpec(group.key, opt)"
            >
              <text>{{ opt }}</text>
            </view>
          </view>
        </view>
      </view>

      <view class="combo-section qty-section">
        <text class="section-title">份数</text>
        <view class="qty-row">
          <image class="qty-btn" :src="staticUrl('tab/jianhao.png')" mode="widthFix" @tap="changeQty(-1)"></image>
          <text class="qty-num">{{ quantity }}</text>
          <image class="qty-btn" :src="staticUrl('tab/jia.png')" mode="widthFix" @tap="changeQty(1)"></image>
        </view>
      </view>
      <view class="scroll-pad"></view>
    </scroll-view>

    <view class="combo-footer">
      <view class="footer-price">
        <text class="footer-label">合计</text>
        <text class="footer-amount">¥{{ totalPriceDisplay }}</text>
        <text v-if="showOriginalTotalPrice" class="footer-original">原价 ¥{{ originalTotalPriceDisplay }}</text>
        <text v-if="priceLoading" class="footer-calc">试算中…</text>
      </view>
      <button class="footer-btn" :disabled="submitting || !priceReady" @tap="onAddToCart">
        {{ submitting ? "处理中…" : "加入购物车" }}
      </button>
    </view>
  </view>

  <view class="combo-loading" v-else-if="loadError">
    <text class="load-err-text">{{ loadError }}</text>
    <button class="load-back-btn" @tap="goBack">返回</button>
  </view>
  <view class="combo-loading" v-else>
    <text>加载中…</text>
  </view>
</template>

<script>
import { staticUrl } from "../../utils/staticAssetUrl.js";
import { dishImageUrlDetail } from "../../utils/imageUrl.js";
import {
  fetchComboDetail,
  buildDefaultComboSelections,
  validateComboSelections,
  calcComboPrice,
  buildComboCartItem,
  componentCanPick,
  componentDishId,
  computeComboOriginalUnitPrice,
  recalcComboCartLineTotal,
} from "../../utils/comboMeal.js";
import {
  parseDishSpecification,
  buildDefaultSelectedSpicy,
  validateSelectedSpicy,
  resolveComboHeaderSpecification,
} from "../../utils/dishSpecification.js";

export default {
  data() {
    return {
      dishId: null,
      catIndex: 0,
      dishIndex: 0,
      cid: "",
      dishSnapshot: null,
      detail: null,
      selections: {},
      quantity: 1,
      totalPrice: 0,
      originalTotalPrice: 0,
      priceReady: false,
      priceLoading: false,
      loaded: false,
      loadError: "",
      submitting: false,
      _priceTimer: null,
      specification: null,
      selectedSpicy: {},
    };
  },
  computed: {
    hasSpecification() {
      return (
        this.specification &&
        typeof this.specification === "object" &&
        Object.keys(this.specification).length > 0
      );
    },
    specificationGroups() {
      if (!this.hasSpecification) return [];
      return Object.keys(this.specification).map((key) => ({
        key,
        options: Array.isArray(this.specification[key])
          ? this.specification[key]
          : [],
      }));
    },
    fixedItems() {
      return (this.detail && this.detail.fixedItems) || [];
    },
    groups() {
      return (this.detail && this.detail.groups) || [];
    },
    headerDish() {
      return (this.detail && (this.detail.header || this.detail.headerDish)) || {};
    },
    headerName() {
      const h = this.headerDish;
      return h.name || h.dishName || (this.dishSnapshot && this.dishSnapshot.name) || "套餐";
    },
    headerUnit() {
      const h = this.headerDish;
      return h.unit || (this.dishSnapshot && this.dishSnapshot.unit) || "份";
    },
    headerImageUrl() {
      const h = this.headerDish;
      const img = h.image || (this.dishSnapshot && this.dishSnapshot.image);
      if (!img) return staticUrl("images/default-avatar.png");
      if (String(img).startsWith("http")) return img;
      return dishImageUrlDetail(img);
    },
    unitPriceDisplay() {
      const d = this.detail || {};
      const p = Number(
        d.baseUnitPrice != null ? d.baseUnitPrice : this.headerDish.unitprice
      );
      return Number.isFinite(p) ? p.toFixed(2) : "0.00";
    },
    totalPriceDisplay() {
      const p = Number(this.totalPrice);
      return Number.isFinite(p) ? p.toFixed(2) : "0.00";
    },
    originalUnitPrice() {
      return computeComboOriginalUnitPrice(this.detail, this.selections);
    },
    originalUnitPriceDisplay() {
      const p = this.originalUnitPrice;
      return Number.isFinite(p) ? p.toFixed(2) : "0.00";
    },
    originalTotalPriceDisplay() {
      const p = Number(this.originalTotalPrice);
      return Number.isFinite(p) ? p.toFixed(2) : "0.00";
    },
    showOriginalUnitPrice() {
      const orig = this.originalUnitPrice;
      const cur = Number(
        (this.detail && this.detail.baseUnitPrice != null)
          ? this.detail.baseUnitPrice
          : this.headerDish.unitprice
      );
      return orig > 0 && orig > cur + 0.009;
    },
    showOriginalTotalPrice() {
      const orig = Number(this.originalTotalPrice);
      const cur = Number(this.totalPrice);
      return orig > 0 && orig > cur + 0.009;
    },
  },
  onLoad(options) {
    const dishId = Number(options && options.dishId);
    if (!Number.isFinite(dishId) || dishId <= 0) {
      this.loadError = "参数错误";
      return;
    }
    this.dishId = dishId;
    this.catIndex = Number(options.catIndex) || 0;
    this.dishIndex = Number(options.dishIndex) || 0;
    this.cid = options.cid != null ? String(options.cid) : "";
    try {
      const snap = options.dishSnap ? decodeURIComponent(options.dishSnap) : "";
      if (snap) this.dishSnapshot = JSON.parse(snap);
    } catch (e) {
      this.dishSnapshot = null;
    }
    this.bootstrap();
  },
  onUnload() {
    if (this._priceTimer) clearTimeout(this._priceTimer);
  },
  methods: {
    staticUrl,
    goBack() {
      wx.navigateBack();
    },
    initComboSpecification() {
      const raw = resolveComboHeaderSpecification(
        this.headerDish,
        this.dishSnapshot
      );
      this.specification = parseDishSpecification(raw);
      this.selectedSpicy = buildDefaultSelectedSpicy(this.specification);
    },
    isSpecPicked(specKey, val) {
      return this.selectedSpicy && this.selectedSpicy[specKey] === val;
    },
    onPickSpec(specKey, val) {
      this.selectedSpicy = {
        ...(this.selectedSpicy || {}),
        [specKey]: val,
      };
    },
    updateOriginalTotal(priceResult) {
      const qty = Math.max(1, Number(this.quantity) || 1);
      const apiOrig = priceResult && Number(priceResult.original_price);
      if (Number.isFinite(apiOrig) && apiOrig > 0) {
        this.originalTotalPrice = Math.round(apiOrig * 100) / 100;
        return;
      }
      const unit = computeComboOriginalUnitPrice(this.detail, this.selections);
      this.originalTotalPrice =
        unit > 0 ? Math.round(unit * qty * 100) / 100 : 0;
    },
    itemDishId(it) {
      return componentDishId(it) || 0;
    },
    itemName(it) {
      return it.name || it.dishName || "菜品";
    },
    itemQtyPerCombo(it) {
      return Number(it.qtyPerCombo != null ? it.qtyPerCombo : it.qty_per_combo) || 1;
    },
    itemExtraPrice(it) {
      const n = Number(it.extraPrice != null ? it.extraPrice : it.extra_price);
      return Number.isFinite(n) && n > 0 ? Math.round(n * 100) / 100 : 0;
    },
    itemSelectable(it) {
      return componentCanPick(it);
    },
    groupPickHint(g) {
      if (g.minPick === g.maxPick && g.minPick === 1) return "必选1项";
      if (g.minPick === g.maxPick) return `必选${g.minPick}项`;
      return `选${g.minPick}-${g.maxPick}项`;
    },
    isPicked(groupKey, it) {
      const id = this.itemDishId(it);
      const arr = this.selections[groupKey] || [];
      return arr.includes(id);
    },
    onToggleGroupItem(g, it) {
      if (!this.itemSelectable(it)) {
        wx.showToast({ title: "该选项不可选", icon: "none" });
        return;
      }
      const key = g.groupKey;
      const id = this.itemDishId(it);
      let arr = [...(this.selections[key] || [])];
      const idx = arr.indexOf(id);
      if (idx >= 0) {
        arr.splice(idx, 1);
      } else {
        if (g.maxPick <= 1) {
          arr = [id];
        } else {
          if (arr.length >= g.maxPick) {
            wx.showToast({ title: `最多选${g.maxPick}项`, icon: "none" });
            return;
          }
          arr.push(id);
        }
      }
      this.$set(this.selections, key, arr);
      this.updateOriginalTotal();
      this.scheduleCalcPrice();
    },
    changeQty(delta) {
      const next = this.quantity + delta;
      if (next < 1 || next > 99) return;
      this.quantity = next;
      this.updateOriginalTotal();
      this.scheduleCalcPrice();
    },
    scheduleCalcPrice() {
      if (this._priceTimer) clearTimeout(this._priceTimer);
      this.priceLoading = true;
      this._priceTimer = setTimeout(() => {
        this._priceTimer = null;
        this.refreshPrice();
      }, 280);
    },
    async bootstrap() {
      try {
        const detail = await fetchComboDetail(this.dishId);
        if (!detail.ok) {
          this.loadError = detail.message || "套餐不可用";
          return;
        }
        this.detail = detail;
        this.selections = buildDefaultComboSelections(detail);
        this.initComboSpecification();
        this.loaded = true;
        this.updateOriginalTotal();
        await this.refreshPrice();
      } catch (e) {
        this.loadError = "加载失败，请重试";
      }
    },
    async refreshPrice() {
      const valid = validateComboSelections(this.detail, this.selections);
      if (!valid.ok) {
        this.priceReady = false;
        this.priceLoading = false;
        return;
      }
      this.priceLoading = true;
      try {
        const pr = await calcComboPrice({
          comboId: this.detail.comboId,
          quantity: this.quantity,
          comboSelections: this.selections,
        });
        if (pr.ok) {
          this.totalPrice = pr.total_price;
          this.updateOriginalTotal(pr);
          this.priceReady = true;
        } else {
          this.priceReady = false;
          wx.showToast({ title: pr.message || "试算失败", icon: "none" });
        }
      } catch (e) {
        this.priceReady = false;
      } finally {
        this.priceLoading = false;
      }
    },
    async onAddToCart() {
      if (this.submitting || !this.priceReady) return;
      const valid = validateComboSelections(this.detail, this.selections);
      if (!valid.ok) {
        wx.showToast({ title: valid.message, icon: "none" });
        return;
      }
      const specValid = validateSelectedSpicy(
        this.specification,
        this.selectedSpicy
      );
      if (!specValid.ok) {
        wx.showToast({ title: specValid.message, icon: "none" });
        return;
      }
      this.submitting = true;
      try {
        const pr = await calcComboPrice({
          comboId: this.detail.comboId,
          quantity: this.quantity,
          comboSelections: this.selections,
        });
        if (!pr.ok) {
          wx.showToast({ title: pr.message || "价格校验失败", icon: "none" });
          return;
        }
        const dish = this.dishSnapshot || { id: this.dishId, name: this.headerName };
        const line = buildComboCartItem({
          dish,
          detail: this.detail,
          selections: this.selections,
          quantity: this.quantity,
          totalPrice: pr.total_price,
          catIndex: this.catIndex,
          dishIndex: this.dishIndex,
          cid: this.cid,
          selectedSpicy: this.selectedSpicy,
        });
        let cart = [];
        try {
          const raw = wx.getStorageSync("shopping_cart");
          cart = Array.isArray(raw) ? raw : [];
        } catch (e) {
          cart = [];
        }
        const existIdx = cart.findIndex((c) => c.cartKey && c.cartKey === line.cartKey);
        if (existIdx >= 0) {
          const merged = {
            ...cart[existIdx],
            quantity: cart[existIdx].quantity + line.quantity,
          };
          const recalc = await recalcComboCartLineTotal(merged);
          cart[existIdx] = recalc;
        } else {
          cart.push(line);
        }
        wx.setStorageSync("shopping_cart", cart);
        wx.showToast({ title: "已加入购物车", icon: "success" });
        setTimeout(() => wx.navigateBack(), 400);
      } catch (e) {
        wx.showToast({ title: "加入失败", icon: "none" });
      } finally {
        this.submitting = false;
      }
    },
  },
};
</script>

<style scoped>
.combo-page {
  min-height: 100vh;
  background: #f5f5f5;
  display: flex;
  flex-direction: column;
  padding-bottom: calc(140rpx + env(safe-area-inset-bottom));
  box-sizing: border-box;
}
.combo-header-card {
  display: flex;
  padding: 24rpx 28rpx;
  background: #fff;
  border-bottom: 1rpx solid #eee;
}
.combo-cover {
  width: 160rpx;
  height: 160rpx;
  border-radius: 12rpx;
  flex-shrink: 0;
  background: #f0f0f0;
}
.combo-header-info {
  flex: 1;
  margin-left: 24rpx;
  display: flex;
  flex-direction: column;
  justify-content: center;
}
.combo-name {
  font-size: 34rpx;
  font-weight: 600;
  color: #222;
  line-height: 1.35;
}
.combo-price-row {
  margin-top: 12rpx;
  display: flex;
  flex-wrap: wrap;
  align-items: baseline;
  gap: 8rpx 16rpx;
}
.combo-price {
  font-size: 36rpx;
  font-weight: 700;
  color: #e10606;
}
.combo-unit {
  font-size: 24rpx;
  color: #999;
}
.combo-original {
  font-size: 26rpx;
  color: #999;
  text-decoration: line-through;
}
.combo-scroll {
  flex: 1;
  height: calc(100vh - 220rpx - 140rpx);
  box-sizing: border-box;
}
.combo-section {
  margin: 20rpx 24rpx 0;
  padding: 24rpx;
  background: #fff;
  border-radius: 16rpx;
}
.section-head {
  display: flex;
  align-items: baseline;
  justify-content: space-between;
  margin-bottom: 16rpx;
}
.section-title {
  font-size: 30rpx;
  font-weight: 600;
  color: #333;
}
.section-hint {
  font-size: 24rpx;
  color: #999;
}
.fixed-row {
  display: flex;
  justify-content: space-between;
  padding: 12rpx 0;
  font-size: 28rpx;
  color: #555;
  border-bottom: 1rpx solid #f5f5f5;
}
.fixed-row:last-child {
  border-bottom: none;
}
.fixed-qty {
  color: #999;
}
.option-grid {
  display: flex;
  flex-wrap: wrap;
  gap: 16rpx;
}
.option-chip {
  padding: 16rpx 24rpx;
  border-radius: 12rpx;
  border: 1rpx solid #e0e0e0;
  background: #fafafa;
  max-width: 100%;
  box-sizing: border-box;
}
.option-chip--on {
  border-color: #e10606;
  background: #fff5f2;
  color: #e10606;
}
.option-chip--disabled {
  opacity: 0.45;
}
.option-name {
  font-size: 26rpx;
}
.option-extra {
  display: block;
  font-size: 22rpx;
  color: #e10606;
  margin-top: 4rpx;
}
.option-tag {
  display: block;
  font-size: 20rpx;
  color: #999;
  margin-top: 4rpx;
}
.spec-group {
  margin-bottom: 20rpx;
}
.spec-group:last-child {
  margin-bottom: 0;
}
.spec-title {
  display: block;
  font-size: 26rpx;
  color: #666;
  margin-bottom: 12rpx;
}
.spec-options {
  display: flex;
  flex-wrap: wrap;
  gap: 16rpx;
}
.spec-chip {
  padding: 16rpx 28rpx;
  border-radius: 12rpx;
  border: 1rpx solid #e0e0e0;
  background: #fafafa;
  font-size: 26rpx;
  color: #333;
}
.spec-chip--on {
  border-color: #e10606;
  background: #fff5f2;
  color: #e10606;
}
.qty-section .qty-row {
  display: flex;
  align-items: center;
  justify-content: flex-end;
  gap: 28rpx;
  margin-top: 8rpx;
}
.qty-btn {
  width: 56rpx;
  height: 56rpx;
}
.qty-num {
  font-size: 32rpx;
  font-weight: 600;
  min-width: 48rpx;
  text-align: center;
}
.scroll-pad {
  height: 40rpx;
}
.combo-footer {
  position: fixed;
  left: 0;
  right: 0;
  bottom: 0;
  padding: 16rpx 24rpx calc(16rpx + env(safe-area-inset-bottom));
  background: #fff;
  box-shadow: 0 -4rpx 20rpx rgba(0, 0, 0, 0.06);
  display: flex;
  align-items: center;
  gap: 20rpx;
  z-index: 10;
}
.footer-price {
  flex: 1;
  min-width: 0;
}
.footer-label {
  font-size: 24rpx;
  color: #999;
  margin-right: 8rpx;
}
.footer-amount {
  font-size: 36rpx;
  font-weight: 700;
  color: #e10606;
}
.footer-original {
  display: block;
  font-size: 24rpx;
  color: #999;
  text-decoration: line-through;
  margin-top: 4rpx;
}
.footer-calc {
  display: block;
  font-size: 22rpx;
  color: #bbb;
  margin-top: 4rpx;
}
.footer-btn {
  flex-shrink: 0;
  width: 260rpx;
  height: 80rpx;
  line-height: 80rpx;
  margin: 0;
  padding: 0;
  border: none;
  border-radius: 40rpx;
  background: linear-gradient(to right, #ff5117, #e10606);
  color: #fff;
  font-size: 30rpx;
  font-weight: 600;
}
.footer-btn[disabled] {
  opacity: 0.55;
}
.footer-btn::after {
  border: none;
}
.combo-loading {
  min-height: 60vh;
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  color: #999;
  font-size: 28rpx;
}
.load-err-text {
  margin-bottom: 24rpx;
  padding: 0 48rpx;
  text-align: center;
}
.load-back-btn {
  font-size: 28rpx;
}
</style>
