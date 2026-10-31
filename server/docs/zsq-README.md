# 真省钱对接 — Java 后端模块

Spring Boot 3 模块，提供**你服务器对外 REST 接口**，内部转发至 `https://zsq.wlhulian.com/api`。

## 合并到已有项目

1. 将 `src/main/java/com/zsq/integration` 复制到你工程的 `src/main/java`（可按需改包名）。
2. 在 `application.yml` 增加 `application-zsq-example.yml` 中的配置。
3. 确保有依赖：`spring-boot-starter-web`、`validation`。
4. 启动类扫描包：`@SpringBootApplication(scanBasePackages = {"你的包", "com.zsq.integration"})`
  或把 `com.zsq.integration` 改成你的包名前缀。

独立运行本模块：

```bash
cd java-backend
mvn spring-boot:run
```

默认端口 `8088`。

## 你方对外接口一览


| 方法   | 路径                                             | 说明                               |
| ---- | ---------------------------------------------- | -------------------------------- |
| POST | `/api/zsq/auth/login`                          | 登录，返回 `authorization`            |
| POST | `/api/zsq/auth/login/config`                   | 用 yml 账号登录                       |
| GET  | `/api/zsq/auth/verify`                         | 校验 token，Header: `Authorization` |
| GET  | `/api/zsq/orders/shops`                        | 发单店铺列表                           |
| GET  | `/api/zsq/orders/address/tips?city=&keywords=` | 地址解析                             |
| POST | `/api/zsq/orders/takeaway`                     | 创建外卖订单                           |
| POST | `/api/zsq/orders/takeaway/auto`                | 用 yml 账号自动登录并下单                  |


## 调用示例

### 1. 登录

```http
POST /api/zsq/auth/login
Content-Type: application/json

{
  "username": "手机号",
  "password": "密码",
  "role": "merchant"
}
```

响应：

```json
{
  "code": 200,
  "message": "success",
  "data": {
    "authorization": "Bearer eyJ...",
    "role": "merchant"
  }
}
```

### 2. 创建外卖订单

```http
POST /api/zsq/orders/takeaway
Authorization: Bearer eyJ...
Content-Type: application/json

{
  "fromAddressId": 1842397,
  "receiverName": "qiqi",
  "receiverPhone": "13800138001",
  "receiverAddress": "沙坪街道大鹏路",
  "receiverDetail": "文汇华府",
  "cityName": "江门市",
  "productName": "到店查看",
  "productAmount": "50",
  "productCount": 1,
  "weight": 3,
  "remark": ""
}
```

响应 `data`：

```json
{
  "shopNumber": "3",
  "id": 43787770,
  "orderId": "808353241436549"
}
```

### 3. 配置账号一键下单（无 Header）

`application.yml` 配置 `zsq.username`、`zsq.password` 后：

```http
POST /api/zsq/orders/takeaway/auto
Content-Type: application/json

{ ...同上 CreateTakeawayOrderRequest... }
```

## 真省钱原始 API 映射


| 你方 Service                            | 真省钱接口                                       |
| ------------------------------------- | ------------------------------------------- |
| `ZsqAuthService.login`                | `POST /store/staff/login` 或 `/pt/app/login` |
| `ZsqRemoteClient.listShopAddresses`   | `GET /open/order/address`                   |
| `ZsqRemoteClient.addressInputTips`    | `GET /address/v2/input-tips`                |
| `ZsqRemoteClient.createTakeawayOrder` | `POST /open/order/create`（`type` 固定为 `1`）   |


## 包结构

```
com.zsq.integration
├── config          # ZsqProperties、RestTemplate
├── remote          # ZsqRemoteClient + 远端 DTO
├── service         # ZsqAuthService、ZsqOrderService
├── web             # Controller + 你方入参/出参 DTO
└── exception       # ZsqApiException
```

## 安全建议

- 不要将真省钱密码提交到前端；登录接口应仅服务端调用。
- `authorization` 建议存入 Redis，按你方用户 ID 关联。
- 生产环境使用 HTTPS，并限制 `/api/zsq/**` 的内网或鉴权访问。

