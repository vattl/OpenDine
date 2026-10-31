<template>
  <view class="invite-page">
   
   

    <!-- 16:9 Banner轮播 -->
    <view class="banner-swiper">
      <swiper 
        autoplay 
        circular 
        indicator-dots 
        indicator-color="#ffffff"
        indicator-active-color="#e10606"
        style="height: 422rpx;"  
      >
      
        <swiper-item v-for="(banner, index) in bannerList" :key="index">
          <image 
            :src="banner.imageUrl" 
            mode="widthFix" 
            class="banner-img"
            :lazy-load="index > 0"
          ></image>
        </swiper-item>
      </swiper>
    </view>

    <!-- 头像+文案区块 -->
    <view class="avatar-card">
      <view class="avatar-wrapper">
        <image 
          class="user-avatar" 
          :src="userAvatarUrl" 
          mode="aspectFill"
        ></image>
        <view class="avatar-text">
          <text class="main-text">邀请好友品尝</text>
          <text class="sub-text">注册即可双方得9折优惠券</text>
        </view>
      </view>
    </view>

    <!-- 邀请分享+邀请码区块 -->
    <view class="invite-share-card">
      <!-- 海报邀请/微信邀请按钮（带ICO图标） -->
      <view class="share-btns">
        <button class="share-btn" @click="generateInvitePoster">
          <view class="btn-icon-wrapper">
            <image :src="staticUrl('images/poster-ico.png')" mode="widthFix" class="btn-ico"></image>
          </view>
          <text class="btn-text">海报邀请</text>
        </button>
        <button class="share-btn" @click="guideShareTimeline">
          <view class="btn-icon-wrapper">
            <image :src="staticUrl('images/wechat-ico.png')" mode="widthFix" class="btn-ico"></image>
          </view>
          <text class="btn-text">转发朋友圈</text>
        </button>
      </view>
      
      <view class="invite-code-box">
        <text class="invite-code-label">邀请码：</text>
        <text class="invite-code">{{ inviteCode || '加载中...' }}</text>
        <button class="copy-btn" @click="copyInviteCode">复制</button>
      </view>
    </view>

    <!-- 邀请记录+奖励记录区块 -->
    <view class="record-tabs">
      <view class="tab-item" :class="{ active: activeTab === 'invite' }" @tap="switchTab('invite')">
        <text>邀请记录</text>
      </view>
      <view class="tab-item" :class="{ active: activeTab === 'reward' }" @tap="switchTab('reward')">
        <text>奖励记录</text>
      </view>
    </view>

    <!-- 邀请记录内容 -->
    <view class="record-content" v-if="activeTab === 'invite'">
     <!-- 有邀请记录时展示 -->
     <view class="record-list" v-if="inviteRecords.length > 0">
        <view class="record-item" v-for="(item, index) in inviteRecordsPreview" :key="index">
         <!-- 左侧：名称 + 邀请时间（核心修改区域） -->
         <view class="friend-info">
           <!-- 保留头像（可选，若不需要可删除） -->
           <image class="friend-avatar" :src="getRecordAvatar(item.avatar)" mode="aspectFill"></image>
           
           <!-- 名称 + 邀请时间 纵向布局 -->
           <view class="friend-detail">
             <!-- 名称/脱敏手机号 优先显示 -->
             <text class="friend-name">
               {{ getShowName(item) }}
             </text>
             <!-- 邀请时间（格式化显示） -->
             <text class="invite-time">
               {{ formatTime(item.create_time) }}
             </text>
             <text v-if="inviteCashbackBrief(item)" class="invite-cashback-brief">{{ inviteCashbackBrief(item) }}</text>
           </view>
         </view>
   
         <!-- 右侧：邀请状态（修改文案） -->
         <view class="record-right">
           <view class="invite-status" :class="item.status === 1 ? 'success' : 'pending'">
             {{ item.status === 1 ? '邀请成功' : '邀请中' }}
           </view>
         </view>
        </view>
      </view>
   
     <!-- 无邀请记录时展示（相对路径避免开发环境被解析为 127.0.0.1） -->
     <view class="empty-record" v-else>
       <image :src="staticUrl('images/empty-invite.png')" mode="widthFix" class="empty-img"></image>
       <text class="empty-record-text">暂无邀请记录</text>
     </view>
     <view class="record-load-footer" v-if="activeTab === 'invite' && inviteRecords.length > 0">
       <text v-if="inviteListLoading">加载中…</text>
       <text v-else-if="inviteRecords.length > recordPreviewLimit || inviteHasMore">仅展示最近 {{ recordPreviewLimit }} 条，完整记录请点下方查看</text>
       <text v-else>已展示全部邀请记录</text>
     </view>
    </view>

    <!-- 奖励记录内容 -->
    <view class="record-content" v-if="activeTab === 'reward'">
      <view class="record-list" v-if="rewardRecords.length > 0">
        <view class="record-item reward-record-item" v-for="(item, index) in rewardRecordsPreview" :key="index">
          <view class="reward-info">
            <text class="reward-desc">{{ getRewardRecordTitle(item) }}</text>
            <text class="reward-discount" v-if="getRewardDiscountText(item)">{{ getRewardDiscountText(item) }}</text>
          </view>
          <view class="reward-right">
            <text class="reward-user-name">{{ getRewardShowName(item) }}</text>
            <text class="reward-time">{{ formatTime(item.reward_time || item.createTime) }}</text>
            <view class="reward-amount" v-if="getRewardAmountDisplay(item)">
              <text class="amount-text">{{ getRewardAmountDisplay(item) }}</text>
            </view>
          </view>
        </view>
      </view>
      <view class="empty-record" v-else>
        <image :src="staticUrl('images/empty_reward.png')" mode="widthFix" class="empty-img"></image>
        <text class="empty-record-text">暂无奖励记录</text>
      </view>
      <view class="record-load-footer" v-if="activeTab === 'reward' && rewardRecords.length > 0">
        <text v-if="rewardRecords.length > recordPreviewLimit">仅展示最近 {{ recordPreviewLimit }} 条，完整记录请点下方查看</text>
        <text v-else>已展示全部奖励记录</text>
      </view>
    </view>

    <view class="detail-entry-bar" v-if="showRecordsDetailEntry" @tap="goInviteRecordsDetail">
      <text class="detail-entry-text">查看全部邀请记录与奖励发放</text>
      <text class="detail-entry-arrow">›</text>
    </view>

    <!-- 活动详情：活动详细规则说明 -->
    <view class="activity-detail">
      <view class="activity-detail-title">活动详细规则说明</view>
      <view class="activity-detail-section">
        <text class="activity-detail-h2">一、参与对象</text>
        <text class="activity-detail-p">本小程序注册用户，手机号完成验证即可参与。</text>
      </view>
      <view class="activity-detail-section">
        <text class="activity-detail-h2">二、参与方式</text>
        <text class="activity-detail-p">用户进入小程序活动页面，点击发起邀请，生成专属邀请链接和邀请海报。</text>
        <text class="activity-detail-p">分享给微信好友，好友通过您的邀请链接首次进入小程序并完成指定操作（注册 > 登录 > 绑定手机号），视为注册成功。</text>
        <text class="activity-detail-p">达到活动要求后，系统自动发放9折优惠券至双方的账户。</text>
      </view>
      <view class="activity-detail-section">
        <text class="activity-detail-h2">三、优惠券说明</text>
        <text class="activity-detail-p">优惠券使用条件：</text>
        <text class="activity-detail-p activity-detail-indent">仅限烧烤类商品使用；</text>
        <text class="activity-detail-p activity-detail-indent">柠檬茶、炖汤、酒水不参与折扣；</text>
        <text class="activity-detail-p activity-detail-indent">单笔消费满 50 元可用。</text>
        <text class="activity-detail-p">优惠券不可兑换现金、不找零、不可转赠、仅限本人使用。</text>
        <text class="activity-detail-p">优惠券有效期以到账后显示的使用期限为准，过期自动作废。</text>
        <text class="activity-detail-p">使用账户余额支付订单时，不支持同时使用优惠券。</text>
      </view>
      <view class="activity-detail-section">
        <text class="activity-detail-h2">四、活动规则</text>
        <text class="activity-detail-p">邀请成功双方都可获得一张9折优惠券。</text>
        <text class="activity-detail-p">被邀请人完成首单消费后，其首单消费金额的 5% 将以现金余额形式返现至邀请人账户（返现基数与到账规则以系统结算为准）。</text>
        <text class="activity-detail-p">邀请的好友需为未使用过本小程序的新用户，老用户助力、重复助力、刷号助力均视为无效。</text>
        <text class="activity-detail-p">严禁使用任何外挂、脚本、刷量工具等违规手段参与活动，一经发现，平台有权取消活动资格、收回优惠券，并保留封禁账号的权利。</text>
        <text class="activity-detail-p">若用户出现违规操作、虚假助力、恶意套现等行为，导致交易退款 / 取消，优惠券不予退还。</text>
      </view>
      <view class="activity-detail-section">
        <text class="activity-detail-h2">五、其他说明</text>
        <text class="activity-detail-p">活动期间如遇系统维护、网络异常等不可抗力情况，平台可暂停、调整或提前终止活动，不另行单独通知。</text>
        <text class="activity-detail-p">本平台在法律允许范围内保留对活动规则的解释权。</text>
      </view>
    </view>

    <!-- 海报独立弹窗（契约：海报来自 GET /invite/poster?code=，仅展示与本地操作） -->
    <view class="poster-modal" v-if="showPosterModal">
      <view class="poster-mask" @tap="closePosterModal"></view>
      <view class="poster-window" @tap.stop>
        <view class="poster-close" @tap="closePosterModal">×</view>
        <view class="poster-title">邀请海报</view>
        <view class="poster-image-wrap">
          <image class="poster-image" :src="currentPosterUrl" mode="widthFix"></image>
        </view>
        <view class="poster-actions">
          <view class="poster-btn poster-btn-save" @tap.stop="savePosterToLocal">保存本地</view>
          <button class="poster-btn poster-btn-share" open-type="share" @tap="closePosterModal">转发给朋友</button>
        </view>
        <view class="poster-tip">发朋友圈请先「保存本地」，再在微信朋友圈从相册选图发布</view>
      </view>
    </view>
  </view>
