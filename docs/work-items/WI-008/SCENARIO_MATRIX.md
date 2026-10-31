# Scenario Matrix — WI-008

| ID | Scenario | Input/context | Expected outcome | Invariants | Verification | Result |
|---|---|---|---|---|---|---|
| S01 | 普通默认查询 | 无时间参数 | 当前店未结账 OR 最近3小时 | BILL-01/02 | controller unit | PASS |
| S02 | 普通用户越权 | 无 admin:super，传时间 | 403，零查询 | BILL-03 | controller unit | PASS |
| S03 | 超管自定义范围 | admin:super + 合法起止 | 当前店闭区间返回 | BILL-01/03 | controller unit | PASS |
| S04 | 参数不完整/混用 | 单端时间或 date+range | 400，零查询 | BILL-03 | controller unit | PASS |
| S05 | 非法范围 | 格式错/倒序/>31天 | 400，零查询 | BILL-03 | controller unit | PASS |
| S06 | 旧 date 兼容 | admin:super + date | 指定营业班次窗口 | BILL-01/03 | controller unit | PASS |
| S07 | 门店越权 | shopId 与解析门店不同 | 4003，零查询 | BILL-01 | existing regression | PASS |

Material scenarios must be PASS before acceptance.
