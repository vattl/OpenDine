<template>
  <view class="recharge-page">
    <view class="balance-card">
      <view class="balance-label">当前余额（元）</view>
      <view class="balance-value">{{ displayBalance }}</view>
      <view class="balance-tip">充值金额实时到账后可用于门店余额支付</view>
    </view>

    <view class="section">
      <view class="section-title">选择金额</view>
      <view class="amount-grid">
        <view
          v-for="tier in presetTiers"
          :key="tier.amount"
          class="amount-cell"
          :class="{ active: selectedPreset === tier.amount && !useCustom }"
          @click="pickPreset(tier.amount)"
        >
          <text class="amount-cell-main">¥{{ tier.amount }}</text>
          <text v-if="tier.gift > 0" class="amount-cell-gift">送¥{{ tier.gift }}</text>
        </view>
      </view>
      <view class="custom-row">
        <text class="custom-label">其他金额</text>
        <input
          class="custom-input"
          type="digit"
          v-model="customInput"
          :placeholder="amountPlaceholder"
          @focus="onCustomFocus"
          @input="onCustomInput"
        />
      </view>
    </view>

    <view class="footer">
      <view class="pay-summary">应付：<text class="pay-yuan">¥{{ payAmountText }}</text></view>
      <view v-if="expectedGiftYuan > 0" class="gift-hint">
        活动赠送约 <text class="gift-yuan">¥{{ expectedGiftText }}</text>（以实际到账为准）
      </view>
      <button class="primary-btn" :loading="paying" :disabled="!canSubmit" @click="submitRecharge">
        {{ rechargeButtonLabel }}
      </button>
      <view v-if="rechargePayBlockedMsg" class="footer-tip footer-tip--warn">{{ rechargePayBlockedMsg }}</view>
      <view class="footer-tip">若未及时到账请稍后再试或联系门店。</view>
    </view>

    <view class="section history-section">
      <view class="section-title">充值记录</view>
      <view class="history-sub">最近 20 条（含微信充值与门店入账）</view>
      <view class="history-loading" v-if="historyLoading">加载中…</view>
      <view v-else-if="!historyList.length" class="history-empty">暂无记录</view>
      <view v-else class="history-list">
        <view
          v-for="(row, idx) in historyList"
          :key="idx"
          class="history-row"
        >
          <view class="history-main">
            <text class="history-amount">+{{ formatHistoryAmount(row) }}</text>
            <text class="history-meta">{{ historyChannelText(row.channel) }} · {{ historyStatusText(row.status) }}</text>
          </view>
          <text class="history-time">{{ formatHistoryTime(row) }}</text>
        </view>
      </view>
    </view>
  </view>
</template>

<script>
import { requestUtil } from "../../utils/requestUtil.js";
import { formatBalanceForDisplay } from "../../utils/formatBalance.js";
import {
  rechargeCreateAndGetPayParams,
  RECHARGE_AMOUNT_MIN,
  RECHARGE_AMOUNT_MAX,
  RECHARGE_GIFT_TIERS,
  giftForRechargeAmountYuan,
} from "../../utils/rechargePay.js";
import {
  fetchPaymentCapabilities,
  isWechatPayAvailable,
  resolvePaymentApiErrorMessage,
  resolveWechatPayDisabledMessage,
  PAYMENT_ONLINE_DISABLED_CODE,
  PAYMENT_CHANNEL_DISABLED_CODE,
  PAYMENT_WECHAT_MERCHANT_MISSING_CODE,
} from "../../utils/paymentCapabilities.js";

const app = getApp();