</template>

<script>
import { getBaseUrl, requestUtil } from "../../utils/requestUtil.js";
import { staticUrl } from "../../utils/staticAssetUrl.js";
import {
  activityPopupImageUrl,
  pickActivityPopupImage,
} from "../../utils/imageUrl.js";
const app = getApp();
const defaultAvatarUrl = 'https://mmbiz.qpic.cn/mmbiz/icTdbqWNOwNRna42FI242Lcia07jQodd2FJGIYQfG0LAJGFxM4FbnQP6yfMxBgJ0F3YRqJCJ1aPAK2dQagdusBZg/0';
export default {
  computed: {
    userAvatarUrl() {
      const u = this.userInfo;
      if (!u || !u.avatar) return staticUrl("images/default-avatar.png");
      const av = u.avatar;
      if (av.startsWith("http://") || av.startsWith("https://")) return av;
      return getBaseUrl() + (av.startsWith("/") ? "" : "/") + av;
    },
    /** 首页仅展示最近几条，完整列表见「邀请记录与奖励」页 */
    inviteRecordsPreview() {
      const n = this.recordPreviewLimit || 5;
      return (this.inviteRecords || []).slice(0, n);
    },
    rewardRecordsPreview() {
      const n = this.recordPreviewLimit || 5;
      return (this.rewardRecords || []).slice(0, n);
    },
    showRecordsDetailEntry() {
      if (this.inviteHasMore) return true;
      if ((this.inviteRecords || []).length > 0) return true;
      if ((this.rewardRecords || []).length > 0) return true;
      return false;
    },
  },

  data() {
    return {
      baseUrl: getBaseUrl(),
      inviteCode: "", // 专属邀请码
      inviteRecords: [], // 邀请记录（分页累积）
      inviteNextPage: 1,
      invitePageSize: 5,
      /** 首页「邀请记录 / 奖励记录」各最多展示条数，其余在详情页查看 */
      recordPreviewLimit: 5,
      inviteHasMore: true,
      inviteListLoading: false,
      /** 服务端一次返回全量列表时的本地分页缓存 */
      inviteLegacyFull: null,
      rewardRecords: [], // 奖励记录
	  userInfo:null,
      rewardAmount: 5, // 邀请奖励金额
      isLoading: false,
      bannerList: [],
      activeTab: "invite",
      showPosterModal: false,
      currentPosterUrl: "", // 当前展示的海报地址（Base64 或 URL，契约来自 /invite/poster）
      _initialLoadDone: false, // 防止 onLoad 被多次触发导致接口连续请求两次
    };
  },
  onLoad() {
    // 防止重复加载（避免连续访问两次）
    if (this._initialLoadDone) return;
    this._initialLoadDone = true;

    // 检查登录状态
    if (!app.globalData.isLogin) {
      wx.showToast({
        title: "请先登录",
        icon: "none",
      });
      wx.navigateBack();
      return;
    }
    // 启用「发送给朋友」与「转发朋友圈」，用户点击右上角 ⋯ 时可选择
    wx.showShareMenu({
      withShareTicket: true,
      menus: ["shareAppMessage", "shareTimeline"],
    });
    this.getUserInfo();
    this.getInviteCode();
    this.getInviteRecords(true);
    this.loadBanners();
  },
  onShow() {
    if (this.activeTab === "reward" && this.rewardRecords.length === 0) {
      this.getRewardRecords();
    }
  },
  methods: {
    staticUrl,
    goBack() {
      wx.navigateBack();
    },
    goInviteRecordsDetail() {
      wx.navigateTo({
        url: "/packageOther/invite-friend/invite-records-detail",
      });
    },
    /** 首单余额返现整数元（与 openapi / t_invite_record.first_order_reward_amount 一致） */
    getFirstOrderRewardYuan(item) {
      if (!item) return 0;
      const v =
        item.first_order_reward_amount != null ? item.first_order_reward_amount : item.firstOrderRewardAmount;
      const n = Number(v);
      if (!Number.isFinite(n) || n <= 0) return 0;
      return Math.round(n);
    },
    inviteCashbackBrief(item) {
      const y = this.getFirstOrderRewardYuan(item);
      const t = item.first_order_reward_time || item.firstOrderRewardTime;
      if (y > 0 && t) return `首单已返现 ${y} 元`;
      if (item.status === 1 && y <= 0) return "待好友首单余额返现";
      return "";
    },
    getRewardRecordTitle(item) {
      const rt = String(item.reward_type || item.rewardType || "").toLowerCase();
      if (rt === "point" || rt === "points") return "积分奖励";
      if (rt === "balance" || rt === "first_order" || rt === "first_order_balance") return "首单余额返现";
      if (item.coupon_name) return item.coupon_name;
      return item.desc || "邀请好友注册奖励";
    },
    getRewardAmountDisplay(item) {
      const rt = String(item.reward_type || item.rewardType || "").toLowerCase();
      const fo = this.getFirstOrderRewardYuan(item);
      if (
        fo > 0 &&
        (rt === "balance" ||
          rt === "first_order" ||
          rt === "first_order_balance" ||
          (!item.coupon_name && fo))
      ) {
        return "+" + fo + "元";
      }
      if (item.amount != null && item.amount !== "") return "+" + item.amount + "元";
      if ((rt === "point" || rt === "points") && item.reward_id != null) return "+" + item.reward_id + "分";
      return "";
    },
    switchTab(tab) {
      if (this.activeTab === tab) return;
      this.activeTab = tab;
      if (tab === "reward") this.getRewardRecords();
      if (tab === "invite") this.getInviteRecords(true);
    },
    getRecordAvatar(avatar) {
      if (!avatar) return staticUrl("images/default-avatar.png");
      if (avatar.startsWith("http://") || avatar.startsWith("https://")) return avatar;
      return getBaseUrl() + (avatar.startsWith("/") ? "" : "/") + avatar;
    },
	// 时间格式化（iOS 兼容：后端可能返回 yyyy-MM-dd HH:mm:ss，需归一化）
	formatTime(time) {
      if (!time) return "未知时间";
      let date;
      if (typeof time === "string" && time.indexOf(" ") !== -1) {
        date = new Date(time.replace(" ", "T"));
      } else {
        date = new Date(time);
      }
      if (isNaN(date.getTime())) return String(time);
      const year = date.getFullYear();
      const month = String(date.getMonth() + 1).padStart(2, "0");
      const day = String(date.getDate()).padStart(2, "0");
      return `${year}-${month}-${day}`;
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
      if (!mobile || mobile.length !== 11) {
        return mobile; // 非11位手机号直接返回
      }
      // 正则替换中间4位为*
      return mobile.replace(/(\d{3})\d{4}(\d{4})/, '$1****$2');
    },
    // 奖励记录折扣展示（与 db_diancan.sql t_coupon 一致：coupon_type=full_reduction/discount/direct_reduction，discount_value 满减/立减为金额、折扣为百分比如80=8折，min_amount 为使用门槛）
    getRewardDiscountText(item) {
      const type = (item.coupon_type || "").toLowerCase();
      const v = item.discount_value;
      const minAmt = item.min_amount;
      const num = v != null && v !== "" ? Number(v) : NaN;
      const minNum = minAmt != null && minAmt !== "" ? Number(minAmt) : NaN;

      // direct_reduction-立减：discount_value 为金额
      if (type === "direct_reduction") {
        if (isNaN(num)) return "";
        return "减" + num + "元";
      }
      // full_reduction-满减：discount_value 为减的金额，min_amount 为门槛（0为无门槛）
      if (type === "full_reduction") {
        if (isNaN(num)) return "";
        if (!isNaN(minNum) && minNum > 0) return "满" + minNum + "元减" + num + "元";
        return "减" + num + "元";
      }
      // discount-折扣：discount_value 为百分比，如 80=8折、90=9折（见 t_coupon 注释）
      if (type === "discount") {
        if (isNaN(num)) return "";
        if (num > 0 && num <= 1) return (num * 10) + "折";   // 兼容 0.8 表示 8折
        if (num >= 1 && num <= 10) return num + "折";        // 兼容 9 表示 9折
        if (num > 10 && num <= 100) return (num / 10) + "折"; // 库存 80=8折
        return num + "折";
      }
      // 未区分类型时兼容
      if (!isNaN(num)) {
        if (num > 0 && num <= 1) return (num * 10) + "折";
        if (num >= 1 && num <= 10) return num + "折";
        if (num > 10 && num <= 100) return (num / 10) + "折";
        if (num > 100) return "减" + num + "元";
      }
      return "";
    },
    // 奖励记录右侧：被邀请人名称，无名称则显示脱敏手机号（与邀请记录 getShowName 逻辑一致）
    getRewardShowName(item) {
      if (!item) return "未知用户";
      const name = item.name != null ? String(item.name).trim() : "";
      if (name && name !== "未知用户") return name;
      const phone = item.phone != null ? String(item.phone).trim() : "";
      if (phone) return this.desensitizeMobile(phone);
      return "未知用户";
    },
    // 获取用户信息（契约：可与 POST /order/getUserInfo 对齐，用于头像等）
    async getUserInfo() {
      await app.getUserInfo();
    },

    // 获取用户专属邀请码（契约：POST /invite/getCode，body { openid }，成功 body 含 invite_code；可返回“活动未开始”）
    async getInviteCode() {
      this.isLoading = true;
      try {
        const res = await requestUtil({
          url: "/invite/getCode",
          data: { openid: app.globalData.openid },
          method: "post",
          showErrorMsg: false,
        });
        if (res.code === 0) {
          this.inviteCode = (res.invite_code != null ? res.invite_code : (res.data && res.data.invite_code)) || "";
          if (!this.inviteCode && res.msg) {
            wx.showToast({ title: res.msg, icon: "none" });
          }
        } else {
          this.inviteCode = "";
          if (res.msg) wx.showToast({ title: res.msg, icon: "none" });
        }
      } catch (e) {
        console.error("获取邀请码失败:", e);
        wx.showToast({ title: "网络异常，请重试", icon: "none" });
        this.goBack();
      } finally {
        this.isLoading = false;
      }
    },

    // 复制邀请码
    copyInviteCode() {
      if (!this.inviteCode) {
        wx.showToast({ title: "邀请码未加载完成", icon: "none" });
        return;
      }
      wx.setClipboardData({
        data: this.inviteCode,
        success: () => {
          wx.showToast({
            title: "邀请码复制成功",
            icon: "success",
          });
        },
      });
    },

    /**
     * 邀请记录分页（契约：POST /invite/getRecords，body 含 openid、可选 page、pageSize）
     * 成功时 data 可为 InviteRecordDTO[]，或 { list|records|data, total?, hasMore? }
     * 若服务端仍一次返回全量且条数大于 pageSize，则前端按页切片展示。
     */
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

    // 轮播图（契约：POST /activity/popupList，成功 body 含 code、hasActivity、activity[]，项含 popup_image、image_url）
    async loadBanners() {
      try {
        const res = await requestUtil({
          url: "/activity/popupList",
          method: "post",
          data: { type: "invite_top" },
          
        });
        if (res && res.code === 0 && Array.isArray(res.activity) && res.activity.length > 0) {
          this.bannerList = res.activity
            .filter((item) => pickActivityPopupImage(item))
            .map((item) => ({
              imageUrl: activityPopupImageUrl(item, 750),
            }))
            .filter((row) => row.imageUrl);
        }
      } catch (e) {
        console.error("获取轮播图失败:", e);
        wx.showToast({ title: "获取轮播图失败", icon: "none" });
      }
    },
    // 奖励记录（契约：POST /invite/getReward body { openid }，成功 data 为 InviteRecordDTO[]，含 coupon_name、discount_value、reward_time）
    async getRewardRecords() {
      try {
        const res = await requestUtil({
          url: "/invite/getReward",
          data: { openid: app.globalData.openid },
          method: "post",
          
        });
        if (res && res.code === 0) {
          const raw = res.data && (Array.isArray(res.data) ? res.data : (res.data.records || res.data.list)) || res.records || [];
          this.rewardRecords = Array.isArray(raw) ? raw : [];
        } else {
          this.rewardRecords = [];
        }
      } catch (e) {
        this.rewardRecords = [];
      }
    },

    // 生成分享海报（契约：GET /invite/poster?code=xxx，成功 body 含 posterUrl），在独立弹窗中展示
    async generateInvitePoster() {
      if (!this.inviteCode || !this.inviteCode.trim()) {
        wx.showToast({ title: "邀请码不能为空", icon: "none" });
        return;
      }
      wx.showLoading({ title: "生成海报中...", mask: true });
      try {
        const code = encodeURIComponent(this.inviteCode.trim());
        const res = await requestUtil({
          url: `/invite/poster?code=${code}`,
          method: "get",
          
        });
        let posterUrl = res && (res.posterUrl != null ? res.posterUrl : res.data && res.data.posterUrl);
        if (!posterUrl || typeof posterUrl !== "string") {
          wx.showToast({ title: (res && res.msg) || "海报生成失败", icon: "none" });
          return;
        }
        // 接口返回的是纯 base64 数据，补全为 data URL 以便 <image> 展示和保存到相册
        if (!posterUrl.startsWith("data:") && !posterUrl.startsWith("http")) {
          posterUrl = "data:image/jpeg;base64," + posterUrl.trim();
        }
        this.currentPosterUrl = posterUrl;
        this.showPosterModal = true;
      } catch (e) {
        console.error("生成海报失败:", e);
        wx.showToast({ title: "海报生成失败，请重试", icon: "none" });
      } finally {
        wx.hideLoading();
      }
    },
    closePosterModal() {
      this.showPosterModal = false;
    },
    // 将海报保存到本地相册（契约：海报为 Base64 或 URL，仅本地操作）
    async savePosterToLocal() {
      const url = this.currentPosterUrl;
      if (!url || !String(url).trim()) {
        wx.showToast({ title: "海报未加载完成，请关闭后重新生成", icon: "none" });
        return;
      }
      wx.showLoading({ title: "保存中...", mask: true });
      let filePath = "";
      try {
        if (url.startsWith("data:")) {
          const base64 = url.replace(/^data:image\/\w+;base64,/, "");
          const dir = typeof wx !== "undefined" && wx.env && wx.env.USER_DATA_PATH ? wx.env.USER_DATA_PATH : "";
          const sep = dir && !dir.endsWith("/") ? "/" : "";
          filePath = `${dir}${sep}invite_poster_${Date.now()}.jpg`;
          const fs = wx.getFileSystemManager();
          await new Promise((resolve, reject) => {
            fs.writeFile({
              filePath,
              data: base64,
              encoding: "base64",
              success: resolve,
              fail: reject,
            });
          });
        } else if (url.startsWith("http")) {
          const res = await new Promise((resolve, reject) => {
            wx.downloadFile({ url, success: resolve, fail: reject });
          });
          if (res.statusCode !== 200) throw new Error("下载失败");
          filePath = res.tempFilePath;
        } else {
          filePath = url;
        }
        await new Promise((resolve, reject) => {
          wx.saveImageToPhotosAlbum({
            filePath,
            success: () => {
              wx.showToast({ title: "已保存到相册", icon: "success" });
              resolve();
            },
            fail: (err) => {
              if (err.errMsg && err.errMsg.indexOf("auth") !== -1) {
                wx.showModal({
                  title: "提示",
                  content: "需要您授权保存图片到相册",
                  confirmText: "去设置",
                  success: (r) => {
                    if (r.confirm) wx.openSetting();
                  },
                });
              } else {
                wx.showToast({ title: err.errMsg || "保存失败", icon: "none" });
              }
              reject(err);
            },
          });
        });
      } catch (e) {
        wx.showToast({ title: e && e.errMsg ? "保存失败" : "保存失败，请重试", icon: "none" });
      } finally {
        wx.hideLoading();
      }
    },
    // 点击「转发朋友圈」按钮时引导用户通过右上角 ⋯ 菜单分享（小程序不支持页面内直接调起朋友圈）
    guideShareTimeline() {
      wx.showModal({
        title: "转发朋友圈",
        content: "请点击右上角「⋯」选择「转发朋友圈」即可分享到朋友圈。",
        showCancel: false,
        confirmText: "知道了",
      });
    },
  },
  // 转发给朋友（海报弹窗内按钮、右上角菜单）
  onShareAppMessage() {
    const firstBanner = this.bannerList && this.bannerList[0];
    const imageUrl = firstBanner && firstBanner.imageUrl
      ? firstBanner.imageUrl
      : staticUrl("images/default-avatar.png");
    return {
      title: "【老肥油边王】邀请你注册，双方都能领9折优惠券！",
      path: `/pages/my/my?invite_code=${this.inviteCode}`,
      imageUrl,
    };
  },
  // 转发朋友圈（仅支持通过右上角 ⋯ 菜单触发，不支持页面内直接调起）
  onShareTimeline() {
    const firstBanner = this.bannerList && this.bannerList[0];
    const imageUrl = firstBanner && firstBanner.imageUrl
      ? firstBanner.imageUrl
      : staticUrl("images/default-avatar.png");
    return {
      title: "【老肥油边王】邀请你注册，双方都能领9折优惠券！",
      imageUrl,
    };
  },
};
</script>

