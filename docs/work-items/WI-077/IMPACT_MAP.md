# Impact Map — WI-077

## Audit Routing Inputs

Risk Level: LOW
UI Impact: NONE
Contract Impact: NONE
Security Impact: NO
Data / Migration Impact: NO
Reliability / Performance Impact: NO

## Authoritative Owner

- `TaxBureauResolver`: 税务局解析器工具类，负责根据门店地址匹配全国 36 个省级及计划单列市电子税务局官方门户，以及默认总入口。
- `OrderInvoiceServiceImpl`: 发票分页查询数据装配，负责补全 `shop_address`、`tax_bureau_name`、`tax_bureau_url`。
- `AdminShopAccessServiceImpl`: 管理员登录门店摘要装配，负责补全 `address`、`taxBureauName`、`taxBureauUrl`。
- `admin.html`: 财务开票工作台页面，负责提供一键打开税局开票网页、表格快捷操作与开票弹窗信息复制。

## Change Propagation Path

```text
门店配置地址 (t_shop.address)
→ AdminShopAccessServiceImpl / OrderInvoiceServiceImpl 查出 Shop
→ TaxBureauResolver.resolve(shop.address)
→ 动态丰富 shop_address, tax_bureau_name, tax_bureau_url
→ 财务工作台 (admin.html) 获取并渲染
→ 财务人员点击「🏛️ 打开当地电子税局」/「🏛️ 税局开票」/「🌐 一键打开当地税局开票系统」
→ 浏览器新标签页精准跳转至对应省市国家电子税务局官方开票页面 (e.g. 深圳/广东/北京/上海等)
→ 配合开票信息一键复制，顺利完成税局开票并录入系统归档
```

## Consumer Coverage

| Consumer | Relationship | Classification | Needs Change | Evidence |
|---|---|---|---|---|
| 财务开票工作台 | 页面操作与开票直达 | AFFECTED | YES | `src/main/resources/static/invoice/admin.html` |
| 发票分页管理接口 | 扩展返回门店地址与税局元数据 | AFFECTED | YES | `OrderInvoice.java`, `OrderInvoiceServiceImpl.java` |
| 管理员登录认证 | 扩展门店摘要地址与税局元数据 | AFFECTED | YES | `AdminShopAccessServiceImpl.java` |
| 接口文档 | 补充发票与登录门店摘要的字段说明 | AFFECTED | YES | `docs/openapi.yaml`, `docs/API.md` |

## Layer Coverage

| Layer | State | Owner / Impact |
|---|---|---|
| Controller / API | PRESERVED | `/admin/order/invoice/page`, `/adminLogin` 契约向后兼容扩展 |
| Domain / Service | MODIFIED | `TaxBureauResolver.java`, `OrderInvoice.java`, `OrderInvoiceServiceImpl.java`, `AdminShopAccessServiceImpl.java` |
| Persistence / DB | PRESERVED | `t_shop`, `t_order_invoice` 物理表结构不变，新增字段均为 `@TableField(exist = false)` |
| Frontend / UI | MODIFIED | `src/main/resources/static/invoice/admin.html` (静态页面体验增强) |
| Documentation | MODIFIED | 同步更新 `docs/openapi.yaml`, `docs/API.md` |