export default {
  data() {
    return {
      presetTiers: RECHARGE_GIFT_TIERS,
      selectedPreset: 200,
      useCustom: false,
      customInput: "",
      balanceYuan: null,
      paying: false,
      historyList: [],
      historyLoading: false,
      paymentCapabilities: null,
    };
  },
  computed: {
    rechargePayBlockedMsg() {
      const c = this.paymentCapabilities;
      if (c == null) return "";
      if (!isWechatPayAvailable(c)) {
        return resolveWechatPayDisabledMessage(c);
      }
      return "";
    },
    rechargeButtonLabel() {
      if (this.rechargePayBlockedMsg) return this.rechargePayBlockedMsg;
      return "微信支付充值";
    },
    amountPlaceholder() {
      return `${RECHARGE_AMOUNT_MIN}～${RECHARGE_AMOUNT_MAX}`;
    },
    displayBalance() {
      const b = this.balanceYuan;
      if (b == null || !Number.isFinite(Number(b))) return "0";
      return formatBalanceForDisplay(b);
    },
    payAmountYuan() {
      if (this.useCustom) {
        const v = parseFloat(String(this.customInput || "").trim());
        return Number.isFinite(v) ? v : 0;
      }
      return Number(this.selectedPreset) || 0;
    },
    payAmountText() {
      const y = this.payAmountYuan;
      if (!y || y <= 0) return "0.00";
      return (Math.round(y * 100) / 100).toFixed(2);
    },
    expectedGiftYuan() {
      return giftForRechargeAmountYuan(this.payAmountYuan);
    },
    expectedGiftText() {
      const g = this.expectedGiftYuan;
      return (Math.round(g * 100) / 100).toFixed(2);
    },
    canSubmit() {
      const y = this.payAmountYuan;
      if (!isWechatPayAvailable(this.paymentCapabilities)) return false;
      return y >= RECHARGE_AMOUNT_MIN && y <= RECHARGE_AMOUNT_MAX && !this.paying;
    },
  },
  async onShow() {
    try {
      this.paymentCapabilities = await fetchPaymentCapabilities();
    } catch (e) {
      this.paymentCapabilities = null;
    }
    this.refreshBalance();
    this.loadRechargeHistory();
  },
  onPullDownRefresh() {
    Promise.all([this.refreshBalance(), this.loadRechargeHistory()]).finally(() => {
      wx.stopPullDownRefresh();
    });
  },
  methods: {
    pickPreset(n) {
      this.selectedPreset = n;
      this.useCustom = false;
      this.customInput = "";
    },
    onCustomFocus() {
      this.useCustom = true;
    },
    onCustomInput() {
      this.useCustom = true;
    },
    formatHistoryAmount(item) {
      if (!item) return "0";
      const total = item.total_amount != null ? Number(item.total_amount) : NaN;
      if (Number.isFinite(total)) return formatBalanceForDisplay(total);
      const r = Number(item.recharge_amount || 0);
      const g = Number(item.gift_amount || 0);
      return formatBalanceForDisplay(r + g);
    },
    historyChannelText(ch) {
      if (ch === "wechat") return "微信";
      if (ch === "admin") return "门店";
      return ch ? String(ch) : "-";
    },
    historyStatusText(s) {
      const m = { pending: "待支付", success: "成功", cancelled: "已取消" };
      return m[s] || (s ? String(s) : "-");
    },
    formatHistoryTime(row) {
      const t = row.create_time || row.created_at || row.updated_at || row.pay_time || "";
      if (!t) return "-";
      return String(t).replace("T", " ").slice(0, 19);
    },
    async refreshBalance() {
      const openid = app.globalData.openid || wx.getStorageSync("openid");
      if (!openid) {
        this.balanceYuan = 0;
        return;
      }
      try {
        const res = await app.getUserInfo({ showLoading: false });
        if (res && res.code === 0 && res.data) {
          const raw = res.data.balance;
          const n = raw == null || raw === "" ? 0 : Number(raw);
          this.balanceYuan = Number.isFinite(n) ? Math.round(n * 100) / 100 : 0;
        }
      } catch (e) {
        this.balanceYuan = null;
      }
    },
    /**
     * 支付成功后服务端入账可能略晚于 requestPayment:ok，短轮询直到余额变大或达上限
     */
    async refreshBalanceAfterPaySuccess(balanceBeforePay) {
      const before =
        balanceBeforePay != null && Number.isFinite(Number(balanceBeforePay))
          ? Math.round(Number(balanceBeforePay) * 100) / 100
          : null;
      const maxAttempts = before != null ? 12 : 4;
      const gapMs = 500;
      for (let i = 0; i < maxAttempts; i++) {
        if (i > 0) {
          await new Promise((r) => setTimeout(r, gapMs));
        }
        await this.refreshBalance();
        const now = this.balanceYuan;
        if (before == null) {
          if (i >= maxAttempts - 1) break;
          continue;
        }
        if (now != null && Number.isFinite(Number(now)) && Number(now) > before + 1e-6) {
          break;
        }
      }
      await this.loadRechargeHistory();
    },
    async loadRechargeHistory() {
      const openid = app.globalData.openid || wx.getStorageSync("openid");
      if (!openid) {
        this.historyList = [];
        return;
      }
      this.historyLoading = true;
      try {
        const res = await requestUtil({
          url: "/order/rechargeHistory",
          method: "post",
          data: { openid, page: 1, pageSize: 20, status: "all" },
          showLoading: false,
        });
        if (res && res.code === 0) {
          const raw =
            (Array.isArray(res.list) && res.list) ||
            (res.data && Array.isArray(res.data.list) && res.data.list) ||
            (res.data && Array.isArray(res.data.records) && res.data.records) ||
            [];
          this.historyList = raw;
        } else {
          this.historyList = [];
        }
      } catch (e) {
        this.historyList = [];
      } finally {
        this.historyLoading = false;
      }
    },
    async submitRecharge() {
      if (!this.canSubmit) {
        if (this.rechargePayBlockedMsg) {
          wx.showToast({ title: this.rechargePayBlockedMsg, icon: "none", duration: 3000 });
        }
        return;
      }
      const openid = app.globalData.openid || wx.getStorageSync("openid");
      if (!openid) {
        wx.showToast({ title: "请先登录", icon: "none" });
        return;
      }
      const amount = this.payAmountYuan;
      if (amount < RECHARGE_AMOUNT_MIN || amount > RECHARGE_AMOUNT_MAX) {
        wx.showToast({
          title: `请输入 ${RECHARGE_AMOUNT_MIN}～${RECHARGE_AMOUNT_MAX} 元`,
          icon: "none",
        });
        return;
      }
      this.paying = true;
      const balanceSnapshot = this.balanceYuan;
      wx.showLoading({ title: "创建订单...", mask: true });
      try {
        const response = await rechargeCreateAndGetPayParams({ openid, amountYuan: amount });
        wx.hideLoading();
        if (!response || response.code !== 0 || !response.payParams) {
          const msg =
            resolvePaymentApiErrorMessage(response, this.paymentCapabilities) ||
            (response && (response.msg || response.message)) ||
            "暂无法发起充值，请联系门店";
          if (
            response &&
            (Number(response.code) === PAYMENT_ONLINE_DISABLED_CODE ||
              Number(response.code) === PAYMENT_CHANNEL_DISABLED_CODE ||
              Number(response.code) === PAYMENT_WECHAT_MERCHANT_MISSING_CODE)
          ) {
            this.paymentCapabilities = await fetchPaymentCapabilities({ force: true });
          }
          wx.showToast({ title: String(msg), icon: "none", duration: 3000 });
          this.paying = false;
          return;
        }
        const pp = response.payParams;
        await new Promise((resolve, reject) => {
          wx.requestPayment({
            timeStamp: pp.timeStamp,
            nonceStr: pp.nonceStr,
            package: pp.package,
            signType: pp.signType,
            paySign: pp.paySign,
            success: (r) => {
              if (r.errMsg === "requestPayment:ok") resolve(r);
              else reject(new Error(r.errMsg || "支付未完成"));
            },
            fail: (err) => reject(new Error(err.errMsg || "支付失败")),
          });
        });
        wx.showToast({ title: "支付成功", icon: "success" });
        await this.refreshBalanceAfterPaySuccess(balanceSnapshot);
      } catch (e) {
        wx.hideLoading();
        const em = e && e.message ? String(e.message) : "";
        if (em.includes("cancel") || em.includes("取消")) {
          wx.showToast({ title: "已取消支付", icon: "none" });
        } else if (em) {
          wx.showToast({ title: em.length > 40 ? "支付未完成" : em, icon: "none" });
        }
      } finally {
        this.paying = false;
      }
    },
  },
};
</script>

