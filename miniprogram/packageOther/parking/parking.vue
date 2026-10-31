<template>
  <view class="parking-coupon-page" style="height: 100%;">
    <!-- 主内容区 -->
    <scroll-view class="main-content" scroll-y style="height: 100%;">
      <!-- 优惠券卡片 -->
      <view class="coupon-card" style="background-color: #fff;">
        <!-- 停车基础信息 -->
        <view class="parking-info">
          <view class="info-item">
            <text class="label">停车场：</text>
            <text class="value">{{parkingLotName}}</text>
          </view>
          <view class="info-item">
            <text class="label">优惠类型：</text>
            <text class="value">{{couponTypeText}}</text>
          </view>
          <view class="info-item">
            <text class="label">有效期：</text>
            <text class="value">{{couponValidity}}</text>
          </view>
        </view>
        
        <!-- 优惠券详情 -->
        <view class="coupon-detail">
          <view class="detail-title">优惠券详情</view>
          <view class="detail-item">
            <view class="detail-name">{{couponName}}</view>
            <view class="detail-desc">{{couponDescription}}</view>
          </view>
          
          <!-- 使用规则 -->
          <view class="rule-section">
            <view class="rule-label">使用规则</view>
            <view class="rule-content">
              <text v-for="(rule, index) in couponRules" :key="index" class="rule-item">{{rule}}</text>
            </view>
          </view>
        </view>
        
        <!-- 车牌输入区域（重构核心） -->
        <view class="plate-input-section">
          <view class="plate-label">请输入车牌信息</view>
          
          <!-- 方格式车牌输入框（8个格子：省份+7位） -->
          <!-- 修复：移除center居中，添加最小宽度，确保8个格子完整显示 -->
          <view class="plate-grid-wrapper">
            <!-- 省份格子 -->
            <view 
              class="plate-grid-item province-item" 
              :class="{filled: selectedProvince}"
              @click="showProvinceKeyboard = true"
            >
              <text>{{selectedProvince || '省'}}</text>
            </view>
            
            <!-- 车牌号数字/字母格（7位） -->
            <view 
              v-for="(item, index) in 7" 
              :key="index" 
              class="plate-grid-item number-item"
              :class="{
                filled: plateNumber[index], 
                disabled: index === 6 && !enableLastPlate 
              }"
              @click="openNumberKeyboard(index)"
            >
              <text>{{plateNumber[index] || ''}}</text>
            </view>
          </view>
        
          <!-- 错误提示 -->
          <view class="error-tip" v-if="errorMsg" style="color: #f56c6c;">{{errorMsg}}</view>
        </view>
        
        <!-- 底部占位区域 -->
        <view class="bottom-placeholder"></view>
      </view>
    </scroll-view>
    
    <!-- 领取按钮 -->
    <view class="receive-btn-container" style="position: fixed; bottom: 0; left: 0; right: 0; background: #fff; padding: 30rpx 20rpx; box-shadow: 0 -2rpx 10rpx rgba(0,0,0,0.05);">
      <button 
        @click="receiveCoupon" 
        :class="[isPlateVa ? 'receive-coupon-btn' : 'receive-coupon-btn-disabled']"
        :disabled="!isPlateVa"
       
        style="width: 100%; height: 90rpx; border-radius: 45rpx; font-size: 32rpx; border: none;"
      >
        {{ isReceiving ? '领取中...' : '确认领取优惠券' }}
      </button>
    </view>

    <!-- 自定义省份选择键盘 -->
    <view class="custom-keyboard" v-if="showProvinceKeyboard">
      <view class="keyboard-mask" @click="showProvinceKeyboard = false"></view>
      <view class="keyboard-content">
        <view class="keyboard-title">选择省份</view>
        <view class="province-grid">
          <view 
            class="province-item" 
            v-for="(province, index) in provinceList" 
            :key="index"
            @click="selectProvince(province)"
          >
            {{province}}
          </view>
        </view>
      </view>
    </view>

    <!-- 自定义数字字母键盘 -->
    <view class="custom-keyboard" v-if="showNumberKeyboard">
      <view class="keyboard-mask" @click="closeNumberKeyboard"></view>
      <view class="keyboard-content">
        <view class="keyboard-title">输入车牌号</view>
        <view class="number-grid">
          <!-- 字母行 -->
          <view 
            class="key-item" 
            v-for="char in letterChars" 
            :key="char"
            @click="inputCharacter(char)"
          >
            {{char}}
          </view>
          <!-- 数字行 -->
          <view 
            class="key-item" 
            v-for="num in numberChars" 
            :key="num"
            @click="inputCharacter(num)"
          >
            {{num}}
          </view>
          <!-- 退格键 -->
          <view class="key-item backspace" @click="deleteCharacter">
            ←
          </view>
        </view>
      </view>
    </view>
	<!-- 新增：验证码弹出输入框 -->
    <view class="captcha-popup" v-if="showCaptchaPopup">
      <!-- 遮罩层：不可点击关闭，仅能通过输入验证码并确定后关闭 -->
      <view class="captcha-mask"></view>
      <!-- 弹窗主体 -->
      <view class="captcha-content">
        <view class="captcha-title">验证身份</view>
        <view class="captcha-desc">请输入收到的短信验证码</view>
        <!-- 验证码输入框 -->
        <input 
          class="captcha-input" 
          type="number" 
          placeholder="请输入6位验证码" 
          placeholder-class="captcha-placeholder"
          v-model="captchaCode"
          maxlength="6"
        />
        <!-- 仅确定按钮（手机验证码必验，不提供取消） -->
        <view class="captcha-btn-group">
          <button 
            class="captcha-confirm-btn"
            :disabled="!captchaCode || captchaCode.length !== 6"
            @click="parkingLogin"
          >
            确定
          </button>
        </view>
      </view>
    </view>
  </view>
