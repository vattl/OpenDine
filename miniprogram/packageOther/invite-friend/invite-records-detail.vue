<template>
  <view class="invite-detail-page">
    <view class="record-tabs">
      <view class="tab-item" :class="{ active: activeTab === 'invite' }" @tap="switchTab('invite')">
        <text>邀请记录</text>
      </view>
      <view class="tab-item" :class="{ active: activeTab === 'reward' }" @tap="switchTab('reward')">
        <text>奖励发放</text>
      </view>
    </view>

    <view class="record-content" v-if="activeTab === 'invite'">
      <view class="record-list" v-if="inviteRecords.length > 0">
        <view class="record-item" v-for="(item, index) in inviteRecords" :key="'inv-' + index">
          <view class="friend-info">
            <image class="friend-avatar" :src="getRecordAvatar(item.avatar)" mode="aspectFill"></image>
            <view class="friend-detail">
              <text class="friend-name">{{ getShowName(item) }}</text>
              <text class="invite-time">{{ formatDateTime(item.create_time) }}</text>
              <text v-if="inviteCashbackLine(item)" class="cashback-line">{{ inviteCashbackLine(item) }}</text>
            </view>
          </view>
          <view class="record-right">
            <view class="invite-status" :class="item.status === 1 ? 'success' : 'pending'">
              {{ item.status === 1 ? '邀请成功' : '邀请中' }}
            </view>
          </view>
        </view>
      </view>
      <view class="empty-record" v-else-if="!inviteListLoading">
        <text class="empty-record-text">暂无邀请记录</text>
      </view>
      <view class="record-load-footer" v-if="inviteRecords.length > 0">
        <text v-if="inviteListLoading">加载中…</text>
        <text v-else-if="!inviteHasMore">没有更多了</text>
        <text v-else class="record-load-hint">上拉加载更多</text>
      </view>
    </view>

    <view class="record-content" v-if="activeTab === 'reward'">
      <view v-if="cashbackRows.length > 0" class="reward-section">
        <view class="reward-section-title">首单余额返现</view>
        <view class="record-list">
          <view class="record-item reward-record-item" v-for="(row, idx) in cashbackRows" :key="'cb-' + idx">
            <view class="reward-info">
              <text class="reward-desc">好友 {{ getShowName(row) }} 首单返现</text>
              <text class="reward-discount" v-if="row.first_order_no">订单 {{ formatOrderNo(row.first_order_no) }}</text>
            </view>
            <view class="reward-right">
              <text class="amount-text">+{{ getFirstOrderRewardYuan(row) }}元</text>
              <text class="reward-time">{{ formatDateTime(row.first_order_reward_time || row.firstOrderRewardTime) }}</text>
            </view>
          </view>
        </view>
      </view>

      <view v-if="rewardRecords.length > 0" class="reward-section">
        <view class="reward-section-title">{{ cashbackRows.length > 0 ? '优惠券与积分' : '奖励记录' }}</view>
        <view class="record-list">
          <view class="record-item reward-record-item" v-for="(item, index) in rewardRecords" :key="'rw-' + index">
            <view class="reward-info">
              <text class="reward-desc">{{ getRewardRecordTitle(item) }}</text>
              <text class="reward-discount" v-if="getRewardDiscountText(item)">{{ getRewardDiscountText(item) }}</text>
            </view>
            <view class="reward-right">
              <text class="reward-user-name">{{ getRewardShowName(item) }}</text>
              <text class="reward-time">{{ formatDateTime(item.reward_time || item.createTime) }}</text>
              <view class="reward-amount" v-if="getRewardAmountDisplay(item)">
                <text class="amount-text">{{ getRewardAmountDisplay(item) }}</text>
              </view>
            </view>
          </view>
        </view>
      </view>

      <view class="empty-record" v-if="!rewardLoading && cashbackRows.length === 0 && rewardRecords.length === 0">
        <text class="empty-record-text">暂无奖励发放记录</text>
      </view>
    </view>
  </view>
</template>

<script>
import { getBaseUrl, requestUtil } from "../../utils/requestUtil.js";
import { staticUrl } from "../../utils/staticAssetUrl.js";

const app = getApp();

