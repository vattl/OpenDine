# D006 — 打印引擎补全附加费用/外卖信息参数绑定

> 日期：2026-09-05 ｜ 级别：STANDARD ｜ 状态：IMPLEMENTED

## 背景

审计发现 FULL_ORDER（整单小票）RAW 文本模板 5 个注册参数无绑定：`receiverName`（收件人）、`receiverPhone`（收件人电话）、`deliveryAddress`（配送地址）、`deliveryFee`（配送费）、`packagingFee`（打包费）。模板 `打包费：{打包费}无` 原样打印占位符（截图 bug），且未解析占位符漏检正则只认英文，中文占位符静默漏过。

## Current → Target → Diff

### 改动点（`PrintTemplateEngineImpl.java`，7 处）

| # | 位置 | 改动 |
|---|---|---|
| 1 | import | +`TakeoutDelivery`、+`OrderPackagingFeeCalculator` |
| 2 | `interpolateAllTextVariables` 尾部 | 挂载 `interpolateExtraFeeBindings(res, order)` |
| 3 | 新增 `interpolateExtraFeeBindings` | 5 参数绑定：打包费复用 `OrderPackagingFeeCalculator.calcYuan(商品小计)`（每满 100 加 1 元，不足 100 也收 1 元，无商品为 0）；配送费取 `order.delivery_fee`（null 时 `enrichOrder` 查 `t_takeout_delivery`）；收件人/电话/地址经 `getByOrderId` 查 `t_takeout_delivery`（receiver_name/receiver_phone/address_full）。**空值全部替换 `__PRINT_BINDING_MISSING__` 哨兵 → 整行隐藏** |
| 4 | RAW 漏检正则（L806） | `\{[A-Za-z_][A-Za-z0-9_]*\}` → `\{[^}]{1,20}\}`（支持中文占位符；`parseConditionalBlocks` 已先消费 `{if:}/{else}/{/if}`，菜品迭代行先行拦截，无冲突） |
| 5 | Custom 漏检正则（L865） | 同上 |
| 6 | `renderDynamicDeliveryInfo` | 空实现 → 真实渲染：enrich 后按 cfg 开关输出 收件人/电话/配送地址/配送费（label 可配） |
| 7 | `appendTakeoutDeliverySection` | 删除（被 6 取代，死代码） |

### 行为契约

- `打包费：{打包费}`：商品小计>0 → `打包费：1.00`（满 100 每百加 1）；无商品 → 整行不输出
- `配送费：{配送费}`：外卖单 → `配送费：5.00`；堂食/无配送 → 整行不输出
- `收件人：{收件人}` / `电话：{收件人电话}` / `地址：{配送地址}`：有配送数据 → 输出；否则整行隐藏
- 引擎不认识的任意中/英文占位符 → 整行隐藏 + `bindingWarnings` 告警（不再静默上票）
- 动态块 DELIVERY_INFO：外卖单输出收件人/电话/地址/配送费；非外卖不输出（原为空转块）

## 验证

- [x] 回读验证：import/新方法/正则两处/DELIVERY_INFO 替换/死方法清除，残留检查 0
- [x] `mvn compile` 通过（EXIT 0）
- [x] `mvn test` 全量测试通过
- [x] 无 API 端点增删改 → openapi 无需变更

## 遗留提示

店铺自定义模板原文 `打包费：{打包费}无` 中的默认文字"无"不属代码可清除范围：有值时将输出 `打包费：1.00无`。建议后台模板把行改为 `打包费：{打包费}元`（空值自动整行隐藏）。