</template>

<script>
import { getBaseUrl, requestUtil } from "../../utils/requestUtil.js";
import { encryptFull,testEncrypt } from "../../utils/encode.js";
import { decryptFull,testDecrypt } from "../../utils/decode.js";
const app = getApp();

export default {
  data() {
    return {
      // 停车场信息
      parkingLotName: '智慧停车场(中心店)',
      // 优惠券信息
      couponId: '',          
      couponName: '5元停车立减券',        
      couponDescription: '凭此券可享受5元停车费立减优惠，单次停车限用1张', 
      couponRules: ['1. 本券仅限指定停车场使用','2. 每车牌限领1张','3. 券有效期内使用'],       
      couponType: 'direct',        
      couponValidity: '2025-01-01 至 2025-12-31',
      couponValue: 0, // 新增：优惠券价值（分钟/金额）
      servicePhone: '', // 新增：客服电话
      // 车牌信息（核心修改：8个格子=省份+7位车牌号）
      provinceList: ['京','沪','粤','深','浙','苏','鲁','川','渝','冀','晋','蒙','辽','吉','黑','皖','闽','赣','豫','鄂','湘','桂','琼','贵','云','陕','甘','青','宁','新','藏'],
      selectedProvince: '',  
      plateNumber: [],       // 车牌号数组（7位）
      enableLastPlate: false,// 是否启用最后一格（第7位）
      errorMsg: '',          
      isReceiving: false,
	  Bearer:"",
	  app_id:"op61763b8368768d6",
	  plate:'',
	  isPlateVa:false,
	  identity:'',
	  token:'1156AC2846FA04790CE48D9715A8FF06',
      // 自定义键盘相关
      showProvinceKeyboard: false, // 省份键盘显示状态
      showNumberKeyboard: false,   // 数字字母键盘显示状态
      currentInputIndex: 0,        // 当前输入位置
      // 键盘字符集
      letterChars: ['A','B','C','D','E','F','G','H','J','K','L','M','N','P','Q','R','S','T','U','V','W','X','Y','Z'],
      numberChars: ['0','1','2','3','4','5','6','7','8','9'],
	  showCaptchaPopup: false, // 控制验证码弹窗显示/隐藏
	  captchaCode: '' // 存储用户输入的验证码
    }
  },
  onLoad(options) {
    // 仅登录后可打开：未登录直接返回
    const openid = app.globalData.openid || wx.getStorageSync('openid');
    const userInfo = app.globalData.userInfo || wx.getStorageSync('userInfo') || {};
    const hasPhone = userInfo.phone && String(userInfo.phone).trim();
    if (!openid || !hasPhone) {
      wx.reLaunch({ url: '/pages/my/my' });
      return;
    }
    // 处理页面参数
    this.loadCouponDetail();
    // 初始化车牌数组（7位）
    this.initPlateNumberArray();
  },
  computed: {
    // 优惠券类型文本（适配接口数字类型）
    couponTypeText() {
      // 适配接口返回的数字类型 coupon_type
      const typeMap = {
        1: '折扣券',
        2: '时长券',
        3: '立减券',
        'discount': '折扣券',
        'full_reduction': '满减券',
        'direct': '立减券'
      };
      return typeMap[this.couponType] || '停车优惠券';
    },
    // 完整车牌号
    fullPlateNumber() {
      return this.selectedProvince + this.plateNumber.join('');
    },
    
    // 车牌类型（修正分类逻辑，删除重复定义）
    plateType() {
      const filledLength = this.plateNumber.filter(item => !!item).length;
      return filledLength === 6 ? 1 : (filledLength === 7 ? 2 : 0);
    }
  },
  methods: {
    goBack() {
      wx.navigateBack();
    }, 
    // 初始化车牌数组（7位）
    initPlateNumberArray() {
      this.plateNumber = Array(7).fill('');
    },
	// 车牌是否有效（修正新能源长度规则）
	isPlateValid() {
	  if (!this.selectedProvince) return false;
	  
	  // 过滤空值，获取已输入的有效长度（不含省份）
	  const filledLength = this.plateNumber.filter(item => !!item).length;
	  
	  // 有效规则：
	  // 燃油车：必须填5位 ｜ 新能源车：必须填6位
	  
	  this.isPlateVa = filledLength === 6 || filledLength === 7;
	  console.log(this.isPlateVa);
	  return filledLength === 6 || filledLength === 7;
	},
	async  fetchUserWhoami() {
	  // 接口基础配置
	  const baseUrl = "https://user-api.4pyun.com/rest/2.0/user/whoami";
	  const encryptKey = "riegh^ee:w0fok5je5eeS{eecaes1nep"; // 沿用停车券接口加密密钥（实际需按接口要求调整）
	
	    // 1. 处理URL参数（解析原URL中的加密参数，这里还原为明文参数示例，实际需按接口加密规则处理）
	    const params = {
	      // 原URL中加密参数解码后的示例（实际需根据接口要求加密/拼接）
	      "5vX/ve228sXV+PP/+A==": "pw==" 
	    };
	
	    // 2. 拼接URL参数（手动URL编码，避免特殊字符问题）
	    const paramStr = Object.entries(params)
	      .map(([key, value]) => `${encodeURIComponent(key)}=${encodeURIComponent(value)}`)
	      .join("&");
	    const requestUrl = `${baseUrl}?${paramStr}`;
	
	    // 3. 发起小程序原生请求（兼容uni-app可替换为uni.request）
	    const response = await new Promise((resolve, reject) => {
	      wx.request({
	        url: requestUrl,
	        method: "GET",
	        header: {
	          "Accept": "application/json, text/plain, */*",
	          // 携带停车券接口中有效的Authorization令牌（实际需按whoami接口授权要求调整）
	          "Authorization": this.Bearer
	        },
	        timeout: 10000,
	        success: (res) => resolve(res),
	        fail: (err) => reject(err)
	      });
	    });
	
	    // 4. 处理响应结果（适配目标返回格式）
	    const resData = response.data;
	    if (resData && resData.code === "1001") {
	      // 接口返回成功时，直接返回符合格式的数据（若字段不一致可在此映射）
		  this.Bearer = resData.payload.access_token.value;
	      this.identity =  resData.payload.identity;
	      return resData;
	    } else {
		  
	      // 接口返回错误时，返回统一错误格式
	      return resData;
	    }
	  
	},
	async parkingLogin(){
		const baseUrl = 'https://user-api.4pyun.com/rest/2.0/user/login'
		
		const postData = encryptFull({mobile: app.globalData.userInfo.phone, captcha: this.captchaCode, app_id: this.app_id});
		    
		
		// 3. 小程序原生请求（替代 fetch）
		const response = await new Promise((resolve, reject) => {
		  wx.request({
		    url: baseUrl,
		    method: 'POST',
		    header: {
		      'Accept': 'application/json, text/plain, */*',
		      'Authorization': ' Bearer ' + this.Bearer
		    },
			data: postData, 
		    timeout: 10000, // 超时时间
		    success: (res) => resolve(res), // 小程序 res 结构：{ data, statusCode, header }
		    fail: (err) => reject(err)
		  });
		});
		
		const resData = response.data;
		if (resData && resData.code === "1001") {
		    this.Bearer = resData.payload.access_token.type + " " + resData.payload.access_token.value;
			app.setStorageWithExpiry('Bearer',this.Bearer,1440);
			this.app_id = resData.payload.app_id;
			this.showCaptchaPopup = false;
			// 重置验证码输入框
			this.captchaCode = '';
			this.loadCouponDetail();
			wx.showToast({
			  title: '请领取停车优惠',
			  icon: 'none'
			});	
		    
		} else {
			wx.showToast({
			  title: resData.message,
			  icon: 'none'
			});	
		  
		}
	},
	async sendCaptcha(phone){
		const baseUrl = 'https://user-api.4pyun.com/rest/2.0/captcha/create'
		
		const params = {
		  [encryptFull('mobile')]: encryptFull(app.globalData.userInfo.phone),
		  [encryptFull('app_id')]: encryptFull(this.app_id)
		};
		    
		// 2. 手动拼接 URL 参数（替代小程序不支持的 URL 构造函数）
		const paramStr = Object.entries(params)
		  .map(([key, value]) => {
		    // 手动 URL 编码，避免特殊字符问题
		    const encodedKey = encodeURIComponent(key);
		    const encodedValue = encodeURIComponent(value);
		    return `${encodedKey}=${encodedValue}`;
		  })
		  .join('&');
		// 拼接最终 URL（有参数则加 ?，无则直接用 baseUrl）
		const finalUrl = paramStr ? `${baseUrl}?${paramStr}` : baseUrl;
		// 3. 小程序原生请求（替代 fetch）
		const response = await new Promise((resolve, reject) => {
		  wx.request({
		    url: finalUrl,
		    method: 'GET',
		    header: {
		      'Content-Type': 'application/x-www-form-urlencoded',
		      'Accept': 'application/json, text/plain, */*',
		      
		    },
		    timeout: 10000, // 超时时间
		    success: (res) => resolve(res), // 小程序 res 结构：{ data, statusCode, header }
		    fail: (err) => reject(err)
		  });
		});
		
		const resData = response.data;
		if (resData && resData.code === "1001") {
			wx.showToast({
			  title: '请验证手机',
			  icon: 'none'
			});	
			this.showCaptchaPopup = true;
			// 重置验证码输入框
			this.captchaCode = '';
		    
		} else {
			wx.showToast({
			  title: resData.message,
			  icon: 'none'
			});	
		  
		}
	},
	// 新增：关闭验证码弹窗
    closeCaptchaPopup() {
      this.showCaptchaPopup = false;
      this.captchaCode = ''; // 关闭时清空验证码
    },
    // 加载优惠券详情（适配真实接口格式，已修复所有错误，支持车牌号自动填充）
    async loadCouponDetail() {
      try {
        wx.showLoading({ title: '加载中...' });
		
		this.Bearer = app.getStorageWithExpiry('Bearer');
		console.log(this.Bearer);
		if(!this.Bearer){
			this.sendCaptcha();
			return
		}
        const UserData = await this.fetchUserWhoami();
		
		if(UserData.message === '令牌已失效'){
			await this.sendCaptcha();
			return
		}
        console.log(this.Bearer);
        const encryptKey = "riegh^ee:w0fok5je5eeS{eecaes1nep"; // 加密密钥（必须）
        const baseUrl = "https://user-api.4pyun.com/rest/2.0/parking/mcoupon/token/verify";
    
        const params = {
          [encryptFull('identity', encryptKey)]: encryptFull(this.identity, encryptKey),
          [encryptFull('token', encryptKey)]: encryptFull(this.token, encryptKey)
        };
    
        // 2. 手动拼接 URL 参数（替代小程序不支持的 URL 构造函数）
        const paramStr = Object.entries(params)
          .map(([key, value]) => {
            // 手动 URL 编码，避免特殊字符问题
            const encodedKey = encodeURIComponent(key);
            const encodedValue = encodeURIComponent(value);
            return `${encodedKey}=${encodedValue}`;
          })
          .join('&');
        // 拼接最终 URL（有参数则加 ?，无则直接用 baseUrl）
        const finalUrl = paramStr ? `${baseUrl}?${paramStr}` : baseUrl;
    
        // 3. 小程序原生请求（替代 fetch）
        const response = await new Promise((resolve, reject) => {
          wx.request({
            url: finalUrl,
            method: 'GET',
            header: {
              'Content-Type': 'application/x-www-form-urlencoded',
              'Accept': 'application/json, text/plain, */*',
              'Authorization': ' Bearer ' + this.Bearer
            },
            timeout: 10000, // 超时时间
            success: (res) => resolve(res), // 小程序 res 结构：{ data, statusCode, header }
            fail: (err) => reject(err)
          });
        });
    
        wx.hideLoading();
    
        // 4. 适配小程序响应结构（核心：response.data 才是接口返回的实际数据）
        const resData = response.data;
        if (resData && resData.code === "1001" && resData.payload) {
          const payload = resData.payload;
    
          // 修复1：Vue 中直接赋值（替换 setData）
          // 基础信息赋值
          this.couponName = payload.coupon_name || '';
          this.couponType = payload.coupon_type || 'direct';
          this.couponValue = payload.coupon_value || 0;
          this.parkingLotName = payload.park_name || payload.merchant_name || '未知停车场';
          this.servicePhone = payload.service_phone || '暂无';
          this.couponValidity = payload.validity || '2025-01-01 至 2025-12-31';
		  this.plate = payload.plate || '';
		  
		  
          // 格式化优惠券描述（分钟转小时）
          let couponDescription = '';
          // 修复2：Vue 中直接通过 this.xxx 获取属性（替换 this.data.xxx）
          const { couponType, couponValue } = this;
          if (couponType == 2) { // 时长券
            const hours = Math.floor(couponValue / 60);
            const minutes = couponValue % 60;
            if (hours > 0) {
              couponDescription = minutes > 0
                ? `凭此券可享受${hours}小时${minutes}分钟停车时长优惠，单次停车限用1张`
                : `凭此券可享受${hours}小时停车时长优惠，单次停车限用1张`;
            } else {
              couponDescription = `凭此券可享受${minutes}分钟停车时长优惠，单次停车限用1张`;
            }
          } else {
            couponDescription = payload.coupon_desc || '';
          }
          // 直接赋值 couponDescription
          this.couponDescription = couponDescription;
    
          // 自动填充省份前缀
          let plateProvince = ''; // 错误修复：先声明初始化 plateProvince 变量
          if (payload.row && payload.row.length > 0 && payload.row[0].plate_prefix) {
            const platePrefix = payload.row[0].plate_prefix;
            plateProvince = platePrefix.substring(0, 1); // 赋值给 plateProvince
            this.selectedProvince = plateProvince; // 直接赋值
          }
    
          
          const fullPlateNumber = payload.plate || (payload.row && payload.row.length > 0 ? payload.row[0].plate_number || '' : '');
          
          if (fullPlateNumber){
			let plateNumWithoutProvince = '';
            
            if (plateProvince && fullPlateNumber.startsWith(plateProvince)) {
              
              plateNumWithoutProvince = fullPlateNumber.slice(plateProvince.length);
            } else {
             
              const provinceList = this.provinceList; 
              for (const province of provinceList) {
                if (fullPlateNumber.startsWith(province)) {
                  plateProvince = province;
                  this.selectedProvince = province;
                  plateNumWithoutProvince = fullPlateNumber.slice(province.length);
                  break;
                }
              }
              
              if (!plateProvince) {
                plateNumWithoutProvince = fullPlateNumber;
              }
            
          }
			
    
            // 3. 初始化 plateNumber 数组（清空原有内容）
            this.plateNumber = Array(7).fill('');
    
            // 4. 将车牌号拆分为单个字符，填充到 plateNumber 数组中
            const plateChars = plateNumWithoutProvince.split('');
            plateChars.forEach((char, index) => {
              if (index < 7) { // 不超过数组长度7
                this.plateNumber[index] = char;
              }
            });
    
            // 5. 若车牌号长度为6（新能源车），自动启用最后一位格子
            if (plateChars.length === 7) {
              this.enableLastPlate = true;
            }
          }
		  this.validatePlate();	
          // 生成使用规则
          // 修复3：直接通过 this.xxx 获取属性（替换 this.data.xxx）
          const { parkingLotName, servicePhone } = this;
          const couponRules = [
            `1. 本券仅限${parkingLotName}使用`,
            '2. 每车牌限领1张',
            '3. 券有效期内使用',
            servicePhone !== '暂无' ? `4. 客服电话：${servicePhone}` : ''
          ].filter(rule => rule);
          // 直接赋值 couponRules
          this.couponRules = couponRules;
    
        } else {
          // 修复4：增加 resData 存在性判断，避免兜底失败
          const errorMsg = resData?.message || '获取优惠券信息失败';
          wx.showToast({
            title: errorMsg,
            icon: 'none'
          });
        }
      } catch (error) {
        wx.hideLoading();
        console.error("加载优惠券详情失败:", error);
        wx.showToast({
          title: '网络异常，请重试',
          icon: 'none'
        });
      }
    },
    
    // 日期格式化工具方法
    formatDate(dateStr) {
      if (!dateStr) return '';
      // 简单的日期格式化，可根据实际需求扩展
      const date = new Date(dateStr);
      return `${date.getFullYear()}-${(date.getMonth() + 1).toString().padStart(2, '0')}-${date.getDate().toString().padStart(2, '0')}`;
    },
    
    // 选择省份
    selectProvince(province) {
      this.selectedProvince = province;
      this.showProvinceKeyboard = false;
      this.errorMsg = '';
    },
    
    // 打开数字字母键盘（核心修改：点击最后一格时启用）
    openNumberKeyboard(index) {
      if (!this.selectedProvince) {
        wx.showToast({
          title: '请先选择省份',
          icon: 'none'
        });
        return;
      }
      
      // 点击最后一格（第7位，索引6）时，启用该格
      if (index === 6) {
        this.enableLastPlate = true;
      }
      
      this.currentInputIndex = index;
      this.showNumberKeyboard = true;
      
    },
    
    // 关闭数字字母键盘
    closeNumberKeyboard() {
      this.showNumberKeyboard = false;
    },
    
    // 输入字符
    inputCharacter(char) {
      // 设置当前位置的字符
      this.plateNumber[this.currentInputIndex] = char;
      console.log(this.plateNumber);
      // 自动切换到下一个位置（最后一格除外，需手动点击）
      if (this.currentInputIndex < 7 || (this.currentInputIndex === 7 && this.enableLastPlate)) {
        this.currentInputIndex = Math.min(this.currentInputIndex + 1, 7);
      }
	  if (this.currentInputIndex === 6) {
	    this.enableLastPlate = true;
	  }
      if (this.currentInputIndex === 7) {
        this.closeNumberKeyboard();
      }
      // 校验车牌格式
      this.validatePlate();
    },
    
    // 删除字符
    deleteCharacter() {
      // 清空当前位置
      this.plateNumber[this.currentInputIndex] = '';
      console.log(this.plateNumber);
      // 自动切换到上一个位置
      if (this.currentInputIndex > 0) {
        this.currentInputIndex--;
      }
      
      // 如果最后一格为空，禁用它
      if (this.currentInputIndex < 6 && !this.plateNumber[6]) {
        this.enableLastPlate = false;
      }
      
      // 校验车牌格式
      this.validatePlate();
    },
    
    // 校验车牌格式（修正新能源车牌长度错误）
    validatePlate() {
      this.errorMsg = '';
      if (!this.selectedProvince) return;
      
      const plateStr = this.plateNumber.join('');
      // 过滤空格，获取实际输入的车牌号长度（不含省份）
      const filledLength = plateStr.replace(/\s/g, '').length;
      
      // 只在输入完成后进行格式校验
      if (this.isPlateValid()) {
        // 1. 第一位必须是字母（燃油车/新能源车通用规则）
        const firstChar = this.plateNumber[0];
        if (!/^[A-Z]$/.test(firstChar)) {
          this.errorMsg = '车牌号第一位必须是字母';
          return;
        }
        
        // 2. 完整车牌格式校验（严格遵循交规）
        const fullPlate = this.selectedProvince + this.plateNumber.join('');
        
        // 正确的正则规则：
        // 燃油车：省份 + 1位字母 + 4位数字/字母（总长度6位）
        const fuelReg = /^[京津沪渝冀晋蒙辽吉黑苏浙皖闽赣鲁豫鄂湘粤桂琼川贵云陕甘青宁新藏][A-Z][A-Z0-9]{5}$/; 
        // 新能源车：省份 + 1位字母 + 5位数字/字母（总长度7位，全国统一）
        const newEnergyReg = /^[京津沪渝冀晋蒙辽吉黑苏浙皖闽赣鲁豫鄂湘粤桂琼川贵云陕甘青宁新藏][A-Z][A-Z0-9]{6}$/; 
        console.log(fullPlate);
        // 根据输入长度匹配对应规则（核心修正）
        if (filledLength === 6) {
          // 输入5位车牌号 → 燃油车，校验燃油车规则
          if (!fuelReg.test(fullPlate)) {
            this.errorMsg = '车牌号格式不正确';
          }
        } else if (filledLength === 7) {
          // 输入6位车牌号 → 新能源车，校验新能源车规则
          if (!newEnergyReg.test(fullPlate)) {
            this.errorMsg = '车牌号格式不正确';
          }
        }
      }
    },
    
    // 领取优惠券
    async receiveCoupon() {
      // 最终校验
      this.validatePlate();
	  
      if (this.errorMsg) {
        wx.showToast({
          title: this.errorMsg,
          icon: 'none'
        });
        return;
      }
      
      // 检查是否选择省份
      if (!this.selectedProvince) {
        wx.showToast({
          title: '请选择车牌省份',
          icon: 'none'
        });
        return;
      }
      
      // 检查是否输入完整车牌
      if (!this.isPlateValid) {
        wx.showToast({
          title: '请输入完整的车牌号',
          icon: 'none'
        });
        return;
      }
      
      // 检查是否登录
      if (!app.globalData.openid) {
        wx.showToast({
          title: '请先登录小程序',
          icon: 'none'
        });
        // 这里可以添加跳转到登录页的逻辑
        return;
      }
      
      this.isReceiving = true;
	  testDecrypt();
      testEncrypt();
      try {
        const plateNumStr = this.selectedProvince + this.plateNumber.join('');
	    const finalUrl = 'https://user-api.4pyun.com/rest/2.0/parking/mcoupon/token/grant'
		const data = {app_id: this.app_id, plate: plateNumStr, token: this.token, identity: this.identity}
		
		console.log(data);
	    const postData = encryptFull(data)
	    console.log(postData);
	  
	    const response = await new Promise((resolve, reject) => {
            wx.request({
            url: finalUrl,
            method: 'POST',
            header: {
              
              'Accept': 'application/json, text/plain, */*',
              'Authorization': ' Bearer ' + this.Bearer
            },
			data: postData, 
            timeout: 10000, // 超时时间
            success: (res) => resolve(res), // 小程序 res 结构：{ data, statusCode, header }
            fail: (err) => reject(err)
          });
        });
        
		// 1. 提取接口返回的实际数据（小程序 wx.request 中，response.data 才是接口返回的JSON对象）
		const resData = response.data;
		console.log("领取优惠券接口返回：", resData); // 打印日志，方便调试

		// 2. 根据 code 字段判断业务状态
		if (resData) {
		  // 成功状态（假设 1001 为领取成功，可根据实际接口调整）
		  if (resData.code === "1001") {
			wx.showToast({
			  title: '优惠券领取成功',
			  icon: 'success',
			  duration: 2000
			});
			// 领取成功后，延迟返回上一页
			setTimeout(() => {
			  wx.navigateBack({
				delta: 1 // 返回上一级页面
			  });
			}, 1500);
		  } 
		  // 失败状态（如你提供的 1002 未查询到停车记录，及其他错误码）
		  else {
			const errorMsg = resData.message || '领取优惠券失败';
			wx.showToast({
			  title: errorMsg,
			  icon: 'none',
			  duration: 2000
			});
			// 可根据具体错误码做个性化处理（示例）
			if (resData.code === "1002") {
			  console.warn("领取失败原因：", resData.message);
			  // 额外逻辑：如引导用户去停车记录页面，或提示补充停车信息
			  // wx.showModal({
			  //   title: '提示',
			  //   content: '未查询到你的停车记录，无法领取优惠券',
			  //   showCancel: false,
			  //   confirmText: '我知道了'
			  // });
			}
		  }
		} 
       
      } catch (error) {
        console.error("领取优惠券失败:", error);
        wx.showToast({
          title: '网络异常，领取失败',
          icon: 'none'
        });
      } finally {
        this.isReceiving = false;
      }
    }
  }
}
</script>