export default {
  data() {
    return {
      activeTab: "invite",
      inviteRecords: [],
      inviteNextPage: 1,
      invitePageSize: 15,
      inviteHasMore: true,
      inviteListLoading: false,
      inviteLegacyFull: null,
      rewardRecords: [],
      rewardLoading: false,
    };
  },
  computed: {
    cashbackRows() {
      return (this.inviteRecords || []).filter((row) => {
        const y = this.getFirstOrderRewardYuan(row);
        const t = row.first_order_reward_time || row.firstOrderRewardTime;
        return y > 0 && t;
      });
    },
  },
  onLoad() {
    if (!app.globalData.isLogin) {
      wx.showToast({ title: "请先登录", icon: "none" });
      wx.navigateBack();
      return;
    }
    this.getInviteRecords(true);
    this.getRewardRecords();
  },
  onReachBottom() {
    if (this.activeTab !== "invite") return;
    if (!this.inviteHasMore || this.inviteListLoading) return;
    this.getInviteRecords(false);
  },
  methods: {
    staticUrl,
    switchTab(tab) {
      if (this.activeTab === tab) return;
      this.activeTab = tab;
      if (tab === "reward" && this.rewardRecords.length === 0 && !this.rewardLoading) {
        this.getRewardRecords();
      }
    },
    getRecordAvatar(avatar) {
      if (!avatar) return staticUrl("images/default-avatar.png");
      if (avatar.startsWith("http://") || avatar.startsWith("https://")) return avatar;
      return getBaseUrl() + (avatar.startsWith("/") ? "" : "/") + avatar;
    },
    formatDateTime(time) {
      if (!time) return "—";
      let date;
      if (typeof time === "string" && time.indexOf(" ") !== -1) {
        date = new Date(time.replace(" ", "T"));
      } else {
        date = new Date(time);
      }
      if (isNaN(date.getTime())) return String(time);
      const y = date.getFullYear();
      const m = String(date.getMonth() + 1).padStart(2, "0");
      const d = String(date.getDate()).padStart(2, "0");
      const h = String(date.getHours()).padStart(2, "0");
      const min = String(date.getMinutes()).padStart(2, "0");
      return `${y}-${m}-${d} ${h}:${min}`;
    },
    formatOrderNo(no) {
      if (!no) return "";
      const s = String(no);
      return s.length > 14 ? s.slice(0, 8) + "…" + s.slice(-4) : s;
    },
    getShowName(item) {
      if (!item) return "未知好友";
      const name = item.name != null ? String(item.name).trim() : "";
      if (name && name !== "未知好友") return name;
      const phone = item.phone != null ? String(item.phone).trim() : "";
      if (phone) return this.desensitizeMobile(phone);
      return "未知好友";
    },
    desensitizeMobile(mobile) {
      if (!mobile || mobile.length !== 11) return mobile;
      return mobile.replace(/(\d{3})\d{4}(\d{4})/, "$1****$2");
    },
    getFirstOrderRewardYuan(item) {
      if (!item) return 0;
      const v = item.first_order_reward_amount != null ? item.first_order_reward_amount : item.firstOrderRewardAmount;
      const n = Number(v);
      if (!Number.isFinite(n) || n <= 0) return 0;
      return Math.round(n);
    },
    inviteCashbackLine(item) {
      const y = this.getFirstOrderRewardYuan(item);
      const t = item.first_order_reward_time || item.firstOrderRewardTime;
      if (y > 0 && t) return `首单已返现 ${y} 元（${this.formatDateTime(t)}）`;
      if (item.status === 1 && y <= 0) return "好友完成首单并支付后可获余额返现";
      return "";
    },
    getRewardDiscountText(item) {
      const type = (item.coupon_type || "").toLowerCase();
      const v = item.discount_value;
      const minAmt = item.min_amount;
      const num = v != null && v !== "" ? Number(v) : NaN;
      const minNum = minAmt != null && minAmt !== "" ? Number(minAmt) : NaN;
      if (type === "direct_reduction") {
        if (isNaN(num)) return "";
        return "减" + num + "元";
      }
      if (type === "full_reduction") {
        if (isNaN(num)) return "";
        if (!isNaN(minNum) && minNum > 0) return "满" + minNum + "元减" + num + "元";
        return "减" + num + "元";
      }
      if (type === "discount") {
        if (isNaN(num)) return "";
        if (num > 0 && num <= 1) return (num * 10) + "折";
        if (num >= 1 && num <= 10) return num + "折";
        if (num > 10 && num <= 100) return num / 10 + "折";
        return num + "折";
      }
      if (!isNaN(num)) {
        if (num > 0 && num <= 1) return (num * 10) + "折";
        if (num >= 1 && num <= 10) return num + "折";
        if (num > 10 && num <= 100) return num / 10 + "折";
        if (num > 100) return "减" + num + "元";
      }
      return "";
    },
    getRewardShowName(item) {
      if (!item) return "未知用户";
      const name = item.name != null ? String(item.name).trim() : "";
      if (name && name !== "未知用户") return name;
      const phone = item.phone != null ? String(item.phone).trim() : "";
      if (phone) return this.desensitizeMobile(phone);
      return "未知用户";
    },
    getRewardRecordTitle(item) {
      const rt = String(item.reward_type || item.rewardType || "").toLowerCase();
      if (rt === "point" || rt === "points") return "积分奖励";
      if (rt === "balance" || rt === "first_order" || rt === "first_order_balance") return "首单余额返现";
      if (item.coupon_name) return item.coupon_name;
      return item.desc || "邀请奖励";
    },
    getRewardAmountDisplay(item) {
      const rt = String(item.reward_type || item.rewardType || "").toLowerCase();
      const fo = this.getFirstOrderRewardYuan(item);
      if (fo > 0 && (rt === "balance" || rt === "first_order" || rt === "first_order_balance" || (!item.coupon_name && fo))) {
        return "+" + fo + "元";
      }
      if (item.amount != null && item.amount !== "") return "+" + item.amount + "元";
      if ((rt === "point" || rt === "points") && item.reward_id != null) return "+" + item.reward_id + "分";
      return "";
    },
    async getInviteRecords(reset = false) {
      if (this.inviteListLoading) return;
      if (!reset && !this.inviteHasMore) return;

      if (reset) {
        this.inviteNextPage = 1;
        this.inviteRecords = [];
        this.inviteLegacyFull = null;
        this.inviteHasMore = true;
      }

      if (this.inviteLegacyFull && !reset) {
        this._appendInviteLegacyPage();
        return;
      }

      this.inviteListLoading = true;
      try {
        const page = this.inviteNextPage;
        const res = await requestUtil({
          url: "/invite/getRecords",
          data: {
            openid: app.globalData.openid,
            page,
            pageSize: this.invitePageSize,
          },
          method: "post",
          showErrorMsg: false,
        });
        if (res.code !== 0) {
          if (reset) this.inviteRecords = [];
          return;
        }

        let list = [];
        let total;
        let hasMoreFlag;
        const raw = res.data != null ? res.data : res.list != null ? res.list : res.records;
        if (Array.isArray(raw)) {
          list = raw;
        } else if (raw && typeof raw === "object") {
          const inner = raw.records || raw.list || raw.data;
          list = Array.isArray(inner) ? inner : [];
          if (raw.total != null) total = Number(raw.total);
          if (raw.hasMore != null) hasMoreFlag = !!raw.hasMore;
        }
        if (res.total != null && total === undefined) total = Number(res.total);
        if (res.hasMore != null && hasMoreFlag === undefined) hasMoreFlag = !!res.hasMore;

        if (page > 1 && list.length === 0) {
          this.inviteHasMore = false;
          return;
        }

        const legacyFullDump =
          page === 1 &&
          list.length > this.invitePageSize &&
          total === undefined &&
          hasMoreFlag === undefined;

        if (legacyFullDump) {
          this.inviteLegacyFull = list;
          this.inviteRecords = list.slice(0, this.invitePageSize);
          this.inviteHasMore = list.length > this.inviteRecords.length;
          this.inviteNextPage = 2;
          return;
        }

        if (page === 1) {
          this.inviteRecords = list;
        } else {
          this.inviteRecords = [...this.inviteRecords, ...list];
        }

        if (hasMoreFlag === false) {
          this.inviteHasMore = false;
        } else if (total != null && Number.isFinite(total) && total >= 0) {
          this.inviteHasMore = this.inviteRecords.length < total;
        } else {
          this.inviteHasMore = list.length >= this.invitePageSize;
        }

        if (this.inviteHasMore) {
          this.inviteNextPage = page + 1;
        }
      } catch (e) {
        console.error("获取邀请记录失败:", e);
      } finally {
        this.inviteListLoading = false;
      }
    },
    _appendInviteLegacyPage() {
      if (!this.inviteLegacyFull || !this.inviteHasMore) return;
      const full = this.inviteLegacyFull;
      const size = this.invitePageSize;
      const start = this.inviteRecords.length;
      const chunk = full.slice(start, start + size);
      if (chunk.length === 0) {
        this.inviteHasMore = false;
        return;
      }
      this.inviteRecords = [...this.inviteRecords, ...chunk];
      this.inviteHasMore = start + chunk.length < full.length;
    },
    async getRewardRecords() {
      this.rewardLoading = true;
      try {
        const res = await requestUtil({
          url: "/invite/getReward",
          data: { openid: app.globalData.openid },
          method: "post",
          showErrorMsg: false,
        });
        if (res && res.code === 0) {
          const raw =
            (res.data && (Array.isArray(res.data) ? res.data : res.data.records || res.data.list)) ||
            res.records ||
            [];
          this.rewardRecords = Array.isArray(raw) ? raw : [];
        } else {
          this.rewardRecords = [];
        }
      } catch (e) {
        this.rewardRecords = [];
      } finally {
        this.rewardLoading = false;
      }
    },
  },
};
</script>