<style scoped>
/* 全局样式 */
.invite-page {
  background-color: #f5f5f5;
  min-height: 100vh;
  padding-bottom: 30rpx;
}

/* 导航栏 */
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

/* 16:9 Banner轮播 */
.banner-swiper {
  width: 100%;
  margin-bottom: 30rpx;
}
.banner-img {
  width: 100%;
  height: 100%;
  border-radius: 0;
}

/* 头像+文案区块 */
.avatar-card {
  background-color: #fff;
  margin: 0 30rpx 30rpx;
  border-radius: 10rpx;
  padding: 30rpx;
  box-shadow: 0 2rpx 10rpx rgba(0, 0, 0, 0.05);
  border: 1rpx solid #f0f0f0;
}
.avatar-wrapper {
  display: flex;
  align-items: center;
}
.user-avatar {
  width: 120rpx;
  height: 120rpx;
  border-radius: 50%;
  margin-right: 30rpx;
  border: 2rpx solid #f0f0f0;
}
.avatar-text {
  display: flex;
  flex-direction: column;
}
.main-text {
  font-size: 32rpx;
  font-weight: bold;
  color: #333;
  margin-bottom: 10rpx;
}
.sub-text {
  font-size: 26rpx;
  color: #666;
}

/* 邀请分享+邀请码区块 */
.invite-share-card {
  background-color: #fff;
  margin: 0 30rpx 30rpx;
  border-radius: 10rpx;
  padding: 30rpx;
  box-shadow: 0 2rpx 10rpx rgba(0, 0, 0, 0.05);
  border: 1rpx solid #f0f0f0;
}

