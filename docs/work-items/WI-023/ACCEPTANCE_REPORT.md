# Acceptance Report — WI-023

Decision: ACCEPTED

## Acceptance Evidence

- 授信账户生命周期、门店/商户范围、额度、账期和总部共享账户权限已实现。
- 订单可按服务端金额原子挂账；重复和并发请求不重复占额；挂账不生成支付台账。
- 部分/全额回款、幂等、超收阻断、现金钱箱联动、撤销和坏账均有不可变流水。
- 对账单、动态逾期状态、账龄分桶和门店级期末余额已实现。
- 日结明确区分销售和实际收款，应收水位进入预检及不可变快照。
- 既有支付退款不会处理挂账订单；旧 `/cashier/order/hang` 挂单语义保持不变。
- API 文档和权限 SQL 已同步，全量测试和可运行 JAR 构建通过。

## Scope Boundary

本决策仅接受服务端能力。外部收银/管理端消费者状态仍为 PENDING，必须按 `API_CONSUMER_HANDOFF.md` 实现后另行做端到端验收。

## Release State

ACCEPTED only；未部署、未做真实数据库迁移演练或生产验证，不是 INTEGRATED / RELEASED。
