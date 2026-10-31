# C004: 可视化小票模板设计器服务端支持 (Printing Template Designer)

- **Change ID**: `C004`
- **Diff ID**: `D004`
- **Status**: Completed
- **Created**: 2026-08-31
- **Target**: 支持前端拖拽/勾选式模板设计器、小票排版模板持久化存储与动态区块渲染引擎。

---

## 1. 背景与业务价值

为支持类似美团餐饮、客如云的前端可视化小票模板设计器，将原有的硬编码小票排版组装升级为标准区块化 DSL（Blocks Architecture）动态装配引擎，并提供模板的 CRUD、乐观锁版本控制、默认模板设置及与出票规则的无缝联动。

---

## 2. 核心改动

1. **数据库模型 (`t_printing_template`)**:
   - 支持门店隔离、系统内置通用模板（`shop_id = 0, is_system = 1`）与门店自定义模板。
   - 存储 `template_json`（Blocks DSL 结构）与 `version` 乐观锁。
2. **模板引擎升级 (`PrintTemplateEngine` & `PrintTemplateEngineImpl`)**:
   - 新增 `renderDynamicTicket` 与 `renderDynamicKitchenTickets`。
   - 支持解析 `PrintTemplateDsl`，遍历各区块（`HEADER`、`ORDER_INFO`、`DISH_ITEMS`、`PAYMENT_SUMMARY`、`MEMBER_INFO`、`DELIVERY_INFO`、`REMARK`、`CUSTOM_TEXT`、`DIVIDER`、`QRCODE`、`FOOTER`、`CUT_PAPER`）进行属性控制与变量填充。
3. **打印调度与规则联动 (`PrintDispatcherServiceImpl` & `PrintingService`)**:
   - 出票规则绑定的 `template_code` 若在 `t_printing_template` 存在对应配置，自动动态渲染出票。
   - 实时预览接口（`POST /admin/printing/preview`）支持直接传入 `templateJson` / `templateDsl` / `templateId` 实时渲染 AST。
4. **管理端 API 与权限**:
   - `GET /admin/printing/templates`
   - `GET /admin/printing/templates/{id}`
   - `POST /admin/printing/templates`
   - `PUT /admin/printing/templates/{id}`
   - `DELETE /admin/printing/templates/{id}`
   - `POST /admin/printing/templates/{id}/set-default`
   - 权限码：`printing:view` 与 `printing:manage`。

---

## 3. 验证情况

- 单元测试：`PrintTemplateEngineTest`、`PrintingTemplateServiceTest`、`AdminPrintingControllerTemplateTest` 均全量通过。
- 全量自动化测试：590+ 测试用例通过。
- OpenAPI 契约：同步更新 `docs/openapi.yaml` 与 `docs/API.md`。