/* 核心修改：带ICO的分享按钮样式 */
.share-btns {
  display: flex;
  justify-content: space-between;
  gap: 20rpx;
  margin-bottom: 30rpx;
}
.share-btn {
  display: flex;
  align-items: center; /* 图标+文字水平居中 */
  flex: 1;
  padding: 20rpx 10rpx;
  border-radius: 10rpx;
  border: 1rpx solid #222222;
  background-color: #fff;
  justify-content: center;
}
/* 图标容器 */
.btn-icon-wrapper {
  margin-right: 12rpx; /* 图标和文字间距 */
  display: flex;
  align-items: center;
}
/* ICO图标样式 */
.btn-ico {
  width: 40rpx;  /* 图标尺寸 */
  height: 40rpx;
}
/* 按钮文字 */
.btn-text {
  font-size: 28rpx;
  color: #222222;
  font-weight: 500;
}

.invite-code-box {
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: 20rpx;
  background-color: #fafafa;
  border-radius: 10rpx;
}
.invite-code-label {
  font-size: 28rpx;
  color: #222222;
}
.invite-code {
  font-size: 28rpx;
  color: #222222;
  letter-spacing: 2rpx;
  text-align: center;
}
.copy-btn {
  color: #555;
  font-size: 24rpx;
  padding: 10rpx 30rpx;
  text-align: right;
  flex: auto;
 
 
  
}

