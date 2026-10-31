<template>
  <view class="queue-page">
    <view class="header-card">
      <view class="title">排队取号</view>
      <view class="desc">{{ queueConfig.shopName || "老肥油边王" }} · 在线取号更省时</view>
      <view class="tips" v-if="queueConfig.notice">{{ queueConfig.notice }}</view>
    </view>

    <view class="panel panel-closed" v-if="queueConfig.enabled === false">
      <view class="panel-title">排队暂未开启</view>
      <view class="closed-desc">当前门店暂未开放线上排队，请到店咨询前台。</view>
    </view>

    <view class="panel" v-else-if="!ticketInfo">
      <view class="panel-title">填写取号信息</view>

      <view class="form-item">
        <view class="label">手机号</view>
        <input class="input" type="number" maxlength="11" v-model="form.mobile" placeholder="请输入手机号" />
      </view>

      <view class="form-item">
        <view class="label">就餐人数</view>
        <picker mode="selector" :range="partySizeRange" @change="onPartySizeChange">
          <view class="picker-value">{{ form.partySize }} 人</view>
        </picker>
      </view>

      <view class="form-item">
        <view class="label">就餐类型</view>
        <view class="picker-value">堂食</view>
      </view>

      <view class="form-item">
        <view class="label">备注（可选）</view>
        <input class="input" maxlength="30" v-model="form.remark" placeholder="如：婴儿车、靠窗等" />
      </view>

      <button class="primary-btn" :loading="loading" :disabled="!hasOpenid" @click="createQueueTicket">立即取号</button>
      <view class="login-tip" v-if="!hasOpenid">请先在“我的”页面登录后再取号</view>
    </view>

    <view class="panel" v-else>
      <view class="panel-title">当前排队信息</view>
      <view class="ticket-row"><text>排队号</text><text class="strong">{{ ticketInfo.ticketNo }}</text></view>
      <view class="ticket-row"><text>当前状态</text><text>{{ statusText(ticketInfo.status) }}</text></view>
      <view class="ticket-row"><text>前方桌数</text><text>{{ ticketInfo.aheadCount || 0 }} 桌</text></view>
      <view class="ticket-row"><text>预计等待</text><text>{{ ticketInfo.estimatedWaitMinutes || 0 }} 分钟</text></view>
      <view class="ticket-row"><text>取号时间</text><text>{{ ticketInfo.createdAt || "-" }}</text></view>

      <view class="btn-row">
        <button class="ghost-btn" :loading="loading" @click="queryQueueStatus">刷新进度</button>
        <button class="danger-btn" :loading="loading" @click="cancelQueueTicket" v-if="canCancelTicket">取消排队</button>
      </view>
    </view>
      <global-activity-popup />
  </view>
</template>

<script>
import { requestUtil } from "../../utils/requestUtil.js";
import { requestSceneSubscribe } from "../../utils/wechatSubscribeManager.js";

const app = getApp();

