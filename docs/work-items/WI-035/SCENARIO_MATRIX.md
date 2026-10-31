# Scenario Matrix — WI-035

| ID | Scenario | Input / Context | Expected Outcome | Invariants | Verification | Result |
|---|---|---|---|---|---|---|
| S01 | 并台后加菜 | 同桌订单 A=100、B=40；A 加菜 20 | A=120，桌台=160 | INV-TABLE-035-01/02 | OrderControllerCompanionAddDishesTest | PASS |
| S02 | 单订单加菜 | A=100；加菜 68 | A=168，桌台=168 | INV-TABLE-035-01 | OrderControllerAddDishesComboTest | PASS |
| S03 | 优惠/退款/赠送金 | 同桌订单包含扣减字段 | 桌台按统一净应付汇总 | INV-ORDER-035-01 | OrderNetRevenueTest / regression | PASS |
| S04 | 并台动作本身 | 源/目标桌多笔未结订单 | 目标桌金额为完整总和 | INV-TABLE-035-01 | TableServiceTest / merge regression | PASS |
| S05 | 历史时间 | 加菜已有订单 | `order_time` 不变 | must preserve | OrderControllerCompanionAddDishesTest | PASS |
