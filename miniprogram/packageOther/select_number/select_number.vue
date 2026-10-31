<template>
  <view class="page">
    <view class="body">
      <view class="head-block">
        
        <text class="head-title">堂食就餐人数</text>
        <text class="head-sub">请选择本次用餐人数，便于门店备餐与安排</text>
      </view>

      <view class="card table-card">
        <view class="table-row">
          <text class="table-label">当前信息</text>
        </view>
        <view class="table-pill" :class="{ 'table-pill--muted': !table_number }">
          <text class="table-pill-icon">桌</text>
          <text class="table-pill-text">{{
            table_number ? "台号 " + table_number : "现场堂食（未绑台号）"
          }}</text>
        </view>
      </view>

      <view class="card picker-card">
        <view class="section-head">
          <text class="section-title">就餐人数</text>
          <text class="section-hint">快捷 1～10 或自定义</text>
        </view>
        <view class="count-grid">
          <view
            v-for="n in people"
            :key="n"
            class="count-cell"
            :class="{ active: !useCustom && selectedPeople === n }"
            @click="selectCount(n)"
          >
            <text class="count-num">{{ n }}</text>
            <text class="count-unit">人</text>
          </view>
        </view>
        <view class="custom-row">
          <text class="custom-label">其他人数</text>
          <input
            class="custom-input"
            type="number"
            :placeholder="dinersPlaceholder"
            v-model="customInput"
            @focus="onCustomFocus"
            @input="onCustomInput"
          />
        </view>
        <view v-if="effectiveDiners != null" class="selected-hint">
          已选 <text class="selected-strong">{{ effectiveDiners }}</text> 位
        </view>
      </view>

      <view class="footer">
        <button
          class="primary-btn"
          :class="{ disabled: !canSubmit }"
          :disabled="!canSubmit"
          :hover-class="canSubmit ? 'primary-btn-hover' : 'none'"
          @click="stArt"
        >
          开始点餐
        </button>
        <text class="footer-tip">{{ footerTipText }}</text>
      </view>
    </view>
  </view>
</template>

<script>
import { requestUtil } from "../../utils/requestUtil.js";
import { saveDinersCount } from "../../utils/dinersCache.js";

const app = typeof getApp === "function" ? getApp() : null;

/** 自定义人数上下限（与快捷 1～10 一致为整数人） */
const DINERS_MIN = 1;
const DINERS_MAX = 99;

export default {
  data() {
    return {
      table_number: "",
      /** 快捷档位 1～10，与自定义互斥时为 null */
      selectedPeople: null,
      useCustom: false,
      customInput: "",
      people: [1, 2, 3, 4, 5, 6, 7, 8, 9, 10],
    };
  },
  computed: {
    dinersPlaceholder() {
      return `${DINERS_MIN}～${DINERS_MAX} 整数`;
    },
    /** 当前生效人数：处于自定义模式时解析输入框，否则取快捷档位 */
    effectiveDiners() {
      if (this.useCustom) {
        const raw = String(this.customInput || "").trim();
        if (!raw) return null;
        if (!/^\d+$/.test(raw)) return null;
        const n = parseInt(raw, 10);
        if (n < DINERS_MIN || n > DINERS_MAX) return null;
        return n;
      }
      return this.selectedPeople;
    },
    canSubmit() {
      return this.effectiveDiners != null;
    },
    footerTipText() {
      return `支持快捷 1～10 人或自定义 ${DINERS_MIN}～${DINERS_MAX} 人；确认后进入点餐页，未下单前可返回修改`;
    },
  },
  onLoad(e) {
    const raw = e && e.number != null ? String(e.number).trim() : "";
    this.table_number = raw || "";
    if (this.table_number) {
      this.checkOrderStatus();
    }
    /* 进入本页不恢复缓存人数，须用户重新选择后按钮才可点 */
  },
  methods: {
    selectCount(n) {
      this.useCustom = false;
      this.customInput = "";
      this.selectedPeople = n;
    },
    onCustomFocus() {
      this.useCustom = true;
      this.selectedPeople = null;
    },
    onCustomInput() {
      this.useCustom = true;
      this.selectedPeople = null;
    },
    stArt() {
      const diners = this.effectiveDiners;
      if (diners == null) {
        wx.showToast({
          title: `请选择人数或输入 ${DINERS_MIN}～${DINERS_MAX} 的整数`,
          icon: "none",
        });
        return;
      }
      saveDinersCount(app, diners);
      wx.setStorageSync("dineInOrTakeOut", "堂食");
      if (app && typeof app.setStorageWithExpiry === "function") {
        try {
          app.setStorageWithExpiry("dineInOrTakeOut", "堂食", 7 * 24 * 60);
        } catch (e) {
          /* 忽略 */
        }
      }
      const tn = this.table_number ? String(this.table_number).trim() : "";
      const qs = [
        `dineInOrTakeOut=${encodeURIComponent("堂食")}`,
        `number_people=${encodeURIComponent(String(diners))}`,
      ];
      if (tn) qs.push(`table_number=${encodeURIComponent(tn)}`);
      wx.reLaunch({
        url: `/pages/home-page/page?${qs.join("&")}`,
      });
    },
    async verifyTableNumber(tableNumber) {
      try {
        const res = await requestUtil({
          url: "/order/table_verify",
          data: { number: tableNumber },
          method: "get",
          showLoading: false,
        });
        return res.code;
      } catch (e) {
        console.error("验证台号失败:", e);
        return false;
      }
    },
    async checkOrderStatus() {
      if (!this.table_number) return;
      try {
        const isValid = await this.verifyTableNumber(this.table_number);
        if (isValid !== 0) {
          wx.showToast({
            title: "无效的桌台号",
            icon: "none",
            duration: 2000,
          });
          setTimeout(() => {
            wx.reLaunch({ url: "/pages/index/index" });
          }, 1000);
          return;
        }
        const res = await requestUtil({
          url: "/order/get",
          data: { table_number: this.table_number, transac_status: "unsettled" },
          method: "get",
          showLoading: false,
        });
        if (res && res.goods_list && res.goods_list.length > 0) {
          wx.redirectTo({
            url: "/packageOther/order-details/details?table_number=" + this.table_number,
          });
          wx.hideLoading();
        }
      } catch (e) {
        console.error("检查订单状态失败:", e);
      }
    },
  },
};
</script>

