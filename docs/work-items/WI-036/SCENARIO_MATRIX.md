# SCENARIO MATRIX — WI-036

| 编号 | 场景描述 | 输入条件 | 预期判定 | 实际结果 |
|---|---|---|---|---|
| SC-01 | 空规则默认路由 | 门店未配置任何规则 | 走 default 主商户 | PASS |
| SC-02 | 就餐方式分流 | 规则指定 diningTypes: ["打包", "自提"] | 打包单命中，堂食单不命中 | PASS |
| SC-03 | 金额区间分流 | minPaidYuan=50, maxPaidYuan=100 | 75.5元命中，49.9元与100.1元不命中 | PASS |
| SC-04 | 菜品关键字分流 | goodsNameKeywords: ["三文鱼"] (CONTAINS_ANY) | 包含三文鱼刺身命中，纯牛排不命中 | PASS |
| SC-05 | 菜品类别与模式 | categoryIds: [10], mode: ONLY | 全单均为生鱼片命中，含米饭不命中 | PASS |
| SC-06 | 多维度 AND 组合 | 打包 且 包含三文鱼 且 金额>50 | 3个条件全满足命中，任一不符不命中 | PASS |
| SC-07 | 多维度 ANY (OR) 组合 | 打包 或 金额>=100 (ANY) | 打包且小额命中，堂食且大额命中 | PASS |
| SC-08 | 目标商户未就绪自愈 | 命中目标商户但 isMerchantPayReady=false | 自动降级回退至 default 主商户 | PASS |
| SC-09 | 规则优先级排序 | 规则A (priority 200) vs 规则B (priority 100) | A 优先评估命中 | PASS |
| SC-10 | 后台模拟测算接口 | POST /simulate 传入试算订单 | 返回命中规则、目标商户、生效商户与就绪状态 | PASS |