<style scoped>
.captcha-popup {
  position: fixed;
  top: 0;
  left: 0;
  right: 0;
  bottom: 0;
  z-index: 999; /* 确保弹窗在最上层 */
}

.captcha-mask {
  width: 100%;
  height: 100%;
  background-color: rgba(0, 0, 0, 0.5);
}

.captcha-content {
  position: absolute;
  top: 50%;
  left: 50%;
  transform: translate(-50%, -50%);
  width: 80%;
  max-width: 500rpx;
  background-color: #fff;
  border-radius: 20rpx;
  padding: 40rpx 30rpx;
  box-sizing: border-box;
}

.captcha-title {
  font-size: 36rpx;
  font-weight: bold;
  text-align: center;
  margin-bottom: 20rpx;
  color: #333;
}

.captcha-desc {
  font-size: 28rpx;
  text-align: center;
  color: #666;
  margin-bottom: 30rpx;
}

.captcha-input {
  width: 100%;
  height: 80rpx;
  border: 2rpx solid #eee;
  border-radius: 10rpx;
  padding: 0 20rpx;
  box-sizing: border-box;
  font-size: 30rpx;
  margin-bottom: 30rpx;
}

.captcha-placeholder {
  color: #999;
  font-size: 28rpx;
}

.captcha-btn-group {
  display: flex;
  justify-content: space-between;
  gap: 20rpx;
}

