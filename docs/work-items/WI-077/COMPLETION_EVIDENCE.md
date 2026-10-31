# Completion Evidence — WI-077

## Summary

为财务人工开票管理工作台（`admin.html`）提供「一键打开当地电子税局开票网页」功能，并根据各独立纳税主体门店的注册详细地址智能精准匹配国家税务总局全国统一规范电子税务局及各省市/计划单列市官方电子税务局门户。

## Key Deliverables

1. **权威税务解析组件**：`com.lanf.util.TaxBureauResolver`，覆盖国家税务总局总平台及全国 36 个省级/计划单列市（深圳、大连、青岛、宁波、厦门）官方电子税局，支持计划单列市优先判定、多级城市行政关键词匹配与空地址优雅回退。
2. **实体与服务数据丰富**：
   - `OrderInvoice.java` 增加 `shop_address`、`tax_bureau_name`、`tax_bureau_url` 字段（`@TableField(exist = false)`，保证物理表结构稳定）；
   - `OrderInvoiceServiceImpl.adminPage` 分页查询自动装配门店地址与匹配税局门户数据；
   - `AdminShopAccessServiceImpl.toShopSummaries` 登录门店摘要同步装配 `address`、`taxBureauName`、`taxBureauUrl`。
3. **财务开票工作台页面升级 (`admin.html`)**：
   - 顶部导航栏增加「🏛️ 打开当地电子税局」按钮，单店模式直达对应税局，全部门店模式弹出税局直达导航清单抽屉；
   - 模式提示栏增加「🏛️ 一键打开税局开票网」快捷操作；
   - 开票数据表格「所属门店」列展示对应所属税局标签及直达超链接，操作列针对待开票记录增加「🏛️ 税局开票」直达按钮；
   - 确认开票弹窗中展示销方门店详细地址与所属税局，并提供「🌐 直达当地电子税局开票 ↗」与「📋 一键复制开票资料」按钮，极大提高白天财务开票效率。
4. **自动化单元测试全覆盖**：
   - `TaxBureauResolverTest` 7 项核心测试用例全绿；
   - `OrderInvoiceServiceTest` 25 项测试全绿，含 `pageInvoiceForAdmin_enrichesShopTaxEntityInfo` 专门断言税局解析与地址补全。
5. **契约文档同步**：同步更新 `docs/openapi.yaml` 与 `docs/API.md`。
6. **可运行 JAR 构建**：重新编译与打包，成功生成 `target/diancan-0.0.1-SNAPSHOT.jar`。
