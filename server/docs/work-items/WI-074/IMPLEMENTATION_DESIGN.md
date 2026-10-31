# Implementation Design — WI-074

## Root Fix / Owner

- 核心业务主管服务：`OrderInvoiceServiceImpl`（负责发票生命周期状态流转、Token 颁发与验证、可开票金额校验、敏感日志脱敏）。
- 外部入口主管控制器：
  - 公开端：`PublicInvoiceController`（强制 Token 必填，零信任鉴权，拒绝匿名自动初始化）。
  - 收银管理端：`AdminOrderController`（校验支付状态，控制开票金额与人工补录权限）。
- 支付通道层：`WechatJsapiChannel`（统一注入 `support_fapiao: true`）。
- 持久层：`t_order_invoice`（通过 `V050` 迁移脚本增加安全哈希与时效字段）。
- 表现层：`src/main/resources/static/invoice-apply.html`（静态 H5 界面合规整改与隐私保护）。

## 2. 数据库结构演进 (`V050__invoice_token_auth_and_audit.sql`)

```sql
ALTER TABLE `t_order_invoice`
  ADD COLUMN `token_hash` varchar(64) DEFAULT NULL COMMENT '访问token SHA-256哈希' AFTER `invoice_qr_url`,
  ADD COLUMN `token_expire_at` datetime DEFAULT NULL COMMENT 'token有效期截止时间' AFTER `token_hash`,
  ADD COLUMN `token_used_at` datetime DEFAULT NULL COMMENT 'token首次提交/使用时间' AFTER `token_expire_at`,
  ADD KEY `idx_token_hash` (`token_hash`);
```

## 3. 安全 Token 生成与验证机制

1. **Token 颁发**：
   - 收银端在为已支付订单生成发票二维码时，通过 `SecureRandom` 或高熵随机算法生成 32 字符的访问 Token。
   - 服务端计算 Token 的 SHA-256 十六进制摘要，存入 `token_hash`。
   - 设置 `token_expire_at = now() + 24小时`。
   - 生成的二维码 URL 中携带原明文 Token 作为查询参数：`https://domain/invoice-apply.html?order_no=...&apply_id=...&token=...`。
2. **Token 校验**：
   - 顾客端访问公开接口时，必须携带 `token`。
   - 服务端计算传入 token 的 SHA-256，与数据库 `token_hash` 进行恒定时间比较（`MessageDigest.isEqual`）。
   - 校验当前时间 `now() <= token_expire_at`。
   - 校验当前记录绑定的 `order_no` 与可选 `apply_id`、`shop_id` 完全一致。
   - 校验失败直接抛出 403 权限拒绝异常。

## 4. 状态机与业务不变量设计

1. **支付状态前置检查**：
   - 只有 `order.getTransacStatus() == 1`（已支付）且 `order.getPayTime() != null` 的订单才允许生成发票二维码或申请发票。
   - 未支付、已取消订单直接拒绝（400 Bad Request）。
2. **累计可开票金额校验**：
   - 订单净支付金额 = `实付金额 (payAmount) - 累计成功退款金额 (refundAmount)`。
   - 历史有效发票金额 = `SUM(invoice_amount)`，其中状态在 `['TITLE_SUBMITTED', 'ISSUING', 'SUCCESS']`。
   - 本次申请金额校验：`本次申请金额 + 历史有效发票金额 <= 订单净支付金额`。若超额直接拒绝。
3. **状态跃迁控制**：
   - `PENDING_SCAN` -> `TITLE_SUBMITTED`：顾客扫码并成功提交抬头。
   - `TITLE_SUBMITTED` -> `ISSUING` / `SUCCESS`：人工审核录入发票号码或系统处理。禁止从未扫码（`PENDING_SCAN`）直接跃迁至 `SUCCESS`。
   - `SUCCESS` -> `REVERSED`：发生退款冲红或人工发票作废。

## 5. 隐私保护与敏感数据脱敏规范

1. **日志脱敏**：
   - 打印日志时，发票抬头仅打印前 2 位及后 2 位，税号遮蔽中间 8 位（如 `9111****0001`）。
   - 手机号遮蔽中间 4 位（`138****1234`），邮箱仅保留首字符与域名（`u***@domain.com`）。
2. **前端回显脱敏**：
   - 公开接口 `GET /api/public/invoice/info` 返回的 DTO 中，直接返回脱敏后的 `buyer_tax_no`、`buyer_phone`、`buyer_email`。
   - 避免向未授权前端传输完整的用户敏感隐私。

## 6. 微信普通商户能力适配

- 移除对微信普通服务商专属抬头 API（`/v3/new-tax-control-fapiao/user-title/title-url`）的调用，普通商户模式直接安全降级到本地受控登记二维码；
- 在 `WechatJsapiChannel` 下单构造器中增加 `support_fapiao: true` 参数透传，使顾客在微信支付成功后可直接在微信账单详情页看到开票入口。

## 7. 顾客端 H5 界面合规性改造

- 标题文案由“国家税务总局全国统一规范电子发票开具服务”更正为“老肥家餐饮 · 发票抬头登记服务”。
- 提交结果文案明确标注“发票申请已提交，商家将根据预留信息处理并开具发票”。
- 提交按钮增加防抖逻辑（点击立即禁用并显示“正在提交...”）。
- 下载按钮实施协议白名单校验，杜绝 `javascript:` 或恶意外部链接伪造。

## Verification Strategy

- 单元测试：编写针对 Token 颁发、哈希匹配、过期判定、订单支付校验、累计金额防超额及脱敏工具方法的单测套件。
- Web 接口测试：测试 PublicInvoiceController 与 AdminOrderController 对非法/空 Token 的 403 拒绝与查无记录 404 返回，断言数据库无匿名记录插入。
- 微信通道测试：测试 WechatJsapiChannel 在统一下单参数中注入 `support_fapiao: true`。
- 界面与静态资源测试：通过原型与构建物对比验证文案更正、PII 掩码渲染与防抖效果。
- 编译与打包验证：执行 `mvn clean package -DskipTests` 生成 deployable JAR 包。