.captcha-close-btn {
  flex: 1;
  height: 80rpx;
  background-color: #f5f5f5;
  color: #666;
  border: none;
  border-radius: 10rpx;
  font-size: 30rpx;
}

.captcha-confirm-btn {
  flex: 1;
  height: 80rpx;
  background-color: #ff5117;
  color: #fff;
  border: none;
  border-radius: 10rpx;
  font-size: 30rpx;
}

.captcha-confirm-btn:disabled {
  background-color: #ccc;
  color: #fff;
  opacity: 0.8;
}	
/* 基础样式 */
.parking-coupon-page {
  background-color: #f8f8f8;
  min-height: 100vh;
  display: flex;
  flex-direction: column;
  width: 100%;
}

/* 主内容区：修复高度计算 */
.main-content {
  flex: 1;
  height: calc(100vh - 90rpx); /* 只减去底部按钮高度 */
  overflow-y: auto;
  padding: 20rpx;
  box-sizing: border-box;
}

/* 优惠券卡片：强制生效样式 */
.coupon-card {
  background-color: #ffffff !important;
  border-radius: 16rpx;
  padding: 30rpx;
  box-shadow: 0 2rpx 10rpx rgba(0, 0, 0, 0.05);
  margin-bottom: 20rpx;
}

/* 停车信息区域 */
.parking-info {
  margin-bottom: 30rpx;
}

