# Structural Diff — WI-075

Diff ID: DIFF-UI-FINANCE-INVOICE-001
Parent Work: WI-075
Title: 财务人工开票工作台新增与顾客端状态回显联动
Status: PROPOSED
Created: 2026-10-29
Last Updated: 2026-10-29

Plan Status: APPROVED
Unclassified Legacy Regions: 0
Target State Match: YES
Legacy Remaining: NO
Unexpected Active Behavior: NO
Final Status: VERIFIED

## 1. Change Intent

为财务人员提供集中的开票管理工作台，支持白天上班集中查看顾客提交的发票信息并录入税控结果；同时在顾客端 H5 补充工作日人工开票时间说明及驳回修改入口。

## 2. Current State

```text
Admin: 缺少集中开票申请列表与可视化操作界面，无法直观筛选待开票记录
Customer H5: 仅提示已提交，缺少预计开票时效说明，未支持被驳回后的状态回显与重新修改
```

## 3. Target State

```text
Admin: 增加财务人工开票工作台页面（/invoice/admin.html），支持待开票/已开具/已驳回过滤、一键复制税号、弹窗确认开具与弹窗驳回
Customer H5: 增加“工作日集中开具”提示，增加被驳回警告卡片与重新修改提交按钮
```

## 4. Structural Diff

| ID | Element | Current | Target | Operation | Risk |
|---|---|---|---|---|---|
| D1 | Admin Workbench Page | 无财务开票管理工作台 | 新增完整响应式工作台 `/invoice/admin.html` | ADD | LOW |
| D2 | Admin Metrics Bar | 无统计卡片 | 新增待开票、今日已开、填写中、已驳回 4 项指标 | ADD | LOW |
| D3 | Admin Action Buttons | 无快捷操作 | 增加一键复制税号、开具弹窗与驳回弹窗 | ADD | LOW |
| D4 | Customer H5 Tip | 仅显示隐私提示 | 增加财务工作日集中处理开具的温馨提示 | MODIFY | LOW |
| D5 | Customer H5 Rejected State | 无驳回处理逻辑 | 增加驳回原因展示并允许重新激活表单提交 | ADD | LOW |

## 5. Preserve / Unchanged

- 顾客端发票抬头申请与结果回显核心样式和交互
- Token 防伪与防遍历机制
- 累计开票金额不超实付金额的核心状态机约束
