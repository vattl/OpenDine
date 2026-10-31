# D007 — 堂食个人收款/收银结账补打结账单

> 日期：2026-09-08 ｜ 级别：STANDARD ｜ 状态：IMPLEMENTED

## 背景

审计发现个人回调收款链路：打包/外卖自动结账后经 `PaymentSuccessHandler.run` 打印，**堂食订单不打印**（`checkoutInternal` 的 `isPackOrDeliveryType` 条件拦截）。微信支付回调路径堂食分支存在（run L113）但因入口条件永远走不到。

## Current → Target → Diff

### 改动点

| # | 文件 | 改动 |
|---|---|---|
| 1 | `PaymentSuccessHandler.java` | run 的堂食分支提炼为公开方法 `printDineInTicket(Order)`：加载明细 → `printDispatcherService.dispatch(ORDER, ofOrder(order,false))`（与微信支付回调行为完全一致） |
| 2 | `CashierCheckoutService.java` | `checkoutInternal` L221 条件增加 `else if ("堂食")`：AfterCommit 执行 `paymentSuccessHandler.printDineInTicket(order)`（key `cashier_checkout_print:{orderNo}`，与 fulfillment 互不冲突） |

### 行为契约

- 堂食订单经**个人收款回调**自动结账 → 提交后异步补打整单结账单（统一打印调度中心 → `t_printing_job` 落库可追溯）
- 堂食订单经**普通收银端结账**（CashierOrderController）→ 同样补打（同一 checkoutInternal）
- 打包/外卖行为不变（仍走 run → doAutoAcceptAndPrint）
- 不改变其他副作用：核销券/清台仍在结账事务内完成，打印为提交后异步，失败不影响结账结果
- 未配置打印机/未命中打印规则的门店：dispatch 自然跳过，无异常

### 为什么不用"放开 run 调用条件"方案

`run` 还包含反积分、邀请返利等副作用；普通收银堂食结账当前无这些行为，直接放开会引入业务行为变更。本方案仅补打印，最小且不越界。

## 验证

- [x] 回读验证：run 分支提炼 / printDineInTicket 新增 / checkoutInternal 堂食分支
- [x] `mvn test` 全量测试通过（758 tests, 0 failures, 0 errors）
- [x] 无 API 端点增删改 → openapi 无需变更

## 附带修复（外部会话引入的预存回归，阻塞构建门禁）

- `docs/openapi.yaml`：ApiPermissionMappingRecord 属性段 flow mapping 缺闭合 `}`（L12572）且 `{id}` 未引号包裹 → 重写为等价 block mapping，PyYAML 整体解析通过。
- `src/test/java/com/lanf/service/PersonalPaymentReverseMatchTest.java`：`8affd36` 将 settleOrder 改为调 `checkoutKeepMerchantId` 后测试未同步（仍 stub `checkout`）→ stub 与 verify 改为 `checkoutKeepMerchantId`，恢复断言真实路径。
