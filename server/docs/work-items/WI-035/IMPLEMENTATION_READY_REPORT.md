# Implementation Ready Report — WI-035

IMPLEMENTATION_READY: YES

## Evidence

- Requirement Contract：并台后加菜金额漂移、目标行为和保留项明确。
- Baseline：PB-1 已读取，相关事实已用当前控制器、金额工具和并台服务验证。
- Impact Map：API、控制器、持久化和测试均已分类；Material UNKNOWN 为 0。
- Scenario Matrix：覆盖并台加菜、单单加菜、扣减字段、并台动作和首次下单时间。
- UI：NOT_APPLICABLE。
- Dirty worktree：WI-034 改动已识别；只做最小增量，不覆盖用户改动。

## Blockers

NONE
