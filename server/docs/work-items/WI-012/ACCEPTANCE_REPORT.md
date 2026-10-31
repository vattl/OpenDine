# Acceptance Report — WI-012

Decision: ACCEPTED

## Result

桌台待结账金额已绑定当前桌全部未结订单的实际净应付金额。套餐 108 元加菇串 8 元时，即使历史或重复明细可被错误重算成 124 元，桌台仍按订单实际金额显示 116 元。

## Review

正确性、可读性、架构、安全和性能五轴审查通过，无未解决的 Critical/Required 发现。金额计算复用 `OrderNetRevenue` 统一口径，未引入额外查询或写入。

## State Distinction

本地统一基线为 `ACCEPTED`；尚未推送或部署，因此不是 `RELEASED`。
