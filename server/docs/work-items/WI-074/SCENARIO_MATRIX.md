# Scenario Matrix — WI-074

## Scenarios

| Scenario ID | Category | Scenario / Context | Expected Outcome | Applicable Invariants | Verification Method | Result |
|---|---|---|---|---|---|---|
| SC-01 | 安全鉴权 | 匿名调用公开发票 info 接口，未带 token | HTTP 403 拒绝，禁止返回发票及订单数据 | 公开接口必须强验 Token | 单元测试 + Controller 测试 | PASS |
| SC-02 | 安全鉴权 | 匿名查询不存在的发票记录（伪造订单号） | HTTP 404/403 拒绝，严禁自动在数据库创建记录 | 查无记录禁止自动初始化 | 单元测试验证数据库无新行插入 | PASS |
| SC-03 | 篡改防护 | 携带错误或过期 Token 提交发票抬头 | HTTP 403 拒绝，数据不被修改 | Token 必须强哈希比对并检查有效期 | 单元测试构造错误 Token 与过期 Token | PASS |
| SC-04 | 正常开票 | 携带合法 Token 首次提交发票抬头 | 状态由 PENDING_SCAN 成功流转为 TITLE_SUBMITTED，记录 token_used_at | 合法 Token 允许正常提交 | 单元测试与服务集成测试 | PASS |
| SC-05 | 状态机约束 | 未支付订单尝试生成发票二维码或人工登记 | 抛出业务异常或返回 400，拒绝开票 | 仅已支付订单允许开票 | 单元测试模拟未支付订单 | PASS |
| SC-06 | 金额与退款 | 发生退款后，申请开票金额超过订单实付扣除退款后的余额 | 拒绝开票，提示超出可开票余额 | 累计开票金额不得超过净支付额 | 单元测试计算累计金额与退款 | PASS |
| SC-07 | 隐私保护 | 查看已提交抬头信息与查看应用日志 | 响应与日志中的税号、手机、邮箱均脱敏展示 | 敏感数据严禁明文暴露 | 单元测试断言脱敏掩码与日志格式 | PASS |
| SC-08 | 微信下单 | 微信 JSAPI 统一下单请求参数构造 | 下单参数字典中包含 `support_fapiao: true` | 普通商户下单开启发票入口 | 单元测试验证 Channel 下单入参 | PASS |
| SC-09 | 页面合规 | 顾客访问发票申请 H5 页面并点击提交 | 界面展示“发票抬头登记服务”，点击后按钮立即禁用防抖 | 消除虚假宣称并提供交互防抖 | 原型与界面审查 | PASS |
