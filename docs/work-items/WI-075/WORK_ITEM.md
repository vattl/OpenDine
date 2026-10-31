# Work Item — WI-075

## Title

财务后台人工开票工作台与申请流转支撑 (Manual Invoice Management Workbench and Application Workflow Support for Finance Admin)

## Type

FEATURE

## Goal

针对个人/普通商户无法直连税控 API 开具在线发票的现实业务场景，保留顾客前端（H5）扫码提交发票抬头页面，在管理后台为财务人员新增集中的“发票管理工作台”（含待办指标、开票列表、一键复制税号/抬头、弹窗录入发票号完成开具、驳回错误申请）；顾客端增加工作日人工处理时效提示及驳回修改入口，实现完整的线下人工开票业务闭环。

## Requirement Contract

- **R1: 财务开票申请分页列表接口**：新增 `GET /admin/order/invoice/list`，支持按状态（待开票 `TITLE_SUBMITTED` / 已开具 `SUCCESS` / 已驳回 `REJECTED` / 待填抬头 `PENDING_SCAN` / 全部）、订单号、抬头名称、手机号、日期范围分页查询，仅向已认证管理员提供未掩码数据以便复制开票。
- **R2: 财务确认开票录入接口优化**：优化 `POST /admin/order/invoice/issue`，支持录入发票号码（必填）、发票代码（选填）、发票下载链接（选填，支持外网链接或留空），校验状态并流转至 `SUCCESS`。
- **R3: 财务开票申请驳回接口**：新增 `POST /admin/order/invoice/reject`，支持填写驳回原因（`error_msg`），校验状态流转至 `REJECTED`。
- **R4: 财务人工开票工作台界面**：交付静态工作台页面 `src/main/resources/static/invoice/admin.html`，具备待开票指标统计、表格渲染、税号一键复制、弹窗确认开票与弹窗驳回。
- **R5: 顾客端 H5 申请页联动适配**：在 `invoice-apply.html` 及镜像中增加“工作日集中开具”提示，支持展示 `REJECTED` 驳回原因并允许顾客重新编辑修改抬头并提交。
- **R6: 规范与构建验证**：同步更新 `docs/openapi.yaml` 与 `docs/API.md`，执行自动化测试与 Maven 构建生成可运行 JAR。

### Acceptance criteria

- [x] AC-01: 财务管理员可通过 `GET /admin/order/invoice/list` 分页拉取开票申请，默认优先展示 `TITLE_SUBMITTED` 待开票记录，支持关键词与状态过滤。
- [x] AC-02: 财务管理员可通过 `POST /admin/order/invoice/issue` 录入税控发票号码并将状态更新为 `SUCCESS`；可通过 `POST /admin/order/invoice/reject` 驳回异常申请并将状态更新为 `REJECTED`。
- [x] AC-03: 财务工作台界面提供指标卡、申请列表、一键复制税号/抬头、确认开具弹窗与驳回弹窗，交互流畅且无跨站脚本/协议注入漏洞。
- [x] AC-04: 顾客端 H5 页面在订单被驳回时友好展示驳回理由，并支持解锁表单让顾客重新修改提交，提交后重新进入 `TITLE_SUBMITTED` 待办。
- [x] AC-05: 核心业务不变量严格保持：未支付订单禁止开票，已开票总额不可超过实付净额，普通商户不调用第三方服务商税控接口。
- [x] AC-06: 接口文档同步更新至 `docs/openapi.yaml` 与 `docs/API.md`，全量测试通过且 Maven 打包生成可运行 JAR。

## Acceptance Decision

ACCEPTED

## Consumer Handoffs

NONE（工作台前端与顾客端页面均在当前 Work Item 中同源交付）。

## Integration / Release

INTEGRATED / NOT_RELEASED

## Related IDs

Workstream: WECHATPAY-INVOICE-FINANCE-WORKBENCH

UI: UI-FINANCE-INVOICE-001

Capability: CASHIER-INVOICE

Commits: PENDING

## Business Invariants

- 只有已支付且具备可开票余额的订单可以申请发票并被财务开具。
- 订单累计有效开票金额不得超过实际支付金额扣除累计退款金额。
- 财务工作台接口必须要求具备后台管理员认证与权限（`order:view` / `order:operate`），杜绝越权访问。
- 顾客端公开接口必须受 Token 保护，禁止无 Token 或错误 Token 遍历发票信息。
- 驳回理由必须落库并对持 Token 的顾客端透明展示，支持修改重提。

## Impact Map Authority

- Impact map path: `docs/work-items/WI-075/IMPACT_MAP.md`
- Material UNKNOWN count: 0

## Scenario Matrix

- Scenario matrix path: `docs/work-items/WI-075/SCENARIO_MATRIX.md`
- Material NOT_VERIFIED count: 0

## Implementation Ready

- Status: YES
- Blockers: none

## Completion Level

COMPLETE
