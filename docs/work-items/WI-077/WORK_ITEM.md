# Work Item — WI-077

## Title

财务工作台提供一键打开开票网页及按门店地址精准导航当地税局开票 (Finance Workbench One-Click Open Tax Bureau Website by Store Address)

## Type

FEATURE

## Goal

为财务开票工作台（`/invoice/admin.html`）提供一键打开开票网页能力，并根据每个独立纳税主体门店的注册/营业地址（`shop.address`），智能精准匹配国家税务总局全国统一规范电子税务局及各省市电子税局（含深圳、大连、青岛、宁波、厦门等计划单列市与各省直辖市共36个税区），实现财务人员从工作台一键直达当地税局开票平台，并配套开票资料一键复制，大幅提升白天人工开票与归档效率。

## Requirement Contract

### Acceptance criteria

- [x] AC-01: 后端提供 `TaxBureauResolver` 权威解析器，覆盖国家税务总局全国统一规范电子税务局总入口及全国 36 个省级/计划单列市电子税务局官方门户，优先匹配计划单列市，精准支持省份与重点地级市关键词匹配，无地址或未识别时优雅回退全国统一电子税务局总门户。
- [x] AC-02: 订单发票实体 `OrderInvoice` 扩展扩展字段 `shop_address`、`tax_bureau_name`、`tax_bureau_url`；分页查询接口 `/admin/order/invoice/page` 自动丰富门店地址与所属税局门户信息。
- [x] AC-03: 管理员登录与门店摘要接口（`toShopSummaries`）扩展返回 `address`、`taxBureauName`、`taxBureauUrl`，使财务端全局掌握各门店纳税归属地及对应税局。
- [x] AC-04: 财务工作台（`admin.html`）顶部导航栏提供「🏛️ 打开当地电子税局」一键直达入口；单店模式下直接新标签页打开对应税局，全部门店模式下弹出多门店税局导航抽屉与全国总平台入口。
- [x] AC-05: 财务工作台表格每行提供「🏛️ 税局开票」快捷操作，直达该笔发票销方门店对应的电子税局。
- [x] AC-06: 财务工作台「确认开票」弹窗内展示销方门店地址及匹配税局，提供「🌐 一键打开当地税局开票系统」与「📋 一键复制开票资料」按钮，方便财务在税局快速录入。
- [x] AC-07: 单元测试全覆盖解析规则，同步更新 `docs/openapi.yaml` 与 `docs/API.md`，执行 Maven 编译打包生成可运行 JAR 包。

## Acceptance Decision

ACCEPTED

## Consumer Handoffs

NONE（包含服务端接口与内置静态管理工作台页面一体化交付）。

## Integration / Release

INTEGRATED / NOT_RELEASED

## Related IDs

Workstream: INVOICE-TAX-BUREAU-PORTAL-NAV-V1
