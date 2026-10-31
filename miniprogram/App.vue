
<script>
	import { getBaseUrl, requestUtil } from './utils/requestUtil.js';
	import { parseTableNumberFromScanCodeResult } from './utils/tableQrParse.js';
	import {
		parseReviewFromBusinessResponse,
		QUEUE_TICKET_PAGE,
		isQueueTicketRoute,
	} from './utils/reviewMode.js';
	import { prefetchActivityPopupOnLaunch } from './utils/globalActivityPopup.js';
	import { requestGetPrepayId, persistOpenidFromResponse, WX_LOGIN_EXPIRED_CODE } from './utils/wxAuth.js';
	import { getStoredUserToken, persistUserAuthFromResponse } from './utils/userAuthToken.js';
	import { ensureUnifiedNotifySocketStarted } from './utils/unifiedNotifyCenter.js';
	import {
		fetchPaymentCapabilities,
		isWechatPayAvailable,
		resolvePaymentApiErrorMessage,
		resolveWechatPayDisabledMessage,
		PAYMENT_ONLINE_DISABLED_CODE,
		PAYMENT_CHANNEL_DISABLED_CODE,
		PAYMENT_WECHAT_MERCHANT_MISSING_CODE,
	} from './utils/paymentCapabilities.js';

	export default {
		globalData: {
			backUrl:"",
			isLogin: false,
			isReviewMode: false,
			isReviewModeUpdatedAt: 0,
			invite_code:'',
		    openid: null,  // 初始化openid为null
		    userToken: '',
		    userInfo: {
				avatar: '',      // 头像
				nickname: '',    // 昵称
				phone: '',       // 手机号
				points: 0,       // 积分
				balance: 0       // 账户余额（元），与 getUserInfo data.balance 一致
			  } ,// 可以同时存储其他用户信息
			activity_record:{
				activity_id:"",
				time:"",
				type:"",
				name:""
			}
		},
		event: {
		  listeners: {},
		  on(event, callback) {
		    if (!this.listeners[event]) {
		      this.listeners[event] = [];
		    }
		    this.listeners[event].push(callback);
		    return callback; // 返回回调以便移除监听
		  },
		  off(event, callback) {
		    if (this.listeners[event]) {
		      this.listeners[event] = this.listeners[event].filter(fn => fn !== callback);
		    }
		  },
		  emit(event, ...args) {
		    if (this.listeners[event]) {
		      this.listeners[event].forEach(callback => callback(...args));
		    }
		  }
		},
		onShow() {
			ensureUnifiedNotifySocketStarted();
		},
		onLaunch() {
			// 启动时检测更新
			this.checkUpdate()
			
			this.globalData.openid = wx.getStorageSync('openid');
			this.globalData.userToken = getStoredUserToken();
			this.globalData.userInfo = wx.getStorageSync('userInfo');
			console.log(this.globalData.isLogin,this.globalData.openid);
			if (this.globalData.openid) {
			  this.globalData.isLogin = true;
			  this.getUserInfo();
			  prefetchActivityPopupOnLaunch(this);
			  console.log(this.globalData.userInfo);
			} 
			
			// 获取设备型号（wx.getSystemInfo 已废弃，改用 wx.getWindowInfo）
			try {
				const res = wx.getWindowInfo();
				this.globalData.Modelmes = !!(res.safeArea && res.safeArea.top > 40);
			} catch (e) {
				this.globalData.Modelmes = false;
			}

			// 审核态：启动即拉取开关，为真则强制进入排队取号页
			this.fetchReviewMode(true).then((review) => {
				if (review && typeof this.guardToQueueIfReview === "function") {
					this.guardToQueueIfReview({ skipFetch: true });
				}
			});
		},
		methods:{
			/**
			 * 拉取审核态开关（POST /order/Business）
			 * @param {boolean} force 是否强制刷新
			 * @returns {Promise<boolean>}
			 */
			async fetchReviewMode(force = false) {
				const now = Date.now();
				const ttl = 60 * 1000;
				if (!force && this.globalData.isReviewModeUpdatedAt && (now - this.globalData.isReviewModeUpdatedAt) < ttl) {
					return !!this.globalData.isReviewMode;
				}
				if (this._reviewModePromise) {
					return this._reviewModePromise;
				}
				this._reviewModePromise = requestUtil({
					url: "/order/Business",
					method: "post",
					showLoading: false
				}).then((res) => {
					const review = parseReviewFromBusinessResponse(res);
					this.globalData.isReviewMode = review;
					this.globalData.isReviewModeUpdatedAt = Date.now();
					return review;
				}).catch(() => {
					return !!this.globalData.isReviewMode;
				}).finally(() => {
					this._reviewModePromise = null;
				});
				return this._reviewModePromise;
			},
			/**
			 * 审核态仅展示排队页：若 isReview=true，则强制跳转排队页
			 * @param {{ force?: boolean }} options
			 * @returns {Promise<boolean>} 是否已触发跳转
			 */
			async guardToQueueIfReview(options = {}) {
				const review = options.skipFetch
					? !!this.globalData.isReviewMode
					: await this.fetchReviewMode(!!options.force);
				if (!review) return false;
				const pages = getCurrentPages();
				const current = pages && pages.length ? pages[pages.length - 1] : null;
				const route = current && current.route ? String(current.route) : "";
				if (isQueueTicketRoute(route)) return false;
				wx.reLaunch({
					url: QUEUE_TICKET_PAGE,
				});
				return true;
			},
			
			checkUpdate() {
				// 判断当前微信版本是否支持更新管理器（基础库 1.9.90+）
				if (!wx.canIUse('getUpdateManager')) {
				  return
				}
				const updateManager = wx.getUpdateManager()
				// 必须先注册 onUpdateReady/onUpdateFailed，再触发检查，否则异步下载完成时可能已错过回调（官方文档写法）
				updateManager.onUpdateReady(() => {
				  wx.showModal({
					title: '更新提示',
					content: '新版本已经准备好，是否立即重启应用？',
					success(res) {
					  if (res.confirm) {
						updateManager.applyUpdate()
					  }
					}
				  })
				})
				updateManager.onUpdateFailed(() => {
				  wx.showModal({
					title: '更新提示',
					content: '新版本下载失败，请稍后重新打开小程序或删除后重新搜索打开。',
					showCancel: false
				  })
				})
				// 向微信后台请求检查更新结果（有更新时会异步下载，下载完成后触发 onUpdateReady）
				updateManager.onCheckForUpdate((res) => {
				  if (res.hasUpdate) {
					console.log('检测到新版本，后台下载中…')
				  }
				})
			},

			checkLogin(url){
				if(url){
					this.globalData.backUrl = url;
				}
				const userInfo = this.globalData.userInfo || {};
				const hasPhone = userInfo.phone && String(userInfo.phone).trim();
				if(!this.globalData.isLogin || !hasPhone) {
					wx.reLaunch({ url: '/pages/my/my' });
				} else {
					this.globalData.backUrl = "";
				}
			},
			/**
			 * 全局扫码方法：统一调用 wx.scanCode，页面可自定义成功/失败回调
			 * @param {Object} options
			 * @param {boolean} [options.onlyFromCamera=true] 是否仅允许相机扫码
			 * @param {boolean} [options.verifyTableNumber=true] 是否校验台号存在（GET /order/table_verify；若扫码含 shop_id 会一并作为 query 传入）
			 * @param {(res: any) => void} [options.onSuccess] 扫码成功回调
			 * @param {(err: any) => void} [options.onFail] 扫码失败回调
			 */
			scanCode({ onlyFromCamera = true, verifyTableNumber = true, onSuccess, onFail } = {}) {
				wx.scanCode({
					onlyFromCamera,
					success: async (res) => {
						
						if (verifyTableNumber) {
							const { tableNumber, shopId } = parseTableNumberFromScanCodeResult(res);
							if (!tableNumber) {
								const err = { errMsg: 'scanCode:fail invalid table number' };
								wx.showToast({ title: '未识别到有效台号', icon: 'none' });
								if (typeof onFail === 'function') onFail(err);
								return;
							}
							try {
								const verifyData = { number: tableNumber };
								if (shopId != null && Number.isFinite(shopId) && shopId > 0) {
									verifyData.shop_id = shopId;
								}
								const verifyRes = await requestUtil({
									url: '/order/table_verify',
									method: 'get',
									data: verifyData,
									showLoading: false
								});
								if (!verifyRes || verifyRes.code !== 0) {
									const err = { errMsg: 'scanCode:fail table number not found', tableNumber, verifyRes };
									wx.showToast({ title: '桌号不存在，请重扫', icon: 'none' });
									if (typeof onFail === 'function') onFail(err);
									return;
								}
							} catch (e) {
								const err = { errMsg: 'scanCode:fail table verify error', tableNumber, error: e };
								wx.showToast({ title: '台号校验失败，请重试', icon: 'none' });
								if (typeof onFail === 'function') onFail(err);
								return;
							}
						}
						if (typeof onSuccess === 'function') {
							onSuccess(res);
						}
					},
					fail: (err) => {
						if (typeof onFail === 'function') {
							onFail(err);
							return;
						}
						if (err.errMsg === 'scanCode:fail cancel') {
							wx.showToast({ title: '已取消扫码', icon: 'none' });
						} else {
							wx.showToast({ title: '扫码失败，请重试', icon: 'none' });
						}
					}
				});
			},

			/**
			 * 获取用户信息（契约：POST /order/getUserInfo，body { openid }，成功返回 code、data（User）、couponCount）
			 * @param {{ showLoading?: boolean }} [options] showLoading 默认 true；轮询/静默刷新时传 false
			 * @returns {Promise<{ code: number, data?: object, couponCount?: number, msg?: string }>}
			 */
			async getUserInfo(options = {}) {
				const showLoading = options.showLoading !== false;
				const openid = this.globalData.openid;
				const emptyUserInfo = { avatar: '', nickname: '', name: '', phone: '', points: 0, couponCount: 0, birthday: '', balance: 0 };
				if (!openid) {
					console.warn('getUserInfo: 无 openid，请先登录');
					this.globalData.userInfo = emptyUserInfo;
					this.globalData.isLogin = false;
					wx.setStorageSync('userInfo', emptyUserInfo);
					return { code: -1, msg: '未登录' };
				}
				try {
					const res = await requestUtil({
						url: '/order/getUserInfo',
						method: 'post',
						data: { openid },
						showLoading,
					});
					if (res && res.code === 0 && res.data) {
						const { session_key, ...data } = res.data;
						const userInfo = {
							...data,
							couponCount: res.couponCount != null ? res.couponCount : (data.couponCount != null ? data.couponCount : 0)
						};
						this.globalData.userInfo = userInfo;
						wx.setStorageSync('userInfo', userInfo);
						return res;
					}
					this.globalData.userInfo = emptyUserInfo;
					this.globalData.isLogin = false;
					wx.setStorageSync('userInfo', emptyUserInfo);
					return res || { code: -1, msg: '获取用户信息失败' };
				} catch (e) {
					console.error('getUserInfo 请求失败:', e);
					this.globalData.userInfo = emptyUserInfo;
					this.globalData.isLogin = false;
					wx.setStorageSync('userInfo', emptyUserInfo);
					return { code: -1, msg: (e && e.errMsg) || '网络异常' };
				}
			},
			wxLogin() {
			  return new Promise((resolve, reject) => {
			    wx.login({
			      success: async (res) => {
			        if (res.code) {
			          try {
			            const response = await requestUtil({
			              url: "/order/getOpenid",
			              data: {
			                code: res.code
			              },
			              method: "post"
			            });
			            console.log(res.code);
			            if (response.code === 0) {
						  persistUserAuthFromResponse(response, this);
						  if (this.globalData.openid) {
			                resolve(this.globalData.openid);
						  } else {
			                reject(new Error('获取openid失败: 后端未返回openid'));
						  }
			            } else {
			              console.error('获取openid失败:', response.msg);
			              reject(new Error('获取openid失败: ' + response.msg));
			            }
			          } catch (error) {
			            console.error('请求后端接口失败:', error);
			            reject(error);
			          }
			        } else {
			          console.error('登录失败:', res.errMsg);
			          reject(new Error('登录失败: ' + res.errMsg));
			        }
			      },
			      fail: (err) => {
			        console.error('wx.login调用失败:', err);
			        reject(err);
			      }
			    });
			  });
			},
			// 存储带有效期的缓存
			setStorageWithExpiry(key, data, expiryMinutes = 15) {
			  const item = {
			    data: data,
			    expiry: Date.now() + expiryMinutes * 60 * 1000 // 计算过期时间戳
			  };
			  wx.setStorageSync(key, item);
			},
			// 获取带有效期的缓存
			getStorageWithExpiry(key) {
			  const item = wx.getStorageSync(key);
			  
			  // 缓存不存在
			  if (!item) return null;
			  
			  // 缓存已过期
			  if (Date.now() > item.expiry) {
			    wx.removeStorageSync(key); // 清除过期缓存
			    return null;
			  }
			  
			  // 缓存有效，返回数据
			  return item.data;
			},
			/**
			 * 统一订单结账流程（全局）：调用 /order/getPrepayId + wx.requestPayment，按 openapi 处理换单与失败
			 * @param {Object} params
			 * @param {string} params.orderNo 订单号
			 * @param {number} params.totalAmount 实付金额（必填，单位元）
			 * @param {string} params.dineInOrTakeOut 用餐方式：堂食/打包 等
			 * @param {string|number} [params.coupon_id] 用户优惠券ID（t_user_coupon.id）
			 * @param {string} [params.coupon_type] 优惠券类型 full_reduction/discount/direct_reduction
			 * @param {number} [params.discount_amount] 优惠金额
			 * @returns {Promise<{ success: boolean, response?: any, error?: any, newOrderNo?: string }>}
			 */
			async payOrder({ orderNo, totalAmount, dineInOrTakeOut, coupon_id = '', coupon_type = '', discount_amount = 0 } = {}) {
				if (!orderNo || totalAmount == null) {
					return { success: false, error: new Error('缺少必要的支付参数 orderNo/totalAmount') };
				}
				const openid = this.globalData.openid || wx.getStorageSync('openid');
				if (!openid) {
					wx.switchTab({ url: '/pages/my/my' });
					return { success: false, error: new Error('未登录小程序（缺少 openid）') };
				}
				const paymentCaps = await fetchPaymentCapabilities({ orderNo });
				if (!isWechatPayAvailable(paymentCaps)) {
					const msg = resolveWechatPayDisabledMessage(paymentCaps);
					let errCode = PAYMENT_CHANNEL_DISABLED_CODE;
					if (paymentCaps && !paymentCaps.onlinePayEnabled) {
						errCode = PAYMENT_ONLINE_DISABLED_CODE;
					} else if (paymentCaps && paymentCaps.wechatMerchantReady === false) {
						errCode = PAYMENT_WECHAT_MERCHANT_MISSING_CODE;
					}
					return {
						success: false,
						response: { code: errCode, msg },
						error: new Error(msg),
					};
				}
				const payData = {
					orderNo,
					totalAmount,
					openid,
					takeOut: dineInOrTakeOut || '',
					coupon_id: String(coupon_id || ''),
					coupon_type: String(coupon_type || ''),
					discount_amount: Number(discount_amount) || 0
				};
				let response;
				try {
					response = await requestGetPrepayId({ ...payData });
					persistOpenidFromResponse(response, this);
				} catch (error) {
					return { success: false, error };
				}
				if (!response) {
					return { success: false, response: null };
				}
				if (Number(response.code) === WX_LOGIN_EXPIRED_CODE) {
					return { success: false, response, error: new Error(response.msg || '登录已失效，请重试') };
				}
				// 换单：后端返回 newOrderNo，用新订单号再请求一次
				if (response.code === 0 && response.newOrderNo && !response.payParams) {
					payData.orderNo = response.newOrderNo;
					try {
						response = await requestGetPrepayId({ ...payData });
						persistOpenidFromResponse(response, this);
					} catch (err) {
						return { success: false, error: err };
					}
					if (!response || !response.payParams) {
						return { success: false, response, newOrderNo: payData.orderNo };
					}
				}
				// 业务失败：code 非 0 或无 payParams
				if (response.code !== 0 || !response.payParams) {
					const apiMsg = resolvePaymentApiErrorMessage(response, paymentCaps);
					if (apiMsg) {
						response = { ...response, msg: apiMsg };
					}
					return { success: false, response, newOrderNo: response.newOrderNo };
				}
				const currentOrderNo = payData.orderNo;
				try {
					await new Promise((resolve, reject) => {
						wx.requestPayment({
							timeStamp: response.payParams.timeStamp,
							nonceStr: response.payParams.nonceStr,
							package: response.payParams.package,
							signType: response.payParams.signType,
							paySign: response.payParams.paySign,
							success: (res) => {
								if (res.errMsg === 'requestPayment:ok') {
									resolve(res);
								} else {
									reject(new Error('支付未完成'));
								}
							},
							fail: (err) => {
								
								
								reject(new Error(err.errMsg || '支付失败'));
							}
						});
					});
					return { success: true, response, newOrderNo: response.newOrderNo || currentOrderNo };
				} catch (error) {
					return { success: false, error, response, newOrderNo: response.newOrderNo || currentOrderNo };
				}
			},
			async sub_message(){
				const pubsub = this.goeasy.pubsub;
				pubsub.subscribe({
				    channel: "my_channel",//替换为您自己的channel
				    onMessage: function (message) {
				        //收到消息
				        console.log("Channel:" + message.channel + " content:" + message.content);
				    },
				    onSuccess: function () {
				        console.log("Channel订阅成功。");
				    },
				    onFailed: function (error) {
				        console.log("Channel订阅失败, 错误编码：" + error.code + " 错误信息：" + error.content)
				    }
				});
			},
			async send_message(){
				const pubsub = this.goeasy.pubsub;
				pubsub.publish({
				    channel: "my_channel",//替换为您自己的channel
				    message: "Hello GoEasy!",//替换为您想要发送的消息内容
				    onSuccess:function(){
				        console.log("消息发布成功。");
				    },
				    onFailed: function (error) {
				        console.log("消息发送失败，错误编码："+error.code+" 错误信息："+error.content);
				    }
				});
			}
			
		}
	}
</script>

<style>
	/*每个页面公共css */
</style>