<style scoped>
.recharge-page {
  min-height: 100vh;
  background: #f5f5f5;
  padding: 24rpx 30rpx 48rpx;
  padding-bottom: calc(48rpx + env(safe-area-inset-bottom));
  box-sizing: border-box;
}
.balance-card {
  background: linear-gradient(135deg, #e74c3c 0%, #c0392b 100%);
  border-radius: 20rpx;
  padding: 36rpx 32rpx;
  color: #fff;
  margin-bottom: 28rpx;
  box-shadow: 0 8rpx 24rpx rgba(231, 76, 60, 0.35);
}
.balance-label {
  font-size: 26rpx;
  opacity: 0.9;
}
.balance-value {
  font-size: 52rpx;
  font-weight: bold;
  margin-top: 12rpx;
  letter-spacing: 1rpx;
}
.balance-tip {
  font-size: 22rpx;
  opacity: 0.85;
  margin-top: 16rpx;
  line-height: 1.5;
}
.section {
  background: #fff;
  border-radius: 20rpx;
  padding: 28rpx 24rpx 32rpx;
  margin-bottom: 24rpx;
}
.history-section {
  margin-bottom: 0;
}
.history-sub {
  font-size: 24rpx;
  color: #999;
  margin-top: -8rpx;
  margin-bottom: 16rpx;
  line-height: 1.4;
}
.history-list {
  display: flex;
  flex-direction: column;
  width: 100%;
}
.section-title {
  font-size: 30rpx;
  font-weight: 600;
  color: #333;
  margin-bottom: 20rpx;
}
.amount-grid {
  display: flex;
  flex-wrap: wrap;
  gap: 20rpx;
}
.amount-cell {
  width: calc(50% - 20rpx);
  box-sizing: border-box;
  text-align: center;
  padding: 26rpx 0;
  border-radius: 16rpx;
  border: 2rpx solid #eee;
  font-size: 30rpx;
  color: #333;
  background: #fafafa;
}
.amount-cell.active {
  border-color: #e74c3c;
  background: #fff5f3;
  color: #e74c3c;
  font-weight: 600;
}
.amount-cell-main {
  display: block;
  font-size: 30rpx;
  line-height: 1.35;
}
.amount-cell-gift {
  display: block;
  margin-top: 8rpx;
  font-size: 24rpx;
  color: #e67e22;
  font-weight: 500;
}
.amount-cell.active .amount-cell-gift {
  color: #d35400;
}
.custom-row {
  display: flex;
  align-items: center;
  margin-top: 24rpx;
  padding-top: 24rpx;
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
}
.footer {
  margin-top: 8rpx;
}
.pay-summary {
  font-size: 28rpx;
  color: #666;
  margin-bottom: 16rpx;
}
.pay-yuan {
  font-size: 36rpx;
  font-weight: bold;
  color: #e74c3c;
}
.gift-hint {
  font-size: 24rpx;
  color: #888;
  margin-bottom: 14rpx;
  line-height: 1.45;
}
.gift-yuan {
  color: #e67e22;
  font-weight: 600;
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
.primary-btn[disabled] {
  opacity: 0.55;
}
.footer-tip {
  font-size: 22rpx;
  color: #999;
  margin-top: 20rpx;
  line-height: 1.5;
}
.footer-tip--warn {
  color: #c45656;
  font-weight: 500;
}
.history-loading,
.history-empty {
  font-size: 26rpx;
  color: #999;
  padding: 24rpx 0;
  text-align: center;
  background: #fafafa;
  border-radius: 12rpx;
}
.history-row {
  display: flex;
  align-items: flex-start;
  justify-content: space-between;
  padding: 20rpx 0;
  border-bottom: 1rpx solid #f0f0f0;
}
.history-row:last-child {
  border-bottom: none;
}
.history-main {
  display: flex;
  flex-direction: column;
  gap: 6rpx;
  min-width: 0;
}
.history-amount {
  font-size: 30rpx;
  font-weight: 600;
  color: #333;
}
.history-meta {
  font-size: 22rpx;
  color: #999;
}
.history-time {
  font-size: 22rpx;
  color: #999;
  flex-shrink: 0;
  margin-left: 16rpx;
}
</style>