export default {
  data() {
    return {
      loading: false,
      partySizeRange: [1, 2, 3, 4, 5, 6, 7, 8, 9, 10],
      queueConfig: {
        enabled: true,
        shopName: "",
        notice: "",
      },
      form: {
        mobile: "",
        partySize: 2,
        remark: "",
      },
      ticketInfo: null,
    };
  },
  computed: {
    hasOpenid() {
      return !!this.getOpenid();
    },
    canCancelTicket() {
      if (!this.ticketInfo) return false;
      const status = this.ticketInfo.status;
      return status === "waiting" || status === "calling";
    },
  },
  methods: {
    getOpenid() {
      return app.globalData.openid || wx.getStorageSync("openid") || "";
    },
    getTicketStorageKey() {
      return `queue_ticket_no_${this.getOpenid() || "guest"}`;
    },
    saveLocalTicketNo(ticketNo) {
      if (!ticketNo) return;
      wx.setStorageSync(this.getTicketStorageKey(), String(ticketNo));
    },
    clearLocalTicketNo() {
      wx.removeStorageSync(this.getTicketStorageKey());
    },
    loadLocalTicketNo() {
      return wx.getStorageSync(this.getTicketStorageKey()) || "";
    },
    onPartySizeChange(e) {
      const index = Number(e.detail.value || 0);
      this.form.partySize = this.partySizeRange[index];
    },
    statusText(status) {
      const map = {
        waiting: "排队中",
        calling: "叫号中",
        seated: "已入座",
        cancelled: "已取消",
        expired: "已过号",
      };
      return map[status] || "排队中";
    },
    async loadQueueConfig() {
      try {
        const res = await requestUtil({
          url: "/queue/config",
          method: "get",
          showLoading: false,
        });
        if (res && res.code === 0 && res.data) {
          this.queueConfig = { ...this.queueConfig, ...res.data };
        }
      } catch (e) {
        console.error("loadQueueConfig error:", e);
      }
    },
    validForm() {
      if (!this.hasOpenid) {
        wx.showToast({ title: "请先登录后再取号", icon: "none" });
        return false;
      }
      const mobile = (this.form.mobile || "").trim();
      if (!/^1\d{10}$/.test(mobile)) {
        wx.showToast({ title: "请输入正确手机号", icon: "none" });
        return false;
      }
      return true;
    },
    async createQueueTicket() {
      if (!this.validForm()) return;
      // 在用户点击手势内智能决策订阅排队到号通知并同步配额台账
      await requestSceneSubscribe("QUEUE_CALL", {
        openid: this.getOpenid(),
        shopId: (this.queueConfig && this.queueConfig.shopId) || 1,
        showToast: false,
      });

      this.loading = true;
      try {
        const res = await requestUtil({
          url: "/queue/ticket/create",
          method: "post",
          data: {
            openid: this.getOpenid(),
            mobile: this.form.mobile.trim(),
            partySize: this.form.partySize,
            dineType: "dinein",
            remark: this.form.remark.trim(),
          },
        });
        if (res && res.code === 0 && res.data) {
          this.ticketInfo = res.data;
          this.saveLocalTicketNo(res.data.ticketNo);
          wx.showToast({ title: "取号成功", icon: "success" });
          return;
        }
        wx.showToast({ title: (res && res.msg) || "取号失败", icon: "none" });
      } catch (e) {
        console.error("createQueueTicket error:", e);
      } finally {
        this.loading = false;
      }
    },
    async queryQueueStatus() {
      if (!this.ticketInfo || !this.ticketInfo.ticketNo) return;
      this.loading = true;
      try {
        const res = await requestUtil({
          url: "/queue/ticket/status",
          method: "get",
          data: {
            ticketNo: this.ticketInfo.ticketNo,
          },
          showLoading: false,
        });
        if (res && res.code === 0 && res.data) {
          this.ticketInfo = { ...this.ticketInfo, ...res.data };
          const status = this.ticketInfo.status;
          if (status === "seated" || status === "cancelled" || status === "expired") {
            this.clearLocalTicketNo();
          }
          return;
        }
        wx.showToast({ title: (res && res.msg) || "刷新失败", icon: "none" });
      } catch (e) {
        console.error("queryQueueStatus error:", e);
      } finally {
        this.loading = false;
      }
    },
    async cancelQueueTicket() {
      if (!this.ticketInfo || !this.ticketInfo.ticketNo) return;
      this.loading = true;
      try {
        const res = await requestUtil({
          url: "/queue/ticket/cancel",
          method: "post",
          data: {
            ticketNo: this.ticketInfo.ticketNo,
          },
          showLoading: false,
        });
        if (res && res.code === 0) {
          wx.showToast({ title: "已取消排队", icon: "none" });
          this.ticketInfo = null;
          this.clearLocalTicketNo();
          return;
        }
        wx.showToast({ title: (res && res.msg) || "取消失败", icon: "none" });
      } catch (e) {
        console.error("cancelQueueTicket error:", e);
      } finally {
        this.loading = false;
      }
    },
  },
  onLoad(options) {
    try {
      wx.hideHomeButton();
    } catch (e) {}
    this.loadQueueConfig();
    const ticketNo = (options && options.ticketNo) || this.loadLocalTicketNo();
    if (ticketNo) {
      this.ticketInfo = { ticketNo };
      this.queryQueueStatus();
    }
  },
};
</script>

<style scoped>
page {
  background-color: #fff5f2;
}

.queue-page {
  padding: 24rpx;
}

.header-card {
  background: linear-gradient(135deg, #fef2ea, #ffe7dc);
  border-radius: 20rpx;
  padding: 28rpx 24rpx;
  margin-bottom: 20rpx;
}

.title {
  font-size: 40rpx;
  color: #333;
  font-weight: 600;
}

.desc {
  margin-top: 10rpx;
  font-size: 26rpx;
  color: #8a4d2f;
}

.tips {
  margin-top: 10rpx;
  font-size: 24rpx;
  color: #b32424;
}

.panel {
  background-color: #fff;
  border-radius: 20rpx;
  padding: 26rpx 24rpx;
  box-shadow: 0 6rpx 20rpx rgba(0, 0, 0, 0.04);
}

.panel-closed {
  text-align: center;
}

.closed-desc {
  font-size: 26rpx;
  color: #888;
  line-height: 1.7;
}

.panel-title {
  font-size: 32rpx;
  color: #333;
  font-weight: 600;
  margin-bottom: 20rpx;
}

.form-item {
  margin-bottom: 20rpx;
}

.label {
  font-size: 26rpx;
  color: #666;
  margin-bottom: 10rpx;
}

.input,
.picker-value {
  height: 80rpx;
  border-radius: 14rpx;
  background-color: #f8f8f8;
  padding: 0 20rpx;
  font-size: 28rpx;
  color: #333;
  display: flex;
  align-items: center;
}

.primary-btn {
  margin-top: 16rpx;
  background: linear-gradient(to right, #f8da81, #f6cb4a);
  color: #222;
  border-radius: 14rpx;
  font-size: 30rpx;
}

.login-tip {
  margin-top: 12rpx;
  text-align: center;
  font-size: 24rpx;
  color: #999;
}

.ticket-row {
  display: flex;
  justify-content: space-between;
  font-size: 28rpx;
  color: #333;
  padding: 16rpx 0;
  border-bottom: 1rpx solid #f1f1f1;
}

.ticket-row .strong {
  font-weight: 600;
  color: #b32424;
}

.btn-row {
  display: flex;
  margin-top: 24rpx;
}

.ghost-btn,
.danger-btn {
  flex: 1;
  border-radius: 14rpx;
  font-size: 28rpx;
}

.danger-btn {
  margin-left: 16rpx;
}

.ghost-btn {
  background-color: #f2f2f2;
  color: #333;
}

.danger-btn {
  background-color: #b32424;
  color: #fff;
}
</style>
