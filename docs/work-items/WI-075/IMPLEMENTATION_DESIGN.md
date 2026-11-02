# Implementation Design — WI-075

## Root Fix / Owner

- 核心业务主管服务：`OrderInvoiceServiceImpl`（负责管理端申请列表分页查询、开票结果归档、驳回异常处理、顾客端状态回显与重新修改逻辑）。
- 管理端网关：`AdminOrderController`
  - 新增 `GET /admin/order/invoice/list`：支持按状态、订单号、抬头名称、手机号、日期分页查询。
  - 增强 `POST /admin/order/invoice/issue`：支持线下税控发票号码录入与成功状态归档，将文件下载链接设为非必填。
  - 新增 `POST /admin/order/invoice/reject`：支持录入驳回原因并将状态流转至 `REJECTED`。
- 顾客端网关：`PublicInvoiceController`
  - 当开票记录处于 `REJECTED` 状态时，返回驳回原因，并允许顾客持有效 Token 重新修改发票抬头并提交。
- 表现层：
  - 新增 `src/main/resources/static/invoice/admin.html`（财务开票管理工作台，提供指标看板、列表展示、税号一键复制、弹窗开票与弹窗驳回）。
  - 更新 `src/main/resources/static/invoice-apply.html` 及镜像文件（增加工作日集中开具说明与驳回状态修改重提交互）。

## 2. 状态机演进与流转设计

当前系统状态定义：
- `PENDING_SCAN`: 顾客已扫码/生成申请，尚未提交发票抬头。
- `TITLE_SUBMITTED`: 顾客已提交抬头信息，等待财务人员白天人工开票（待办核心状态）。
- `SUCCESS`: 财务已在外部税控系统开具完成，并在后台录入发票号码归档。
- `REJECTED`: 财务审核发现抬头/税号等有误，驳回申请并记录 `error_msg`。此时顾客端可看到原因并重新修改提交，提交后状态重新流转为 `TITLE_SUBMITTED`。
- `FAILED`: 历史异常状态（保留兼容）。

状态流转图：
```text
[已支付订单] 
       │ 扫码发起
       ▼
PENDING_SCAN ─── 顾客提交抬头 ───► TITLE_SUBMITTED (待财务开具)
                                          │
                  ┌───────────────────────┴───────────────────────┐
                  │ 财务确认已开票                                 │ 财务驳回申请
                  ▼                                               ▼
               SUCCESS                                         REJECTED
                                                                  │
                                                                  │ 顾客修改抬头重新提交
                                                                  ▼
                                                           TITLE_SUBMITTED
```

## 3. 接口设计

### 3.1 财务开票申请分页列表接口 (`GET /admin/order/invoice/list`)
- **权限**：需要管理员登录，具备 `order:view` 权限。
- **参数**：
  - `page`: 当前页码（默认 1）
  - `limit`: 每页条数（默认 10）
  - `status`: 状态过滤（可选：`TITLE_SUBMITTED`、`SUCCESS`、`REJECTED`、`PENDING_SCAN`；为空则查询全部）
  - `keyword`: 搜索关键词（支持订单号、抬头名称、手机号模糊搜索）
  - `startDate` / `endDate`: 申请日期范围
- **响应**：包含 `total`、`list`（明细包含：`applyId`, `orderNo`, `invoiceAmount`, `titleType`, `buyerTitle`, `buyerTaxNo`, `buyerPhone`, `buyerEmail`, `invoiceStatus`, `fapiaoNumber`, `fapiaoCode`, `fapiaoFileUrl`, `errorMsg`, `createdAt`, `updatedAt`）。
- **指标统计**：响应中一并返回 `metrics`（`countWaiting`, `countSuccess`, `countRejected`, `countPendingScan`），方便工作台顶部即时渲染统计数字。

### 3.2 财务开票驳回接口 (`POST /admin/order/invoice/reject`)
- **权限**：需要管理员登录，具备 `order:operate` 权限。
- **参数**：
  - `orderNo`: 订单编号（必填）
  - `rejectReason`: 驳回原因说明（必填，存入 `error_msg`）
- **处理逻辑**：
  - 校验订单存在性与当前开票状态，仅允许在 `TITLE_SUBMITTED` 状态下执行驳回；
  - 已完成开具（`SUCCESS`）的记录禁止直接驳回；
  - 记录操作人员 ID，更新 `invoice_status = 'REJECTED'`，`error_msg = rejectReason`，`updated_at = now()`。

### 3.3 财务确认开票录入接口优化 (`POST /admin/order/invoice/issue`)
- **参数**：`orderNo`（必填）、`fapiaoNumber`（必填）、`fapiaoCode`（选填）、`fapiaoFileUrl`（选填）。
- **处理逻辑**：
  - 允许在 `TITLE_SUBMITTED` 状态下确认开具；
  - 若 `fapiaoFileUrl` 为空，跳过 URL 校验并允许直接归档为 `SUCCESS`，适配线下纸质/本地税控机仅开出纸票或未导出 PDF 的小微商户场景。

## 4. 顾客端 H5 联动设计
- 在 `invoice-apply.html` 增加温馨提示：告知顾客发票将在工作日集中处理。
- 当 `invoiceStatus == 'REJECTED'` 时：
  - 显示驳回提示卡片，展示黄色感叹号及具体驳回原因（如：“税号位数错误，请核对执照后修改”）；
  - 激活“修改发票抬头”按钮，点击后平滑切回表单编辑态，并预填上次提交的内容，方便用户修改后再次调用 `/public/invoice/submit`。

## Verification Strategy

1. **接口单元测试**：针对 `GET /admin/order/invoice/list`、`POST /admin/order/invoice/issue`、`POST /admin/order/invoice/reject` 编写全面测试用例，覆盖状态筛选、模糊搜索、未开票驳回、已开票防驳回、非管理员鉴权拦截等。
2. **顾客端状态机流转测试**：测试 `PENDING_SCAN` -> `TITLE_SUBMITTED` -> `REJECTED` -> `TITLE_SUBMITTED` -> `SUCCESS` 完整闭环链路。
3. **前端原型与静态页面验证**：验证 `invoice/admin.html` 复制税号、搜索、弹窗交互；验证 `invoice-apply.html` 驳回展示与修改重提。
4. **编译与打包**：执行 `mvn test` 全量测试，执行 `mvn clean package -DskipTests` 生成最新可运行 JAR。