.info-item {
  display: flex;
  align-items: center;
  padding: 20rpx 0;
  border-bottom: 1rpx solid #f5f5f5;
}

.info-item:last-child {
  border-bottom: none;
}

.label {
  font-size: 28rpx;
  color: #666666;
  width: 180rpx;
}

.value {
  font-size: 28rpx;
  color: #333333;
  flex: 1;
}

/* 优惠券详情 */
.coupon-detail {
  margin-bottom: 30rpx;
}

.detail-title {
  font-size: 30rpx;
  font-weight: bold;
  padding: 20rpx 0;
  border-bottom: 1rpx solid #f5f5f5;
  margin-bottom: 10rpx;
}

.detail-item {
  padding: 15rpx 0;
}

.detail-name {
  font-size: 30rpx;
  font-weight: bold;
  color: #e10606;
  margin-bottom: 10rpx;
}

.detail-desc {
  font-size: 26rpx;
  color: #666;
  line-height: 1.5;
}

/* 使用规则 */
.rule-section {
  margin-top: 20rpx;
  padding-top: 20rpx;
  border-top: 1rpx solid #f5f5f5;
}

.rule-label {
  font-size: 28rpx;
  font-weight: bold;
  margin-bottom: 15rpx;
}

.rule-content {
  font-size: 26rpx;
  color: #666;
  line-height: 1.6;
}

