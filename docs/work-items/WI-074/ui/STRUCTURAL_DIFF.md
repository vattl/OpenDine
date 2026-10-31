# Structural Diff — WI-074

Diff ID: DIFF-UI-INVOICE-001
Parent Work: WI-074
Title: 顾客端发票申请页合规化文案、防抖与脱敏改造
Status: PROPOSED
Created: 2026-10-28
Last Updated: 2026-10-28

Plan Status: APPROVED
Unclassified Legacy Regions: 0
Target State Match: YES
Legacy Remaining: NO
Unexpected Active Behavior: NO
Final Status: VERIFIED

## 1. Change Intent

清除虚假税务总局宣称，增加提交防抖以杜绝并发重复开票，并在回显区域对 PII 隐私数据实施掩码脱敏。

## 2. Current State

```text
Header: "老肥家餐饮 · 增值税电子发票" / "国家税务总局全国统一规范电子发票开具服务"
Form: 提交按钮无点击防抖逻辑
SubmittedCard: "财务系统正在自动处理开具增值税电子发票" / 明文渲染税号、手机、邮箱 / downloadBox 直接接收任意 URL
```

## 3. Target State

```text
Header: "老肥家餐饮 · 电子发票服务" / "门店发票抬头在线登记与开具申请"
PrivacyBanner: 增加隐私保护说明横幅
Form: 提交按钮具备禁用防抖保护与 loading 文案
SubmittedCard: "发票抬头登记已提交，商家财务将核对订单并处理开票凭证" / 掩码渲染税号、手机、邮箱 / downloadBox 校验协议
```

## 4. Structural Diff

| ID | Element | Current | Target | Operation | Risk |
|---|---|---|---|---|---|
| D1 | Header Subtitle | 国家税务总局全国统一规范电子发票开具服务 | 门店发票抬头在线登记与开具申请 | REPLACE | LOW |
| D2 | Privacy Notice | 无 | 增加隐私安全横幅与脱敏说明 | ADD | LOW |
| D3 | Submit Button | 无防抖，可连击 | 点击后立即 disabled 并显示提交处理中 | MODIFY | LOW |
| D4 | Submitted Subtitle | 财务系统正在自动处理开具增值税电子发票 | 发票抬头登记已提交，商家财务将核对订单并处理开票凭证 | REPLACE | LOW |
| D5 | PII Data Rendering | 明文完整展示税号/手机/邮箱 | 掩码脱敏展示 (9111****0001, 138****1234) | MODIFY | LOW |
| D6 | Download Box | 直接赋值未过滤的 URL | 校验协议前缀，杜绝非法协议注入 | MODIFY | LOW |

## 5. Preserve / Unchanged

- 订单概览卡片结构与可开票金额样式
- 抬头类型切换选项卡与基本输入框布局
- 已开具结果展示卡片基本结构与下载按钮样式
