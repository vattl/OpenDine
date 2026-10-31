# Change: C001-unified-printing-refactor

## Status: COMPLETED
**Date**: 2026-08-30
**Type**: REFACTOR / ARCHITECTURE

---

## 1. 变更背景与目标
系统原有的打印功能存在新旧双轨并存问题：管理后台已有统一设备（`t_printing_device`）、场景规则（`t_printing_rule`）与流水表（`t_printing_job`），但在下单自动打印、支付后打印、收银点餐出票、后厨分单补打、KDS 划单传菜等核心业务链路中仍直接依赖旧版 `FeieyunController` 与 `t_shop_printer_config` 单设备配置。

**本次重构目标**：
1. 构建统一打印调度引擎 `PrintDispatcherService` 与统一模板引擎 `PrintTemplateEngine`；
2. 业务触发点（点餐接单、支付成功、收银结账、后厨补打、KDS 划单传菜、交接班等）全面收口至 `PrintDispatcherService`；
3. 保留对旧表 `t_shop_printer_config` 与旧接口 `/api/feieyun/*` 的平滑兼容与自动迁移；
4. 实现多硬件通道支持（CLOUD 云打印、LAN 局域网、USB/蓝牙设备队列 `PENDING_DEVICE`）。

---

## 2. 变更架构与核心组件

### 2.1 核心类与包结构
- `com.lanf.printing.model.PrintScenario`：场景标识常量（`order`, `kitchen`, `serve`, `shift`, `refund`, `label`, `test`）
- `com.lanf.printing.model.PrintContext`：统一打印上下文 DTO（支持 Order, OrderDetail, Shift, cidFilter, 自定义文本等）
- `com.lanf.printing.model.PrintDispatchResult`：打印任务执行与派发结果
- `com.lanf.printing.engine.PrintTemplateOptions`：模板排版参数
- `com.lanf.printing.engine.PrintTemplateEngine` & `PrintTemplateEngineImpl`：统一小票模板渲染引擎（自适应 58mm/80mm，涵盖结账单、加菜单、后厨分单、传菜单、交接班小票、退款单）
- `com.lanf.printing.service.PrintDispatcherService` & `PrintDispatcherServiceImpl`：统一打印调度服务（规则路由、多设备分发、任务持久化、三级优雅降级与历史数据自动迁移、补打调度）

### 2.2 业务链路收口
1. **`PaymentSuccessHandler`**：堂食支付成功后调用 `printDispatcherService.dispatch(shopId, ORDER, ...)`；
2. **`OrderController.doAutoAcceptAndPrintLocked`**：接单后统一派发后厨小票与前台制作单；
3. **`OrderController.reprintKitchenTickets`**：后厨分单补打统一由 `PrintDispatcherService` 驱动；
4. **`OrderController.printContentForCashier`**：收银小票生成与派发统一收口；
5. **`KdsServePrintService`**：KDS 划单后传菜单统一派发 `SERVE` 场景规则；
6. **`FeieyunController`** / **`CashierPrintController`**：保留所有原有端点路由，平滑向后兼容。

---

## 3. 验证情况
- 单元测试矩阵覆盖：
  - `PrintTemplateEngineTest`（5 个用例）
  - `PrintDispatcherServiceTest`（3 个用例）
  - `PrintingServiceTest`（26 个用例）
  - `OrderAutoAcceptPrintTest`（4 个用例）
  - `KdsServePrintServiceTest`（7 个用例）
- **全量测试回归**：执行 `mvn test`，全工程 566 个用例全部通过（566 run, 0 failures, 0 errors, 1 skipped）。
