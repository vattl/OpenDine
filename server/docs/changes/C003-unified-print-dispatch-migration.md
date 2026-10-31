# C003 — 移除旧版打印逻辑与统一接入打印调度中心

## 变更信息

- **Change ID**: C003
- **Change Type**: REPLACE / REMOVE / MIGRATE
- **Created**: 2026-08-30
- **Status**: COMPLETED

---

## 1. 变更背景与目标

此前系统中部分业务触发点（如 `OrderController` 的收银出票、接单后厨出票、补打厨房小票，`PaymentSuccessHandler` 的堂食支付成功出票，`KdsServePrintService` 的传菜单打印等）仍保留直接调用 `feieyunController.printOrder` 或 `feieyunService.print` 的旧版兜底分支，并且小票模版排版代码分散在 `OrderController` 中。

本次变更目标：
1. **移除旧版直调逻辑**：彻底清理 `OrderController`、`PaymentSuccessHandler`、`KdsServePrintService` 中对 `FeieyunController` 和 `feieyunService.print` 的硬编码直调与兜底代码。
2. **统一触发点路由**：所有打印业务触发点 100% 统一路由至 `PrintDispatcherService.dispatch(shopId, scenario, context)`。
3. **模板引擎集中管理**：厨房小票、结账单、预结单、整单、加菜单、传菜单、退款单、交接班报表、标签贴等所有模板统一由 `PrintTemplateEngine` 管理与渲染。

---

## 2. 变更矩阵与受影响文件

| 文件 | 变更内容 |
| :--- | :--- |
| `src/main/java/com/lanf/controller/OrderController.java` | 移除 `FeieyunController` 依赖与 4 处 `PrintRequest` 直调，`printContentForCashier`、`doAutoAcceptAndPrintLocked`、`reprintKitchenTickets` 全部统一调用 `PrintDispatcherService`；`generatePrintContent` 与 `generateKitchenTicketContents` 委托至 `PrintTemplateEngine`。 |
| `src/main/java/com/lanf/payment/success/PaymentSuccessHandler.java` | 移除 `FeieyunController` 依赖与直接打印分支，支付出票统一下发 `PrintDispatcherService.dispatch(ORDER)`。 |
| `src/main/java/com/lanf/kds/service/KdsServePrintService.java` | 移除 `IFeieyunService` 依赖，自动划菜出单与 `printManual` 手动出单 100% 统一下发 `PrintDispatcherService.dispatch(SERVE)`。 |
| `src/main/java/com/lanf/payment/support/OrderPaymentBridgeImpl.java` | 引入 `PrintTemplateEngine`，小票内容生成直接委托模板引擎。 |
| `src/main/java/com/lanf/printing/service/impl/PrintDispatcherServiceImpl.java` | 扩展场景别名支持（`full_order`, `checkout`, `pre_checkout`, `takeout`, `expedite`, `label`）。 |
| `src/main/java/com/lanf/printing/engine/PrintTemplateEngine.java` & `Impl` | 补充 `renderLabelTicket` 商品标签/杯贴渲染方法。 |
| `src/main/java/com/lanf/printing/model/PrintDispatchResult.java` | 增加 `sent(...)` 与 `failed(...)` 静态便捷工厂方法。 |
| `src/test/java/com/lanf/controller/OrderAutoAcceptPrintTest.java` | 升级 Mock 适配 `PrintDispatcherService`。 |
| `src/test/java/com/lanf/kds/service/KdsServePrintServiceTest.java` | 升级 Mock 适配 `PrintDispatcherService`。 |

---

## 3. 验证结果

- **单元测试**：全量 575 项单元测试通过（0 失败，0 错误，1 skipped）。
- **端到端模拟测试**：`PrintingFullLifecycleSimulationTest` 覆盖全生命周期闭环验证通过。
- **打包验证**：`mvn clean package -DskipTests` 构建成功，产物 `target/diancan-0.0.1-SNAPSHOT.jar`。
