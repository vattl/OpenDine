# Scenario Matrix — WI-067

| ID | Scenario | Preconditions/Input | Expected Business Outcome | Invariants | Verification | Result |
|---|---|---|---|---|---|---|
| S01 | 正常连续日结 | D-1 已结，当前 D | 默认展示并结算 D | INV-CLOSE-SEQ-001 | sequence resolver + targeted tests | PASS |
| S02 | 昨天漏结 | 最新已结 D-2，当前 D | 只返回 D-1，D 被锁定 | INV-CLOSE-SEQ-001 | `precheck_withoutDate_selectsEarliestGapInsteadOfCurrentBusinessDay` | PASS |
| S03 | 连漏三日 | 最新已结 D-4，当前 D | D-3→D-2→D-1→D 逐日推进 | INV-CLOSE-SEQ-001 | gap scan and pending count assertion | PASS |
| S04 | 零销售营业日 | next 日无订单/流水/钱箱 | 生成零值快照后推进 | INV-CLOSE-SEQ-001 | empty-window reclose test + existing settle persistence test | PASS |
| S05 | 显式跳日写入 | expected D-1，请求 D settle | 409，返回 expected/requested | INV-CLOSE-SEQ-001 | `settle_evenWithForce_rejectsLaterBusinessDayWhenEarlierDayIsPending` | PASS |
| S06 | 后续营业日已开钱箱 | 补结 D-1，D 有 OPEN 钱箱 | D 钱箱不阻断 D-1 | INV-CLOSE-SEQ-002 | business-day predicate assertion | PASS |
| S07 | 后续营业日持续交易 | D-1 预检后 D 新增交易 | D-1 token 不因窗口外变化失效 | INV-CLOSE-001/002 | bounded watermark query review + tests | PASS |
| S08 | 目标日财务变化 | D-1 预检后 D-1 新增/变更流水 | WATERMARK_CHANGED | INV-CLOSE-001 | existing payment/recharge watermark tests | PASS |
| S09 | 重开最新日 | 最新 CLOSED 为 D-1 | 重开后 next=D-1，可重结同一行 | INV-CLOSE-SEQ-001 | `settle_whenReopened_reusesSnapshotRowInsteadOfViolatingUniqueBusinessDay` | PASS |
| S10 | 重开历史日 | D 已结，请求重开 D-1 | 409，不产生序列空洞 | INV-CLOSE-SEQ-001 | `reopen_whenLaterClosedDayExists_rejectsSequenceHole` | PASS |
| S11 | 并发跨日请求 | 同门店同时 settle D-1 与 D | 只有 D-1 可成功 | INV-CLOSE-SEQ-001 | SERIALIZABLE boundary + pre-mutation sequence guard review | PASS |
| S12 | 无快照兼容启动 | 老门店无任何 snapshot | 从当前活动营业日建立序列 | compatibility | existing explicit-date precheck/settle tests | PASS |
| S13 | 历史 Z 报表 | 显式请求已结 D-30 | 原日期返回，不重定向 next | historical-read invariant | existing explicit timestamp Z-report test | PASS |
| S14 | 权限不足 | 无 daily:settle | API 403 | security | unchanged endpoint permission mapping + access regression | PASS |

## Acceptance rule

全部物质场景必须 PASS；任何 NOT_RUN/UNKNOWN/FAIL/BLOCKED 阻止 ACCEPT。
