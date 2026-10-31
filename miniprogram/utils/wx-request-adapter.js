// utils/wx-request-adapter.js
module.exports = function wxRequestAdapter(config) {
  return new Promise((resolve, reject) => {
    const { method, url, data, headers, timeout } = config;
    
    // 处理请求头
    const requestHeaders = {
      ...headers,
      'content-type': headers['content-type'] || 'application/json'
    };
    
    const wxConfig = {
      url,
      method: method.toUpperCase(),
      data,
      header: requestHeaders,
      timeout: timeout || 10000,
      success: (res) => {
        resolve({
          data: res.data,
          status: res.statusCode,
          statusText: res.statusMessage,
          headers: res.header,
          config
        });
      },
      fail: (err) => {
        reject({
          message: err.errMsg,
          code: err.errCode,
          config,
          request: err
        });
      }
    };
    
    wx.request(wxConfig);
  });
};