/* 记录标签页 */
.record-tabs {
  display: flex;
  background-color: #fff;
  margin: 0 30rpx 0;
  border-radius: 10rpx 10rpx 0 0;
  overflow: hidden;
}
.tab-item {
  flex: 1;
  text-align: center;
  padding: 20rpx 0;
  font-size: 30rpx;
  font-weight: 500;
  color: #666;
  border-bottom: 2rpx solid #f0f0f0;
}
.tab-item.active {
  color: #e10606;
  border-bottom: 2rpx solid #e10606;
}

/* 记录内容区域 */
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
  padding: 0 30rpx;
}
.record-item {
  display: flex;
  justify-content: space-between;
  align-items: center;
  padding: 15rpx 20rpx;
  border-bottom: 1rpx solid #f5f5f5;
}


/* 左侧好友信息容器 */
.friend-info {
  display: flex;
  align-items: center;
  gap: 15rpx; /* 头像与文字间距 */
}
/* 头像样式（可选，如需保留） */
.friend-avatar {
  width: 80rpx;
  height: 80rpx;
  border-radius: 50%;
}
.friend-name {
  font-size: 28rpx;
  color: #333;
  font-weight: 500;
}
/* 名称+时间 纵向容器 */
.friend-detail {
  display: flex;
  flex-direction: column; /* 纵向排列 */
  gap: 8rpx; /* 名称与时间间距 */
}

