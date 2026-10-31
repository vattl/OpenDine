# Layer Impact Matrix — WI-019

| Surface | Impact | Action |
|---|---|---|
| Cashier API | Contract-compatible addition | 新增 `40231` 与可选诊断字段。 |
| Native API client | Code | 结构化区分明确拒绝与不确定失败。 |
| Native payment service | Code | 仅明确拒绝释放活动键。 |
| Database | No schema change | 复用现有状态字段。 |
| Cashier consumer | Handoff | `40231` 可提示纠正配置/参数；`50331` 仍必须先查单。 |