<style scoped>
.page {
  min-height: 100vh;
  background: #fff5f2;
  box-sizing: border-box;
}

.body {
  padding: 24rpx 28rpx 48rpx;
  padding-bottom: calc(48rpx + env(safe-area-inset-bottom));
  box-sizing: border-box;
}

.head-block {
  margin-bottom: 28rpx;
}

.brand {
  display: block;
  font-size: 26rpx;
  color: #b32424;
  font-weight: 600;
  letter-spacing: 2rpx;
  margin-bottom: 8rpx;
}

.head-title {
  display: block;
  font-size: 40rpx;
  font-weight: 600;
  color: #222;
}

.head-sub {
  display: block;
  margin-top: 12rpx;
  font-size: 26rpx;
  color: #888;
  line-height: 1.5;
}

.card {
  background: #fff;
  border-radius: 20rpx;
  padding: 28rpx 24rpx 32rpx;
  margin-bottom: 24rpx;
  box-shadow: 0 4rpx 16rpx rgba(0, 0, 0, 0.06);
}

.table-row {
  margin-bottom: 16rpx;
}

.table-label {
  font-size: 28rpx;
  font-weight: 600;
  color: #333;
}

.table-pill {
  display: flex;
  align-items: center;
  padding: 20rpx 22rpx;
  border-radius: 16rpx;
  background: linear-gradient(135deg, #fff5f3 0%, #ffe8e4 100%);
  border: 1rpx solid rgba(179, 36, 36, 0.12);
}

.table-pill--muted {
  background: #fafafa;
  border-color: #eee;
}

.table-pill-icon {
  width: 48rpx;
  height: 48rpx;
  line-height: 48rpx;
  text-align: center;
  font-size: 24rpx;
  color: #fff;
  background: #e74c3c;
  border-radius: 12rpx;
  margin-right: 16rpx;
  flex-shrink: 0;
}

.table-pill--muted .table-pill-icon {
  background: #bbb;
}

.table-pill-text {
  flex: 1;
  font-size: 28rpx;
  color: #333;
  line-height: 1.4;
}

.section-head {
  display: flex;
  align-items: baseline;
  justify-content: space-between;
  margin-bottom: 24rpx;
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

.count-grid {
  display: flex;
  flex-wrap: wrap;
  margin: -10rpx;
}

.count-cell {
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: flex-start;
  width: 20%;
  padding: 10rpx;
  box-sizing: border-box;
}

.count-num {
  width: 100%;
  text-align: center;
  padding: 28rpx 0 8rpx;
  font-size: 40rpx;
  font-weight: 600;
  color: #333;
  background: #fafafa;
  border-radius: 16rpx;
  border: 2rpx solid #eee;
  box-sizing: border-box;
}

.count-unit {
  margin-top: 6rpx;
  font-size: 22rpx;
  color: #999;
}

.count-cell.active .count-num {
  border-color: #e74c3c;
  background: #fff5f3;
  color: #e74c3c;
}

.count-cell.active .count-unit {
  color: #e74c3c;
}

.custom-row {
  display: flex;
  align-items: center;
  margin-top: 28rpx;
  padding-top: 28rpx;
  border-top: 1rpx solid #f0f0f0;
}

.custom-label {
  font-size: 28rpx;
  color: #666;
  width: 160rpx;
  flex-shrink: 0;
}

.custom-input {
  flex: 1;
  height: 72rpx;
  border: 1rpx solid #eee;
  border-radius: 12rpx;
  padding: 0 20rpx;
  font-size: 28rpx;
  box-sizing: border-box;
  background: #fafafa;
}

.selected-hint {
  margin-top: 24rpx;
  text-align: center;
  font-size: 26rpx;
  color: #666;
}

.selected-strong {
  color: #e74c3c;
  font-weight: 600;
}

.footer {
  margin-top: 12rpx;
}

.primary-btn {
  width: 100%;
  background: #e74c3c;
  color: #fff;
  font-size: 32rpx;
  padding: 22rpx 0;
  border-radius: 44rpx;
  border: none;
  font-weight: 500;
}

.primary-btn::after {
  border: none;
}

.primary-btn-hover {
  opacity: 0.92;
}

.primary-btn.disabled,
.primary-btn[disabled] {
  background: #e0e0e0 !important;
  color: #999 !important;
  opacity: 1;
}

.footer-tip {
  display: block;
  margin-top: 20rpx;
  font-size: 22rpx;
  color: #999;
  line-height: 1.5;
  text-align: center;
}
</style>
