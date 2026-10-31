# 外卖配送路网距离（高德）

## 配置

`application.yml`：

```yaml
amap:
  web-key: <高德 Web 服务 Key>
  route-distance-enabled: true
  route-mode: driving   # driving=驾车(v3)；bicycling=骑行(v4)
  fallback-straight-line: true
  route-cache-minutes: 30
```

也可通过环境变量 `AMAP_WEB_KEY` 注入（需在 yml 中写 `${AMAP_WEB_KEY:}`）。

## 行为

- `POST /order/takeout/preview`、`POST /order/takeout/create` 计费距离优先调用高德路径规划，响应增加 **`distance_method`**：
  - `route`：路网距离（公里，保留 3 位小数）
  - `straight_line`：未配置 Key 或规划失败且开启回退时使用 Haversine 直线距离
- 阶梯配送费、最远配送、免配距离判断均基于上述 **`distance_km`**。

## 高德控制台

1. 申请 **Web 服务** Key（非小程序 Key）
2. 开通 **路径规划** 相关服务（驾车/骑行）
3. 配置 IP 白名单（若启用）