/* 好友名称样式 */
.friend-name {
  font-size: 32rpx;
  color: #333;
  font-weight: 500;
}
/* 右侧状态容器 */
.record-right {
  display: flex;
  align-items: center;
}
/* 邀请时间样式 */
.invite-time {
  font-size: 24rpx;
  color: #999;
}
.invite-cashback-brief {
  font-size: 22rpx;
  color: #e10606;
  line-height: 1.35;
}
/* 邀请状态样式 */
.invite-status {
  padding: 8rpx 16rpx;
  border-radius: 20rpx;
  font-size: 28rpx;
}
/* 成功状态 */
.invite-status.success {
  background-color: #e8f5e9;
  color: #4caf50;
}
/* 待注册状态 */
.invite-status.pending {
  background-color: #fff8e1;
  color: #ff9800;
}

/* 奖励记录样式 */
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
  display: inline-block;
  font-size: 24rpx;
  color: #e10606;
  margin-bottom: 4rpx;
  padding: 2rpx 10rpx;
  border-radius: 6rpx;
  max-width: 100%;
}
.reward-time {
  font-size: 24rpx;
  color: #999;
}
.reward-right {
  flex-shrink: 0;
  display: flex;
  flex-direction: column;
  align-items: flex-end;
  justify-content: center;
  margin-left: 20rpx;
}
.reward-user-name {
  font-size: 26rpx;
  color: #333;
  margin-bottom: 4rpx;
  text-align: right;
  max-width: 180rpx;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}
