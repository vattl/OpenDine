# Scenario Matrix — WI-017

| ID | Scenario | Expected Outcome | Invariant | Verification | Result |
|---|---|---|---|---|---|
| S01 | 并发冲突后胜出请求生成二维码 | 后到请求复用同一二维码，`reused=true` | INV-PAY-002 | `concurrentCreateWaitsForWinnerAndReusesItsCodeUrl` | PASS |
| S02 | 胜出请求持续 CREATING | 有界等待后返回 `40931` | INV-PAY-003 | `concurrentCreateKeepsSafetyErrorWhenWinnerDoesNotFinishInTime` | PASS |
| S03 | 胜出请求进入 UNKNOWN | 不重新下单并返回安全提示 | INV-PAY-001/003 | `createDoesNotReplaceAnUnknownAttemptThatCouldStillBePayable` | PASS |
| S04 | 已有 ACTIVE 二维码 | 立即复用，不进入等待 | INV-PAY-002 | `createUsesServerAmountAndReusesLiveCodeUrl` | PASS |
| S05 | 正常首次创建 | 仅一次微信下单并返回二维码 | INV-PAY-002 | full regression | PASS |

