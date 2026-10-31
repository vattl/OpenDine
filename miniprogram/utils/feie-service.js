// src/services/feie-service.js
import wxRequestAdapter from '../utils/wx-request-adapter'; // 导入小程序适配器

class FeieService {
  constructor() {
    this.config = {
      user: "870992729@qq.com", // 飞鹅云账号
      ukey: "pc7KMwRFBEZtkm3f", // 飞鹅云UKEY
      host: "https://api.feieyun.cn",
      path: "/Api/Open/",
      port: 443, // 使用HTTPS默认端口443
      sn: "521635737"
    };
  }

  // 将对象转换为URL编码的字符串（UTF-8格式）
  formatUrlEncoded(data) {
    return Object.keys(data)
      .map(key => {
        const value = typeof data[key] === 'string' 
          ? encodeURIComponent(data[key]) 
          : encodeURIComponent(String(data[key]));
        return `${encodeURIComponent(key)}=${value}`;
      })
      .join('&');
  }

  // 生成签名
  generateSignature(timestamp) {
    const rawString = this.config.user + this.config.ukey + timestamp;
    return require('crypto').createHash('sha1').update(rawString).digest('hex');
  }

  // 生成10位UNIX时间戳（秒级）
  getUnixTimestamp() {
    return Math.floor(new Date().getTime() / 1000);
  }

  // 发送请求到飞鹅云API
  async request(apiName, data) {
    const timestamp = this.getUnixTimestamp();
    
    // 验证时间戳是否在合理范围内
    const now = Math.floor(Date.now() / 1000);
    if (Math.abs(timestamp - now) > 600) {
      console.warn('时间戳与当前时间差异过大:', timestamp, now);
    }
    
    const requestData = {
      user: this.config.user,
      stime: timestamp,
      sig: this.generateSignature(timestamp),
      apiname: apiName,
      ...data
    };
    
    console.log('发送请求:', requestData);
    
    try {
      const fullUrl = `${this.config.host}${this.config.path}`;
      
      return await new Promise((resolve, reject) => {
        wx.request({
          url: fullUrl,
          method: 'POST',
          data: this.formatUrlEncoded(requestData),
          header: {
            'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8'
          },
          success: (res) => {
            if (res && res.data) {
              console.log('收到响应:', res.data);
              resolve(res.data);
            } else {
              console.error('响应格式异常:', res);
              reject(new Error('API响应格式不正确'));
            }
          },
          fail: (err) => {
            console.error('请求失败:', err);
            reject(err);
          }
        });
      });
    } catch (error) {
      console.error('Feie API 请求错误:', error);
      throw error; // 直接抛出原始错误
    }
  }

  // 打印订单
  async printOrder(content, times = 1) {
    if (!content) {
      throw new Error('打印内容不能为空');
    }
    
    try {
      const result = await this.request('Open_printMsg', {
        sn: this.config.sn,
        content,
        times
      });
      
      return result; // 直接返回原始结果，不做额外处理
    } catch (error) {
      console.error(`打印订单失败 [打印机:${this.config.sn}]`, error);
      throw error; // 直接抛出错误，由调用者处理
    }
  }

  // 查询订单状态
  async queryOrderStatus(orderId) {
    return this.request('Open_queryOrderState', {
      orderid: orderId
    });
  }

  // 查询打印机状态
  async queryPrinterStatus(printerSn) {
    return this.request('Open_queryPrinterStatus', {
      sn: printerSn
    });
  }
}

// 创建单例
export default new FeieService();