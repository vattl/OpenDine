# Adaptive UI Report — WI-074

UI ID: UI-INVOICE-APPLY-001
Parent Work Item: WI-074
Approved Prototype: `invoice-apply-prototype.html`

Adaptive Verification Status: VERIFIED
Failed Required Profiles: 0
Critical Operation Failures: 0
Component Consistency Violations: 0
Unintended Overflow / Clipping: 0
Input Modality Checks: PASS
Orientation / Safe Area Checks: PASS
Business Operation Checks: PASS
Required Device Profiles: 1
Verified Required Profiles: 1

## Required Profile Verification

| Profile ID | Production Evidence | Component Check | Operation Evidence | Overflow / Clipping | Input / Focus | Orientation / Safe Area | Status |
|---|---|---|---|---|---|---|---|
| PHONE | production-mobile.png | PASS | e2e_contract_evidence.json | 0 | PASS | PASS | VERIFIED |

## Operation Verification

| Operation ID | Profile ID | E2E / Manual Evidence | Result |
|---|---|---|---|
| OP-INVOICE-001 | PHONE | e2e_contract_evidence.json | PASS |
| OP-INVOICE-002 | PHONE | e2e_contract_evidence.json | PASS |

## Verification Details

- **PHONE (390x844)**: Verified single-column touch card layout. All component families (`BTN-PRIMARY`, `INPUT-TEXT`, `CARD-CONTAINER`, `TAG-BADGE`) respect min-height targets and responsive boundaries with 0 unintended overflow or clipping.
- **OP-INVOICE-001**: 页面扫码进入自动携带 token 查询订单可开票金额，成功展示订单卡片。
- **OP-INVOICE-002**: 表单填写、输入防抖锁定、安全提交并脱敏回显，端到端验证通过。
