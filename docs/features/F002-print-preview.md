# F002 — 统一打印小票预览接口 (Print Preview API)

## 状态
- **Feature ID**: F002
- **Status**: DONE
- **Created**: 2026-08-31
- **Completed**: 2026-08-31
- **Owner**: Development Team

---

## 1. 背景与目标
在收银端与运营管理后台中，管理人员及收银员在配置打印机模板或出票前，需要实时预览小票在 58mm / 80mm 热敏纸上的排版效果。
本特性提供统一的打印预览接口 `POST /admin/printing/preview` 与 `GET /admin/printing/preview`，组装真实或 Mock 订单数据，返回原生打印机指令文本、纯文本排版及前端易解析的结构化 AST 元素树。

---

## 2. 覆盖场景
1. `ORDER`：前台结账单 / 预结单 / 加菜单
2. `KITCHEN`：后厨制作分单（按分类分组拆单）
3. `SERVE`：KDS 划菜传菜单
4. `REFUND`：订单退款明细单
5. `SHIFT`：收银交接班报表小票
6. `LABEL`：商品杯贴 / 包装标签
7. `TEST`：打印机自检测试单

---

## 3. 验收标准
- [x] 接口支持按 `scenario`、`orderId` / `orderNo`、`deviceId`、`paperSize`（58mm/80mm）等参数灵活调用。
- [x] 当未传 `orderId` 时，自动采用规范的 Mock 示例数据渲染，确保后台随时可用。
- [x] 响应数据包含 `tickets` 列表（支持后厨分类多张小票），每张小票包含 `rawContent`、`plainText` 与结构化 `elements`（标题、分割线、表格、键值对、文本、切刀指令等）。
- [x] 注册 API 权限映射，并在 `docs/openapi.yaml` 与 `docs/API.md` 中同步接口文档。
- [x] 编写全场景单元测试，全量测试通过（593/593）。