.reward-right .reward-time {
  font-size: 24rpx;
  color: #999;
  margin-bottom: 4rpx;
  text-align: right;
}
.reward-amount {
  text-align: right;
}
.amount-text {
  font-size: 28rpx;
  font-weight: bold;
  color: #e10606;
}

/* 空记录样式 */
.empty-record {
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  padding: 100rpx 0;
  color: #999;
}
.empty-img {
  width: 100rpx;
  margin-bottom: 20rpx;
}
.empty-record-text {
  font-size: 28rpx;
  color: #999;
}

.record-load-footer {
  text-align: center;
  padding: 24rpx 0 40rpx;
  font-size: 24rpx;
  color: #999;
}
.record-load-hint {
  color: #bbb;
}

.detail-entry-bar {
  display: flex;
  align-items: center;
  justify-content: space-between;
  margin: 0 30rpx 30rpx;
  padding: 28rpx 32rpx;
  background: linear-gradient(to right, #fff8f5, #fff);
  border-radius: 12rpx;
  border: 1rpx solid #ffd6cc;
  box-shadow: 0 2rpx 12rpx rgba(225, 6, 6, 0.08);
}
.detail-entry-text {
  font-size: 28rpx;
  color: #e10606;
  font-weight: 500;
}
.detail-entry-arrow {
  font-size: 40rpx;
  color: #e10606;
  line-height: 1;
  font-weight: 300;
}

/* 活动详情：活动详细规则说明 */
.activity-detail {
  background: #fff;
  margin: 0 30rpx 40rpx;
  padding: 32rpx 28rpx 48rpx;
  border-radius: 10rpx;
  box-shadow: 0 2rpx 10rpx rgba(0, 0, 0, 0.05);
  border: 1rpx solid #f0f0f0;
}
.activity-detail-title {
  font-size: 32rpx;
  font-weight: bold;
  color: #333;
  margin-bottom: 28rpx;
  line-height: 1.4;
}
.activity-detail-section {
  display: flex;
  flex-direction: column;
  margin-bottom: 24rpx;
}
.activity-detail-section:last-of-type {
  margin-bottom: 0;
}
.activity-detail-h2 {
  font-size: 28rpx;
  font-weight: 600;
  color: #333;
  margin-bottom: 12rpx;
  line-height: 1.4;
}
.activity-detail-p {
  font-size: 26rpx;
  color: #666;
  line-height: 1.6;
  margin-bottom: 10rpx;
}
.activity-detail-p:last-of-type {
  margin-bottom: 0;
}
.activity-detail-indent {
  padding-left: 24rpx;
}

/* 按钮默认样式重置 */
button::after {
  border: none;
}

/* 海报独立弹窗 */
.poster-modal {
  position: fixed;
  top: 0;
  left: 0;
  right: 0;
  bottom: 0;
  z-index: 1000;
}
.poster-mask {
  position: absolute;
  top: 0;
  left: 0;
  right: 0;
  bottom: 0;
  background: rgba(0, 0, 0, 0.6);
}
.poster-window {
  position: absolute;
  left: 50%;
  top: 50%;
  transform: translate(-50%, -50%);
  width: 90%;
  max-width: 640rpx;
  background: #fff;
  border-radius: 24rpx;
  padding: 24rpx;
  box-sizing: border-box;
}
.poster-close {
  position: absolute;
  top: 16rpx;
  right: 16rpx;
  width: 56rpx;
  height: 56rpx;
  line-height: 56rpx;
  text-align: center;
  font-size: 44rpx;
  color: #999;
  z-index: 2;
}
.poster-title {
  font-size: 32rpx;
  font-weight: bold;
  text-align: center;
  padding: 16rpx 0 20rpx;
  color: #333;
}
.poster-image-wrap {
  width: 100%;
  max-height: 70vh;
  overflow: hidden;
  border-radius: 12rpx;
  background: #f5f5f5;
}
.poster-image {
  width: 100%;
  display: block;
}
.poster-actions {
  display: flex;
  gap: 24rpx;
  margin-top: 28rpx;
  padding: 0 8rpx;
}
.poster-actions .poster-btn {
  flex: 1;
  height: 88rpx;
  line-height: 88rpx;
  text-align: center;
  font-size: 30rpx;
  font-weight: 500;
  border-radius: 44rpx;
  border: none;
  margin: 0;
  padding: 0;
}
.poster-actions .poster-btn::after {
  border: none;
}
.poster-btn-save {
  background: #f5f5f5;
  color: #333;
}
.poster-btn-share {
  background: linear-gradient(to right, #ff5117, #e10606);
  color: #fff;
}
.poster-tip {
  margin-top: 16rpx;
  font-size: 22rpx;
  color: #999;
  text-align: center;
  line-height: 1.4;
}
</style>