# IMPACT MAP — WI-036

## Affected Files
1. Flyway 迁移: `src/main/resources/db/migration/V035__payment_routing_rules.sql`
2. 实体 & Mapper:
   - `src/main/java/com/lanf/payment/entity/PaymentRoutingRuleEntity.java`
   - `src/main/java/com/lanf/payment/mapper/PaymentRoutingRuleMapper.java`
3. 路由评估与引擎:
   - `src/main/java/com/lanf/payment/routing/PaymentRoutingContext.java`
   - `src/main/java/com/lanf/payment/routing/PaymentRoutingRuleMatcher.java`
4. 业务服务:
   - `src/main/java/com/lanf/payment/service/PaymentRoutingRuleService.java`
   - `src/main/java/com/lanf/payment/service/WechatMerchantRoutingService.java`
5. 支付结账调用方:
   - `src/main/java/com/lanf/payment/settlement/PayableAmountContext.java`
   - `src/main/java/com/lanf/payment/settlement/PaymentSettlementService.java`
   - `src/main/java/com/lanf/payment/service/WechatNativePaymentService.java`
   - `src/main/java/com/lanf/payment/service/WechatMicropayService.java`
6. 管理端控制层:
   - `src/main/java/com/lanf/payment/controller/admin/AdminPaymentRoutingRuleController.java`
   - `src/main/java/com/lanf/config/ApiPermissionMapping.java`
7. 自动化测试:
   - `src/test/java/com/lanf/payment/routing/PaymentRoutingRuleMatcherTest.java`
   - `src/test/java/com/lanf/payment/service/PaymentRoutingRuleServiceTest.java`
   - `src/test/java/com/lanf/payment/service/WechatMerchantRoutingServiceTest.java`
   - `src/test/java/com/lanf/payment/service/WechatNativePaymentServiceTest.java`
   - `src/test/java/com/lanf/payment/service/WechatMicropayServiceTest.java`
8. 契约文档:
   - `docs/API.md`
   - `docs/openapi.yaml`