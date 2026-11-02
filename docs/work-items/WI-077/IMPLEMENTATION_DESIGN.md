# Implementation Design — WI-077

## Root Fix / Owner

- 核心税务地址匹配组件：`com.lanf.util.TaxBureauResolver`（负责地址分析与国家电子税务局门户 URL 匹配映射）。
- 发票分页服务：`OrderInvoiceServiceImpl.adminPage`（装配门店地址与税局元数据）。
- 管理员登录服务：`AdminShopAccessServiceImpl.toShopSummaries`（装配门店地址与税局元数据）。
- 财务开票工作台：`src/main/resources/static/invoice/admin.html`（提供一键打开、行内直达、弹窗展示与资料一键复制）。

## 架构与设计原则

- **标准优先与计划单列市前置（权威映射）**：
  中国国家税务总局全国统一规范电子税务局采用统一域名规则 `https://etax.<region>.chinatax.gov.cn/`。
  匹配规则遵循严格的优先级分层：
  1. **计划单列市前置**：深圳、大连、青岛、宁波、厦门等计划单列市拥有独立的国家税务总局直属局，其层级独立于所属省，必须在省份匹配之前优先判别（如地址含「深圳市」或「深圳」，映射至 `etax.shenzhen.chinatax.gov.cn` 而非 `etax.guangdong.chinatax.gov.cn`）。
  2. **4个直辖市及27个省/自治区全覆盖**：覆盖北京、上海、天津、重庆及各省主要城市关键词（如广州/东莞/佛山等自动映射广东，杭州/温州/嘉兴等自动映射浙江）。
  3. **全国统一总平台安全回退**：若门店地址未配置或无法匹配任何省市关键字，安全回退至国家税务总局全国统一规范电子税务局总门户 `https://etax.chinatax.gov.cn/`。
  4. **双端对齐与即时计算**：后端提供 Java 权威类 `TaxBureauResolver`，前端 `admin.html` 同步提供等价的纯前端解析器，确保离线切换门店、新发票实时查询等场景均能毫秒级即时响应。

- **非侵入与向后兼容**：
  - `OrderInvoice` 中的 `shop_address`、`tax_bureau_name`、`tax_bureau_url` 均标注 `@TableField(exist = false)`，无需改动数据库物理表结构，对历史订单和数据绝对安全。
  - `/adminLogin` 与 `/admin/order/invoice/page` 返回的 JSON 结构仅平级新增非空字段，不改变现有字段类型与语义，平滑向后兼容现有客户端。

- **开票闭环与效率提升**：
  - **顶部一键直达**：顶部导航栏「🏛️ 打开当地电子税局」，单店模式一键开网页，全部门店模式提供多店清单弹窗。
  - **行内直达**：发票列表「🏛️ 税局开票」按钮直接携带当前发票对应门店的税局地址打开。
  - **弹窗集成开票资料一键复制**：开票审核弹窗展示所属税局直达按钮，并提供「📋 一键复制开票资料」功能，将发票抬头、税号、地址电话、开户行账号格式化复制到系统剪贴板，彻底免除财务人员频繁手动比对打字的痛苦。

## 详细设计与接口契约

### 1. `TaxBureauResolver` (Java)
```java
package com.lanf.util;

public class TaxBureauResolver {
    public static class TaxBureauInfo {
        private String region;
        private String name;
        private String url;
        // getters...
    }

    public static TaxBureauInfo resolve(String address) {
        if (address == null || address.trim().isEmpty()) {
            return new TaxBureauInfo("全国", "国家税务总局全国统一规范电子税务局", "https://etax.chinatax.gov.cn/");
        }
        // 1. 计划单列市
        if (address.contains("深圳")) {
            return new TaxBureauInfo("深圳", "国家税务总局深圳市电子税务局", "https://etax.shenzhen.chinatax.gov.cn/");
        }
        if (address.contains("大连")) {
            return new TaxBureauInfo("大连", "国家税务总局大连市电子税务局", "https://etax.dalian.chinatax.gov.cn/");
        }
        if (address.contains("青岛")) {
            return new TaxBureauInfo("青岛", "国家税务总局青岛市电子税务局", "https://etax.qingdao.chinatax.gov.cn/");
        }
        if (address.contains("宁波")) {
            return new TaxBureauInfo("宁波", "国家税务总局宁波市电子税务局", "https://etax.ningbo.chinatax.gov.cn/");
        }
        if (address.contains("厦门")) {
            return new TaxBureauInfo("厦门", "国家税务总局厦门市电子税务局", "https://etax.xiamen.chinatax.gov.cn/");
        }
        // 2. 直辖市与各省份匹配...
    }
}
```

### 2. 财务工作台交互设计 (`admin.html`)
- **顶部操作栏**：在门店选择器右侧新增按钮 `<button class="btn-top-tax" onclick="openCurrentShopTaxBureau()">🏛️ 打开当地电子税局</button>`。
- **开票弹窗**：在发票开具弹窗的销方信息下方展示门店地址与税局名称，附带 `<button class="btn-tax-direct" onclick="openDirectTaxBureau()">🌐 一键打开当地税局开票系统</button>` 与 `<button class="btn-copy-info" onclick="copyInvoiceBuyerInfo()">📋 一键复制开票资料</button>`。


## Verification Strategy

1. **单元测试与规则断言**：
   编写 `TaxBureauResolverTest`，覆盖：
   - 计划单列市（深圳、大连、青岛、宁波、厦门）优先命中对应独立税局；
   - 直辖市（北京、上海、天津、重庆）精准命中；
   - 各省主要地级市关键词（广州/东莞/佛山等映射广东，杭州/温州等映射浙江，苏州/南京等映射江苏）；
   - 空地址与非法/未识别地址安全回退到国家统一规范电子税务局总平台 `https://etax.chinatax.gov.cn/`。
2. **服务集成与数据装配断言**：
   - 验证 `OrderInvoiceServiceImpl.adminPage` 返回的记录中包含 `shop_address`、`tax_bureau_name`、`tax_bureau_url`；
   - 验证 `AdminShopAccessServiceImpl.toShopSummaries` 包含 `address`、`taxBureauName`、`taxBureauUrl`。
3. **前端页面功能与 DOM 验证**：
   - 验证顶部按钮、表格操作列按钮、开票弹窗直达按钮与一键复制功能。
4. **文档与构建验证**：
   - 同步更新 `docs/openapi.yaml` 与 `docs/API.md`；
   - 执行 `mvn clean package -DskipTests` 验证 JAR 包顺利生成。
