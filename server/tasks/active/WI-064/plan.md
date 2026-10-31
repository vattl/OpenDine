# Implementation Plan: WI-064 订单 expectedVersion

## Overview
以现有 `t_order.revision` 为云端权威，为加菜、退菜、改价和优惠建立事务内陈旧写保护及单调版本响应，同时保持旧客户端兼容和 KDS cloud-first 边界。

## Dependency Graph
```text
OrderRevisionService + 409 contract
  → addDishes path
  → refundDish/updatePrice/discount paths
  → KDS POS add single-bump alignment
  → API docs + consumer handoff
```

## Vertical Slices
1. 共享 revision 守卫：解析、冲突摘要、CAS +1。
2. 加菜端到端：直接/收银入口、成功 revision、KDS 单次递增。
3. 高风险金额动作：冲突校验早于审批，成功 revision。
4. 契约、回归、审查、打包和验收。

## Risks
- 事务返回错误而未回滚：冲突使用 `ApiException` 抛出，不以普通 R 吞掉 CAS 失败。
- KDS 双递增：POS 加菜在业务层递增后，KDS 仅更新局部投影版本。
- 旧客户端：expectedVersion 保持可选，并公开迁移状态。
- 脏工作区：只叠加 WI-064 文件/目标行，不回退 WI-062/WI-063。
