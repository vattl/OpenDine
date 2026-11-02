# Scenario Matrix — WI-009

| ID | Scenario | Preconditions/Input | Expected Business Outcome | Invariants | Verification | Result |
|---|---|---|---|---|---|---|
| S01 | 既有订单成功加菜 | 固定历史 `order_time`，合法菜品 | 加菜成功且 `order_time` 原值不变 | ORDER-TIME-01 | controller unit | PASS |
| S02 | 金额与轮次更新 | 原金额100、轮次1，加菜68 | 金额168、轮次2 | ADD-DISH-01 | controller unit | PASS |
| S03 | 全部加菜消费者回归 | 小程序/收银/AI 共用 owner | 现有加菜测试无回归 | ORDER-TIME-01/ADD-DISH-01 | full Maven suite | PASS |

## Acceptance rule

Material scenarios must be PASS before acceptance.