.rule-item {
  display: block;
  margin-bottom: 8rpx;
}

/* 车牌输入区域 */
.plate-input-section {
  margin-top: 20rpx;
  padding-top: 20rpx;
  border-top: 1rpx solid #f5f5f5;
}

.plate-label {
  font-size: 28rpx;
  font-weight: bold;
  margin-bottom: 15rpx;
}

/* 方格式车牌输入容器（核心修复：8个格子完整显示） */
.plate-grid-wrapper {
  display: flex;
  align-items: center;
  gap: 6rpx; /* 进一步缩小间距 */
  margin-bottom: 20rpx;
  /* 关键修复：移除center居中，改为flex-start，确保从左侧开始显示 */
  justify-content: flex-start;
  flex-wrap: nowrap;
  width: 100%;
  overflow-x: auto;
  padding: 10rpx 0;
  /* 关键修复：设置最小宽度，确保8个格子能完整显示 */
  min-width: 620rpx;
  /* 隐藏滚动条但保留滚动功能 */
  scrollbar-width: none;
  -ms-overflow-style: none;
}

/* 隐藏滚动条 */
.plate-grid-wrapper::-webkit-scrollbar {
  display: none;
}

/* 车牌格子样式（微调尺寸，确保8个格子适配） */
.plate-grid-item {
  width: 68rpx; /* 稍微缩小宽度 */
  height: 80rpx;
  border: 1rpx solid #e6e6e6;
  border-radius: 8rpx;
  display: flex;
  justify-content: center;
  align-items: center;
  font-size: 32rpx;
  color: #333;
  background-color: #fff;
  touch-action: manipulation;
  flex-shrink: 0; /* 防止压缩 */
}

