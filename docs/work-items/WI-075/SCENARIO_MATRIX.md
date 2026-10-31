# Scenario Matrix — WI-075

## Scenarios

| Scenario ID | Category | Scenario / Context | Expected Outcome | Applicable Invariants | Verification Method | Result |
|---|---|---|---|---|---|---|
| SC-01 | 财务列表 | 财务调用 `GET /admin/order/invoice/list` 查询待开票列表 | 成功返回分页结果与待办统计指标，默认优先返回 `TITLE_SUBMITTED` 数据 | 财务管理端需支持按状态检索开票申请 | 单元测试 + Controller 测试 | PASS |
| SC-02 | 关键词过滤 | 财务在列表中按订单号、抬头名称或手机号关键词搜索 | 精确筛选出符合关键词的开票记录 | 提高财务开票核验效率 | 单元测试验证模糊查询条件 | PASS |
| SC-03 | 确认开具 | 财务对 `TITLE_SUBMITTED` 记录录入发票号码确认开具 | 状态更新为 `SUCCESS`，记录操作人与发票号 | 仅允许从未开具状态流转至成功 | 单元测试验证 issue 接口与数据落地 | PASS |
| SC-04 | 选填支持 | 财务开具发票时未填写文件 URL（仅填发票号码） | 成功归档为 `SUCCESS`，不强制要求外网 URL | 适配小微商户本地纸质税控机实际操作 | 单元测试验证空文件 URL 正常开票 | PASS |
| SC-05 | 申请驳回 | 财务对抬头税号有误的 `TITLE_SUBMITTED` 记录执行驳回 | 状态更新为 `REJECTED`，成功落库驳回理由 `error_msg` | 异常申请需支持退回修改 | 单元测试验证 reject 接口 | PASS |
| SC-06 | 状态机防错 | 财务尝试对已成功开具（`SUCCESS`）的记录执行驳回 | 返回 400 业务错误，禁止驳回已生效发票 | 已开具发票不可逆向驳回 | 单元测试测试防错拦截 | PASS |
| SC-07 | 顾客重提 | 顾客开票被驳回后重新访问 H5 页面并修改重新提交 | 页面回显驳回理由，修改后成功重新进入 `TITLE_SUBMITTED` | 允许用户修正错误信息重新排队 | 接口与状态机测试 | PASS |
| SC-08 | 权限安全 | 匿名非管理员请求财务开票列表或执行驳回操作 | 鉴权拦截返回 401 未登录或 403 无权限 | 严禁未授权用户访问财务开票中枢 | Controller 权限测试 | PASS |
| SC-09 | 工作台UI | 财务在工作台页面进行状态过滤、税号一键复制与弹窗交互 | 界面流畅响应，无脚本报错，一键复制税号入剪贴板 | 确保财务人员操作体验与效率 | 页面功能验证 | PASS |