<style scoped>
.invite-detail-page {
  min-height: 100vh;
  background-color: #f5f5f5;
  padding-bottom: 40rpx;
}
.record-tabs {
  display: flex;
  background-color: #fff;
  margin: 20rpx 30rpx 0;
  border-radius: 10rpx 10rpx 0 0;
  overflow: hidden;
}
.tab-item {
  flex: 1;
  text-align: center;
  padding: 24rpx 0;
  font-size: 30rpx;
  font-weight: 500;
  color: #666;
  border-bottom: 2rpx solid #f0f0f0;
}
.tab-item.active {
  color: #e10606;
  border-bottom: 2rpx solid #e10606;
}
.record-content {
  background-color: #fff;
  margin: 0 30rpx 30rpx;
  border-radius: 0 0 10rpx 10rpx;
  padding: 20rpx 0;
  box-shadow: 0 2rpx 10rpx rgba(0, 0, 0, 0.05);
  border: 1rpx solid #f0f0f0;
  border-top: none;
}
.record-list {
  padding: 0 24rpx;
}
.record-item {
  display: flex;
  justify-content: space-between;
  align-items: flex-start;
  padding: 20rpx 12rpx;
  border-bottom: 1rpx solid #f5f5f5;
}
.friend-info {
  display: flex;
  align-items: flex-start;
  gap: 15rpx;
  flex: 1;
  min-width: 0;
}
.friend-avatar {
  width: 80rpx;
  height: 80rpx;
  border-radius: 50%;
  flex-shrink: 0;
}
.friend-detail {
  display: flex;
  flex-direction: column;
  gap: 6rpx;
  min-width: 0;
}
.friend-name {
  font-size: 30rpx;
  color: #333;
  font-weight: 500;
}
.invite-time {
  font-size: 24rpx;
  color: #999;
}
.cashback-line {
  font-size: 22rpx;
  color: #e10606;
  line-height: 1.4;
}
.record-right {
  flex-shrink: 0;
  margin-left: 12rpx;
}
.invite-status {
  padding: 8rpx 16rpx;
  border-radius: 20rpx;
  font-size: 24rpx;
}
.invite-status.success {
  background-color: #e8f5e9;
  color: #4caf50;
}
.invite-status.pending {
  background-color: #fff8e1;
  color: #ff9800;
}
.reward-section {
  margin-bottom: 16rpx;
}
.reward-section-title {
  font-size: 26rpx;
  color: #666;
  padding: 12rpx 28rpx 8rpx;
  font-weight: 600;
}
.reward-record-item .reward-info {
  flex: 1;
  min-width: 0;
  display: flex;
  flex-direction: column;
  justify-content: center;
}
.reward-desc {
  font-size: 28rpx;
  color: #333;
  margin-bottom: 6rpx;
  font-weight: 500;
}
.reward-discount {
  font-size: 24rpx;
  color: #e10606;
}
.reward-right {
  flex-shrink: 0;
  display: flex;
  flex-direction: column;
  align-items: flex-end;
  justify-content: center;
  margin-left: 16rpx;
}
.reward-user-name {
  font-size: 26rpx;
  color: #333;
  margin-bottom: 4rpx;
  max-width: 200rpx;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}
.reward-time {
  font-size: 24rpx;
  color: #999;
  margin-bottom: 4rpx;
}
.amount-text {
  font-size: 28rpx;
  font-weight: bold;
  color: #e10606;
}
.empty-record {
  padding: 80rpx 0;
  text-align: center;
}
.empty-record-text {
  font-size: 28rpx;
  color: #999;
}
.record-load-footer {
  text-align: center;
  padding: 24rpx 0 16rpx;
  font-size: 24rpx;
  color: #999;
}
.record-load-hint {
  color: #bbb;
}
</style>
