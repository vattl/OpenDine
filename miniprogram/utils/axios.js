// src/plugins/axios.js
import axios from 'axios';

// 创建axios实例
const service = axios.create({
  timeout: 10000 // 请求超时时间
});

// 请求拦截器
service.interceptors.request.use(
  config => {
    // 可以在这里添加统一的请求头
    return config;
  },
  error => {
    console.error(error);
    Promise.reject(error);
  }
);

// 响应拦截器
service.interceptors.response.use(
  response => {
    return response.data;
  },
  error => {
    console.error('API请求错误:', error);
    return Promise.reject(error);
  }
);

export default service;