/* 省份格子样式 */
.province-item {
  background-color: #f8f8f8;
}

/* 已填充样式 */
.plate-grid-item.filled {
  border-color: #e10606;
  background-color: #fff;
}

/* 最后一格禁用样式（默认灰色，核心样式） */
.plate-grid-item.disabled {
  background-color: #f0f0f0 !important;
  color: #999 !important;
  border-color: #ddd !important;
  cursor: not-allowed;
}

/* 错误提示 */
.error-tip {
  font-size: 24rpx;
  margin-bottom: 20rpx;
  padding-left: 5rpx;
}

/* 底部占位 */
.bottom-placeholder {
  height: 200rpx;
}
/* 按钮可用状态样式 */
.receive-coupon-btn {
  background: linear-gradient(to right,#ff5117,#f0331a,#e10606,#d30606);
  color: #fff !important; /* 明确可用状态文字颜色 */
  cursor: pointer;
}
/* 领取按钮禁用态 */
.receive-coupon-btn-disabled {
  background: #cccccc !important; /* 强制覆盖可用状态背景 */
  color: #f0f0f0 !important; /* 禁用状态文字灰色 */
  opacity: 0.8 !important;
  cursor: not-allowed !important;
  pointer-events: none !important; /* 额外添加：阻止点击事件触发（兜底方案） */
}
/* 自定义键盘样式 */
.custom-keyboard {
  position: fixed;
  bottom: 0;
  left: 0;
  right: 0;
  z-index: 9999;
}

.keyboard-mask {
  position: fixed;
  top: 0;
  left: 0;
  right: 0;
  bottom: 0;
  background-color: rgba(0, 0, 0, 0.5);
}

.keyboard-content {
  position: fixed;
  bottom: 0;
  left: 0;
  right: 0;
  background-color: #fff;
  border-radius: 16rpx 16rpx 0 0;
  padding: 20rpx;
}

.keyboard-title {
  font-size: 30rpx;
  font-weight: bold;
  text-align: center;
  padding: 10rpx 0;
  border-bottom: 1rpx solid #eee;
  margin-bottom: 20rpx;
}

/* 省份键盘样式 */
.province-grid {
  display: flex;
  flex-wrap: wrap;
  gap: 15rpx;
  justify-content: space-between;
  max-height: 500rpx;
  overflow-y: auto;
}

.province-grid .province-item {
  width: calc(20% - 10rpx);
  height: 80rpx;
  display: flex;
  justify-content: center;
  align-items: center;
  background-color: #f8f8f8;
  border-radius: 8rpx;
  font-size: 28rpx;
  color: #333;
}

.province-grid .province-item:active {
  background-color: #e10606;
  color: #fff;
}

/* 数字字母键盘样式 */
.number-grid {
  display: flex;
  flex-wrap: wrap;
  gap: 10rpx;
  justify-content: space-between;
}

.key-item {
  width: calc(10% - 8rpx);
  height: 80rpx;
  display: flex;
  justify-content: center;
  align-items: center;
  background-color: #f8f8f8;
  border-radius: 8rpx;
  font-size: 32rpx;
  color: #333;
}

.key-item.backspace {
  width: calc(10% - 8rpx);
  background-color: #e10606;
  color: #fff;
}

.key-item:active {
  background-color: #e0e0e0;
}

.key-item.backspace:active {
  background-color: #c00505;
}
</style>