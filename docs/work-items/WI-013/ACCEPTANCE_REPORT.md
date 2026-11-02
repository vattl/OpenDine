# Acceptance Report — WI-013

Decision: ACCEPTED

## Result

已实现强制结账（`force: true`）功能，要求操作人必须具备 `admin:manage` 权限（或超管身份、店长密码授权、`approvalToken` 审批令牌）。
在遇到收款会话已确认但订单未结或收款意向冲突导致常规结账被锁死时，持有该权限可强制放行入账，并在结账完成后原子收敛订单名下所有意向为 COMPLETED，记录特权安全审计日志并返回 `forced: true`。

## Review

正确性、可读性、架构、安全和性能五轴审查通过。无未解决的 Critical/Required 发现。
OpenAPI 规范与 API 文档已同步更新，JAR 包已通过 Maven 完整构建并生成。

## State Distinction

本地统一基线为 `ACCEPTED`；尚未推送或部署，因此不是 `RELEASED`。
