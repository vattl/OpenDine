# Scenario Matrix — WI-065

| ID | Context | Expected | Invariants | Verification | Result |
|---|---|---|---|---|---|
| TC01 | 6人、150元、2人不辣、fitness+weightloss、均衡 | 真实菜单求解，总价≤15000分，2人免辣分配有效，耗时<50ms | HARD-CONSTRAINTS | solver unit test | PASS |
| TC02 | 方案上追加「其中1人不吃牛肉」 | 仅更新该成员限制，保留预算与其他条件，解释菜品差异 | CONCURRENCY-REVISION | session service test | PASS |
| TC03 | 预算从150元降为130元 | 总价不超13000分；无解时诚实报错，不冒用旧方案 | HARD-CONSTRAINTS | solver unit test | PASS |
| TC04 | 菜品在门店不支持免辣制作 | 该变体严禁分配给免辣成员 | FOOD-SAFETY | solver unit test | PASS |
| TC05 | 商品缺少热量和蛋白质数据 | 不虚构精确数值，营养评分归零并明确降级标注 | TRUTH-IN-DATA | solver unit test | PASS |
| TC06 | 声明过敏且无法排除后厨交叉污染 | 强排除该菜品，禁止分配给对应过敏成员 | FOOD-SAFETY | solver unit test | PASS |
| TC07 | 菜品在草稿后发生价格变动或售罄 | 提交下单前 validate 拦截，原确认失效，提示重新核对 | ORDER-INTEGRITY | order draft service test | PASS |
| TC08 | 连续重试或并发重复提交订单 | 幂等键防重，仅生成一张正式订单，不重复打单扣款 | IDEMPOTENCY | order draft service test | PASS |
| TC09 | 备注中包含恶意提示词（Prompt Injection） | 严格当普通字符串转义，不改变求解与权限规则 | SECURITY-DEFENSE | controller unit test | PASS |
| TC10 | 6人150元在实际菜价下无可行解 | 返回 INFEASIBLE，计算出确切最小可行预算差额 | DETERMINISTIC-NEGOTIATION | solver unit test | PASS |
| TC11 | 门店未录入或无法读取在售菜单 | 返回 REQUIRES_MENU_DATA，不生成虚假报价 | TRUTH-IN-DATA | adapter unit test | PASS |
| TC12 | 多店数据隔离（深圳店 vs 江门店） | 店铺菜单、会话与订单物理隔离，禁止跨店操作 | SHOP-ISOLATION | controller unit test | PASS |
| TC13 | 调用 MCP 工具 submit_order | 必须用户显式确认并具备有效会话/草稿，无权限拒绝 | MCP-SECURITY | mcp service test | PASS |
| TC14 | 缺失食物克重时声称「吃饱优先」 | 标注「充足度未验证」，不得虚假宣称人人吃饱 | TRUTH-IN-DATA | solver unit test | PASS |
